# P4-U6 / C-51 — INVESTIGATION AND PREDICTION

**Committed BEFORE the test is written and before anything is mutated.**
Accepted client checkpoint `7744027`; server checkpoint `dfba1d8`.

C-51 is **coverage, not a behavioural defect** by its own register cell. The
implementation exposure was closed by Phase 2 U2; what is outstanding is
**runtime verification by fault injection** of the one surviving route.

---

## 1. THE ROUTE, MEASURED RATHER THAN RESTATED

**The exposure needs all four of these at once, and I confirmed each in source.**

| # | claim | measured |
|---|---|---|
| 1 | the queue survives a process death | `SessionSyncQueue_v1.json` under `Application Support/MOTIVO/` (`SessionSyncQueue.swift:394-400`) |
| 2 | the queued payload carries **no** paths | `PostPublishPayload` (`:48-65`) holds `sessionID`, never a file path |
| 3 | so the flush re-reads Core Data | `loadIncludedAttachments(for sessionID:)` fetches Session and reads `fileURL` (`BackendShim.swift:1143`) |
| 4 | an unresolved path is **silently skipped** | `guard let url = … else { continue }` and `if !fileExists { continue }` (`:1161`, `:1164`) — no error, no throw, publish proceeds |

**2 is what makes the route real.** Had the payload captured resolved URLs at
enqueue time, rotation could not reach the flush at all.

**4 is what makes it dangerous rather than noisy.** The post publishes and
arrives with its media missing, and nothing anywhere reports it.

**Backup/restore cannot produce this**, because the queue file lives in the
excluded directory and does not restore — P5 working as designed. **Container
rotation on an ordinary app update is the only producer**, and that is
established fact (Device A, 2026-08-15).

---

## 2. TWO CANDIDATE RESIDUAL DEFECTS, BOTH FALSIFIED BY READING

I looked for a *second* stale-path consumer on the same route, because the
resolver being correct does not make the function correct.

- **`AttachmentPrivacy.isPrivate(id:url:)` at `BackendShim.swift:1166`.** It
  takes a URL, and `isPrivate` fails **closed** (`map[key] ?? true`), so a key
  miss would mark an included attachment private and skip it — the identical
  silent-skip symptom from a different cause. **Falsified:** `privacyKey`
  (`AttachmentPrivacy.swift:39-43`) returns `"id://<uuid>"` whenever an id is
  present and only falls back to `url.absoluteString` when it is nil, and
  `loadIncludedAttachments` has already `guard let id`-ed. The key is
  **container-independent on this route**.
- **A nil-id call site somewhere else could still key on the URL.** **Falsified:**
  all 21 call sites pass an id, and the publish route's is non-optional by guard.

**Neither is a defect. Recorded because the reasoning is what the next person
implements from, and "the resolver is fine" would not have covered either.**

---

## 3. WHAT U2 DID AND DID NOT DO

**P4-U2b shrinks the surface without closing it:** a private session no longer
enqueues at all, so only a **shared** publish can carry a stale path into a
queued flush. **That is an interaction, not a resolution** — the scope record
says so explicitly and I am not claiming otherwise.

---

## 4. PREDICTION

**I predict U6 requires NO production code change, and that the measurement
will show the attachment surviving the rotation.**

Stated so it can be falsified:

| # | prediction |
|---|---|
| **P1** | With a **correct** path, a queued shared publish flushes and uploads **1** Storage object under the post prefix. *(positive control — without it a 0 proves nothing)* |
| **P2** | With a **stale container path** and the file present in the current `Documents/`, the flush uploads **1** object. **This is C-51's exact condition.** |
| **P3** | With a stale path and the file **absent everywhere**, the flush uploads **0** objects and the post row still exists — the silent-skip is real and the assertion can see it |
| **P4** | The pre-U2 resolver semantics, replicated in the test, return a path that **does not exist** for the same stale input, while `AttachmentPathResolver.resolve` returns one that **does** |
| **P5** | The `.publish` intent survives **decode from the real queue file**, so the route is exercised through disk and not merely in memory |
| **P6** | No production file changes; standing suites and both builds stay green |

**P3 and P4 are the discriminators, and they are why P2 is evidence.** P2 alone
could pass on a harness that uploads regardless; P3 shows the same assertion
returns 0 when resolution genuinely fails, and P4 shows the pre-fix code would
have produced exactly that.

**If P2 fails, C-51 is a live defect rather than a coverage gap**, and the
smallest fix is the one the measurement names — not a redesign of attachment
identity, which is M13/M14 and explicitly out of scope.

---

## 5. THE FAULT TO BE INJECTED

Rewrite the persisted `Attachment.fileURL` to a path whose **container UUID is
replaced** while the filename and the `Documents/` parent are preserved, and
leave the real bytes where they are. That is precisely what an in-place app
update does, and it is injected **between enqueue and flush** so the queue is
carrying the intent across the rotation.

**Not simulated by deleting the file** — that is P3, a different assertion.
