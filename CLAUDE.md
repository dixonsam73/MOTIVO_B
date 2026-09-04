# Études — Working Context

iPhone app: a local-first journal for musicians, with an optional paid
"Études Connected" social layer (Supabase + StoreKit 2 + Sign in with Apple).

Working branch: `feature/solo-connected`. Audit baseline commit: `ec2f52f`.

"MOTIVO" is the legacy working title. The project file, scheme and source
directory are all named MOTIVO; the product is `Etudes.app`, display name
"Études". Renaming is not release work.

Baseline verified at migration: Debug and Release both compile clean
(0 errors). See `docs/audit-findings.md` for what the Release build surfaced.

---

# PHASE 3 IS CLOSED — 2026-09-03. UNATTENDED EXPIRY CLEANUP IS LIVE

**U3, U4, U5, U6 and U7 are all complete and in production.** Membership is
**established** authoritatively (U5), **enforced** durably (U6), and now
**collected** unattended (U7) under a live Apple authority check.
`CLEANUP_MODE = execute` is set; the daily 03:17 UTC job invokes
`membership_cleanup_v1` v6. The full record is
`supabase/sql/README-u7e-closure.md`.

**ARMING ENABLED A CAPABILITY; IT DID NOT SCHEDULE A DELETION.** Two gates
survive it. Candidate selection is empty until **2026-11-01**, and every
candidate still needs a successful live Apple read applied through the canonical
writer before `membership_cleanup_authorised_v1` will authorise. **That is
measured, not argued:** on 2026-09-03 a manual `execute` against a
deliberately-advanced schedule **REFUSED**, and the reconciliation overwrote the
artificial value with Apple's own derived date. **`pending_cleanup_at` SELECTS;
it never AUTHORISES**, and an operator writing it by hand cannot change that.

**NOTHING HAS EVER BEEN DELETED BY THE WORKER.** Production is byte-identical to
its pre-U7 state — 17 identities, 101 posts, 5 comments, 9 follows, 15 attachment
objects — and `renewal_info_signed_date` has never moved on a scheduled run.

**FOUR OBLIGATIONS ARE CARRIED, NONE OWNERLESS:** **G7** (first naturally matured
production cleanup, owner U7, earliest 2026-11-01 — its only precondition now is
elapsed time), **C-31** (Production Billing Grace), **B-34** (shadow telemetry
blind to denied writes — an observability limitation, never a correctness
defect), and **Gate 6 part 3** on B-11 (production GRANT at the first real
subscription). **Phase 3 is allowed to close carrying these**, by the project's
own rule that forcing an obligation to fit a phase boundary is the opposite of
the discipline that says no obligation may be ownerless.

**KILL SWITCHES, none of which touch membership state:** unset `CLEANUP_MODE`
(back to `dry_run`), disable the workflow, delete the GitHub secret, or delete
the Supabase `CLEANUP_INVOKE_KEY` (the worker then refuses every caller,
fail-closed). **None of them undoes a completed deletion** — there is no backup
of Domain 3 content.

**THE HISTORICAL RECORD BELOW REMAINS ACCURATE AS OF ITS OWN DATES AND IS NOT
REWRITTEN.**

# PHASE 3 — SETTLED LIFECYCLE ARCHITECTURE

**Approved and frozen 2026-08-16, before any implementation.** Phase 3 makes
membership server-authoritative and makes **leaving Connected** a distinct
lifecycle from **deleting an account**. This section is the durable record of
what was decided; it is not a description of what is built. **Implemented so far:
U0 (this record), U1 (the local backend baseline), U2 (the four backend
verifications), U3 — DEPLOYED TO PRODUCTION 2026-08-17 — U4 in full, including
U4h/U4i — DEPLOYED TO PRODUCTION AND ACCEPTED 2026-08-20 — U5a, a gate unit
(2026-08-20): F1/C-52 corrected and verified, F3b EXECUTED and scored **P2** —
**U5b, U5c and U5d (2026-08-23): the SQL foundation, the attestation support
and `membership_attest_v1` itself** — **U5e (2026-08-23): client plumbing and
F6** — **U5f (2026-08-23): the new join flow and attestation orchestration**,
the first product-visible U5 unit — and **U5g — DEPLOYED TO PRODUCTION AND
ACCEPTED 2026-08-23**. **THE WHOLE PROTOCOL IS DEPLOYED AND HAS MET APPLE IN
BOTH DIRECTIONS**: the legacy claim on 2026-08-25 (S-1, S-2, S-3) and
bound-at-source on 2026-08-30 (B-24n, F10), both on genuine Apple Sandbox.
**U6a — SHADOW ENFORCEMENT — DEPLOYED TO PRODUCTION AND VERIFIED 2026-09-01.**
23 policies and 9 RPCs now *observe* membership; **not one of them enforces it**,
and the observer returns `true` on every path. **U6b, U6c AND U7 HAVE NOT
BEGUN** — nothing consults membership *for a decision* and no cleanup worker
exists.

**CORRECTED 2026-08-30, AND THIS IS THE FOURTH INSTANCE OF ONE FAILURE MODE.**
This paragraph read "U5b, U5c and U5d ... **LOCAL ONLY AND NOT DEPLOYED** ...
**NOTHING IS DEPLOYED and nothing has met Apple** ... **U5g ... has not begun**"
for seven days after U5g deployed — while the heading three sections below read
"U5 IS LIVE IN PRODUCTION — deployed and accepted 2026-08-23", and while two
genuine Apple Sandbox runs were recorded elsewhere in this same file. Written
before the deploy and never re-read afterwards: **exactly C-52, exactly the U4
heading corrected immediately below, and exactly the rig-state section corrected
at `c7cb0f7`.** **This one is the opening paragraph** — the first thing a new
session reads, and therefore the last thing anybody re-reads.

**CORRECTED 2026-08-20.** This paragraph previously read "U4b-U4g ... IMPLEMENTED
AND GREEN LOCALLY BUT NOT DEPLOYED", which the very next section contradicted in
its own heading. It was written before the deploy and never re-read afterwards —
**the same failure mode as C-52 four lines of reasoning apart**: a durable
document describing a state it is not itself evidence of.

## U6b — DEPLOYED AND INERT. ENFORCEMENT WAS BOUND FOR SIX MINUTES AND ROLLED BACK. 2026-09-01

**U6b-1 IS LIVE IN PRODUCTION AND DENIES NOTHING.** The gate, the kill switch, the
four denormalised `entitled_until` columns and their five triggers are deployed;
`enforcement_enabled` is **FALSE**. B-23 returned **GATE MET** after recapture, and
the deployed state is **byte-identical to the pre-deploy local build** on nine of
ten surfaces, the tenth differing only by the standing `account_id_format`
exception. Device inertness was confirmed on real traffic at P4.

**ENFORCEMENT WAS BOUND AT 16:52:52 AND ROLLED BACK AT 16:58:29.** The structural
bind succeeded and every prediction held — ten guards passed, and the policy
fingerprint was unchanged afterwards, proving the flip wrote one boolean and one
timestamp. **`u6b_bound_at` REMAINS SET, DELIBERATELY:** it records that binding
happened, which stays true, and it makes the bind statement **refuse to run a
second time**. A re-bind is a conscious act, never a repeat.

**PRODUCTION DENY-PATH VERIFICATION IS SUBSTANTIALLY PASSED, WITH D-3
BEHAVIOURAL ENFORCEMENT COVERAGE OUTSTANDING — 2026-09-02.** Re-bound 11:17:55,
kill switch 11:28:07, enforcement live for about ten minutes, `u6b_bound_at`
preserved so the record of the first binding is not rewritten. **This is
deliberately not recorded as "P6 complete" or "P6 passed".** **D-1 production
PASS** (feed filtered); **D-2 — non-owner content filtered from the production
feed, direct-open behaviour NOT independently exercised**; **D-3 — structurally
enforced and shadow-path reachability previously demonstrated, but NO
behavioural enforcement denial has been observed either locally or in
production, filed as C-59**; **D-7 production PASS** (directory search empty);
**account-deletion and carve-outs production PASS**.

**C-57 IS BEHAVIOURALLY VERIFIED UNDER LIVE ENFORCEMENT**, across both
`sandbox_only` and `unknown`, **with no credential destruction and no sign-out
across the observed denials** — `auth.users` held at 17 and both devices stayed
Connected while being denied. That was the run's primary purpose and it is the
exact failure that forced the rollback below. Post-kill: gate agrees with the
flag, **drift 0** on all four denormalised columns, five triggers, binding
`updated_at` untouched at 2026-08-25, Production rows 0, conflicts 0.

**D-1 CORRECTS AN EARLIER INFERENCE, NOW WITHDRAWN.** Device B saw its own posts
and nobody else's — the **ungated owner branch**, carve-out D-U6-4, working as
designed. The earlier claim that the feed's `all` scope excludes the viewer's own
posts was drawn from Device A's empty feed in the contaminated window and is
withdrawn; the observation stands, the inference does not.

**THE RECORD BELOW IS THE 2026-09-01 RUN AND REMAINS ACCURATE AS OF ITS DATE.**

**THE BEHAVIOURAL DENY-PATH QA WAS INCOMPLETE ON 2026-09-01 AND MUST NOT BE READ AS PASSED.** A
Supabase service incident — **HTTP 401 JWT rejections at PostgREST**, persisting on
14.17 and rolled back to 14.5 — was in progress during the QA window, and the
device symptoms seen under it — an empty feed with its empty-state message
*absent*, attribution rendering as `User` — are the shape of **failed** requests,
not denied ones. Only **two** surfaces were ever exercised under enforcement, both denying
gracefully; **`posts.select` never fired**, so publish, comment, own-attachment,
own-profile and account-deletion-reachable were never tested at all. **The deny
path is NOT verified in production.**

**A 401 IS AN AUTHENTICATION FAILURE AND AN RLS DENIAL IS NOT**, which is why the
vendor fault explains those symptoms and the gate does not: a denial returns zero
rows and would have rendered the empty state. It also explains why direct Postgres
access stayed healthy throughout — that path reaches the database through the
Management API and **never presents the app's JWT**, while the app goes through
PostgREST, which is exactly where the rejections were. **Corroboration, not
measurement: no request-level 401 was captured from either device.** The record is
`supabase/sql/README-u6b-p6-binding.md`.

**Nothing in U6b touches the client.** Zero client code shipped, and the grant path
remains deferred to the first genuine App Store subscription after public release.

## U6a IS LIVE IN PRODUCTION — shadow enforcement, deployed and verified 2026-09-01

**23 policies and 9 SECURITY DEFINER RPCs now carry an observer. NOTHING IS
ENFORCED.** `shadow_observe` returns `true` on every path and swallows its own
write failure, so no request's outcome changed — a property of the code, proven
by G4-S2 comparing row counts with the observer attached and detached.
**`shadow_enforcement_stat` holds zero rows, zero privilege for every client
role, and RLS is on.** The record is `supabase/sql/README-u6a-deployment.md`.

**Every predicted number matched production and nothing was repaired forward.**
Structural delta 10 of 10 — columns 130, constraints 67, functions 24 with 9
modified, function_grants 72 with **zero** modified, rls_enabled 15, policies 33
with 23 modified, and four surfaces byte-identical. B-23 returned **GATE MET**
after recapture with only the standing `account_id_format` exception. **The
deployed state is byte-identical to the prediction captured before the deploy**,
and both fingerprints moved to exactly the rehearsed local values, so
production's 33 policies and 9 functions are the same bytes the 74-assertion
suite ran against.

**Verified in the DEPLOYED BUNDLE rather than the tree: 23 observer calls, 23
wrapped as `(select …)`, ZERO BARE.** That is the one property review cannot
catch, because both forms are functionally correct and only the timing differs —
278ms against 3.9ms at 5000 rows.

**B-33 CLOSES HERE, on both halves.** The predicate reachable from a policy qual
is `connected_member_self()`, zero-argument and granted to `authenticated` only;
`connected_member(uuid)` and `membership_state(uuid)` stay ungranted to every
client role, so the membership oracle is structurally unbuildable. And **U3's
false comment is corrected in place with the original sentence quoted, not
deleted** — the point is to recognise a claim that is correct-sounding and cannot
be falsified by reading.

### THE FIRST APPLY REPORTED SUCCESS AND APPLIED NOTHING

**This outlives U6a and it is the reason to re-read this section before any
future deploy.** The SQL editor answered *"Success. No rows returned."* and
production was **completely unchanged** — both fingerprints still at their
pre-U6a values, 22 functions, zero new objects. Not partial. Nothing.

**The mechanism was not at fault, established by probes rather than argued.** A
bare `create table` landed; `begin; create table …; commit;` landed; the project
and the read path were right. So DDL, multi-statement submission and explicit
transactions all work, and **what failed was the submitted text** — most likely
the P1 no-op verification file running a second time, which is valid, commits,
returns no rows and changes nothing.

**A SUCCESS MESSAGE IS NOT EVIDENCE THAT THE INTENDED TEXT RAN.**
`supabase/README.md` already warned that a Studio submission can fail in a way
that *"reads exactly like success"*; that warning was about a split
`BEGIN`/`COMMIT` and this arrived by a route it did not cover. **The
generalisation is the durable part: any procedure whose success is reported by
the thing being asked to act is unverified.** U3, U4 and U5 were not safer — they
were caught by post-deploy verification rather than by the apply.

**The fix was not more care at the keyboard.** It was a guard *inside* the
transaction asserting the state it had just produced, and a final `SELECT` that
returns a row — so **"no rows returned" became the symptom instead of the
disguise**. `supabase/sql/2026-09-01-u6a-apply-production.sql`, rehearsed both
ways before it was offered.

### The rollback was regenerated from production, and the local one was right

The 2026-08-30 baseline came from the **local** reproduction, so relying on it
would have made the rollback correct only if fidelity held — and fidelity is what
B-23 measures, never what it may assume. The same generator pointed at production
produced **zero differences** across all 33 policy statements and all 9 function
definitions. **The local file was correct all along, and that is now a
measurement.** The full rollback was rehearsed end to end locally and its proof is
not that the DROPs succeeded: **B-23 returned GATE MET on the rolled-back
instance**, which is structural identity with live production.

**`supabase db query` is SINGLE-STATEMENT.** It reaches production and its role
holds write as well as read — that is how the whole read-only pre-flight was done
— but it refuses more than one statement. Enough for the ten structural queries,
never enough for a migration. **The gap between "there is no path" and "the path
is single-statement" is where somebody improvises.**

### What U6a does NOT do

**Nothing consults membership for a decision**, no `account_directory` visibility
state is maintained (U6b), no worker exists and no cleanup runs (U7). **G11 PASSED AS A SCORED GATE ON 2026-09-01, 16 of 16 predictions with zero
falsifiers** — see `supabase/sql/README-g11-gate.md`. It is one of U6b's entry
conditions and it is now MET. **G4-B2 is the other, and it was restated the same
day: the shadow window is ONE-DIRECTIONAL — non-zero BLOCKS, zero can never
UNBLOCK — and the unblocking evidence is the 16-identity census, not the window.**
Neither is a U6a pass condition. A
window that observes grandfather-only decisions is a *successful* G4 and a
*blocked* U6b. **Device A's identity is pre-cutover**, so it cannot demonstrate
post-cutover behaviour on its own.

## U4 IS LIVE IN PRODUCTION — deployed and accepted 2026-08-20

**P0-P13 all executed and passed.** The schema and both Edge Functions are live,
the Sandbox notification URL is configured, B-23 returned GREEN after recapture,
and Apple's own test notification verified end to end. **U4 remains observe-only:
no policy consults membership, nothing is scheduled and nothing is deleted.** The
record is `supabase/sql/README-u4-deployment.md`; the evidence is in
`docs/qa-plan.md` under "U4 — PREDICTIONS AND RESULTS".

**207 local assertions pass** (25 route gate + 48 module + 94 SQL + 40
end-to-end), with U3's own suite re-running **93 of 93** underneath U4.

**The U4a gate settled the verification route empirically, and two obvious
choices were dead.** `node:crypto`'s `X509Certificate.verify` throws
`ERR_NOT_IMPLEMENTED` in the Supabase Edge Runtime, and
`@apple/app-store-server-library@1.6.0` **rejects payloads it should accept while
reporting its own runtime incapacity with the same status as a genuine forgery**
— deployed, it would have rejected 100% of real Apple traffic while the audit
table filled with rows that read exactly like an attack. The adopted route is
`@peculiar/x509@1.12.3`, exactly pinned with committed integrity metadata. **A
green endpoint and a dead verifier are the same observation from outside**, which
is why the gate is re-runnable rather than a recorded result.

**U4 CANNOT ESTABLISH MEMBERSHIP, AND THAT IS PERMANENT.** Corrected 2026-08-20:
the first revision let ingestion CREATE the initial `membership` row, inferring
`binding_method = 'purchase'` from the fact that `Set App Account Token` has not
shipped. **The reasoning was sound and the design was still wrong** — those
columns record *how ownership was proved*, and a value inferred from what has not
been built yet is provenance invented rather than established. The canonical
writer is now UPDATE-ONLY and there is **no `INSERT INTO public.membership`
anywhere in U4**, asserted structurally as well as behaviourally. A mapped,
complete notification with no authoritative row is recorded
`ignored`/`unestablished` and flagged for U5. **Ownership establishment is U5's
alone.**

**`service_role` still holds ZERO privilege on all six membership tables** — the
whole U4 privilege delta is four EXECUTE grants, the canonical writer is granted
to nobody, and the four were audited on 2026-08-20 and found minimal.

**Keep the two zero-row statements apart.** *Permanent:* U4 never originates a
membership row. *ACCEPTANCE-WINDOW PREDICTION, U4 before U5:* nothing maps at
all, because no Apple subscription carries an `appAccountToken` and no binding
exists to match. The second becomes false the moment U5 ships, by design;
reading it later as an invariant would make U5 look like a regression.

**Six findings were filed and five are DEPLOYED IN PRODUCTION: B-25** (derived
entitlement failed *into* scheduled cleanup when Apple omitted a field — every
renewal-info field is optional), **B-26** (`'duplicate'` was structurally
unwritable, so QA G2 asserted something no correct implementation could
produce), **B-27** (the outcome vocabulary conflated hostile traffic with the
highest-volume routine category), **B-29** (an unauthenticated durable write
primitive, now bounded to hours x categories), **B-30** (two RPC calls are two
transactions, proven at 20888/20889). **B-28 IS NOW RESOLVED — U4i, 2026-08-20.** Apple's own
test notification verified through the deployed path and landed in
`membership_notification` as `TEST`/`ignored`/`not_applicable`, with the Tier-2
reject aggregate still **empty**. **Where the row landed is the proof, not that
one did:** a dead verifier would have put it in the reject aggregate while the
endpoint still looked healthy from outside.

**QA G2 was amended and the reasoning outlives it:** structural reject 400,
signature failure **5xx**, verified-and-durably-handled 200. The old "answer 200"
assumed a failing payload was never valid; the catastrophic case is a verifier
that rejects everything, and 5xx buys production's five retries over 72 hours to
fix it. Sandbox never retries either way.

## U5f — NEW JOIN FLOW AND ATTESTATION ORCHESTRATION. 2026-08-23

**The first product-visible U5 unit.** No server surface changed. 12 unit tests,
47 structural assertions, both builds clean.

**The sequence is now** Explore Connected -> SIWA -> `ensure_membership_binding()`
-> purchase with `.appAccountToken(bindingToken)` -> `.verified` -> attestation.
**THE BINDING TOKEN IS A HARD PREREQUISITE OF THE PURCHASE**, enforced by the
type: `purchase(_:appAccountToken:)` takes a non-optional `UUID`, so an unbound
call does not compile. **An already-authenticated member sees no extra step.**
Solo remains entirely account-free.

**Corrected 2026-08-23. The first revision allowed an unbound purchase when the
token could not be fetched, and the reasoning — "refusing would turn a
recoverable hiccup into a lost sale" — was wrong twice over.** It overstated the
cost: StoreKit is never reached, so no money moves and nothing is lost but a
second tap. And it understated the consequence: **the legacy-claim path's whole
safety argument is that its population is FINITE AND SHRINKING**, which is why
F3's residual risk is acceptable. Minting new members into it makes that
population unbounded and permanent. **The legacy path serves subscriptions that
PREDATE bound purchase; it is not a fallback for new ones**, and it is otherwise
unchanged.

### The trigger invariant, and the assertion that protects it

Six triggers — launch, foreground, entitlement resolving, identity arriving,
purchase, restore — all routed through one coordinator so the invariant lives in
one place: `locally entitled ∧ hasConnectedIdentity ∧ BackendConfig.isConfigured`,
**and nothing else**.

**`C5f-12` parses `MOTIVOApp.swift` and asserts no `attestIfNeeded` call sits
behind a `canViewFeed` guard.** This is the most load-bearing client assertion in
Phase 3: gate attestation on Connected already being active and **the member the
mechanism exists to rescue can never reach it** — the dormant pre-cutover
subscriber is in Solo *precisely because* the server does not know them yet.
G11 would fail silently and forever.

**Duplicate suppression is single-flight plus a 30-second cooldown, IN MEMORY
ONLY.** Persisting it would make the client authoritative over server membership
— invariant 3 — and would defeat G11, whose recovery depends on a cold launch
attesting again. A previous success is never permanent authority.

### F10 — a verified purchase is a completed purchase

`ConnectedMembershipStore` used to return **`.failed`** when a `.verified`
transaction's entitlement had not surfaced by the time the refresh returned.
**Apple had taken the money and the app said "Purchase unavailable"**, inviting a
second purchase. That branch is gone and its error case is kept as a gravestone
with no caller.

After a successful purchase the member is told **nothing** in the common case.
Only two situations earn a word: **propagation** ("Finishing setup — this
completes on its own, no action needed") and **unresolvable** conflict or
terminal refusal ("Your purchase is safe. Please contact support"). A unit test
asserts the pending copy contains none of *fail, error, unavailable, try again,
retry, refund, lost* — **F10 as an executable assertion rather than a style
note** — and that the unresolvable cases never say "try again", because the
member cannot fix them alone.

---

## U5e — CLIENT PLUMBING AND F6. NO TRIGGERS WIRED. 2026-08-23

**Two services and one correctly-named session helper. The user-visible flow is
untouched** — asserted, not promised: `C5e-25` pins that
`MembershipSelectionView` still knows nothing about `appAccountToken`, and
`C5e-24` that `MOTIVOApp` wires no attestation trigger. **SIWA-before-purchase
remains U5f.**

- **`MembershipBindingService`** — asks the server for this identity's
  `appAccountToken` and hands it back. **There is no `UUID()` in the file**
  (`C5e-11`): a client-minted token would be a value the server never issued, and
  binding a real Apple subscription to one puts a fabricated identifier at the
  centre of the ownership protocol.
- **`MembershipAttestationService`** — collects a `.verified` JWS, POSTs **only**
  the JWS, and reports what the server decided. **It decides nothing about
  product mode**: `AppMode`, `canViewFeed` and `isConnected` appear nowhere in
  either service (`C5e-13`), and `isLocallyEntitled` is a PARAMETER so the
  service cannot reach into entitlement state and reacquire a mode dependency.
- **An unrecognised 200 is `serverError`, never success.** Guessing that an
  unknown outcome means "established" is how a client starts believing it is a
  member on evidence nobody produced.

**The JWS is treated as what F3b proved it is.** Under P2 it stays valid for the
life of the transaction, so a leak is permanent rather than expiring in minutes.
The service holds **no mutable state at all** (`C5e-7`), never logs, never
persists, never caches, and builds exactly one request body carrying exactly one
key (`C5e-8`/`C5e-9`).

### F6 — resolved by naming, not by reuse

`ensureValidSession` is gated on `BackendEnvironment.shared.isConnected`, which
is right for feed refresh and **wrong for attestation**, whose invariant is
`(locally entitled ∧ hasConnectedIdentity)` and which must run while the visible
experience is Solo. **The behaviour already existed and only under a misleading
name** — `ensureValidSessionForConnectedAccountCleanup` is mode-independent but
names a *caller's motive*, which is exactly the defect C-25 was filed for.

So that body is now **`ensureValidBackendSession(reason:)`**, and the cleanup
function is a **thin alias** over it — provably identical rather than similar,
which keeps C-44/C-45's reasoning findable by its own name. `ensureValidSession`
keeps its guard, so no existing caller changes (`C5e-18`). The new helper
deliberately **does not sign anybody out** on an unconfigured backend: a liveness
helper that can revoke a session is the wrong shape for a path that runs on every
foreground.

### C-54 — RESOLVED 2026-08-23. The seven tests now execute and pass

**It had TWO stale references and only the first was visible.** `TEST_HOST`
named `MOTIVO.app/MOTIVO`; once corrected, the build got *further* and failed on
`@testable import MOTIVO`, because the app's Swift module is **`Etudes`**.
**Neither had ever been reached, for the same reason — the target could not be
built at all, so its second defect hid behind its first.**

All seven U5e tests now run **normally, with no command-line override**, and are
named individually in the log. The project delta is **4 lines, all `TEST_HOST`**,
with zero UI-test references. **U5e's tests are evidence now**, where the U5e
record correctly said they were not.

---

## U5d — `membership_attest_v1`. LOCAL ONLY, NOT DEPLOYED. 2026-08-23

**B-24's protocol, end to end:** authenticated identity -> claim-checked client
JWS -> live Apple read -> token comparison -> atomic establishment. One Edge
Function and one `config.toml` entry; **no SQL**, so the B-23 delta is unchanged
at 20 — exactly U5b's. **469 assertions green.**

**Authorisation is `verify_jwt = false` plus our own `auth.getUser`**, stricter
than the gateway: the identity comes from the verified session, never the body,
and the body carries exactly one field. Not to be confused with
`appstore_notifications_v1`, which is genuinely unauthenticated because Apple
sends no JWT.

**The endpoint never calls `verifyAppleJWS`** — client input goes through
`verifyAttestationJWS`, Apple's responses through `readAuthoritativeState`, both
in `_shared`. **That was a deliberate design choice to make B-31's requirement a
one-line structural assertion** rather than a reviewer's judgement about which
variable reached which call.

### A30's LOCAL half is discharged, and it is an ORDERING proof

Observed outbound log for the legacy claim: **`GET, PUT, GET, GET`** — read,
Set App Account Token, independent re-read, authoritative re-read before
establishing. Asserted three ways, including that the call *immediately* after
the PUT is a read. **A correct row reached in the wrong order FAILS**, which is
the only way to test a rule whose violation produces an identical row. **The
genuine-Apple half remains outstanding.**

**The conflict path never issues the PUT at all** (E5d-36). Apple would happily
let us overwrite another identity's token; that is precisely why our rule has to
be the protection, and the endpoint never even asks.

**Propagation returns `pending` with `wrote:false` and no row**, and a later
attestation completes it **without a second PUT**.

### Three structural assertions failed on a CORRECT file, for the second time

They searched raw source text, and the endpoint's own header says "THIS FUNCTION
NEVER CALLS verifyAppleJWS" — **the file explaining the rule defeated the check
for the rule.** `U5c-34` had the identical shape one unit earlier. **A
source-text assertion must target code, and a well-commented file is exactly the
one most likely to defeat it.**

### A cross-suite state leak the sequence caught

Two assertions counted `public.membership` **globally**; they passed standalone
and failed after `acceptance.sh` left six rows. **A suite that only ever runs
alone can carry an assertion that is silently order-dependent.**

### The labelled U5 stand-ins are retired from both U4 suites

They now call the real `membership_establish_v1`, so U4 refreshes a row the real
writer established rather than one the test manufactured.

---

## B-24 IS RESOLVED — B-24n AND F10 ON GENUINE APPLE, 2026-08-30

**The bound-at-source half, and with it every reason B-24 listed for staying
open.** Those reasons were: the endpoint not deployed, no client existing to
present a JWS, and everything verified only against a faithful local
reproduction. All three are now false. The row closed on its own stated
condition — *"this row closes when the protocol runs for real, not when its
server half compiles."*

A U5f purchase on a **fresh Sandbox tester**, carrying `.appAccountToken`,
established `binding_method = 'purchase'` on a new `originalTransactionId`, with
`pending_cleanup_at` and `entitlement_ended_at` both NULL, `connected_member()`
false, `membership_state()` `sandbox_only`, and the conflict table empty. **All
eight committed predictions matched and nothing was repaired forward.**

**`'purchase'` PROVES AN ABSENCE.** Provenance is derived, never supplied, so
that value is written only when the client's own Apple-signed JWS already
carried our stored token — which means the legacy branch was never entered and
**no Set App Account Token PUT was issued at all**. There is no other way to
observe a call that did not happen.

### The binding row was never touched, and a different Apple Account bought it

```
binding_created_at : 2026-08-25 17:31:54.005854+00
binding_updated_at : 2026-08-25 17:31:54.005854+00   -- IDENTICAL
```

`binding_rows = 1` alone would have been satisfied by deleting the old row and
minting a new one. **The identical timestamps exclude that**, so one unchanged
token survived a legacy claim, eleven renewals, a cancellation, a genuine expiry,
deletion of the membership row, **a change of Apple Account**, and a fresh
purchase. **Two Apple Accounts, one Études identity, one token, two
`originalTransactionId`s** — which measures rather than argues the settled claim
that the token is an attribute of the IDENTITY, not of a subscription, and is the
part no local reproduction could have shown.

### The race produced an assertion nobody scheduled

`SUBSCRIBED`/`INITIAL_BUY` landed **`ignored`/`unestablished`** at 14:58:15 — a
predicted pass, with delivery beating attestation. `unmapped` would have
falsified B-24n; `unestablished` means the binding matched **on the first
notification of the subscription's life**.

**So the membership row came from attestation, not from ingestion**, and U4's
UPDATE-ONLY rule — the correction of 2026-08-20 — was exercised **against genuine
Apple traffic** in exactly the window where a writer that originated rows would
have had to invent `binding_method`.

### F10 passed on its strongest branch

**The app said nothing and Connected activated.** Only propagation and
unresolvable refusal earn a word, and neither arose. The inverse — Apple taking
the money while the app says "Purchase unavailable" — is the defect F10 removed.
**No sign-in step appeared**, so U5f's "an already-authenticated member sees no
extra step" holds on device.

### What this does NOT close

**Nothing consults membership.** Zero policies enforce it, no worker exists, no
cleanup runs, Production ASSN is still unset and attestation is Sandbox-only.
Membership is now *established* authoritatively and is still *read by nothing* —
which is C-26, B-11 and C-31, and unchanged by any of this.

---

## S-1, S-2 AND S-3 DISCHARGED ON GENUINE APPLE SANDBOX — 2026-08-25

**The first evidence in this project that is not "verified against a faithful
local reproduction".** Real device, real Sandbox subscription, Apple's servers,
the deployed endpoints.

**S-1.** A genuine `currentEntitlements` JWS passed the **pinned Apple Root CA
G3** and the full claim boundary. Attestation fired **unattended on the first
cold launch** — the invariant holding, nothing else gating it. This is the half
no local fixture could supply: every local payload is signed by a throwaway CA,
so a dead verifier and a healthy one look identical until real Apple bytes pass
the shipping anchor.

**S-2.** The legacy claim established `binding_method = 'legacy_claim'`, and
**the row itself evidences the `GET -> PUT -> GET` ordering**: that provenance is
written only when the client's JWS carried no token AND Apple reports ours — both
true at once means the PUT happened and an independent re-read confirmed it
before establishment. `pending_cleanup_at` and `entitlement_ended_at` both NULL,
so F11 held on real Apple state.

**S-3 — THE SINGLE ASSERTION THAT PROVES THE WHOLE PROTOCOL.** A real
`DID_RENEW` arrived 47 minutes later and ingested as **`applied`**. **14
notifications for this tester are `ignored`/`unmapped`; exactly one is
`applied`** — same subscription, same `originalTransactionId`, same endpoint, and
**the only thing that changed between them is the binding**. Apple carried our
token into a genuine renewal, which is what B-24 predicted and what no stub can
demonstrate.

**D4 confirmed on real Apple state:** `connected_member()` **false**,
`membership_state()` **`sandbox_only`**, on a live entitled Apple-verified
Sandbox membership.

**Two incidental observations.** Apple **reused** `originalTransactionId` across
lapse-and-resubscribe — evidence on a question this file deliberately leaves
open, and **not** licence to depend on it. And Sign in with Apple returned the
**same `sub` after the credential had been manually revoked**, re-authenticating
the 2026-08-15 identity rather than minting a new one; `auth.users` did not grow.

**THE FIXTURE'S ORDER DID NOT MATTER, AND THAT IS WORTH KNOWING.** The purchase
was made on the pre-U5f build and SIWA completed *afterwards*. Binding requires
`ensure_membership_binding` plus Set App Account Token, and that build has
neither — so the subscription was token-less regardless, which **Apple itself
confirmed** by landing the `SUBSCRIBED` notification `ignored`/`unmapped`.

---

## U5 IS LIVE IN PRODUCTION — deployed and accepted 2026-08-23

**P0-P8 and P6b all executed and passed.** The U5b schema, `membership_attest_v1`
and the corrected `appstore_reconcile_v1` are deployed; B-23 returned **GATE MET**
with only the standing `account_id_format` exception. **Every predicted number
matched production exactly and nothing was repaired forward.** The record is
`supabase/sql/README-u5-deployment.md` §8.

**U5 REMAINS ENFORCEMENT-FREE AND CLEANUP-FREE, PROVEN RATHER THAN STATED:**
zero policies consult membership (33 unchanged), zero rows carry
`pending_cleanup_at`, `service_role` holds **no** table privilege on any
membership table, and **exactly one function** inserts into `public.membership`.

**The client-reachable surface is one argument-less function.**
`ensure_membership_binding()` is executable by `authenticated` **only** — anon,
`service_role` and PUBLIC all false. `membership_establish_v1` is `service_role`
only. **U4's canonical writer stays internal.** No client parameter can supply
ownership provenance.

**B-31 VERIFIED IN THE DEPLOYED BUNDLE**, not merely the tree: the downloaded
`membership_attest_v1` contains five `verifyAttestationJWS` references and
**zero** `verifyAppleJWS(` calls.

**B-32 RESOLVED ON REAL EVIDENCE.** The same Apple Notification History call that
returned a structural `0` at pre-flight now returns **14 with
`unverifiable_items: 0`**, and Apple's uuid set and ours are **identical** — zero
lost, zero unexplained. **G3's instrument works now**; G3 itself stays open,
because its deliberate-drop recovery half has not been run.

**THE UNSCOPED RE-VERSIONING IS CAUSALLY ATTRIBUTED AT LAST, AND IT IS NOT THE
DEPLOY.** `supabase secrets set` moved all four functions' versions with **every
SHA unchanged**; the subsequent `functions deploy` moved **only the two named**.
U4 named this as a hypothesis; this run separated the two actions and settled it.

**`membership` HOLDS ZERO ROWS AND THAT IS CORRECT** — no client build carrying
U5e/U5f exists on any device, so nothing has attested. **The U4-era "zero rows"
prediction stops being an invariant the moment a device attests, by design.**

---

## U5c — ATTESTATION SUPPORT. LOCAL ONLY, NOT DEPLOYED. 2026-08-23

**Two modules and nothing else** — `_shared/appstore/attest.ts` new, `api.ts`
extended. No SQL, no Edge Function, no client change; the B-23 delta is
**unchanged at 20 problems**, identical to U5b's, which is how "U5c added no
schema surface" is checked rather than asserted. **406 assertions green.**

### B-31 closed in implementation — the claim boundary exists

`verifyAppleJWS` is **untouched** and still answers exactly one question, "did
Apple sign these bytes", because U4's notification path depends on that and
nothing else. The client-supplied path gets its own entry point,
`verifyAttestationJWS`, which enforces bundleId, environment, product, Family
Sharing and `originalTransactionId` **after** signature verification.

**Every hostile fixture is VALIDLY APPLE-SIGNED.** That is what makes the suite
meaningful: if a claim check regresses, a stranger's genuine subscription does
not start failing elsewhere — it starts being **accepted**.

**Revocation is deliberately NOT checked.** The JWS answers *who*, never *now*;
that is B-24's split and F3b's P2 is why it has to be.

**No freshness window, and `U5c-9` is what stops one being reintroduced:** a
year-old JWS must verify, because that is G11's dormant pre-cutover subscriber.

### A defect was introduced and caught by the battery rather than by review

**Apple's Set App Account Token answers 200 with an EMPTY BODY**, and `request()`
enforces "a 200 we cannot parse is not an answer" — right for every read
endpoint, **wrong for a write endpoint that returns nothing**. As first written,
every *successful* token assignment would have thrown `malformed`: the legacy
claim would have failed 100% of the time while Apple accepted every call, and it
would have looked like an Apple problem. Fixed with an explicit `allowEmptyBody`
on the one endpoint that needs it; the general rule is untouched because the
general rule is right. **A safety rule inherited from read paths can be a defect
on a write path, and "it threw" is not the same as "it failed".**

### The re-read is a code path now, not a rule somebody remembers

`setAppAccountToken` returns **void**, so a 200 cannot be mistaken for
confirmation. `observeAppAccountToken` does a fresh authoritative read and
verifies the nested JWS in its own right against the pinned anchor.
`interpretObservation` names four outcomes, and **`propagating` — found, but our
token not visible yet — is explicitly NOT failure**: write nothing, retry on a
later attestation. P12 already proved Apple-side propagation is real and
indistinguishable from misconfiguration while it lasts.

**Apple's five terminal error codes were READ FROM APPLE'S REFERENCE on
2026-08-23, not inferred from their names:** `4000006`, `4000048`, `4000183`,
`4000185` (Family Sharing), `4000187` (not the original transaction id), and
`4040005`. Terminal means record and stop; anything unrecognised is **retryable**,
because failing closed would permanently refuse a legitimate owner over an Apple
error we have not met yet.

---

## U5b — SQL FOUNDATION. LOCAL ONLY, NOT DEPLOYED. 2026-08-23

**Unit lettering settled, because the record had drifted into two meanings.**
U5a's subdivision called U5b the `_shared/appstore` work while D4's agreed text
said the predicate semantics "land in U5b". Resolved 2026-08-23: **U5b is the SQL
foundation, U5c is `_shared/appstore`, U5d is the attest Edge Function.**

**What U5b contains:** `connected_member()` and `membership_state()` replaced
with D4's semantics; `membership_establish_v1`, the only INSERT into
`public.membership` anywhere; `membership_binding_conflict`, bounded; and **two
grants, which are the entire privilege delta** — `ensure_membership_binding()` to
`authenticated` (the grant U3 created the function for and deliberately withheld)
and `membership_establish_v1` to `service_role`.

**What it does not contain, and this boundary is enforced rather than promised:
it CANNOT perform a legacy claim or an orphan rebind.** Both need Apple's
Set App Account Token plus an independent re-read, an HTTPS round trip that must
never sit inside a transaction (B-30). Both paths return `requires_claim`.

**A30 IS NOT DISCHARGED BY U5b AND MUST NOT BE RECORDED AS IF IT WERE.** What is
asserted is the SQL-side precondition only — that establishment REFUSES on a
token Apple has not confirmed as ours, so the claim path cannot be
short-circuited in the database. The assertions are labelled `A30pre*` so the
distinction survives a skim. **A29 and A31 ARE discharged in full**, because both
are decisions the database makes on its own evidence.

**338 assertions green** — U3 97, U4 48+95+43, U5b 55.

### The blast radius was under-predicted, 4 against an actual 11

The four named — A47i, A53b, A54d, E17 — were exactly right. **Seven were
missed**, all of them assertions pinning the *privilege surface* and *object
counts*: U3's A4, A3h and A22b, and U4's A41, A45, A45e and A47f. None is a
defect and none was weakened to pass; A45e had literally been written as
"ensure_membership_binding still ungranted **(U5)**", anticipating this change.
**The lesson: "which assertions change their RESULT" is a different question from
"which assertions mention the thing I am changing", and only the first one
matters.** Three were made stricter rather than merely re-pointed — A4 now pins
*exactly which* object is client-reachable, A22 splits the binding RPC out of an
aggregate that could have passed on either role's success, and A47f excludes
U5b's writer by name so it still fails if U4's writer ever gains an INSERT.

### PREDICTED B-23 DELTA, and U5b IS NOT PURELY ADDITIVE

Measured against the committed production snapshot: **columns +7, constraints
+5, rls_enabled +1, functions +1 new and 2 MODIFIED, function_grants +3 new and
1 MODIFIED.** `table_grants`, `column_grants`, `policies`, `triggers` and
`storage_buckets` all **IDENTICAL** — so U3's A3f invariant survives, no policy
consults membership, and the entire client-reachable surface U5 creates is one
argument-less function.

**Like U4, and unlike U3, this modifies deployed objects rather than only adding
to them** — two function definitions and one grant row — so the deployment
package's rollback cannot be "drop what was added". The gate correctly reports
**GATE NOT MET, 20 problems** pre-deploy, every one a U5b object; it returns
GREEN after deploy and recapture, as U4's did. **The `account_id_format`
constraint pair in the raw diff is NOT U5b's**: it is the single declared
standing exception, and counting it would overstate the delta by one.

---

## U5a — GATE UNIT. F1 CORRECTED; F3b EXECUTED AND SCORED P2. 2026-08-20

**U5a is a gate in U4a's sense: a re-runnable experiment plus a correction, not
an implementation.** No SQL, no Edge Function, no client protocol, no deploy.
U5b onwards has not begun.

**THE U5 AUDIT IS ACCEPTED AND D1-D9 ARE AGREED**, with **D4 decided against the
audit's own proposal and the proposal rejected outright** — see below. Twelve
architectural decisions are now settled and binding on U5's implementation:

- **Establishment NEVER schedules cleanup.** `pending_cleanup_at` stays NULL on
  every insert path, unconditionally. Scheduling is a *transition* from entitled
  to not-entitled and an establishment has no previous state to transition from
  — the same reasoning as "absence of a membership record can never schedule
  cleanup", one level down. Without this rule U5, the unit explicitly free of
  enforcement and cleanup, becomes the unit that can schedule destruction of a
  returning member's Connected content on first contact. **The born-lapsed case
  is therefore left explicitly open for U7 rather than silently resolved.**
- **`ignored`/`unestablished` notifications are HISTORICAL EVIDENCE, not a
  queue.** Establishment performs its own live authoritative read, which
  supersedes whatever the notification carried. Do not build a consumer; do not
  read `needs_establishment` as a work item.
- **A separate `APPLE_ATTEST_ALLOWED_ENVIRONMENTS`**, never reuse
  `APPLE_ASSN_ALLOWED_ENVIRONMENTS`. Same reasoning that keeps
  `APPLE_IAP_BUNDLE_ID` separate from `APPLE_CLIENT_ID`: they hold the same value
  today and mean different things, and coupling them means a future notification
  change silently alters attestation.
- **Attest `.verified` transactions only.** The server re-verifies regardless, so
  the local filter costs nothing real.
- **`ensure_membership_binding()` may be granted to `authenticated`** — the one
  client-reachable membership object U5 creates, and the narrowest the design
  admits: no argument, identity from `auth.uid()`, idempotent, at most one row
  per `auth.users` row.
- **F2 claim binding is MANDATORY** — see B-31.
- **`membership_state()` gains a fifth value, named `sandbox_only`** (agreed
  2026-08-20). Not cosmetic: without it a Sandbox-only identity reports
  `'expired'`, which is false and makes a tester indistinguishable from a member
  whose Production subscription lapsed — corrupting the metric U6a's shadow reads.
- **The Production/Sandbox predicate semantics land in U5b, not U6** (agreed
  2026-08-20). Nothing reads `connected_member()` until U6, so it *could* wait —
  but U5 creates the first membership rows, and shipping a predicate that would
  mis-derive them leaves U6 a landmine. The suites are being touched for U5
  anyway, so the four affected assertions are re-pointed in the same pass.
- **E17 is rewritten to assert the Sandbox ROW rather than Production
  entitlement** (agreed 2026-08-20). It cannot be re-pointed: ingestion applies
  state to the row of the notification's own environment, so no Sandbox
  notification can ever produce entitlement under the new semantics. Asserting
  the row is what `e2e.sh` is for by its own description — entitlement derivation
  belongs to `acceptance.sh`.
- **D3, decided from the F3b measurement: no freshness window and no one-time
  consumption on the transaction JWS.** See the F3b section below.
- **Sign in with Apple BEFORE purchase, for every new Connected join** (D2,
  confirmed 2026-08-20). Forced rather than chosen: the binding token must exist
  before `product.purchase()` can carry it. **This inverts the shipping flow** —
  `MembershipSelectionView` currently purchases and *then* presents the sign-in
  sheet — so it is a product-visible change, not a refactor. **Solo remains
  entirely account-free**; only *joining* Connected requires authentication.
- **`Set App Account Token` handling has four parts and all four are settled**
  (2026-08-20). (i) **Terminal, non-retryable handling** for Apple's permanent
  refusals — `FamilyTransactionNotSupportedError`,
  `AppTransactionIdNotSupportedError`,
  `TransactionIdIsNotOriginalTransactionIdError`. (ii) **A successful call is NOT
  sufficient evidence on its own.** (iii) **Re-read Apple, and establish only
  once the token is actually observed on the subscription.** (iv) **A re-read
  that does not yet show the token is PROPAGATION, not failure** — write nothing
  and retry on a later attestation. Attestation runs every foreground, so a
  legacy claim completing on a second pass is invisible to the user, and P12
  already proved Apple-side propagation looks exactly like misconfiguration.

### F1 is corrected, and the correction is verified rather than asserted

**C-52.** `0daecd1` (2026-08-14, a commit about B-6) silently reverted the Run
action to Debug and re-pinned `Etudes.storekit`, undoing `67d64f0`'s deliberate
change and contradicting two standing statements in this file for six days.
Restored 2026-08-20. **The restored scheme is byte-identical to `67d64f0`'s
version — same blob `013cc35`** — so it is provably back to the deliberate state
rather than hand-edited to resemble it, and `xcodebuild -showBuildSettings`
confirms the Run action's Release configuration resolves
`PRODUCT_BUNDLE_IDENTIFIER = com.sdsongs.etudes` with no pinned StoreKit
configuration. Debug and Release both compile clean.

**The lesson is not "check the scheme".** It is that **a durable document
asserting a repository fact is not evidence of that fact** — this file said the
right thing throughout, was re-read many times, and was wrong the whole time.

### C-53 — `Etudes.storekit` no longer ships. Resolved 2026-08-20

**F1's fix was necessary and not sufficient, and this is the second route.**
Unpinning the scheme stopped Xcode *attaching* the configuration; the `MOTIVO`
synchronized root group was *compiling it into the app* the whole time, because
its `membershipExceptions` list named only `debug_upload_test.m4a`,
`debug_upload_test.mp4` and `Info.plist`. Someone had already met this mechanism
and excepted two debug media files; the StoreKit configuration was missed.

**One line, and the evidence is a measured delta rather than a rebuild and an
assurance:** the Release bundle inventory was captured **before** the change (15
items, file present) and after (14 items), and the diff is **exactly the removal
of `Etudes.storekit`**. Nothing else in the bundle moved. No Swift file changed;
no source loads that file at runtime; the product identifiers are untouched; the
exception is scoped to the app target so both test targets are unaffected.

**The file is retained on disk and is now genuinely opt-in** — which is what this
document has claimed since 2026-08-11 and what was not actually true until now.

**THE CAUSAL CLAIM REMAINS UNPROVEN AND UNMADE.** This fix does not establish
that the bundled file caused the Xcode-labelled purchase sheet, and TestFlight
build 131 is evidence against that simple story. **Do not let "C-53 resolved" be
read as "the Xcode-sheet question is answered."** What is resolved is that a
StoreKit configuration file carrying internal identifiers no longer ships inside
an App Store binary, which was defect enough on its own.

### F3b — EXECUTED ON DEVICE A, 2026-08-20. RESULT: **P2**. D3 is decided

**`Transaction.currentEntitlements` returns a STORED HISTORICAL representation,
not a freshly signed one.** `signedDate` is fixed at approximately the purchase
instant and does not move; identical `jwsSha256` across repeated reads, a
foreground and multiple cold launches over more than ten minutes, with `txID`
constant throughout so no renewal confounded it, and `env=Sandbox` so it is real
Apple rather than Xcode's test signer. Full scoring in `docs/qa-plan.md`.

**D3: NO freshness window, and NO one-time consumption.** A window is not merely
weak, it would **break G11** — a dormant pre-cutover subscriber returns holding a
JWS signed months or years earlier, and that is the exact case U5 exists to make
self-healing. One-time consumption fails differently: the legitimate client
presents the *same* JWS on every attestation, so consuming it would refuse the
owner's second call, and scoped narrowly enough to be coherent it adds nothing
`membership_transaction_unique` and the conflict rule do not already give.

**The residual is accepted explicitly and is narrow:** an attacker holding a
*legacy, token-less* subscriber's JWS *before that subscriber ever attests* can
bind it. Bounded by the transaction uniqueness constraint, the live-binding
conflict rule, the self-extinguishing legacy branch, and D2/U5f setting a token
at purchase so the exposed cohort is finite and shrinking. The owner's failure
mode is a **recorded refusal for operator disposition**, not silent loss.

**THE EVIDENCE VALIDATES THE THREE-ARTEFACT SPLIT RATHER THAN COMPLICATING IT.**
A permanently-stale artefact is precisely why the JWS may answer **who** and must
never answer **now**. Had the gate returned P1 it would have been tempting to let
a fresh JWS stand in for the live Apple read; P2 forecloses that, so B-24's
separation is now confirmed by measurement instead of by argument.

**Two rules tighten as a direct consequence.** The JWS is required **only on the
establishment path** — refresh afterwards runs server-side on the stored
`original_transaction_id` with no client artefact at all. And **U5 must never
log, store or echo a transaction JWS**: under P1 a leak would have expired in
minutes, under P2 it is valid for the life of the transaction, so the no-persist
rule is load-bearing rather than cautious.

### `Set App Account Token` — CONFIRMED against Apple's reference, 2026-08-20, with two corrections to the U5 audit

`PUT /inApps/v1/transactions/{originalTransactionId}/appAccountToken`, both
hosts. Confirms B-24 unchanged: Apple **replaces** an existing token on request,
so **Apple does not enforce the binding against us and our rule is the only
protection**. Also confirms the per-identity token model — the same token may be
assigned to many transactions.

**CORRECTION 1 — the legacy claim can be REFUSED BY APPLE for a reason the audit
did not model.** `FamilyTransactionNotSupportedError`: a transaction whose
`inAppOwnershipType` is `FAMILY_SHARED` **cannot ever** receive a token. Family
Sharing is off for both products, so this should not arise — but "should not
arise" is not "is handled". It is a **permanent** refusal, not a transient one,
and U5 must record it as such rather than retrying forever. `AppTransactionIdNot
SupportedError` and `TransactionIdIsNotOriginalTransactionIdError` are the same
shape: pass the *original* transaction id, never any transaction id, even though
`Get All Subscription Statuses` accepts either.

**CORRECTION 2 — the re-read may legitimately not show the token yet, and A30
must tolerate it.** Apple documents the update as applying to "the current
renewal transaction and all subsequent renewals" and **not to past
transactions**, and says nothing about read-after-write visibility. **P12 already
taught this project that Apple-side propagation is real and looks exactly like
misconfiguration** — two 404s with `4040007` on a notification URL that was
correctly set, succeeding later with no change to anything. So A30's "call Set
App Account Token, then re-read before writing membership" stands, but the
failure branch is **write nothing and retry on the next attestation**, never
"accept the 200 as sufficient". Attestation runs on every foreground, so a legacy
claim completing on the second pass is invisible to the user.

### D4 — DECIDED, AND THE FIRST PROPOSAL WAS REJECTED. 2026-08-20

**Production `connected_member()` means PRODUCTION ENTITLEMENT ONLY. A Sandbox
membership row must never make the production membership predicate return true,
and there is no exception mechanism inside the predicate.**

**U5a first proposed a `membership_sandbox_tester` allowlist that widened the
predicate per identity, with an expiry. IT WAS REJECTED AND THE REJECTION IS
RIGHT.** Even bounded and self-closing, it put a *shippable exception* inside the
one function that defines paid access — and the whole of B-24's lesson is that an
authority predicate must not contain a branch whose safety rests on operational
discipline. The QA need is real; **solving it inside the entitlement predicate
was the wrong place**, and the correct answer turned out to need no mechanism at
all (see below).

### The exact semantics — the environment test moves INTO `bool_or`, not into `WHERE`

**The naive fix is wrong and it is worth seeing why**, because it fails in the
direction that matters. Adding `and m.environment = 'Production'` to the WHERE
clause empties the row set for a Sandbox-only identity, `bool_or` over an empty
set is NULL, and the predicate **falls through to the grandfather clause** — so a
pre-cutover tester with a live Sandbox subscription would be granted Production
entitlement *by the compatibility clause*. That is the exact inversion of
invariant 8.

**The row set that decides EXISTENCE must stay wider than the row set that can
decide TRUE:**

```sql
(select bool_or(
     m.environment = 'Production'
     and (coalesce(m.renewal_date > now(), false)
          or coalesce(m.is_in_billing_retry
                      and m.grace_period_expires_date > now(), false))
   )
   from public.membership m
  where m.user_id = target_user_id)   -- NO environment filter here
```

- **Sandbox-only identity** → set non-empty, per-row expression FALSE → `bool_or`
  FALSE → **does NOT fall through** → false. Authoritative state wins over
  grandfathering, which is decision 2.
- **Production entitled** → true. **Production lapsed** → false, no fall-through.
- **No rows at all** → NULL → grandfather clause, unchanged.

**U3's coalesce lesson survives and is strengthened.** `environment` is
`NOT NULL`, and `false AND anything` is FALSE in SQL, so the row expression is
**strictly two-valued in every case** — `bool_or` is NULL if and only if there
are no rows, which is precisely the distinction the clause ordering depends on.

### `membership_state()` needs a FIFTH value, and it is load-bearing

Under the above, a Sandbox-only identity would report `'expired'` — which is
false. It has not expired; it has no Production membership at all. **U6a's shadow
window reads this function to report which clause would have decided a denial**,
so conflating "Sandbox-only tester" with "Production subscription lapsed" would
corrupt exactly the metric B-11's stage-2 gate depends on. The `exists` test
gains an `environment = 'Production'` filter and a new branch returns
**`'sandbox_only'`**. `'grandfathered'` becomes unreachable for any identity
holding any row, which is correct.

### Blast radius on the suites — FOUR assertions, not the thirty-seven first stated

**Corrected 2026-08-20.** The earlier figure counted *references* to
`connected_member` and `membership_state`, not assertions whose result changes.
Measured by reading the fixtures:

- **U3 acceptance: zero affected.** Every one of its `membership` fixtures is
  `'Production'`; its only two `'Sandbox'` literals are a
  `membership_notification` duplicate-key fixture that never reaches the
  predicate.
- **U4 acceptance: three flip** — A47i, A53b, A54d — all because the U5 stand-in
  row is inserted as `'Sandbox'`. Fixed by making that fixture `'Production'`.
- **U4 e2e: one, and it cannot simply be re-pointed.** E17 asserts entitlement at
  the end of a chain that is Sandbox end to end — the notification must be
  Sandbox to pass `APPLE_ASSN_ALLOWED_ENVIRONMENTS`, and ingestion applies state
  to the row *of the notification's own environment*, so no Sandbox notification
  can ever produce entitlement under the new semantics. **That is correct
  behaviour, not a test problem.** E17 should assert the resulting ROW rather
  than the predicate — which is what `e2e.sh` is for by its own description
  ("wiring: the right row, the right status code, the right absence of a write"),
  entitlement derivation being `acceptance.sh`'s job. E17 was testing the wrong
  thing in the wrong suite.
- **A28's wording** moves from "exactly the four states" to five.

### Sandbox QA needs NO entitlement mechanism at U5, and that is the whole answer

**U5's claims are about ownership establishment and binding. Not one of them
reads `connected_member()`.** S-1 (a real sandbox JWS passes the pinned anchor),
S-2 (Set App Account Token accepted and reflected), S-3 (the token survives into
a real renewal, so ingestion goes `unmapped` -> `applied`), and A29/A30/A31 are
all assertions about **rows** in `membership` and `membership_binding` and about
what the attest endpoint did. **The row is the evidence.** `connected_member()`
returning false for a Sandbox row is not an obstacle to U5 QA; it is irrelevant
to it.

**And the client is unaffected in the U5 window**, because `AppMode` resolves
from **local StoreKit** entitlement via `ProductionAppModeActivation.resolve`,
and no policy consults membership. A sandbox tester on Device A therefore reaches
the full Connected experience during U5 with **no mechanism at all**.

**So the minimum explicit QA mechanism now is: make `membership_state()` honest
(`'sandbox_only'`), and read the row.** Zero new tables, zero new grants, zero
exceptions in the entitlement predicate.

### The enforcement-path mechanism is DEFERRED TO U6b — and U6a is not the boundary

**Owned on B-11.** The need appears only when enforcement becomes *binding*, and
that is U6b, not U6a: **U6a is a shadow window by construction** — it records
which clause would have decided a denial and denies nothing, so a sandbox tester
is not blocked there either.

Deferring is not procrastination, it is the B-24 lesson applied: designing an
exception now means designing it against an enforcement surface that does not
exist, which is exactly how the original U5 activation design came to prove
authenticity while proving nothing about ownership. **At U6b the real options can
be weighed against the real surface** — a separate QA project, a Production
subscription bought for the purpose, or an explicit tester carve-out *outside*
the predicate — and U6b's gate already requires G11 passed and zero
grandfather-only decisions, so the tester population is enumerable by then.

**One thing U6a must carry from this decision:** a sandbox tester's would-be
denials must not be counted as evidence about real users in the shadow report.
`'sandbox_only'` is what makes that separable.

---

## U3 IS LIVE IN PRODUCTION — deployed and accepted 2026-08-17

**The schema is deployed and the cutover boundary is declared, verified and
irreversible. U3 remains inert: no policy reads it, no client role can reach it,
no Edge Function was deployed, no Apple request is made and no cleanup is
scheduled.** Executed as P0–P11 of `supabase/sql/README-u3-deployment.md`; the
full record with every observed value is in `docs/qa-plan.md`.

**The cutover facts U6b and U6c will need. No production UID is recorded here or
anywhere in the repository, deliberately.**

| Fact | Value |
|---|---|
| `cutover_at` | **2026-08-17 19:08:27.125223+00** |
| `cutover_identity_count` | **16** |
| `cutover_verified_at` | **2026-08-17 19:09:48.080684+00** |
| `grandfather_enabled` | `true` |
| `grandfather_expires_at` | `null` |
| `u6b_bound_at` | `null` — U6b has not run |
| Structural delta | **+90 additive rows, zero modified, zero removed** |

**`cutover_at` must never be redeclared or altered.** It is the definition of
"pre-cutover", and every later check — including U6c's removal rule — is stated
relative to it.

**Convergence passed on the first fresh snapshot** (`missing = 0`,
`null_created_at = 0`, `invalid_members = 0`), so the single permitted repair was
never needed and PHASE 2b never ran. **That repair belonged to the P6/P7
procedure alone and is now spent by completion, not held in reserve.** The
snapshot is verified. **Any later discovery of a qualifying-but-missing identity
is a NEW ANOMALY requiring investigation — never authority to re-run the
population.** The cutover file already says so in its own words: *"Either is a
stop-and-report, never a silent repair."*

**B-23's green gate does NOT prove the 16-row population, and must never be cited
as if it did.** The gate is **structural only** — it reads system catalogs and no
user table, so `membership_cutover`'s contents are invisible to it by design,
which is exactly what keeps production UIDs out of the repository. **The
population was verified separately**, by P4's in-transaction coherence
assertions, P6's post-commit convergence on a fresh snapshot, P8's
materialised = by_predicate = recorded agreement, and P11's re-verification of
the permanent invariant. Two independent claims, two independent proofs.

**The permanent invariant is re-runnable forever and both columns must always be
zero** — see the tail of `supabase/sql/2026-08-16-u3-cutover-population.sql`.
Verified zero at P8 and again at P11.

**`service_role` holds NO privilege on any membership table** — see "U3's
privileges are deterministic" below. U4 must grant what U4 needs.

**Phase 3 accounting at implementation entrance — four counts, deliberately
separate. Conflating them is how B-9's subcase went missing once already.**

| Count | Value | What it is |
|---|---|---|
| Phase-3-tagged register rows | **27** | Every row whose Phase cell contains a literal `3`. Was 10; **U6b's final P6 run filed C-59** (OPEN — a COVERAGE defect on the enforcement write-deny path, not a production defect); **U4 filed six — B-25 to B-30 — and resolved all six**; **U5a filed three — C-52, B-31, C-53 — and resolved two**; **U5e filed C-54** (Resolved); **U5g filed B-32** (Resolved); **the U6a gate filed B-33** (Resolved by U6a); **the U6a production shadow window filed B-34** (OPEN); **the 16-identity census filed B-35** (Resolved the same day); **the beta-cohort classification filed B-36** (Resolved the same day, by a product decision); **U6b's interrupted deny-path QA filed C-55** (**RESOLVED 2026-09-01** — a runaway SwiftUI re-render loop, not a navigation defect; unrelated to enforcement, as recorded). **Its Phase cell reads `4`, so it never entered this literal-`3` count — yet it was listed among the open Phase 3 obligations. That inconsistency predates this unit and is recorded rather than silently corrected, because the two counts are deliberately different questions and quietly aligning them would destroy exactly the distinction the table exists to preserve** |
| Open Phase 3 obligations | **2** | **C-31 and B-34.** **C-26 AND B-11 ARE RESOLVED 2026-09-02 BY THE FINAL U6 BIND** — enforcement is live and durable, bound at 15:30:20 under explicit human authorisation and NOT rolled back. **C-31 stays open on the Production App Store Connect Billing Grace promotion, deliberately NOT merged into C-26**, whose Billing Grace element is the server's support for the state (implemented, asserted by U6b E3/E4). **B-34 stays open as an OBSERVABILITY LIMITATION, never a blocker** — and was confirmed in production by this run, since the raising RPCs and the refused INSERT both left no telemetry while denying correctly. **C-59 WAS THE FIFTH AND IS RESOLVED 2026-09-02** — filed from U6b's final P6 run because the enforcement write-deny path had never been observed behaving, and closed by U6b acceptance group **L**: an unentitled author's INSERT refused as an RLS violation with no row landing, through the real policy path, with an entitled author succeeding under the same enforcement and the identical statement succeeding with enforcement off. **Scored on database outcome, never on telemetry.** The production-device observation remains unmade and always would have — that is **B-34**, which stays open on its own account. **C-58 was filed 2026-09-02 and is Phase 4, so it does NOT enter this count** — a bounded product/UX follow-up on follower attribution for a lapsed viewer, with the global fix explicitly rejected. **C-55 WAS THE FIFTH AND IS RESOLVED 2026-09-01** — the mechanism was a runaway SwiftUI re-render loop, **not** a navigation defect; two no-op guards removed it, no navigation code changed, and the fix was accepted on Device A against a scoring rule fixed before the run. **C-56 was filed by that investigation and is Phase 5, so it does NOT enter this count** — a coverage defect in the U6a metric, NOT a production defect. **B-35 was filed and RESOLVED the same day** — U6c's liveness check was keyed on `auth.users.last_sign_in_at`, which is blind to long-lived sessions and fails OPEN; corrected in both durable documents before U6c's clock has started. **B-33 was filed 2026-08-30 by the U6a gate and RESOLVED 2026-09-01 by U6a itself**, on both halves of its stated condition — the wrapper is deployed and the false sentence is corrected. **B-24 IS RESOLVED — 2026-08-30, by B-24n on genuine Apple** (was open through U4 and all of U5's implementation). **B-32 was filed and RESOLVED by U5g.** **B-31 was added by U5a and RESOLVED by U5d**; **C-54 was filed by U5e and RESOLVED the same day**; U5a also filed and resolved C-52 and C-53 |
| Backend-verification obligations | **0** | Was 4. **All four executed by U2.** B-24 is a design defect, not a verification |
| QA obligations with no register row | **9** | C5–C10, plus C2 and C3's recovery halves and C12's proxy half |

The twenty-two rows are **C-26, B-11, C-31, B-23, B-24, B-4, B-12, B-13, B-9,
C-9**, plus U4's six: **B-25, B-26, B-27, B-28, B-29, B-30**, plus U5a's three:
**C-52** (Resolved), **B-31** (Resolved by U5d) and **C-53** (Resolved), plus U5e's **C-54** (Resolved), U5g's **B-32** (Resolved) and the U6a gate's
**B-33** (Resolved by U6a, 2026-09-01).

**THE DENOMINATOR MOVED AND THE OPEN COUNT DID NOT, which is exactly the
distinction this table exists to preserve.** U4 added six rows and closed all six
in the same unit — five deployed and verified in production, and **B-28
discharged by Apple's own test notification** — so the arithmetic is 6 resolved
by U4, 6 previously resolved (B-23, B-4, B-12, B-13, B-9, C-9), 6 resolved after
U4 (C-52, C-53, B-31, C-54, B-32, B-24), and 4 open. **Do not read "U4 is done"
as reducing the open obligations: it never touched them.**

**The open-obligation arithmetic, shown rather than asserted.** Twenty-two tagged
rows, minus the eighteen resolved:

- **C-9** — Resolved 2026-08-12, in the denominator only because its phase cell
  contains a literal `3`, and owing Phase 3 nothing;
- **B-23** — Resolved 2026-08-16 by U1;
- **B-4, B-12, B-13** — Resolved 2026-08-16 by U2;
- **B-9** — its row was already Resolved, and U2 discharged the two-recipient
  subcase that was the only thing carried;
- **B-25, B-26, B-27, B-28, B-29, B-30** — all six filed AND resolved by U4;
- **C-52** and **C-53** — filed and resolved by U5a; **B-31** — filed by U5a,
  resolved by U5d;
- **C-54** — filed by U5e and resolved the same day; **B-32** — filed and
  resolved inside U5g;
- **B-24** — Resolved 2026-08-30, by B-24n on genuine Apple;

- **B-33** — filed by the U6a gate 2026-08-30 and resolved by U6a 2026-09-01;

= **2 open: C-31 and B-34.** **C-26 and B-11 were RESOLVED 2026-09-02 by the final U6 bind.** **C-59 was filed AND RESOLVED on 2026-09-02** — the only one that was a COVERAGE defect rather than missing capability or a metric gap, and the shortest-lived row in the register. **B-24 CLOSED ON 2026-08-30**, on its own
stated condition — *"this row closes when the protocol runs for real, not when
its server half compiles"* — with both branches now discharged against genuine
Apple: `legacy_claim` by S-1/S-2/S-3 and **bound-at-source by B-24n**. **B-32 was
filed and resolved inside U5g**, on real Apple evidence. **B-31 was resolved by
U5d** and **C-54 by the correction that followed U5e**.

**C-55 IS RESOLVED — 2026-09-01 — AND IT WAS NOT WHAT IT LOOKED LIKE.** The
symptom was "tapping a journal row does not open `SessionDetailView`"; the cause
was a **runaway SwiftUI re-render loop saturating the main thread**, which
starved the tap gesture. An `.onReceive` on the root scene body mutated state
that invalidated that same body, `@Published` re-delivered on every
re-subscription, and the handler re-entered each frame off
`CA::Transaction::commit`. **Measured on Device A's live process by read-only
`xctrace --attach`, not inferred.** The fix is **two guards, 18 added lines**,
each making an already-intended no-op actually be one — `setBackendMode` writes
only on a real change, `MembershipAttestationCoordinator.reset()` publishes only
when there is something to clear. **NO NAVIGATION CODE WAS CHANGED.** Device A
went from 4,418 backtraces in 12s to **zero samples** and the row now opens.
**Why Device B never exhibited it is UNKNOWN and does not block closure** — Device
A's arm predates any plausible Device B build, so "B is older" does not explain
it. **The leading hypothesis — two stacked `navigationDestination(isPresented:)`
modifiers — was FALSIFIED BY EXPERIMENT**, and the register already contained the
real mechanism, written down on 2026-08-11 as an observation about C-38.

**U6 IS CLOSED — 2026-09-02.** Enforcement is live, durable and denying; the
kill switch remains available and `u6b_bound_at` is never rewritten by it.
**BOTH REMAINING OBLIGATIONS ARE OUTSIDE ENFORCEMENT:** C-31 is an App Store
Connect configuration promotion, and B-34 is an observability limitation.
**U7 HAS NOT BEGUN and is the next unit** — no cleanup worker exists, and a
lapsed Sandbox row carries `pending_cleanup_at` that nothing acts on.

**HISTORICAL — the position before the final bind:**
**THREE OF THE FOUR WERE ENFORCEMENT AND CLEANUP, AND NONE OF THEM HAD BEGUN.**
**C-59 WAS THE FIFTH AND IS RESOLVED 2026-09-02** — the enforcement write-deny
path has now been watched denying, by database outcome rather than telemetry, so
the next enforcement bind is no longer preceded by an unobserved write path.
**B-34 is the fourth and is a different shape — it is a defect in what the U6a
window can SEE, not in what production does.** Do not
read B-24's closure, or U6a's deploy, as progress against them. Membership is
*established* authoritatively and is now *observed* by 23 policies — and **still
nothing consults it for a decision**. Zero policies enforce it, no worker exists,
no cleanup runs. That gap is exactly C-26, and **U6a was built to leave it
exactly where it was**: G4-S2 proves row counts identical with the observer
attached and detached, which is the honest form of "enforcement has not begun".

**B-33 WAS THE FOURTH AND IT IS RESOLVED — 2026-09-01, by U6a.** It was never a
missing capability; it was a **wrong sentence in a deployed migration's comment**
that U6 would have implemented from, carrying no production defect at all —
U3's revokes are correct and the schema needed no change. **It had two halves and
both are now done:** `connected_member_self()` is deployed, zero-argument,
`SECURITY DEFINER`, granted to `authenticated` only, and consulted as
`(select …)` in all 23 policies with **zero bare calls in production**; and the
U3 migration comment is corrected in place, **with the false sentence quoted
rather than deleted**, because the thing to recognise is a claim that is
correct-sounding and unfalsifiable by reading. The same correction is applied to
U3 acceptance's `A3h`, whose comment restated it. **`connected_member(uuid)` and
`membership_state(uuid)` remain ungranted to every client role**, so the
membership oracle stays structurally unbuildable.

**The backend-verification count went 4 → 0, and that is a different statement
from the row arithmetic.** B-23 was never a fifth member of it — it was their
prerequisite, so discharging B-23 unblocked them without reducing the count, and
only executing them reduced it. **B-9 is the standing reminder that the two
counts are not the same thing:** its row is *Resolved* while still carrying an
outstanding verification, which is exactly how its subcase went missing once
before. Never sum these numbers.

**Everything U2 verified carries its evidence level in the cell: *verified
against a faithful local reproduction*, never *verified in production*.** That
qualifier is part of the disposition, not a footnote, and the residual gap — a
local stack is the same software but not the same deployment — is stated rather
than glossed.

---

## Operational starting state — confirmed 2026-08-16

**Observed directly in App Store Connect by the account holder**, not inferred.
This is the baseline every S-step and every Group C gate starts from.

| Setting | State | |
|---|---|---|
| **Billing Grace Period** | **ENABLED — 16 days, All Renewals, Only Sandbox Environment** | **S1 done 2026-08-16** |
| Production Billing Grace | **Untouched** | Until its later authorised step |
| Production notification URL | **Unset** | Until its later authorised step |
| Sandbox notification URL | **SET — the deployed `appstore_notifications_v1` endpoint** | **S2b DONE 2026-08-20.** Apple's own test notification verified through it |
| In-App Purchase key | **1 active**, `Etudes App Store Server API` | **S2a done 2026-08-16** |
| Account access | **Account Holder + Admin** | Sufficient for every S-step |

**S1 is configured, not yet relied upon.** Apple's change takes **up to 24
hours** and applies only to *upcoming* renewals, so the propagation window must
elapse before any grace-dependent lifecycle QA (G6b) is run or scored.

**S2a's private key is stored outside the repository** at `~/.etudes-secrets/`,
downloaded once as Apple permits only one download. The SIWA `.p8` remains
separate and untouched — it is a different key type for a different purpose and
cannot authenticate App Store Server API requests. **The runtime Supabase
secrets are NOT yet installed**; that belongs with U4, which is the first unit
that needs them. **Key ID and Issuer ID are deliberately not recorded here** —
they are needed at runtime from Supabase secrets, and there is no technical
reason for the repository to be a place where Apple credentials live.

**Both notification URLs remain unset, which is the safe state, and it is worth
knowing why.** Apple's rule is that if a *Production* URL is set and a Sandbox
one is not, the App Store sends **both** environments' notifications to the
production URL. With neither set, nothing is delivered anywhere and no
configuration can be silently receiving sandbox traffic. **Production stays
unset**, which also means no production notifications are sent — intended until
the later authorised phase.

**No In-App Purchase key exists**, and the four `APPLE_SIWA_*` secrets are **not**
a substitute: those are a Sign in with Apple key, a different key type for a
different purpose. Server→Apple reconciliation needs its own.

### Accepted sequencing before U4's first purchase

**Refined 2026-08-16 from the operational-readiness pass, and it differs from the
order originally written.** Two moves, each forced by a real dependency.

```
S2a  create + store the In-App Purchase server key
 ->  S1   enable Billing Grace, SANDBOX ONLY
 ->  U3   membership schema, inert
 ->  U4   ingestion endpoint implemented and DEPLOYED
 ->  S2b  configure the SANDBOX notification URL (V2) to that deployed endpoint
 ->  test notification
 ->  first Sandbox lifecycle purchase
```

**Why S1 moved earlier.** Billing Grace takes **up to 24 hours** to take effect
and applies only to *upcoming* renewals. Enabling it close to a run means the
first sandbox cycle renews without grace available, G6b cannot be scored, and a
purchase the rig cannot cheaply replace is wasted.

**Why S2 split, and why S2b moved after U4.** The notification URL needs a
deployed endpoint to point at. **Sandbox delivers each notification exactly once,
with no retries** — production retries five times over 72 hours, sandbox does
not retry at all — so a URL configured before the endpoint exists does not queue
anything; those notifications are permanently lost. S2a has no such dependency
and is done first, partly because the `.p8` downloads **once**.

**Production Billing Grace and the production notification URL remain untouched
until their later authorised step.** Neither is part of the sequence above.

### U3's privileges are deterministic, and U4 inherits nothing

**Recorded 2026-08-17, because the alternative is a defect U4 would discover as a
runtime permission error.** A new public table inherits whatever `pg_default_acl`
entry applies to the role that creates it, and that entry differs between
deployments — the local stack's `postgres` entry grants `anon`, `authenticated`
and `service_role` `Dxtm`, the stock `supabase_admin` entry grants all three
`arwdDxtm`. U3 originally revoked from the two client roles only, which left its
final state, and two of its ten predicted structural surfaces, as properties of
the environment rather than of the migration.

**U3 now revokes every privilege on all five membership tables from `public`,
`anon`, `authenticated` and `service_role`, and revokes EXECUTE on all three
helpers from the same four before granting `membership_state` back to
`service_role`. That single grant is the entire privilege surface U3 creates**,
and the resulting delta on `table_grants` and `column_grants` is **zero**.

**So `service_role` holds no DML on any membership table, deliberately.** U3
needs none — every read goes through a `SECURITY DEFINER` helper owned by the
table owner. **U4 must introduce whatever server mutation surface it needs by
explicit grant**, and will otherwise fail with `permission denied for table
membership`. That failure is the intended one: deliberate at the point of
writing, rather than an accidental privilege found later.

## The fundamental rule

**Leaving Connected is not leaving Études.**

A musician may stop paying for Connected temporarily or permanently and continue
using Études in Solo mode indefinitely. **No subscription lifecycle event may
delete or reset local Études data** — not cancellation, Billing Grace, Billing
Retry, expiry, refund or revocation, a missed or delayed notification, a
reconciliation failure, or resubscription.

The local Journal, sessions and thoughts, Scores, media and attachments,
profile, settings and every other piece of personal local data remain untouched
through all of them.

**`LocalFactoryReset.perform` remains reachable only through explicit
user-confirmed destructive operations.** It has exactly two callers —
`ProfileView:1680` (Solo erase) and `ProfileView:1753` (Connected delete) — and
Phase 3 must not add a third. That caller count is a Phase 3 **exit assertion**,
not a convention, and QA C12's proxy half is its runtime counterpart.

## Expiry is NOT explicit account deletion

**These are two deliberately distinct lifecycle policies on two distinct
destructive backend paths:** explicit user-triggered account deletion, through
the established deletion transaction and `delete_account_v1`; and
server-scheduled expiry cleanup, through its own worker. The first is a
*request*; the second is a *schedule*. Do not describe them as "two workers", and
do not reuse `delete_account_v1` as the expiry worker merely because it already
deletes an account.

**This corrects a conflation, and the reconstruction matters more than the
correction.** QA C7 was amended on 2026-08-14 to assert that "expiry cleanup must
match `delete_account_v1`'s deployed semantics", on the grounds that retention
was "the pre-2026-08-13 rule and is now wrong". **That inference was
unsupported.** The 2026-08-13 revision (`c4f6d0f`, `dac78af`) was scoped to
account deletion by its own text — the bullets it removed were unqualified, the
bullets that replaced them begin "*Deleting a Connected account*" — and it was
justified by Apple's **account-deletion** guidance, which says nothing about
subscription expiry. `docs/architecture.md`'s "On expiry" table was never
touched by any commit in that revision, and is **not** superseded documentation:
it is the surviving statement of a deliberately different rule, prefaced in its
own words "*Owner: mixed, deliberately — which is why expiry is not uniform*".
The same C7 cell then said the question was Phase 3's to decide, so the row
asserted a requirement and declared the question open in one breath.

### The expiry retention matrix

| Data | Ordinary expiry | Explicit account deletion |
|---|---|---|
| Own posts, included attachments, their storage objects | **Removed** | Removed |
| Post shares, sent (by cascade) and received | **Removed** | Removed |
| Own received-attachment references | **Removed** | Removed |
| Follows / social graph, both directions | **Removed** | Removed |
| `post_comment_views` as viewer | **Removed** | Removed |
| Sent attachments with **no** live recipient reference | **Removed** | Removed |
| Avatar storage object | **Removed** | Removed |
| **Comments authored on other members' surviving posts** | **RETAINED** | Removed (`author_user_id` alone) |
| **Sent attachments while a live recipient reference remains** | **RETAINED**, row and object, reference-counted on `deleted_at IS NULL` | Removed |
| `account_directory` row | **RETAINED**, undiscoverable | Removed |
| `auth.users` | **RETAINED** | Removed, strictly last |
| Comments authored by others, merely addressed to them | Retained | Retained — B-19, never add `recipient_user_id` |
| **`membership` and `membership_binding`** | **RETAINED** | Removed by `auth.users` cascade |
| **All local data** | **UNTOUCHED** | Erased, because the user asked |

**Membership state is private lifecycle and authority state, NOT Domain 3
content, and ordinary expiry cleanup must not remove it.** The matrix above says
so explicitly because it was written before membership existed, and an
implementer reading the older version could reasonably have deleted both. Three
consequences:

- **`membership` is retained** (deriving not-entitled) so the record of what
  happened survives, and so `binding_method` still answers whether this
  subscription was ever ownership-verified.
- **`membership_binding` is retained**, and this one is load-bearing rather than
  tidy. Whether `originalTransactionId` survives a lapse-and-resubscribe is
  genuinely ambiguous — Apple does not document it, reports describe the id being
  reused, and there is evidence of a change in 2025 producing a new one. **The
  design does not need Apple to settle it, because the asymmetry decides:** if
  the id is reused, Apple still reports the old token and a retained binding
  matches instantly, whereas a deleted binding would mint a new token, mismatch,
  and **reject the legitimate owner as a conflict**; if the id is new, the legacy
  claim path handles it either way. Retaining is correct under both behaviours;
  deleting is broken under one.
- **Explicit account deletion removes both**, through the `auth.users` FK
  cascade — no new deletion step, and `delete_account_v1` is not modified.
- **External Sign in with Apple revocation retains both**, because it withdraws
  authentication and not the account (C-45, invariant 5).

**STANDING RULE: never make long-lived Études correctness depend on
`originalTransactionId` surviving every lapse-and-rejoin shape.** It is a stable
key for an ongoing subscription and nothing stronger.

**Explicit account deletion keeps the already-verified Phase 1 semantics and is
not weakened by this.** Deletion has two triggers expiry does not: the user asked
for it, and Apple's guidance requires it. A lapsed member retains a one-tap route
to delete their account without paying, which removes everything.

**One implementation consequence, worth having early.** Retention of sent
attachments requires **reference-counted preservation**, which existed as step 2
of `delete_account_v1` and was deliberately removed on 2026-08-13 — its
gravestone comment is still in the deployed function. Expiry must re-implement
it in its own worker. That is an independent reason not to share the deletion
sequence between the two paths.

## Rejoining

After completed expiry cleanup, **rejoining Connected means a fresh Connected
content and social presence, not necessarily a new backend UUID.** The retained
identity may be reused — and in practice will be, because Sign in with Apple
returns a stable subject for the same Apple ID and development team, so a new
identity would require deleting the auth user.

**The local Journal never disappeared.** Nothing is restored or reconstructed
because nothing was lost. A previously shared entry is shared again through the
ordinary route — open it, edit, save — producing a new Connected post. That is
why a dormant Connected account need not be kept alive for the musician to
recover their own work, and it is what makes cleanup safe rather than lossy.

## Quarantine

- Entitlement ends → **Connected access ends**.
- The Connected presence becomes **invisible to other members immediately**.
- A **60-day quarantine** begins.
- Quarantine is an **internal safety mechanism with no user-facing mode or
  surface**. It must never become a third app mode or a state users depend upon.
- **Resubscription during quarantine cancels pending cleanup and restores the
  previous Connected presence whole.**
- After completed cleanup, resubscription starts a **fresh** Connected content
  and social presence on the retained identity.

**Rationale, stated precisely because it is easy to overstate: Études chooses 60
days as its safety/quarantine period, informed by Apple's own ≤60-day
subscription-continuity boundary** (`recentSubscriptionStartDate` is documented
as ignoring lapses of 60 days or less). **Apple neither requires nor recommends a
60-day application-data retention period, and nothing in this record may imply
that it does.**

**Refund and revocation use the same 60-day quarantine**, deliberately. Apple
documents `REFUND_REVERSED` — "reinstate content/services if revoked" — so a
refund is not a terminal signal, and destroying content promptly on one risks
destroying content Apple may later instruct us to restore. Revocation ends
*access* immediately; it does not shorten the fuse.

## Cleanup authority — load-bearing

**No stored membership record, notification, scheduled timestamp, client state
or local cache is sufficient authority for irreversible expiry cleanup.
Immediately before cleanup, Études must obtain current authoritative
subscription status from Apple. If that authority cannot be obtained, cleanup
does not run and is retried later.**

**Notifications may schedule cleanup. They never directly execute it.**

This applies equally to expiry and to refund/revocation quarantine completion.
It is the reason a replayed, spoofed or mis-ordered notification cannot destroy
anything on its own.

## Subscription semantics

Entitlement is **derived** from Apple's own service formula, never transitioned
by notification type:

```
entitled(now) = renewalDate > now
             OR (isInBillingRetryPeriod AND gracePeriodExpiresDate > now)
```

This is identical to what `Transaction.currentEntitlements` resolves on-device —
it includes `subscribed` and `inGracePeriod`, and excludes expired, refunded and
revoked — so **client and server can disagree only about freshness, never about
meaning.**

| State | `status` | Entitled | Notes |
|---|---|---|---|
| **Voluntary cancellation** | 1 | **Yes** | Auto-renew off. **A renewal-preference change, not a billing event, and NOT Billing Grace.** Entitled to the paid-through date, then `EXPIRED / VOLUNTARY` |
| Active / renewed | 1 | Yes | |
| **Billing Grace** | 4 | **Yes** | `DID_FAIL_TO_RENEW` with subtype `GRACE_PERIOD`. Only a *billing failure* reaches here |
| **Billing Retry outside Grace** | 3 | **NO** | `isInBillingRetryPeriod` alone does **not** entitle — Apple's formula requires it *combined with* an unexpired grace period. Quarantine starts |
| Expiry | 2 | No | Subtypes `VOLUNTARY`, `BILLING_RETRY`, `PRICE_INCREASE`, `PRODUCT_NOT_FOR_SALE` |
| Refund / revocation | 5 | No | Same 60-day quarantine |
| Refund reversal | 1 | Yes | Cancels pending cleanup |
| Resubscription | 1 | Yes | Cancels pending cleanup |

**The `Cancel → Grace` conflation must not survive anywhere as current expected
behaviour.** Historical prediction material may remain where it is clearly marked
as superseded; it must not be rewritten to look as though it was always right.

## Directory and attribution

Recorded as contract. **None of this is implemented in U0.**

- `search_account_directory` respects Connected eligibility as ultimately
  implemented, so a **lapsed member becomes undiscoverable**.
- **`get_account_directory_by_user_ids` must continue resolving retained authors
  for entitled viewers.** These are two separate deployed RPCs, which is the only
  reason undiscoverability and attribution can coexist — and it makes the
  separation load-bearing rather than incidental.
- **Expiry retains the directory row and `display_name`.** Clearing either would
  break attribution for every retained comment while appearing to satisfy
  "undiscoverable".
- Expiry removes the avatar object and clears `avatar_key` **only after
  successful object removal** — C-33's ordering lesson, applied to the expiry
  path. The predicted render for a retained comment is therefore initials, not a
  photo and not a broken image.

## Existing-member rollout

The approved temporary cutover compatibility design:

- **U3 captures a frozen pre-enforcement identity snapshot** at deploy.
- **Real membership state always takes precedence** over the snapshot.
- The snapshot is a **bounded compatibility mechanism** for pre-cutover users
  whose authoritative membership row has not yet been established.
- **Post-cutover identities with no membership record are not entitled merely
  because no record exists.** Absence is never entitlement.
- **Absence of a membership record can never schedule cleanup** —
  `pending_cleanup_at` is only ever set when a membership row's derived
  entitlement transitions from true to false, so a user with no row has nothing
  to transition. This is structural and holds independently of the snapshot.

**RETIREMENT DECIDED 2026-09-01 — B-36. THE SNAPSHOT HAS NO ENTITLEMENT
PREDICATE, and that is why this whole mechanism is being removed rather than
wound down.** U3's population statement is `where u.created_at < cutover_at` and
nothing else, so the snapshot captured **every identity that existed, not every
identity that was paying**. The clause therefore grants Connected to all 16
pre-cutover identities regardless of whether any ever subscribed — and the cohort
is pre-release beta, which the account holder has confirmed need not be
preserved. **U6b's Gate 2 is retired, not satisfied: it was unsatisfiable by
construction**, since an identity that never had a subscription can never acquire
authoritative membership state. `connected_member()` loses its middle `coalesce`
arm, `membership_state()` loses `'grandfathered'`, and `membership_cutover` plus
three `membership_control` columns become dead.

**It is not a backfill, and calling it one would be wrong.** `Get Notification
History` can enumerate `originalTransactionId` values server-side, but the app
does **not** set `appAccountToken` — `product.purchase()` is called with no
options anywhere in the source — so nothing on Apple's side or ours maps a
subscription to a Supabase user. Client participation is required.

## Ownership binding — settled 2026-08-16, see B-24

**Proving a subscription is genuine and proving it belongs to this Études
identity are two different problems, and only the first was solved.** Apple's
answer to "is this subscription active?" is authoritative and says nothing about
who owns it — no Apple surface returns the Apple Account, and none will.

**Three artefacts, none interchangeable:**

| Artefact | Proves |
|---|---|
| **Apple-signed transaction JWS**, server-verified | **Who** — possession. Obtainable only from `currentEntitlements` on a device signed in as the owning Apple Account, and signed by Apple, so it cannot be minted |
| **Live server→Apple status read** | **Now** — current authoritative entitlement. A JWS may be stale |
| **`appAccountToken`** | **The durable binding** to an Études identity, carried by Apple into all future renewals |

**Future Connected joins (accepted):** Sign in with Apple → establish backend
identity → establish binding → purchase with `appAccountToken` → verify the
Apple-signed JWS → live reconciliation → verify Apple's reported token matches →
**only then** establish membership. **Solo remains completely account-free**; only
*joining* Connected requires authentication.

**Existing subscribers migrate without repurchase.** Apple's `Set App Account
Token` attaches a binding to an existing subscription and carries it into future
renewals, so a legacy subscription acquires one on its first JWS-verified
reconciliation. **The legacy branch is self-extinguishing rather than
time-limited** — it is reachable only while Apple reports no token, and taking it
sets one, so each subscription can traverse it exactly once, ever. No date
governs it and no flag can be left on.

**Rebinding authority — do not overstate it.** Apple *stores and returns* the
binding; Apple does **not** enforce it against us, because our In-App Purchase
key can call `Set App Account Token`, which overrides. The protection is our
rule:

- ordinary application logic **never** automatically overwrites a token
  belonging to a **live** `membership_binding`;
- a mismatch against a live binding is a **security and account-recovery event**
  — grant nothing, change nothing, record it for explicit operator disposition;
- a token matching **no** live binding is an **orphan**, typically left by an
  explicit account deletion, and a JWS-verified claimant may rebind. **Without
  this distinction a customer who deletes their account and returns would be
  locked out of their own subscription.**

**The token is an attribute of the identity, not of a subscription.** It must
exist *before* the purchase, and one identity may hold both a Sandbox and a
Production membership, so it lives in `membership_binding` keyed on `user_id`.
Because it does, **`membership.binding_method` and `bound_at` are `NOT NULL`** —
the database cannot hold an ownership-unverified membership row, which makes the
central rule a constraint rather than something U5 must remember.

### The load-bearing U5 invariant

**Attestation/reconciliation fires whenever `(locally entitled ∧
hasConnectedIdentity)` holds, including at launch and on every foreground, and
is never gated on Connected mode already being active or on a membership row
already existing.**

This is what makes a dormant pre-cutover subscriber's return self-healing within
a single launch. It was chosen over making activation *await* attestation,
deliberately: that would put a network round trip on a cold-launch path that is
entirely local today, and would invert the settled split in which the client
governs UI reversibly and the server governs the API authoritatively. The worst
case under the chosen design is a few denied requests in the first seconds of a
cold launch. **Not a lockout.**

### U6c — removing the snapshot

**SUPERSEDED IN DIRECTION 2026-09-01 BY B-36, AND THIS HEADING IS KEPT BECAUSE
THE REASONING BELOW RETURNS THE MOMENT A PRODUCTION CUSTOMER EXISTS.** The
account holder confirmed that Études has never been publicly released, that there
are no production customers, and that preserving pre-release beta accounts or
their server-side content is **not a release requirement**. The decision is
therefore to **retire the grandfather mechanism outright rather than to remove the
snapshot at the end of a compatibility period** — which makes everything in this
subsection an ordinary cleanup migration: no twelve-month clock, no liveness
safety check, no dated post-phase obligation. **The simplification depends
entirely on the cohort being disposable, and that dependency is the thing to
re-read before adopting it.** See `supabase/sql/README-grandfather-retirement.md`.

**U6c may remove the migration snapshot when either:**

1. **every snapshot UID has acquired authoritative membership state; or**
2. **twelve months have elapsed since U6b binding**

**— and, before removal in either case, a final LIVENESS safety check is
performed.**

**The safety check is meaningful, not ceremonial. Any snapshot UID that has been
ACTIVE since U6b but still lacks authoritative membership state is evidence that
U5 migration/reconciliation failed for that identity, and blocks snapshot removal
until dispositioned.**

**CORRECTED 2026-09-01 BY B-35. THIS CHECK WAS SPECIFIED ON
`auth.users.last_sign_in_at`, AND THAT COLUMN CANNOT ANSWER THE QUESTION.**
GoTrue advances it only on re-authentication, never on token refresh — so an
identity holding a long-lived session is fully active and reads as though it has
not signed in since before the cutover. **Measured, not reasoned:** both
identities that generated the 48 shadow observations of 2026-09-01 carry
`last_sign_in_at` of 2026-08-25 and **2026-08-14**, the latter three days BEFORE
`cutover_at`, while `auth.users.updated_at` and their `auth.sessions` rows both
moved that day.

**The check must key on `max(auth.sessions.updated_at)` per user, cross-checked
against `auth.users.updated_at`** — the two agreed on every bucket across all 16
snapshot identities when the census was run. **`last_sign_in_at` may be recorded
alongside, and must never be the predicate.**

**The failure direction is what makes this load-bearing: it fails OPEN.** A
blind check reports "nobody active" and lets the snapshot be removed out from
under identities that are still using it — which is the one outcome U6c exists to
prevent, arriving silently and looking like a pass.

**"Zero grandfather-dependent requests in the shadow window" must never stand in
for U6c safety.** The shadow metric proves something about *observed traffic*
only, and a dormant subscriber generates none. That distinction is the whole
point: four different questions were sharing one metric.

**Phase 3 is explicitly allowed to close with the bounded snapshot still
present.** U6c is therefore a **dated, owned post-phase obligation recorded on
B-11** rather than something forced to happen inside the phase. Forcing removal
to fit a phase boundary would be the opposite of the discipline that says no
obligation may be ownerless.

---

**PHASE 2 IS FORMALLY CLOSED — 2026-08-15.** C-4 is **Resolved**: built as units
U1–U6 plus a bounded D1–D6 remediation, and discharged on a **genuine encrypted
Finder backup → restore onto Device A**, scored against predictions committed
before every mutation. The gate was never substitutable by resource-flag
inspection — the experiments establish what the URL API reports, never what
Apple's backup daemon copied — which is why it was held open until a real backup
and a real restore had run.

**Phase 2 owned exactly one register row and discharged it. It also discharged
C-49, a carried Phase 1 row, from the same destructive run, and filed C-51 to
Phase 4.** Nine device assertions were scored: **seven PASS** (the U5 pre-backup
reconciliation gate, F1, F2, F2b, F4, D15, C-49), **one NOT EXERCISED with a
named owner** (F3 → C-51, Phase 4), and **F5 satisfied by the D15 run** on the
restored device rather than by a separate destructive run. Closure was audited
independently against the repository on 2026-08-15 before being recorded.

**What Phase 2 turned out to be, beyond C-4 as filed.** Three things the original
finding did not say, each found by looking rather than assuming. (i) The Scores
restore failure is **not** an empty library — the index lives in `UserDefaults`
and restores, so the user gets a populated library whose every PDF is missing;
QA F1's old expectation would have read that as a pass. (ii) `AttachmentPrivacy.json`
was excluded too, **incidentally** — `PracticeTimerStore` flagged the whole
`Application Support/MOTIVO/` directory as a side effect of a migration helper,
so permanent user intent sat in scratch storage with no code saying so. Losing it
fails *closed*, which is why it was P3-shaped rather than urgent. (iii) **Backup
participation alone was insufficient.** `Attachment.fileURL` stores an absolute
path containing the container UUID, which changes on restore, and **nine**
consumers read it — not the three first identified. Two of the five extra are
deletion-safety guards that fail **open**, and one is the publish path, where a
missing fallback made `loadIncludedAttachments` *silently skip* attachments so a
shared post arrived with its media missing and no error anywhere.

**Two experiments settled design questions that reasoning had got wrong.**
Backup exclusion resolves by **ancestor walk**, not attribute inheritance: there
is **no per-item "include" override**, so a child of an excluded directory cannot
be exempted — which is why the privacy map had to *move* rather than be
un-excluded in place — and **a child's own flag survives its parent being
un-flagged**, which is why reconciliation must clear item-level flags and not just
directories. `Documents/Scores/` was flagged at both levels; clearing only the
directory would have left every PDF excluded, invisibly, until a real restore.
**Standing rule: never rely on ancestor resolution for inclusion.**

**Three separate first-run results in this work were misleading, all from
caching.** The exclusion experiment's first run was incoherent because `NSURL`
caches resource values; the reconciliation's first simulator run appeared to do
nothing because `cfprefsd` served a stale completion key; and the device
container download showed no exclusion attributes at all because `devicectl copy
from` **strips xattrs** — proven by a control, since `Application Support/MOTIVO/`
provably carries one. In each case the second, controlled run was the real
result. **Re-run before believing a first observation that involves a cache.**

**The filename-uniqueness audit narrowed the resolver rather than widening it.**
Persisted media has always been written to `Documents/` (true since `7c54aae`),
and `tmp/` is a **guaranteed** collision source — a persisted file is
`Documents/<stagedAttachmentID>.<ext>` while its viewer surrogate is
`tmp/<stagedAttachmentID>.<ext>`, same id, same stem, same extension. Feeding
publish and deletion from a resolver that could return a tmp surrogate would mean
uploading stale bytes or aiming a delete at the wrong file. Eligible locations are
now `Documents/` and `Documents/Scores/` only, ambiguity resolves by the stored
path's own parent, and otherwise returns unresolved — never "first directory
wins". That eligible set is deliberately the same set `BackupPolicy` calls
permanent media and the same set reconciliation traverses.

**One defect was introduced and caught by QA, not by review.** U4 ran the privacy-map
migration lazily inside `loadMap()`, which only executes when something queries
attachment privacy — so a user who upgraded and backed up without opening a
session with attachments would still have had the map in the excluded directory.
A bare simulator launch moved nothing. It now runs at launch as well.

**THE THREE PHASE 2 DEVICE GATES ARE ALL RUN AND ALL DISCHARGED, 2026-08-15.
They were scored separately, and they stay separately scored in the record.**

| Gate | What it proves | Where |
|---|---|---|
| **F1/F2** | **DONE 2026-08-15 — BOTH PASS.** Genuine encrypted Finder backup → restore on Device A. All 7 files authored by `a8eb050` (excluded at write time, cleared only by U5) came back **byte-identical**; the adopted Scores copy survived while the byte-identical inbox cache did not; excluded scratch did not restore; the privacy map and its choices came back intact; reconciliation correctly did **not** re-run. **F3 is NOT EXERCISED and is not a pass** | QA Group F |
| **Erase-regression gate (D15)** | **DONE 2026-08-15 — PASS.** The root-level `AttachmentPrivacy.json` (520 bytes, 10 entries) was **removed**, along with all 8 Documents files, Scores, the Scores index and the journal; backend blast radius matched **10 of 10** measures and B's data survived. Received-cache and CommentsStore assertions **not re-exercised** (empty preconditions) and **not counted as passes**. **This run also satisfies QA F5** — see below | QA Group D |
| **C-49** | **DONE 2026-08-15 — PASS.** Immediately on completion, without relaunching, the app was on **first-launch onboarding**, not the journal | Carried Phase 1 row — **now Resolved** |

**F5 needed no gate of its own, and this is an evidence relationship rather than
a rename.** F5 asks that a factory reset still removes everything *after a
restore*, when stored absolute paths are stale — its stated rationale being that
the sweeps are directory- and extension-based and never read `Attachment.fileURL`.
The D15 run instantiated exactly that condition: it ran **on the restored Device
A**, with paths two container generations stale (F4 had already demonstrated the
staleness on the same device state), and every populated fixture was removed —
8 `Documents` files, `Documents/Scores/`, the 4-entry Scores index, the journal
(2 sessions / 4 attachments → 0/0, store rebuilt) and the root privacy map. The
one honest caveat: the button pressed was **Delete Account & All Études Data**,
not the Solo-only **Erase All Études Data**, because Device A held a Connected
identity. Both converge on `LocalFactoryReset`, so the local sweep behaviour is
identical and the Connected path is a strict superset. F5's empty-precondition
carve-outs are D15's, unchanged: the received cache, `CommentsStore.json`, the
local avatar and the legacy privacy-map location were all absent and are **not
counted as passes**.

**C-49 was discharged by the D15 run on 2026-08-15, as designed** — one
legitimate destructive operation, two separately scored gates. The restore did
not discharge it; the deletion did.

**TWO THINGS THE RESTORE TAUGHT US THAT OUTLIVE THE GATE.** (i) **An ordinary
in-place app update rotates the data container**, established from the pre-backup
database rather than the restore — so stale absolute paths in `Attachment.fileURL`
are a *routine* condition, not a rare restore artifact, and U2's resolver is
load-bearing on every update. A pre-backup note claiming the UUID was unchanged
was **wrong**, caused by `limit 1` sampling one row; it is corrected in
`docs/qa-plan.md`. (ii) **F3 could not be exercised through the shipping UI at
all**: the only publish trigger is the editor's save, which rewrites
`Attachment.fileURL` from resolved URLs ~80 lines before publishing, so the save
*self-heals* the very condition F3 exists to test.

**F3's remaining obligation is C-51, owned by Phase 4. It is coverage, not a
defect, and it is not resolved.** State it in these four parts, because
collapsing them is how it gets misread: (a) **the implementation exposure is
already fixed by U2**, which routes `BackendShim.resolveLocalFileURL` through the
canonical resolver — pre-U2 `loadIncludedAttachments` silently skipped the
attachment and the shared post arrived with its media missing; (b) **F3 was not
exercised because the shipping editor/save route self-heals stale paths before
publish**, so running it would have scored an assertion the test never reached;
(c) **what remains is runtime verification** of the one route that can still
reach upload selection with stale paths — a publish enqueued in `SessionSyncQueue`
that flushes after an ordinary container rotation, which needs fault injection;
(d) **Phase 4 owns that verification** because Phase 4's shared-only upload work
rewrites the upload-selection surface itself and already carries A2's proxy-based
network acceptance. Deliberately **not** Phase 3, which is a different subsystem
that merely shares the fault-injection blocker. Phase 2 was not expanded to
manufacture it, and Phase 4 implementation is not expanded now.

**Three Phase 2 obligations are closed on source verification only, and are
recorded as such rather than dressed as device passes.** (i) The transient
`motivo_vid_*` exclusion — the fixture contained none, so the reconciliation
skip was traversed vacuously. It is accepted because its failure direction is
*a scratch capture riding into a backup*, never loss of permanent data, and
C-4's obligation is the latter. (ii) The two **deletion-safety guards**, whose
Phase 2 changes are provably monotone in the safe direction:
`protectedPersistedAttachmentPaths_edit` inserts resolved *and* raw paths, a
strict superset of pre-Phase-2, and `isPathReferencedInCoreData` protects on more
paths and fails **closed** on a fetch error. Their worst case is a retained
orphan, never deletion of referenced media. (iii) The **legacy
`MOTIVO/AttachmentPrivacy.json` erase sweep**, absent at D15 time because U4 had
migrated it away: it is the same statement as the exercised root sweep with a
different element of the same array, and `legacyFileURL()` was independently
exercised by the migration on the same device. **None of the three is given a
later verification owner**, because each closes on a stated sufficiency argument
rather than being blocked on a fixture.

---

**Phase 1 position: FORMALLY CLOSED — 2026-08-14.** It closed on an
independent audit reconstructed from this repository and from read-only
production checks rather than from any conversation, followed by one bounded
reconciliation unit. **It did not close on the numbers being tidy.** Four rows
remain open and are carried explicitly, named below; anyone reading "closed" as
"nothing left" is reading it wrong. **C-49, the fifth, was discharged on
2026-08-15 by Phase 2's destructive run**, exactly as its carry condition
specified.

**The closure judgement, stated so it can be audited later.** Every Phase 1
obligation is now in exactly one of four states: executed with durable evidence;
closed under a stopping rule agreed *before* the attempt; fixture- or
infrastructure-blocked with that fact recorded; or assigned to a named later
phase. **No obligation is ownerless**, which was not true before this unit ran —
B-12's pagination check and B-9's two-recipient case each had a blocker and no
owner, and B-19's client half had been unowned since 2026-08-11.

**The audit found no behavioural defect.** Every load-bearing backend claim was
re-verified against live production and holds: both Edge Functions ACTIVE and
byte-identical to source, B-14's column privileges, B-5's directory grants,
B-6's owner-bound policy `qual`, and B-7/B-10's three dropped functions absent
from `pg_proc`. **What was wrong was the record**, in four places sharing one
shape — *a document written under a rule that later changed, and never re-read.*

**The arithmetic — 32 of 36, recomputed from the register on 2026-08-15.** The
denominator is reproducible: counting every row whose Phase cell contains `1`
gives **36** (19 client, 17 backend). Of those, **30** are resolved or closed
with verification, **C-38** is closed under the agreed stopping rule, and **C-3**
is discharged as *measured* (Phase 1 owned the severity; Phase 5 owns the fix) —
**32 discharged**, with **4 carried**: C-36, B-4, B-12, B-13. It was 31 with 5
carried until **C-49** was device-verified on 2026-08-15 by the D15 destructive
run. An older headline of "31 of 34" was worse still — its denominator was not
reproducible at all, having silently dropped C-49 and C-36.

**Row arithmetic and outstanding verification are two different counts, and
conflating them is how B-9's subcase went missing once already.** The Phase 3
backend-verification unit holds **four** obligations, not three: **B-4**,
**B-12**, **B-13** — which *are* carried Phase 1 rows and appear in the 4 above —
plus **B-9's two-recipient case**, which does **not**, because B-9's row is
**Resolved**. B-9's Phase 1 obligation was the fix, and D14 device-verified it on
2026-08-11; only the two-recipient subcase was transferred, and a Resolved row
correctly contributes nothing to a carried count. **Read the Phase cell, not the
state word:** B-9 is `1 (fix) / 3 (two-recipient case)`.

**Two further Phase-1-discharged rows carry remainders owned elsewhere, and
those are not Phase 1 debt either:** **C-3** (measurement done; the fix is Phase
5) and **B-10** (functions dropped; the real Storage-API cleanup is Phase 4).

**What the audit found, none of it a behavioural defect.** Every load-bearing
backend claim was re-verified live and holds: both Edge Functions ACTIVE and
byte-identical to source, B-14's column privileges, B-5's grants, B-6's
owner-bound policy `qual`, and B-7/B-10's three functions absent. **The failures
were all in the record**, and they share one shape — *a document written under a
rule that later changed, and never re-read*. (i) `delete_account_v1` carried a
comment block instructing the next maintainer **not** to add the `post_comments`
statement that the revised rule requires, twenty lines above that statement.
(ii) B-3 and B-19's **state** cells still described the superseded retention rule
— the finding columns had been revised on 2026-08-13, the state columns had not,
untouched since `1889b48`. (iii) QA **D7** and **C7** still specified the retired
expected outcome. (iv) The shared note under the backend table blamed the
unreached client half on a blocker that the C-35 run had already disproved, and
attributed it to the wrong half (the *author*, which is now moot, rather than the
*recipient*, which is B-19's). **All four are corrected.** The function change is
comments-only and is **not deployed** — see `supabase/README.md` for the recorded
divergence and the condition for closing it.

**Ownership gaps closed in the same unit:** B-12's pagination verification and
B-9's two-recipient case both had a stated blocker and **no owner**, which is how
they survived a phase gate unnoticed; both are now Phase 3, grouped with B-4 and
B-13 as one backend-verification unit. QA **E8/E8b** are marked superseded so no
crafted production-write exploit appears to be outstanding. QA **A2, C1–C4, C11,
C12** — which carried no execution status at all — are each dispositioned as
satisfied by later evidence, superseded by architecture, or given a named
later-phase owner, with the uncovered parts named rather than absorbed. **No new
QA was manufactured to tick a box.**

**B-19's client-rendering half is RESOLVED — device-observed 2026-08-14, and it
closed the last unowned Phase 1 obligation.** No staging, no new account, no
destructive action: a live production fixture already existed and was located
read-only. The C-35 discriminator thread (`944a70cb`, recipient `92d6b718`,
deleted 2026-08-13 with no directory identity) opened instantly on Device B /
Études Dev and rendered normally — author "You" with avatar, body intact, no raw
UUID, no blank or broken identity UI, no null/undefined, no spinner. **The
non-failure was predicted from source first** — `CommentsView` hydrates identity
for authors, owner and viewer only and never for `recipientUserID`, so the
recipient has no render site at which to fail — which is what makes this a
confirmed mechanism rather than a green screen. **The cost of the correction is
the lesson:** it had sat unowned since 2026-08-11 behind a blocker disproved on
2026-08-13 and a premise the rule change had made moot, and it took one existing
fixture and one thread open. The expensive part was never the test.

**FOUR ROWS ARE CARRIED PAST CLOSURE. They are open, and closure does not make
them less so.** C-49 was the fifth; it is **Resolved** as of 2026-08-15, having
been folded into Phase 2's destructive run exactly as its carry condition
required, without a fixture of its own ever being spent.

| Row | Why it is carried | Owner |
|---|---|---|
| **C-36 / QA B7** | Genuinely fixture-blocked: needs a **fresh first-join account**. A first-join path exercised by an account that has already joined proves nothing | Blocked until such an account exists |
| **B-4** | Only the positive direction executed; the honest `success: false` needs fault injection (D10) | **Phase 3** |
| **B-12** | Never executed — 5 objects against a 1000-entry page boundary | **Phase 3** |
| **B-13** | Idempotency by inspection; D10 deferred | **Phase 3** |

**B-4, B-12, B-13 and B-9's two-recipient case are ONE Phase 3 unit, not four
errands.** All four are blocked on the same thing — a disposable or local
backend where destructive fixtures are free. **State the dependency precisely,
because it is easy to overstate: the instance makes those fixtures safe to
build; it does not build them.** Generating >1000 objects under one prefix, and
minting a third identity without an Apple ID, are both explicit work to schedule.

**C-26 and B-11 remain release blockers owned by Phase 3**, not Phase 1 debt.
C-31 is a Phase 3 prerequisite; C-30 and C-32 are RC.

**Historic detail below is kept as the record of how the phase was worked.** Landed and device-verified: C-13
(purchase-path hang), C-24 (reconnect after reinstall), C-1 client half (client
expiry-deletion authority removed), C-2 (Scores survived Erase All).
Verification batch cleared: C-7, C-8, C-19. Filed along the way: C-23, C-25,
C-26, C-27, C-28, from the avatar audit C-33, C-34, C-35 and B-20 (avatar
lifecycle — deletion on erase, and replacement propagation), and C-36 from the
location audit (Solo location published on join, then clobbered). From the
2026-08-13 TestFlight run and the B-14 unit: C-42 (membership screen priced in
USD while Apple's sheet showed GBP), C-41 (vestigial `lookup_enabled` client
plumbing) and C-43 (Unfollow and Remove Follower each delete *both* directional
follow rows).

**`delete_account_v1` is deployed, and QA runs 1 and 2 have both passed.** The
rewrite (`ca00189`) plus the B-20 avatar fix (`5714c53`) carry eight findings.
D5–D9, D11 and D12 ran combined on 2026-08-11, and D13 ran separately the same
day; together they **Resolve B-1, B-3, B-19 and B-20**. D13 is the only run that
proves the avatar fix, because D12's populated `avatar_key` cannot tell the two
implementations apart.

**B-9 joined them on 2026-08-11 via D14**, the third run and the first against
the `step 3b` deploy — the sent-tombstone cleanup, committed and reviewed before
it was deployed. Its received-row path had never executed in any prior run. Three
legs, one erase, and all eight blast-radius counts matched a prediction written
down *beforehand*, which is what made the check binary rather than a reading of
the aftermath. **Three stay open** — B-4 only ever saw the positive direction,
B-12 was never executed, and B-13's D10 is deferred for want of a safe
fault-injection path.

**One lesson from D14 is worth more than the fix.** B-9's cell had justified the
tombstone cleanup as deleting "precisely the rows whose objects were just swept",
and that reasoning was wrong — rows are per-recipient and share one storage path.
The predicate it implied was right; the reason was not. Implemented from the
stated reason, the natural code would have deleted *every* soft-deleted row, and
account B happened to hold one from a third-party sender that the run would then
have destroyed. **Correct a finding's reasoning even when its proposed fix is
right**, because the reasoning is what the next person implements from.

**Filed from D13's blast-radius check: B-21, P3.** Two avatars of accounts
deleted in July were permanently orphaned in the bucket — no `auth.users` row, no
directory row, no pointer, and no policy path that could ever reach them. B-20
observed in production rather than argued from source. Both were the developer's
own earlier beta accounts, so no real user's data was involved; cleared manually
2026-08-11. The row is kept as the observed instance behind B-20.

A whole-backend read-only orphan sweep followed, on the reasoning that the old
function ran for months. **Nothing else was left exposed** — zero orphaned
`posts` (B-4's worst case never materialised), zero orphaned shares, follows,
comment views or `attachments` objects; 30 dead `connected_attachments` rows with
no surviving storage. The avatars bucket was the only place with residue, which
is exactly where the audit had no coverage. **One false positive is recorded on
B-8 as a warning:** an orphan heuristic keyed on the `users/<uid>/` path prefix
flags D5's survivor, because the prefix carries the *sender's* uid and a dead
sender is the correct state for a preserved asset. Any future cleanup must read
liveness from `connected_attachments.deleted_at`, never from the path.

`verify_jwt` is now pinned in `supabase/config.toml` — without it the CLI
defaults to `true` and a deploy would silently change the deletion path's
authorisation configuration.

**C-38 is CLOSED as Unverified — a synthetic-only artefact.** The one deliberate
attempt was run on 2026-08-11 and **did not reproduce it.** A fresh Sandbox Apple
Account on device A gave the clean first-purchase state the attempt needed
(`entitlementRead resolved=notEntitled`, confirmed from the trace rather than
from the screen). The purchase went through Apple's sandbox — verified on Apple's
own payment sheet, headed "Sandbox", not the synthetic `[Environment: Xcode]`
sheet — and **the first entitlement read after the verified transaction already
resolved `entitled`**, with `purchaseGuard isEntitled=true`. There was no stale
read at any point. The single synthetic observation stands and is not retracted;
it simply has never occurred on Apple's pipeline in four runs now. Per the agreed
stopping rule, no further hypotheses are manufactured. It reopens only on a real
observation, and QA B2 is where that would surface.

**Note the run method, because it is more useful than TestFlight for this class
of work:** the shared scheme's Run action is already Release, so clearing the
StoreKit configuration in Run → Options gives a development build on real sandbox
StoreKit with the debugger and live console attached. That is a genuine
real-StoreKit environment and it iterates in minutes rather than in TestFlight
processing time. **The Run action must stay on Release** — and it did NOT, from
2026-08-14 to 2026-08-20; see C-52 and the U5a record below before trusting this
paragraph. **Restored 2026-08-20 and verified against the build settings rather
than against this file.** Debug carries
`com.samueldixon.motivo.dev`, which App Store Connect does not know, so products
return an empty array and you get C-29's signature instead of a purchase.

**The TestFlight checkpoint is DONE — 2026-08-13, build 131. C-9 is Resolved.**
Group B ran on the distribution artifact: B1, B3, B4, B5 and B6 all passed, B2
counted as a single attempt (its throttled repetitions are not runnable on
TestFlight — see the environment notes), and B7 needs a first-join account. E12
and E13 ran on the same build and carried B-5 to Resolved.

**Directory hardening is complete.** B-5 Resolved — both directory RPCs are now
authenticated-only, at the grant *and* in the body. B-2's `lookup_enabled`
premise was **withdrawn**, not deferred: there is no discovery opt-out in the
product, and gating either RPC on that column would have blanked names and
avatars for existing followers. B-18 closed as **not a defect** — its
anon-executable claim was false against the deployed grant, and its
`SECURITY DEFINER` is load-bearing in the fail-*open* direction.

**B-14 fixed as a column privilege, not a policy predicate**, because RLS cannot
pin a column to its previous value — `WITH CHECK` has no `OLD`. `authenticated`
can no longer UPDATE either participant ID. **B-14 is RESOLVED — the
normal-approval regression check closed on 2026-08-14**, incidentally and
without spending Device B's lapsed fixture: the `connected_attachments` insert
policy demands an approved follow, so staging C-28's fixture forced a genuine
request → approval cycle, and both rows read back `approved`. The approving
client was Études Dev under a synthetic entitlement, which does not weaken the
result — the fix is a server-side column privilege and the client sends the
same PATCH whatever build it is.

**A genuine lapse was observed on the artifact, 2026-08-13.** C-1's client
authority removal and C-26's retention both held: Connected withdrawn, identity
kept without re-authenticating, and **nothing deleted** — verified against a
baseline recorded while still entitled, read once before the device foregrounded
and again after. C-1's *local durability* half is **not** covered by that run;
Device B had no local journal to lose.

**C-35 is RESOLVED — 2026-08-13, device-verified end to end.** A lapsed member
deleted their Connected account **without re-subscribing**: every one of eight
counts, nine residue checks and both discriminators matched a prediction
committed before the erase. It took two attempts, and the first failure is worth
more than the fix — **C-35's defect existed twice**, and the second instance was
an entitlement dependency laundered through a `UserDefaults` key
(`AppModeManager` writes the backend runtime mode from `AppMode`, which is
resolved from `isEntitled`). The deletion path had been audited for `isEntitled`,
`AppMode` and `canShowConnectedAccountManagement` and passed, because it
contained none of them **by name**. No grep could have found it; only running it
did. `delete_account_v1` was redeployed the same day (version 6) with the revised
B-1/B-3 semantics and verified byte-identical to source.

**C-44 and C-45 are both RESOLVED and device-verified (2026-08-13).** Sign in
with Apple revocation now runs at account deletion via
`revoke_apple_identity_v1`, and the client reacts to Apple revoking a
credential. Every Apple-specific assumption was verified against Apple's live
documentation first, then two empirical gates were run **before any code was
written**: a repeat authorization does return an `authorizationCode`, and a real
native code exchanges at `/auth/token` with **no `redirect_uri`**. Fetch Apple's
docs via `developer.apple.com/tutorials/data/documentation/….json` — the HTML is
an SPA shell and returns no body text.

**Three lessons from that work are worth more than the feature.** (1) **A probe
validates a mechanism, not the presentation context it ships in.** Gate (b2)
exchanged a real code from a plain Profile row; the first production run failed
because the same authorization cannot present while the delete confirmation
sheet is up. Where a probe's environment differs from the shipping call site,
that difference is untested surface. (2) **`#if DEBUG` diagnostics do not exist
in the only build that can execute these paths** — the rig runs Release, and
that is why the first failure could not be diagnosed at all. Use `os.Logger`
with `privacy: .public`, through one funnel. (3) **Check the premise before
explaining the symptom.** An attachment title appeared to vanish on credential
withdrawal and produced a confident, fully-reasoned, wrong mechanism — including
an exhaustive proof that nothing had deleted it, which was true and beside the
point. A controlled single-variable re-run showed the title survives; it had
most likely never been saved. See C-47, downgraded to P3.

**Start by reading these durable sources and reconciling the current Phase 1
position before doing anything.** `CLAUDE.md`, `docs/audit-findings.md` and
`docs/qa-plan.md` are the state; no conversation is.

**A full reconciliation against deployed state was run on 2026-08-13 and found
NO disagreement.** Both Edge Functions ACTIVE with `verify_jwt: false` and
byte-identical to committed source (`delete_account_v1` v7 sha256 `993b505b…`,
`revoke_apple_identity_v1` v1 sha256 `3a7c2035…`); `capture-schema.sh` produced
an empty diff across all ten snapshot files; B-14's column privileges and B-5's
directory grants both as their cells claim; and every backend count identical to
C-45's committed baseline. Device A's `44a6018e…` exists with **no**
`account_directory` row, which is exactly what accounts for 16 `auth.users`
against 15 directory rows. The reconciliation is worth re-running rather than
assumed — but as of that date the documents and production agreed completely.

**Agreed order, set 2026-08-13:**

1. ~~**B-22 — historical deletion residue.**~~ **DONE 2026-08-13. B-22 is
   RESOLVED**, cleared under explicit authorisation after a read-only sweep, and
   verified against a prediction committed beforehand — all nine measures
   matched. Five records and two storage objects went, **by explicit id and
   explicit path, with no liveness predicate anywhere**, so it was never
   generalised into an orphan sweep. **Deliberately left behind, and the
   distinction is the point:** 29 `connected_attachments` rows with both parties
   deleted, one live row from a *live* sender to a deleted recipient, one
   unreferenced object under a live user's prefix, and one orphan
   `post_comment_views` row. None is made non-compliant by the revised deletion
   rule; all belong to B-8, B-10 and B-16 in Phase 4. **B-22 closed the policy
   gap, not the backend.** Two lessons landed with it — B-22's own low-stakes
   reasoning was wrong even though its conclusion held (the Mo rows *were*
   visible in the inbox; `fetchReceived` tests neither sender liveness nor object
   existence), and **`supabase storage rm` silently no-ops** at CLI 2.113.0, exit
   0 with an empty `deleted` list and no DELETE request issued at all. See
   `supabase/README.md`, which now carries the working route.
2. ~~**B-14's runtime approval check.**~~ **DONE 2026-08-14 — B-14 is RESOLVED.**
   It closed incidentally, which is exactly how the cell said it should: the
   `connected_attachments` insert policy demands an approved follow, so staging
   C-28's fixture forced a real request → approval cycle, and both rows read back
   `approved`. Approving client was Études Dev under a synthetic entitlement, so
   Device B's lapsed Release fixture was never spent. No crafted exploit write.
3. ~~**C-28.**~~ **DONE 2026-08-14 — C-28 and C-48 are both RESOLVED**,
   device-verified against a prediction committed beforehand. Product rule
   settled: **Erase All erases everything Études owns or manages locally on that
   device regardless of provenance, and reaches nothing the user has explicitly
   exported to Files or Photos.** Both overreach checks held. **Three lessons
   landed with it, all the same shape:** the received-inbox instruction, the
   `CommentsStore` staging instruction and the tmp "Save to Files" rationale were
   each produced by reading what a function does without asking what can reach
   it — and two of the three were caught by the tester refusing to act rather
   than by the analysis. **C-49 filed** from the one deviation: after a
   successful erase the app lands on the journal, not onboarding — navigation
   state only, clears on relaunch, but on the path App Review exercises.
4. ~~**The remaining cheap investigations.**~~ **ALL DONE 2026-08-14.** C-33
   RESOLVED (structural; the runtime failure path is recorded as unexercised
   rather than given invented fault injection). **C-49 fixed** alongside it, as
   an explicit `onEraseComplete` closure rather than an environment dependency —
   **device acceptance still pending**, folded into the next legitimate
   destructive run. **B-7 and B-10 RESOLVED** — three dormant functions dropped
   from production under authorisation, snapshot diff deletions-only and matching
   a committed delta. **C-3 MEASURED** — severity downgraded `P1?` → **P3**;
   Phase 5 still owns the fix. **B-6 RESOLVED** — hardened structurally
   (`ALTER POLICY` binding an attachment to its post's owner) and device-verified
   on the approved-follower read, which is the only path that exercises it.
5. **C-36 / QA B7 stay parked until a genuinely fresh first-join fixture
   exists.** Do not manufacture a pass from an established account — a
   first-join path exercised by an account that has already joined proves
   nothing.

**Keep deliberately infrastructure-blocked and later-phase items where they
belong.** Do not pull them into Phase 1 to make the register look tidier.

**A Phase 1 exit / reconciliation view is wanted at a sensible point:** what is
genuinely left before the phase can close, what is explicitly deferred and why,
and whether anything still carries material release or security risk rather than
being cleanup or later-phase work. **Produce it from the evidence, not by moving
statuses to improve the numbers.** An item that is open stays open.

**RIG STATE AT END OF U5 — 2026-08-30. READ THIS BEFORE PLANNING ANY DEVICE QA.
IT SUPERSEDES THE 2026-08-15 DESCRIPTION THAT FOLLOWS IT, WHICH IS NOW WRONG
ABOUT DEVICE A IN ALMOST EVERY PARTICULAR.** The older block is kept because its
Phase 2 material is still accurate and still load-bearing; it is marked, not
rewritten.

**This section was stale for five days and nobody noticed until a handover forced
a re-read** — the same shape as C-52 and the U4 heading. A rig description is the
one document a device QA plan is built from, so it fails silently: the plan looks
sound and the fixture it assumes does not exist.

### Device A — verified 2026-08-30 at `41ae743`

| | |
|---|---|
| Build | **U5f client** (U5e/U5f shipped), no temporary instrumentation |
| Connected identity | **LIVE and usable** — the 2026-08-15 identity, re-authenticated |
| Apple credential | **NOT revoked any more** — see below |
| `membership_binding` | **1 row**, created `2026-08-25 17:31:54`, **never updated** |
| `membership` | **1 row**, Sandbox, `binding_method = 'purchase'`, otid `2000001228947923` |
| Sandbox tester signed in | **the second tester**, created 2026-08-30 |
| Local journal contents | **not surveyed** — do not assume empty or populated |

**THE REVOCATION STATEMENT BELOW IS OBSOLETE AND THIS IS WHY.** The 2026-08-15
block says Device A holds nothing usable *because its Apple credential was
manually revoked*. On 2026-08-25 **Sign in with Apple returned the SAME `sub`
after that manual revocation**, re-authenticating the existing identity rather
than minting a new one — `auth.users` did not grow. Revoking the credential
withdrew authentication and not the account, exactly as C-45 and invariant 5
say. **So the identity was never lost, and the inference drawn from the
revocation was wrong even while the revocation itself was correctly recorded.**

**THE CURRENT SANDBOX SUBSCRIPTION EXPIRES ON ITS OWN, ~15:58 UTC 2026-08-30.**
Purchased 14:58 on a 5-minute renewal cycle, so Apple's ~12-renewal cap ends it
within the hour. Nothing needs it: B-24n and F10 are discharged. **Expect a final
`EXPIRED` to schedule quarantine 60 days out, exactly as Q1 recorded — that is a
free confirmation, not a defect and not something to chase.** After it lands,
`membership` holds a lapsed Sandbox row with `pending_cleanup_at` set and **no
worker exists to act on it**.

**BOTH SANDBOX TESTERS ARE NOW SPENT FOR CLEAN-FIRST-PURCHASE PURPOSES, AND A
THIRD IS THE ONLY ROUTE TO ANOTHER.** The first reported `RESUBSCRIBE` rather
than `INITIAL_BUY` from 2026-08-20 onward; the second delivered its one genuine
`INITIAL_BUY` on 2026-08-30. **Clearing purchase history has never been observed
to work in this project** — see the Environment section — so plan any future run
needing a first purchase around minting a new tester, and design it to need
exactly one.

**DEVICE A'S IDENTITY IS PRE-CUTOVER, AND THAT IS A PROPERTY U6 PLANNING MUST
KNOW.** It was minted 2026-08-15 20:08:05, and `cutover_at` is
2026-08-17 19:08:27, so it is inside the frozen 16-row snapshot and the
grandfather clause applies to it. **It therefore cannot demonstrate post-cutover
behaviour on its own.** Stated as a fixture fact, not a design decision — what to
do about it belongs to U6.

### PHYSICAL DEVICE IDENTITIES AND INSTALLED BUILDS — established 2026-09-01 by `devicectl`

**Recorded because "Device A" and "Device B" were used throughout this project
without ever naming a physical device or a bundle, and that ambiguity produced a
false premise in C-55 which survived until it was challenged.**

| Label | Physical device | Installed |
|---|---|---|
| **Device A** | **SD beta burner** — iPhone 16e | `com.sdsongs.etudes` (**Release**) **only** |
| **Device B** | **SD iPhone** — iPhone 17 Pro | `com.sdsongs.etudes` (Release) **and** `com.samueldixon.motivo.dev` (**"Études Dev"**, Debug) |

**SANDBOX TESTER ↔ DEVICE ↔ `originalTransactionId` — established 2026-09-01 by
reading Device A's Settings, not by inferring from names.**

| Tester | Device | `originalTransactionId` | Window |
|---|---|---|---|
| **tester 1** (`sdsongsltd@gmail.com`) | — | **2000001220187383** | 2026-08-20 → 2026-08-25, 18 notifications |
| **tester 2** (`sdsongsltd+devicec@…`) | **Device A** — SD beta burner | **2000001228947923** | 2026-08-30 → 2026-09-01, 29 notifications |
| (`sdsongsltd+deviceB@…`) | **Device B** — SD iPhone | — | no subscription of its own on record |

**The record previously said only "the second tester, created 2026-08-30" and
never named it**, which cost a round trip — the same ambiguity class as "Device B"
meaning two different installs. **Full addresses are deliberately not written
here**; the plus-tag disambiguates all three and the account holder holds the
rest.

**RESUBSCRIBING DEVICE A MUST BE DONE ON `+devicec`.** A different tester means a
different `originalTransactionId` and therefore a SECOND `membership` row — at
which point the U6b re-bind guard correctly refuses, because it requires exactly
one live Sandbox row.

**DEVICE B HAS TWO INSTALLS AND ANY QA STEP MUST NAME WHICH.** They are different
bundle identifiers with different containers and different local data. "Device B"
alone is not a specification — that is exactly what went wrong.

**Both configurations share ONE backend.** A single `Info.plist` carries a single
`SUPABASE_URL` pointing at the production project, so **every server-side
observation is valid regardless of which install produced it** — the server gates
on identity, never on bundle id.

**WHICH TO USE:** anything involving StoreKit, purchases or entitlement-driven
mode **must be Release**, because Debug's bundle id is unknown to App Store
Connect and `Product.products(for:)` returns empty. Pure server-behaviour checks
work from either, but the unit must still name one.

**A GAP WORTH KNOWING BEFORE IT BITES AGAIN: THE BUILD NUMBER CANNOT IDENTIFY A
BUILD.** Both configurations are hard-coded `MARKETING_VERSION 1.0` and
`CURRENT_PROJECT_VERSION 131` and neither is incremented, so **every install from
this project reports `1.0 (131)` whatever commit it came from**. `devicectl`
exposes no install date or hash and the app displays no version at all. **There is
currently no way to tell which source a Release install was built from.**

### Device B — unchanged

Untouched by Phase 2 and by all of Phase 3. Still the established / lapsed
control fixture. **Never run Erase All on it.**

### The 2026-08-15 block below

Everything it says about **Phase 2**, the D15 run, the destroyed Phase 2 fixture,
the C-44 revocation outcome and the abandoned refresh token **remains accurate
and is not superseded**. Only its Device A availability statements are.

---

**HISTORICAL — rig state at end of 2026-08-15. SUPERSEDED FOR DEVICE A by the
section above; retained for its Phase 2 record.** It in turn superseded the
2026-08-14 description.

**Device A held NO usable Connected identity, account state or fixture at that
date, and sat at first-launch onboarding.** The Connected identity it carried
through Phase 2 —
`cfadb7cb-12d3-47cc-ac79-c574e5341eb1`, restored intact from the encrypted backup
— was **deleted by the D15 destructive run on 2026-08-15**, a legitimate gate,
not an accident. The container went with it: all 8 `Documents` files, `Scores`,
the Scores index, the journal and the root `AttachmentPrivacy.json`. Backend
counts dropped as predicted (`auth.users` 16 → 15).

**CORRECTED 2026-08-16 — `auth.users` is 16, not 15, and the device statement and
the backend statement are not the same statement.** D15's deletion landed exactly
as recorded; `cfadb7cb…` is provably absent. **A subsequent Sign in with Apple on
2026-08-15 20:08:05 UTC — after the run, ~34 minutes before the closure commit —
minted a new backend identity `5ae3faab…`**, which still exists. It has **no
`account_directory` row and zero Domain 3 residue**: 0 posts, follows, comments,
attachments and storage objects.

**The mechanism is explained by source, not merely consistent with a story.**
`AuthManager:596` guards the directory publish with
`guard !displayNameToPublish.isEmpty else { return }`, and its failure branch
only logs, under `#if DEBUG`. A sign-in on a device with no local profile name —
which is exactly what a factory-reset Device A had — mints `auth.users` and never
attempts the directory upsert. **Every new member passes through that state**, so
it is the normal first-run shape rather than an anomaly; the earlier
`44a6018e…` instance noted on 2026-08-13 had the same shape.

**The Apple credential has since been manually revoked**, so no client can
currently authenticate to that identity — which is why Device A holds nothing
usable while the backend identity remains. **[OBSOLETE 2026-08-25 — the
revocation is correctly recorded, the inference from it is not. SIWA later
returned the SAME `sub` and re-authenticated this identity. See the current rig
state above.]** **Retained as evidence, not deleted to
tidy the count.** It is **not** a C-36 fixture and must not be used as one: its
credential is revoked and it has already authenticated. It is a **Phase 3
reference case**, being the first observed instance of the "authenticated, no
membership record" state, and Phase 3's cleanup selector must key on
`pending_cleanup_at` alone so that identities of this shape can never be swept.

**The Phase 2 fixture no longer exists and cannot be re-created cheaply.** The
pre-Phase-2 media, the privacy map and the adopted-Score control were all
destroyed by the run that scored them. Re-authoring an equivalent would mean
rebuilding `a8eb050`, reinstalling it, and recreating every file by hand. Plan
around that rather than assuming a re-run is available.

**Device A's Apple credential for Études HAS been revoked — manually, by the
user, after the run.** Do not let that overwrite the historical result: the
in-app revocation during D15 was **`[C-44] revocation reason=delete-account
outcome=notAttempted(authorization/AuthorizationError/1001)`** — 1001 is
*canceled*, the re-authorization sheet was dismissed — after which **the account
deletion continued regardless**, which is the settled semantics, and the app
showed C-44's TN3194 step-2 manual fallback. **That result stands as recorded and
must not be rewritten as an in-app revocation success.** The manual Settings step
that the fallback asked for has since been completed, so no live Études
credential remains on Device A.

**One item survives from 2026-08-13 and is unrelated to any of the above:** a
**live Apple refresh token minted and abandoned by the C-44 gate (b2) exchange**
is still outstanding — nobody holds it, and it was never revoked, because the run
that would have cleared it used a different, later grant. It is **pre-existing
operational test residue, not created by Phase 2**, and it remains outstanding.

**DEVICE A'S SANDBOX SUBSCRIPTION FROM F3b HAS EXPIRED — established 2026-08-23
from production notification rows, not assumed.** The purchase at 2026-08-20
19:57 produced `SUBSCRIBED`/`RESUBSCRIBE`, then **11 hourly `DID_RENEW`**, then
`EXPIRED`/`VOLUNTARY` — consistent with Apple's documented sandbox cap of up to
12 renewals before auto-renewal turns off. **So the F3b entitlement CANNOT be
reused for S-1, S-2, B-24n, G11 or F10**; every one of those needs a live
entitlement and the fixture is spent. **[HISTORICAL — FOUR of the five were
subsequently discharged on later fixtures: S-1 and S-2 on 2026-08-25 (with S-3),
B-24n and F10 on 2026-08-30. **G11 was not, at that date** — its essential behaviour was
observed incidentally during S-1, where attestation fired unattended on a first
cold launch. **G11 was subsequently RUN AND PASSED as a scored gate on
2026-09-01**, on a resubscribed tester-2 fixture with the membership row deleted
under a guard. The paragraph is kept
because its sandbox-renewal-cap observation still holds.]** The tester also
reported `RESUBSCRIBE` rather than `INITIAL_BUY`, so it can no longer produce a
clean first-purchase observation either.

**Device B Release is UNTOUCHED by Phase 2** — still the established / lapsed
control fixture. No Phase 2 commit touched it and no Phase 2 run spent it.

**A build carrying no temporary instrumentation is installed on A**, from a
clean tree.

**Device B Release is the established / lapsed control fixture** — a lapsed member
still holding a live backend account, C-35's exact condition, shared with the
long-running Études Dev install. It was used only for C-44 gate (a), which wrote
nothing and made no network call. Do not spend it casually and never run Erase
All on it. **B-14's approval check no longer depends on it** — that closed on
2026-08-14 via Études Dev under a synthetic entitlement, which is also how
Account B was made Connected for the C-28 staging and the B-6 regression. That
route leaves the Release/lapsed fixture untouched and is the one to reuse
whenever Account B needs to be Connected.

Update this section as work lands.

**The four `APPLE_*` Supabase secrets are production infrastructure, not
instrumentation.** `APPLE_SIWA_P8_B64` (base64 of the `.p8` — base64 because a
multi-line PEM gets its newlines mangled in an env var, and the resulting
`importKey` failure looks nothing like its cause), `APPLE_SIWA_KEY_ID`,
`APPLE_TEAM_ID`, `APPLE_CLIENT_ID`. They were set for gate (b2) and deliberately
**retained** when its probe was removed, so that `revoke_apple_identity_v1` needs
no further handling of the private key. The `.p8` itself lives at
`~/.etudes-secrets/` (dir `700`, file `600`), outside the repo; `.gitignore`
already blocks `*.p8` and `*.pem`.

**Temporary instrumentation: NONE PRESENT.** `JWSFreshnessProbe` and its two
call sites were deleted on 2026-08-20 **the moment F3b was scored**, as its
standing condition required and as `ActivationTrace` and `MembershipTrace` were
before it. **Removal verified as a PURE DELETION rather than asserted:**
`MOTIVOApp.swift` is byte-identical to its state at `e157b1c^`, before the probe
existed, and both configurations compile clean. It earned its keep — `txID` was
added to it late, and that field is the only reason the P2 result can be
distinguished from a sandbox renewal. One inert `UserDefaults` key,
`u5a_jwsProbe_v1`, remains on Device A; it is disposable-fixture scratch and no
shipping code reads it.

**Earlier note, still true of everything before U5a.** The most recent was C-3's
foreground-timing probe, added and removed on 2026-08-14 within the same day.
Its removal was verified as a *pure deletion* — `git diff` against the pre-probe
commit is empty, so the tree is byte-identical to its state before the probe
existed, and both configurations compile clean. **Not to be confused with the
C-28/C-48 wipe-outcome lines, which are permanent** — those are outcome
reporting on a destructive path, in the same family as C-44's revocation line,
and the standing removal condition does not apply to them.

**Earlier temporary instrumentation: REMOVED.** `ActivationTrace.swift` and all
15 call sites were deleted on 2026-08-11 the moment C-38 closed, as the standing
condition required. Nothing of it ships. Removal was done by restoring the four
touched files to their pre-instrumentation state rather than by hand-editing the
call sites — no client code had landed in between, so the result is provably
identical to the tree before `402418c`, and Debug and Release both compile clean.

It earned its keep three times over: it produced the healthy activation sequence
(`docs/audit-findings.md`, "Activation path — observed behaviour"), killed two
C-38 hypotheses, re-verified C-24 on real StoreKit, and finally closed C-38
itself — the last of which no screen could have done, since the app sits in Solo
with a live entitlement whenever identity is absent, and "stayed Solo" is the
single observation both the healthy and the broken path produce.

**The `privacy: .public` lesson held.** Every line funnelled through one `emit`,
and every line was readable on device — unlike the previous effort. Reuse the
pattern if release-readable logging is ever needed again.

**One tooling correction for next time:** `log stream --device` no longer exists
on this macOS. The working retrospective route is
`sudo log collect --device-name "<device>"` followed by `log show` on the
archive. Running from Xcode is better still — `Logger` output with
`privacy: .public` appears live in the Xcode console, with no root required.

**Previous temporary instrumentation: removed.** `MembershipTrace.swift` and its
thirteen call sites were deleted once QA B2 passed on real StoreKit, as the
standing condition here required. It earned its keep — it diagnosed C-24,
produced C-1's only device evidence, and framed C-13's verification. One
lesson worth keeping: it was labelled "Release-capable by design" but only ever
read through Xcode, and on TestFlight every line arrived as `<private>`,
because `NSLog` with `%@` arguments is redacted when read from a device. If
release-readable logging is ever needed again, use `os.Logger` with
`privacy: .public`.

---

## Architectural invariants — FIXED. Do not revisit.

1. **The local journal is never deleted by any Connected or membership action.**
2. **If nobody else can see it, it does not belong on Supabase.**
3. **Reversible decisions may rely on client-side evidence. Irreversible
   decisions require authoritative server-side evidence.**
4. **Personal durability is independent of Connected membership and follows
   Apple's normal backup model.**

Settled after a four-phase client audit and a Supabase backend audit. Only
genuine new evidence contradicting one of them is grounds to reopen — not a
preference for a different design.

`docs/architecture.md` — the four data domains, plus designed-but-parked work.
`docs/audit-findings.md` — finding register (IDs C-n client, B-n backend).
`docs/qa-plan.md` — manual QA, used at each phase gate and for the RC.
`docs/pricing-launch-model.md` — pricing and the Founding 500 launch model.
**PLANNED, NOT IMPLEMENTED.**
`docs/phase-4-ca-residue-cleanup-acceptance.md` — **THE SIX LIVE
`connected_attachments` ROWS ARE CLEARED, 2026-09-04.** B-22's deliberately
retained residue (29 both-parties-deleted + 1 live-sender), **identified by the
account holder as test debris — evidence the database cannot supply** — and
cleared by explicit id after confirming the producing mechanism is already fixed
(`delete_account_v1` deletes both sides). **An explicit later disposition on new
evidence, NOT a claim that B-22 was wrong.** `connected_attachments` 31 → 25, all
soft-deleted; dangling 5 → 0; objects 11 → 10. **U4's one unmet criterion is now
satisfied here, not backdated.**
`docs/phase-4-u4-acceptance.md` — **P4-U4 / B-8 COMPLETE 2026-09-04. 4 orphaned
Storage objects deleted by explicit path; unreferenced 4 → 0, referenced still
11, no row deleted.** **It also corrects U1: the four were DIRECT-SEND objects
(`users/<uid>/connected/<assetID>`), not post attachments — both shapes have four
segments, so a segment COUNT could not tell them apart.** **B-8's guard was
applied on TWO keys** (`storage_path` and `asset_id`, the latter with no
`deleted_at` filter) plus a full-text scan; liveness never from the path prefix.
**A verification method was itself wrong** — an HTTP `GET` returned 200 after a
successful DELETE, so the run stopped itself; `storage.objects` is the
authority. **5 dangling references remain — all live `connected_attachments`
rows pointing at missing objects.** That is the INVERSE of B-8, pre-exists U4,
and needs its own decision.
`docs/phase-4-u3-noop.md` — **P4-U3 IS A MEASURED NO-OP, 2026-09-04 — the
PREDICTED SUCCESSFUL OUTCOME, not a skipped unit.** Private rows were **zero at
the U1 baseline and zero immediately pre-U3**, measured three ways including a
`GROUP BY` over the whole column domain, so there were **no explicit ids
eligible for purge, zero DELETE statements issued and zero rows deleted**. The
zero is now **defended** rather than merely observed — U2b, U2c and U2s close the
creating mechanism at three layers. **`UPDATE → false` remains deliberately
possible** as the transient fail-safe for unshare reconciliation (C-61). **This
is NOT a claim that production has never held private rows** — `posts` has no
audit column, and F-1's withdrawal of that claim stands.
`docs/phase-4-u2s-acceptance.md` — **P4-U2s IS LIVE IN PRODUCTION, 2026-09-04.
SHARED-ONLY IS NOW SERVER-ENFORCED.** `posts_insert_owner` gained one top-level
conjunct, `AND (is_public = true)`; deployed `with_check` md5
`fb1873d10077148c59180ec7d45edbcb`, byte-exact to the rehearsed local policy.
**It is a PEER of `enforcement_gate`, not nested inside it** — the gate returns
true when U6b enforcement is off, so a nested clause would evaporate with the
kill switch. **No UPDATE restriction** (C-61: demotion must stay possible).
**The schema default is still `false`, deliberately** — the guard rejects the
resulting value, so an omitted column is refused too. **Production behavioural
testing was impossible for me** (all 17 identities are Apple-only, zero
passwords; `service_role` bypasses RLS) so A/B/C/D/E ran on the byte-identical
local stack and production got structural verification; the behavioural half
folds into U2b's outstanding Device A run.
`docs/phase-4-u2c-amendment-acceptance.md` — **U2c COMPLETION AMENDMENT,
2026-09-04. THE FORBIDDEN STATE IS NOW UNREPRESENTABLE.** `op` is DERIVED from
`isPublic` and has no initialiser parameter, so `.publish + isPublic:false`
**does not compile** (discriminator: `error: extra argument 'op' in call`), and
`init(from:)` normalises a contradictory file to the SAFE reading `.unshare`.
**One declared migration:** a legacy queued item with `isPublic:false` now
converges to DELETION rather than demotion. **Read §5 before touching the
queue** — three tests that asserted the pre-amendment world were re-expressed,
and two now assert something stronger.
`docs/phase-4-u2c-acceptance.md` — **P4-U2c COMPLETE 2026-09-04, ZERO
PRODUCTION CODE.** The attachment-upload invariant is guaranteed by topology:
the only door into Storage for a post attachment is inside `uploadPost`,
`uploadPost` has ONE caller, and it sits behind an `.unshare`
guard-and-`continue`. The `op` boundary alone is **not** sufficient — `.publish`
+ `isPublic:false` is representable — and what closes it is that both call sites
pass the **same identifier** to `isPublic:` and `shouldPublish:`. Asserted, and
proven non-vacuous by reverting U2b and watching it fail.
`docs/phase-4-u2b-device-handoff.md` — **THE DEVICE A PROCEDURE. U2b IS
IMPLEMENTATION-COMPLETE / DEVICE-VERIFICATION-PENDING and must NOT be called
closed until this has been run.** Deferred, not waived: Device A's Sandbox
entitlement is expired (client expected **Solo**), and `connected_member()` is
**false** under active U6b enforcement with zero Production membership rows — so
a sandbox resubscribe **alone is insufficient**. **Enforcement is deliberately
not being weakened, and membership state not manufactured, for a test.**
`docs/phase-4-u2b-acceptance.md` — **P4-U2b COMPLETE 2026-09-04. SHARED-ONLY
UPLOADS ARE LIVE IN THE CLIENT.** Both call sites now pass `shouldPublish:
isPublic`, so a Share-OFF save and a Thought create **no server row**, and the
redundant bare `deletePost` is gone — the queue's demote-then-delete is the only
unshare semantics. **U2s is NOT started, so no old-client durability is claimed:
a pre-U2b build can still create a private row.** Also records the suite-pinning
policy and a planned positive control that could not be obtained (§4.1).
`docs/phase-4-u2a2-acceptance.md` — **P4-U2a-2 / C-61 RESOLVED 2026-09-04.**
The unshare is now a DURABLE INTENT in the existing queue: `op` discriminator
defaulted to `.publish` so legacy files decode, demote-then-delete, dequeue only
on confirmed removal, no retry cap. **Read §2 before touching Storage error
handling:** an ABSENT object returns `NoSuchKey`, a PRESENT-but-unpermitted one
returns `AccessDenied` — they are distinct, which is why fail-closed survives —
and the HTTP status is 400 with the 404 in the BODY. A prediction of this unit
was wrong and is corrected there.
`docs/phase-4-u2a2-durability.md` — **U2a-2 REVISED, 2026-09-04, NOT
IMPLEMENTED.** Today an unshare ENQUEUES (because the literals are still `true`),
and the queue is a file drained on every foreground — so an offline unshare
**converges with no further user action**. Both directions are measured. **U2b
plus an immediate-only demote/delete would destroy that**, and would leave B/C
settling permanently on a private row, which Phase 4 forbids. Fix: extend the
EXISTING queue with an operation kind; dequeue only when the row is gone.
`docs/phase-4-u2b-blocked-c61.md` — **U2b IS BLOCKED, 2026-09-04, and the
`shouldPublish` literals are UNCHANGED.** C-61: on the unshare path nothing ever
writes `is_public` (`patchPostMetadata` has one caller, inside `uploadPost`,
which needs `shouldPublish == true`), so a FAILED delete would leave the post
**publicly visible** while the member believes it withdrawn. Measured both ways
on the local stack — today the same action demotes the row to private, so U2b
would REGRESS the failure path. Smallest repair: **demote, then delete.**
`publishedURIs` is NOT the mechanism; its only reader is the Feed filter for
non-owned sessions.
`docs/phase-4-u2a-acceptance.md` — **P4-U2a / C-60, COMPLETE 2026-09-04.** Two
predicates in `PublishService` (`:209`, `:304`) so an un-share reaches deletion
in `.backendConnected`, not only `.backendPreview`. **The behavioural suite was
run against the PRE-fix code and failed** — that discriminator is what makes it
evidence. Fail-closed intact; zero production delta; **not device-verified in
production and cannot be until U2b**.
`docs/phase-4-u1-baseline.md` — **P4-U1 measurement baseline, captured
2026-09-04 at `78e2002` before any Phase 4 change.** The pre-change production
numbers, B-8's reference-set method, the 16-assertion structural baseline, and
the predictions U2/U2s/U3 are scored against. **U2s's invariant test CANNOT be
run with `supabase db query --linked`** — `cli_login_postgres` holds `bypassrls`,
so every attempt would pass regardless of the policy while writing the forbidden
row. It goes through PostgREST with a real JWT.
`docs/phase-4-scope.md` — Phase 4 scope record. **SCOPED AND CORRECTED
2026-09-04, NOT STARTED.** Read it before touching the publish path. It measures
**101 posts, all public, zero private, at that baseline** — so "purge historic
unshared rows" has no population to purge at the measurement. **That is a claim
about the present population and NOT about history:** `posts` has no audit
column and no history table exists, so a private row created and later deleted
would leave no trace, and an earlier revision's "never exercised" claim is
withdrawn. It also records **C-60** (un-share does not delete in
`.backendConnected`, so reverting `shouldPublish: true` naively creates
permanent invisible residue) and the **durability decision**: one clause on
`posts_insert_owner` makes shared-only server-enforced, which covers the Storage
objects too because the post row is written before them.

---

## Product principles

These are interaction principles rather than architectural invariants.

- **Reduce ceremony between the musical impulse and the musical record.**
- **Assistance should never override explicit user intent.**
- **Live state is useful; historical state should never become guilt or performance pressure.**
- **Reflection over measurement. Continuity over productivity.**

---

## Settled decisions

- Only sessions the user explicitly shares are uploaded. Solo mode uploads
  nothing. Unsharing deletes the backend post and any storage objects no longer
  required by surviving recipient references.
- Notes and each attachment keep independent privacy controls within a shared
  session. Only explicitly included components upload.
- "Share with followers" defaults ON. This is intentional, chosen from
  TestFlight evidence that the opposite default produced empty feeds. Users
  have a persistent "Default to Private Posts" preference. Copy must describe
  this accurately rather than claiming "private by default" of Connected.
- Client StoreKit governs Études vs Connected (access only). Apple's App Store
  Server Notifications are the authority that **schedules** membership-expiry
  cleanup — **they never execute it**. A live authoritative read from Apple
  immediately before cleanup is required, and cleanup does not run without one.
  See "Cleanup authority" under the Phase 3 section. Explicit user-triggered
  **Erase All Études Data** remains a valid client-initiated destructive action.
- Expiry removes Connected, not the musician. Local journal, Scores, media,
  profile name, avatar, location, instruments, activities, settings and
  preferences all survive untouched. **What expiry removes and retains on the
  *backend* is a separate, deliberately distinct policy from account deletion —
  see the Phase 3 expiry retention matrix.** `CLAUDE.md` was silent on backend
  expiry semantics between `dac78af` (2026-08-13), which narrowed the retention
  bullets to deletion, and the Phase 3 record above.
- **Deleting a Connected account deletes the departing member's own backend
  UGC** — their comments on others' posts, and the Connected attachments they
  sent, rows and objects, even where recipients hold live inbox references.
  **Revised 2026-08-13 on an App Review constraint, not because the earlier rule
  was wrong.** Retention was correct given the architecture as it stood; Apple's
  account-deletion guidance treats content shared with others as UGC that
  deletion must remove, and the deployed representation could not sustain the
  "that is the recipient's copy" defence — `sender_user_id` is NOT NULL with no
  FK, and the path CHECK pins the object under `users/<sender>/`. Verified
  end-to-end on Device A.
- **B-19 is untouched and is the line to hold:** content authored by somebody
  else and merely *addressed to* the departing member must survive. The comments
  predicate is scoped to `author_user_id` alone for exactly that reason.
- **Membership never gates account deletion.** Deletion authority is
  `auth.hasConnectedIdentity`, deliberately entitlement-free — a lapsed member
  must never re-subscribe to delete their account (C-35). It had to be fixed
  twice: the second gate was an entitlement dependency laundered through a
  `UserDefaults` key, invisible to a structural audit for identifiers.
- Recipient copies already adopted into local, recipient-owned storage (Scores),
  and files already downloaded to another person's device, are out of scope —
  no backend deletion can reach them. The confirmation copy says so.
- M13 (iPad) and M14 (personal iCloud sync) are deliberately deferred. Their
  absence is not a defect.

---

## Implementation phases

One phase at a time. Tight scope, green build, explicit verification, reviewed
before moving on. Six bounded, separately reviewable phases — not one rewrite.

1. **Safety** — C-13 first (purchase-path hang); safe `delete_account_v1`;
   directory + follow-policy hardening; remove client expiry-deletion
   authority; Scores erase defect; zero-dependency cleanup; cheap verification
   tests (staged-video measurement, B-6 two-account test).
2. **Durability** — restore Apple backup participation for permanent user
   data, including the reconciliation pass for already-excluded media. Keep
   excluding staging and timer scratch.
3. **Membership authority** — server-side entitlement state; App Store Server
   Notifications; Billing Grace **enabled Sandbox-first and only promoted to
   production after handling is accepted**; replay protection; idempotent
   processing. Plus the expiry lifecycle — invisible presence on lapse, a 60-day
   quarantine, and cleanup under its own retention policy by its own worker,
   gated on a live Apple read. Plus B-23's reproducible local backend and the
   four carried backend verifications it unblocks. Scope frozen 2026-08-16; see
   the Phase 3 section at the top of this file.
4. **Shared-only architecture** — shared-only uploads; remove the accidental
   analytics mirror; purge historic unshared rows; align onboarding, settings
   and App Store privacy disclosures.
5. **Remaining client fixes** — duplicate Score adoption; staged-video work if
   measurement justifies it; playback rate (AttachmentViewerView only, local
   and remote audio/video, discrete 50/75/100%, pitch preserved, no looping,
   no PracticeTimerView changes, no MediaTrimView carry-over, TestFlight soak);
   accessibility and polish.
6. **Cleanup** — obsolete backend code, AVFoundation deprecation sweep,
   architectural leftovers.

Verification gate after each phase. RC QA confirms an already-tested system.

---

## Per-phase working rules

- Restate the agreed scope before proposing any implementation.
- Keep changes strictly within that scope.
- Preserve existing architecture. Prefer subtraction over new abstractions.
- Surface assumptions before making changes; never fill gaps with invented
  behaviour.
- Finish with clear verification steps.
- Verify before asserting. Several audit findings were wrong because behaviour
  was inferred from names and structure rather than checked.

---

## Environment

- iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), deployment target iOS 18.5.
- Flat source layout via `fileSystemSynchronizedGroups` — everything in
  `MOTIVO/` is auto-included in the app target.
- Debug and Release use different bundle IDs, and **only Release can transact.**
  Debug is `com.samueldixon.motivo.dev`, which App Store Connect does not know,
  so `Product.products(for:)` returns an empty array and you get C-29's
  signature — "Membership options are unavailable", no error beneath it —
  instead of a purchase. The shared scheme's Run action is Release. Keep it
  there.
- **The shared scheme no longer pins a StoreKit configuration** (changed
  2026-08-11; **silently reverted 2026-08-14 by `0daecd1`, restored 2026-08-20 by
  U5a — C-52**, and the six-day gap is why this bullet is not self-verifying). Running from Xcode now gets **real StoreKit against Apple's
  sandbox by default**, which is the inverse of the setting that masked C-9,
  C-29, C-30 and C-38. `Etudes.storekit` is retained but **opt-in only**: attach
  it in Run → Options when synthetic behaviour is deliberately wanted, and
  detach it afterwards. A pinned configuration applies **regardless of build
  configuration**, so it silences real StoreKit in Release too — which is
  exactly how a Release QA pass was once mistaken for real-StoreKit evidence.
- **Preferred StoreKit testing loop**, documented in full in `docs/qa-plan.md`:
  Xcode + Release + StoreKit Configuration **None** + a dedicated Sandbox Apple
  Account. **It is not cheaply repeatable — corrected 2026-08-12.** This line
  used to claim that clearing the tester's purchase history in App Store Connect
  restores a first-purchase state "without creating a new account and without
  waiting for a subscription to lapse". **That was written from expectation and
  is false.** Observed on Device B: history cleared, >10 minutes waited, app
  force-quit and relaunched, tester signed out and in, device restarted — and
  the subscription stayed live, with Apple's own Manage Membership sheet showing
  it active and renewing. **Two Apple surfaces disagreed** — Settings → Sandbox
  Apple Account → Subscriptions simultaneously read "You do not have any
  subscriptions". That disagreement is the observation; **where the retained
  entitlement state lives is unknown and is not needed for any current work.**
  **A clean first-purchase state needs a new sandbox
  tester or a waited-out period**, so design runs to need one purchase rather
  than several. Note the one clean run on record, C-38's, used a *fresh* tester
  — clearing has never been observed to work.
- **To *observe* a lapse rather than re-purchase, cancel the subscription.**
  Access runs to the period end, so cancelling converts an open-ended run of
  daily TestFlight renewals into an expiry on a known date. That is the tool for
  C-1 / C-26 lapse testing. Device-side sandbox controls also include **Test
  Interrupted Purchases**, which is Apple's own way to produce the contended
  purchase state C-13's hazard needs — better than throttling. See
  `docs/qa-plan.md` step 4.
- **The two sandboxes keep different time.** Development sandbox (run from
  Xcode) honours the tester's accelerated renewal rate, so a Monthly cycle
  completes in about 30 minutes. **TestFlight ignores that rate entirely** —
  Apple documents daily renewal, up to six times in one week, so a TestFlight
  entitlement lasts roughly six days and cannot be reset on demand. That is why
  Device B read "Renews 13 August" on a tester configured for five minutes;
  nothing was misconfigured. Runs needing repeated first purchases belong in the
  development sandbox.
- **TestFlight is still a required checkpoint before StoreKit work is settled.**
  The sandbox loop proves the purchase path; it does not prove the artifact beta
  testers actually install. Cut a build at the next clean checkpoint and run QA
  Group B against it.
- 193 `#if DEBUG` blocks. Always verify Release as well as Debug.
- **The unit test target RUNS, since 2026-08-23 (C-54), and holds 7 passing
  tests.** This bullet used to read "an empty template ... compile-clean, not
  test-verified", and that **described a symptom without its cause**: the target
  could not be executed at all, because `TEST_HOST` and `@testable import` both
  still named the pre-rename product. Nobody noticed because nobody ran it.
  `xcodebuild test -only-testing:MOTIVOTests` now works with no override.
  Coverage is deliberately narrow — the PURE membership-client pieces only.
- Build: `xcodebuild -project MOTIVO.xcodeproj -scheme MOTIVO -configuration
  {Debug|Release} -destination 'generic/platform=iOS Simulator' build`
