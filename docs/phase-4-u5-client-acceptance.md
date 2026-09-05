# P4-U5 — C-34 CLIENT HALF. COMPLETE 2026-09-05

**Prediction `14ebb66`, committed before any mutation. Server half `dfba1d8`,
unchanged and re-verified by identity below.**

The server stamps `avatar_version` whenever `avatar_key` is *targeted* by an
update. This unit makes the client **observe** that stamp and drop its caches.
Until now a member who replaced their avatar with a different image under the
**same key** stayed stale on every other member's device until the process died.

**Nothing server-side changed in this unit, and that is measured rather than
asserted** — see §5.

---

## 1. What ships

**One registry, one optional parameter, five render sites, three deletions.**

`RemoteAvatarVersionRegistry` is a file-scope actor in `NetworkManager.swift`
holding `[cacheKey: lastAppliedVersion]`. `fetchAvatarImageIfNeeded` gained
`version: String? = nil`; when the observed version differs from the last
applied one for that key, it invalidates the image and signed-URL caches
**before** the fetch, then records the new value.

**The cache-key format is deliberately untouched.** It stays `"avatars|<key>"`.

---

## 2. THE KEY FORMAT IS THE LOAD-BEARING DECISION, AND THE OBVIOUS DESIGN IS WRONG

Folding the version into the key — `"avatars|<key>|<version>"` — is the first
thing that comes to mind and it would have broken the owner silently.

`"avatars|<key>"` is constructed in **ten** places. **Three of them are
owner-side invalidation helpers with byte-identical bodies:**
`NetworkManager.invalidateAvatarCaches`, `ProfileView`'s
`invalidateRemoteAvatarCaches`, and `AuthManager`'s `invalidateAvatarCaches`.
Each computes `"avatars|\(trimmed)"` and drops that entry when the owner
changes their own avatar.

Under a versioned key all three would go on dropping `"avatars|<key>"` while
the directory pipeline served `"avatars|<key>|<version>"` — **an entry nothing
clears any more.** The owner's own explicit invalidation would have become a
no-op, and it would have failed in the direction that produces no error at all.

**So the version DROPS the existing entry rather than renaming it.** Owner-side
invalidation and directory-side invalidation act on the same string, which is
why acceptance point 3 is a real criterion and not bookkeeping.

---

## 3. A SECOND STALENESS PATH, NOT NAMED IN THE PREDICTION

**Found during implementation and reported before completion.** Three of the
five directory render sites opened their avatar task with:

```swift
if RemoteAvatarImageCache.get(cacheKey) != nil { return }
```

**That pre-check reads the cache before the pipeline can invalidate it.**
Invalidation lives inside `fetchAvatarImageIfNeeded`; a site that returns early
on a cache hit never calls it. A version bump would have been answered with the
stale image, and the whole unit would have been inert at three of five sites —
**while every unit test passed**, because the tests exercise the registry and
the pipeline, not the view.

Removed at `ContentViewRemotePostRowTwin`, `ProfilePeekView` and
`BackendSessionDetailView`. Nothing is lost: the pipeline already returns a
valid cached entry itself, so the pre-check only ever saved an actor hop.

**The four owner-side pre-checks are left alone** — they are not on a
version-bearing path.

---

## 4. THE EXACT SITES

**Five directory sites changed.** Each carries the version in **both** places,
and both are required: version in the fetch but not in `.task(id:)` means the
task identity never changes and the refetch never fires; version in
`.task(id:)` but not in the fetch means the task re-runs and the pipeline
serves the same stale entry. **Either alone is a silent no-op.**

| site | task identity | fetch |
|---|---|---|
| `ContentViewRemotePostRowTwin:579` | `directoryAvatarVersion ?? ""` | `version: directoryAvatarVersion` |
| `ProfilePeekView:547` | `directoryAvatarVersion ?? ""` | `version: directoryAvatarVersion` |
| `PeopleUserRow:150` | `overrideAvatarVersion ?? ""` | `version: overrideAvatarVersion` |
| `CommentsView:944` | `directoryAccount?.avatarVersion ?? ""` | `version: directoryAccount?.avatarVersion` |
| `BackendSessionDetailView:450` | `directoryAccount?.avatarVersion ?? ""` | `version: directoryAccount?.avatarVersion` |

The two expressions differ by **type**, not by style: `.task(id:)` needs a
`String` and coalesces; the parameter is `String?` and takes the optional
straight through.

**17 caller sites** were wired to pass the version down, across
`ConnectedAttachmentShareUI`, `ContentViewRemotePostRowTwin`,
`ContentViewRowSupport`, `ContentViewSessionRow`, `FollowersListView`,
`FollowingListView`, `PeopleView` and `SessionDetailView`.

**Four owner-side sites are deliberately UNCHANGED** — `ProfileView:1091`,
`ContentView:1614`, `PracticeTimerView:1877`, `ContentViewSessionRow:537`. All
four read `auth.backendAvatarKey`. **The owner already knows when their own
avatar changed**, and invalidates explicitly at the moment they change it; a
server round-trip version would be strictly later and strictly worse
information. `version:` is optional precisely so these four compile untouched.

---

## 5. EVIDENCE

### The seven acceptance points

| # | claim | evidence |
|---|---|---|
| 1 | same key + same version causes no refetch churn | `testSameKeySameVersionNeverInvalidatesTwice` |
| 2 | same key + newer version causes exactly one new fetch | `testNewerVersionInvalidatesExactlyOnce` |
| 3 | invalidation uses the existing key format, so owner-side invalidation stays compatible | `U5c-1`, `U5c-key-*`, `U5c-2` |
| 4 | all five directory sites carry version through task identity AND fetch | `U5c-task-*`, `U5c-fetch-*` (10 assertions) |
| 5 | no owner-side site unnecessarily changed | `U5c-3`, `U5c-owner-*` |
| 6 | NULL `avatar_version` is backward-compatible | `testNilVersionIsStableAndBackwardCompatible` |
| 7 | G10 and B-15 server behaviour untouched | u6b 64/0, plus the md5 identity below |

### Gates

| gate | result |
|---|---|
| Debug build | **BUILD SUCCEEDED** |
| Release build | **BUILD SUCCEEDED** |
| `MOTIVOTests` | **TEST SUCCEEDED**, 45 tests passed, 0 failures |
| `u5-client-acceptance.sh` | **30 passed, 0 failed** |
| `u6b/acceptance.sh` | **64 passed, 0 failed** |
| `u2a / u2a2 / u2b / u2c / u2s` | 16 / 22 / 16 / 20 / 12, **all 0 failed** |
| `u1-baseline.sh` | 10 passed, **6 failed — expected, see below** |

**`u1-baseline`'s six failures are the unit's own successes and were verified
as such rather than assumed.** They assert the pre-Phase-4 world:
`shouldPublish: true` hard-coded, no `isPublic` gate, unshare gating on
`.backendPreview`, and `posts_insert_owner` carrying no `is_public` predicate.
U2a, U2b and U2s each inverted one. **Run against its own commit `f12330e` in a
detached worktree it returns 16 of 16**, which is the suite-pinning policy
applied rather than described. **None of the six touches avatars**, so this
unit is not implicated in any of them.

### The structural suite is non-vacuous — the discriminator

Stashed the client edits and re-ran against pre-fix source:
**19 of 30 assertions FAILED.** The 11 that passed are the standing
"did-not-change" invariants — the key format, the four owner-side fetches, no
server delta — which **must** hold in both worlds and would be worthless if
they flipped.

The three pre-check assertions read `1` against pre-fix code and `0` now, so
§3's second staleness path is **measured**, not merely described.

### Point 7 is proven by identity, not by absence of edits

`U5c-10` shows no file under `supabase/{sql,schema,migrations,functions}`
changed since `dfba1d8`. That alone only proves I did not type anything. So
both deployed RPC definitions were read back from production read-only:

| RPC | production `md5(pg_get_functiondef)` | matches `functions.json` @ `dfba1d8` |
|---|---|---|
| `get_account_directory_by_user_ids` | `d0d1322e926fa0c9c385c6272395c207` | **yes** |
| `search_account_directory` | `077f73f28c5d5c477635c9878a35d790` | **yes** |

Both still return `avatar_version`; **neither carries a subject-side filter**,
so **G10 holds**. B-15's disposition is untouched.

---

## 6. WHAT THIS DOES NOT CLAIM

- **Not device-verified.** No build carrying this code has run on Device A or
  Device B. The behavioural evidence is unit-level and structural. **Two
  members and one avatar replacement are needed to observe it end to end**, and
  that fixture has not been built.
- **No TTL.** A directory record fetched once and held keeps its version for as
  long as the caller holds it. Deliberately Phase 5.
- **`SelfDirectoryRow` is unchanged** — the owner's own row does not decode
  `avatar_version`, because no owner-side path consumes it.
- **The registry is in-memory and unbounded**, in the same sense the caches it
  guards are. It resets with the process. `resetForFactoryReset()` exists and
  is called by nothing yet.

---

## 7. REMAINING PHASE 4 OBLIGATIONS

- **U2b Device A verification** — implementation-complete, device-pending.
  `docs/phase-4-u2b-device-handoff.md`.
- **U6 has not begun.**
- **C-51** — F3's stale-path publish verification, carried from Phase 2.
- **C-58** — follower attribution for a lapsed viewer.
- **B-37** — filed during U5, P3, deferred to Phase 6.
- **The five dangling `connected_attachments` references** — live rows pointing
  at missing objects, the inverse of B-8. Still undecided.
