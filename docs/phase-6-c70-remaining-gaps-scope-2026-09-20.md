# C-70 remaining gaps — consolidated scope, design and evidence plan (20 September 2026)

**Status: REVISION 4 — IMPLEMENTED LOCALLY AND GREEN, 20 September 2026.** Approved by Codex
within the §3 boundary; measurements M1–M5 resolved §2.6; code and tests written, built and run.

**COMMITTED 20 September 2026 on Samuel's explicit instruction, after Codex's independent local
implementation acceptance. NOT PUSHED BY CLAUDE, NOT DEVICE-VERIFIED, AND NOT CLOSED.** No
production, device, credential or purchase action was taken, and **the real lapsed-owner device
QA has NOT been performed** — the behaviour this unit restores has never been observed on
hardware. **Codex's acceptance was explicitly local only: no device or RLS end-to-end
acceptance, and no phase closure.** Phase 6 remains open.

**Superseded status lines, preserved rather than rewritten — but they are NOT all dated
history, and the difference matters.** Revisions 1–2 read "NOT APPROVED, NOT IMPLEMENTED",
which **was** true when written. Revision 3's added clause — "no code, test, device, production,
credential or purchase action has been taken" — **was NOT true when written and is corrected
here rather than excused.** It was carried forward from revision 2 at the moment the status
line was changed to record approval, by which point measurements M1–M5 had already been written
and run. **It was retained in error**, and a status line that contradicts the section
immediately below it is exactly the failure this project has recorded repeatedly: a durable
document asserting a fact is not evidence of that fact. §9 records what was actually done.

Prepared by Claude at `e5b3b08` on `feature/solo-connected`, consolidating several rounds of
Codex source review (`docs/c70-residuals-codex-review-2026-09-20.md`).

**This scope proposes no new product policy.** D-U6-3 is settled and is not re-asked. General
Connected mode, feed and access gates are untouched. Age, band and security protections are
untouched.

## 0. The two gaps

1. **A naturally lapsed member in Solo cannot sync maintenance of an existing Connected
   profile; the client returns before the directory write.** `account_directory_update_owner`
   is ungated and D-U6-3 always intended owner maintenance — the client never reaches it.
2. **Local display-name persistence happens only on `onDisappear`, and its Core Data failure is
   swallowed** (`ProfileView.swift:1395`, `do { try ctx.save() } catch { }`).

## 1. Gap 1 — three laundered entitlement dependencies, not one

### 1.1 The guards on the write path

`syncDirectoryFromCurrentState()` (`ProfileView.swift:1524`):

| # | Line | Guard | Lapsed-in-Solo |
|---|---|---|---|
| 1 | `:1528` | `appModeManager.canShowConnectedAccountManagement` | **FALSE — blocks** |
| 2 | `:1529` | `BackendEnvironment.shared.isConnected` | **FALSE — also blocks** |
| 3 | `:1530` | `auth.hasSupabaseAccessToken` | passive; see §1.4 |
| 4 | `:1532` | `auth.backendUserID` non-empty | mode-independent |

### 1.2 All three blockers are C-35's shape, in one call chain

- `canShowConnectedAccountManagement` is `mode == .connected` (`AppModeManager.swift:109`).
- `applyBackendRuntimeMode` (`:47`) maps `.solo` → `setBackendMode(.localSimulation)`, which
  writes `UserDefaults["backendMode_v1"]` (`BackendShim.swift:104`).
- `BackendEnvironment.isConnected` (`:2536`) reads that same key via `currentBackendMode()`
  (`:2543`). `AppMode` is resolved from `isEntitled`.
- **`ensureValidSession` (`AuthManager.swift:873`) is ALSO mode-gated** — `:882-884`:
  `guard BackendEnvironment.shared.isConnected else { return self.isSignedIn }`.

**So an entitlement dependency reaches this path three times without ever appearing by name.**
Guard 1 is visible; guard 2 is C-35's second defect; the refresh route is a third.

### 1.3 The fix precedent is already in this file

`performDeleteAccount()` (`:1880-1925`) carried the **same two guards** and C-35 replaced them:
`canShowConnectedAccountManagement` → **`auth.hasConnectedIdentity`**, and
`BackendEnvironment.shared.isConnected` → **`BackendConfig.isConfigured`**, with the reasoning
recorded in place. **This scope applies the established substitution rather than inventing
one.** It matches Phase 3's settled attestation invariant, which is deliberately never gated on
Connected mode being active.

### 1.4 THE 401 PATH — bounded fix, NOT deferred

**Codex has not accepted a deferral here, and the "global rewrite or nothing" framing in my
earlier draft was a FALSE CHOICE. Withdrawn.**

On a 401, `NetworkManager.onAuthChallenge` (`AuthManager.swift:351-353`) calls
`ensureValidSession(force: true)`. In Solo that returns `isSignedIn` **without rotating
anything**, so the retry re-presents the refused token — defeating the `force: true` whose own
comment (`:345-350`) exists to prevent exactly that. **A preflight alone does not fix this**,
so it does not close the gap as requested.

**Proposed, bounded and operation-specific:**

- **`boundRequest` gains an OPTIONAL auth-challenge closure that DEFAULTS to the existing
  global `onAuthChallenge` slot** (`NetworkManager.swift:79`, read at `:1084`). Every existing
  caller is unchanged by construction.
- **Directory maintenance alone passes a force-capable, mode-independent refresh.**
- **`ensureValidSession`'s global guard is NOT touched, and the EXISTING global
  `onAuthChallenge` callback is preserved EXACTLY as it is** — it already calls
  `ensureValidSession(reason: "network-auth-challenge", force: true)`
  (`AuthManager.swift:351-353`), and `force: true` there is load-bearing per its own comment.
  **CORRECTED ON CODEX'S REVIEW: my earlier wording said the global slot keeps a "non-force
  default", which was wrong — the global challenge IS forced.** The **non-force default**
  belongs to **`ensureValidBackendSession(reason:force:)`**, whose new `force` parameter must
  default to `false` so every existing caller is unchanged.
- **C-98's protection must not be weakened**: a refresh completing after sign-out or identity
  withdrawal must still not repopulate tokens or the backend user id.
- **Owner and generation are captured BEFORE the preflight/refresh await** and re-checked
  after, so a transition across it invalidates rather than proceeds.
- **Factory reset**: a reset must invalidate any in-flight preflight and any draft, with **no
  resurrection** afterwards.
- **The owner/generation guards that already wrap the refresh at `:1080` and `:1091` are
  preserved**, so an A→B→A transition across a refresh still fails on generation.

### 1.5 Create-versus-update policy

- **Existing row → owner-filtered PATCH**, reaching the ungated `account_directory_update_owner`.
  No server change.
- **Creation stays gated.** `enforcement_gate` refuses; **the server, not the client, decides
  whether a missing row may be created.** Fail-closed, not weakened for a test.
- **Automatic handle generation stays Connected-only** — `autoGenerateAccountIDIfMissing`'s
  `BackendEnvironment` guard (`AccountDirectoryService.swift:776`) is **deliberately
  unchanged**.
- **Manually filling an existing row's empty handle is owner maintenance and is NOT
  generation.** The two are not conflated.

### 1.6 Established, not assumed

`NetworkManager` contains **no** `BackendEnvironment`/`currentBackendMode`/`localSimulation`
reference. `BackendConfig.apply()` (`BackendConfig.swift:94`) does **not** branch on mode.
`upsertSelfRow` carries **no** mode guard, and the service's own rule is *"PATCH, then create,
then at most one bounded probe. Local effects are applied on `.applied` ALONE."*
`ensureValidBackendSession` (`AuthManager.swift:1215`) guards on factory-reset, `currentUserID`,
`isSigningIn` and `BackendConfig.isConfigured` — **no mode check**.

## 2. Gap 2 — local-first persistence

### 2.1 The path and the inversion

`save()` (`:1387`) assigns `p.name`, `p.primaryInstrument`, `p.defaultPrivacy`, then
`do { try ctx.save() } catch { }` at **`:1395`**. Its only lifecycle caller is
`.onDisappear(perform: persistProfileEdits)` (`:2028`); the other caller is the sign-out
transition (`:2092`). **`ProfileView` has zero `scenePhase` references.**

| | Trigger | Frequency |
|---|---|---|
| **Remote** write | `onChange(of: name)` `:2114` → 650 ms debounce `:1474` | **every settled edit** |
| **Local** write | `.onDisappear` only | **once, at dismissal** |

**The server copy is kept fresher than the device copy** — the inverse of invariant 1.

### 2.2 Blur does not fix it; the commit point must be structural

A member can **pause while still focused**: the debounce fires, the remote write goes out, and
no blur has occurred. **Proposed instead:**

- **The local commit guards `syncDirectoryFromCurrentState()` ITSELF**, not the debounced
  wrapper — because **`:633` (Account ID blur) and `:639` (onSubmit) call it directly and
  bypass the debounce entirely.** One common path, no bypass.
- **AND IT RUNS BEFORE THE NO-IDENTITY REMOTE GUARDS** (`:1528-1532`), not after. **Added on
  Codex's review:** otherwise a Solo member with no Connected identity returns at a guard and
  gets **no debounce-driven local persistence at all** — the very members for whom the local
  record is the only record. Local persistence must not be reachable only through a remote
  code path's preconditions.
- **A failed local commit BLOCKS the remote submission.** The device never publishes a value it
  could not record.
- **Blur, `scenePhase` leaving `.active`, and `.onDisappear` are retained** as additional
  commit points for edits that never reach a submission.
- **No timer and no general autosave is introduced.**

### 2.3 Identity transitions — cancel the pre-submit debounce

`DirectoryWriteCoordinator` owns work **after** submission. A debounced task scheduled under
identity A that fires after a switch to B is **pre-submit** and therefore unowned.
**`directorySyncDebounceTask` must be cancelled/invalidated on an identity transition**
(`:2075`, `:2099`), so no edit composed under A is submitted under B.

### 2.4 Draft scope — the local name is DEVICE-LOCAL

**My earlier proposal to discard an unsaved name on identity transition is WITHDRAWN.** It
would have created a new policy contradicting a deliberate existing one.

| Value | Scope | Evidence |
|---|---|---|
| **`name`** (Core Data `Profile`) | **DEVICE-LOCAL** | `load()` `:1357` fetches `fetchLimit 1`, **no owner predicate** |
| `locationText` | per-owner | `ProfileStore.setLocation(_, for:)`; re-hydrated `:2099-2109` |
| `accountIDText` | per-owner | `ProfileStore.accountID(for:)`; re-hydrated `:2099-2109` |

Sign-out **already preserves the local name deliberately** (`:2087-2093`, *"Preserve the
currently presented profile as the local Études profile after sign-out."*).

**Rule: an unsaved local NAME draft is never discarded on an identity transition.** What is
invalidated is (i) **remote submission** — tokens, plus §2.3's debounce cancellation — and
(ii) the **per-owner** `accountIDText`/`locationText` drafts, whose existing behaviour is
unchanged. The two concerns stay structurally separate.

### 2.5 Hydration — the guard belongs in `load()`

`load()` (`:1357`) is the real hydration function. **Two call sites reach it directly, skipping
`onAppearLoad()`:**

| # | Site | Route |
|---|---|---|
| 1 | `onAppearLoad()` `:1085` → `load()` `:1088` | `.onAppear` `:2027`; re-entered `:2093/2094/2096` |
| 2 | **`NSManagedObjectContextDidSave` `:2117` → `load()` `:2124`** | **any save on `ctx`**, no sheet up |
| 3 | **instrument manager close `:2168` → `load()`** | sheet dismissal |

**So the dirty-draft guard lives inside `load()`**, covering all three by construction. The
flag clears on **evidenced success only**, never optimistically, so the in-flight window
assigns nothing.

**Established hazard:** an **unrelated** save on `ctx` runs `load()` and can replace a live
draft.

**NOT established, and I previously asserted it — withdrawn:** that a **failed** `ctx.save()`
posts `NSManagedObjectContextDidSave`. Core Data documents that notification for successful
saves. **This will be measured with a controlled failing-context test before any claim is made
about it** (§6, M1).

### 2.6 Failure semantics — MEASURED 20 September 2026, §2.6 RESOLVED

**Raw evidence:** `…/pl/outputs/c70-measurements-raw.txt`, bundle
`c70-measure-20260920-3.xcresult`, `XCODEBUILD_EXIT=0`, `** TEST SUCCEEDED **`. Harness:
`MOTIVOTests/C70LocalSaveFailureMeasurementTests.swift`, isolated disposable on-disk stores
under a unique temp directory, modelling `save()`'s real shape — **mutate the managed object,
then attempt `ctx.save()`** — in two failure modes.

| # | Question | Result |
|---|---|---|
| **M1** | does a FAILED `ctx.save()` post `NSManagedObjectContextDidSave`? | **NO — 0 notifications**, in BOTH failure modes (read-only store `NSCocoaErrorDomain 513`; validation `1570`) |
| **M2** | same-context re-fetch after failure | **`EDITED`** — the pending edit is returned; `hasChanges == true` |
| **M3** | fresh context, same coordinator | **`STORED`** — committed data only |
| **M4** | **PROXY ONLY — store teardown + reopen from disk. NOT a process kill** | **`STORED`** — the pending change is not on disk |
| **M5** | does a LATER successful save commit the edit left pending by the failure? | **YES — committed value `EDITED`, and the name was NOT re-applied before that save** |

#### Two claims of mine die here, and one hazard I invented never existed

- **WITHDRAWN: "a failed save's own `DidSave` restores the stale value over the failed draft."**
  **M1 = 0.** That hazard **does not exist**, and the test written for it is removed.
- **WITHDRAWN: "dismissal loses the edit" and "reopen shows the last successfully persisted
  value."** **M2** shows the edit survives in the shared view context and a `load()`-shaped
  fetch returns it.

#### The hazard that DOES survive is narrower, and it is not the one I described

**The draft lives in `@State name` and only reaches the managed object INSIDE `save()`.** So
the real clobber window is **between a keystroke and the first `save()`**, while the managed
object still holds the old value: an **unrelated successful** save elsewhere posts `DidSave` →
`load()` → `name` is reset from the stored value.

**CORRECTED ON CODEX'S REVIEW — my "harmless after save" wording was an overclaim.** It holds
**only while no NEWER UI edit exists.** `load()` returning `EDITED` is harmless only when the
managed object already carries the newest text. **Every subsequent keystroke REOPENS the
window**, because the new text again lives only in `@State` until the next `save()`.

**So the dirty protection covers the NEWEST draft until it is evidenced saved — not merely "the
first save ever".** The window is not opened once and closed once; it is opened by each edit
and closed by each evidenced commit. **This is also the window the local-first commit point
shortens** — a second reason for §2.2 that the measurements produced.

#### Final narrow failure-handling plan

1. **Report the failure; never swallow it.**
2. **Do NOT roll back or reset the shared view context** — Codex's direction, and now also
   evidenced: a rollback would discard the very edit **M5** shows is recoverable, as well as
   unrelated pending edits belonging to other screens.
3. **Leave the failed edit pending and do not block later local commits.** **M5** establishes
   that the next successful `ctx.save()` — this screen's retry, or any other save on the shared
   context — **commits it without it being re-applied.**
4. **The dirty flag guards `load()` for the pre-`save()` window only**, and clears on evidenced
   success.
5. **The remote submission stays blocked on a failed local commit** (§2.2). **CORRECTED ON
   CODEX'S REVIEW: my "the local edit is not at risk" was too broad and is withdrawn.** A
   pending edit is **still vulnerable to process loss** (M4 proxy), so blocking is **not merely
   a consistency preference — the local-first gate stays important**: it prevents the device
   publishing a value that exists nowhere but volatile memory.
6. **Failure feedback is its own surface.** On a local-save failure the member gets **clear,
   separate retry feedback**, distinct from `directorySyncMessage` (which concerns the remote
   write), and **the pending state is preserved**. **It must never be presented as durably
   saved.**
7. **Factory reset is an EXPLICIT exception to draft retention.** A reset invalidates any
   in-flight preflight and any draft, with **no resurrection afterwards.**

#### What may now be claimed, and what may not

- **MAY, CONDITIONALLY — corrected on Codex's review.** **M2 is a same-context re-fetch, not a
  SwiftUI dismiss/reopen QA.** What is measured is that a re-fetch **on a context that is
  retained and not reset** returns the pending edit. The dismissal/reopen implication therefore
  holds **only while the shared `viewContext` is retained and nothing resets it** — it is an
  inference from a context-level measurement, **not an observed UI flow**, and no device or UI
  verification was run.
- **MAY:** a failed save cannot cause a self-clobber (M1).
- **MAY NOT:** that the edit survives **process termination**. **M4's proxy shows it is not on
  disk**, and the proxy is an in-process teardown, **not a process kill** — so even this is a
  proxy result and is labelled as one everywhere it appears.
- **MAY NOT:** any durability guarantee. **This unit still adds no durable local draft store.**

#### One latent constraint worth pinning

**M3** shows a fresh context sees only committed data. `ProfileView` hydrates from the shared
`viewContext`, so this is not a live hazard — but **if hydration were ever moved to another
context the draft would silently vanish.** Worth a standing assertion.

### 2.7 Visibility — SETTLED by Samuel's delegated decision

Both surfaces are behind the mode guard today: the directory-sync message (`:651`) and the
whole Account ID field (`:605`, with its sync triggers at `:617/626/633/639`). **Fixing the
write without visibility would ship a silent path.**

**Decided (delegated bounded choice, recorded by Codex):**

- **Use `auth.hasConnectedIdentity`** (with `BackendConfig.isConfigured` as appropriate) **for
  the profile-maintenance message and the Account ID editor only.**
- **General Connected account management, feed and access gates are untouched.**
- **The editor is NOT gated on the handle text being non-empty** — it could disappear mid-edit.
- **Manually filling an existing row's empty handle is owner maintenance**, distinct from
  automatic generation, which **stays Connected-only**. The server still decides whether a
  missing row may be created.

**This is settled owner-maintenance policy exposed consistently — not a new membership rule.**

## 3. Exact file boundary

| File | Expected change |
|---|---|
| `MOTIVO/ProfileView.swift` | guards `:1528-1530`; local-commit gate inside `syncDirectoryFromCurrentState`; `save()` returns an outcome; commit points (blur, `scenePhase`, retained `onDisappear`); dirty-draft guard in `load()`; debounce cancellation on identity transition; visibility predicate at `:605`/`:651`; local-save message state |
| `MOTIVO/NetworkManager.swift` | optional per-operation auth-challenge closure on `boundRequest`, **defaulting to the existing global slot** |
| `MOTIVO/AccountDirectoryService.swift` | an **optional** challenge parameter threaded to `boundRequest`, **supplied only by the ProfileView maintenance path**. Generation, setup and hydration callers pass nothing and are unchanged. **`:776` generation guard UNCHANGED** |
| `MOTIVO/AuthManager.swift` | `ensureValidBackendSession(reason:force:)` gains a **`force` parameter defaulting to `false`**, so every existing caller is unchanged. **`ensureValidSession`'s global guard `:882` UNCHANGED, and the global `onAuthChallenge` callback at `:351-353` preserved EXACTLY (it is already `force: true`). C-98 protections preserved** |
| `MOTIVOTests/` | new behavioural tests (§6) |

**No other file. No SQL, migration, policy, grant, predicate or trigger. No project-file
change.**

## 4. Visible behaviour changes

1. A lapsed member in Solo **holding an existing directory row** has name / location /
   instrument / handle edits reach the server again.
2. A lapsed owner **sees** the sync outcome, and can edit the Account ID field.
3. A lapsed member with **no** row gains nothing — creation still refused by the server.
4. Local name and location persist at blur, at backgrounding, **and before any remote
   submission**.
5. A failed local save becomes **visible**, and **blocks** the remote publish.
6. **Solo without a Connected identity is entirely unchanged** — no backend work at all.

## 5. What is preserved

Gated creation · server-decided row creation · Connected-only automatic generation · identity
and owner binding via `OperationBinding`/`boundRequest` · serialised writes · the lock-protected
freshness token validated inside the cache actor · `mayApplyEffects(owner:capturedGeneration:seq:)`
· `DirectorySyncLatch` submit/confirm/invalidate, including revert-in-flight re-publication ·
receipt evidence (`return=representation`, one row, every selected column present, compared
against what was sent; mismatch → `notEvidenced`, never reported saved/cached/latched) · C-98's
post-withdrawal refresh protections · Solo-without-identity account-free · the active-Sandbox
`connected_member()` predicate · B-40 and band protections · D-U6-3.

**Out of scope:** C-34/avatar, recorder, broader sharing or age work, general Connected mode,
feed/access, C-70(a)'s error-placement residual, and any production, device, credential or
purchase action.

## 6. Evidence plan

**Behaviour and state-transition tests are the proof. Source-text assertions are retained only
as two anti-regression pins and are explicitly NOT the main evidence.**

**Measurements (§2.6) — DONE, and they changed the design.** M1 `DidSave` on failed save: **0**,
so a hazard I had written a test for did not exist and the test was removed. M2 same-context
re-fetch: **`EDITED`**. M3 fresh context: **`STORED`**. M4 proxy: **`STORED`** — *not* a process
kill. M5 recovery: a later successful save **commits the pending edit without re-application**.

**Policy behaviour:** identity+config+Solo+existing row → submits · no identity → **no remote
work, but the local commit still runs** · no row → still fails closed · **401 under a lapsed owner → the forced,
mode-independent refresh runs and the retry succeeds** · **403 does NOT trigger a refresh** ·
owner/generation change across a refresh → `identityChanged`, not a retry · one settled edit →
at most one preflight · **existing callers of `boundRequest` keep the EXISTING global
`onAuthChallenge`, which is and stays `force: true`** ·
latch/generation/receipt semantics unchanged.

**Preserved-caller behaviour:** every existing `boundRequest` caller still uses the global
forced challenge · every existing `ensureValidBackendSession` caller still gets `force: false`
· generation/setup/hydration directory callers pass no closure · a factory reset invalidates
in-flight preflights and drafts with no resurrection.

**Draft transitions — REVISED BY THE MEASUREMENTS.** Local commit precedes and **gates** remote
submission, including via the **direct** `:633`/`:639` callers · local commit runs even with no
identity · failed `ctx.save()` is reported · **an unrelated successful `DidSave` does not
replace a draft in the PRE-`save()` window** (the surviving hazard) · instrument-close `load()`
likewise · **a later successful save commits an edit left pending by a failure** (M5) · the
context is **never** rolled back · flag clears on evidenced success only · **identity transition
does NOT discard the local name draft** while per-owner drafts re-hydrate as today · a debounced
task composed under A is **cancelled** and never submitted under B · hydration reads the shared
`viewContext` (pins M3).

**REMOVED: the test for "a failed save's own `DidSave` restores the stale value".** **M1
disproved the premise**, so the test would have asserted a condition no correct implementation
can reach.

**Visibility:** lapsed owner sees the message and the Account ID editor · the editor is not
gated on non-empty text · general management/feed/access unchanged · automatic generation still
Connected-only.

**Positive controls — stated honestly.** Controls are **bounded and explicitly predicted
behavioural** ones, and **I do not promise that a test depending on a new API compiles against
pre-change code**. For each control I will state the predicted failure in advance, record the
**precise** failure observed and the exact restore, and make **no blind or broad edits**. Where
a control cannot be run for that reason, it is recorded as **not run**, not quietly dropped.

**Builds:** Debug and Release, sequential, one `xcodebuild` at a time.
**Suite:** full `MOTIVOTests`, unique explicit `resultBundlePath` outside DerivedData.

## 7. Limits stated in advance

- **No device verification is proposed or will be claimed.** The lapsed-Solo path's real
  confirmation needs a lapsed identity with an existing row on hardware — a separate named
  obligation this unit does not close.
- **A passing suite will not prove the server accepted the PATCH.** The server side is already
  independently evidenced (expired membership → upsert **403/42501**; ordinary **PATCH → 204**),
  but **no request-level evidence was ever captured from a device**, and that is unchanged.
- **`membership_state()` reports `'sandbox_only'` regardless of entitlement** — scope 011
  widened `connected_member()` and not it. **It is not an entitlement test** and is not used as
  one here; that exact misreading already produced one confident wrong conclusion.
- **No durable local draft store** is added.
- **No fetch, production read/write, credential or purchase.**

## 8. The open items at approval time — ALL RESOLVED

Preserved as written, with outcomes. **§1.4's bounded challenge-closure shape** — implemented
as an optional `boundRequest` parameter defaulting to the global slot, with the global callback
unchanged and still `force: true`; the non-force default belongs to
`ensureValidBackendSession(reason:force:)`. **§2.2's gate siting** — moved onto
`syncDirectoryFromCurrentState` itself, and made SYNCHRONOUS so it adds no `await` before the
owner/snapshot capture. **§2.6's measurements** — run; they changed the failure-handling design,
removing a hazard that did not exist and narrowing two claims.

## 9. OUTCOME — what was done and what it establishes

### 9.1 Files changed (the whole change)

| File | Change |
|---|---|
| `MOTIVO/ProfileView.swift` | guards, local-first synchronous gate, `save()` reports failure, commit points, dirty-draft guard in `load()`, reset invalidation, debounce/submit capture, visibility, Retry |
| `MOTIVO/AuthManager.swift` | `ensureValidBackendSession(reason:force:)`, `force` defaulting to `false` |
| `MOTIVO/NetworkManager.swift` | optional per-operation `authChallenge` on `boundRequest`, defaulting to the global slot |
| `MOTIVO/AccountDirectoryService.swift` | optional challenge threaded to the maintenance write only |
| `MOTIVOTests/` | 3 new files; 2 existing extended |

Exact bytes: `…/pl/outputs/c70-impl-source-manifest.txt`. **No SQL, migration, policy, grant,
predicate, trigger or project-file change.**

### 9.2 Validation

- **Debug and Release both BUILD SUCCEEDED against the FINAL bytes** (`c70-impl-release-final.log`;
  hashes re-verified identical to the manifest after the build).
- **Full `MOTIVOTests`: Passed — 972 passed, 0 failed, 6 skipped, 978 total**
  (`c70-impl-fullsuite-1.xcresult`). The 6 skips are exactly the standing opt-in set; the two
  local-stack tests that were SKIPPED during the earlier clean-up run **passed here**, so this
  run's coverage is wider than that one's.

### 9.3 What the evidence does and does NOT establish

**Establishes:** the extracted mechanisms decide correctly, with counted effects — a failed
local commit permits no remote work, no identity still commits locally, an A→B→A transition is
stale, an invalidated view performs zero local writes; the real 401 routes against the
transport — a scoped handler is the one consulted, the global one is used when none is
supplied, a 403 refreshes nothing, an identity change during the refresh abandons the write;
and the real forced refresh — `force: true` rotates an unexpired token in Solo, the non-forced
default rotates nothing, and `ensureValidSession` in Solo rotates nothing even when forced,
which is the premise of gap 1.

**Does NOT establish — stated rather than implied:**
- **The counted helper tests do not mount `ProfileView` and do not execute its storage
  modifiers.** They show the mechanisms decide correctly, **not** that every call site consults
  them. That half rests on the two structural pins and on independent wiring review.
- **No device verification of any kind**, and **no real lapsed-owner QA**. The restored
  behaviour has not been seen on hardware.
- **NO DESIGNED MUTATION OR POSITIVE CONTROLS WERE RUN.** The scope said each control would
  state its predicted failure in advance and record the precise failure and restore; that was
  not done for any assertion. The only **executed test-assertion** failure was **unplanned**:
  the wiring pin failed because MY extractor preferred a five-space `private func` match at
  offset 9799 over a nearer four-space one at 6694, over-running into the generation path that
  legitimately keeps its `BackendEnvironment` guard. It is evidence the pin can fail and that
  the extraction was wrong; it is **not** a control for production behaviour and is not
  presented as one.

  **Compilation failures also occurred during implementation and are not counted above** —
  `authChallenge` out of scope in `performProfileWrite`, duplicated `@MainActor` from an
  insertion that split an attribute from its function, and the helper types unreachable from
  the tests because they had been nested inside `struct ProfileView` rather than placed at file
  scope. They are recorded in Codex's review. **A compiler failure proves a lexical dependency,
  never a behavioural one**, so none of them substitutes for the controls that were not run.
- **A passing suite does not prove the server accepted anything.** No request-level device
  evidence exists, and this unit does not change that.
- **`membership_state()` still reports `'sandbox_only'` regardless of entitlement** and is not
  an entitlement test.

### 9.4 Known cosmetic residue, not fixed

In `NetworkManager.swift` the new `- Parameter` doc comment sits **after** the existing
`@MainActor` attribute rather than before it. Legal Swift, zero behavioural effect; left alone
rather than invalidate the manifest and re-run the suite for comment placement.
