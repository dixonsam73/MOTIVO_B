# B-37 — DEPLOYMENT RECORD

## CURRENT STATUS: **DEPLOYED AND VERIFIED IN PRODUCTION, 2026-09-20 16:24:00.874241+00**

Applied under Samuel's explicit approval from the reviewed artifact
`2026-09-20-b37-apply-production.sql` (sha256 `2b5fa035…`). Verification row `B-37 APPLIED`;
independent catalog reads confirm function md5 **`e55b8f0b583d70a6eeeab252fc15b8b3`**, `VOLATILE`
`plpgsql`, and the private `directory_search_budget` with RLS on, no policy and no client-role
privilege. Delta exactly **columns +6, constraints +2, rls_enabled +1, one function replaced**,
with grants, policies, triggers and storage buckets **byte-identical**. Canonical
`supabase/schema/` recaptured; **B-23 returned GATE MET** with only the standing
`account_id_format` exception. Privacy baseline and member content unchanged.

**WHAT IS AND IS NOT ESTABLISHED IN PRODUCTION.** The deployed *structure* is verified. **No
production search has been observed to leave a durable row**: `directory_search_budget` holds
zero rows and `shadow_enforcement_stat` none for this surface. **That is an absence of durable
rows, NOT proof that nobody has searched** — a refused or otherwise rolled-back call leaves
nothing behind either. The behavioural evidence for literal tokens and for the budget is the
99-assertion local suite, **not production traffic**. **Nothing here demonstrates rate-limiting
against live requests, and no such claim may be made.**

**Full record: §D. The durability evidence that gated the apply: §C.**

**THE SECTIONS BELOW ARE THE PRE-APPLY PREPARATION AND ARE HISTORICAL.** They are preserved as
written, not rewritten. Where one says "nothing is deployed" or "unresolved", read it as the state
at its own date.

---

# APPENDIX (HISTORICAL) — THE PRE-APPLY CHECKPOINT

**Prepared 2026-09-20, BEFORE the apply. HISTORICAL: at the time of writing nothing was deployed
and the preparation was read-only throughout.** Separate production-apply approval was required
and was not sought by this document. **That approval was subsequently given and the apply is
recorded in §D.**

Code checkpoint: commit `1940ca3` on `feature/solo-connected`.

| Artifact | |
|---|---|
| Apply | `supabase/sql/2026-09-20-b37-apply-production.sql` |
| Rollback | `supabase/sql/2026-09-20-b37-rollback-production.sql` |
| Source of truth | `supabase/migrations/20260920130000_b37_literal_search_and_budget.sql` |
| Acceptance | `supabase/tests/b37/acceptance.sh` — 99/0 |

---

## 1. Read-only production preflight — RESULTS

**Fresh B-23 parity: all ten captures IDENTICAL to the committed
`supabase/schema/`.** Production has not drifted since the post-B-38 capture, so the committed
snapshot **is** current production truth and the rollback text can be taken from it.

| | |
|---|---|
| `columns`, `constraints`, `functions`, `function_grants`, `policies` | IDENTICAL |
| `rls_enabled`, `table_grants`, `column_grants`, `triggers`, `storage_buckets` | IDENTICAL |

**The pre-state is pinned by measurement.** Production's `search_account_directory` has md5
**`3c1026dc34ef4d2e74cade068d168443`**, is `STABLE` (`provolatile = 's'`), 2648 bytes; the
counter table is absent; there are 23 public policies and 42 public functions. **The committed
capture's stored definition reproduces that md5 exactly**, which is what makes the rollback a
restoration rather than a reconstruction.

### How the capture was taken, and a hazard found doing it

`capture-schema.sh` with no arguments writes **into `supabase/schema/`**, overwriting the only
record of observed production truth. To avoid that, the preflight ran a copy of the script with
one line changed (`OUT` overridable) into a scratch directory; the ten queries are byte-identical
and are all catalog `SELECT`s. `git status supabase/schema/` was empty before and after.

**A real trap was hit on the way, and it is worth recording:** the copied script `cd`s relative
to its own location, so from a scratch directory it ran with **no linked project**, wrote
`null` into `functions.json`, and aborted under `set -e`. **Run the real script that way and the
committed capture's `functions.json` becomes the string `null`** — which would look like
catastrophic schema loss and is in fact a working-directory mistake. Not a defect in the
committed script, which is always run from the repo; recorded because the failure is silent and
the file it damages is the deployment gate's authority.

## 2. Current default durability — **HISTORICAL: UNRESOLVED AT THIS POINT, SUBSEQUENTLY MET (see §C)**

**SUPERSEDED BY APPENDIX C**, which records a deliberate ordinary client write persisting in
production at `2026-09-20 16:12:54.889440+00`, excluding both rollback modes as a point
observation. The analysis below is kept as the reasoning that specified what evidence would
count.

**Established read-only:** production's `authenticator` role carries **no `pgrst.db_tx_end`**
setting. Its full in-database configuration is `session_preload_libraries=safeupdate`,
`statement_timeout=8s`, `lock_timeout=8s`.

**An absent role setting says nothing about the process configuration** — it only rules out an
in-database override. It is recorded as one observation, not as clearance.

**NOT established:** PostgREST's own process configuration (`PGRST_DB_TX_END` in the service
environment). On a hosted project that is not readable through any authorised read-only path
available here. PostgREST's documented default is `commit`, under which `Prefer: tx=rollback` is
ignored entirely — but **a default is not a measurement**, and this must not be recorded as one.

**Why it matters:** under `commit-allow-override` or `rollback-allow-override` a caller can have
their transaction rolled back while still receiving rows, discarding the budget debit. The
in-function guard refuses any `Prefer` header and closes that, **but it cannot defend against a
server set to roll back by DEFAULT**, because then no header is sent and nothing distinguishes
the request.

### THE HEADER DISCRIMINATOR IS INSUFFICIENT ON ITS OWN — measured, and an earlier proposal here is WITHDRAWN

An earlier revision of this document proposed a single request carrying `Prefer: tx=rollback` and
read the **absence** of `Preference-Applied` as proof of commit mode. **That was wrong**, and it
was caught in review before it was performed. Measured locally across all four modes, with a
write probe to establish durability independently of the headers:

| `db-tx-end` | header sent | `Preference-Applied` | write durable |
|---|---|---|---|
| `commit` | none / `tx=commit` / `tx=rollback` | **absent** in all three | **yes** |
| `rollback` | none / `tx=commit` / `tx=rollback` | **absent** in all three | **NO** |
| `commit-allow-override` | none | absent | yes |
| `commit-allow-override` | `tx=commit` | `tx=commit` | yes |
| `commit-allow-override` | `tx=rollback` | `tx=rollback` | **no** |
| `rollback-allow-override` | none | absent | **NO** |
| `rollback-allow-override` | `tx=commit` | `tx=commit` | yes |
| `rollback-allow-override` | `tx=rollback` | `tx=rollback` | **no** |

**`commit` and `rollback` are header-identical and opposite in effect.** So an absent
`Preference-Applied` proves nothing on its own, and **an absent role setting proves nothing about
the process configuration** either.

### WHAT THE MATRIX NARROWS THE QUESTION TO — and it is NOT "which of four modes"

**`commit-allow-override` is acceptable, and an earlier revision of this document wrongly said
STOP.** The any-`Prefer` guard was built and tested precisely for the overridable case: under
`commit-allow-override` a caller sending `tx=rollback` is refused before the budget is touched,
measured in group F under exactly that setting, in both duplicate-header orders. So an
overridable server is not a reason to stop.

**Read across the matrix by the header-less row instead**, because that is what every real client
request is:

| mode | header-less request | acceptable for B-37? |
|---|---|---|
| `commit` | durable | **yes** |
| `commit-allow-override` | durable | **yes** — the guard covers the override |
| `rollback` | **discarded** | no |
| `rollback-allow-override` | **discarded** | no |

**So exactly ONE property remains: does a header-less request's transaction persist in production
right now?** That is the whole gate, and it does not require identifying which of the four modes
is configured.

### THE HISTORICAL ARGUMENT IS WITHDRAWN AS A PRESENT-DAY GATE

An earlier revision argued that both `rollback` modes were "already excluded" because production
carries persisted client writes — CP-3's discovery preference, B-38's trigger firing, the 17
directory rows. **That argument is sound about the past and unsound as a gate.** Those writes
establish the mode **at the time they were made**. PostgREST configuration is a deployment
property that can change, and nothing here observes it as of today. **Withdrawn, and it must not
be cited as clearance.**

### A HEADER-ONLY REQUEST CANNOT CLOSE THIS, SO NO PRODUCTION REQUEST IS PROPOSED FOR IT

`Preference-Applied` distinguishes overridable from non-overridable, which is **not** the
question. `commit` and `rollback` are header-identical, and those are precisely the two the
header-less row must separate. **Spending a production request on a signal that cannot answer the
question would buy nothing**, so the earlier proposal to send `Prefer: tx=commit` is withdrawn
too.

### THE SMALLEST VERIFICATION — two alternatives, neither performed here

**Preferred: an existing authorised fresh durable observation. No probe, no new mechanism, no new
credential, and no request from me.**

The account holder performs **one ordinary Connected write in the app** — for example toggling
the discovery preference in Profile, which goes through `account_privacy_set_lookup_v1`, or saving
a profile display-name change — and tells me which. I then confirm, **read-only**, that the row
reflects it (`account_privacy.lookup_enabled` and `lookup_changed_at`, or the directory row's
`display_name`).

- **What it establishes:** a header-less transaction committed in production at that moment.
  Under either `rollback` mode the write would vanish, so persistence is a direct disproof of
  both.
- **What it does not:** it is a point observation. It says nothing about configuration an hour
  later, and it must be taken close to the apply rather than banked.
- **Cost:** one ordinary app interaction the member would be free to make anyway, plus one
  read-only query. **Nothing is created that has to be cleaned up**, and a preference toggle is
  reversible by the member in the same screen.
- **Caveat worth stating:** if the toggle is left flipped it changes a real preference. Prefer a
  change the holder intends to keep, or one they flip back — and note `lookup_enabled = false` on
  `6fd0a833` is deliberate surviving evidence and must not be used for this.

**Fallback, only if no ordinary write is available: an isolated reversible probe, requiring
separate approval of its own.** A single row inserted into a scratch table created and dropped
inside the same authorised session, touching no existing object and no member data, with the
insert's persistence read back before the drop.

- **What it establishes:** the same property, without depending on the holder's app use.
- **Consequences to weigh:** it is a **live production write**, which nothing in the current
  authorisation covers; it creates and drops an object in `public`, which moves the B-23 gate for
  as long as it exists, so it must be bracketed by a recapture; and it would be the first
  production mutation of this unit. **It is proposed, not prepared, and I have written no SQL for
  it.**

**RECORDED AS UNRESOLVED.** No live write, no probe and no production request has been performed.
The deploy should not proceed on PostgREST's documented default, which this document does not
treat as evidence of the current configuration.

## 3. The apply, and what its guards actually assert

Single submission. **Guards are INSIDE the transaction and the final statement RETURNS A ROW**,
so "Success. No rows returned." is the symptom of the wrong text having run rather than its
disguise — the U6a lesson, where an apply reported success and changed nothing.

**PRE:** the function exists and its md5 is exactly the rehearsed pre-state; the counter table
does not exist; 23 public policies; 42 public functions.

**POST:** the deployed definition is **byte-identical** to the rehearsed object
(md5 `e55b8f0b583d70a6eeeab252fc15b8b3`); it is `VOLATILE`; **all three** match branches carry an
explicit `ESCAPE`; the empty-token guard is present; the `Prefer` guard is present; the counter
table exists with RLS on, no policy and no client-role privilege; the execute surface is
`authenticated` only; policy and function counts unmoved.

**Never score this on an exit code or a success message.** Score it on the verification row, then
on an independent recapture.

## 4. The rollback

Restores the previous definition **verbatim from the committed capture**, whose md5 was verified
against production read-only, then drops the counter table. Its POST guard re-asserts the
pre-B-37 md5, so a rollback landing anything else aborts rather than leaving a plausible-looking
wrong function in place.

**No Domain 3 content is touched in either direction** — no member content, no posts, no
comments, no attachments, no directory rows.

**But the rollback's cost is NOT "one member's allowance window", and an earlier revision of this
document said so wrongly.** Dropping `directory_search_budget` discards **every account's**
current counters and returns the whole directory to **unmetered search with wildcard
characters live again** — both browse routes reopen. That is the correct thing for a rollback to
do, since it restores the pre-B-37 state exactly; it is simply a larger statement than the one
first written here, and whoever authorises a rollback should be reading the accurate one.

## 5. Local rehearsal — RESULTS

Run against the local stack, which after `db reset --local` carries B-37 via the migration.

| step | result |
|---|---|
| rollback (B-37 → pre-B-37) | **md5 `3c1026dc…`, `STABLE`, table gone, 23 policies** — verification row returned |
| apply (pre-B-37 → B-37) | **md5 `e55b8f0b…`, `VOLATILE`, table present, 0 counter rows, 23 policies** — verification row returned |
| re-run apply when already applied | **REFUSED** — `PRE-1 FAILED … refusing to apply` |
| re-run rollback when already rolled back | **REFUSED** — `PRE-2 REFUSED: already at the pre-B-37 definition` |
| **B-23 gate on the ROLLED-BACK stack** | **GATE MET**, with only the standing `account_id_format` catalog-serialization exception |
| acceptance suite through the APPLY path | **PASS 99, FAIL 0** |

**The rollback's strongest evidence is the GATE MET line:** structural identity with production,
measured, not argued. And because apply and migration produce the **same md5**, the object the
99-assertion suite ran against is byte-identical to the object the apply installs.

**Two defects were found by rehearsing and are fixed:** every `raise` format string used `%%`,
which renders a literal `%` and consumes no argument, so each would have failed with *"too many
parameters specified for RAISE"*; and `pg_get_functiondef` emits **no trailing semicolon**, so
the restored definition ran straight into the next statement and the rollback failed with a
syntax error. Both would have surfaced only during a production apply.

## 6. Expected production delta

**columns +6, constraints +2, rls_enabled +1, functions 0 new with 1 MODIFIED, policies 0,
function_grants 0, table_grants 0, column_grants 0, triggers 0, storage_buckets 0.**

Pre-deploy, the B-23 gate reports **GATE NOT MET — 10 problems**, every one a B-37 object: the
replaced function, the new table's RLS row, its two constraints and its six columns. That is the
correct pre-deploy result, the same shape U5b recorded; it returns GREEN after deploy and
recapture.

## 7. Consequence to state at the approval point, not to discover afterwards

**`shadow_enforcement_stat` will begin recording `rpc.search_account_directory`.** PostgREST runs
a `STABLE` function's RPC in a read-only transaction, so `enforcement_gate`'s telemetry INSERT has
been failing there and being swallowed by its own `exception when others then null`
(measured locally: SQLSTATE 25006). With the function `VOLATILE` that write succeeds. This is a
consequence of the volatility change, not a feature; it bears on **B-34** and **C-56** without
resolving either. **Measured locally; production behaviour is inference.**

## 8. Outstanding before apply

1. **Current default durability** — §2. One header-less transaction observed to persist in
   production, close to the apply: preferably the account holder's own ordinary Connected write
   confirmed read-only, otherwise a separately approved isolated reversible probe. **Which of the
   four modes is configured does not need to be identified**, and the documented default is not
   evidence.
2. **Separate production-apply approval** from Samuel.
3. Independent post-apply verification: the verification row, then a fresh capture and a B-23 run
   expected to return GREEN.

---

# APPENDIX A — THE DURABILITY OBSERVATION: BASELINE AND EVIDENCE

**Recorded 2026-09-20. Read-only throughout; no production write, probe or apply has been
performed.** This appendix exists so the observation can be scored later against a value captured
before it, rather than against memory.

## A.1 Preflight refreshed immediately before this

Fresh read-only capture into scratch: **all ten files IDENTICAL** to committed
`supabase/schema/`, which was not written to (`git status supabase/schema/` empty before and
after). Production still matches the apply's PRE guard exactly — function md5
`3c1026dc34ef4d2e74cade068d168443`, `provolatile = 's'`, `directory_search_budget` absent, 23
public policies, 42 public functions. The apply still embeds the committed migration body
verbatim and the migration in the tree is identical to the one at `1940ca3`; the rollback still
embeds the canonical prior definition verbatim. Local re-rehearsal passed both ways.

## A.2 BASELINE — observed `2026-09-20 15:50:02.426386+00`

Identity `6fd0a833` (prefix only; **no full production UID is recorded in this repository**).

**Corroborated as Device A by membership, NOT by display-name uniqueness:** its `membership` row
carries `original_transaction_id = 2000001228947923`, which the device/tester table in
`CLAUDE.md` pins to tester 2 (`+devicec`) on Device A, the SD beta burner. The name matched
exactly one row as well, so there was no ambiguity by either route.

| `account_directory` | value |
|---|---|
| `account_id` | `devicearlease` |
| **`display_name`** | **`Ben Craft`** |
| `location` | `Hertfordshire` |
| **`lookup_enabled`** | **`false`** ← **PROTECTED: the surviving evidence of an explicit user preference (CP-3). Must be unchanged afterwards.** |
| `avatar_version` | `2026-09-16 17:25:28.047554+00` |
| `entitled_until` | `2026-09-20 15:48:39+00` |

| `account_privacy` | value |
|---|---|
| `age_band` / `lookup_set_under_band` | `band_18_plus` / `band_18_plus` |
| **`lookup_enabled`** | **`true`** ← **authoritative, and ALSO to be unchanged** |
| **`lookup_changed_at`** | **`2026-09-10 06:02:41.524643+00`** ← **to be unchanged** |
| `follow_requests_enabled` / `_changed_at` | `true` / `null` |
| `band_updated_at` | `2026-09-08 16:54:51.48418+00` |

**THE TWO `lookup_enabled` COLUMNS DISAGREE, AND THAT IS THE EXPECTED POST-CP-3 SHAPE.** Directory
`false`, privacy `true`; authority moved to `account_privacy` when CP-2 stopped reading the
directory column. **Both are to be preserved** — the protected artefact is the directory `false`,
and the authoritative value is the privacy `true`.

## A.3 Why this write is a valid discriminator — MEASURED, not argued

Run on the disposable local stack with the **client's exact request shape**: a table upsert to
`rest/v1/account_directory?on_conflict=user_id` carrying
`Prefer: resolution=merge-duplicates,return=minimal`, with the privacy columns omitted exactly as
`upsertSelfRowOnce` omits them.

| `db-tx-end` | HTTP | `Preference-Applied` | display_name after | directory `lookup_enabled` after |
|---|---|---|---|---|
| `commit` | 200 | `resolution=merge-duplicates, return=minimal` | **After Name — PERSISTS** | `false` |
| `commit-allow-override` | 200 | same | **After Name — PERSISTS** | `false` |
| `rollback` | 200 | same | **Before Name — REVERTED** | `false` |
| `rollback-allow-override` | 200 | same | **Before Name — REVERTED** | `false` |

**So an ordinary display-name change that PERSISTS excludes both rollback modes**, which is the
entire remaining gate. Identifying which of the four modes is configured is not required.

**The path DOES send a `Prefer` header**, and the earlier condition "sends no Prefer header" is
therefore **not literally met**. It carries no `tx=` preference, and the table above shows the
transaction outcome tracking `db-tx-end` alone across all four modes. That is the measurement the
suitability rests on, not the absence of a header.

## A.4 Why it cannot disturb the protected evidence

- **The payload omits both privacy columns** — `upsertSelfRowOnce` sends only `user_id`,
  `display_name`, `location`, and conditionally `account_id` and `instruments`. PostgREST's
  merge-duplicates upsert updates only supplied columns.
- **Behaviourally confirmed, not inferred from the comment:** `account_directory.lookup_enabled`
  stayed `false` in all four modes, and the whole `account_privacy` row — `lookup_enabled`,
  `lookup_changed_at`, `band_updated_at` — was byte-identical before and after.
- **No trigger on `account_directory` writes `account_privacy`.** The four are
  `tg_directory_avatar_guard`, `tg_directory_avatar_version` (`BEFORE UPDATE OF avatar_key`, so it
  cannot fire here), `tg_directory_entitled_until` and `tg_directory_requires_band`
  (`BEFORE INSERT` only).

**ONE HONEST SIDE EFFECT:** `tg_directory_entitled_until` fires `BEFORE INSERT OR UPDATE`, so the
edit recomputes `entitled_until`. That membership's `renewal_date` is `2026-09-20 15:48:39`, so
the value may legitimately move. **It does not touch the discovery evidence, and a change there
must not be read as one.** `account_directory` has **no `updated_at`**, so the only time evidence
is the observation timestamp.

## A.5 What was still outstanding AT THAT POINT — **both items discharged the same day**

**HISTORICAL.** Item 1 was met at `16:12:54.889440+00` (§C) and item 2 was given, with the apply
recorded in §D.

1. **Samuel's ordinary write**, then an independent read-only observation confirming the new
   `display_name`, with `account_directory.lookup_enabled` still `false` and
   `account_privacy.lookup_enabled` / `lookup_changed_at` unchanged at `true` /
   `2026-09-10 06:02:41.524643+00`.
2. **Samuel's separate production-apply approval.**

**Nothing is deployed. No production write has been made by me.**

---

# APPENDIX B (HISTORICAL — SUPERSEDED BY §C) — A FIRST ATTEMPT THAT PRODUCED NO EVIDENCE

**Kept because its diagnosis stands and is now an addendum on C-70. The gate it left open was
met later the same day; see §C.**

**2026-09-20. The gate is NOT met. It is also NOT failed. The write never reached a
commit-or-rollback decision, so it says nothing about `db-tx-end` in either direction.**

## B.1 What was observed

Samuel reported saving `Ben Craft` → `Ben Craft QA1` on Device A, with a red ProfileView warning
*"couldn't update your profile… please try again"*, and the new name surviving leaving and
returning to the screen.

Read read-only at **`2026-09-20 15:53:02.222042+00`** and again at `15:53:29`: `display_name` is
still **`Ben Craft`**. **Zero rows in `account_directory` contain "QA1".** All protected values
unchanged — `account_directory.lookup_enabled` `false`, `account_privacy.lookup_enabled` `true`,
`lookup_changed_at` `2026-09-10 06:02:41.524643+00`, `band_updated_at` unmoved. `entitled_until`
did **not** move either, which is consistent with no UPDATE having been applied at all.

The name surviving on screen is the **local `ProfileStore`**, written independently of the remote
result. Local success and remote failure are separate outcomes here, and that is pre-existing
behaviour.

## B.2 The cause — structurally supported and now LOCALLY REPRODUCED, but NOT captured on the wire

The client write is an upsert, which Postgres executes as `INSERT … ON CONFLICT DO UPDATE` and
therefore checks against the **INSERT** policy:

```
[INSERT] account_directory_insert_owner   check: enforcement_gate('account_directory.insert') AND user_id = auth.uid()
[UPDATE] account_directory_update_owner   check: user_id = auth.uid()          <-- UNGATED
```

Reproduced on the local stack with enforcement ON, the client's exact request shape, and a
sandbox-only membership toggled between active and expired:

| fixture | `connected_member` | `membership_state` | upsert | row after |
|---|---|---|---|---|
| Sandbox, renewal in the future | **true** | `sandbox_only` | **HTTP 200** | `Ben Craft QA1` |
| Sandbox, renewal in the past | **false** | `sandbox_only` | **HTTP 403, 42501 "new row violates row-level security policy"** | unchanged |
| same, ordinary PATCH instead | false | `sandbox_only` | **HTTP 204** | `Ben Craft QA2` |

**NO REQUEST-LEVEL ERROR WAS CAPTURED FROM DEVICE A.** No device log is attached to this session
and none was requested. So the production explanation is **structurally supported and locally
reproduced, not HTTP-proven on that device**, and is recorded at that strength.

## B.3 TWO CORRECTIONS TO THE RECORD, both mine to make

**(i) `membership_state = 'sandbox_only'` DOES NOT MEAN "not entitled", and reading it that way
is the trap that produced a wrong correction during this session.**

**PROVENANCE, recorded rather than tidied away.** The wrong correction came from Codex's review,
which steered against a Sandbox resubscribe on the grounds that `connected_member` requires
`m.environment = 'Production'`. That is what
`20260902120000_u6b4_grandfather_retirement.sql` line 69 says, and it is **superseded**. Codex
independently re-read `20260915160000_scope011_verified_sandbox_entitlement.sql` and the canonical
`functions.json`, confirmed the deployed predicate accepts Production **and** Sandbox, withdrew
the steering and corrected the account holder directly. **The sequence is kept because the failure
mode — reading a migration's bytes as the deployed state when a later migration changed them — is
the same shape as B-23's whole reason for existing, and the deployed capture is what settled it.**
 `connected_member()` as
DEPLOYED accepts `m.environment in ('Production', 'Sandbox')` — scope011, migration
`20260915160000`, which superseded the Production-only text still visible at line 69 of
`20260902120000_u6b4_grandfather_retirement.sql`. But `membership_state()` was **not** changed by
scope011: its `exists` branch still filters `environment = 'Production'`, so a Sandbox identity
reports `sandbox_only` **whether or not it is entitled**. The local table above shows the label
constant while the predicate flips.

**(ii) The causal conjunct is EXPIRY, measured rather than assumed.** Live decomposition of the
deployed predicate for this identity at `2026-09-20 15:58:04+00`:

```
env_ok = true    not_revoked = true    renewal_in_future = FALSE    in_grace = false  ->  predicate = false
```

`entitlement_ended_at = 2026-09-20 15:48:39+00`, roughly three minutes before the save. **Only the
renewal conjunct is false**, so restoring entitlement would flip it.

## B.4 This is NOT a new finding — it is C-70's already-traced condition

`docs/audit-findings.md` C-70, traced 2026-09-09, already records it in these words: *"Measured on
the deployed policies: `account_directory_insert_owner` is gated by `enforcement_gate`, while
`account_directory_update_owner` is NOT… no directory INSERT can succeed"*, and names this same
identity. **No duplicate row is filed.** What today adds is the first **behavioural reproduction**
(HTTP 403/42501) and the active-versus-expired discrimination; that belongs as an addendum to
C-70, not as a new register row, and is **proposed rather than written**.

## B.5 Where the gate now stands

**Unchanged and outstanding.** No ordinary client write to a gated surface can succeed in
production at present: **both** directory identities are Sandbox-only with `renewal_date` in the
past (`6fd0a833` ended 15:48:39, `ed6c420b` ended 15:43:44), so `connected_member()` is false for
every identity and the INSERT gate refuses.

**The earlier recommendation is restated with its evidence rather than withdrawn.** A Sandbox
resubscribe on Device A's `+devicec` tester would restore entitlement — the local fixture shows an
active Sandbox membership yielding `connected_member = true` and the upsert succeeding — after
which repeating the same ordinary name edit would produce the observation. **It is a member
purchase and needs Samuel's approval; it is proposed, not requested.** A successful retry would
no longer stand alone as the causal evidence, because §B.2 isolates the cause locally.

**Alternatives considered and their costs:** `account_privacy_set_lookup_v1` is ungated and would
succeed, but it mutates a discovery preference — excluded on `6fd0a833`, and on `ed6c420b` it
would change a real member preference and move `lookup_changed_at` twice to restore. An avatar
PATCH is ungated but clearing an avatar is **not safely reversible while unentitled**, because
re-uploading needs the gated storage INSERT. The isolated scratch-table probe remains available
under separate approval and is still a production write.

**B-37 APPLY REMAINS HELD** on this observation and on Samuel's separate approval. Nothing has
been applied, written or configured in production.

---

# APPENDIX C — CURRENT DEFAULT DURABILITY: GATE MET AS A POINT OBSERVATION

**2026-09-20. A deliberate ordinary client write persisted in production, bracketed by two
independent read-only observations inside a known-entitled window.**

| | |
|---|---|
| **Pre-edit read** | **`2026-09-20 16:11:27.924973+00`** — `display_name` = `Ben Craft QA1` |
| Member action | Samuel restored the name on Device A, `Ben Craft QA1` -> `Ben Craft`, and reported done |
| **Post-edit read** | **`2026-09-20 16:12:54.889440+00`** — `display_name` = **`Ben Craft`** |

`connected_member` was **true at both ends**, by the predicate and not by the
`membership_state` label: `env_ok` true, `not_revoked` true, **`renewal_in_future` true**,
`in_grace` false, `renewal_date 2026-09-20 16:39:33+00`.

**PRIVACY EVIDENCE PRESERVED THROUGHOUT**, unchanged from the A.2 baseline:
`account_directory.lookup_enabled` **`false`**, `account_privacy.lookup_enabled` **`true`**,
`lookup_changed_at` **`2026-09-10 06:02:41.524643+00`**, `band_updated_at` unmoved. `account_id`,
`location` and `avatar_version` also unchanged. **The member's profile is restored to its original
value**, so nothing was left altered to obtain this evidence.

**WHAT THIS ESTABLISHES.** A header-equivalent ordinary client write committed in production at
that moment. Per the four-mode matrix in A.3, both `rollback` and `rollback-allow-override` would
have discarded it. **Both rollback modes are therefore excluded as of `16:12:54.889440+00`.**

**WHAT IT DOES NOT ESTABLISH, and must not be written up as if it did.** It is a **point
observation, not a standing configuration claim.** PostgREST's configuration is a deployment
property that can change, and nothing here reads it. It does not identify which of `commit` or
`commit-allow-override` is set — and it does not need to, because the any-`Prefer` guard covers
the overridable case (A.3). **If the apply does not follow closely, this observation should be
repeated rather than relied upon.**

**An earlier, weaker instance is recorded separately and is NOT the evidence relied on:** the
first edit's value appeared between the `15:53:02` and `16:10:18` reads, with the write moment
unobserved and automatic-retry versus fresh action undetermined. Appendix C rests on the
deliberate bracketed pair above.

---

# APPENDIX D — APPLIED TO PRODUCTION 2026-09-20

**Applied under Samuel's explicit approval ("approved. deploy") and Codex's authorisation, using
the reviewed artifact. One transaction, submitted once that reached the database.**

## D.1 Artifact and timing

| | |
|---|---|
| Artifact | `supabase/sql/2026-09-20-b37-apply-production.sql` |
| sha256 | `2b5fa03573be1cafee34e4c6aab6afcac028be991547c707869d6e29c800bc1a` — **verified immediately before submitting** |
| PRE state, read fresh | `16:23:29.452291+00` — md5 `3c1026dc…`, `s`, table absent, 23 policies, 42 functions |
| Submitted | `16:23:58.573882+00` |
| **Applied** | **`16:24:00.874241+00`** (the verification row's own `applied_at`) |

**A FIRST SUBMISSION WAS REJECTED BEFORE REACHING THE DATABASE AND IS RECORDED, NOT HIDDEN.**
Passing the SQL as a positional argument failed with `UnrecognizedOption` — the CLI parsed the
file's leading `--` comment as a flag. **Nothing executed.** Production was re-read before
anything else (`16:23:51.097766+00`: md5 `3c1026dc…`, table absent, 23/42, unchanged), and the
second submission used the CLI's own `-f/--file` flag, which sends the file bytes.

**The submission was made through `subprocess` with an argv list, never a shell.** The file
contains `$guard$` and `$function$` dollar-quoting, and shell parameter expansion would have
silently substituted `$guard` and `$function` with empty strings — corrupting the text while
still submitting something. That is the U6a failure mode in a new costume.

## D.2 The verification row — scored, not the exit code

```
result "B-37 APPLIED" | function_md5 e55b8f0b583d70a6eeeab252fc15b8b3 | volatility v
counter_table true | owner_only_grants 7 | counter_rows 0 | public_policies 23
applied_at 2026-09-20 16:24:00.874241+00
```

**Independent catalog reads at `16:24:16.600531+00`**, not trusting that row: md5
`e55b8f0b583d70a6eeeab252fc15b8b3`, `provolatile = v`, `plpgsql`, table present, **RLS on, zero
policies, zero client-role grants, 6 columns**, execute `authenticated` true / `anon` false /
`service_role` false, 23 policies, 42 functions, 0 counter rows.

## D.3 Delta — exactly as predicted

Post-apply capture against the **pre-apply production capture**:

| | |
|---|---|
| `columns` | **+6** |
| `constraints` | **+2** |
| `rls_enabled` | **+1** |
| `functions` | 42 → 42, **one modified** |
| `function_grants`, `policies`, `table_grants`, `column_grants`, `triggers`, `storage_buckets` | **IDENTICAL** |

Against the **local prediction** captured before the apply: **nine of ten byte-identical**, the
tenth differing only by the standing `account_id_format` catalog-serialization exception.

**Canonical `supabase/schema/` recaptured afterwards**, changing exactly four files. **B-23
returned GATE MET**, with that single approved and mechanically verified exception.

## D.4 Nothing else moved

Privacy baseline at `16:26:06.757299+00`, identical to the A.2 baseline in every field:
`display_name` `Ben Craft`, `account_directory.lookup_enabled` **`false`**,
`account_privacy.lookup_enabled` **`true`**, `lookup_changed_at`
**`2026-09-10 06:02:41.524643+00`**, `band_updated_at`, `account_id`, `location`,
`avatar_version` all unchanged.

Member content census: users 3, directory 2, posts 10, comments 5, follows 2, membership 2.
**No member content was mutated, and no synthetic search was run.**

## D.5 The telemetry consequence — OBSERVED SO FAR, and the distinction matters

`shadow_enforcement_stat` currently holds **0 rows for `rpc.search_account_directory`**, and
`directory_search_budget` holds **0 rows**.

**READ THAT AS AN ABSENCE OF DURABLE ROWS, NOT AS "nobody has searched yet" — an earlier revision
of this section said the latter and it was wrong.** A search that was refused, that failed, or
whose transaction was rolled back leaves no row in either table, so zero is consistent with
several histories and distinguishes none of them. What is established is only that **no durable
search row exists at this observation**.

**INFERRED, NOT OBSERVED:** that those counts will become non-zero on the first real search now
that the function is `VOLATILE` and `enforcement_gate`'s INSERT can land. The mechanism was
measured **locally** (a `STABLE` function's nested INSERT fails `25006` in PostgREST's read-only
transaction); **it has not yet been observed in production**, and will not be until a member
searches. It bears on **B-34** and **C-56** and resolves neither.

## D.6 Not done

**No commit, no push.** The canonical schema recapture and this record are uncommitted and await
review. The rollback artifact
(`supabase/sql/2026-09-20-b37-rollback-production.sql`, sha256
`112467221dd787908feb730b45eaabfa21238e2966ca25d611a4485c25d6ba7a`) remains available and
rehearsed; its consequence is unchanged — it discards every account's counters and reopens both
browse routes.
