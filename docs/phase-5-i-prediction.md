# P5-I / C-34 — PREDICTION, COMMITTED BEFORE MUTATION. 2026-09-11

**At `6244bb0`.** Account-holder decisions the same day: **R1 → A** (expiry on
`DirectoryAccountCache`), **R2 → B1** (the backend avatar and its version are
authoritative for the Connected profile **when this device has no unsynced local
avatar change**), **R3 → C** (the image-cache TTL proposal is closed as
superseded), and the **`avatar_version` UPDATE grant is filed separately (B-38),
not fixed**. **The carried C-34 Production-fixture device acceptance stays
OUTSTANDING; nothing here clears it.** C-73 is next after P5-I, before C-3.

---

## 1. Measured state at HEAD

- **No avatar-logic commit since Phase 4's client half.** `git log -S` for
  `RemoteAvatar` and `avatarVersion` after 2026-09-05 is empty.
- **The image cache is already correct at the five directory sites** — the
  version registry drops the entry when `avatar_version` changes, and NULL → a
  stamped version counts as a change.
- **R1:** `DirectoryAccountCache` holds rows for the process lifetime with no
  expiry. The only `forceRefresh: true` caller (`BackendShim:1926`) refreshes
  **feed authors only**. Every other site reuses the cached row, so a new
  `avatar_version` reaches it only on relaunch.
- **R2:** `ProfileView.refreshAvatarDisplay` returns on any local file
  (`:1220`); its trigger is keyed on the constant key (`:1195`);
  `fetchSelfRow` does not select `avatar_version`. So an owner's second device
  stays stale **across relaunch**.
- **`authenticated` holds SELECT on `account_directory.avatar_version`** — so R2
  needs no server change.

## 2. Premise checks

**Comparable TTL — found, and adopted for consistency.** `CommentPresenceStore`
is a viewer-local, in-memory cache of server state with a per-entry `fetchedAt`
and `ttlSeconds = 20 * 60`, justified in its own words as *"short to avoid stale
state; long enough to avoid spamming requests"* — the same trade-off. **R1 uses
20 minutes, not a second convention of 10.** The 300 s signed-URL TTLs are not
comparable: they follow the URL's own expiry.

**"Unsynced local avatar change" — reliable with EXISTING state.** One
device-level key (`profile.__local_etudes_profile__.avatarSyncState_v1`) is set to
`upload`/`delete` whenever the **local-scope** avatar is saved or deleted, and the
Connected edit path always writes that scope (`onSave` →
`mirrorCurrentAvatarIntoLocalScope` → `saveAvatarDerived(…, for: nil)`; delete →
`deleteAvatar(for: nil)`). It is cleared **only** after upload **and** directory
patch both succeed (`ProfileView:1629`, `AuthManager:456`, `:493`); every early
return and failure leaves it set. **No new pending-state architecture.** The one
new persisted value is a **last-applied backend version** per identity — a
record of what this device last took from the backend, not a pending flag.

## 3. Design

**R1 — `AccountDirectoryService`.** Each cached row carries `fetchedAt`;
`static let directoryCacheTTL = 20 * 60`. `idsNeedingFetch(requested:fetchedAt:now:ttl:forceRefresh:)`
— pure, tested — returns absent **and expired** ids. **If a refresh fails but
every requested id has a cached row, the cached rows are served** rather than a
failure: expiry must not blank names that are showing today. No polling; rows
refresh when next asked for.

**R2 / B1.** `SelfDirectoryRow` decodes `avatar_version`, selected by
`fetchSelfRow`. After self-row hydration, `OwnAvatarSync.decide` (pure, tested):

| Pending local change | Last applied | Backend avatar | Action |
|---|---|---|---|
| yes | any | any | **nothing** — never overwrite an unsynced edit; not recorded, so it is re-evaluated after the sync |
| no | none (first sight) | present | **refresh** |
| no | none (first sight) | absent | **record only — never delete on first sight** |
| no | equal | any | nothing |
| no | different | present | **refresh** |
| no | different | absent | **remove the local copy** |

**The first-sight rule is deliberate.** On first sight an absent backend avatar
cannot be told apart from one that was never uploaded, so removal happens only
when the version **changes** after one was already applied. **Removal IS
included** — under B1's rule an avatar removed on another device is the backend's
authoritative state — and it uses a delete that does **not** set the pending flag,
so it cannot loop back into a sync.

Refresh drops the image and signed-URL caches for the key first (the registry
would treat a first sight as no change and could hand back a stale cached image),
fetches, **re-checks the pending flag after the fetch**, then replaces the
connected-scope and local-scope copies through **one `ProfileStore` function**
that `ProfileView`'s existing seed also routes through. `AuthManager` publishes an
`ownAvatarRevision`, and `ProfileView`'s trigger includes it, so the Profile
redraws.

**Scope:** the avatar/profile copy only. Journal data's local-first treatment is
untouched.

**R3 — closed as superseded.** No time-based expiry on the image cache.

## 4. PREDICTION

**Z1 — pre-change, `AvatarFreshnessTests` source guards all FAIL:**
`testDirectoryCacheExpires`, `testSelfRowReadsAvatarVersion` (scoped to
`SelfDirectoryRow` and `fetchSelfRow` — `DirectoryAccount` already decodes the
field, so a file-wide check would be vacuous), `testHydrationSyncsOwnAvatarFromBackend`,
`testProfileAvatarRedrawsWhenOwnAvatarIsReplaced`.

**Z2 — after:** all pass, plus behavioural `testExpiredDirectoryRowsAreRefetched`
and `testOwnAvatarSyncDecisionTable`.

**Z3 — warnings unchanged: Debug 177 / Release 165.**

**Z4 — census 238 / 238** (232 + 4 + 2).

**Z5 — no device acceptance is possible now.** Every observation that would
settle R1 or B1 needs an avatar **replacement**, and `storage.avatars` INSERT is
gated on Production entitlement. **The carried C-34 check — member X replaces,
member Y sees it without relaunch — and a B1 check — the same identity on two
devices — both stay carried to the Production Connected fixture.** Phase 4's
exit state is unchanged by P5-I.
