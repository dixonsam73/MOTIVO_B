# Phase 6 — bounded clean-up scope and reachability evidence (20 September 2026)

**Status: SUPERSEDED AS A PROPOSAL — IMPLEMENTED 20 September 2026.** Prepared by Claude at
`dec0236` as a scope proposal; **Codex reviewed it and APPROVED the exact Tier B table plus
C-12's three sites, with Tier C and the shared naming helpers retained.** The removal was then
implemented exactly as approved and nothing was widened. The tables below are retained **as
written** as the reachability record the approval was given against; §8 records what was
actually done and what was measured. **Nothing is committed or pushed** — that needs Samuel's
specific instruction.

**Codex applied four wording corrections to this record before implementation** (§0 items 1–2,
§2.1, §2.1.1, §1.1 and §2.5). They were proof-wording corrections, not source blockers.

- **Base:** `dec0236a30a7de6af9d59a6c3a1962994fff1f36`, branch `feature/solo-connected`.
- **Protected files verified unchanged** (all three hashes match the handover):
  `docs/connected-invitations-direction.md` `90f60494…`,
  `docs/private-connection-invitations-scope-2026-09-17.md` `c470d4a1…`,
  `AGENTS.md` `f9483878…`.
- **Pre-change source hashes:**
  - `MOTIVO/TasksManagerView.swift` — `59f298fb0153f4e0b3e014b7556ec87ea9bfcfa486a15a7aa86ed665962cd3d8`
  - `MOTIVO/SessionDetailView.swift` — `c22cf906ab05ceb14de553faf1866929dcb3a3d0ea013c446e8d643caa0cc2d5`

## 0. Two corrections to my own earlier statements in this session

Recorded because the record should show what was wrong, not only what is now right.

1. **I first said `TasksManagerView` has "exactly three presentation modifiers". That was
   wrong.** There are **four**: `:834` `navigationDestination`, `:837` and `:841` in `body`,
   plus the **live** `:647` `.sheet(item: $listShareRequest)` nested inside
   `taskSetEditorView`. My first sweep omitted `navigationDestination` from its pattern.
   Codex caught this independently. The conclusion is unchanged and is now established on a
   stronger measurement — see §2.1.
2. **`occ=1` (declared, never named again) is not a deadness proof.** `dropEntered`,
   `performDrop`, `dropUpdated`, `makeCoordinator`, `makeUIViewController`,
   `updateUIViewController` and `documentCameraViewControllerDidCancel` are all `occ=1` and
   all **protocol witnesses** — callback entry points reached by conformance rather than by
   name, so a reference count says nothing about them either way. **Corrected on Codex's
   review: that does not make them live here.** A witness is reachable only once an instance
   is constructed and registered, and in this file the only construction sites
   (`ImportedTaskDraftLineDropDelegate` at `:931`, `TasksManagerImportScanSheet` never) are
   themselves unreachable. They are cited as the reason a reference count cannot decide the
   question, **not** as examples of live code. Every conclusion below rests on a reachability
   argument, never on a reference count.

## 1. Method, and what it can and cannot establish

Roots are `body`, `init`, and any member named from outside its own type. Edges are
whole-word occurrences of a member's name inside another member's source range. The
reachable set is the transitive closure from the roots; everything else is unreachable.

**What this establishes:** that no *lexical* path leads from a root to the candidate.
**What it does not establish on its own:** that no *runtime* mechanism reaches it. Those are
enumerated per candidate in §2.1 and §3.1 and excluded by declaration and context, not by
absence of search hits.

### 1.1 The C-35 test, applied rather than cited

C-35's second defect was an entitlement dependency carried through a **`UserDefaults` key**,
so the deletion path contained none of `isEntitled`, `AppMode` or
`canShowConnectedAccountManagement` **by name** and passed an identifier audit. Only running
it found the defect. The general shape is a **semantic dependency travelling through shared
mutable state**, invisible to any symbol search.

Applied here, the analogous risk would be a candidate whose *effects* are observed elsewhere
even though its *name* is unreachable. Two things exclude it for this scope:

- Every candidate's state is `@State` or `@FocusState` (`focusedImportLineID` `:79` is
  `@FocusState`, not `@State` — corrected on Codex's review), and both are **per-view-instance
  memory, not persisted state.** Neither can be written by `UserDefaults`, a queued payload or
  a restoration path, because nothing outside the view instance can address it.
- The candidates' side effects (writing the saved-lists store, reading the clipboard,
  deleting a Core Data `Session`) occur **only inside bodies that never execute.** Code that
  never runs writes no shared state, so removing it cannot change what any other reader sees.

The residual C-35-shaped risk is therefore **initialisation side effects**, not call-time
ones. All candidate `@State` and `@FocusState` declarations use plain literal
initialisers (`false`, `""`, `[]`, `nil`, or `@FocusState`'s implicit `nil`) with no
registration, no key derivation and no observer attachment. The two
`UserDefaults` key strings in this file (`autofillCompatibilityKey` `:146`,
`defaultTaskSetIDKey` `:148`) are **out of scope and retained** — see Tier C.

## 2. Candidate group 1 — Lists import / save scaffolding (`MOTIVO/TasksManagerView.swift`)

### 2.1 The decisive measurement

`TasksManagerView` declares five import/save state variables. **Not one of them is ever
`$`-projected anywhere in the file**, and the file contains no `extension TasksManagerView`
and no other file does either (they are `private`, so no other file could reach them in any
case):

| State var | Line | Written `true` | Ever bound to a presentation |
|---|---|---|---|
| `showTaskImportLauncher` | `:68` | never | **never `$`-projected** |
| `showTaskImportPasteSheet` | `:69` | never (only `= false` at `:882`, `:1237`) | **never `$`-projected** |
| `showTaskImportScanSheet` | `:70` | never | **never `$`-projected** |
| `showSaveCurrentTaskSetPrompt` | `:71` | `:1207`, inside caller-less `saveCurrentItemsAsTaskSet` | **never `$`-projected** |
| `showDefaultTaskSetSheet` | `:72` | never (only `= false` at `:982`, `:1010`, `:1023`) | **never `$`-projected** |

**Corrected on Codex's review: absent `$` projection is NOT on its own sufficient**, because
a `Binding(get:set:)` can be constructed by hand over a bare name without `$` ever appearing.
The file does contain four such manual constructions (`:272`, `:360`, `:377`, `:553`) — and
**none of them names a candidate var.** The argument that actually carries is the
**no-writer / no-consumer graph**: the occurrences of these five names are enumerated
exhaustively above and in §2.1.1, and **every single one is either the declaration itself or a
direct `= true` / `= false` assignment.** There is no third kind of occurrence, so there is no
site at which a binding, closure capture, stored property or escape could be formed. The
four
presentation modifiers that do exist (`:647`, `:834`, `:837`, `:841`) bind
`listShareRequest`, `showTaskSetEditor`, `showManagerInstrumentPickerSheet` and
`showManagerActivityPickerSheet` — all retained, all live.

#### 2.1.1 The complete occurrence list (the actual evidence)

Every occurrence in the repository of each of the five names, with its kind:

| Line | Occurrence | Kind |
|---|---|---|
| `:68` `:69` `:70` `:71` `:72` | the five declarations | declaration, literal `false` |
| `:882` `:1237` | `showTaskImportPasteSheet = false` | direct assignment |
| `:982` `:1010` `:1023` | `showDefaultTaskSetSheet = false` | direct assignment |
| `:1207` | `showSaveCurrentTaskSetPrompt = true` | direct assignment, inside caller-less `saveCurrentItemsAsTaskSet` |
| `:1218` | `showSaveCurrentTaskSetPrompt = false` | direct assignment |

**Twelve occurrences, all accounted for; none is a binding, a capture or a read.** The single
`= true` sits inside a function with no caller. `showTaskImportLauncher` and
`showTaskImportScanSheet` are never mentioned again after declaration at all.

Runtime mechanisms considered and excluded for these members: they are `private` members of a
SwiftUI `View` **struct**, so there is no `@objc` exposure, no selector, no KVC/KVO and no
`NSObject` dynamism; no string-keyed lookup of a Swift type exists; and `#if` blocks in this
file are only `canImport(UIKit)` / `canImport(VisionKit)`, both true for the iOS target, so
no conditional configuration reveals a different wiring.

### 2.2 Tier B — proposed removal: the four named candidates and their strict orphan closure

Every member below is unreachable **and** is reached by nothing outside this closure.

| Lines | Kind | Member | Why it is in scope |
|---|---|---|---|
| `15-42` | struct | `ImportedTaskDraftLineDropDelegate` | **sole** use is `:931`, inside `importDraftEditorCard` |
| `69` | state | `showTaskImportPasteSheet` | named candidate's state |
| `71` | state | `showSaveCurrentTaskSetPrompt` | **named candidate** |
| `73-79` | state ×7 | `pastedImportText`, `importDraftItems`, `importDraftTaskSetName`, `importDraftLines`, `draggedImportLineID`, `suppressImportedRawTextObserver`, `focusedImportLineID` | used only by members in this closure |
| `109-112` | struct | `EditableImportedTaskLine` | used only by `:17` (delegate above) and closure members |
| `862-898` | view | `taskImportPasteSheet` | **named candidate** |
| `899-918` | view | `importPasteHeader` | orphaned by `taskImportPasteSheet` |
| `919-923` | view | `importPasteButtonBackground` | orphaned |
| `924-959` | view | `importDraftEditorCard` | orphaned |
| `960-972` | view | `importTaskSetNameSection` | orphaned |
| `1050-1062` | func | `pasteImportedTasksFromClipboard` | orphaned |
| `1205-1209` | func | `saveCurrentItemsAsTaskSet` | **named candidate** |
| `1210-1220` | func | `commitSaveCurrentItemsAsTaskSet` | **named candidate** |
| `1221-1240` | func | `saveImportedTaskSetFromDraft` | orphaned |
| `1241-1282` | func | `importedTaskDraftRow` | orphaned |
| `1283-1320` | func | `handleImportedRawTextChanged` | orphaned |
| `1321-1327` | func | `syncImportDraftItemsFromLines` | orphaned |
| `1328-1332` | func | `dismissImportedTaskKeyboard` | orphaned |
| `1389-1401` | func | `parseImportedTaskLines` | orphaned |
| `1405-1500` | struct | `TasksManagerImportLauncherSheet` | **named candidate**; self-contained, zero references |

**≈ 404 lines, 25 declarations, one file.**

### 2.3 RETAINED although unreachable — the boundary Codex identified

**These three are dead but must NOT be removed under this scope**, because the independently
dead `duplicateTaskSet` (`:444-455`, Tier C, retained) calls `uniqueTaskSetName` at `:448`,
and `uniqueTaskSetName` calls the other two at `:1362`. Removing them while retaining
`duplicateTaskSet` **would not compile**:

| Lines | Member | Lexically required by |
|---|---|---|
| `171-174` | `textItems` | `uniqueTaskSetName:1362`, and Tier-C `duplicateTaskSet` transitively |
| `1360-1378` | `uniqueTaskSetName` | **`duplicateTaskSet:448`** (Tier C, retained) |
| `1379-1388` | `defaultImportedTaskSetName` | `uniqueTaskSetName:1362` |

This is the explicit price of keeping the unit bounded, and it is the right price: it keeps
the removal to one coherent subsystem instead of cascading into unrelated dead UI.

### 2.4 Tier C — independently dead, OUTSIDE this scope, flagged not removed

Found during the trace, **not authorised by the handover, and not proposed here.** Reported
because a later reader should not have to rediscover it, and because Tier B deliberately
leaves it standing.

- **Import siblings:** `showTaskImportLauncher` `:68`, `showTaskImportScanSheet` `:70`, and
  `TasksManagerImportScanSheet` (`:1503-1574` VisionKit branch, `:1576-1599` fallback).
- **Default-list subsystem:** `showDefaultTaskSetSheet` `:72`, `defaultTaskSetSheet`
  `:973-1018`, `defaultTaskSetRow` `:1019-1049`, `defaultTaskSetIDKey` `:148`.
- **In-place manager-row editing island:** `newItemText` `:59`, `focusedManagerLineID` `:80`,
  `ignoreNextManagerTapLineID` `:81`, `canSaveCurrentAsTaskSet` `:263`,
  `showsSingleTopSelector` `:267`, `managerLineTextBinding` `:271`, `toggleManagerLineType`
  `:284`, `managerTaskRow` `:299`, `managerTaskTextArea` `:322`, `addItem` `:1063`,
  `deleteManagerLine` `:1071`, `saveItems` `:1106`, `dismissManagerKeyboard` `:1333`,
  `moveManagerLines` `:1341`.
- **Other:** `LegacySavedTaskSet` `:107`, `autofillCompatibilityKey` `:146`,
  `duplicateTaskSet` `:444`, `commitTaskSetNameIfNeeded` `:1194`.

**`saveItems` `:1106` deserves a product decision rather than a deletion.** It is the file's
persistence entry point and is called only from other dead members (`:279`, `:287`, `:1068`,
`:1073`, `:1344`). That the live screen persists through a different route is an
**observation about this file**, not a verified account of the Lists feature, and I am not
making one.

### 2.5 Live neighbours explicitly preserved — the naming-similarity trap

**`taskImportPasteSheet` has TWO declarations and one use — three occurrences, not three
declarations (corrected on Codex's review) — and only the `TasksManagerView` declaration is
dead.** The table below also lists two separate `PracticeTimerView` state vars, which are
different symbols again and are counted separately.

| Symbol | Where | Disposition |
|---|---|---|
| `taskImportPasteSheet` | `TasksManagerView.swift:862`, `private` | **REMOVE** (Tier B) |
| `taskImportPasteSheet` | `PracticeTimerView+Sheets.swift:495` | **LIVE — PRESERVE.** Used at `PracticeTimerView.swift:1525` |
| `showTaskImportPasteSheet` | `PracticeTimerView.swift:484` | **LIVE — PRESERVE.** Set `true` at `:2971`, bound at `:1519` |
| `showTaskImportScanSheet` | `PracticeTimerView.swift:485` | **LIVE — PRESERVE.** Bound at `:1527` |

They are members of **different types in different files**, and the `TasksManagerView` one is
`private`, so `PracticeTimerView` could not resolve to it even if the names were shared. The
`PracticeTimerView` import feature is a **working user-facing feature** and this unit does not
touch its file at all.

## 3. Candidate group 2 — C-12 deletion UI (`MOTIVO/SessionDetailView.swift`)

### 3.1 Reachability

The handover is right that this is **not** a zero-reference case: `deleteSession()` has a
lexical caller at `:867`. The claim is that the **trigger** is unreachable.

`showDeleteConfirm` occurs **exactly twice in the entire repository** — `:203` (declaration,
`= false`) and `:866` (`isPresented: $showDeleteConfirm`). **Nothing anywhere assigns it
`true`.** The only consumer of its binding is `.alert(_:isPresented:actions:)`, whose contract
is to *present when the binding is true* and to write **`false`** on dismissal; it never
writes `true`. So the alert can never present and the `Delete` button can never be tapped.

Excluded by declaration and context, not by absence of hits: `_showDeleteConfirm` (the
underlying wrapper) is never named; the binding is passed to no other modifier, stored in no
property and captured by no closure; `SessionDetailView` is a `View` **struct** with a
`private` member, so there is no `@objc`, selector, KVC or `NSObject` route; and no
`extension SessionDetailView` exists in any file. Codex independently confirmed that the
`UserDefaults` notification path only increments `_refreshTick` and that the `#if DEBUG`
paths do not set it.

**A different, live symbol must not be confused with it:**
`ConnectedAttachmentShareUI.swift:673` declares `showDeleteConfirmation` — different name,
different file, different type — and it **is** wired (`= true` at `:722`, bound at `:744`).
**Untouched.**

### 3.2 Proposed removal — 3 sites, 20 lines, zero orphans

| Lines | What |
|---|---|
| `203` | `@State private var showDeleteConfirm = false` |
| `866-869` | the `.alert("Delete Session?")` block, including `Button("Delete") { deleteSession() }` |
| `1786-1800` | `private func deleteSession()` |

**Shared dependencies all retained, verified:** `AttachmentStore.deleteAttachmentFiles`
keeps its live caller at `JournalDeleteBackendStep.swift:136`; `viewContext` keeps 10 other
uses in this file; `dismiss` keeps its use at `:823`.

### 3.3 Live deletion explicitly preserved

- **Journal swipe deletion is untouched** — it lives in `ContentView` (`deleteSessions`,
  `deleteSessionsWithBackendIfNeeded`) and `JournalDeleteBackendStep.deleteSessionLocally`.
  These are **different whole words** in different files. This unit does not edit them.
- **`SessionDetailView` attachment deletion (`:616`, `:623-624`) is a different feature and is
  untouched.**
- `MOTIVOTests/JournalDeleteQueuedPublishTests.swift` makes **source-text assertions** on
  `ContentView.deleteSessions` / `deleteSessionsWithBackendIfNeeded` (`:801-818`). None names
  `SessionDetailView.deleteSession`, so no assertion mirrors anything being removed.
- After removal, `SessionDetailView` offers **no session-delete affordance** — which is
  already true today, because the alert cannot present. **There is no user-visible delete
  control in this view to lose.**

## 4. Expected behavioural delta

**Zero, in both configurations.** No reachable code path changes; no shared state changes; no
persisted format changes; no layout changes (an `.alert` that never presents contributes no
layout). Nothing user-visible is added or withdrawn.

## 5. Proposed validation, and its stated limits

Proportionate, per the handover: Debug build, Release build, and the existing full
`MOTIVOTests` suite. **No new tests** — a test asserting that lines were deleted would mirror
the implementation and rot.

**Limits, stated in advance rather than after a green run:**
- **A passing suite does not prove deadness.** It is consistent with deadness and would also
  pass if a dead-but-untested path were removed. The reachability argument in §2.1 and §3.1
  is the evidence; the suite is a regression check on the retained code.
- **A compile failure would prove only a lexical dependency I missed** — which is exactly its
  value here, given §2.3.
- Builds corroborate the search for plain Swift types and `private` members. They are **not**
  a universal proof of dynamic use; §2.1 and §3.1 carry that argument separately.
- **No device QA is proposed**, both candidates being unreachable-only removals.

Single `xcodebuild` process at a time. Result bundle written to a **unique explicit
`resultBundlePath` outside DerivedData**, and its path recorded here.

**No mutation/delete-and-observe experiment is proposed.** For Tier B the informative
discriminator already exists statically — §2.3 names three members whose removal *would*
break the build — so a blind deletion experiment would add risk without adding evidence.

## 6. What is NOT in this unit

No backend, schema, deployment or production write. No age, sharing, invitations or
lifecycle-worker work. No device action. No commit and no push unless Samuel instructs it.
No edit to the protected files, to Codex-owned records, or to `PracticeTimerView.swift` /
`PracticeTimerView+Sheets.swift`. Tier C is reported only.

## 7. Open question — CLOSED 20 September 2026

**Asked:** whether Tier B should extend to the whole import subsystem, given that it removes
`TasksManagerImportLauncherSheet` while leaving `showTaskImportLauncher`,
`showTaskImportScanSheet` and `TasksManagerImportScanSheet` standing.

**Closed by Codex on review: the narrow scope is approved and sufficient, and this bounded
choice was delegated rather than escalated to Samuel.** Tier C stays retained. No product
decision is outstanding from this unit.

**The narrow scope then turned out to be load-bearing rather than merely tidy** — see §8.3.
Two of the Tier C members I retained are the exact delimiters a source-text test uses to
extract the regions it asserts on. Widening to Tier C would have silently changed what that
test reads.

---

# 8. IMPLEMENTATION AND EVIDENCE — 20 September 2026

Appended after implementation. **The tables above are the reachability record the approval was
given against and are NOT edited to match the outcome**; this section is what was actually
done and measured.

## 8.1 What was removed

Exactly the approved scope. **Pure deletion, zero insertions, `git diff --check` clean.**

| File | Deletions | Insertions | Lines after |
|---|---|---|---|
| `MOTIVO/TasksManagerView.swift` | **405** | 0 | 1195 |
| `MOTIVO/SessionDetailView.swift` | **21** | 0 | 2293 |
| **Total** | **426** | **0** | |

C-12 is 21 rather than the 20 estimated in §3.2: the extra line is the blank line that followed
`deleteSession()`, removed with it.

**Post-change hashes:**
- `MOTIVO/TasksManagerView.swift` — `8c60a178323c9b297611faf9281533ecfae29022219c017da6b0705cdd48fbd4`
- `MOTIVO/SessionDetailView.swift` — `bb0991f4dc1f34dbf7607869a77d40a9e59946660dbf4e26816fb3fed2381c98`

**Verified after removal:** all 26 removed symbols absent from both files; every retained Tier C
member and all three shared naming helpers present, with `textItems`, `uniqueTaskSetName` and
`defaultImportedTaskSetName` each at exactly 2 occurrences — the declaration plus the
`duplicateTaskSet` chain predicted in §2.3. `PracticeTimerView.swift`,
`PracticeTimerView+Sheets.swift`, `ConnectedAttachmentShareUI.swift`, `ContentView.swift` and
`JournalDeleteBackendStep.swift` all show **zero diff**.

## 8.2 Two things found during implementation that the proposal had not

**(1) `parseImportedTaskLines` is a THIRD naming collision, and the only Tier B member that is
module-visible.** It is `static func` with **no access modifier — internal**, so unlike every
other candidate it was not protected by file scope, and **§1's closure had only checked
references within its own file.** A module-wide search settled it: `PracticeTimerView`
declares its own separate `parseImportedTaskLines` (`PracticeTimerView+Sheets.swift:572`) with
**four live call sites** (`:1015`, `:1116`, `:1120`, `:1186`), while the `TasksManagerView` one
was called only from `:1304`, inside a removed member. Codex independently reproduced this
search. **The general point: an access-level audit belongs in the closure, because `private`
is what makes a within-file closure sufficient, and one member was not `private`.**

**(2) A range boundary was misattributed by the parser.** Line `:1240` is `@ViewBuilder`, an
attribute belonging to `importedTaskDraftRow` at `:1241`, but the parser assigned it to the
member above. Harmless here — both ranges were removed and they are contiguous — but a
parser that derives a member's end from the next member's start **will mis-split an attributed
declaration**, and that would matter if only one of the two were being removed.

## 8.3 The bounded scope was load-bearing, not merely tidy

`MOTIVOTests/ListsExplicitDefaultTests.swift` does not assert on whole files: it extracts
**source regions** delimited by *the next* `private func`, then asserts inside them. Its two
delimiters are **`saveItems` `:1106`** and **`commitTaskSetNameIfNeeded` `:1194`** — both
**Tier C, retained**.

**Had Tier B been widened to Tier C, both regions would have silently changed what they
read.** The narrow scope Codex approved was therefore protective rather than conservative,
and this is the concrete answer to §7.

Two source-text tests read `TasksManagerView.swift` and both were checked before removal:
- `ListsExplicitDefaultTests.swift:227` — region delimiters, above; also `:243`
  `ListsDefaultContext.effectiveInstrument(`, outside every removed range.
- `P6I04ListsPersistenceTests.swift:268` — requires `SavedListLibrary.load(` **at least once**
  in this file. It occurs exactly once, at `:1130`, inside the **reachable** `loadSavedTaskSets`
  — outside every removed range.

## 8.4 Builds and tests

**Single `xcodebuild` process at a time. Result bundles and logs are outside DerivedData**, in
the persistent evidence root `/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/`.

| Check | Result | Artefact |
|---|---|---|
| Debug build | **BUILD SUCCEEDED** | `p6cleanup-20260920-debug-build.log` |
| Release build | **BUILD SUCCEEDED** | `p6cleanup-20260920-release-build.log` |
| `MOTIVOTests` | **TEST SUCCEEDED — 938 passed, 0 failed, 8 skipped, 0 expected failures** | `p6cleanup-20260920-suite-2.{log,xcresult}` |
| `MOTIVOUITests` (extra, see below) | **TEST SUCCEEDED — 1 passed, 0 failed, 3 skipped** (top-level; the device row shows **4 passes** from four dynamic launch runs of the one parameterised launch test — literal accounting preserved, this is not four distinct tests) | `p6cleanup-20260920-uitests-1.{log,xcresult}` |

`xcresulttool` reports `"result": "Passed"` on **iPhone 17 Pro, iOS 26.5 (23F77)**,
device `336BE316-177B-46D8-8D28-809E4F41204B`, one configuration. **`XCODEBUILD_EXIT=0`**, and
the log-derived counts (938 / 0 / 8) match the bundle exactly.

### The first suite attempt FAILED, and it is preserved rather than deleted

`p6cleanup-20260920-suite-1.{log,xcresult}` — **`xcodebuild` exit 70, before any test ran.**

- **Established from the log:** the destination
  `DF4362E3-4C4B-4AFE-9369-15881D6BD793` is **absent from Xcode's eligible destination list**.
- **Established separately by `xcrun simctl`, because the log does not say why:** that UDID is
  an **iOS 26.0** runtime, below the project's 26.4 deployment target; the destination actually
  used is **26.5**.
- **NOT the cause, and initially misattributed by Claude:** the `iOS 26.3.1` line near the
  bottom of that log belongs to **Samuel's physical iPad**, not to the chosen simulator. Codex
  caught this. It is recorded because *"a plausible line in the same log"* is exactly how a
  wrong cause gets adopted.
- **`xcrun simctl list devices available` and Xcode's eligible-destination list are not the
  same set.** Pick the destination from the eligible list.

**A process note worth keeping:** the first attempt's background task reported "exit code 0"
while `xcodebuild` had actually exited 70 — the 0 was the exit status of the trailing `tail` in
a compound command. **Never score an `xcodebuild` run on a compound command's exit status;**
capture `$?` immediately after the build itself.

### The difference from the C-70 baseline — TWO separate effects, not one

The C-70 controlled run recorded 941 passed / 9 skipped; this run records 938 / 8.
**CORRECTED ON CODEX'S REVIEW: I first wrote that the difference was "entirely the scope of
the invocation". That was right about which tests are PRESENT and wrong about their STATUS,
and the second half is the half that costs coverage.**

**(a) Presence — invocation scope.** Diffing test identifiers between the two bundles gives
exactly four present then and absent now: `testBackgroundTimerPath()`,
`testEditSessionDescriptionPersists()`, `testLaunch()`,
`testPrimaryActivityFallbackOnHideOrDelete()`. **All four live in `MOTIVOUITests`**, which
`-only-testing:MOTIVOTests` excludes; in the C-70 run they contributed 1 pass and 3 skips.
No test present there is missing here for any other reason, and none was added.

**(b) Status — TWO TESTS WENT FROM PASSED TO SKIPPED, AND THAT IS REDUCED COVERAGE.**

| Test | C-70 run | This run |
|---|---|---|
| `StalePathQueuedPublishTests.testPublishThenReinspectFixture()` | **Passed** | **Skipped** |
| `UnshareDurabilityTests.testDemotionUnreachableKeepsIntentQueued()` | **Passed** | **Skipped** |

Both throw `XCTSkip("local Supabase stack not reachable — run `supabase start`")`
(`StalePathQueuedPublishTests.swift:56`, `UnshareDurabilityTests.swift:47`). **These two tests
failed their local-stack reachability preconditions; the exact cause is not established.**

**CORRECTED ON CODEX'S REVIEW.** This first read *"the local Supabase stack was running for the
C-70 baseline and was not running for this run"* — **an inference the evidence does not
support.** What each skip establishes is only that **that test's own probe was not reachable at
the moment it ran**, not that the stack was down throughout; other same-stack tests passed.
**A per-test precondition failure is not a measurement of the environment**, and stating it as
one would have put an unverified environmental claim into the record — the same shape as
misreading the iPad line in §8.4's destination failure.

**These are two additional coverage exclusions and must not be read as part of the standing
opt-in skip set.** The 19 September checkpoint's "6 skips … the existing opt-in reproduction
and local-stack suites" are the three `P6I02WithdrawalLocalStackTests` and the three
`SyncQueueOrderingReproductionTests`; **these two are on top of those.**

The arithmetic closes exactly: removing the UI target from the C-70 figures gives 940 passed /
6 skipped, and 940 − 2 = **938**, 6 + 2 = **8**.

**Not rerun**, on Codex's direction: both exercise publish/withdrawal durability, neither is
touched by an unreachable-only UI removal, and starting a local stack is outside this unit's
scope. **Recorded as a stated limit rather than closed.**

### The extra UI-target run did NOT obtain the coverage it was run for

**The approved validation scope was `MOTIVOTests`; the UI target was not required.** I ran it
anyway because `testEditSessionDescriptionPersists()` appeared to exercise `SessionDetailView`,
the view C-12 was removed from, and I wanted that covered rather than merely argued.

**It skipped, so no UI-level coverage of the edited view was obtained.** `XCODEBUILD_EXIT=0`,
result **Passed**, and the composition is **identical to the C-70 baseline's UI contribution —
1 pass, 3 skips**:

| Test | Outcome |
|---|---|
| `MOTIVOUITestsLaunchTests.testLaunch()` | **passed** |
| `AccessibilityAndPersistenceTests.testEditSessionDescriptionPersists()` | **skipped** |
| `AccessibilityAndPersistenceTests.testBackgroundTimerPath()` | **skipped** |
| `AccessibilityAndPersistenceTests.testPrimaryActivityFallbackOnHideOrDelete()` | **skipped** |

The three skips are fixture-dependent guards on an empty simulator —
`XCTSkip("No sessions available to open.")` (`MOTIVOUITests.swift:26`), plus
`"Activity Manager not available"` (`:83`) and `"Timer not present"` (`:96`).

**So what this run establishes is only that the app still launches.** It is recorded because
the honest outcome of an extra check is part of the evidence, and because *"the UI tests
passed"* would be a true sentence that implied something false here. **No further tests were
run and no fixture was manufactured to unskip it.**

## 8.5 What this evidence does and does not establish

- **A passing suite does not prove deadness.** It is a regression check on the retained code.
  The reachability arguments in §2.1, §2.1.1 and §3.1 carry the deadness claim.
- **Both builds succeeding proves no lexical dependency was missed** — which was a live risk,
  given §2.3 names three members whose removal *would* have broken the build, and given §8.2's
  module-visible member.
- **No behavioural delta was observed and none was expected.** No device QA was run, and none
  is claimed; both removals are unreachable-only.
- **`SessionDetailView` has NO UI-level test coverage in this run.** The one UI test that would
  have exercised it skipped for want of a session fixture. C-12's removal rests on the
  reachability argument in §3.1 and on both builds succeeding — not on any executed test of
  that view.
- **Two local-stack tests that passed in the C-70 baseline were SKIPPED here**, so this run's
  coverage is narrower than that baseline's in a second, independent way. See §8.4(b).
- **Nothing is committed or pushed.** That needs Samuel's specific instruction.
