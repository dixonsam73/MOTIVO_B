# Études — Manual QA Plan

Derived from the implementation as audited, and revised against the settled
architecture. Used as the per-phase verification gate and, in full, for the
Release Candidate.

**Prerequisites:** a TestFlight (Release) build — Debug cannot exercise real
StoreKit; a sandbox Apple ID; a second Connected account for social flows; a
device with ≥2 GB free. **Use a disposable Apple ID and a device you can erase
for Groups C and D.**

**Verification principle.** Every phase should verify both the new behaviour and
that the existing interaction still feels unchanged where architectural
refactoring is intended to be invisible. Where a refactor is meant to be
invisible, "it still feels the same to use" is the acceptance criterion, and it
is tested by using the app — not by reading the diff.

---

## Group A — Solo / local-first (no account)

| # | Steps | Expected |
|---|---|---|
| A1 | Fresh install, launch | Setup asks name + one instrument. **No sign-in prompt at any point.** |
| A2 | Complete setup; log a session with notes, photo, audio | Saves locally. Confirm via proxy that **no network traffic** occurs |
| A3 | Import 3 PDFs to Scores; favourite one, rename one, attach a page range to a session | All persist across relaunch; attachment reopens at the right pages |
| A4 | Record a 30s video, background the app, return | Returns promptly. **Time it** — small-scale C-3 probe |
| A5 | Repeat with a 5-minute video | Hang or kill on foreground confirms C-3 |

## Group B — Connected acquisition

| # | Steps | Expected |
|---|---|---|
| B1 | Profile → Explore Connected → Continue → Monthly → purchase | Sandbox purchase, then SIWA, then Connected active |
| B2 | **C-13 probe:** repeat B1 several times on a slow or throttled connection | Purchase must always complete through to sign-in. A permanently spinning Continue button confirms the unterminating loop. **First-run coverage, not a re-test:** the loop made `refreshEntitlement`'s forced re-entry unreachable, so the second, fresh entitlement refresh has never executed in any build. Watch for a wrong entitlement state after a verified purchase — "Purchase verified but no active membership" — as well as for a hang |
| B3 | Check pre-existing Group A sessions | Still present, still private. Confirm none appear in another account's feed |
| B4 | Create a session, tap Save without touching Visibility | Observe whether it shares — D-1 behaviour check |
| B5 | Delete and reinstall; Restore Purchases | Entitlement restored, Connected reactivated |
| B6 | Sign out, sign back in | Connected restored; no data loss; no account deletion |
| B7 | **C-36 probe — does the Solo location survive joining?** Set a Location (and a Name) in Solo. Join Connected as in B1. Watch the Location field at the instant sign-in completes, then query `account_directory.location` for the new user **and** check what a second account sees on your profile | The field must not blank out, and the column must hold the location, not `NULL`. Blank field is the read at `ProfileView:1687`; `NULL` in the column is the debounced write ~650 ms later. Both can occur while Profile *later* shows the location again, because `AuthManager:529` repairs the local copy — so **the column is the verdict, not the screen**. Repeat once with the Name field left empty: that path skips the publish entirely and should fail the same way without any race |

## Group C — Membership lifecycle (disposable account)

Rewritten for the settled architecture. Three properties are under test, and
they are separable — test each on its own before testing them together:

1. **The client drops to Solo on entitlement, and does nothing else.** Loss of
   entitlement changes app mode. It must never initiate backend deletion.
2. **The server performs Domain 3 cleanup**, driven by App Store Server
   Notifications V2 — not by anything the device does or fails to do.
3. **The two are decoupled.** Neither is a precondition for the other. A device
   that never launches again must not prevent cleanup; a server that has not yet
   processed a notification must not keep the app in Connected.

Domain 1 (the local journal, media and Scores) is untouched by every row in this
group. Verify that explicitly each time, not just once.

| # | Steps | Expected |
|---|---|---|
| C1 | Cancel the sandbox subscription, let it lapse, foreground the app | App drops to Solo. Local sessions, Scores and attachments **all intact**. **No "Membership Ended" alert** — the client is no longer authoritative about membership state, so it makes no claim about it. The **backend account and posts survive**: no client-initiated cleanup exists, and server cleanup arrives with Phase 3. **No account-deletion request is issued from the device** — confirm via proxy that no `delete_account_v1` call occurs |
| C2 | Repeat C1 with the device in Airplane Mode when foregrounding, then re-enable networking | **C-1 probe.** A transient or unverifiable negative read *may* drop access to Solo — that is permitted, because it is reversible and invariant 3 allows reversible decisions on client evidence. The invariant under test is that **nothing irreversible or destructive follows from client entitlement evidence**: no `delete_account_v1` call, no Connected identity or session cleared on the device, backend account and posts intact. Access must return once connectivity is restored and the entitlement re-resolves |
| C3 | While entitled, sign out of the App Store account in iOS Settings, then foreground Études | **C-1 probe.** Same invariant as C2: dropping to Solo is permitted, destroying anything is not. Backend account survives, Connected credentials remain on the device, and access returns when the entitlement resolves again |
| C4 | Force-quit during the drop to Solo, relaunch | The mode transition completes idempotently. Still no client-initiated deletion. Local data intact |
| C5 | Let expiry occur, then re-subscribe **before** the server has processed cleanup | Entitlement restored; Connected reactivated; Connected data intact. The server must recognise the renewal and abandon any pending cleanup |
| C6 | Failed payment on renewal (Billing Grace Period) | Entitlement retained throughout grace. App stays Connected. No cleanup at any point during grace |
| C7 | **Server authority:** let a subscription expire and grace lapse, then **never launch the app again**. Inspect the backend after the cleanup window | Domain 3 cleanup completes server-side with no device involvement. `posts`, `post_shares`, `connected_attachments`, storage objects and `account_directory` handled per the retention decision — comments authored on others' posts **retained** |
| C8 | Deliver the same expiry notification twice (replay) | Second delivery is a no-op. No double deletion, no error surfaced, cleanup state unchanged |
| C9 | Deliver a malformed or unsigned notification | Rejected on signature verification. Nothing is deleted |
| C10 | **Decoupling:** with cleanup already complete server-side, launch the app while still un-entitled | App is in Solo, local journal intact, no crash and no attempt to reach Domain 3 endpoints. Re-subscribing produces a clean new Connected identity |
| C11 | **C-19 probe:** set a location while Connected, let membership expire, foreground the app **without opening Profile** | Location survives the transition. Reopen Profile afterwards and confirm it is still set |
| C12 | Confirm by code inspection and by proxy that Erase All is the **only** client-initiated destructive action remaining | Invariant check. Any client path to backend deletion other than Erase All is a regression |

## Group D — Destructive (disposable device state)

**Prerequisite: two real Apple IDs, held at the same time.** D5–D8 each need a
sender and a recipient, and E2 and E8 need the same. This cannot be met with
sandbox tester accounts: those authorise *purchases* only, and Sign in with
Apple requires a real Apple ID, so a tester can never become a second Connected
identity. Two devices, or one device and a willing second person.

Reassuring counterpart: **an Apple ID is not consumed by these tests.** Erase
All deletes the Connected account, not the Apple ID — signing in again with the
same Apple ID mints a fresh Connected identity. So two Apple IDs can cycle
through every destructive row rather than being spent one per test.

D5–D11 test the rewritten `delete_account_v1` and are meaningless until it is
deployed. Run against the old function they would simply re-demonstrate B-1,
B-3, B-4, B-9, B-12, B-13 and B-19 while destroying accounts to do it.

| # | Steps | Expected |
|---|---|---|
| D1 | Import 3 scores. Erase All Études Data → type ERASE. **Without relaunching**, reopen Scores | **C-2 probe.** Library must be empty. If scores appear, tap one — the resurrection path |
| D2 | Relaunch; check Scores; inspect the container for `Documents/Scores` | Directory empty |
| D3 | Sign out (not erase) | Local journal intact; backend account **not** deleted |
| D4 | Swipe-delete a shared session with the network off | Fail-closed: nothing deleted locally or remotely |
| D5 | **B-1 probe:** account A sends an attachment to B; B does *not* save it to Scores; A performs Erase All; check B's inbox | Before fix: B's item fails to download. After fix: B's item still works |
| D6 | **B-1 counterpart.** A sends an attachment to B; B deletes it from their inbox (soft delete); A performs Erase All. Inspect storage under `users/<A>/connected/` | The object **is** removed. Preservation is reference-counted on `deleted_at IS NULL`, not blanket — a sent asset with no live recipient reference must not linger. Together with D5 this pins both directions of the rule |
| D7 | **B-3 retention.** A comments on B's post. A performs Erase All. B views their own post | A's comment is **still there**. It is A's words on B's post, and the settled decision retains it. The author is now unresolvable — confirm the client renders that gracefully rather than crashing or showing a blank row |
| D8 | **B-19 retention.** A comments on B's post; B replies to A using the owner reply. A performs Erase All. B views their own post | B's reply is **still there**. It is B's words on B's own post; A was merely the addressee. Previously deleted by the `recipient_user_id` clause. Check the recipient renders gracefully — `account_directory` is cascade-deleted, so the name will not resolve |
| D9 | **Post attachments removed.** A creates a post with an attachment, then performs Erase All. Inspect storage under `users/<A>/<postID>/` | Objects removed. These live under the same prefix as Connected shares but are never referenced by `connected_attachments`, so the preservation rule must not accidentally spare them |
| D10 | **Idempotent retry.** Induce a mid-sequence failure (for example, revoke storage permissions or take the bucket offline), call Erase All, and confirm the response is `{ success: false, step: … }`. Restore the condition and retry | The first call names the step it stopped at and does **not** report success. The retry safely continues — steps already completed are no-ops — and either completes with `success: true` or fails honestly at the next unresolved step. The account must still be signed in and usable between the two attempts, because `auth.users` deletion is strictly last |
| D11 | **No silent success.** Across D5–D10, confirm `success: true` is returned only when every step completed | The old function reported success unconditionally, so the client's existing `success` check was meaningless. This is what makes it meaningful |
| D12 | **B-20 probe — the avatar is removed on Erase All.** A sets an avatar while Connected and confirms it renders for follower B. A performs Erase All. Inspect the `avatars` bucket under `users/<A>/` | The object is gone. This is the ordinary path, where `avatar_key` is correctly set, and it must pass before D13 means anything |
| D13 | **B-20 orphan probe — the null-pointer case.** Reach the state deliberately: with an avatar uploaded, fail **only** the storage DELETE (a proxy blocking `storage/v1/object/avatars/*` is the honest way; the network being off fails the directory patch too and the pending marker then repairs it) while letting the `avatar_key` patch succeed. Confirm the column is null and the object still present. Now perform Erase All and inspect `avatars/users/<A>/` | The object is removed anyway. Pointer-driven deletion leaves it — that is the defect. If the proxy proves impractical, null the column directly in the dashboard and record in the result that the state was simulated rather than provoked |

## Group E — Connected social and attachments

| # | Steps | Expected |
|---|---|---|
| E1 | Follow request → approve → check feed | Chronological, approved-follow only |
| E2 | Comment, then owner private reply; check with a third account | Third account sees neither |
| E3 | Share a PDF to two recipients | One upload, two inbox rows |
| E4 | "Add to Scores" on a received PDF, then **tap it again** | **C-5 probe** — duplicates? |
| E5 | Save received photo to Photos, audio to Files | Both succeed with correct permissions |
| E6 | Publish with attachments left private | Followers see none |
| E7 | Attach a `.txt` or `.zip` to a session, mark included, share | **C-10 probe.** Watch for a permanently stuck sync queue |
| E8 | **B-6 probe, part 1 — revocation:** A (approved follower) records the path of B's public post attachment; B unshares; A attempts access | Determines whether the revocation bypass is real |
| E8b | **B-6 probe, part 2 — the decisive test. NOT RUNNABLE AS WRITTEN — see note below Group E.** A takes the path recorded in E8 and creates a **private** post of their own whose attachment references that exact bucket and path. A then attempts to read the object. A must never have needed legitimate access for this to work | This is the mechanism read from the deployed policy: `attachments_select_via_visible_post` asks only whether *some* post references the path, with no predicate tying that post to the object's owner, and `posts_insert_owner` leaves the `attachments` jsonb unvalidated. **If A can read the object, B-6 is confirmed and is a privilege escalation rather than only a revocation bypass** — any member can read any attachment whose path they know. If A cannot, the schema reading is wrong and B-6 should be closed |
| E9 | **B-2 probe:** account A disables directory lookup; account B searches for A's handle and display name | A must not be returned. Repeat via both directory RPCs |
| E10 | **B-11 probe:** obtain a Supabase session for an account with no active entitlement and attempt each Connected operation | After Phase 3: every write and every read of Domain 3 is refused server-side |
| E11 | **C-34 probe — does a replacement propagate?** A sets an avatar; B (an approved follower) opens A's profile and the feed so B's device caches it. A replaces it with a visibly different image. Without relaunching either app, check B's feed rows, People and comments; then check A's own second device if one is available | Today: B keeps the old image until relaunch, and A's second device keeps it indefinitely, across relaunches. Also settles the storage half — inspect `avatars/users/<A>/` and confirm **one** object, overwritten, not two. That inspection is what turns C-34's upsert behaviour from inferred into observed |

**E8b needs a method, not just a tester.** It is written as though it were a UI
test and it is not: the app offers no way to type a storage path, so "create a
post whose attachment references that path" cannot be done by using the app. It
requires a crafted PostgREST insert with A's access token, setting the
`attachments` jsonb by hand — a developer action, and a deliberate write of
fabricated data to production.

That is the same category of action we declined for B-6 earlier, and declining
it is why B-6 still reads "mechanism established from schema; runtime
confirmation pending". Resolve the method before attempting the row. The
options, none yet chosen: run it against a local Supabase instance once Phase 3
brings one; run it against a disposable project; or accept a single crafted
insert on production under a disposable account, with the row deleted
afterwards. Do not improvise this mid-session.

## Group F — Backup and restore

| # | Steps | Expected |
|---|---|---|
| F1 | Full device backup → restore to another device | After Phase 2: media and Scores present. Before Phase 2: expect broken media and empty Scores |
| F2 | After Phase 2 reconciliation: verify pre-existing media is included, not just newly written files | The reconciliation pass is what makes this true for existing users |

## Group G — Accessibility

| # | Steps | Expected |
|---|---|---|
| G1 | VoiceOver through Journal, Session Detail, Scores, Membership Selection | Correct labels. **C-11 probe:** the heart must announce "Save", not "Open comments" |
| G2 | Largest accessibility Dynamic Type size across all primary screens | No truncation or overlap |
| G3 | Reduce Motion enabled | Animations respect it |

## Group H — Playback rate (Phase 5)

Four playback surfaces are backed by two engines: `AVAudioPlayer` for local
audio, `AVPlayer` for everything else. Test all four surfaces regardless — the
point of the feature is that origin is invisible to the user.

| # | Steps | Expected |
|---|---|---|
| H1 | Local audio attachment: play at 100%, 75%, 50% | Rate changes take effect immediately at each step |
| H2 | Local video attachment: same three rates | As H1, with audio and video staying in sync |
| H3 | Received (remote) audio: same three rates | Identical behaviour and identical controls to H1 |
| H4 | Received (remote) video: same three rates | Identical behaviour and identical controls to H2 |
| H5 | **Pitch:** play both a sustained musical note and spoken speech at 50% and 75% | Pitch is preserved by ear — slower, not lower — for both musical material and speech. Any audible transposition is a failure |
| H6 | Set 50%, pause mid-item, resume | Resumes at 50%. The rate is not silently reset by the pause |
| H7 | Set 50%, scrub backwards and forwards | Rate survives seeking |
| H8 | Set 75%, close the viewer, reopen the same attachment | Rate resets to 100%. The setting is per viewing session, not persisted |
| H9 | Set 50%, close the viewer, open a **different** attachment | Opens at 100% |
| H10 | Open `MediaTrimView` on an item last played at 50% | **Always opens at 1×.** Trimming is judged against true speed; a trim performed at reduced rate would be misleading |
| H11 | Change rate with VoiceOver active | Control is labelled and its current value announced |

---

## Regression areas after any change

Timer state recovery across launch · staged-media rehydration on foreground ·
score-to-session attachment resolution after relaunch · publish/unpublish
`is_public` propagation · the three lifecycle paths remaining separate ·
**client and server membership responsibilities remaining decoupled.**

---

## Deferred — Threads as first-class entities (M13)

Not for implementation now. Recorded here so the behavioural contract survives
the refactor: when Threads stop being string labels and become entities, these
are the properties that must still hold. Several of them describe behaviour that
exists today and must be *preserved*, which is the harder half.

| # | Property | Notes |
|---|---|---|
| T1 | Primary Thread assignment | A session's explicitly chosen Thread is authoritative and round-trips through save, edit and relaunch |
| T2 | Derived Thread usage | Threads inferred from usage appear where expected without being promoted to explicit assignments |
| T3 | Thread-aware Resume | Resume opens the right Score at the right page for the Thread in play |
| T4 | **Thread chip interaction unchanged after entity conversion** | The refactor is meant to be invisible. Judged by using the chips for five minutes and finding nothing different — not by reading the diff |
| T5 | Thread rename updates all references | No orphaned label strings, no duplicated Threads, no sessions left behind on the old name |
| T6 | Primary Score preparation never overrides an explicitly chosen Score | Thread selection may *prepare* a Score. An explicit choice always wins |
| T7 | Unused Threads disappear naturally while preserving stable identity | A Thread with no references is simply not presented in the UI, while its identity persists underneath for sync. Reusing the Thread never creates a duplicate and never requires recreation by name |
