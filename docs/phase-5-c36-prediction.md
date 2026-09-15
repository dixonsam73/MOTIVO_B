# C-36 — prediction, before any edit (2026-09-15)

**Governing documents:** `claude-scope-009.md`, approved with evidence corrections by `codex-scope-review-009.md`.

## Mechanism under test (read-path only)

- **Two read sites:** `ProfileView` presents the location at `:1114` (`onAppearLoad`) and `:2057` (`onChange(of: auth.backendUserID)`), both via `ProfileStore.location(for: backendUserID)`.
- **The blank:** when the user-scoped key `profile.<uid>.location` has never been written, that read gives `""` even though the member's Solo value sits in `profile.__local_etudes_profile__.location`.
- **How the blank reaches the server:** `locationText` feeds the debounced directory sync, which sends `NULL` for a blank.

**Writers of a user-scoped location key:**
- `ProfileView.persistProfileEdits`;
- the sign-out copy for the old identity;
- `AuthManager`'s publish copy-forward;
- **`ProfileStore.hydrateMissingLocalIdentity`** (`ProfileStore:238-240`, from `AuthManager:740`) — added by the review, and consistent with the build-131 reinstall non-reproduction;
- factory-reset removal.

Wherever one of these has already written the key, that value is used.

## Fix

`ProfileStore.presentedLocation(for:)`:
- uses `profileStorageID` normalization;
- if the user-scoped key **exists**, returns exactly what `location(for:)` returns today, including an explicit `""`;
- **only if the key is absent**, returns the local Études location;
- persists nothing.

`ProfileView:1114` and `:2057` call it instead of `location(for:)`.

**Unchanged:** `location(for:)` and `setLocation`, `AuthManager`'s publish and copy-forward, `AccountDirectoryService` payload and clear semantics, sign-out (C-27), hydration, the server.

## Test — `MOTIVOTests/C36FirstJoinLocationTests.swift`, four cases

**Setup:**
- a fresh random user id per case;
- the raw local-scope key snapshotted in `setUp` and restored exactly in `tearDown`;
- per-case user keys removed.

The disposable hosted test process only.

| # | State | Before (shim = `location(for:)`) | After (shim = `presentedLocation(for:)`) |
|---|---|---|---|
| 1 | local "London", user key absent | **FAIL** (`""`) | PASS (`"London"`) |
| 2 | local "London", user "Paris" | PASS | PASS |
| 3 | local "London", user key explicitly `""` | PASS | PASS |
| 4 | both absent | PASS | PASS |

**Predicted:** 1 fail / 3 pass before, 4 / 4 after. Then one Release build. No full suite.

## Limits

- **What is proven:** the value presented for a missing scoped key, and nothing about network ordering.
- **Not shown:** that every first join loses the location.
- **Backend and device:** the backend row is not observed. Confirmation is **QA B7**, which needs a fresh first-join account and is Samuel's.

**If a valid run contradicts a prediction, stop and report it.**
