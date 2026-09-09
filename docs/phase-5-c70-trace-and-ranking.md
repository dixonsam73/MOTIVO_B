# C-70 TRACE + PHASE-5 RE-RANKING. 2026-09-09

**Investigation only. No implementation. No production, ASC or device mutation.**

## 1. C-70 — THE PREMISE SUBSTANTIALLY DEFLATES

### 1.1 The dominant cause is a KNOWN BLOCKED CONDITION, not a new defect

**Measured on the deployed policies:**

| policy | gated? |
|---|---|
| `account_directory_insert_owner` (INSERT) | **`enforcement_gate('account_directory.insert')` AND `user_id = auth.uid()`** |
| `account_directory_update_owner` (UPDATE) | **NOT gated** — `user_id = auth.uid()` only |

**So creating a directory row is enforcement-gated; updating an existing one is
not.** Production holds **one membership row, Sandbox only**, so
`connected_member()` is false for every identity and **no INSERT can succeed**.

**Device A is signed in as `6fd0a833`, which has ZERO directory rows** (measured
earlier this session; `dfaf8d18` holds the only one).

**That single fact produces all three reported symptoms:**

1. **Account ID does not populate** — there is no directory row to hydrate from.
2. **"Couldn't update your Account ID" appears frequently** — every upsert is an
   INSERT, and every INSERT is refused at the gate.
3. **Auto-generation does not happen** — `AccountDirectoryService`'s own header
   states generation *"requires an existing backend directory row before deriving
   a handle"*, and there is none.

**This is the SAME ROOT as Phase 4 conditions 2 and 8:** enforcement live, no
Production entitlement. **A genuine App Store subscriber would hold a Production
membership row, `connected_member()` would be true, and the INSERT would
succeed.** So the dominant symptom is a **pre-release testing artefact, not a
shipping defect.**

### 1.2 ONE GENUINE SHIPPING DEFECT SURVIVES — and it is small

**`upsertSelfRow` writes the WHOLE row** — `displayName`, `accountID`, `location`
and `instruments` — but **every non-collision failure is reported as
"Couldn't update your Account ID. Please try again."** (`ProfileView:1524`).

**So a failed NAME or LOCATION edit blames the Account ID field.** The message is
user-facing misinformation, it is independent of enforcement, and it will ship.
**Collision is handled correctly and separately** (*"That account ID is already
taken"*), which shows the distinction was already understood once.

### 1.3 A weaker coupling, recorded but not dramatic

`ProfileView` calls `attemptAccountIDAutoGenerationIfNeeded` **only from the
`.success` branch**. But generation has **three** entry points — `ProfileView:1558`,
`AuthManager:602` (backfill) and `AppSetUpView:331` — so it is not solely coupled
to that upsert. **Weaker than it first appeared.**

### 1.4 One defect or several? **ONE ROOT CAUSE PLUS ONE UI DEFECT**

Not three defects. **The device observations are one blocked condition
(§1.1) presented through one misleading message (§1.2).**

### 1.5 User impact

**At release: small.** An entitled member creates their row normally.
**Before release: large but expected** — an unentitled identity cannot create a
directory row, so it is undiscoverable, unattributable and has no Account ID.
**The shipping harm is the wrong error text.**

### 1.6 No device work needed

The trace was completed from source and deployed policy. **A discriminator exists
if ever wanted** — sign in on an identity that already has a directory row
(`dfaf8d18`) and confirm edits succeed, since UPDATE is ungated — but it would
only confirm what the policies already state.

## 2. RANKING AT HEAD

| # | item | evidence | why here |
|---|---|---|---|
| **1** | **C-56** | **CONFIRMED at HEAD**: `requiresAppSetUpNow()` runs a `Profile` fetch **plus** `fetchInstruments()`, reached from `body` at **two** sites; previously **measured** at 47/50 samples, ~100% CPU | Real user-visible cost on the **first screen a new member sees**. Bounded, local evidence, no external deps |
| **2** | **C-70(a)** | **CONFIRMED**: one message for four fields | Ships; misinforms; tiny fix. Cheap companion to any unit |
| **3** | **C-67 / P5-N** | **CONFIRMED**: all 12 `accessibilityLabel`s are top-toolbar; both `mediaControlButton` helpers add none | **Planned Phase-5 work, not a finding bucket.** Placed explicitly so it cannot drift |
| **4** | **C-5** | **CONFIRMED, sharper than the row**: `savedToScoresAt` has **zero UI reads** | User-visible duplicate; bounded |
| **5** | **C-62** | **CONFIRMED it ships** (DEBUG depth 0) | **Measurement first** — may deflate if `%@` reads `<private>` |
| 6 | C-65 | confirmed | needs product semantics |
| 7 | C-68 | confirmed | real teardown gap, no observed consequence |
| 8 | C-69 | confirmed | correct, but path unreachable |
| 9 | C-66 | confirmed | impact reasoned, not measured |
| 10 | C-71 | recorded | inventory required first |
| 11 | C-3 | confirmed, P3 | sibling of C-56 |
| — | C-20 | **premise does not reproduce** | re-verification only |
| — | **C-64** | **REFUTED, closed** | 118/118 across six structured runs |

### 2.1 Accessibility, explicitly

**P5-N sits at 3 — above C-5 and C-62 — and that is deliberate.** It is *planned
Phase-5 work*, it now carries **two** findings, and it has no advocate.
**If it slips past two more units it should be promoted regardless of what else
is filed.**

## 3. RECOMMENDATION — **C-56**, with **C-70(a)** folded in

**C-56 outranks C-70** because C-70's dominant symptom is a known blocked
condition that resolves itself at release, whereas C-56 is a measured cost on the
onboarding screen that ships exactly as-is.

**C-70(a) is cheap enough to carry alongside** — it is a message-correctness
change in the same `ProfileView` area, with no shared mechanism, so it can be
scoped as a clearly separate second commit inside one unit or split out entirely
if you prefer strict one-defect units.

**I am NOT preserving C-70's priority because it was device-observed.** Its trace
deflated it, and the ranking follows the trace.

## 4. PROPOSED SCOPE — C-56

**Measure first, then fix.** The register's 47/50-sample figure came from the
C-55 investigation and is **not** a current measurement.

1. **Re-measure at HEAD** — confirm the fetches occur per body evaluation and
   quantify, before changing anything.
2. **Fix**: hoist the Core Data reads out of `body` into state computed on
   appearance and on the events that can change the answer.
3. **Assert** no Core Data fetch is reachable from `body`.

**Acceptance:** a before/after measurement; both builds clean; full suite via
`scripts/test-census.py` showing **118/118**; warning delta zero; **no change to
onboarding behaviour** — the same screen must still appear under the same
conditions.

**External requirements: none.** Simulator and local stack only.

## 5. DEMOTED OR CLOSED IN THIS PASS

- **C-64 — CLOSED, refuted** by structured census.
- **C-70 — DEFLATED**: dominant cause re-attributed to the enforcement-gated
  INSERT (Phase 4 conditions 2/8); **only the misleading message survives as a
  shipping defect**, carried as **C-70(a)**.
- **C-20 — remains demoted**, premise not reproduced.
- Nothing else closed.
