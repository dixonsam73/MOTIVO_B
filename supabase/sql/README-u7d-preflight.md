# U7d — PRODUCTION PREFLIGHT. NOTHING DEPLOYED, NOTHING MUTATED. 2026-09-02

**NO DEPLOY, NO SCHEMA CHANGE, NO EDGE FUNCTION, NO TIMESTAMP MUTATION, NO
CLEANUP, NO SCHEDULER.** Everything below is either a repository change already
committed locally, or a procedure awaiting explicit authorisation.

**Production was READ, never written.** Every figure in §5 came from `select`
statements against the linked project. **No production UID appears in this file**,
per the standing rule; the subject is written `5ae3faab…`.

---

## 0. THE SECURITY QUESTION, ANSWERED FIRST — NOT A BLOCKER

**Question: with `verify_jwt = false`, what authenticates the caller?**

**Answer: the function's own constant-time comparison of the presented bearer
against `SERVICE_ROLE_KEY`. A header merely being present is NOT sufficient, and
that is measured rather than reviewed.**

`supabase/functions/membership_cleanup_v1/index.ts:179`:

```ts
const presented = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
if (!presented || !secretEquals(presented, SERVICE_ROLE)) {
  return json(401, { error: "service role credential required" });
}
```

`secretEquals` compares length first, then XOR-accumulates every byte — content
does not leak through timing; length may.

**Why `verify_jwt = true` would have been WORSE, not safer.** It authenticates
*any* valid Supabase JWT — including the anon key and every end-user token. Every
authenticated Apple user can obtain one. It would have put a stranger's token on
the doorstep of the most destructive endpoint in the system while *looking* like
platform-grade protection. **`verify_jwt = false` plus an explicit secret check is
strictly stronger here**, and it is the same authorisation story as
`appstore_reconcile_v1` — byte-identical expression, deliberately.

**MEASURED — `supabase/tests/u7/auth-probe.sh`, 11/11:**

| Presented | Result |
|---|---|
| no header | **401** |
| the **anon key** (a valid JWT) | **401** |
| junk bearer | **401** |
| service key **+1 char** | **401** |
| service key **−1 char** | **401** |
| a wrong secret, no scheme | **401** |
| **a genuine signed user JWT** — what `verify_jwt=true` would have admitted | **401** |
| the correct service role key | **200** — the check is not vacuously refusing |
| `GET` | **405** |
| **`SERVICE_ROLE_KEY` absent from the environment** | **fail-CLOSED — 500, no work done** |

**One laxness found and accepted, recorded rather than smoothed over.** The scheme
prefix is optional: `Authorization: <key>` without `Bearer ` is accepted, because
`.replace(/^Bearer\s+/i,"")` leaves a scheme-less header unchanged. **This is
parsing laxness, not an authorisation weakness** — the correct secret is still
required and still compared in constant time — and it is **byte-identical to the
deployed `appstore_reconcile_v1`**. Diverging would give the two service-role
functions different authorisation stories. **Not changed.**

**The destructive worker is therefore not publicly callable.** Anyone holding the
service role key can already do anything; nobody else can reach it.

---

## 1. WHAT DEPLOYS, AND IN WHAT ORDER

| # | Artefact | Effect on deploy |
|---|---|---|
| **1** | `supabase/migrations/20260902130000_u7b_cleanup_primitive.sql` | 2 columns, 2 functions, 2 grants, born-lapsed floor. **Contains no `delete`.** Inert |
| **2** | `supabase/migrations/20260902140000_u7c_preview_path.sql` | 3 functions (lease, eligibility/preview, authority gate), 1 grant, replaces the execute selector. **Contains no `delete`.** Inert |
| **3** | `supabase/functions/membership_cleanup_v1/` | The worker. **Does not run itself** |
| **4** | `supabase/config.toml` → `[functions.membership_cleanup_v1] verify_jwt = false` | **Required.** Without the block the CLI defaults to `true` and the service-role caller is rejected at the gateway, making the worker uninvokable |

**Order is load-bearing: 1 before 2** (U7c replaces a function U7b creates), and
**both before 3** (the worker calls all five).

**DEPLOYING ALL FOUR DESTROYS NOTHING.** The SQL has no path to a deletion — the
deletion lives in the Edge Function; an Edge Function requires an inbound POST
bearing the service role key; and `pg_cron` is absent (measured: 0). The gap
between deploy and effect is a deliberate human act with a credential.

**Every production SQL submission must carry a guard inside the transaction and
end in a `SELECT` returning a row**, so "no rows returned" is the symptom rather
than the disguise. `supabase db query` is **single-statement**.

---

## 2. EXPECTED B-23 TRANSITION AND STRUCTURAL DELTA

**Now: `GATE NOT MET — 23 problems`** (11 from U7b + 12 from U7c), every one a
U7b/U7c object. **After deploy and recapture: `GATE MET`**, with only the standing
`account_id_format` exception.

**Delta in CAPTURE ROWS** — the U7b/U7c units lesson applied, and this is the
number to score against:

| Surface | Predicted |
|---|---|
| `columns` | **+2** — `membership.cleanup_completed_at`, `membership.cleanup_claimed_at` |
| `functions` | **+5 new, 1 modified** — new: `cleanup_complete`, `due_for_cleanup`, `cleanup_lease`, `cleanup_eligible`, `cleanup_authorised`; modified: `membership_apply_state_v1` |
| `function_grants` | **+15** |
| `constraints` | **0** (the `account_id_format` pair is the standing exception) |
| `policies`, `rls_enabled`, `triggers`, `table_grants`, `column_grants`, `storage_buckets` | **IDENTICAL** |

**THE RULE THAT COST TWO MISSES, STATED WITHOUT THE EXCEPTION I INVENTED TWICE:
every new function contributes exactly 3 `function_grants` rows — one per
grantee — whether or not anything was granted to anybody.** 5 × 3 = 15.
`membership_cleanup_lease_v1` is granted to **nobody** and still contributes 3
rows, all `can_execute = false`.

**Privilege delta: 3 EXECUTE grants to `service_role`** (`cleanup_complete`,
`due_for_cleanup`, `cleanup_eligible`, `cleanup_authorised` — 4 in total across
both migrations). **`connected_member(uuid)` stays ungranted to every role;
B-33 is not weakened.** No client role gains anything; `service_role` still holds
zero table privilege on all six membership tables.

---

## 3. SECRETS, CONFIGURATION, AND READ-ONLY PREFLIGHT CHECKS

### Required at runtime

| Secret | Used for | Status |
|---|---|---|
| `SERVICE_ROLE_KEY` | **the authorisation boundary itself** (§0) and the DB client | **VERIFY** |
| `APPLE_IAP_KEY_ID`, `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_BUNDLE_ID`, `APPLE_IAP_P8_B64` | the fresh authoritative Apple read | **VERIFY** |
| `APPLE_API_BASE_URL_SANDBOX` / `_PRODUCTION` | local stubs only | **MUST BE UNSET** |

**Verify rather than assume.** Absent Apple credentials fail as
`credentials unavailable` on every identity, which reads like a worker defect
rather than a configuration one. Absent `SERVICE_ROLE_KEY` fails **closed** but
as an opaque 500 (AUTH-10).

### Read-only checks already run (2026-09-02)

| Check | Observed |
|---|---|
| `auth.users` / `posts` | **17 / 101** |
| `membership` | **1 row — Sandbox**, `apple_status` 2, otid `2000001228947923`, `binding_method` `purchase` |
| `entitlement_ended_at` | **2026-09-02 15:16:44+00** |
| **`pending_cleanup_at`** | **2026-11-01 15:16:44+00** ← the genuine original |
| `connected_member()` / `membership_state()` | **false** / **`sandbox_only`** |
| `enforcement_enabled` / `u6b_bound_at` | **true** / 2026-09-01 16:52:52 |
| bindings / conflicts | 1 / **0** |
| `pg_cron` | **0** |
| U7b/U7c columns present in production | **NO** — confirmed by `column "cleanup_completed_at" does not exist` |

**Global baseline for scoring:** comments **5**, follows **9**, shares **0**,
views **9**, `connected_attachments` **31**, directory **17**,
attachments objects **15**, avatar objects **3**, bindings **1**.

---

## 4. THE CALLER-AUTHENTICATION BOUNDARY — EXACT

```
internet -> Supabase gateway   : verify_jwt = false, NO authentication performed
         -> function body      : constant-time compare vs SERVICE_ROLE_KEY
                                 mismatch or absent -> 401, nothing executed
         -> mode gate          : "execute" must be named explicitly;
                                 anything else (including a malformed or
                                 replayed body) is treated as dry_run
         -> database           : service_role, which holds NO table privilege on
                                 any membership table and CANNOT execute
                                 connected_member(uuid)
```

**Three independent gates, and the third is the interesting one.** Even a caller
holding the service role key cannot read `public.membership` directly or evaluate
`connected_member(uuid)`. The worker reaches authority **only** through
`membership_cleanup_authorised_v1`, which returns one decision about one
identity. **There is no membership oracle at any layer.**

---

## 5. INDEPENDENT PREDICTION — DERIVED FROM PRODUCTION, NOT FROM THE WORKER

**This is the oracle. The dry run will be scored against it, never the reverse.**
Every figure below came from read-only `select`s, before any deploy, and none of
it came from the worker in any mode.

### Subject `5ae3faab…` — the exact effect of one cleanup

| Table / store | Before | Predicted after | Rule |
|---|---|---|---|
| `posts` (own) | **1** | **0** | REMOVE |
| storage `attachments` under the subject | **1** object | **0** | REMOVE — `users/…/<postID>/<attachmentID>.m4a`, a post attachment |
| `follows` (1 out, 1 in) | **2** | **0** | REMOVE, both directions |
| `post_comments` **on the subject's own post** | **3** | **0** | **CASCADE** via `post_comments_post_id_fkey` |
| `post_comments` **authored by the subject on ANOTHER member's post** | **1** | **1** | **RETAIN** |
| `account_directory` row | **1** | **1** | **RETAIN** — `display_name` "Steve Rename" intact |
| `account_directory.avatar_key` | **already NULL** | NULL | unchanged |
| avatar objects | **0** | 0 | nothing to remove |
| `auth.users` | **17** | **17** | **RETAIN** |
| `membership` / `membership_binding` | 1 / 1 | **1 / 1** | **RETAIN** — QA A24 behavioural |
| `post_shares` (either direction) | **0** | 0 | nothing to exercise |
| `post_comment_views` | **0** | 0 | nothing to exercise |
| `connected_attachments` sent / received | **0 / 0** | 0 / 0 | **nothing to exercise — see below** |

### Global totals

| | Before | After |
|---|---|---|
| `posts` | 101 | **100** |
| `post_comments` | 5 | **2** |
| `follows` | 9 | **7** |
| storage `attachments` objects | 15 | **14** |
| `auth.users`, directory, avatars, `connected_attachments`, bindings, conflicts | 17, 17, 3, 31, 1, 0 | **unchanged** |
| `membership.pending_cleanup_at` | due | **NULL**, `cleanup_completed_at` set |

### THIRD-PARTY DATA — STATE IT PLAINLY BEFORE AUTHORISING

**Cleaning this identity destroys 3 comments written by ONE other account.** They
are on the subject's own post, so they go with it under the cascade **ratified on
2026-09-02**. This is the ratified rule operating exactly as decided, and it is
the one effect of this run that reaches somebody else's content.

**Per the standing rule, whose account that is and whether it matters is the
account holder's to say, not mine to infer from the database.** The product
constraint records that all existing accounts are pre-release beta and need no
production-grade preservation; **this note exists so that is a decision rather
than a discovery.**

### WHAT THIS RUN WILL NOT EXERCISE — the honest coverage statement

**Production has no fixture for most of the retention matrix**, and U7d must not
be described as covering it:

| Not exercised | Why |
|---|---|
| **Reference-counted shared sent attachments (E-8/E-9)** — the most intricate rule in the unit | `connected_attachments` sent = **0** |
| Received attachment references (E-3) | received = **0** |
| Received post shares (E-4) | **0** |
| `post_comment_views` as viewer (E-5) | **0** |
| **Avatar removal and the C-33 object-before-pointer ordering (E-13)** | **0** avatar objects, `avatar_key` already NULL |
| **B-19 retention of comments addressed to the subject on OTHERS' posts (E-11)** | **0** such rows — all 3 addressed comments are on the subject's own post |
| F-2 / F-4 / F-5 storage-failure paths | no fault injection; unchanged from U7c |

**The local e2e suite remains the coverage for all of the above (75/75). U7d
proves the worker works against genuine Apple and real production state on a thin
slice.** Both statements are true and neither substitutes for the other.

---

## 6. STRUCTURAL CONFIRMATION — A FAILED OR UNVERIFIED OBJECT DELETION CANNOT REACH THE DATABASE EVIDENCE

**Enforced by control flow, not by convention.** All destructive steps sit in one
linear `try` block; `removeVerified` and `must` **throw**; a throw exits to the
`catch`, which records `decision: "abort"` and writes **no** completion marker.

```
await removeVerified(ATTACHMENTS, …)   <-- throws on remove error OR on any
                                           doomed object still present in the
                                           post-removal RE-LIST
   delete connected_attachments (sent)     <-- unreachable if the above threw
   delete connected_attachments (received)
   delete post_shares / post_comment_views / follows
   delete posts                            <-- the post-attachment evidence
   read account_directory.avatar_key
await removeVerified(AVATARS, …)       <-- throws the same way
   update account_directory set avatar_key = null   <-- UNREACHABLE if it threw
   membership_cleanup_complete_v1                   <-- last, only on success
```

**`avatar_key` is cleared strictly after the avatar objects are proven absent**
(C-33's ordering), so a failure leaves a real photo with a live pointer rather
than an orphan behind a null one. Because expiry **retains** the directory row,
that pointer stays usable by a later run — a better position than deletion has.

**"Proven absent" means RE-LISTED, not `error === null`.** Measured 2026-09-02:
`storage.remove` returns success for keys it did **not** delete, so a wrong path
would report success, delete nothing, and let the rows be deleted after it —
B-8's unreachable orphan arriving through a success message. Asserted at **G-4c**:
all three removal sites go through the verifier.

---

## 7. THE FIXTURE MUTATION — PROPOSED, NOT PERFORMED

**The genuine original value is `2026-11-01 15:16:44+00`, recorded in §3 above
and in this section, before anything changes it.**

**Single statement, because `supabase db query` is single-statement — and THE
GUARD IS THE `WHERE` CLAUSE**, so a guard failure returns **zero rows** rather
than a misleading success:

```sql
update public.membership m
   set pending_cleanup_at = now() - interval '1 minute'
 where m.environment = 'Sandbox'
   and m.original_transaction_id = '2000001228947923'
   and m.pending_cleanup_at = timestamptz '2026-11-01 15:16:44+00'
   and not public.connected_member(m.user_id)
   and (select count(*) from public.membership) = 1
returning m.environment, m.original_transaction_id, m.entitlement_ended_at,
          m.pending_cleanup_at as new_due,
          timestamptz '2026-11-01 15:16:44+00' as original_preserved;
```

Five guards: the right environment, the right subscription, **the value is still
the genuine original**, the identity is not Production-entitled, and there is
exactly one membership row. **Running it twice matches nothing the second time**,
because the original value is gone.

**REVERSIBLE while cleanup has not run:**

```sql
update public.membership m
   set pending_cleanup_at = timestamptz '2026-11-01 15:16:44+00'
 where m.environment = 'Sandbox'
   and m.original_transaction_id = '2000001228947923'
   and m.cleanup_completed_at is null
returning m.environment, m.pending_cleanup_at as restored;
```

The `cleanup_completed_at is null` guard is honest rather than decorative:
**after cleanup has run, restoring the timestamp restores nothing** — the content
is gone and the row would merely be re-scheduled.

**It is a FIXTURE, not evidence.** It tests worker execution. It tests nothing
about the 60-day arithmetic, which was already witnessed in production on genuine
Apple traffic (`entitlement_ended_at 2026-09-02 15:16:44` →
`pending_cleanup_at 2026-11-01 15:16:44`), and locally by N22/N23.

---

## 8. PROCEDURE

### P0 — capture (read-only)
Baseline every figure in §3 and §5; capture B-23; confirm the four `APPLE_IAP_*`
secrets and `SERVICE_ROLE_KEY` exist and both `APPLE_API_BASE_URL_*` are unset.

### P1–P2 — SQL
Apply migration 1, then migration 2, each guarded and ending in a `SELECT`.
Recapture the schema; score the §2 delta; **B-23 must return GATE MET.**

### P3 — the worker
Deploy `membership_cleanup_v1` with the `config.toml` block. **Verify the
deployed bundle**, not the tree — SHA against source, `verify_jwt: false`.
Confirm a wrong bearer gets **401** in production.

### P4 — DRY RUN
```
POST … {"mode":"dry_run"}
```
**Proves:** which identity is eligible; the exact object paths and per-table
counts that would be affected; that the worker reaches production data correctly.
**Scored against §5, which was written first.**

**Does NOT prove:** that cleanup will proceed. Dry run makes **no Apple request**
and evaluates **no authority** — by design (§3 of the U7c results). It also
acquires **no lease**, so it may be run repeatedly and cannot make the execution
after it report "nothing to do".

### ⛔ HARD STOP — HUMAN REVIEW, EXPLICIT AUTHORISATION REQUIRED
Nothing destructive has happened. Compare P4 against §5. **A disagreement stops
U7d and is a finding, not a reconciliation exercise.** Only then, and only on
explicit authorisation, apply §7's fixture mutation and proceed.

### P5 — EXECUTE, ONE IDENTITY
```
POST … {"mode":"execute","user_id":"<the subject>","limit":1}
```
Flow: claim → **fresh authoritative Apple read for every row of the identity,
verified against the pinned anchor and applied through the canonical writer** →
`membership_cleanup_authorised_v1` → destroy (objects re-listed before rows) →
complete.

**Abort/retry:** any Apple failure, any unverified object removal, any step error
→ `decision: "abort"`, **nothing further deleted, no completion marker**, lease
expires after one hour, identity retried by a later run. **There is no
escalation: no number of failures ever authorises deletion.**

**If Apple reports the subscription still entitled** — possible if the Sandbox
tester was resubscribed — the worker returns `refused`, reconciliation clears the
schedule, and **nothing is deleted. That is a PASS of the authority rule, not a
failure of U7d.**

### P6 — score, then ⛔ STOP
Score against §5 exactly. **No second identity, no scheduler.**

---

## 9. WHAT COUNTS AS U7d PASS

1. Both migrations applied; **§2 delta matches; B-23 GATE MET**.
2. Worker deployed; **wrong bearer → 401 in production**.
3. Dry run **agrees with §5**, acquires **no lease**, makes **no Apple call**.
4. Execute performs a **fresh Apple read for the identity** before any deletion.
5. **Every figure in §5 matches**, deletions and retentions alike — `auth.users`
   still **17**, `membership` and `membership_binding` still **1/1**, the
   directory row and `display_name` intact, the subject's comment on another
   member's post **still present**.
6. `cleanup_completed_at` set, `pending_cleanup_at` NULL, **conflicts still 0**.
7. **No unrelated row or object moved** — every other global count unchanged.
8. `pg_cron` still **0**.

**A `refused` outcome on genuine current Apple state is ALSO a pass** of items
1–4 and 8, with 5–7 recorded as not exercised. It must not be repaired forward
into a deletion.

---

## 10. ROLLBACK AND RECOVERY — WHAT GENUINELY EXISTS

**Honest, in both directions.**

| Layer | Recovery |
|---|---|
| **Edge Function** | Delete it, or redeploy the previous version. **Real and complete** |
| **`config.toml`** | Revert the block. Real |
| **SQL** | Regenerated full rollback baseline in the U7b/U7c style — drop the 5 functions, drop the 2 columns, restore `membership_apply_state_v1` to its U4 definition. **Real, and to be rehearsed locally with B-23 GATE MET on the rolled-back instance before P1** |
| **The fixture timestamp** | Restorable **only before** cleanup runs (§7). Real within that window |
| **Deleted rows and storage objects** | **NONE. There is no undo.** No backup of Domain 3 content is taken, and this document does not pretend otherwise |

**The last row is acceptable ONLY because the data is disposable pre-release beta
content, which the account holder has confirmed needs no production-grade
preservation** — and it includes **3 comments belonging to another beta account**
(§5). **That is the whole basis on which P5 is safe, and it is the sentence to
re-read before authorising.** The moment a production customer exists, this
procedure needs a different answer here.

**Stopping the whole thing is always available and needs no rollback:** deploy
and do not invoke. Nothing runs by itself — `pg_cron` is 0 and the worker has no
scheduler.

---

## 11. AWAITING EXPLICIT AUTHORISATION

Nothing in §8 has been performed. **Not deployed, timestamp not altered, no
cleanup executed, no scheduler, C-58 not started.**
