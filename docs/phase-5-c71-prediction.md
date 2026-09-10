# C-71 — REACHABILITY TRACE AND PREDICTION, BEFORE MUTATION

**Inspected at `3657b41`, 2026-09-10.** Approved product rule: local
`SessionDetailView` (owner's Journal, Solo **and** Connected) **removes**
`SessionIdentityHeader`; Connected Feed uses `BackendSessionDetailView` and
**keeps** its attribution for every post including the member's own, because the
distinction is **surface/context, not ownership**.

---

## 1. The reachability trace — CLEARS, decisively

**Question:** does any supported path use local `SessionDetailView` to display
another person's session, where this header provides necessary attribution?
**Answer: no.**

**Only two things create a local `Session` row**, and both are owner-authored:
`AddEditSessionView:1921` and `PostRecordDetailsView:1756`. **Nothing anywhere
constructs a `Session` from a `BackendPost`** — remote content lives in
`BackendPost` / `BackendSessionViewModel` and never becomes Core Data.

**Every writer of `Session.ownerUserID` assigns the signed-in member:**
`AddEditSessionView:1994` and `PostRecordDetailsView:1801` both write
`PersistenceController.shared.currentUserID`; `Persistence:366` backfills rows
whose value is nil or empty. **The only way to get a foreign value is
`Debug.currentUserIDOverride`, which is `#if DEBUG` and absent from Release.**

**Consequence:** `SessionIdentityHeader.displayName`'s `"User"` branch (`:2023`)
is **unreachable in Release**. The header can only ever show the member their own
avatar, name and location on their own session — which is exactly the redundancy
C-71 identified.

## 2. A CORRECTION TO MY OWN INVENTORY

I reported the row carried *"no actions"*. **That was accurate about the
struct's body and incomplete about the CALL SITE.** `SessionDetailView:747`–`:753`
attaches a `#if DEBUG` `.onLongPressGesture(minimumDuration: 0.6)` that opens the
session debug sheet — and `:750`–`:752` is the **ONLY** trigger for
`isDebugPresented` in the file.

**So removing the row naively would delete the only developer route to
`DebugViewerView` for a session.** Not user-facing — it does not exist in
Release — but it is real functionality, and it is precisely the "unrelated
functionality" the prerequisite exists to catch. **It will be preserved**, not
dropped silently.

---

## 3. PREDICTION

**P1.** `SessionIdentityHeader(session:)` and its `.environmentObject(auth)` and
`.padding(.bottom, session.isThought ? 8 : 4)` are removed from `mainContent()`.
The row's own bottom padding goes **with** the row, because it was the row's.

**P2.** The `fileprivate struct SessionIdentityHeader` (`:1985`–`:2083`) is
**deleted**, not left unused. It had exactly one call site.

**P3 — C-72 is discharged by deletion.** Its body-time `Profile` fetch lived in
`displayName` (`:2019`), reached from `body` twice per evaluation, and that code
ceases to exist. **Verified structurally, not assumed:** after the change no
`viewContext.fetch` remains in the deleted struct's former range and
`SessionIdentityHeader` appears nowhere.

**P4 — the DEBUG affordance survives.** The long-press moves to `mainContent()`'s
outer `VStack`, still `#if DEBUG`. **Deliberately broader than the row it came
from** — both branches open with their own `VStack`, so there is no common small
element — and it is invisible in Release either way.

**P5 — no spacing redesign yet.** Beyond removing the row's own padding, layout
values are **left alone** for the device pass. The orphaned comment *"slightly
more separation from identity row"* (`:761`) is corrected, since it now refers to
something that does not exist.

**P6 — `BackendSessionDetailView` is untouched.** Feed attribution is unchanged
for every post, including the member's own.

### Evidence

Structural assertions that `SessionIdentityHeader` is gone and that
`BackendSessionDetailView`'s identity header survives; Debug and Release clean;
warning delta measured; structured full-suite census.

**This unit does NOT close on that.** Per instruction it **stops for a physical
device visual pass** before C-71 is closed or any consequential spacing change is
made.
