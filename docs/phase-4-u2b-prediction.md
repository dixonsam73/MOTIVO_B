# P4-U2b — PREDICTION, COMMITTED BEFORE THE EDIT

**Written 2026-09-04 at `145ddfd` (the accepted U2a-2 checkpoint), BEFORE any
source change.** Scored against U1 (`f12330e`), U2a (`9f1498e`) and U2a-2.

**U2b's purpose is now narrow:** expose the already-tested durable unshare path
to the shipping UI, and stop enqueueing or uploading private content.

---

## 1. DISPOSITION OF THE REDUNDANT IMMEDIATE DELETE — **REMOVE IT**

### What is actually there

On `shouldPublish == false` the sequence is, in order:

1. `SessionSyncQueue.shared.enqueue(… op: .unshare)` — the durable intent;
2. **`await SessionSyncQueue.shared.flushNow()`** (`:206`, `:342`) — which
   **synchronously attempts** `unsharePost`: demote, then delete, dequeue only on
   confirmed removal;
3. the C-60 gate — **`deletePost(id)`**, a *bare delete with no demotion*.

### Why removal is the smallest correct disposition

**The immediate best-effort attempt is step 2, not step 3.** `flushNow()` is
`await`ed, so by the time the gate is reached the persisted intent has *already*
been attempted through the authoritative primitive. **Deleting step 3 therefore
removes a duplicate, not the immediacy.**

**Routing step 3 through `unsharePost` instead would be strictly worse:** it
would perform the whole demote-then-delete a *second* time on every unshare —
re-PATCHing a row the queue may have just deleted — for no additional guarantee.

**And leaving it is the option the brief forbids: two different unshare
semantics in parallel.** Step 3 skips the demotion, so it is not merely a
duplicate but a *differently-shaped* one — the exact bare-delete behaviour whose
absence of demotion caused C-61.

**What is preserved after removal**

| property | preserved by |
|---|---|
| immediate best-effort | the awaited `flushNow()` at `:206` / `:342` |
| durability across offline, termination, launch, foreground | the persisted queue |
| demote-before-delete | `unsharePost`, the single primitive |
| `.backendPreview` still deletes | `flushNow` runs for preview and connected |
| Solo stays local | `flushNow` skips `.localSimulation` |

**C-60 is NOT reopened.** Its defect was that un-sharing reached no deletion at
all in `.backendConnected`. After removal the path is
enqueue → flush → `unsharePost` → demote → delete, which reaches deletion in
that mode through a strictly stronger primitive. **The C-60 regression tests
keep passing, now measuring the queue path** — predicted, and checked.

## 2. SOURCE CHANGES PREDICTED

| file | change |
|---|---|
| `AddEditSessionView.swift:2084` | `shouldPublish: true` → `shouldPublish: isPublic` |
| `PostRecordDetailsView.swift:1836` | `shouldPublish: true` → `shouldPublish: visibility` |
| `PublishService.swift` | **remove both C-60 gate blocks** (§1) |

Nothing else. No `BackendShim`, no `SessionSyncQueue`, no SQL, no policy, no
project file.

## 3. STRUCTURAL PREDICTIONS

| id | now | after U2b |
|---|---|---|
| **P4U1-1, P4U1-2** (`shouldPublish: true`) | 1, 1 | **0, 0** |
| **P4U1-3** (AESV `shouldPublish: isPublic`) | 0 | **1** |
| **P4U1-4** (PRDV `shouldPublish: visibility`) | 0 | **1** |
| **P4U1-5** | 0 | **0** — unchanged |
| **P4U1-6** (`.backendConnected` in `PublishService`) | 2 | **0** — the gates are gone |
| P4U1-7..10 | unchanged | **unchanged** |
| **P4U1-11/12/13** (`LocalFactoryReset`) | 2, 0, 1 | **unchanged — Phase 3 exit assertion** |
| **P4U1-14/15/16** (server policies) | 4, 0, 1 | **unchanged — U2s NOT started** |
| U2a2-1..15 | as accepted | **unchanged** |
| **U2a2-16/17** (`shouldPublish: true` = 1) | 1, 1 | **0, 0 — these SAY "U2b not started" and must flip** |
| **U2a2-18** (`shouldPublish: isPublic` = 0) | 0 | **1** |
| **U2a2-19/20/21/22** | unchanged | **unchanged** |

### 3.1 SUITE-PINNING POLICY, INTRODUCED HERE AND STATED PLAINLY

`u2a-acceptance.sh` asserts the C-60 **gate**, which U2b legitimately removes,
and `u2a2-acceptance.sh` asserts *"U2b not started"*, which U2b legitimately
falsifies. Left alone they would join `u1-baseline.sh` as a third and fourth
permanently-failing suite — **13 expected failures across four files, which is
precisely where a real regression hides.**

**Policy adopted: a unit's acceptance suite is evaluated against that unit's own
commit.** Unit-specific assertions in `u2a-acceptance.sh` and
`u2a2-acceptance.sh` are re-pointed at the pinned tree (`git show <sha>:<path>`),
so each remains a **true, permanently green historical record**. Standing
invariants that are not unit-specific — the server policy shape,
`LocalFactoryReset`'s two callers — stay **live**, because their value is
precisely that they can still fail.

**`u1-baseline.sh` is deliberately NOT pinned.** It is the phase's immutable
pre-change measurement and its two known flips are its own documented evidence.

## 4. BEHAVIOURAL PREDICTIONS

| # | case | predicted |
|---|---|---|
| 1 | **Connected, Share OFF, new session** | **no post row created**; nothing enqueued as `.publish` |
| 2 | **Connected, Thought** | **no post row created** (`isPublic` is false in thought mode) |
| 3 | **Share OFF with an attachment explicitly marked INCLUDED** | **no post row AND no Storage object** — `uploadPost` is never reached, so `loadIncludedAttachments` never runs |
| 4 | **Share ON** | unchanged — row created, included attachments uploaded, dequeued |
| 5 | **shared → Share OFF** | `.unshare` persisted, demote then delete, **row and objects gone**, dequeued |
| 6 | shared → OFF **offline**, then reconnect | **converges** on `flushNow` alone |
| 7 | delete fails | row **private**, intent **still queued** |
| 8 | publish→unshare / unshare→publish | **last intent wins**, both directions |
| 9 | `.backendPreview` | still deletes |
| 10 | `.localSimulation` | stays local |
| 11 | legacy queue file | still decodes as `.publish` |
| 12 | C-60 / C-61 regression cases | **still green**, now via the queue path |

## 5. WHAT U2b DOES NOT DO

- **No `posts_insert_owner` `is_public = true` guard** — `P4U1-15` stays **0**,
  `U2a2-21` stays **0**. **U2b MAKES NO OLD-CLIENT OR BACKEND DURABILITY
  CLAIM:** a pre-U2b build can still create a private post row, and only U2s
  changes that.
- **U2c is not started** — `loadIncludedAttachments` untouched. Attachment
  safety after U2b is a *consequence* of the publish gate, not a property of the
  attachment path; asserting it directly is U2c's job.
- **No retry cap, no backoff.** Unchanged from U2a-2.
- **C-31 untouched.**

## 6. PRODUCTION CENSUS — ZERO DELTA PREDICTED

**101 / 101 / 0 / 0, 9 owners; 15 attachment objects, 11 referenced, 4
unreferenced.**

### 6.1 DEVICE VERIFICATION — NOT PERFORMED. A PROCEDURE IS PROPOSED INSTEAD

**No existing beta-owned post can be toggled OFF and restored**, and the brief's
own condition therefore triggers a stop.

Read-only survey found candidates with **0 attachments, 0 comments, 0 shares**
(e.g. `179a9e67…`, 2026-07-10), so blast radius could be minimised — **but the
operation is still not reversible**:

- under U2b, Share OFF **deletes the row permanently**; there is no undo and no
  backup of Domain 3 content;
- "restoring" means re-sharing, and `uploadPost` writes **`created_at` = now**,
  so the post returns with a **fabricated date** and re-enters followers' feeds
  as new. The original record is not recoverable.

**Proposed smallest reversible procedure, for approval before anything is
created:** create a **fresh throwaway session** on Device A, share it, confirm
the row appears, then toggle Share OFF and confirm the row and its objects are
gone. The fixture is disposable by construction, its removal *is* the behaviour
under test, and **no pre-existing beta record is touched.** Its post id would be
recorded before the toggle and the census checked before and after.

**Not executed in this unit.**
