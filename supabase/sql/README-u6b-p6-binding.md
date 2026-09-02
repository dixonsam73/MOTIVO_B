# P6 — BINDING ENFORCEMENT. PREDICTIONS, committed 2026-09-01 BEFORE THE FLIP

**NOTHING BELOW IS A RESULT.** `enforcement_enabled` is `false` in production as
this is committed. Every number is a claim that can be wrong.

**Scope discipline: this is one row and a QA fixture, not a migration
programme.** No per-user override, no Production fake entitlement, no allowlist,
no Sandbox entitlement exception. **Genuine Production GRANT-path verification
remains deferred to the first real App Store subscription after public release**
— settled, and nothing here discharges it.

---

## 1. STATE AT THE MOMENT OF WRITING — read from production

| | |
|---|---|
| `enforcement_enabled` / `u6b_bound_at` | **false / null** |
| Device A membership | 1 row, **Sandbox**, `renewal_date` past → **not entitled** |
| Device A `membership_state()` / `connected_member()` | **`sandbox_only` / false** |
| Device B | **no membership row** → `unknown` / false |
| `posts` total | **101** — Device A owns **1**, Device B owns **6** |
| rows with a non-null `entitled_until` | **0** — no Production membership row has ever existed |
| drift | **0** |

## 2. THE QA FIXTURE — a genuine Sandbox resubscription, and nothing else

**Device A is restored by an ordinary Apple Sandbox resubscription on tester 2.**
That is a real purchase through Apple, not fabricated state: it produces a real
`SUBSCRIBED`/`RESUBSCRIBE` notification and a real refreshed `membership` row.

**It gives the one fixture shape we cannot otherwise get: client-Connected and
server-`sandbox_only` simultaneously.** The client resolves `AppMode` from local
StoreKit, so Device A returns to the full Connected UI, while D4 keeps
`connected_member()` false because the row is Sandbox. **That divergence is
exactly what P6 must be tested against**, and it needs no exception of any kind to
produce.

**Predicted afterwards:** `membership_state()` stays **`sandbox_only`**,
`connected_member()` stays **false**, `entitled_until` stays **NULL** everywhere
(the derivation is Production-only), and **drift stays 0**.

## 3. PRE-FLIP PREDICTIONS

| # | Prediction |
|---|---|
| **F-1** | The statement updates **exactly one row** |
| **F-2** | `enforcement_enabled` **false → true**, `u6b_bound_at` **null → set** |
| **F-3** | No membership table moves: `membership` 1, `membership_binding` 1, `membership_cutover` 16, conflicts 0 |
| **F-4** | Policy and function definitions are **untouched** — this writes one boolean and one timestamp |
| **F-5** | Drift stays **0** |

## 4. POST-FLIP PREDICTIONS — deny path

**Both devices are unentitled under the authoritative Production decision.** The
client still shows Connected on Device A, because `AppMode` is local. **That is
the predicted UX and not a defect.**

| # | Prediction |
|---|---|
| **D-1** | **The feed is not empty — it shows ONLY the viewer's own posts.** The owner branch of `posts_select_public_or_owner` stays open. Device A sees **1**, Device B sees **6** |
| **D-2** | Opening another member's post: **not found** |
| **D-3** | Publishing a session: **refused** |
| **D-4** | Commenting: **refused**, `not permitted` |
| **D-5** | Another member's attachment bytes: **refused** |
| **D-6** | **Own** attachment bytes: **still readable** — `attachments_user_select_auth` is untouched (D-U6-4) |
| **D-7** | Directory search: **returns nothing** |
| **D-8** | **Own profile loads and edits** — D-U6-3 |
| **D-9** | **Account deletion stays reachable** — D-U6-2 and C-35. **Confirm reachable; DO NOT run it** |
| **D-10** | Telemetry gains rows with **`enforced = true`** and **`would_deny = true`**, sitting beside the historical `enforced = false` rows rather than merging |

**Subject-side is unobservable in this run and that is expected, not a gap.**
Every `entitled_until` is NULL because no Production membership row has ever
existed, so no viewer is entitled and nothing reaches the subject branch. The
subject rule is covered by U6b acceptance locally (`U6b-F1`/`F2`) and by the
release gate.

## 5. STOP CONDITIONS — roll back immediately

- **Any carve-out failing:** own material unreadable, own profile uneditable, or
  **account deletion unreachable**. These are D-U6-2/3/4 and C-35, and they are
  the only failures that are *dangerous* rather than merely wrong.
- Anything failing on a path predicted to **succeed**.
- An **error** where an empty or filtered result was predicted — a denied `SELECT`
  returns zero rows, never an exception.
- Any row moving in `membership`, `membership_binding`, `membership_cutover` or
  `membership_binding_conflict`.
- Drift ≠ 0.

**NOT a stop:** unentitled devices being denied, or a feed showing only your own
posts. That is the unit working.

## 6. ROLLBACK

```sql
update public.membership_control set enforcement_enabled = false, updated_at = now() where id;
```

**One row, effective on the next predicate evaluation** — the flag is read live
inside the gate on every call, so there is no partially-applied window and no
cache.

**`u6b_bound_at` is deliberately NOT cleared.** It records that binding happened,
which stays true after a rollback. The consequence is intended: **P6's guard
requires `u6b_bound_at IS NULL`, so it cannot be re-run silently after a
rollback** — a second bind must be a conscious act, not a repeat.

## 7. WHAT P6 DOES NOT ESTABLISH

**Nothing about the GRANT path.** No Production membership row exists, so no
identity is entitled and the allow branch is never exercised in production. That
is the release gate, unchanged: **before a second paying subscriber exists, the
first genuine App Store subscription is verified end to end.** P6 proves the deny
path and the carve-outs; it cannot and does not prove the grant path.

---

# P6 RESULT — BOUND, THEN ROLLED BACK. DENY-PATH QA **INCOMPLETE**. 2026-09-01

## What happened, as facts

| | |
|---|---|
| **Bound** | `enforcement_enabled = true`, `u6b_bound_at` = **2026-09-01 16:52:52.452956+00** |
| **Rolled back** | `enforcement_enabled = false` at **2026-09-01 16:58:29.176354+00** |
| **`u6b_bound_at`** | **retained, deliberately** — it records that binding happened, which stays true |
| **Now** | `enforcement_enabled` **FALSE**. **U6b-1 remains deployed and INERT** |

## The structural bind SUCCEEDED and every prediction held

All ten guards passed and the returned row matched exactly: `enforcement_enabled t`,
`bound t`, membership 1, binding 1, cutover 16, conflicts 0,
`posts_visible_to_others` 0.

Verified independently afterwards: `enforcement_active()` **true**, Device A
`sandbox_only` / false, **drift 0**, and the policy fingerprint **unchanged at the
U6b-1 value** — proof that P6 wrote one boolean and one timestamp and nothing else.

**F-1 to F-5 all hold.**

## THE BEHAVIOURAL DENY-PATH QA IS INCOMPLETE, AND IS NOT RECORDED AS ANYTHING ELSE

**A Supabase service incident was in progress during the QA window.** Device
symptoms observed under it — an empty feed with its empty-state message *absent*,
and author attribution rendering as `User` instead of the stored display name —
are the shape of **failed** requests rather than denied ones: a denial returns
zero rows and would render the empty state.

**So the observations are contaminated and cannot be scored.** Of D-1 to D-10,
**none is recorded as passed or failed.**

**What the telemetry shows is the whole behavioural evidence there is:**

```
16:54:13  sandbox_only (Device A)  rpc.has_unread_private_comments  deny=true  n=3
16:56:36  unknown      (Device B)  rpc.has_unread_private_comments  deny=true  n=6
16:56:39  unknown      (Device B)  storage.attachments_recipient    deny=true  n=1
```

**Three rows, ten observations, two surfaces.** `posts.select` **never fired**, so
D-1 — the prediction that the feed shows only the viewer's own posts — went
**untested rather than falsified**, and publish, comment, own-attachment,
own-profile and account-deletion-reachable were never exercised at all.

**THE DENY PATH IS NOT VERIFIED IN PRODUCTION.** The two surfaces that were
exercised both denied gracefully, which is consistent with the design and is not
a substitute for the gate.

## What must happen before P6 is attempted again

1. The Supabase incident is **resolved**.
2. Both devices relaunched with enforcement **off**, confirming normal behaviour —
   a clean baseline before re-binding.
3. **A re-bind is a conscious act, not a repeat.** `u6b_bound_at` is set, so
   `2026-09-01-u6b-2-bind-production.sql` will **refuse** on its first
   precondition. That is by design.
4. Device A's `sandbox_only` fixture re-established if it has lapsed again — its
   `renewal_date` was 17:21:02.

**C-55 is open and unrelated to enforcement**; it does not block P6, but Device A
cannot serve as a QA fixture while it is unobservable.

## CONTEMPORANEOUS EXTERNAL EVIDENCE — Supabase incident, 401 JWT rejections

**Reported by the account holder from Supabase's own status page during the same
window.** Recorded because it materially strengthens the contamination finding
above, and because "an incident was in progress" is a much weaker statement than
what the incident actually was.

| | |
|---|---|
| Nature | **HTTP 401 errors due to JWT rejections** |
| Course | Persisted with **PostgREST 14.17**; rolled back to **14.5** owing to unintended performance side effects, investigation continuing |
| Earlier updates | **Intermittent** 401s; waiting or refreshing can succeed |
| Vendor note | Some customers resolved persistent symptoms by restarting the project |

### WHY THIS FITS, AND WHY IT IS NOT PROOF

**A 401 is an AUTHENTICATION failure, not an authorisation one.** That distinction
is the whole reason this is explanatory: U6b's gate denies *authorisation* — an
RLS denial returns **zero rows**, and a denied RPC returns `false` or `not
permitted`. **Neither produces a 401, and neither produces a failed request.**

The symptoms observed were the shape of **failure**, not denial:

- feed **empty with its empty-state message ABSENT** — a returned-zero-rows result
  would have rendered the empty state;
- author attribution falling back to `User` — the directory lookup failed rather
  than returning a row.

**And it explains the asymmetry that was otherwise puzzling.** Direct Postgres
access stayed healthy throughout because `supabase db query` reaches the database
through the Management API and **never presents the app's JWT**; the app reaches
it through PostgREST, which is exactly where the rejections were occurring. **A
healthy database was never evidence of a healthy API layer**, and that was stated
before this report arrived rather than after.

**STATED AS SUPPORT, NOT AS PROOF.** No request-level capture from either device
was taken during the window, so no observed 401 is on record here — the link is
between a vendor-reported fault and symptoms of the matching shape, at the
matching time, on the matching layer. **That is strong corroboration and it is not
a measurement.** D-1 to D-10 remain **unscored**, and the deny path remains
**unverified in production**; better external evidence for *why* the window was
contaminated does not convert a contaminated window into a result.

### One thing left explicitly open rather than folded in

**Device A's Connected → Solo transition during the window is NOT explained here,
and no mechanism is claimed.** Intermittent 401s are a *plausible* contributor —
`AuthManager` has a `network-auth-challenge` path — but **nothing establishes that
it fired**, and it is not recorded as though it had. It is separate again from
C-55, which is a purely local navigation path that **no API-layer fault can
explain**.

### Standing instructions while the incident is unresolved

- **Do NOT restart the Supabase project**, notwithstanding the vendor's note that
  it has resolved symptoms for others. Restarting would destroy the conditions
  under which these observations were taken.
- **Do NOT restart P6.** `enforcement_enabled` stays **FALSE**.
- **Do NOT reinstall, erase or reset Device A.** Its local state is C-55's only
  evidence.


---

## AGREED ADJUSTMENT TO P6 BEFORE IT IS RE-ATTEMPTED — 2026-09-01

Three items, and no broader retest.

1. **C-55 IS DECLARED IN ADVANCE AND EXCLUDED FROM SCORING.** Device A's
   journal-row → `SessionDetailView` navigation is **known-broken independently of
   enforcement** — it reproduces with `enforcement_enabled` FALSE and with the
   device in Solo making no backend request at all. **It must not be scored as an
   enforcement symptom.** It nearly contaminated the record once already, in that
   exact direction.
2. **ONE BASELINE CHECK FIRST.** Once Device A is genuinely Connected again *and*
   Supabase is healthy, verify **one feed → remote post navigation with
   enforcement OFF** before binding. The feed uses a different destination
   (`pushRemotePostID`) from the journal row (`pushSessionID`), and **Device A's
   feed path has never been exercised since C-55 appeared** — so it is untested,
   not known-good. One tap, and it is the difference between a scored gate and
   another contaminated window.
3. **Device B carries the own-attachment-readable carve-out.** D-U6-4 is
   `owner_user_id = auth.uid()`, identical whatever clause is decided, so Device
   B's `unknown` identity exercises it as well as Device A's `sandbox_only` —
   and it does not depend on the path C-55 affects.

**Everything else in P6 is unchanged. Production enforcement stays FALSE and P6
remains stopped until the Supabase incident is healthy.**


---

## FEED QUERY-SHAPE DISCRIMINATION — LOCAL, REAL HTTP, 2026-09-02

**Question:** `posts.select` telemetry was absent in production on two occasions
where a feed demonstrably rendered other members' posts. Does the gate actually
evaluate and decide on the shape the client really sends, or was the feed simply
never gated?

**Method.** The actual client query — `GET /rest/v1/posts?select=*&order=created_at.desc`,
**no filter, RLS-only** (`BackendShim.swift`, the `"all"` scope) — issued against
the local stack over real HTTP with a real JWT. Unentitled viewer, and an
**entitled** author so the subject check passes and **only the viewer gate is
under test**.

| | total | own | **other's** |
|---|---|---|---|
| enforcement **OFF** | 6 | 2 | **4** |
| enforcement **ON** | 2 | 2 | **0** |

**RESULT: the viewer gate is genuinely evaluated and decides correctly on the
production client query shape.** With enforcement on, the unentitled viewer
received **none** of the author's posts. The author's `owner_entitled_until` was
in the future for all four, so the subject check passed and **the denial can only
have come from the viewer gate**.

**The own-post carve-out remained intact** — 2 own posts returned under both the
`all` and `mine` shapes with enforcement on.

**`posts.select` telemetry was absent in BOTH runs**, including the OFF run where
the viewer legitimately received the author's posts. So **telemetry silence on
this GET/read path is a BLIND SPOT and is not evidence of missing enforcement** —
the same class as B-34's storage finding.

*(An unverified possible mechanism, recorded as a pointer only and deliberately
not pursued: PostgREST may run `GET` requests in a read-only transaction, in which
the observer's `INSERT` cannot commit and is swallowed by its fail-open handler.
**This is not established** and nothing here depends on it.)*

### CONSEQUENCE FOR P6 SCORING — binding change

**GET/read-path denials are judged by ACCESS BEHAVIOUR, never by requiring
telemetry.** A feed or post read that returns zero of another member's rows is a
pass whether or not any observation is recorded.

**D-10 is amended accordingly:** telemetry gaining `enforced = true` rows remains
expected for **writes and RPCs**, and is **NOT** a pass condition for reads.
Absence of a read-path observation must not be scored as a failure, and — equally
— must not be scored as evidence of safety.


---

## DEVICE A ACCEPTANCE SEQUENCE — corrected wording, 2026-09-02

Blocked until the C-57 fix is installed on Device A. Four steps, one of which is
the actual assertion.

1. **Install the fixed Release build. With `enforcement_enabled` still FALSE**,
   sign in (SIWA) and confirm the client reaches **Connected**. Baseline: it
   recovers.
2. **Re-bind** (`2026-09-01-u6b-2b-rebind-production.sql`), relaunch Device A, and
   confirm **it STAYS Connected** with a filtered or empty feed rather than
   dropping to Solo. **That single observation is the test.**
3. Confirm **account deletion remains reachable** while denied — C-35.
4. **Return `enforcement_enabled` to FALSE**, explicitly:

```sql
update public.membership_control set enforcement_enabled = false, updated_at = now() where id;
```

**"Kill switch" in step 4 means exactly that statement** — setting the flag back
to FALSE. It is not a figure of speech for "stop testing", and P6 is not left
bound at the end of this sequence.


---

# P6 SECOND RUN — 2026-09-02. C-57 PROVEN. DENY PATH **PARTIALLY** SCORED

**Re-bound 10:42:04, kill switch 10:47:27.** `enforcement_enabled` is **FALSE**;
`u6b_bound_at` still records the first bind at 2026-09-01 16:52:52.

## The primary purpose of this run — C-57 — PASSES

**Same device, same denials, opposite outcome:**

| | denials | result |
|---|---|---|
| before the fix (10:34) | 32 x 403 | `signOut()`, credentials deleted, **irreversible Solo** |
| **after the fix (10:42)** | **17 x deny=true** | **stayed CONNECTED**, session alive 10:42:30, auth.users 17, binding untouched |

**That is the assertion this run existed to make, and it is measured rather than
inferred.**

## Scored PASSES

- **F-1..F-5** — the flip itself: exactly one row, `u6b_bound_at` preserved, no
  membership table moved, drift 0.
- **Denial is live** — `rpc.has_unread_private_comments` denied **17 times**,
  `sandbox_only`, `would_deny=true`.
- **D-1's DENY half** — the feed was empty **WITH its empty-state message**, so
  the query **succeeded and returned zero rows**. That is a denial, not a
  failure, and it is the discriminator that separated this from the PostgREST
  incident.
- **D-6** own attachment readable · **D-8** own profile loads and edits ·
  **D-9 account deletion reachable** — the carve-outs, and the only class whose
  failure would have been dangerous.

## NOT EXERCISED — named rather than absorbed

**D-2, D-3, D-4, D-5, D-7 were not run, and the whole Device B `unknown` half was
not run.** With the feed empty there was nothing to open, and no publish or
comment attempt was made. **They are not scored as passes and must not be read as
any.**

**D-1's UI prediction was WRONG and that is my error, not a defect.** I predicted
the feed would show the viewer's own posts. It showed none. The local real-HTTP
discrimination proved the API *does* return own posts under enforcement, so the
`all` feed scope evidently excludes them in the UI. The API half of D-1 is
confirmed; the UI half was a bad prediction.

## AN UNRECORDED PRODUCT-VISIBLE CONSEQUENCE — needs a decision

Under enforcement, Device A's follower rendered as **`User . 1492f0`** rather than
a display name.

**This is two settled decisions interacting, not a defect.** `follows` SELECT is
deliberately **ungated** (D-U6-2 — you cannot delete what you cannot see), while
`get_account_directory_by_user_ids` gates on the **viewer**. So an unentitled
member keeps a usable follow list but **cannot see who is in it**.

**G10 is intact** — it forbids gating on the *subject*, and retained attribution
still resolves for entitled viewers. What is gated here is the viewer.

**Whether that UX is acceptable is a product decision nobody has taken.** A
secondary note: the fallback renders a UUID prefix, which is pre-existing
behaviour and not introduced by U6b.

## P6 STATUS: NOT COMPLETE

The blocking defect is resolved and the safety-critical half passes. **The
write-denial half and the second identity class remain unexercised**, so P6 is
**not** scored as a pass.


---

## FINAL P6 MATRIX — five actions, both identity classes. NOT YET RUN

| # | Device | Action | Closes |
|---|---|---|---|
| 1 | **A** (`sandbox_only`) | attempt to **publish** a session | **D-3** |
| 2 | **A** | **directory search** for a known member | **D-7** |
| 3 | **B — Études Dev** (`unknown`) | open feed → **filtered/empty WITH its empty-state message** | **D-1**, second class |
| 4 | **B** | attempt to open a **previously visible** post | **D-2** |
| 5 | **B** | **account deletion reachable** — confirm, DO NOT run | **C-35 for `unknown`** |

**Step 5 is kept despite the general instruction not to repeat carve-outs**, because
C-35 is the only dangerous class and `unknown` decides by a different clause than
`sandbox_only`. One tap.

### D-4 and D-5 — recorded accurately, and NOT as production-device passes

**D-4 (comment refused) and D-5 (another member's attachment refused) are covered
by the local enforcement suite** — `U6b-G4` and the structural RPC-gate
assertions — **and were NOT independently exercised on the production device,
because D-2 makes the underlying post and its content unreachable through the
UI.** Once another member's post cannot be opened there is no route to comment on
it or fetch its attachment.

**They must not be recorded as production-device passes.** The deny path is
layered, and the outer layer hiding the inner one is the enforcement working — but
it is not the same thing as having tested the inner one on device.

---

# P6 FINAL RUN — 2026-09-02. PRODUCTION DENY PATH **SUBSTANTIALLY PASSED**

**This is deliberately NOT recorded as "P6 complete" or "P6 passed".** The
correct statement is: **production deny-path verification substantially passed,
with D-3 behavioural enforcement coverage OUTSTANDING.** Four of the five actions
are production passes; one is structural only, and saying otherwise would convert
an unexercised path into a claimed one.

Bound `2026-09-02 11:17:55.79947+00` by the guarded re-bind, which returned
`u6b_bound_at` **preserved** at the original `2026-09-01 16:52:52.452956+00` —
binding happened once, and the record of it is not rewritten by a repeat.
Kill switch executed `2026-09-02 11:28:07.133938+00`. Enforcement was live for
**about ten minutes**.

## The scored matrix — each distinction preserved as stated

| | Class | Action | Result |
|---|---|---|---|
| **D-1** | `unknown` | feed filtered | **PRODUCTION PASS** |
| **D-2** | `unknown` | direct open of non-owner post | **Non-owner content filtered from the production feed; direct-open behaviour NOT independently exercised** |
| **D-3** | `sandbox_only` | publish refused | **Structurally enforced, and shadow-path reachability previously demonstrated — but NO behavioural enforcement denial has yet been observed, locally OR in production** |
| **D-7** | `sandbox_only` | directory search | **PRODUCTION PASS** — nothing found |
| **Carve-outs** | `unknown` | account deletion reachable | **PRODUCTION PASS** |

## C-57 — behaviourally VERIFIED under live enforcement

**Across both `sandbox_only` and `unknown`, with no credential destruction and no
sign-out across the observed denials.** `auth.users` stayed at **17** throughout,
and both devices remained Connected while being denied. This was the primary
purpose of the run: it is the exact failure that forced the 2026-09-01 rollback,
and it is now measured rather than argued.

Telemetry captured both classes — `sandbox_only` on
`rpc.has_unread_private_comments` (11 observations) and `unknown` on the same
surface (7) plus **`storage.attachments_recipient`** (1), a storage-path denial
that DID record, which is new relative to B-34's blind spot.

## D-1's result CORRECTS an earlier inference, which is withdrawn

Device B saw **its own posts and nobody else's**. That is not an anomaly and not
an artefact of two installs on one device: `posts_select_public_or_owner` carries
an **ungated owner branch**, which is carve-out **D-U6-4** — a member must always
reach their own content, or account deletion and export break under denial.

**The withdrawn claim:** after the first bind this record inferred, from Device
A's empty feed, that the `all` feed scope excludes the viewer's own posts. Device
B disproves it under the identical policy. Device A's empty feed was observed in
the contaminated window — C-57 signing it out, amid the Supabase 401 incident —
so it never supported that inference. **The inference is withdrawn; the earlier
observation is left standing as what was seen.**

## D-3 — why it is short, stated precisely

Three separate statements, and collapsing them is how this would be misread:

- **Structurally enforced.** `posts_insert_owner` carries `enforcement_gate` in
  its **`with_check`**, and **8** write policies do. An unentitled identity
  cannot insert, by construction. `posts_delete_owner` remains ungated — D-U6-2
  intact.
- **Shadow-path reachability previously demonstrated.** The row
  `posts.insert / sandbox_only / would_deny = true`, 2026-09-01 10:11:41, proves
  the publish path reaches the policy and the policy decides deny — **under
  observation, not under enforcement**.
- **No behavioural enforcement denial has been observed anywhere.** In
  production, no `posts.insert` row landed on 2026-09-02, and **absence is
  structurally uninformative**: under enforcement an INSERT denial aborts the
  statement, which rolls back the stat write — B-34's blind spot. It cannot
  distinguish *denied* from *never attempted*. Locally, there are **ZERO** insert
  attempts between `setflag true` and `setflag false` in
  `supabase/tests/u6b/acceptance.sh`; groups E–H are all reads, and `U6b-C1`
  inserts while **unbound**, testing the trigger overwrite.

**Nothing was written during the enforced window** — posts, comments and
attachment objects all `0` since the re-bind, `posts` total unchanged at 101.
That is *consistent with* refusal and is **not evidence of** it, because a
client-side enqueue in `SessionSyncQueue` is indistinguishable from a server
refusal when viewed from the database.

**Filed as C-59.** It must be closed before the next enforcement bind. It does
**not** block grandfather cleanup / U6b-4.

## Independent post-kill verification

| | |
|---|---|
| `enforcement_enabled` | **false** |
| `enforcement_active()` | **false** — the gate agrees with the flag |
| `u6b_bound_at` | **preserved**, 2026-09-01 16:52:52.452956+00 |
| Drift, all four denormalised columns | **0** |
| Triggers | **5** present |
| `posts` / `auth.users` | **101 / 17**, unchanged |
| `membership_binding.updated_at` | **2026-08-25 17:31:54** — untouched throughout |
| Production rows / conflicts / cutover | **0 / 0 / 16** |

## A state fact this run established, and it was deliberate rather than drift

`grandfather_enabled` is **false**, set by
`2026-09-01-grandfather-disable-shadow-experiment.sql` and left off. So all 16
pre-cutover identities read `unknown`, and Device B is one of them. **The matrix
therefore ran against the post-retirement world**, which is the configuration
U6b-4 is heading for anyway.

`membership_state` reaches the snapshot **transitively**, via
`when public.connected_member(target_user_id) then 'grandfathered'`. An earlier
source-text check here reported it as not reading the snapshot; that check was
defeated by the delegation, which is U5c-34's lesson arriving a third time.

## TWO CONSTRAINTS CARRIED FORWARD TO U6b-4

1. **Removing the grandfather branch and control is INTENTIONALLY IRREVERSIBLE
   and requires SEPARATE HUMAN AUTHORISATION.** The shadow experiment's
   documented rollback — `set grandfather_enabled = true` — dies with the column.
   Consistent with B-36, and a one-way door that must be a conscious act.
2. **Historical telemetry must continue accepting the existing `'grandfathered'`
   clause value after the live branch is removed.** `shadow_stat_clause_check`
   must NOT be narrowed: a historical row carries that value
   (2026-09-01 10:13:15), and narrowing the constraint alongside the branch
   removal would break existing rows.

---

# C-59 CLOSED — the write deny path has been watched denying. 2026-09-02

**D-3's local half is no longer outstanding.** The P6 matrix scored D-3 as
"structurally enforced, shadow-path reachability demonstrated, but no behavioural
enforcement denial observed either locally or in production". The local half is
now closed by **U6b acceptance group L**, 10 assertions.

**SCORED ON DATABASE OUTCOME, NEVER ON TELEMETRY** — a denied INSERT aborts the
statement and rolls back the observer's own write (B-34), so an absent
`shadow_enforcement_stat` row cannot distinguish *denied* from *never attempted*.
The only sound evidence is whether the row exists afterwards.

| | |
|---|---|
| **L1** | the unentitled author's own INSERT is refused, specifically as `new row violates row-level security policy for table "posts"` |
| **L2** | **no row landed** |
| **L3 / L4** | an **ENTITLED** author inserts successfully under the **same** enforcement — the gate discriminates rather than blanket-refusing |
| **L5 / L6** | the unentitled owner can still **DELETE** their own post (D-U6-2, behavioural half of K4) |
| **L7** | ...and still reads their own posts (D-U6-4) |
| **L8 / L9** | the **identical** refused statement succeeds with enforcement **OFF** — so L1 was the gate, not the statement |

**It traverses the real policy.** `set local role authenticated` plus a JWT claim
and a plain INSERT — the path PostgREST takes. `enforcement_gate()` is never
called directly, and `posts_insert_owner` is the **only** INSERT policy on
`posts`.

**Falsified deliberately rather than assumed discriminating.** With enforcement
off, the L1 check returns `accepted` — so **L1 would fail**. The assertion can
fire, which is the property C56-7 taught us to check.

**THE PRODUCTION-DEVICE OBSERVATION REMAINS UNMADE.** Capturing it needs a bind,
which was out of scope for C-59. D-3's production half is therefore not closed
and is not claimed to be; what has changed is that the mechanism is no longer
unobserved anywhere.

**CORRECTED 2026-09-02 — DISTINGUISH TELEMETRY BLINDNESS FROM BEHAVIOURAL
UNOBSERVABILITY.** This paragraph read *"no production test could have supplied
it"* and *"the reason it cannot be seen there at all is B-34"*. **That overstates
B-34 and the overstatement is the kind that closes off a real option.** What B-34
establishes is narrow: *shadow/observer telemetry* cannot prove whether a denied
INSERT was attempted, because its side effect may roll back. It says nothing
about whether the behaviour itself can be seen. **Under a future bind, a real
client publish IS observable without any new machinery** — by its request/response
and by whether the row persists afterwards, which is exactly the criterion C-59
was scored on. B-34 remains an **observability limitation**, never an
implementation or security blocker.

---

# FINAL U6 BIND — ENFORCEMENT IS LIVE AND DURABLE. 2026-09-02

**Bound `2026-09-02 15:30:20.83726+00` under explicit human authorisation, and
NOT followed by the kill switch.** `u6b_bound_at` preserved at
`2026-09-01 16:52:52.452956+00` — binding happened once and its record is not
rewritten. All nine returned values matched the prediction.

## D-3 PRODUCTION PASSES — the one thing P6 could not score

**All three tightened elements, in a single trace, with no instrumentation
added.** The evidence came from the existing `#if DEBUG` client path on Device B
(Études Dev) attached to Xcode.

| Element | Evidence |
|---|---|
| the real request **reached the server** | `Task <131> sent request, body S 418` → `received response, status 403` |
| it was **refused**, unambiguously on authorisation | `error=HTTP error 403 body={"code":"42501", … "message":"new row violates row-level security policy for table \"posts\""}` |
| it **did not persist** | `posts` **101 → 101**, `posts_since_bind` **0**, the refused post id absent, shares 0, storage objects 0 |

**`42501` is PostgreSQL's `insufficient_privilege`, and the message is the
`WITH CHECK` refusal from `posts_insert_owner` — byte-identical to what C-59
produced locally.** The server-path and production-path evidence now agree
exactly.

**THE CLIENT QUEUED THE POST RATHER THAN LOSING IT.** `Flush completed •
remaining=1` — `SessionSyncQueue` retained the item. Nothing was destroyed by the
refusal, and this is why "nothing was written" alone was never sufficient
evidence: a queued item and a refused one look identical from the database.
**Operationally this means the queued post will publish if enforcement is ever
lifted for that identity**, which is correct behaviour and worth knowing.

## C-57 HELD AGAIN, UNDER DURABLE ENFORCEMENT

`auth.users` **17**, unchanged. The 403 did **not** trigger `onAuthChallenge` —
the C-57 fix narrowed that to 401 alone — and the log shows the app continuing
with 200 responses immediately afterwards. No sign-out, no drop to Solo, on the
run that is not being rolled back.

## The 400s are the fail-closed RPC deny path, not a fault

Two requests returned **400**. Four gated RPCs raise on denial —
`add_post_comment`, `get_unread_private_comment_groups`, `reply_to_commenter`,
`respond_to_commenters` — and PostgREST renders a raised exception as 4xx.
`get_unread_private_comment_groups` is a read RPC the client polls and the
18-byte body matches its shape. **This is the fail-closed decision working.**
Attribution is by shape and is consistent rather than proven; no unexplained
failure occurred and no acceptance step was affected.

**It also explains their silence in telemetry**: the raise aborts the statement,
which rolls back the observer's own write. Only the two NON-raising surfaces
recorded — `storage.attachments_recipient` and `rpc.has_unread_private_comments`,
both `unknown`/`deny=true`. **B-34 confirmed in production for the first time**,
incidentally and exactly as predicted.

**No `posts.insert` telemetry row exists for the refused publish either** — same
mechanism. That is precisely why D-3 was scored on database outcome.

## The acceptance matrix

| # | Result |
|---|---|
| 1 — feed shows own posts only | **PASS** |
| 2 — publish refused, reached server, did not persist | **PASS — D-3 production** |
| 3 — account deletion reachable | **PASS** |
| 4 — stays signed in and Connected throughout | **PASS** |

Settled invariants were not re-proven. P6's evidence was reused.

## Closed by this run

**B-11** — stage 2, binding. Its final stated condition was G11 passed (done,
16 of 16) and the enforcement-path Sandbox QA resolved (Gate 6, settled and
discharged). Enforcement is now durably binding.

**C-26** — server-side membership authority now decides. Its Billing Grace
element is the SERVER's support for the state, implemented and asserted by U6b
E3/E4; **the Production App Store Connect promotion is C-31's obligation and
stays open.**

**U6** closes with them.

**Still open:** C-31 (Production Billing Grace promotion) · B-34 (an
observability limitation, not a blocker) · U7 (no cleanup worker exists; a lapsed
Sandbox row carries `pending_cleanup_at` that nothing acts on).

## The kill switch remains available and unchanged

```sql
update public.membership_control set enforcement_enabled = false, updated_at = now() where id;
```
One boolean, effective on the next predicate evaluation. `u6b_bound_at` is never
rewritten by it.
