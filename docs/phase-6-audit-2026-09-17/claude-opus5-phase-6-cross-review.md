# Études Phase 6 — reciprocal cross-review (Claude Opus 5 reviewing Codex)

**Reviewer:** Claude (Opus 5), Claude Code. **Date:** 17 September 2026.
**Baseline:** `feature/solo-connected` @ `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`,
re-verified unchanged at the end of this review, with all three dirty-file
hashes identical to the audit baseline.

**Reviewed:** `claude-phase-6-audit.md`, `claude-phase-6-comparison.md` and
`claude-phase-6-evidence/` (authored by Codex, as disclosed inside them).
**My own reports are unchanged:** `claude-opus5-phase-6-{scope,audit,comparison}.md`.
This file is additive. **Read-only throughout** — no fixes, commits, pushes,
deploys, device operations or production mutations; Codex's originals and the
dirty invitation documents are untouched.

I verified P6-I-01…05 against source myself rather than against Codex's probe
outputs, so that a defect in a probe could not propagate into agreement.

### Amendment log — 17 September 2026, after Codex's second review

Four corrections accepted; **none rebutted**. Originals are shown struck or
quoted in place rather than deleted, so the overstatement stays findable.

1. **§3 heading and framing** — *"P6-I-02 and F-2 share one root cause"* was
   wrong about P6-I-03 (swallowed persistence failure, not 204 semantics) and
   imprecise about P6-I-02 (root cause is missing originating ownership; only
   its false-success withdrawal consequence shares F-2's mechanism). Batching
   still stands; **three distinct causes need three distinct fixtures.**
2. **§3 remedy** — demoted from *"the joint remedy"* to **design constraints**.
   *"Proceed to `deletePost` either way"* is **withdrawn**: continuing past a
   zero-row demote is correct only under verified ownership and a valid session,
   never after a transport or auth failure. **"Confirmed absent" cannot be an
   RLS-filtered empty SELECT** — that reproduces the bug one level up.
3. **§6 count** — *"Nine distinct findings"* is **withdrawn**; it reached nine by
   collapsing F-4…F-14 into one row and labelling that row P3, which silently
   downgraded **F-10 (P2 process drift)**. Now eight individually ranked
   correctness/performance findings plus a separately itemised set of risks,
   drift and cleanup, with no total offered. **P6-I-05's bound restated:**
   ordinary overlap can still arise after the 30-second cooldown while B is
   pending.
4. **§6 closing** — my negatives (N-1…N-12) scoped explicitly to the server
   boundary, which P6-I-02 sits above.

Codex's original reports and my own audit, scope and comparison are unchanged.

---

## Headline

**All five of Codex's findings are valid. I confirm every one against source,
and I withdraw nothing of my own.** The two audits overlap almost nowhere, which
is the most useful thing to come out of this pair — see §4.

**The single most valuable result of the cross-review is not a finding either of
us made. It is that the remedies we each proposed for P6-I-02 and F-2 are,
separately, both wrong**, and that one *consequence* of P6-I-02 — a withdrawal
consumed as a false success — runs on the same zero-row reporting contract as
F-2. They belong in one batch. **They do not share a root cause**, and neither
does P6-I-03, which is in the same batch for a third reason again. §3, as
amended.

**I accept ten of Codex's corrections in full across its two reviews, and rebut
none.** Two were plain errors on my part: the invitation wording, and a finding
count that silently downgraded one of my own P2s. §5 and the amendment log.

---

## 1. Verification of P6-I-01…05

Each traced independently from source at the cited lines.

### P6-I-01 — attachment-copy failure becomes a successful save · **CONFIRMED · P1 agreed**

Verified in full, on both editors.

- `MOTIVO/AttachmentStore.swift:150-158` — `saveDataWithRollback` throws from
  `data.write(to:options:[.atomic])` at `:154`.
- `MOTIVO/PostRecordDetailsView+Attachments.swift:826-835` — the `catch` rolls
  back files, **deletes every already-created attachment from the context**
  (`:831`), prints, and `break`s. The function then runs on through the
  thumbnail block and **returns normally at `:869`**. No error is returned or
  thrown, and the return type carries no failure channel.
- `MOTIVO/PostRecordDetailsView.swift:1872-1874` — the caller invokes it, then
  `try viewContext.save()` in a `do` block that cannot see the failure.
- `MOTIVO/PostRecordDetailsView.swift:1929-1932` — on the success path
  `consumedIDs` is `stagedAttachments.map { $0.id }`, i.e. **all staged ids, not
  the committed ones**, passed to `StagingStore.removeMany`, which deletes the
  files (`MOTIVO/StagingStore.swift:547-556` → `:375-389`).

**The sibling is worse, and Codex under-stated it.** In
`MOTIVO/AddEditSessionView+Attachments.swift:546-554` the catch has the same
shape, but `stagedAttachments.removeAll()` at `:574` runs **unconditionally after
the loop, before the caller saves** (`MOTIVO/AddEditSessionView.swift:2070-2073`).
So in that editor the in-memory staged items are discarded on the failure path
even if the subsequent save were to fail. Codex marked this path
"source-confirmed, not separately runtime-probed", which is fair; I am adding
that the unconditional clear makes it strictly worse than the probed one.

**Severity: I agree with P1, and the strongest argument is one Codex already
made — that the two saves are independent.** A 300 MB video write can fail on a
full disk while a Core Data row of a few hundred bytes still commits. C-3
measured 278.7 MB of staged video on a real device, so the precondition is not
exotic.

**Limitation I would add to the record:** the probe forced the throw with an
existing-directory destination, which Codex states plainly. Neither of us has
shown that an iOS low-disk condition produces a throw from `data.write` while
Core Data's save succeeds. That ordering is *plausible and untested*, and it is
the one assumption the P1 rating rests on. I would not downgrade the finding for
it — the swallowed error is a defect whatever triggers it — but the batch's
validation should include a fault-injected metadata-save control, which Codex's
proposed validation already names.

### P6-I-02 — queued work is not bound to the account that created it · **CONFIRMED · P1 agreed, with a reachability qualification**

Verified in full.

- `MOTIVO/SessionSyncQueue.swift:71-96` — `PostPublishPayload` has **no owner
  field**.
- `:532-537` — one installation-wide file,
  `Application Support/MOTIVO/SessionSyncQueue_v1.json`, with no per-identity
  scoping.
- **`AuthManager.swift` contains zero references to `SessionSyncQueue`** — I
  checked the whole file, not just the two cited lines. Neither `signOut()` nor
  `clearConnectedIdentity(reason:)` partitions, holds or clears the queue.
- `MOTIVO/MOTIVOApp.swift:398` flushes on foreground.
- `MOTIVO/BackendShim.swift:961` takes the **current**
  `AuthManager.canonicalBackendUserID()` and `:1043` sends it as
  `owner_user_id`.

**Additional evidence Codex did not cite, which strengthens the second
consequence.** Every `posts` write in the client is scoped by `id=eq.<uuid>`
**and nothing else** — `BackendShim.swift:339`, `:378`, `:1549`, `:1581`,
`:1636`, `:1675`, `:1802`. Ownership is enforced only by RLS, and RLS expresses a
non-match as **zero rows**, which PostgREST reports as 204 / `[]`. So B flushing
A's queued withdrawal is not merely unscoped — it is **affirmatively reported as
success and dequeued**, and A's post survives with the withdrawal consumed.

**Reachability qualification, offered as a severity refinement rather than a
rebuttal.** Both consequences need a *second Apple ID* to become Connected on the
same installation: Sign in with Apple returns a stable `sub` per Apple ID and
team (measured in this project on 2026-08-25), so A → sign out → A is the common
case and is harmless. A shared, sold-on or test device is the realistic trigger.
I would keep P1 — the failure is silent, irreversible from the member's side,
and cross-account — but the record should carry the precondition so the batch is
not scoped as though every member is exposed.

### P6-I-03 — a failed queue write can restore an older publish after Unshare · **CONFIRMED · P1 agreed**

Verified in full, and this is the cleanest of the five.

`MOTIVO/SessionSyncQueue.swift:503-510` — `persist()` returns `Void` and its
`catch` only calls `BackendLogger.notice`. `:247-252`, the operation-replacement
path, mutates `items[index]`, calls `persist()`, logs *"Queue intent
replaced"* and returns. **The log line announces a durability that was not
achieved.** `:512` `load(from:)` then reads whatever is actually on disk at the
next launch, which is the superseded `publish`.

Codex's probe is the right shape: a genuine unwritable parent directory, the
unmodified queue, and a decode of the actual file afterwards. Its stated limit —
atomic replacement prevents torn writes but does not make a failed replacement
succeed — is exactly the right distinction.

**One addition.** This is not only an unshare problem. `persist()` is the sole
durability primitive for the whole queue, so the same swallowed failure silently
loses **any** newly enqueued intent, and `acknowledge` likewise cannot report a
failed dequeue — which is the mirror case (a completed publish that re-sends).
Codex's proposed validation already lists "failed dequeue persistence", so this
is a framing addition, not a gap.

### P6-I-04 — opening Lists overwrites an unreadable library · **CONFIRMED · P2 agreed, and slightly broader than stated**

Verified, and **this is the finding I am most glad Codex made, because I read
both of these functions and missed it.**

`MOTIVO/TasksManagerView.swift:1128-1134` — the two `try?` decodes fall through
silently. `:1150-1152` — `defaults.set(data, forKey: globalTaskSetsKey)` runs
**unconditionally**, so `merged` (which is `[]` when nothing decoded and no
legacy key exists) replaces the damaged bytes. Merely opening the screen is
destructive.

**Broader than Codex stated, in one respect.** The guard at `:1128` is
`if let data = defaults.data(forKey: globalTaskSetsKey)`. A value stored under
that key with the **wrong type** (not `Data`) fails that guard entirely, skips
the whole block — and is still overwritten at `:1150`. So the loss covers
"present but unreadable" *and* "present but wrong type", and the wrong-type case
never even reaches a decode attempt.

**The contrast Codex draws is the sharpest part and I confirm it.**
`MOTIVO/SavedList.swift:106-115` distinguishes absent (`return []`) from
unreadable (`throw .damagedLibrary`) correctly, and
`MOTIVOTests/ConnectedListAdoptionTests.swift:104-114`
(`testUnreadableLibraryIsNeverOverwritten`) asserts exactly the safe behaviour —
**on the adoption API only**. Two readers of one key, one safe and one
destructive, with the passing test attached to the safe one. That is a good
example of the brief's warning that existing tests are evidence to assess rather
than authority.

**This intersects my F-1 directly.** F-1 is about `:1150-1152` writing the
*merged legacy content* back over the global key; P6-I-04 is about the same line
writing *emptiness* over unreadable content. **Same statement, two distinct
losses.** They should be fixed together, in one reader/migration contract, and
neither of us should claim the other's half.

### P6-I-05 — a late attestation completion can undo a coordinator reset · **CONFIRMED · P2 agreed, with a reachability narrowing**

Verified. `MOTIVO/MembershipAttestationCoordinator.swift:116-120` — after
`await task.value` the awaiting owner sets `inFlight = nil`,
`isAttesting = false` and `lastOutcome = outcome` with **no generation or task
identity check**. `reset()` at `:126-141` cancels and clears, but the task is
`Task<Outcome, Never>` wrapping a service that converts errors into an ordinary
outcome, so cancellation does not prevent the continuation resuming and
overwriting the cleared state. Reachable from
`MOTIVO/MOTIVOApp.swift:422`.

**Codex's restraint here is correct and worth preserving verbatim into the
register:** this establishes stale diagnostic state and broken single-flight
ownership, and **not** a membership-authority bypass, binding error, token
resurrection or device-visible wrong alert. I checked and agree — the server
re-verifies on every attestation, and the coordinator holds no authority.

**Narrowing I would add.** `reset()` clears `lastAttemptAt`, B's start sets it,
and the late completion **does not restore it** — it writes only the three fields
at `:117-119`. So the 30-second cooldown at `:100-103` still throttles ordinary
triggers, and the "three concurrent invocations" outcome requires a
`force: true` caller. In the shipping app `force: true` exists at exactly two
sites, both purchase/restore:
`MOTIVO/MembershipSelectionView.swift:345` and `:395`. Codex's own probe text
says "a third **forced** call", so this is consistent with its evidence — it just
is not stated as a bound. It makes P2 the right severity rather than something
higher.

---

## 2. Corrections and additions to Codex's audit

Nothing here changes a finding's validity. All are refinements.

1. **P6-I-01, sibling path.** Record that
   `AddEditSessionView+Attachments.swift:574` clears `stagedAttachments`
   **unconditionally after the loop**, so that editor loses the staged items on
   the failure path before its caller saves. Stated as equal to the probed path
   in the current text; it is worse.
2. **P6-I-02, mechanism.** Add that the client scopes every `posts` write by id
   alone, so the cross-account withdrawal is not merely misdirected but
   **reported as success** by the 204/zero-row path. This is the join with my
   F-2 (§3).
3. **P6-I-02, reachability.** Add the second-Apple-ID precondition, so severity
   is not read as "every member".
4. **P6-I-04, breadth.** Add the wrong-type case, which bypasses both decodes and
   is still overwritten.
5. **P6-I-05, bound.** Add that `lastAttemptAt` is not restored, so the extra
   concurrency needs a `force: true` caller and the cooldown otherwise holds.
6. **C-17/C-54 disposition.** Codex's table says *"There are 68 unit-test Swift
   files; that is an inventory, not a count of executed tests"* — correct and
   properly hedged, and its §6 records that no unit target was run. **I ran it,
   so the count exists.** On this baseline,
   `xcodebuild test -only-testing:MOTIVOTests` on iPhone 17 Pro returns
   **`** TEST SUCCEEDED **`: 537 test cases across 71 suites — 534 passed, 0
   failed, 3 skipped.** The three skips are deliberate and self-reporting
   (`XCTSkipUnless` at `MOTIVOTests/SyncQueueOrderingTests.swift:410`, `:433`,
   `:455`) and are not counted as passes. 71 suites from 68 files because some
   files declare more than one. This turns Codex's inventory into a measurement
   and gives every proposed batch a regression baseline.
7. **Build-warning counting.** Codex is right to warn against comparing a raw
   155 against an older count. We independently agree on the number that
   matters: **77 unique deprecation diagnostics**, plus one App Intents note,
   zero errors, zero non-deprecation warnings. Two toolchain-independent
   measurements agreeing raises confidence in my F-12's correction of C-22's
   "53".

---

## 3. The join: one consequence of P6-I-02 shares F-2's mechanism, and both our remedies were wrong

This is the part of the cross-review that changes the plan.

> **AMENDED after Codex's second review — the original heading and framing
> overstated the join, and the correction is accepted in full.** Three distinct
> root causes are involved and must not be collapsed:
>
> - **P6-I-02's root cause is the absence of originating ownership** on a queued
>   intent. Its *first* consequence — A's publish uploaded as B, to B's audience
>   — owes nothing to 204 semantics and would occur under any status code.
>   **Only its second consequence**, A's withdrawal consumed as a false success,
>   shares F-2's zero-row behaviour.
> - **F-2's root cause is the zero-row/204 reporting contract** on a write the
>   client scopes by id alone.
> - **P6-I-03's root cause is a swallowed persistence failure**
>   (`SessionSyncQueue.swift:503-510`) and has **nothing to do with 204
>   semantics**. My §6 Batch 2 originally asserted that all three "share the
>   204/zero-row root cause"; that was wrong about P6-I-03 and imprecise about
>   P6-I-02.
>
> **Batching them together remains sensible** — they interact on the same
> withdrawal path and a fix to one changes what the others' tests must assert —
> **but they need distinct regression tests keyed to distinct causes**: an
> ownerless legacy intent, a zero-row write, and an unwritable queue file are
> three different fixtures and none of them exercises the other two.

**The mechanism shared by F-2 and P6-I-02's second consequence.** PostgREST
answers a write that matched zero rows with
**204 / `[]`**, and every `posts` write in the client is scoped by `id=eq.<uuid>`
with ownership left to RLS. So "denied by RLS", "not my row" and "already gone"
are indistinguishable from "done" at the client. This project measured that fact
for itself in C-43 and fixed it there with `Prefer: return=representation` plus a
row count — the correct idiom is already in the tree twice
(`BackendShim.swift:874`, `ConnectedAttachmentSharing.swift:335`).

- **My F-2** found it on the *demote* step and mis-stated the consequence.
- **Codex's P6-I-02** found it on the *cross-account withdrawal* and correctly
  called it "an empty SELECT plus zero-row PATCH/DELETE can be reported as
  success".

Neither of us identified it as one cause with two faces.

**Codex's correction to my remedy is right, and it is the important one.** Making
a zero-row demote a hard failure would return from `unsharePost` before
`deletePost` is ever called — and `posts_delete_owner` is **deliberately
ungated** so that a lapsed member can withdraw and delete without re-subscribing
(C-35, invariant). My fix as written would have converted a silent-success into a
**permanent block on withdrawal for exactly the population C-35 exists to
protect.** I withdraw that remedy.

**Codex's own remedy for P6-I-02 is also insufficient on its own:** persisting
the originating account and verifying it before dispatch stops B from *sending*
A's intent, but it does not stop a *legitimate* owner's zero-row write from being
read as success — which is F-2, and which is also how a queued item gets dequeued
after doing nothing.

**Design constraints for the joint batch — NOT a finished or approved
algorithm.**

> **AMENDED after Codex's second review.** The three numbered items below were
> originally written as "the joint remedy", which claimed more than I had
> established. They are **constraints any acceptable design must satisfy**, and
> two of them were unsafe as literally written. The corrected form:
>
> 1. **Demote with `Prefer: return=representation` and use the row count as
>    evidence, not as a verdict.** Proceeding to `deletePost` after a zero-row
>    demote is correct **only under a verified originating identity and a valid
>    session**. **Do not continue generically after a transport failure, a 401 or
>    a 403** — those mean the write's outcome is unknown or the caller is not
>    authorised, and continuing to a destructive step on unknown state is the
>    error this whole finding is about. The original wording, *"proceed to
>    `deletePost` either way"*, is withdrawn.
> 2. **"Confirmed absent" cannot be established by an empty SELECT.** Codex is
>    right and this is the sharper half of the correction: `posts_select_public_
>    or_owner` filters by RLS, so a query run as B against A's row returns `[]`
>    because **B cannot see it**, not because it is gone. A naive absence check
>    reproduces the exact bug one level up. Absence may only be concluded under
>    the **captured originating identity**, via an **owner-visible** SELECT, with
>    **identity consistency re-checked across every await** — because the
>    identity can change between the delete and the confirmation.
> 3. **Bind the queued intent to its originating account** (Codex's P6-I-02 fix).
>    This is a **precondition of (1) and (2)**, not an independent third step:
>    without the captured identity, neither the ownership verification in (1) nor
>    the owner-visible confirmation in (2) can be performed at all.
>
> **C-35 must survive all three.** A lapsed member must still reach the
> deliberately ungated delete. Satisfying that *and* (1)'s authorisation
> requirement is the genuinely hard part of this design, and it is unresolved
> here — neither auditor has proposed a mechanism that demonstrably does both.
> **That is work for the batch's design step, with Samuel's agreement, not
> something either report has settled.**

**Batching.** Codex's Batch B and my "Batch B" should merge into one unit,
validated with a shared matrix — entitled owner, unentitled owner, wrong owner,
already-absent row, failed storage step — **with separate fixtures for the three
distinct causes** named in the amendment above: an ownerless legacy intent
(P6-I-02), a zero-row write (F-2), and an unwritable queue file (P6-I-03). A
green result on one of those fixtures says nothing about the other two.

**One qualification of mine that Codex is right to press, accepted:** a post left
at `is_public = true` is **not** presently publicly readable, because
`posts_select_public_or_owner` also requires `owner_entitled_until > now()`. The
residual exposure is **deferred to re-entitlement**, not immediate. My audit's
F-2 text says "the exact state C-61 exists to prevent" without that caveat, and
the caveat materially lowers the immediate impact. It does not change that the
code asserts a safety property it does not deliver.

---

## 4. Agreements, additions, and why the overlap is so small

**Direct agreement, reached independently:** the Release build result (succeeded,
zero errors, 77 unique deprecations); that C-22 stays P3 absent a demonstrated
runtime consequence; that C-12 is dead-code cleanup and not a reachable deletion
defect; that C-97 part 2 remains the right target and QA7 does not close it; that
C-96's equality guard is unimplemented and no loop was reproduced; that B-40
stands and the invitation documents grant no implementation authority; that
Phase 3's closure does not discharge the release obligations; and that Phase 6
should keep a bounded cleanup remit with small correctness batches beside it.

Codex has separately confirmed my **F-1** (legacy-mirror resurrection), **F-2**
(zero-row demote), and — by its own source check — **F-5**, **F-7** (all 15 type
names), **F-8** and **F-9**. I have confirmed all five of its findings. **Neither
audit has had a finding rebutted.**

**Why the overlap is nearly zero, and why that matters for the plan.** The two
passes divided almost perfectly by *method*:

- **Codex went deep on failure paths it could execute**, building four disposable
  probes and reproducing narrow failures — the swallowed commit error, the
  unwritable queue file, the damaged Lists value, the forced coordinator overlap.
  Every one of its five findings is a **runtime-ordering or error-handling**
  defect that a source read alone tends to rationalise away.
- **I went wide on structure I could enumerate exhaustively** — all 33 policies,
  562 column grants, all 12 triggers, every `enforcement_gate` call site, every
  declared type, every unguarded `print`, the whole warning census, and the
  unit-test suite. My findings are **state-machine and invariant** defects
  (the resurrection path, the false authorisation claim, main-thread work) plus
  verified negatives.

**The two method blind spots are complementary, and both are now covered — but
neither pass covered the third.** Neither of us exercised a device, a live
backend, or a running UI. Every conclusion in both reports is source-, probe- or
catalog-derived. **The combined report should say that once, plainly**, rather
than letting the breadth of two audits imply coverage neither has.

---

## 5. Codex's corrections to my audit — my response

**Accepted in full, with an error of mine acknowledged.**

1. **F-4, drone mechanism — ACCEPTED, with a refinement.** You are right that I
   have not measured which callback or guard fired, and that "output UID and
   sample rate unchanged" is a hypothesis about *why*, not an observation. I
   separate the two claims:
   - **Deductive, and I still hold it:** `DroneEngine.start` has exactly two call
     sites, both user controls (`DroneControlStripCard.swift:36`, `:227`); there
     is no `onChange(of: droneIsOn)`; `hardStop()` calls `engine.stop()` and
     sets `output = nil`. So **no in-app path can resume a drone the engine
     invalidated.**
   - **Hypothesis, which I now label as such:** that the route-identity guard at
     `DroneEngine.swift:241-246` held because outputs and sample rate were
     unchanged. **Withdrawn as an assertion.**
   I would add one datum that narrows the space without resolving it: the poll at
   `:256-262` invalidates if the render callback makes no progress for **more
   than one second** (`clock() - lastProgress > 1`). QA8 reports a gap of *"a
   second or so"*, which sits on that boundary — so either the callback kept
   running through an audible-only gap, or the run came close to the stall
   watchdog. **The device mechanism stays unresolved in the combined record**, as
   you ask, and the discriminator I proposed (watch the drone button's active
   highlight through one unplug) is cheap and settles it.
2. **F-6, blanket delete on deliver failure — ACCEPTED, and this is a genuine
   defect in my proposed remedy.** Deleting the uploaded object on *any* deliver
   failure is unsafe when the INSERT committed and only the response was lost:
   that deletes an object live rows reference, which is strictly worse than the
   orphan it cleans. **Amended remedy:** clean up only on a *definite* rejection —
   a PostgREST 4xx, i.e. the RLS/constraint refusal — and never on a transport
   error, timeout or cancellation. Anything ambiguous must be reconciled, not
   deleted, which is the same delivery-idempotency question your "send
   response-loss ambiguity" item raises. **Those two should be scoped together**,
   and F-6 should not ship without it.
3. **Invitations wording — ACCEPTED; I was wrong.** My audit §3 says *"Not
   implemented, not approved, not legally cleared"*, which conflates three
   different states. `docs/connected-invitations-direction.md:3` reads
   **"SCOPE NOW APPROVED; NOT BUILT"**, and `:5-12` records that Samuel approved
   the scope document, required Études styling, confirmed the follow-request
   semantics and `etudes.app` ownership, while *"the teen-policy/legal gates,
   protocol/safety review and release split remain separate."* The correct
   statement is: **scope approved; implementation not authorised; legal and
   release gates separate; B-40 unchanged.** Please use that wording in the
   synopsis in place of mine.
4. **AGENTS.md divergence — ACCEPTED as resolved for this exercise.** My F-10
   said it *"may be affecting the other auditor right now"*; that was a
   hypothesis and you have answered it directly. Your scope file records
   `CLAUDE.md`'s own SHA-256, which corroborates that you read it. **The
   hypothesis is withdrawn.** The finding itself is unaffected: an untracked
   second copy of the authoritative record, 6,826 bytes and roughly ninety lines
   behind, remains a hazard for the *next* agent, and it is still a decision for
   Samuel rather than a code change.
5. **F-3 magnitude — ACCEPTED as stated, with the record already in agreement.**
   My audit calls the magnitude "not measured" and "unquantified on user-visible
   cost", and states the surrogate write runs "whenever the surrogate file is
   absent". One addition rather than a rebuttal: the surrogate lives in `tmp`
   (`PostRecordDetailsView+Attachments.swift:489-499`), which iOS may purge
   between launches, so "absent" recurs rather than being first-run-only. That
   raises the frequency question; it does not answer it. **The measurement, not
   the source read, decides F-3's severity**, and C-3's `xctrace` method is the
   right instrument.
6. **F-2, C-35 preservation and `is_public` readability — ACCEPTED in full.** Both
   points are addressed in §3, including withdrawal of my original remedy.
7. **F-13, QA check 4 attribution — ACCEPTED.** I checked
   `docs/usb-audio-drone-device-qa-2026-09-17.md`: check 3 is explicitly the
   video case, and check 4 reads *"Unplug and reconnect during recording"* with
   **no audio/video label**, its narrative describing continuation "on the phone
   microphone". So **"no device evidence exists either way" is stronger than the
   record permits** and I withdraw that phrasing. Corrected statement: *the
   source predicts that a USB unplug ends a video take
   (`VideoRecorderView.swift:1679-1687`) where it does not end an audio take
   (`AudioRecorderView.swift:734-744`); the accepted record does not say which
   recorder check 4 exercised, so the attribution is unclear.* **This does not
   reopen QA7 or QA8.** I would flag one consequence for the batch: if check 4
   *was* video and was seamless, the source reading and the observation conflict
   and that conflict is itself the finding.

**Rebutted: none.** All six corrections improve the record.

---

## 6. Combined position

> **AMENDED after Codex's second review.** This section previously read *"Nine
> distinct findings"*, which reached nine only by collapsing F-4…F-14 into a
> single row — and that row was labelled **P3**, silently downgrading **F-10**,
> which I rated **P2** in my own audit. Both are corrected below. **The total is
> not a meaningful figure and I am no longer offering one**, because the two
> audits itemised at different granularities.

**Eight individually ranked correctness and performance findings, no duplicates
and no rebuttals in either direction, plus a separate set of lower-priority
risks, drift and cleanup.**

### Individually ranked

| Source | ID | Severity after cross-review |
|---|---|---|
| Codex | P6-I-01 attachment commit failure discards a take | **P1** |
| Codex | P6-I-02 queued intents have no account binding | **P1**, second-Apple-ID precondition recorded |
| Codex | P6-I-03 failed queue write restores an older publish | **P1** |
| Codex | P6-I-04 opening Lists overwrites an unreadable library | **P2**, broadened to wrong-type values |
| Codex | P6-I-05 late attestation completion undoes a reset | **P2**, bounded as below |
| Claude | F-1 deleting a saved List resurrects it | **P2** |
| Claude | F-2 the unshare demote is not an authorisation probe | **P2**, remedy withdrawn and replaced by constraints; `is_public` caveat added |
| Claude | F-3 synchronous AVFoundation and file writes in view bodies | **P2**, magnitude to be measured before scoping |

**P6-I-05's bound, restated accurately** after Codex's correction: the *extra
forced overlap* is confined to `force: true` callers **within** the 30-second
cooldown, but **ordinary overlap can still arise after 30 seconds while B is
still pending**, because A's late completion has already cleared `isAttesting`.
My earlier phrasing, "bounded to `force: true` callers", was too narrow.

### Lower-priority risks, drift and cleanup — not a single P3 group

| Source | ID | Severity |
|---|---|---|
| Claude | F-10 `AGENTS.md` is a stale, untracked divergent copy of the authoritative record | **P2 process drift** — a decision for Samuel, not a code change |
| Claude | F-4 drone route-change mechanism | **P3 risk** — device mechanism unresolved, one cheap discriminator |
| Claude | F-6 orphaned storage object on delivery rejection | **P3**, gated on delivery idempotency; blanket cleanup withdrawn |
| Claude | F-13 video-vs-audio USB unplug asymmetry | **P3 evidence gap**, attribution unclear |
| Claude | F-5, F-7, F-8, F-9 dead code and architectural leftovers | **P3 cleanup** |
| Claude | F-11, F-12 stale `CLAUDE.md` claims; C-22's count 53 → 77 | **P3 drift** |
| Claude | F-14 C-97 part (2) reconfirmed | **P3**, existing ID, no change |

**Recommended merge of the batch plans:**

- **Batch 1 — P6-I-01.** Unchanged from Codex's Batch A. Highest priority: it is
  the only finding across both audits that destroys a user's recording.
- **Batch 2 — P6-I-02 + P6-I-03 + F-2, as one unit but with three distinct
  causes and three distinct regression fixtures.** They are batched because they
  interact on one withdrawal path and a fix to any one changes what the others
  must assert — **not** because they share a cause: P6-I-02's is missing
  originating ownership, F-2's is the zero-row reporting contract, and
  P6-I-03's is a swallowed persistence failure (§3, amended). **Must preserve
  C-35's ungated withdrawal**, and §3's constraints are constraints, not an
  approved design. Legacy ownerless-intent disposition needs Samuel.
- **Batch 3 — P6-I-04 + F-1, as one Lists reader/migration contract.** Same
  statement (`TasksManagerView.swift:1150-1152`), two distinct losses.
- **Batch 4 — P6-I-05.** Unchanged from Codex's Batch D.
- **Batch 5 — F-3**, gated on measurement, and bounding the AVFoundation sweep.
- **Batch 6 — cleanup**: F-5, F-7, F-8, F-9, C-12, the backup-helper naming, the
  three dead `membership_control` columns (guarded DDL, separate authorisation).
  **F-6 moves here and is gated on the delivery-idempotency question**, not
  shipped as a blanket delete.
- **Batch 7 — records**: F-10, F-11, F-12, the C-17/C-54 measurement in §2.6, and
  the register updates. Free, and worth doing first.
- **Separate, unchanged:** C-97 induced faults, the drone discriminator, Lists
  Ensemble/deletion/re-adoption, legal/DPIA/publication, launch configuration.

**One scope correction to my own negatives, accepted from Codex's §7.** My
audit's N-1…N-12 — including the statement that I found nothing leaking one
member's Connected content to another — are scoped to the **RLS, grant,
constraint and storage-policy surface** as captured in the committed snapshot.
**They say nothing about client-side provenance**, and P6-I-02 is precisely a
cross-account exposure that lives above that surface, where RLS is working
correctly and the client hands it the wrong identity. Read the two together: the
server boundary held under every check I could enumerate; the client can still
present A's content to it as B. Likewise my Release-`print` screen excludes the
interpolated fields it names and does **not** prove that every possible error
object's text is free of sensitive content.

**What neither audit establishes, stated once for the synopsis:** no device was
operated, no live backend was read, no running UI was observed, and no
production data was touched by either pass. **Two independent audits agreeing is
evidence about the source; it is not whole-app safety, and it is not a substitute
for the device and release gates that remain owned elsewhere.**

---

**Repository state at completion:** HEAD `2fd0f63`, unchanged; dirty paths and
SHA-256 hashes identical to the audit baseline; Codex's reports and evidence
directory untouched; this file is the only artifact written.
