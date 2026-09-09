# P5-K / C-43 — DIRECTIONAL RELATIONSHIP DELETE: PREDICTION

**Committed BEFORE any product mutation, 2026-09-09.**

## 1. The defect, source-verified

`BackendShim.deleteRelationship(with:)` (`:800`) issues **two unconditional
DELETEs** — `me→other` then `other→me` (`:812-816`) — and reports success if
either returned success. All three product operations route into it:
`declineFollow` (`:791`), `unfollow` (`:796`), and `FollowStore.removeFollower`,
which calls **`follow.unfollow(id)`** (`FollowStore:287`).

**So one directional action destroys an independently existing relationship in
the opposite direction**, which its owner never asked to remove.

**The double delete is not sloppiness.** The comment at `:808-811` states the
reason: PostgREST returns 204 even when zero rows matched, so a single delete
"can look like a success while deleting nothing". **The naïve fix — delete the
second call — would trade a destructive defect for a silent-success defect.**

## 2. THE REQUIRED INVARIANT

| operation | deletes | must survive |
|---|---|---|
| A unfollows B | **A → B only** | B → A |
| A removes follower B | **B → A only** | A → B |
| A declines B's request | **B → A only** | A → B |

**An opposite-direction follow or request is separate user state and survives
unless its own owner performs the corresponding action.**

## 3. THE MATCH-DETECTION MECHANISM — VERIFIED, NOT ASSUMED

Probed against the **installed local stack** on 2026-09-09, through PostgREST,
with a real `authenticated` JWT:

| request | result |
|---|---|
| DELETE, match, `Prefer: return=minimal` | **204, empty body** — the current blindness, exactly as the comment says |
| DELETE, match, `Prefer: return=representation` | **200, `[{…the deleted row…}]`** |
| DELETE, zero match, `Prefer: return=representation` | **200, `[]`** |

**So the affected-row count is recoverable from the RESPONSE BODY**, which
`NetworkManager.request` already returns (`Result<Data, Error>`). **No
`NetworkManager` change is needed**, and `Prefer: count=exact` is deliberately
NOT used: it reports through the `Content-Range` **header**, which this client's
signature does not expose.

`headers(apiKey:)` (`:616`) sets `Prefer: return=minimal` globally — **that is
why the body was empty and why the double delete was reached for.** The fix
overrides `Prefer` for this one call.

## 4. NO-MATCH SEMANTICS — DERIVED FROM THE CALLERS

**Existing convention, read from `FollowStore`:** all three callers treat
`.failure` as non-catastrophic — they log and, for `declineFollow` (`:259`) and
`removeFollower` (`:293`), **refresh from the backend to restore true state**,
commented *"Fail closed"*.

**Adopted: a zero-match returns `.failure` with a distinct
`FollowRelationshipError.notFound`, for all three operations.** This is
**derived, not invented**: it is precisely what the existing code was *trying* to
achieve, stated in its own comment. The three do **not** need different
semantics, because the direction confusion that motivated the original worry is
removed by §2 — each call now deletes exactly the row it means.

**OBSERVATION, NOT FIXED HERE:** `FollowStore.unfollow`'s failure branch
(`:318-320`) logs but does **not** refresh, unlike its two siblings. That
asymmetry pre-exists this unit. **It is recorded for the register rather than
changed**, because widening the unit to UI-refresh policy is not C-43.

## 5. PREDICTED DIFF

| file | change |
|---|---|
| `BackendShim.swift` | protocol gains `removeFollower(_:)`; `deleteRelationship(with:)` replaced by a directional `deleteFollowRow(follower:followed:)` that sends `Prefer: return=representation` and counts the returned rows; three call sites made directional; a `FollowRelationshipError` |
| `BackendShim.swift` (preview/local-sim impl) | `removeFollower` added alongside the existing stubs |
| `FollowStore.swift` | `removeFollower` calls `follow.removeFollower(_:)` instead of `follow.unfollow(_:)` |
| `MOTIVOTests/…` | new behavioural suite |

**A third protocol method is required and is not scope creep:** one function
serving two opposite directions **is** the defect.

**NOT touched:** follows schema, RLS policies, follow-request UI, teen inbound
policy (**closed by P5-G/Q2 and untouched**), age assurance, production, ASC.

## 6. PREDICTIONS

| # | prediction |
|---|---|
| P1 | **Pre-fix control:** A→B and B→A both exist; A unfollows B; **BOTH rows are deleted** |
| P2 | Post-fix, A unfollows B → **A→B gone, B→A survives** |
| P3 | Post-fix, A removes follower B → **B→A gone, A→B survives** |
| P4 | Post-fix, A declines B's `requested` row → **B→A gone, A→B survives** |
| P5 | Post-fix, an operation whose row does not exist returns **`.failure(.notFound)`**, and **deletes nothing in either direction** |
| P6 | full `MOTIVOTests` passes |
| P7 | Debug and Release build clean |
| P8 | **zero** new warning kinds against a captured baseline |
| P9 | **zero** production state change |

## 7. FIXTURE VALIDITY

P4 needs B→A `requested` **and** A→B independently existing. `follows_pk` is
`(follower_user_id, followed_user_id)`, so the two directions are separate rows
and this is representable. **`follows_no_self` forbids self-follows only.** If any
fixture proves impossible under schema or RLS, **that will be established from the
constraint and reported — not manufactured.**

## 8. STOP CONDITION

**If the pre-fix control does not reproduce the opposite-direction deletion, or
if the representation mechanism proves unreliable under the real client path,
STOP and report** rather than trading C-43 for a silent-success defect.
