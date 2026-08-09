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
| B2 | **C-13 probe:** repeat B1 several times on a slow or throttled connection | Purchase must always complete through to sign-in. A permanently spinning Continue button confirms the unterminating loop |
| B3 | Check pre-existing Group A sessions | Still present, still private. Confirm none appear in another account's feed |
| B4 | Create a session, tap Save without touching Visibility | Observe whether it shares — D-1 behaviour check |
| B5 | Delete and reinstall; Restore Purchases | Entitlement restored, Connected reactivated |
| B6 | Sign out, sign back in | Connected restored; no data loss; no account deletion |

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
| C1 | Cancel the sandbox subscription, let it lapse, foreground the app | App drops to Solo. Local sessions, scores and attachments **all intact**. Explanatory alert shown. **No account-deletion request is issued from the device** — confirm via proxy that no `delete_account_v1` call occurs |
| C2 | Repeat C1 with the device in Airplane Mode when foregrounding, then re-enable networking | **C-1 probe.** An unverifiable entitlement read is *indeterminate*, not negative. The app does not treat an indeterminate entitlement state as evidence of expiry: it remains Connected, does not drop to Solo, and — once connectivity returns — issues no account-deletion request and re-resolves entitlement from scratch |
| C3 | While entitled, sign out of the App Store account in iOS Settings, then foreground Études | **C-1 probe.** Same as C2 — indeterminate, no destructive action, backend account survives |
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

| # | Steps | Expected |
|---|---|---|
| D1 | Import 3 scores. Erase All Études Data → type ERASE. **Without relaunching**, reopen Scores | **C-2 probe.** Library must be empty. If scores appear, tap one — the resurrection path |
| D2 | Relaunch; check Scores; inspect the container for `Documents/Scores` | Directory empty |
| D3 | Sign out (not erase) | Local journal intact; backend account **not** deleted |
| D4 | Swipe-delete a shared session with the network off | Fail-closed: nothing deleted locally or remotely |
| D5 | **B-1 probe:** account A sends an attachment to B; B does *not* save it to Scores; A performs Erase All; check B's inbox | Before fix: B's item fails to download. After fix: B's item still works |

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
| E8 | **B-6 probe:** A (approved follower) records the path of B's public post attachment; B unshares; A attempts access | Determines whether the revocation bypass is real |
| E9 | **B-2 probe:** account A disables directory lookup; account B searches for A's handle and display name | A must not be returned. Repeat via both directory RPCs |
| E10 | **B-11 probe:** obtain a Supabase session for an account with no active entitlement and attempt each Connected operation | After Phase 3: every write and every read of Domain 3 is refused server-side |

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
