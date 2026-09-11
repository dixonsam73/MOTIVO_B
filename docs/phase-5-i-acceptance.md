# P5-I / C-34 — IMPLEMENTATION COMPLETE. DEVICE VERIFICATION CARRIED — C-34 NOT CLOSED.

> **Nothing here clears the carried C-34 Production-fixture device check, and it
> must not be read as doing so.** Every observation that would settle C-34 needs
> an avatar **replacement**, and `storage.avatars` INSERT is gated on Production
> entitlement. Phase 4's exit state is unchanged.

Prediction and guards: `docs/phase-5-i-prediction.md`, committed at `cb8503a`
**before mutation**. B-38 filed there. No production, ASC, enforcement or
age-state mutation; no server change of any kind.

## 1. Result

| | Prediction | Outcome |
|---|---|---|
| **Z1** | four source guards FAIL pre-change | **MET** — structured *4 reported, 4 Failed*; the self-row guard failed on **both** scoped halves, so its scoping kept it from being vacuous |
| **Z2** | all pass, plus two behavioural tests | **MET** |
| **Z3** | Debug 177 / Release 165, set unchanged | **MET** — both, warning set identical |
| **Z4** | 238 / 238 | **MET** — **238 declared, 238 passed**, structured census |
| **Z5** | no device acceptance possible now | **Holds** |

## 2. What changed

- **R1 — directory rows expire after 20 minutes**, consistent with
  `CommentPresenceStore`'s comparable cache. `idsNeedingFetch` refetches absent
  **and expired** rows; **if a refresh fails but every requested row is cached,
  the cached rows are served**, so expiry cannot blank a name. No polling.
- **R2 / B1 — the owner's local avatar copy follows the backend when this device
  has no unsynced local avatar change.** `SelfDirectoryRow` decodes
  `avatar_version`; self-row hydration runs `syncOwnAvatarFromBackend`, carrying
  out the pure `OwnAvatarSync.decide`: refresh on a changed or first-seen present
  avatar; **remove only after a version change, never on first sight**; never act
  while the existing pending flag is set, and re-check it after the fetch. One
  `ProfileStore.seedAvatarFromConnected` now serves both the existing first-seed
  and the new replacement. Removal uses a delete that sets **no** pending marker.
  The Profile redraws through `ownAvatarRevision`.
- **R3 — image-cache TTL: closed as superseded** by version-based invalidation.
- **Scope held:** the avatar/profile copy only; Journal data untouched.

## 3. Carried, unchanged

- **C-34's Phase 4 device check** — member X replaces, member Y sees it at the
  feed row, People, comments, profile peek and session detail without relaunch
  (non-feed sites within the 20-minute expiry).
- **B1's device check** — the same identity on two devices: replace on one, and
  the other's Profile follows on its next hydration.

**Both need the legitimate Production Connected fixture.**
