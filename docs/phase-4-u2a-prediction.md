# P4-U2a / C-60 — PREDICTION, COMMITTED BEFORE THE EDIT

**Written 2026-09-04 at `f12330e` (the U1 baseline), BEFORE any source change.**
Scored against `docs/phase-4-u1-baseline.md`. Anything that does not match is a
stop-and-report, not a repair-forward.

**U2a's whole job is REACHABILITY.** It makes the existing, already-correct
delete path reachable in `.backendConnected`. **It does not change what deletion
does**, and it does not touch either `shouldPublish` literal.

**Out of scope and explicitly not implemented here:** U2b (the `shouldPublish`
call sites), U2c (attachment gate assertion), U2s (the server guard). **No
server-side `UPDATE` restriction on `is_public` is added — ever, by §2a.**

---

## 0. WHAT THE DEFECT ACTUALLY IS — NARROWED BY READING, BEFORE FIXING

**`BackendEnvironment.publish` ALREADY routes `.backendConnected` to the real
HTTP service.** `BackendShim.swift:2144`:

```swift
if (mode == .backendPreview || mode == .backendConnected) && hasHTTPConfig {
    return HTTPBackendPublishService()
}
```

The same two-mode pattern appears at `:2155` (follow), `:2164` (shares) and
`SessionSyncQueue.swift:174` (flush). **`PublishService` is the only place in the
codebase that names `.backendPreview` alone on a behavioural gate.**

**So C-60 is not a missing implementation and not a routing defect. It is two
predicates that were never widened when `.backendConnected` was introduced** —
`PublishService.swift:197` and `:292`. That narrows the fix to those two lines
and is why U2a is a reachability unit.

---

## 1. STRUCTURAL ASSERTIONS THAT WILL FLIP — EXACTLY TWO

| id | asserts | now | **predicted after U2a** |
|---|---|---|---|
| **P4U1-5** | `mode == .backendPreview) && hasBaseURL` in `PublishService` | 2 | **0** |
| **P4U1-6** | `.backendConnected` in `PublishService` | 0 | **2** |

**P4U1-5 goes to 0 rather than staying 2**, because the regex pins the closing
parenthesis immediately after `.backendPreview`; widening the predicate to
`(mode == .backendPreview || mode == .backendConnected)` breaks that match at
both sites. **Predicting "2 → 0" rather than "2 → 2" is the point of writing it
down** — a wrong prediction here would be indistinguishable from a wrong edit.

**P4U1-6 goes to exactly 2, not 3.** `PublishService.swift:207` and `:302` also
name `.backendPreview`, but they gate **an NSLog only** and are deliberately not
touched. If P4U1-6 reads 3, the edit went further than intended.

## 2. ASSERTIONS THAT MUST NOT MOVE

| id | value that must hold |
|---|---|
| **P4U1-1, P4U1-2** | **1, 1** — both `shouldPublish: true` literals untouched |
| **P4U1-3, P4U1-4** | **0, 0** — no `isPublic`/`visibility` gating yet |
| **P4U1-7** | 1 — `SessionSyncQueue` flush unchanged |
| **P4U1-8, P4U1-9, P4U1-10** | 2, 2, 1 — `BackendShim` untouched |
| **P4U1-11, P4U1-12, P4U1-13** | **2, 0, 1** — Phase 3 exit assertion |
| **P4U1-14, P4U1-15, P4U1-16** | 4, **0**, 1 — server untouched; **P4U1-15 stays 0 because U2s is NOT in this unit** |

Also unchanged: Debug and Release build clean; `MOTIVOTests` **15/15**;
`u5/client-structural.sh` **60/60** (it pins C57-1..7, and U2a must not disturb
the 401-only auth challenge).

## 3. `PublishService` WHEN `shouldPublish == false` UNDER `.backendConnected`

Predicted sequence, both call paths (`publishIfNeeded(usingContext:…)` and
`publish(payload:objectID:shouldPublish:)`):

1. The object's URI is **removed** from `publishedURIs` and persisted — this
   happens **synchronously, before** any network work.
2. **No enqueue.** The `if shouldPublish` block is skipped entirely.
3. `SessionSyncQueue.shared.flushNow()` runs (unchanged).
4. **The widened gate now passes** — `mode == .backendConnected`, `hasBaseURL`,
   `configured` — and `BackendEnvironment.shared.publish.deletePost(id)` is
   called. **Before U2a this call did not happen at all in Connected mode.**
5. That resolves to `HTTPBackendPublishService.deletePost` via the *existing*
   `:2144` routing.
6. Success or failure is logged and **the result is not propagated to the
   caller** — both sites log only.

**`.backendPreview` continues to reach deletion exactly as before.** This is an
expansion of the legitimate delete mode, not a replacement — asserted by
P4U1-6 = 2 (both gates widened) and by the behavioural matrix in §5.

## 4. IF ATTACHMENT-OBJECT DELETION FAILS

**Fail-closed, and U2a does not weaken it.** `BackendShim.deletePost` (`:1389`):

1. fetch the post's attachment refs; a failure to fetch or decode → **return
   before deleting anything**;
2. delete each referenced storage object; **the first failure returns
   immediately** (`:1414-1419`);
3. **only then** delete the post row.

**Predicted: the storage object survives AND the post row survives.** No partial
state, no orphan created by the failure path.

### 4.1 A CONSEQUENCE U2a MAKES REACHABLE, PREDICTED RATHER THAN DISCOVERED

**The local registry is updated optimistically, before the network delete.** Step
1 of §3 persists the removal from `publishedURIs`; step 4 may then fail. So after
a failed delete the client believes the session is unpublished while the server
row survives.

**It does not self-heal**, because a later `shouldPublish: false` for the same
object computes `changed == false` (the URI is already absent) — though note the
delete is attempted regardless of `changed`, so a *repeat* invocation would
retry. The gap is that nothing invokes it again on its own.

**This is pre-existing behaviour that U2a exposes rather than introduces**, and
it is **not** in scope to fix here. It is predicted so that observing it is a
confirmation rather than a surprise, and it is flagged for U2b — which is the
unit that makes this path reachable from the real UI.

## 5. BEHAVIOURAL ACCEPTANCE — WHAT WILL BE PROVEN, AND WHERE

**The shipping UI cannot reach `shouldPublish == false`** (both callers still
hard-code `true`, by constraint). The branch is therefore exercised **directly**,
without touching the real call sites.

**Environment: the LOCAL Supabase stack** (`API_URL http://127.0.0.1:54321`),
not production. Evidence level is *verified against a faithful local
reproduction*, stated as such — production carries no test post and no test
object at any point.

| # | case | predicted |
|---|---|---|
| **A** | `.backendConnected`, post + attachment object exist, delete path exercised | **row deleted AND storage object deleted** |
| **B** | `.backendConnected`, storage object deletion made to fail | **object survives AND row survives** (fail-closed) |
| **C** | `.backendPreview`, same as A | **row + object deleted** — the pre-existing mode still works |
| **D** | `.localSimulation`, same as A | **gate does not fire** — no delete attempted |

Every created id is recorded before mutation and the environment is verified
restored afterwards. **No broad cleanup predicate is used** — deletion is by
explicit id, the B-22 rule.

## 6. PRODUCTION CENSUS — PREDICTED ZERO DELTA

**U2a changes no production state, and cannot.** The widened gate is only
reachable via `shouldPublish == false`, and both call sites still pass `true`.

| measure | U1 | predicted after U2a |
|---|---|---|
| `total_posts` / `public_posts` | 101 / 101 | **101 / 101** |
| `private_false` / `private_null` | 0 / 0 | **0 / 0** |
| `owners` | 9 | **9** |
| attachment objects / referenced / **unreferenced** | 15 / 11 / **4** | **15 / 11 / 4** |
| avatar objects | 3 | **3** |

**Any non-zero delta is a stop-and-report**, and would mean the branch is
reachable by a route this analysis has not found.

## 7. AN ADJACENT OBSERVATION, RECORDED AND NOT ACTED ON

**`SimulatedPublishService.deletePost` (`BackendShim.swift:308`) performs REAL
network deletion** — it is not simulated, unlike its own `uploadPost` (`:302`)
which returns success without a call. So in `.localSimulation` the *service* would
delete for real if it were ever invoked with a configured API token.

**U2a does not make this reachable and does not change it** — case D above
asserts the `PublishService` gate does not fire in `.localSimulation`, which is
what keeps it unreachable. Recorded because it is adjacent to the line being
changed and would mislead a future reader of this file. **Not filed as a defect
on the strength of a reading alone**; case D is the measurement.
