# Études — Audit Finding Register

From a four-phase client audit and a Supabase backend audit at commit `ec2f52f`,
plus the migration baseline builds. The audit itself compiled nothing except at
migration — findings marked *(build)* came from the Release compile.

**Severity:** P0 critical · P1 release blocker · P2 important · P3 improvement.

**State** — deliberately separate from severity, and the column that moves as
work lands:

| State | Meaning |
|---|---|
| **Confirmed defect** | The code is wrong today. Evidence is in hand. |
| **Unverified** | Suspected, mechanism plausible, not yet established. The cell says what would settle it. |
| **Confirmed gap** | Factually true and worth tracking, but not a defect in behaviour (coverage, tooling, process). |
| **Product decision settled** | We know what the correct behaviour is. The code does not do it yet. |
| **Resolved** | The implementation now matches the decision, and that has been verified. |

The distinction between the last two is the point of this register. An item
moves to **Resolved** only when code has changed and been checked — never
because a design was agreed. C-23 and C-24 are Resolved; both were filed during
Phase 1 rather than by the audit. C-1 is the first audit finding to move, and it
is Resolved **for its client scope only** — the server half is tracked separately
as C-26. Where a state is qualified like that, read the cell rather than the
word.

---

## Client findings

| ID | Finding | Sev | State | Phase |
|---|---|---|---|---|
| C-13 | **Unterminating loop in the purchase path.** `ConnectedMembershipStore:236` — `if let entitlementRefreshTask` shadows with the unwrapped non-optional, so `while entitlementRefreshTask != nil` is always true. Entered only when a refresh is already in flight; reachable after purchase (`:131`), restore (`:199`) and transaction updates (`:225`). A foreground refresh triggered by the StoreKit sheet dismissing is a plausible and possibly common trigger. Consequence: `purchase()` never returns, `isPurchasing` never resets, the user pays and never reaches sign-in. | **P1** (possibly P0 depending on trigger rate) | **Confirmed defect** *(build)*. Originally filed P3 "busy-wait, terminates in practice" — that was a misread. Fix landed on `feature/solo-connected` (`fix: remove the unterminating poll in refreshEntitlement`), awaiting B2 | **1, first** |
| C-23 | **Ownership race in `refreshEntitlement`'s owner tail.** `ConnectedMembershipStore:271-275` cleared `entitlementRefreshTask` unconditionally after awaiting its own task. Once C-13's fix made the forced re-entry reachable, a waiter that resumed before the owner could install a newer task and have the owner then nil it — leaving a live refresh unregistered (so a later caller starts a duplicate), `isRefreshingEntitlement` false while one is in flight, and a stale `membershipState` published over a newer one. **Not present in any build:** unreachable before the C-13 fix, because the poll meant the forced re-entry never ran. Closed by an identity guard in the same commit | P2 | **Resolved** — introduced and closed within the C-13 fix; build-verified, and covered incidentally by B2 | 1 |
| C-24 | **Reconnect after reinstall never completes.** Fresh install of an existing Connected member. The Keychain survives app deletion, so `AuthManager:198/210-220` restores `appleUserID` and the Supabase access token at init and re-derives `backendUserID` from the JWT subject — the app is already "signed in" at first launch. SIWA then writes the same stable Apple user ID (`AuthManager:876`), so `currentUserID` does not change, and every completion path keyed on that transition fails to run: `ProfileView:1621` never dismisses the SIWA sheet or unwinds the navigation stack, and `MOTIVOApp:291/306` (`removeDuplicates`) never re-resolves the app mode. `shouldSuppressSignedInProfileAfterGateSignIn` (`ProfileView:300`) then renders `Color.clear` permanently — the blank screen with only a back chevron — because its only reset requires `currentUserID == nil`. Device-observed on Release: sheet will not dismiss, user is returned to Solo with the Connected account intact on Supabase. **Not C-1 and not C-13**; independent of StoreKit. Note for C-1: the expiry-cleanup gate (`isSignedIn` + token + `backendUserID`) is Keychain-satisfied from the first millisecond of a reinstall, so only a missing entitlement transition stands between a reinstall and the deletion path | **P1** | **Resolved** — fixed at `29828b6`, device-verified on Release. Cause was device-confirmed first: `auth.siwa.applied changed=false` with no `profile.currentUserID.changed` ever emitted, in four runs; Connected was reached only because the *entitlement* transition drove activation, and the user escaped the stuck UI by swiping the sheet away and pressing the back chevron. Verified after the fix in both entitlement states — without an entitlement (sheet dismisses, lands in Solo, correctly) and through a purchase (unwinds into Connected), both logging `auth.signIn.completed` followed by `profile.signInCompleted`. Note the environment: verified under the synthetic StoreKit configuration, which is sufficient here because the defect and its fix are independent of StoreKit. The full journey — existing member, live entitlement, genuinely new device — is not testable under the local configuration, since deleting the app destroys its transactions (see C-9) | 1 |
| C-1 | Entitlement resolution cannot express "indeterminate"; one negative read triggers irreversible backend deletion. `ConnectedMembershipStore:230-267` → `MOTIVOApp:339/377` | P0 | **Resolved (client authority).** Device evidence (Release, instrumented, 2026-08-09), reproduced in three independent runs: a forced refresh fired by `transactionUpdate.verified` immediately after a *verified purchase* published `notEntitled`; only the second refresh moments later published `entitled`. A negative read can therefore be spurious rather than authoritative — previously argued from structure, now observed. Corollary: `purchase()`'s `guard isEntitled` (`:133`) is reliable only because a second read follows. **Environment:** both observations were under the synthetic StoreKit configuration, not real StoreKit (C-9), so the *frequency* under real conditions is still unknown — the mechanism is established, the rate is not. **Fixed at `6109116`:** the detect → arm → gate → delete pipeline is gone, `handleMembershipState` does nothing but `applyActivation`, and no client entitlement path can reach `deleteCurrentConnectedAccount`. **Device-verified on a genuine subscription lapse**, not a forced deletion: the entitlement expired at term end, the app published `notEntitled` and dropped to Solo, Connected credentials and identity survived untouched (`auth.init appleID=true backendID=true token=true` on relaunch), and the Supabase account survived — proven by Erase All Études Data subsequently finding and deleting a live account. Re-subscribing restored Connected unaided. The lapse was observed across a force-quit and relaunch, which also satisfies C4. No indeterminate state was added and none is needed: without deletion a spurious negative read only withdraws access, which invariant 3 permits because it is reversible. **Scope: this closes the client authority only.** Server-side authority and the interim retention gap are tracked as C-26 | 1 |
| C-26 | **No server-side membership authority yet.** C-1 removed the client's ability to act on expiry. App Store Server Notifications V2 — the sole authority for membership-expiry cleanup under the settled architecture — are Phase 3 and do not exist. **Interim consequence: no membership-expiry cleanup happens at all. A lapsed member's Supabase account, posts, attachment references and storage objects are retained indefinitely.** Accepted deliberately: retention pending authoritative evidence beats deletion on client evidence now observed to be wrong in three separate runs. Closing this is the Phase 3 scope already planned — server-side entitlement state, ASSN ingestion, Billing Grace, replay protection, idempotent processing — and QA Group C rows C5–C10 are already written against it | **P1** | **Confirmed gap** — scheduled, not missing by accident. Becomes a defect only if the release ships without it | 3 |
| C-27 | **Location set while Connected does not carry to the Solo profile on sign-out unless `ProfileView` is mounted.** The backend→local copy lives in `ProfileView:1676-1681`, inside the `currentUserID` observer, so it only runs if the view exists at the moment of sign-out. Split from C-19, which concerned *expiry* and is Resolved. **No data loss:** `profile.<backendUserID>.location` is not deleted, so signing back in with the same identity restores it — the local Études profile simply shows the older local value until then. Cosmetic asymmetry: the sign-*in* promotion (`AuthManager:532-537`) is unconditional and view-independent; only the sign-out direction is not | P3 | **Confirmed defect** — by trace | 5 |
| C-2 | "Erase All Études Data" does not clear the Scores library, and the singleton resurrects it on next mutation. `LocalFactoryReset:24`, `AttachmentStore:412`, `ScoreLibraryStore:159` | P1 | **Confirmed defect** | 1 |
| C-3 | Staged video held wholly in memory; re-read plus full temp copy on every foreground, synchronously on main actor. `PracticeTimerView:4572/3988/1816` | P1? | **Confirmed defect** (mechanism); severity **unverified** — needs device measurement | 1 (measure) / 5 (fix) |
| C-19 | Location is keyed per backend user ID (`profile.<userID>.location`, `ProfileStore:32`) and its preservation across membership expiry appears to depend on a mounted `ProfileView`. The architecture states location survives expiry, so this is an implementation question, not an open product decision. | P2 | **Resolved** — the mechanism no longer exists. Verified by the trace this row asked for: location lives at `profile.<backendUserID>.location`, and the only code that deletes it is `wipeLocalIdentityForFactoryReset`, called solely from `LocalFactoryReset:78` (Erase All Études Data) — never on expiry, never on sign-out. Since C-1, expiry does not clear `backendUserID` at all, so the key stays resolvable and `ProfileView:944/1697` reads it normally. Location therefore survives expiry unconditionally, with no mounted-view dependency; the dependency was a consequence of the expiry path clearing identity, which is gone. Corroborated on device: yesterday's genuine lapse occurred with no `ProfileView` mounted and `auth.init` reported `backendID=true` on relaunch. Residual sign-out wrinkle split out as C-27 | 1 |
| C-7 | ~11.6 MB `debug_upload_test.*` in the app bundle | P2 | **Confirmed defect** — inspected `Release-iphoneos/Etudes.app`: `debug_upload_test.mp4` (11,228,233 B) and `.m4a` (382,447 B) are both present, 11.6 MB of a 71 MB bundle. Their only consumer is `DebugViewerView`, which is `#if DEBUG`-gated, so in Release the payload ships and nothing can reach it. Cause is the flat `fileSystemSynchronizedGroups` layout: everything under `MOTIVO/` is copied as a resource regardless of any `#if DEBUG` in Swift. Fix is an exclusion or a move out of the synchronized group, not a code change | 1 |
| C-8 | No `PrivacyInfo.xcprivacy`; required-reason APIs used. TestFlight history suggests uploads were accepted | P2 | **Confirmed gap** — no `PrivacyInfo.xcprivacy` in the repo or the built bundle. First-party required-reason usage is narrower than filed: exactly two categories. **UserDefaults** (42 files) and **file timestamps** — a single site, `PracticeTimerView:4508` reading `attrs[.creationDate]`. *Not* disk space (only `.fileSizeKey`/`.size`, which are out of scope), not system boot time, not active keyboards. Bundled third-party manifests: AudioKit and swift-crypto ship their own; supabase-swift 2.5.1 and KeychainAccess ship none. Remaining unknown is only whether Apple has been sending ITMS-91053 warnings on upload — App Store Connect, owner-checkable | 1 |
| C-20 | Main-actor-isolated `PersistenceController.shared` and `fetchUserInstruments` reached from a nonisolated context. `AuthManager:494`. Touches Core Data `viewContext` off-main — a real data-race risk, and a hard error under Swift 6 | P2 | **Confirmed defect** *(build)* | 5 |
| C-21 | Three discarded `let status` reads in `NetworkManager` (258, 504, 555) — the shape of a dropped check | P2/P3 | **Confirmed defect** *(build)*, needs reading to establish consequence | 5 |
| C-4 | Permanent user media excluded from iCloud backup while Core Data is not. Architecture Decision 4 settles the target: user-authored media participates in Apple backup, with a reconciliation pass on restore | — | **Product decision settled** — implementation pending | 2 |
| C-5 | Duplicate Score adoption: `savedToScoresAt` never consulted by the UI. `ConnectedAttachmentShareUI:755`. Server rejects the second write; the client still creates a duplicate local entry | P2 | **Confirmed defect** | 5 |
| C-6 | `fatalError` on Core Data store load. `Persistence:43` | P2 | **Confirmed defect** | 5 |
| C-9 | All StoreKit testing to date used the synthetic local config; real StoreKit only exercised in Release | P2 | **Confirmed gap** | 3 / RC |
| C-10 | `.file` attachments send `application/octet-stream`, rejected by the bucket allow-list; failure is fatal and wedges the sync queue permanently. `BackendShim:1384`; importers use `[.item]` | P2 | **Confirmed defect** (client side) | 5 |
| C-11 | Favourite button announces "Open comments" to VoiceOver. `SessionDetailView:1704` | P3 | **Confirmed defect** | 5 |
| C-12 | `SessionDetailView.deleteSession()` unreachable dead code | P3 | **Confirmed gap** | 6 |
| C-14 | Backend user IDs and handles logged via NSLog in release | P3 | **Confirmed defect** | 5 |
| C-15 | `PDFSelectedPagesStore` unscoped, never collected | P3 | **Confirmed defect** | 6 |
| C-16 | `try!` on directory creation. `SessionSyncQueue:279` | P3 | **Confirmed defect** | 5 |
| C-17 | Unit test suite is an empty template | P3 | **Confirmed gap** | — |
| C-18 | `stageAudioURL` reads file attributes after deleting the file | P3 | **Confirmed defect** | 6 |
| C-25 | **Expiry-specific naming on a policy-neutral primitive.** `AuthManager:802` `clearConnectedIdentityAfterMembershipExpiry()` names a caller's motive rather than the operation. What it does is mechanical — clear the local Connected identity and session — and has several legitimate triggers beyond expiry: server-confirmed cleanup, Sign in with Apple credential revocation, a server-forced sign-out. Since C-1 removed the client's expiry responsibility, the suffix asserts a context the function has no way to know. Target: a policy-neutral primitive taking the motive as a parameter, `clearConnectedIdentity(reason:)`, mirroring `deleteCurrentConnectedAccount(reason:)` which already models this. Phase 3's server-confirmed expiry orchestration may carry the policy-specific name and *call* the primitive — the policy must not be folded back into it | P3 | **Confirmed gap** — naming and layering, no behavioural defect. Deferred deliberately: renaming now would pre-empt a Phase 3 design that does not exist yet | 6 |
| C-22 | 53 deprecated AVFoundation and SwiftUI APIs (`videoOrientation`, sync `duration`/`tracks`/`naturalSize`, `copyCGImage`, `exportAsynchronously`, `onChange(of:perform:)`) | P3 | **Confirmed gap** *(build)* | 6 |

## Copy alignment (not code defects)

| ID | Item | State | Phase |
|---|---|---|---|
| D-1 | "Share with followers" defaults ON. **Behaviour is intentional and unchanged** — chosen from TestFlight evidence that the opposite default produced empty feeds. Changeable via the persistent "Default to Private Posts" preference; per-session toggle retained; notes and attachments keep independent controls. Copy task: scope "private by default" claims to Études proper, state that Connected follows the user's sharing preference and where to change it, note that Thoughts default to private. Must match the revised App Store privacy labels. | **Product decision settled** — copy not yet written | 4 |
| D-2 | Notes on unshared sessions uploaded unless separately marked private | **Product decision settled** — dissolves under shared-only uploads | 4 |

---

## Backend findings

| ID | Finding | Sev | State | Phase |
|---|---|---|---|---|
| B-1 | `delete_account_v1` recursive sweep of `attachments/users/<uid>` destroys Connected assets other members still reference | P0 | **Confirmed defect** | 1 |
| B-11 | **No server-side membership enforcement anywhere.** Every policy and RPC gates on `auth.uid()` and the follow graph only; nothing consults an entitlement. The entire paid Connected API — posts, comments, shares, attachments, directory — is therefore exercisable by any authenticated Apple user able to obtain a Supabase session. This is the missing enforcement boundary for the paid service itself: Connected is sold as a membership and the server has no concept of one. Requires a server-held entitlement record fed by App Store Server Notifications V2, plus policy predicates that consult it | **P1** | **Confirmed defect** | 3 |
| B-2 | **Account directory is fully scrapeable.** `search_account_directory` and `get_account_directory_by_user_ids` are `SECURITY DEFINER` and never consult `lookup_enabled`, so a member who has opted out of discovery is still returned. With B-15's 2-character substring floor, the whole directory can be enumerated by any authenticated user. (Membership enforcement is tracked separately under B-11) | P1 | **Confirmed defect** | 1 |
| B-3 | `delete_account_v1` deletes the departing member's comments on others' posts (`author_user_id` clause) — contradicts the retention decision. The `post_comments → posts` cascade already covers own-post comments | P1 | **Confirmed defect** | 1 |
| B-4 | Every delete in `delete_account_v1` ignores its result; reports success on partial failure. `posts` has no FK to `auth.users`, so orphans become permanently unreachable by any RLS policy | P1 | **Confirmed defect** | 1 |
| B-5 | `get_account_directory_by_user_ids` is anon-executable with no `auth.uid()` check | P2 | **Confirmed defect** | 1 |
| B-6 | `attachments_select_via_visible_post` trusts an unconstrained jsonb column; appears to permit read access surviving revocation | P2 | **Unverified** — reproduce with two accounts | 1 (verify) / 4 (expected to dissolve under shared-only deletion) |
| B-7 | `sign_attachment_rpc` is dead (client never calls it) and contains a `left(v_path, 6) <> 'debug/'` authorisation bypass | P2 | **Confirmed defect** (dormant) | 1 |
| B-8 | Storage objects orphaned when an attachment is un-included — no cleanup trigger is attached | P2 | **Confirmed defect** | 4 |
| B-9 | `connected_attachments` rows never deleted on account deletion; no FK, no explicit delete, no DELETE policy | P2 | **Confirmed defect** | 1 |
| B-10 | Dormant `cleanup_post_attachments_on_*`: `SECURITY DEFINER`, path-based deletion, no ownership predicate. Attached to nothing, so latent rather than live. Repair with an ownership predicate and attach in Phase 4, or drop | P2 | **Confirmed defect** (latent) | 1 (defuse) / 4 (repair) |
| B-12 | `delete_account_v1` storage listing stops silently at 1000 entries | P2 | **Confirmed defect** | 1 |
| B-13 | `delete_account_v1` not idempotent | P2 | **Confirmed defect** | 1 |
| B-14 | `follows_update_approve_by_followed` contains a tautological no-op guard; the approver can rewrite `follower_user_id` | P3 | **Confirmed defect** | 1 |
| B-15 | Weak anti-browse in `search_account_directory` (2-char substrings) | P3 | **Confirmed defect** | 4 |
| B-16 | `post_comment_views` accumulates orphans | P3 | **Confirmed defect** | 6 |

**Retracted:** an earlier P0 asserted cross-user storage destruction via the
cleanup triggers. `pg_trigger` shows they are attached to nothing, so the attack
does not work. What survives is B-10.

---

## Verified sound — do not revisit

**Backend:** RLS enabled on every public table with policies.
`posts_select_public_or_owner` correct (private posts owner-only; public require
an approved follow). `connected_attachments` INSERT policy binds the storage
path to sender UID and asset ID; SELECT and UPDATE recipient-scoped. The
immutability trigger. All three comment RPCs validate properly.
`follow_requests_open` enforced. Buckets private, MIME allow-listed,
size-limited. `delete_account_v1` authorisation (subject derived from the
verified token, never the request body).

**Client:** attachment privacy fails closed; session deletion is fail-closed;
`StagingStore`'s file-backed design; all DEBUG bypasses correctly gated; no
hardcoded credentials; no analytics, crash-reporting or attribution SDK; the
three lifecycle paths (sign out / expiry / erase) are correctly separated and
cannot trigger one another.

---

## Lessons for future work

Several findings were wrong because behaviour was inferred from names and
structure rather than checked:

- A P0 was filed for cross-user storage destruction on the assumption that two
  functions named `cleanup_post_attachments_on_*` were triggers. They are
  attached to nothing.
- C-13 was filed P3 with "it terminates in practice." It cannot terminate; the
  compiler caught what a close read missed.
- An avatar-loss risk on expiry was asserted and turned out not to exist — the
  avatar is already written to the device-local namespace.

**Verify before asserting.** Cheap checks — a grep, a build, one query — have
repeatedly changed conclusions.
