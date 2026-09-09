# P5-K / C-43 — DIRECTIONAL RELATIONSHIP DELETE: ACCEPTANCE

**COMPLETE 2026-09-09.** Scored against
`docs/phase-5-c43-directional-follow-delete-prediction.md`, committed at
`aeb50ba` **before** any product mutation. **Every prediction held.**

## 1. The pre-fix control reproduced ALL FOUR defects

Run against the **pre-fix** code on the local stack, with `removeFollower`
exercised the way `FollowStore` actually called it then (`follow.unfollow`):

| # | control | pre-fix result |
|---|---|---|
| P1 | A unfollows B, both directions exist | **B→A destroyed too** |
| — | A removes follower B | **A→B destroyed too** |
| — | A declines B's request | **A→B destroyed too** |
| — | zero-match unfollow | **reported SUCCESS having deleted nothing — AND destroyed B→A** |

**The fourth is worth stating plainly: the "detection" mechanism was itself
destructive.** Firing both deletes to find out whether anything matched meant
that even a no-op action removed the opposite relationship and then reported
success.

## 2. The match-detection replacement — verified, not assumed

Probed through PostgREST against the installed stack with a real `authenticated`
JWT **before** the prediction was written:

| request | result |
|---|---|
| match, `Prefer: return=minimal` | **204, empty body** — the blindness the old comment described |
| match, `Prefer: return=representation` | **200, `[{…deleted row…}]`** |
| zero match, `Prefer: return=representation` | **200, `[]`** |

So the affected-row count comes from the **body**, which
`NetworkManager.request` already returns. **No `NetworkManager` change was
needed.** `Prefer: count=exact` was deliberately rejected: it reports through the
`Content-Range` **header**, which this client's signature does not expose.

`headers(apiKey:)` sets `Prefer: return=minimal` globally — **that is why the
body was empty and why the double delete was reached for.** The new path
overrides `Prefer` for this one call only.

## 3. Post-fix acceptance — all pass

| # | assertion | result |
|---|---|---|
| P2 | A unfollows B → A→B gone, **B→A survives** | ✅ |
| P3 | A removes follower B → B→A gone, **A→B survives** | ✅ |
| P4 | A declines B's request → B→A gone, **A→B survives** | ✅ |
| P5 | zero-match → **`.failure(.notFound)`**, and **nothing deleted in either direction** | ✅ |
| P6 | full `MOTIVOTests` | **92 passed, 0 failed, TEST SUCCEEDED** |
| P7 | Debug / Release | **both BUILD SUCCEEDED** |
| P8 | warning kinds | **25 → 25, zero new, zero eliminated** |
| P9 | production state | **untouched** |

**Fixture integrity:** both directions must be seeded, which is impossible as
either party — `follows_insert_requester` requires
`follower_user_id = auth.uid()`. Setup and read-back therefore use the **local
service role**, so the assertions do not run through the same policy path they
are testing. The operations under test run as A with a real `authenticated` JWT.

## 4. The shape of the fix, and why it needed a third method

`FollowStore.removeFollower` called **`follow.unfollow(id)`** — **one shim
function served two opposite directions**, which *is* the defect. So the
protocol gained `removeFollower(_:)`, and the three product operations now map to
three directional deletes:

| operation | deletes |
|---|---|
| `unfollow(target)` | me → target |
| `removeFollower(follower)` | follower → me |
| `declineFollow(from:)` | requester → me |

`deleteRelationship(with:)` is **gone**, replaced by
`deleteFollowRow(follower:followed:)`.

## 5. No-match semantics — derived, not invented

All three callers already treat `.failure` as non-catastrophic, and two refresh
from the backend to restore true state, commented *"Fail closed"*. A zero-match
now returns **`FollowRelationshipError.notFound`** — which is exactly what the
original code's comment said it was trying to achieve. A 2xx whose body cannot be
parsed returns `.undeterminedResult` rather than being assumed to be a deletion.

**The three did not need different semantics**, because the direction confusion
that motivated the original worry is removed by the directional invariant itself.

## 6. Recorded, NOT fixed here

**`FollowStore.unfollow`'s failure branch logs but does not refresh**, unlike its
two siblings, which both refresh on failure and say so. That asymmetry
**pre-exists C-43**, and widening this unit into UI-refresh policy would have
been scope creep. **It becomes newly reachable in practice**, because a
zero-match now returns a failure where it previously returned success — so it is
worth a register row rather than silence.

**Not touched:** the follows schema, RLS policies, follow-request UI, **teen
inbound-follow policy — CLOSED by P5-G/Q2 and untouched** — age assurance,
production, ASC, physical devices.

## 7. One process note

The first edit **left an orphaned tail** of the old function in the file, because
the region was bounded by a regex rather than by its exact text. **The compiler
caught it immediately**; it was removed by matching the exact block, and the
final build is clean. Recorded because a partially-removed function that still
compiled would have been the dangerous version of that mistake.
