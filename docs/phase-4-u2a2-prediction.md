# P4-U2a-2 / C-61 — PREDICTION, COMMITTED BEFORE THE EDIT

**Written 2026-09-04 at `1d8174b`, BEFORE any source change.** Scored against
the U1 baseline (`f12330e`), the U2a acceptance suite and
`docs/phase-4-u2a2-durability.md`. Anything that does not match is a
stop-and-report.

**Approved architecture:** persist unshare intent → immediate best-effort
demotion → deletion → **dequeue only after confirmed row removal**, with the
existing file-backed `SessionSyncQueue` supplying durable retry.

---

## 0. TWO MEASURED FACTS THAT CHANGE THE DESIGN

**Both were probed on the local stack before writing any code, because the
brief required verifying the storage semantics rather than assuming them. Both
contradict the obvious assumption.**

### 0.1 An already-absent object DELETE returns HTTP **400**, not 404

```
DELETE present object        -> 200  {"message":"Successfully deleted"}
DELETE already-absent object -> 400  {"statusCode":"404","error":"not_found","code":"NoSuchKey"}
DELETE never-existed object  -> 400  {"statusCode":"404", ... "NoSuchKey"}
```

**The 404 is in the BODY; the HTTP status is 400.** A reconciliation rule written
as "treat 404 as success" would never fire, and the retry would poison itself
exactly as §3.1 of the durability record predicted. The rule must match the
**body's** `NoSuchKey` / `statusCode:404`.

### 0.2 NoSuchKey is INDISTINGUISHABLE from RLS denial, wrong bucket and no auth

```
DELETE object under ANOTHER user's prefix -> 400 ... "NoSuchKey"
DELETE from a non-existent bucket         -> 400 ... "NoSuchKey"
DELETE with NO Authorization header       -> 400 ... "NoSuchKey"
```

**All four collapse to one response.** So requirement 8 ("already-absent is
success") **necessarily** also treats RLS-denial and missing auth as success.
That is a real consequence and it is accepted, for two reasons:

- **Demote-first is an authorisation probe.** The `PATCH is_public = false`
  precedes any destructive step; a broken session or a row we do not own fails
  *there*, and deletion is never attempted. By the time objects are being
  deleted, the client is known to be authorised for that row.
- **A post's object paths are constructed from the post's own owner**
  (`BackendShim.storageObjectPath(owner:…)`), and the deleting client is that
  owner, so a foreign-prefix reference does not arise naturally. If one ever did,
  the outcome is an orphaned object — a **B-8 class** housekeeping issue, not a
  privacy failure.

**CONSEQUENCE FOR AN EXISTING TEST, DECLARED IN ADVANCE.**
`testConnectedModeFailClosedWhenObjectCannotBeDeleted` demonstrates fail-closed
using a **foreign-prefix** object. Under the new rule that object now reads as
*already gone*, so the row **will** be deleted and **that test must be
re-expressed**. Its replacement asserts fail-closed against a **transport**
failure, which is the only genuinely distinguishable class. **This is a
deliberate, predicted change to a passing test, not a silent relaxation.**

### 0.3 Row deletion cascades

`post_comments` and `post_shares` both reference `posts` with **`ON DELETE
CASCADE`**, so no child row can block the row delete. There is therefore **no
constructible client-side "row delete fails" case** on the local stack; the
predictions below say so rather than inventing one.

---

## 1. SOURCE CHANGES PREDICTED

| file | change |
|---|---|
| `SessionSyncQueue.swift` | add `enum PostOp: String, Codable { case publish, unshare }`; add `op: PostOp` to `PostPublishPayload`, **defaulted to `.publish`** in both the memberwise init and `init(from:)` so existing files decode unchanged; make merge resolve **last intent wins**; dispatch in `flushNow` |
| `BackendShim.swift` | add an `unsharePost` operation to the publish service: demote → delete; treat body-`NoSuchKey` as success on object deletion |
| `PublishService.swift` | on `shouldPublish == false`, **enqueue** an `.unshare` item before/alongside the immediate best-effort attempt |

**Not touched:** `AddEditSessionView.swift`, `PostRecordDetailsView.swift` (both
`shouldPublish: true` literals stay), any SQL, any policy, any project file.

## 2. STRUCTURAL PREDICTIONS

| id | now | after U2a-2 |
|---|---|---|
| P4U1-1, P4U1-2 (`shouldPublish: true`) | 1, 1 | **1, 1 — UNCHANGED** |
| P4U1-3, P4U1-4 | 0, 0 | **0, 0 — UNCHANGED** |
| P4U1-11/12/13 (`LocalFactoryReset`) | 2, 0, 1 | **UNCHANGED** |
| P4U1-14/15/16 (server policies) | 4, 0, 1 | **UNCHANGED — U2s not started** |
| U2a-1..3, U2a-5..10, U2a-16 | as accepted | **UNCHANGED** |
| **U2a-4** (`publish\.deletePost` call sites) | 2 | **may change** — the unshare path routes through the new operation |
| **U2a-11** (`loadIncludedAttachments` = 2) | 2 | **2 — UNCHANGED**; U2c is not this unit |
| **U2a-12/13** (one Swift file changed since `f12330e`) | 1 | **3** — `PublishService`, `SessionSyncQueue`, `BackendShim` |
| **U2a-14** (no migration/function/schema) | 0 | **0 — UNCHANGED** |

## 3. BEHAVIOURAL PREDICTIONS — LOCAL STACK, EXPLICIT FIXTURE IDS

| # | case | predicted |
|---|---|---|
| **1** | ordinary `.publish` (Share ON) | **unchanged** — row created, attachments uploaded, item dequeued |
| **2** | online unshare | demote → delete → row **and** objects gone → **item dequeued** |
| **3** | **offline unshare** | **intent persisted to the queue FILE**; row untouched; **item retained** |
| **4** | **process reconstruction** | the on-disk JSON decodes through the real `PostPublishPayload` decoder to an **`.unshare`** item |
| **5** | reconnect + `flushNow()` alone | **converges: private, then absent** — no further user action |
| **6** | **A — demotion cannot reach the server** | item **retained**, row still public, no destructive step attempted |
| **7** | **B — demote succeeded, deletion does not complete** | row **private**, item **retained**, later flush **converges** |
| **8** | **C — one object already absent, one present** | **converges in a single pass**: absent → success, present → deleted, row deleted, item dequeued |
| **9** | already-absent object alone | **success, not poison** — item dequeued |
| **10** | **publish → unshare collision** | **last intent wins → `.unshare`** |
| **11** | **unshare → publish collision** | **last intent wins → `.publish`** |
| **12** | successful unshare | **dequeues** |
| **13** | failed unshare | **remains queued** |
| **14** | **backward compatibility** | a legacy queue JSON **without** `op` decodes, and every entry is **`.publish`** |
| **15** | `.backendPreview` | still reaches deletion |
| **16** | `.localSimulation` | remains local — gate does not fire |

**On case 7's construction, stated rather than glossed.** A true "demote 200,
object-delete non-NoSuchKey failure" cannot be produced from the client, because
§0.2 collapses every non-transport storage failure into success and a transport
failure would also have failed the demote. Case 7 is therefore constructed as
**row already private + intent queued + flush offline**, which reproduces the
*state* under assertion — private row, retained intent, later convergence — with
the demote as the proximate failure. **What it does not prove is stated in the
acceptance record.**

## 4. WHAT IS NOT IN THIS UNIT

- **No retry cap and no backoff.** Deliberate, per instruction: exhausting a
  finite count and silently abandoning an owed privacy operation is the wrong
  failure. **Terminology corrected accordingly** — a demoted row is a *pending
  reconciliation state*, not a "bounded" one; it is bounded by **convergence**,
  not by an attempt limit. Backoff/scheduling are recorded as future operational
  hardening, to be driven by measured need.
- **No change to Phase 2's backup exclusion** of `Application Support/MOTIVO/`.
  The restore limitation is recorded; the immediate best-effort demotion is what
  keeps the worst restore survivor **private rather than public**.
- **U2b, U2c, U2s are not started.** Both `shouldPublish: true` literals remain,
  so **U2a-2 is unreachable from the shipping UI**, which is what makes it
  independently reviewable and revertible.
- **No server-side `is_public` INSERT guard** — P4U1-15 stays 0.

## 5. PRODUCTION CENSUS — ZERO DELTA PREDICTED

| measure | U1 | predicted |
|---|---|---|
| `total_posts` / `public_posts` | 101 / 101 | **101 / 101** |
| `private_false` / `private_null` | 0 / 0 | **0 / 0** |
| owners | 9 | **9** |
| attachment objects / referenced / unreferenced | 15 / 11 / 4 | **15 / 11 / 4** |

**No production fixture is created at any point.** All behavioural work is on the
local stack with explicit fixture ids, removed by explicit id afterwards.
