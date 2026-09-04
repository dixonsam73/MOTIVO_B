# P4-U2b IS BLOCKED — C-61. INVESTIGATION RECORD

**2026-09-04, at `9f1498e` (the accepted U2a checkpoint). No `shouldPublish`
literal has been changed. No U2b prediction has been committed**, because the
prerequisite below changes what U2b should predict.

**Conclusion: the newly reachable failure state IS a prerequisite. U2b must not
proceed as specified.**

---

## 1. WHAT WAS ASKED, AND THE ONE CORRECTION

The brief asked whether the `publishedURIs` ordering can leave the client
durably believing a post is unpublished while the server row survives.

**It can — and `publishedURIs` is NOT the load-bearing problem.** The registry is
close to inert for this scenario. Investigating it surfaced a **more serious
adjacent defect**, which is what C-61 records. The correction is stated because
adopting the original framing would have produced a fix in the wrong place.

---

## 2. `publishedURIs` — COMPLETE ORDERING AND OWNERSHIP

`PublishService.swift`. Both `shouldPublish == false` paths behave identically.

| step | what happens | when |
|---|---|---|
| 1 | `set.remove(uri)`; if it changed, **`persist(set)` then `publishedURIs = set`** | **synchronously, before any network work** (`:232-243`) |
| 2 | `Task { @MainActor in … }` — **entered unconditionally**, not gated on `changed` | `:245` |
| 3 | the `if shouldPublish` enqueue block is **skipped** | `:246` |
| 4 | `await SessionSyncQueue.shared.flushNow()` | `:301` |
| 5 | the U2a gate; on pass, `publish.deletePost(id)` | `:304` |
| 6 | success or failure is **logged and discarded** — neither call site propagates a result | `:306-312` |

**Persistence:** `UserDefaults`, key `publishedSessions_v1::<ownerKey>`
(`:344-346`). It survives relaunch.

### 2.1 OUTCOMES

- **Successful deletion** — registry already correct; row and every referenced
  storage object gone (`deletePost` deletes objects first, then the row).
- **Attachment-object deletion fails** — `deletePost` returns **before** the row
  DELETE (`BackendShim:1414-1419`). **Row survives. Object survives.** Registry
  already says unpublished.
- **Post-row deletion fails** — objects are already gone, row survives. Registry
  already says unpublished. **This is the one genuinely inconsistent state**, and
  it is pre-existing, unchanged by U2a, and not what blocks U2b.

### 2.2 CAN ANYTHING RECOVER?

**Retry: yes, but only if the user acts again.** The delete gate does **not**
consult `changed` or the registry, so *any* later
`publish(payload:objectID:shouldPublish:false)` for the same id retries the
deletion. Nothing re-invokes it automatically, and **the member is given no
signal that anything failed**, so they have no reason to repeat the action.

**Does the stale registry block recovery? No.** Its only external reader is
`ContentView.swift:2008`, inside the Feed (`.all`) filter, for local sessions
that are **not** the viewer's own — the `isMine` branch returns before reaching
it, and `s.isPublic == false` is already filtered one line earlier (`:1998`).
**The owner's own publish/unpublish path never reads it.**

**So the registry is a display-side cache for a legacy case, not an authority.**

### 2.3 WHY THE ORDERING EXISTS

`git log -L` on the block returns exactly one commit: **`c1563d8` "[Backend]
Step 8F — Call-site payload publishing (GREEN)"**, which introduced it as
**local bookkeeping** — written when nothing downstream could fail, because in
`.backendPreview` the delete was a simulation. **There is no deliberate design
reason for remove-before-delete.** It is simply the order it was written in.

---

## 3. C-61 — THE ACTUAL BLOCKER

**On the `shouldPublish == false` path nothing ever writes `is_public`.**
`patchPostMetadata` is the **only** writer of that column, and it has exactly one
caller — `BackendShim.swift:926`, inside `uploadPost` — which runs only for
enqueued payloads, and enqueue happens only when `shouldPublish == true`.

**Therefore a failed unshare leaves the row `is_public = true`: publicly visible
to approved followers, while the member believes they withdrew it.**

### 3.1 MEASURED, NOT ARGUED

Local stack, `MOTIVOTests/PublishServiceConnectedDeleteTests.swift`:

| test | result |
|---|---|
| `testFailedUnshareLeavesRowStillPublic_C61` | **row survives AND `is_public` is still `true`** |
| `testTodaysUnshareDemotesRowToPrivate` | **today the same action PATCHes the row to `is_public = false`** |

**The second is what makes this a REGRESSION rather than a gap:**

| | server row after an unshare | visible to followers? |
|---|---|---|
| **Today** (`shouldPublish: true` hard-coded) | survives, **demoted to private** | **No** — residue only |
| **U2b, delete succeeds** | **gone** | No — the goal |
| **U2b, delete fails** | survives, **still public** | **YES — exposure** |

### 3.2 THIS IS THE SHAPE §2a ALREADY REJECTED

The scope record refused a server-side `UPDATE` guard on exactly this reasoning:
*an old-client unshare must not be allowed to fail while leaving previously
shared content publicly visible.* **U2b as specified would introduce client-side
the very outcome that argument rejected server-side.** Consistency requires
treating it the same way.

### 3.3 HOW LIKELY IS THE FAILURE?

**Ordinary.** `deletePost` fails if the refs fetch fails, if any storage object
delete fails, or if the row delete fails — i.e. **on any network interruption**.
An unshare performed offline fails, silently, and the post stays public until the
member happens to repeat the action.

### 3.4 A HARNESS CORRECTION WORTH KEEPING

The "today" comparison **failed on its first run and the failure was mine**:
`uploadPost` gates on `AuthManager.canonicalBackendUserID()` and returns
*"Missing owner user id"* before touching the network, so the test never
exercised the path it claimed to. Had it been accepted, this document would have
recorded "today also leaves it public" — the opposite conclusion, from a test
that never ran the code. Fixed by seeding `supabaseUserID_v1` in `setUp`.

---

## 4. THE SMALLEST CORRECT REPAIR — **DEMOTE, THEN DELETE**

On the unshare path, **PATCH `is_public = false` first, then attempt deletion.**

| outcome | result |
|---|---|
| demote ✓, delete ✓ | row gone — the U2b goal |
| demote ✓, delete ✗ | **row survives but PRIVATE — no worse than today** |
| demote ✗ | nothing changed; identical to today's failure mode |

**Why this and not the alternatives.** Retry-with-backoff needs durable retry
state the client does not have. Surfacing an error to the user contradicts F10's
settled principle that the member is not asked to fix what they cannot. Fixing
the `publishedURIs` ordering addresses a registry that **nothing authoritative
reads** and would leave the exposure untouched — the fix in the wrong place.

**It is a strict improvement on today in every branch**, which is the property
that makes it safe to ship ahead of U2s.

---

## 5. RECOMMENDED UNIT ORDERING — FOR REVIEW

**U2a-2 (new, small): demote-then-delete on the unshare path.** Then U2b flips
the literals onto a path whose failure mode is already no worse than today.

**U2b must not claim old-client durability either way** — `posts_insert_owner`
still has no `is_public` predicate (P4U1-15 = 0); that is U2s.

**Stopped here for review, as instructed.** No `shouldPublish` literal changed;
no U2b prediction committed, because the prerequisite changes what it should say.

---

## 6. DISPOSITIONED IN PASSING — THE FOUR DELETE LOGS

**Naming alignment, not a behavioural finding, and done.** The four logs said
`"Preview deletePost …"` on a branch U2a made shared between `.backendPreview`
and `.backendConnected`, so a **Connected** failure would have been recorded
under the wrong mode — the misleading-record class this project keeps meeting.
They now read `deletePost success • mode=…` / `deletePost FAILED • mode=…` and
report the mode they actually ran in. Pinned by `U2a-6b` (0 misnamed) and
`U2a-6c` (4 mode-accurate).

**No behaviour changed**; `u2a-acceptance.sh` is **18/18**.
