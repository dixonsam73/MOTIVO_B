# P4-U2a-2 — OFFLINE / RETRY DURABILITY. INVESTIGATION AND REVISED CRITERIA

**2026-09-04, at `771c2ca`. NO CODE CHANGED — investigation only.** U2a-2 is not
implemented; the `shouldPublish` literals remain `true`.

**Verdict: the concern is correct and is now MEASURED. Today's unshare has
genuine eventual-delivery semantics; U2b plus an immediate-only demote/delete
would DESTROY that property.** U2a-2 must therefore be a durable-intent change,
not a two-call sequence.

---

## 1. WHAT EXISTS TODAY — AND IT IS BETTER THAN ANYONE HAD WRITTEN DOWN

### 1.1 The queue is genuinely durable

`SessionSyncQueue` persists to **`Application Support/MOTIVO/SessionSyncQueue_v1.json`**,
written with `.atomic` on every `enqueue`/`dequeue` (`:253-256`), and read back in
`init` (`:87-88`). **It survives process termination.**

### 1.2 The flush trigger is real and needs no user action

`MOTIVOApp.swift:330` — `.onChange(of: scenePhase)` with `guard phase == .active`
— reaches `SessionSyncQueue.shared.flushNow()` at **`:379`**, behind
`canViewFeed`, `BackendEnvironment.isConnected`, `BackendConfig.isConfigured`,
`baseURL != nil` and `ensureValidSession`. **Cold launch and every foreground.**
The only other callers are `PublishService` itself and the debug
`SyncQueueSection`.

### 1.3 Failures stay queued

`flushNow` dequeues **only** on success (or on a string-matched 409 treated as
success). Its failure branch is explicit: *"failures remain queued; no
retries/timers added here."*

### 1.4 SO TODAY'S OFFLINE UNSHARE CONVERGES — PROVEN, NOT ASSUMED

`testTodaysOfflineUnshareIsQueuedAndConvergesOnReconnect` (**passes**):

1. shared post exists, `is_public = true`;
2. `baseURL` pointed at a dead port; unshare performed exactly as the shipping
   app does (`shouldPublish: true`, `isPublic: false`);
3. **the intent is in the queue AND in the file on disk** — the test asserts the
   JSON file contains the post id, which is what makes "survives termination"
   evidence rather than inference;
4. server still `is_public = true` while offline;
5. connectivity restored, **`flushNow()` only — the user does NOT edit the
   session again**;
6. **server converges to `is_public = false`** and the queue drains.

**That eventual-delivery property exists only because both call sites hard-code
`shouldPublish: true`.** It is accidental, undocumented, and about to be removed.

---

## 2. WHAT U2b WOULD DO — ALSO MEASURED

`testUnsharePathLeavesNoDurableIntentWhenOffline` (**passes**), run against
today's code because U2a already made the branch reachable:

1. shared post exists;
2. offline; `publish(..., shouldPublish: false)`;
3. **`SessionSyncQueue.shared.items` is EMPTY — no durable intent is created at
   all**;
4. reconnect and `flushNow()`;
5. **the row is still there and STILL PUBLIC.**

**The delete result is logged and discarded at both sites**, so nothing observes
the failure, and nothing retries it.

### 2.1 EVERY RETRY MECHANISM, ENUMERATED

| candidate | retries a failed unshare? |
|---|---|
| `SessionSyncQueue` + foreground/launch flush | **No** — nothing is enqueued on the `shouldPublish == false` path |
| `publishedURIs` registry | **No** — display-side only; its sole external reader is `ContentView:2008`, the Feed filter for NON-OWNED sessions |
| The delete gate itself | Retries **only** if something calls `publish(shouldPublish:false)` again — it consults neither `changed` nor the registry, but **nothing re-invokes it** |
| A subsequent save of the same session | **Yes — but only if the member happens to edit it again**, which is exactly what the requirement forbids relying on |
| App launch / foreground | **No** — reaches `flushNow`, which has no item for this post |
| Any timer, background task or reconciliation worker | **None exists** |

**Conclusion: after U2b, an unshare performed offline is lost, silently, with the
content left public.**

---

## 3. THE THREE FAILURE POINTS, UNDER AN IMMEDIATE-ONLY U2a-2

| | scenario | result | acceptable? |
|---|---|---|---|
| **A** | demotion cannot reach the server (offline) | row **public**, no intent recorded, nothing retries | **No** |
| **B** | demote ✓, delete ✗ | row **private** — safe *now*, but **settles there permanently**; Phase 4 forbids private as a settled state | **No** |
| **C** | some objects deleted, row delete ✗ | row **private**, storage partially cleaned, no convergence | **No** |

**Immediate-only fixes A's severity but not its durability, and leaves B and C as
permanent resting states.** The requirement is convergence, not merely a safer
failure colour.

### 3.1 A RETRY DETAIL THAT WILL BITE — IDEMPOTENCE OF THE OBJECT DELETE

`deleteStorageObject` treats **any non-2xx as failure** (`BackendShim`), and
`deletePost` re-reads the refs from the surviving row. So on a **case C** retry it
will attempt to delete objects it already deleted. **If the storage API answers
404 for an absent object, the retry fails forever on an already-successful
step** — a poison item that can never converge. **Retry requires treating
"already gone" as success.** This is a design requirement, not an implementation
detail.

---

## 4. RECOMMENDED MECHANISM — EXTEND THE QUEUE, DO NOT BUILD A SECOND ONE

**Give the existing persisted queue an operation kind.** No new subsystem, no new
file, no new trigger — it inherits durability, the foreground/launch flush, and
the failures-stay-queued rule already proven in §1.

- `PostPublishPayload` gains `op: PostOp = .publish` (`enum PostOp: String,
  Codable { case publish, unshare }`), **defaulted so existing queue files decode
  unchanged** — the loader already carries a legacy-format fallback.
- Unshare **enqueues an `.unshare` item** rather than only firing a one-shot
  delete.
- `flushNow` dispatches: `.publish` → `uploadPost` (untouched); `.unshare` →
  **demote, then delete**:
  1. PATCH `is_public = false`;
  2. `deletePost` (objects first, fail-closed, then the row);
  3. **dequeue only when the row is actually gone.**
- **Also attempt it immediately at unshare time**, best-effort. Online, the
  demotion lands within the same interaction and the exposure window is ~zero;
  offline, the durable intent carries it. The immediate attempt is an
  optimisation; **the queue is the guarantee.**

### 4.1 HOW THAT ANSWERS A, B AND C

| | after the change |
|---|---|
| **A** | intent persisted; row public only until the next foreground with connectivity; converges without the member acting |
| **B** | row private **and the item stays queued**, so private is a *transient reconciliation state on the way to deletion* — exactly what the Phase 4 rule requires |
| **C** | same, and the retry re-drives object deletion; requires §3.1's "already gone = success" |

### 4.2 MERGE SEMANTICS MUST BE STATED, NOT INHERITED

`enqueue` merges by `id`, and its current logic assumes **both items are
publishes** (`isPublic == false` wins, metadata beats a stub). **A `.publish` and
an `.unshare` for the same id must resolve by LAST INTENT WINS**, not by the
existing `isPublic` merge. Left implicit, a re-share after an unshare — or the
reverse — would resolve by a rule written for a different question.

---

## 5. LOCAL / VISIBLE STATE WHEN AN UNSHARE IS INITIATED OFFLINE

- **The local session flips to Share OFF immediately and stays that way.** The
  Journal and Feed already gate on the local `isPublic` (`ContentView:1998`), so
  the member's own view is correct at once. Local truth is not in question.
- **No new blocking UI, no spinner, no error dialog.** F10's settled principle:
  only propagation and unresolvable refusal earn a word, and the member cannot
  fix a network outage.
- **But no success state may assert completed removal.** Copy that says the post
  *was* removed from Connected must not appear while an `.unshare` item is
  pending; "will be removed"/"removing" is honest, silence is acceptable,
  **"removed" is not**. This is the brief's "must not permanently mask an
  unresolved public server row", and it is a copy constraint owned jointly with
  **U8**.
- **The existing pending-queue surface is the honest place to show it** rather
  than a new one.

---

## 6. TWO LIMITATIONS TO RECORD RATHER THAN SOLVE

**(i) A device restore loses pending intents.** The queue lives in
`Application Support/MOTIVO/`, which `BackupPolicy` **excludes wholesale** and
names as holding "the pending publish queue" — a deliberate Phase 2 decision.
So an unshare queued and then restored onto a new device is gone. **The
immediate best-effort demote of §4 is what keeps this from being severe:** online
it has already landed, so the worst survivor is a private row, not a public one.

**(ii) The queue has no cap, no backoff and no attempt counter.** A permanently
failing item is retried on every foreground forever. For an unshare that is the
*right* direction, but it is unbounded and invisible. **Recommend recording an
attempt count and surfacing a long-pending unshare** — the minimum that makes
"bounded reconciliation state" true rather than aspirational.

---

## 7. REVISED U2a-2 ACCEPTANCE CRITERIA

**Structural**

1. `PostPublishPayload` carries an operation kind, defaulted, and **existing
   persisted queue files decode without loss**.
2. Exactly one queue, one file, one flush trigger — **no parallel subsystem**.
3. `uploadPost` and the `.publish` path are byte-unchanged in behaviour.
4. Both `shouldPublish: true` literals still present — **U2a-2 precedes U2b**.
5. `posts_insert_owner` still has no `is_public` predicate (U2s not started).

**Behavioural — local stack**

6. Online unshare: demote + delete, row and objects gone, **item dequeued**.
7. **Offline unshare: intent persisted to the queue FILE**; row untouched or
   demoted; **item retained**.
8. **Reconnect + `flushNow()` alone converges to removal** — no further user
   action. (The direct analogue of §1.4, which must keep passing.)
9. **Case B**: demote ✓ / delete ✗ → row **private** *and* **item still
   queued**; a later flush completes the deletion.
10. **Case C**: partial object deletion then row-delete failure → later flush
    **converges**; an already-deleted object does **not** poison the retry.
11. Re-sharing a session with a pending `.unshare` resolves **last intent wins**.
12. `.backendPreview` and `.localSimulation` behaviour unchanged.

**Copy / state**

13. No UI state asserts completed removal while an `.unshare` is pending.

**Regression**

14. Debug + Release clean; `MOTIVOTests` all green; `u5/client-structural.sh`
    60/60; `p4/u2a-acceptance.sh` green; **`LocalFactoryReset.perform` still
    exactly two callers**; production census unchanged.

---

## 8. RECOMMENDED UNIT ORDERING

1. **U2a-2 — durable unshare intent** (this document). Ships alone; strictly
   improves today's behaviour in every branch; **safe with the literals still
   `true`**, because an `.unshare` item is only ever created by the
   `shouldPublish == false` path that nothing currently invokes. That makes it
   independently reviewable and independently revertible.
2. **U2b — flip the literals** onto a path that now converges.
3. **U2c**, then **U2s** (server INSERT guard), then **U3**.

**U2b must not claim old-client durability** — that is U2s, and P4U1-15 is still 0.

**Stopped before implementation, as instructed.**
