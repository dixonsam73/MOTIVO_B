# P4-U2a / C-60 — ACCEPTANCE

**Executed 2026-09-04. Prediction committed beforehand at `84d2253`; scored
against it and against the U1 baseline `f12330e`.**

**Every prediction matched. Nothing was repaired forward.**

---

## 1. THE CHANGE — 2 FUNCTIONAL LINES

`MOTIVO/PublishService.swift`, the only file changed:

```diff
-if !shouldPublish, (mode == .backendPreview) && hasBaseURL && configured {
+if !shouldPublish, (mode == .backendPreview || mode == .backendConnected) && hasBaseURL && configured {
```

at **`:209`** and **`:304`**, plus a corrected comment above the first (the old
one said *"Preserve delete behavior in backend preview"*, which was the sentence
that made the defect look intentional).

**Nothing else.** No `shouldPublish` literal, no `BackendShim`, no SQL, no
policy, no project file. `git diff f12330e --name-only -- 'MOTIVO/*.swift'`
returns exactly one path (asserted as U2a-12/13).

**Why so small.** `BackendEnvironment.publish` already routed **both** modes to
the real HTTP service (`BackendShim:2144`), and the same two-mode pattern was
already at `:2155`, `:2164` and `SessionSyncQueue:174`. `PublishService` held the
only behavioural gate in the codebase naming `.backendPreview` alone. C-60 was
two un-widened predicates, never a missing implementation.

---

## 2. STRUCTURAL — EXACTLY THE TWO PREDICTED FLIPS

`supabase/tests/p4/u1-baseline.sh` is **left unchanged as the immutable pre-U2
record**. It now reports **14 passed, 2 failed**:

| id | predicted | observed |
|---|---|---|
| **P4U1-5** | 2 → **0** | **0** ✓ |
| **P4U1-6** | 0 → **2** | **2** ✓ |

**All 14 others unchanged**, including P4U1-1/2 (both `shouldPublish: true`
literals intact — U2b not started), P4U1-15 (`posts_insert_owner` still has no
`is_public` predicate — U2s not started) and **P4U1-11/12/13**, the Phase 3
`LocalFactoryReset.perform` exit assertion.

New suite `supabase/tests/p4/u2a-acceptance.sh` — **17 passed, 0 failed** —
asserts the post-U2a state, including that `.backendPreview` is still named 5×
(expansion, not replacement) and that no migration/function/schema file moved.

### Two assertions of MINE were wrong and were corrected against measurement

**U2a-4** counted the bare word `deletePost` and expected 2; the true value is
**6** — two calls and **four NSLog string literals**, which are code and survive
comment stripping. Re-pinned to `publish\.deletePost` = 2. **U2a-6** expected
`.backendPreview` 4×; the true value is **5** — I had missed the early-exit at
`:103`. **Both were caught on the suite's first run and fixed by establishing
the correct value, not by relaxing the assertion** — C57-7's shape.

---

## 3. BEHAVIOURAL — ALL FOUR CASES PASS, AND CASE A IS A DISCRIMINATOR

`MOTIVOTests/PublishServiceConnectedDeleteTests.swift`, against the **local
Supabase stack** (`127.0.0.1:54321`). Evidence level: **verified against a
faithful local reproduction.** Production never held a test fixture.

| # | case | result |
|---|---|---|
| **A** | `.backendConnected` unshare | **PASS — post row AND storage object both deleted** |
| **B** | `.backendConnected`, object deletion refused | **PASS — object survives AND row survives (fail-closed)** |
| **C** | `.backendPreview` unshare | **PASS — still deletes** |
| **D** | `.localSimulation` unshare | **PASS — gate does not fire; row and object survive** |

### 3.1 THE DISCRIMINATOR — THE SUITE WAS RUN AGAINST THE PRE-U2a CODE

**A test that passes both before and after a fix proves nothing**, so the gate
was reverted and the suite re-run:

```
PRE-U2a:  A FAILED   —  "A: storage object must be deleted in .backendConnected"
                        "A: post row must be deleted in .backendConnected"
          B, C, D passed
POST-U2a: A, B, C, D all passed
```

**That failure IS C-60 observed behaviourally** — the first time the defect has
been seen rather than read. `PublishService.swift` was then restored byte-for-byte
from the copy taken before the revert.

### 3.2 B AND D ARE HONEST ABOUT WHAT THEY PROVE

**B passes pre-fix VACUOUSLY** — with the gate closed, no delete is attempted, so
the row trivially survives. Its post-fix pass is meaningful only in combination
with A, which establishes that the gate *does* fire in `.backendConnected`.
Together they give the intended claim: **the gate fires, the object deletion is
refused, and the row is nevertheless not deleted.** Stated rather than glossed.

**D measures the scope record's §7 observation.** `SimulatedPublishService.deletePost`
(`BackendShim:308`) performs **real** network deletion, unlike its own simulated
`uploadPost`. What keeps that harmless in Solo is precisely this gate not firing —
which D now measures instead of assuming.

### 3.3 THE TEST TARGET'S SCOPE WAS WIDENED, DELIBERATELY

`MOTIVOTests.swift` declares the target covers "the PURE pieces … nothing that
needs a network, a session, StoreKit or a running app". U2a's acceptance cannot
be met inside that boundary — the thing it changes is a **gate in front of a
network call**. The new file states this in its header, pins the base URL to
loopback and refuses to run otherwise, and **XCTSkips when the local stack is
down**, so `xcodebuild test` still passes on any machine. `MOTIVOTests` is a
`fileSystemSynchronizedGroup`, so **no project file change was needed**.

### 3.4 TWO HARNESS DEFECTS, BOTH MINE, BOTH RECORDED

**(i) MIME.** The fixture uploaded `application/octet-stream`; the `attachments`
bucket restricts `allowed_mime_types` and answered **415 `InvalidMimeType`**.
Corrected to `image/jpeg`.

**(ii) A SECOND `NSPersistentContainer` FOR THE SAME MODEL.** The harness built
its own in-memory container to obtain a throwaway `NSManagedObjectID`. That
loaded the model a second time and left the shared store throwing **"A fetch
request must have an entity"** in whichever test ran next — so **case A passed
alone and crashed in suite**, which is exactly the shape that gets mistaken for a
product defect. Replaced with a scratch `NSManagedObjectContext` on the app's
existing coordinator, using a **temporary** object id (the `shouldPublish == false`
path only ever calls `uriRepresentation()`).

**Neither was a defect in the code under test**, and neither is recorded as one.

### 3.5 FIXTURE HYGIENE

Every created id was recorded before mutation and removed in `tearDown` **by
explicit id — no predicate sweep**, per B-22's rule. Local stack verified
restored afterwards: `posts` back to its pre-run **2**, and **zero `.jpg`
objects remain** — all 5 surviving `attachments` objects are the pre-existing
U7f `.pdf` fixtures from 2026-09-03.

---

## 4. GATES

| gate | result |
|---|---|
| Debug build | **BUILD SUCCEEDED**, 0 errors |
| Release build | **BUILD SUCCEEDED**, 0 errors |
| `MOTIVOTests` | **19 of 19 passed** (15 pure + 4 behavioural) |
| `u5/client-structural.sh` | **60 / 60** — C57-1..7 undisturbed |
| `p4/u2a-acceptance.sh` | **17 / 17** |
| `p4/u1-baseline.sh` | 14 pass / **2 predicted flips** |

---

## 5. PRODUCTION CENSUS — ZERO DELTA, AS PREDICTED

| measure | U1 | after U2a |
|---|---|---|
| `total_posts` / `public_posts` | 101 / 101 | **101 / 101** |
| `private_false` / `private_null` | 0 / 0 | **0 / 0** |
| `owners` / `total_attach_refs` | 9 / 10 | **9 / 10** |
| attachment objects / referenced / unreferenced | 15 / 11 / 4 | **15 / 11 / 4** |
| avatar objects | 3 | **3** |
| `connected_attachments` rows / live | 31 / 6 | **31 / 6** |

**Every value identical.** As predicted: the widened gate is reachable only via
`shouldPublish == false`, and both call sites still pass `true`.

---

## 6. WHAT U2a DOES NOT DO

- **U2b is not started** — both `shouldPublish: true` literals are untouched, so
  **an un-share still cannot be triggered from the shipping UI.** C-60 is fixed
  but its path stays unreachable in the app until U2b.
- **U2c and U2s are not started.** No `is_public` gate on the attachment path; no
  server guard; `posts_insert_owner` unchanged.
- **No server-side `UPDATE` restriction on `is_public`** — forbidden by §2a and
  by standing instruction.
- **Deletion semantics are unchanged**, including fail-closed ordering, asserted
  structurally (U2a-15) and behaviourally (case B).
- **The four `"Preview deletePost"` log strings still say "Preview"** and now
  fire in Connected mode. Deliberately left — U2a's constraint is the smallest
  change — and **pinned by U2a-6b so U2b must address them consciously.**
- **C-31 untouched.** Still an open carried release obligation.

## 7. CARRIED FORWARD TO U2b

**The optimistic-registry consequence, predicted at §4.1 of the prediction and
neither observed nor fixed here.** `publishedURIs` persists the removal
*before* the network delete, so a failed delete leaves the client believing the
session is unpublished while the server row survives. U2a makes this reachable;
**U2b makes it reachable from the real UI**, and owns deciding whether it needs a
register row of its own.
