# P4-U5 CLIENT HALF (C-34) — PREDICTION, COMMITTED BEFORE ANY EDIT

**2026-09-05 at `dfba1d8`. No client file edited yet.** Server half is live and
verified; **nothing consumes the signal**.

---

## 1. THE SPLIT, MEASURED

Nine `fetchAvatarImageIfNeeded` call sites, in two populations:

| | site | source |
|---|---|---|
| **DIRECTORY — 5, all change** | `ContentViewRemotePostRowTwin:577` | `directoryAvatarKey` |
| | `ProfilePeekView:544` | `directoryAvatarKey` |
| | `PeopleUserRow:151` | `overrideAvatarKey` |
| | `CommentsView:945` | `directoryAccount?.avatarKey` |
| | `BackendSessionDetailView:458` | `directoryAccount?.avatarKey` |
| **OWNER — 4, UNCHANGED** | `ProfileView:1091`, `ContentView:1614`, `PracticeTimerView:1877`, `ContentViewSessionRow:537` | all `auth.backendAvatarKey` |

**The four owner sites keep their existing explicit invalidation and are not
touched** — acceptance point 5.

## 2. ONE DESIGN DECISION THAT DEPARTS FROM LITERAL PER-VIEW PLUMBING, AND WHY

Passing a sibling `…AvatarVersion:` argument beside every `…AvatarKey:` would
mean **25 call-site edits across 8 files** (11 `directoryAvatarKey:`, 14
`overrideAvatarKey:`), of which 15 already pass a `DirectoryAccount` member.

**A missed site fails SILENTLY AS A STALE AVATAR — which is indistinguishable
from the defect itself.** There would be no compile error and no test failure
unless that exact render path were exercised. That is the wrong failure mode for
a 25-site mechanical edit.

**So the version is looked up, not threaded.** A small registry keyed on the
avatar key — which already encodes the subject, `users/<uid>/avatar.jpg` — is
populated wherever directory rows are decoded, and the five directory views read
it. **One lookup path; no site can be missed.**

**This still satisfies the approved design:** the cache-key format is preserved,
`DirectoryAccount` carries `avatarVersion`, both RPC paths decode it, only
directory consumers are affected, `.task(id:)` includes the version, `version:`
is optional on the fetch, and invalidation uses the existing key format.

## 3. PREDICTED CHANGES

| file | change |
|---|---|
| `AccountDirectoryService.swift` | `DirectoryAccount.avatarVersion: String?` + `case avatarVersion = "avatar_version"`; the memberwise construction at the avatar-PATCH cache patch carries it; registry populated in the two decode paths (`resolveAccounts`, `search`) |
| `NetworkManager.swift` | `RemoteAvatarVersionRegistry` (new, small); `fetchAvatarImageIfNeeded(avatarKey:version:expiresInSeconds:)` with **`version: String? = nil`** |
| the 5 directory views | `.task(id:)` includes the version; version passed to the fetch |
| **owner-side 4** | **untouched** |

**Invalidation uses the EXISTING format**, `"avatars|\(key)"`, for both
`RemoteAvatarImageCache` and `RemoteAvatarSignedURLCache` — so the eight places
that build that string, including the owner's two invalidation sites
(`ProfileView:1515`, `AuthManager:404`), stay compatible. **The format string is
not changed anywhere.**

## 4. THE DECISION FUNCTION, MADE TESTABLE

`RemoteAvatarVersionRegistry.shouldInvalidate(key:version:) -> Bool` records the
last version applied for a key and answers whether the caches must be dropped:

| call | returns |
|---|---|
| first sight of a key (any version, including nil) | **false** — nothing cached yet to invalidate |
| same key, **same** version, repeatedly | **false** — acceptance point 1, no churn |
| same key, **newer** version | **true, once**; immediately false again — acceptance point 2 |
| same key, version nil → nil | **false** — acceptance point 6, the current 17 rows |

**Pure and synchronous, so it is unit-testable with no network** — which suits a
target whose stated character is pure tests.

## 5. PREDICTED ACCEPTANCE

| # | claim | how |
|---|---|---|
| 1 | same key + same version → no refetch churn | unit test, repeated calls return false |
| 2 | same key + newer version → exactly one new fetch path | unit test, true then false |
| 3 | invalidation uses the existing key format | structural: `"avatars\|` unchanged in all 8 places; pipeline invalidates with the same string |
| 4 | all 5 directory sites carry version in **both** task identity and fetch | structural, per site |
| 5 | no owner-side site changed | structural: the 4 files' fetch calls unchanged |
| 6 | NULL version stays backward-compatible | unit test (nil → nil → false) + the 17 production rows are NULL |
| 7 | G10 and B-15 server behaviour untouched | no SQL in this unit; `u6b/acceptance.sh` 64/64 must hold |

**Gates:** Debug + Release; `MOTIVOTests`; `u6b/acceptance.sh`; `u5/client-structural.sh`;
`p4/u1..u2s`.

## 6. OUT OF SCOPE

**TTL is Phase 5.** No SQL, no production mutation. **U6 not begun.**
