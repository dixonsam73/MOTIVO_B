# P4-U2c COMPLETION AMENDMENT — PREDICTION

**Written 2026-09-04 at `7ecdba9`, BEFORE any source change.** A U2c completion
amendment, not a new unit.

**The gap, restated precisely.** U2c proved the two shipping call sites do not
construct `.publish + isPublic:false`. It did **not** prove the combination
cannot reach the upload choke point. **It can, and by a concrete route.**

---

## 1. CONSTRUCTION TOPOLOGY — ENUMERATED

### 1.1 Production constructors — **9**, plus **1 decoder**

| # | site | `op` | `isPublic` | can build the forbidden pair? |
|---|---|---|---|---|
| 1 | `AddEditSessionView:2062` | default `.publish` | `isPublic` (user toggle) | **object yes, enqueue no** — U2b routes `shouldPublish: isPublic`, so a false one becomes `.unshare` in `PublishService` |
| 2 | `PostRecordDetailsView:1819` | default | `visibility` | same |
| 3 | **`PublishService:167`** | **default `.publish`** | **`sIsPublic`, read from Core Data** | **YES — see §1.2** |
| 4 | `PublishService:193` | `.unshare` | false | no |
| 5 | `PublishService:276` | default `.publish` | `payload.isPublic` | yes in principle; call sites make it true |
| 6 | `PublishService:321` | `.unshare` | false | no |
| 7 | **`SessionSyncQueue:185`** (merge) | **`payload.op`** | **`mergedIsPublic`** | **YES — two independent fields recombined** |
| 8 | `SessionSyncQueue:213` (`enqueue(postID:)` stub) | default | default true | no |
| 9 | `SessionSyncQueue:358` (legacy `[UUID]` fallback) | default | default true | no |
| D | `init(from:)` | missing → `.publish` | decoded, default true | **YES — a hand-edited or legacy file** |

**Tests (separate category, as instructed):** `UnshareDurabilityTests`,
`PublishServiceConnectedDeleteTests`, `SharedOnlyUploadTests` — four sites.

### 1.2 THE CONCRETE ROUTE, NOT A HYPOTHETICAL

**`PublishService.publish(objectID:)` (`:360`) → `publishIfNeeded(shouldPublish:
true)` → the payload at `:167` with `isPublic: sIsPublic` read straight from Core
Data (`:123-156`).**

**Called on a session whose local `isPublic` is false, that constructs
`.publish + isPublic:false`, enqueues it, and it reaches `uploadPost` —
writing a private row AND uploading its attachments.** It has **no callers
today**, which is why nothing is broken; it is nonetheless production API, and
"no caller today" is exactly the guarantee the amendment is asked to replace.

### 1.3 DO `op` AND `isPublic` NEED TO BE INDEPENDENT? **NO.**

After U2b they are **the same bit**:

| `op` | meaning | `isPublic` |
|---|---|---|
| `.publish` | the post must exist **and be visible** | necessarily **true** — a private post must not exist at all (invariant 2) |
| `.unshare` | the post must **not exist** | irrelevant; only ever written `false` |

Every one of the 9 constructors is consistent with `op == (isPublic ? .publish :
.unshare)`. **The forbidden state is precisely the case where two redundant
fields disagree.**

---

## 2. THE FIX — OPTION 1: MAKE IT UNREPRESENTABLE

**Derive `op` from `isPublic` in the initializer and remove `op:` as a
parameter.**

```swift
public init(… isPublic: Bool = true, notes: …, areNotesPrivate: …) {
    self.op = isPublic ? .publish : .unshare      // DERIVED, never supplied
}
```

**`PostPublishPayload(…, op: .publish, isPublic: false)` then does not
compile** — there is no `op:` argument to pass.

**Why derive `op` from `isPublic` and not the reverse.** Removing `isPublic:`
instead would be equally sound and **would destroy the U2c-9/U2c-10 call-site
symmetry assertions**, which the brief requires preserving. Keeping `isPublic:`
as the single expressed input keeps those assertions meaningful *and* removes the
second field. **The smaller change is also the one that preserves the existing
evidence.**

### 2.1 The decoder is where "unrepresentable" becomes a runtime property

Compile-time removal does not police a file on disk. `init(from:)` will
**normalize**:

| file contains | decoded as | why |
|---|---|---|
| no `op`, `isPublic` true/absent | **`.publish`** | unchanged from today |
| no `op`, **`isPublic: false`** | **`.unshare`** | **A DELIBERATE SEMANTIC MIGRATION — see §2.2** |
| `op` present and agreeing | as written | — |
| **`op: publish` with `isPublic: false`** | **`.unshare`** | the contradiction resolves to the **safe** reading; never to "upload it" |

### 2.2 THE ONE BEHAVIOUR CHANGE, STATED LOUDLY

A legacy queued item with `isPublic: false` meant *"publish this and demote it to
private"* — the pre-U2b Share-OFF behaviour. **It will now converge to deletion
instead of demotion.**

That is **the user's original intent** (they turned Share OFF) expressed under
Phase 4's rule that private content does not belong on Supabase, and it is
strictly more privacy-preserving than leaving a private row. **The alternative —
decoding it as `.publish` — would either upload a private row (the defect) or be
rejected and stick in the queue for ever.** Recorded as a migration, not slipped
in.

### 2.3 No runtime choke-point guard is added

The brief's option 2 applies only *"otherwise"*. Option 1 succeeds, and §2.1
closes the decode path, so a `guard` in `uploadPost` would be unreachable by
construction.

---

## 3. PREDICTED SOURCE CHANGES

| file | change |
|---|---|
| `SessionSyncQueue.swift` | `op` becomes derived: removed from the memberwise init, computed in it; `init(from:)` normalizes (§2.1); the merge drops `op:`/`isPublic:` recombination and lets the init derive |
| `PublishService.swift` | 4 constructors drop `op:` — `.unshare` becomes `isPublic: false` |
| **not touched** | `AddEditSessionView`, `PostRecordDetailsView`, `BackendShim` |
| tests | 4 constructors drop `op:` |

**`AddEditSessionView` and `PostRecordDetailsView` are untouched**, which is why
U2c-9/U2c-10 keep passing unchanged.

## 4. PREDICTED ASSERTIONS

| id | asserts | predicted |
|---|---|---|
| U2c-15 | the memberwise init declares **no `op:` parameter** | **0** |
| U2c-16 | `op` is a `let` — no setter anywhere | **0** writes outside init |
| U2c-17 | the init derives `op` from `isPublic` | **1** |
| U2c-18 | `init(from:)` normalizes a contradictory file to `.unshare` | **1** |
| U2c-19 | no production site passes `op:` | **0** |
| **U2c-20** | **DISCRIMINATOR — the forbidden construction does not compile** | see §5 |

**U2c-1..14 all keep their current values**, including **U2c-9/U2c-10**.

## 5. THE DISCRIMINATOR

**A structural assertion that a parameter is absent is not proof that the state
is unreachable.** So the forbidden construction will be added to a test file,
`xcodebuild` run, and the **compiler error captured**, then removed and the file
restored byte-identically — the same shape as U2c-9's revert test.

**Predicted:** a compile error naming an extra argument `op:`, and
`git diff` empty afterwards.

## 6. PREDICTED BEHAVIOURAL RESULTS — ALL PRESERVED

Legacy decode still green (with §2.2's migration now asserted); `.unshare`
durability and convergence unchanged; **last-intent-wins unchanged** (the merge's
`payload.op != existing.op` branch is untouched); ordinary `.publish` unchanged;
preview and Solo unchanged.

`MOTIVOTests` **39/39**; `u5` 60/60; `u2a` 16/16; `u2a2` 22/22; `u2b` 16/16;
`u2c` **14 → 19/19 + the discriminator**; `u1-baseline` 11 + its 5 flips.

## 7. OUT OF SCOPE

**U2s not started** — no `posts_insert_owner` guard. **No production, membership,
U6b enforcement or Device A change.** **U2b stays device-verification-pending.**
