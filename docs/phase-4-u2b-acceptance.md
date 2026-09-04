# P4-U2b — SHARED-ONLY UPLOADS. ACCEPTANCE.

**Executed 2026-09-04. Prediction committed beforehand at `1905e7a`.**
**Every structural and behavioural prediction matched.** Two assertions of my own
were wrong and were corrected against measurement; one planned piece of evidence
could not be obtained and is recorded as not obtained rather than quietly
dropped.

---

## 1. THE CHANGE — 3 FILES

| file | change |
|---|---|
| `AddEditSessionView.swift` | `shouldPublish: true` → **`shouldPublish: isPublic`** |
| `PostRecordDetailsView.swift` | `shouldPublish: true` → **`shouldPublish: visibility`** |
| `PublishService.swift` | **both C-60 gate blocks removed** (§2) |

No `BackendShim`, no `SessionSyncQueue`, no SQL, no policy, no project file.

**Every session saved since `ec75a3c` (2026-01-30) reached the server, and the
Share toggle only set a column.** That ends here.

---

## 2. DISPOSITION OF THE REDUNDANT IMMEDIATE DELETE — REMOVED

The `shouldPublish == false` sequence was:

1. `enqueue(op: .unshare)` — the durable intent;
2. **`await flushNow()`** — which *synchronously* runs `unsharePost`: demote,
   then delete, dequeue only on confirmed removal;
3. the C-60 gate — **`deletePost`, a bare delete with no demotion**.

**Step 3 is removed.** The immediate best-effort attempt is step 2, which is
`await`ed, so removal costs no immediacy. Routing step 3 through `unsharePost`
instead would have run the whole demote-then-delete a **second** time on every
unshare, re-PATCHing a row the queue may have just deleted, for no extra
guarantee. And leaving it was the option the brief forbids — **two unshare
semantics in parallel**, the second of them the bare-delete shape whose missing
demotion *is* C-61.

| property | preserved by | asserted |
|---|---|---|
| immediate best-effort | the awaited `flushNow` | `U2b-12` |
| durability | the persisted queue | `U2b-13` |
| demote-before-delete | one primitive | `U2b-11` |
| no second semantics | — | `U2b-9`, `U2b-10` |

**C-60 is not reopened.** Its defect was that un-sharing reached *no* deletion in
`.backendConnected`; the path now reaches it through a strictly stronger
primitive, and **its regression tests still pass, now via the queue**.

---

## 3. STRUCTURAL — EXACTLY THE PREDICTED FLIPS

| id | predicted | observed |
|---|---|---|
| P4U1-1, P4U1-2 (`shouldPublish: true`) | 1,1 → **0,0** | **0,0** ✓ |
| P4U1-3 (AESV `isPublic`) | 0 → **1** | **1** ✓ |
| P4U1-4 (PRDV `visibility`) | 0 → **1** | **1** ✓ |
| P4U1-6 (`.backendConnected` in `PublishService`) | 2 → **0** | **0** ✓ |
| P4U1-11/12/13 (`LocalFactoryReset`) | unchanged | **unchanged** ✓ |
| P4U1-14/15/16 (server policies) | unchanged | **unchanged** ✓ |

**`P4U1-6` RECOVERED to its pre-U2a value**, which is the cleanest possible
signal that the gate mechanism is gone rather than merely widened.

`u2b-acceptance.sh` — **16 / 16**.

---

## 4. BEHAVIOURAL — 5 NEW CASES, ALL PASS

`MOTIVOTests/SharedOnlyUploadTests.swift`, calling
`publish(…, shouldPublish: payload.isPublic)` — exactly what the shipping call
sites now pass.

| case | result |
|---|---|
| Connected **Share OFF** → no post row | **PASS** |
| Connected **Thought** → no post row | **PASS** |
| **Included attachment + Share OFF** → no row, no object, no `.publish` item | **PASS** |
| **Share ON** → row created, public, dequeued | **PASS** |
| **shared → Share OFF** → row removed, dequeued | **PASS** |

Plus, unchanged and still green: offline→converges, A/B/C failure points, both
collision directions, legacy-file decode, preview, Solo, and the **C-60 / C-61
regression cases**.

### 4.1 A PLANNED CONTROL THAT COULD NOT BE OBTAINED — STATED, NOT DROPPED

The attachment case was designed with a **positive control**: the same Core Data
fixture, Share **ON**, must upload the object — because "Share OFF uploaded
nothing" is vacuous unless the fixture was capable of uploading.

**The control FAILED.** The post row was created with `attachments: []`, meaning
`loadIncludedAttachments` returned nothing, on a fixture whose three
preconditions all verified: the attachment marked **included**
(`AttachmentPrivacy.isPrivate == false`), the media file **present on disk**, and
the session exposing **exactly one** attachment through the relationship.

**The cause was not established, and no product defect is claimed.** The
difference between this synthetic Core Data fixture and a session created by the
real editor is unreproduced. **What was NOT done is keep the vacuous negative and
present it as coverage.** Instead the claim is now carried by two halves that are
each sound:

- **behavioural** — Share OFF creates no row and enqueues **no `.publish` item**;
- **structural** — `loadIncludedAttachments` has **exactly one call site**, it is
  **inside `uploadPost`** (`U2b-6`, `U2b-7`), and `uploadPost` is invoked from
  **exactly one place** in the queue (`U2b-8`), which runs only for `.publish`.

Together: the upload path has one entrance, and Share OFF never reaches it.
**U2c owns the direct assertion on the attachment path.**

---

## 5. TWO OF MY OWN ASSERTIONS WERE WRONG

**`U2b-12`** expected `flushNow` twice in `PublishService`; the true value is
**3** — I had forgotten the `backendPreview` early-exit flush at `:104`.
**`U2a-6b/6c`** pinned the four `"Preview deletePost"` log strings; U2b deletes
the block they lived in, so an assertion about a removed construct is noise —
**removed, with `U2b-9` carrying the stronger fact** (no bare `deletePost`
remains at all). Both corrected against measurement, neither by relaxing a
threshold.

---

## 6. SUITE-PINNING POLICY, ADOPTED HERE

`u2a-acceptance.sh` asserts the gate U2b removes; `u2a2-acceptance.sh` asserts
*"U2b not started"*. Left alone they would have joined `u1-baseline.sh` as a
third and fourth permanently-failing suite — **13 expected failures across four
files, which is precisely where a real regression hides.**

**A unit's acceptance suite is now evaluated against that unit's own commit** for
its unit-specific assertions (`git show <sha>:<path>`), while standing invariants
stay **live** — the server policy shape, `LocalFactoryReset`'s two callers, and
in `u2a2` the queue and demote-then-delete contracts, whose value is precisely
that they can still fail.

**`u1-baseline.sh` is deliberately NOT pinned.** It is the phase's immutable
pre-change measurement, and its now-**5** documented flips are its own evidence:
P4U1-1/2/3/4 from U2b and P4U1-5 carried from U2a.

---

## 7. GATES

| gate | result |
|---|---|
| Debug / Release build | **BUILD SUCCEEDED**, 0 errors |
| `MOTIVOTests` | **38 of 38** |
| `u5/client-structural.sh` | **60 / 60** |
| `p4/u2b-acceptance.sh` | **16 / 16** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **16 / 16** (pinned) |
| `p4/u1-baseline.sh` | 11 pass / **5 documented flips** |

---

## 8. PRODUCTION CENSUS — BEFORE AND AFTER

| measure | before (U1 → U2a-2) | after U2b |
|---|---|---|
| `total_posts` / `public_posts` | 101 / 101 | **101 / 101** |
| `private_false` / `private_null` | 0 / 0 | **0 / 0** |
| `owners` | 9 | **9** |

**Zero delta.** No production fixture was created. Local stack restored: **2
posts, 5 attachment objects (the pre-existing U7f `.pdf` fixtures), 0 `.jpg`
leftovers.**

### 8.1 DEVICE VERIFICATION — NOT PERFORMED. PROCEDURE PROPOSED

**No existing beta-owned post can be toggled OFF and restored.** A read-only
survey found candidates with **0 attachments, 0 comments, 0 shares** (e.g.
`179a9e67…`, 2026-07-10), so blast radius could be minimised — **but minimal
blast radius is not reversibility**:

- under U2b, Share OFF **deletes the row permanently**; there is no undo and no
  backup of Domain 3 content;
- "restoring" means re-sharing, and `uploadPost` writes **`created_at` = now**,
  so the post would return with a **fabricated date** and re-enter followers'
  feeds as new.

**Proposed smallest reversible procedure, for approval before anything is
created:** on Device A (Release — Debug cannot transact), create a **fresh
throwaway session**, share it, confirm the row appears, record its id, then
toggle Share OFF and confirm the row and any objects are gone. The fixture is
disposable by construction, **its removal is the behaviour under test**, and no
pre-existing beta record is touched. Census before and after.

---

## 9. WHAT U2b DOES NOT DO

- **U2s is not started.** `posts_insert_owner` has **no `is_public` guard**
  (`U2b-15`, `P4U1-15` = 0). **U2b MAKES NO OLD-CLIENT OR BACKEND DURABILITY
  CLAIM** — a pre-U2b build can still create a private post row.
- **U2c is not started** — the direct attachment-path assertion (§4.1) is its
  job.
- **U3 has not begun.** The purge is still predicted to be a recorded no-op.
- **C-31 untouched.**

## 10. CARRIED FORWARD

**The copy constraint (U8).** No UI state may assert *completed* removal while an
`.unshare` is pending. Now that the real UI can reach the path, this is live: a
Share-OFF save returns immediately while convergence may still be queued.
