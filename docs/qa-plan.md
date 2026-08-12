# Études — Manual QA Plan

Derived from the implementation as audited, and revised against the settled
architecture. Used as the per-phase verification gate and, in full, for the
Release Candidate.

**Prerequisites:** a Release build — Debug cannot exercise real StoreKit at all,
and a TestFlight build is required only where the *distribution artifact* is
under test; a sandbox Apple Account; a second Connected account for social flows; a
device with ≥2 GB free. **Use a disposable Apple ID and a device you can erase
for Groups C and D.**

**Verification principle.** Every phase should verify both the new behaviour and
that the existing interaction still feels unchanged where architectural
refactoring is intended to be invisible. Where a refactor is meant to be
invisible, "it still feels the same to use" is the acceptance criterion, and it
is tested by using the app — not by reading the diff.

---

## StoreKit environments — choose deliberately

Three environments, not interchangeable. Four findings in the register — C-9,
C-29, C-30 and C-38 — exist because the differences between them were invisible
at the time.

| Environment | How to get it | What it proves | What it hides |
|---|---|---|---|
| **Synthetic** (`Etudes.storekit`) | Attach in Run → Options. **Opt-in only since 2026-08-11** | Client logic against locally-defined products | Everything server-side — App Store Connect configuration, product vending, real entitlement timing. Apple's sheet reads `[Environment: Xcode]` |
| **Sandbox** — the preferred loop | Xcode, Run action **Release**, StoreKit Configuration **None**, dedicated Sandbox Apple Account | Real StoreKit against Apple's servers, with debugger and live console attached. **Honours the tester's accelerated renewal rate**, so a full subscription cycle completes in ~30 min | The distribution artifact itself |
| **TestFlight** | Upload a build | The artifact beta testers install, transacting on sandbox IAP | Nothing StoreKit-specific — but it is slow to iterate, and **subscriptions renew daily for up to a week regardless of the tester's rate**, so an entitlement cannot be reset on demand. See step 4 |

### The preferred development loop, and it repeats

1. **Run action = Release.** Debug's bundle ID vends nothing; you get C-29's
   signature rather than a purchase.
2. **StoreKit Configuration = None** in Run → Options.
3. A **dedicated Sandbox Apple Account**, signed in under Settings → Developer
   on the test device. Not a personal Apple ID.
4. **Getting back to a clean first-purchase state is the hard part, and there
   is no quick lever. CORRECTED 2026-08-12 — read this before planning any
   run that needs repeated purchases.**

   This step previously read: *"Between clean-purchase tests, clear that
   tester's purchase history in App Store Connect. This restores a genuine
   first-purchase state without creating a new account and without waiting for
   a subscription to lapse."* **That is false, and it was never observed — it
   was written from expectation.** Note what the one successful clean run
   actually used: the C-38 attempt on 2026-08-11 ran on a **fresh Sandbox Apple
   Account**, not a cleared one, so clearing has no supporting evidence behind
   it anywhere in this repository.

   **Observed 2026-08-12, Device B, TestFlight build 131.** Purchase history
   was cleared in App Store Connect; then >10 minutes elapsed, the app was
   force-quit and relaunched repeatedly, the sandbox tester was signed out and
   back in, and the device was restarted. **Études remained Connected
   throughout.** Apple's own Manage Membership sheet on the device showed the
   subscription **active at £4.99/month, renewing 13 August**, and stated that
   cancelling would still leave access until that date.

   So, for an already-active subscription:

   - **Clear Purchase History does not withdraw a live entitlement**, and
     nothing about waiting, relaunching, re-signing-in or rebooting changes
     that.
   - **Cancelling does not either** — access continues to the period end by
     design, which is correct StoreKit behaviour and not a defect.

   **What actually yields a clean first-purchase state:** a **new sandbox
   tester**, or waiting out the current period. Budget for that when planning,
   or design the run to need one purchase rather than several.

   **The two sandboxes keep different time, and conflating them is what made
   the observation above confusing.** Apple documents that **TestFlight**
   auto-renewable subscriptions renew **daily, up to six times within a
   one-week period, regardless of the tester's configured accelerated renewal
   rate**. Development sandbox — Xcode, Run action Release, StoreKit
   Configuration None — *does* honour that per-tester rate.

   | | Renewal cadence | Practical lifetime of one purchase |
   |---|---|---|
   | **Development sandbox** (run from Xcode) | the tester's configured accelerated rate, e.g. Monthly ≈ 5 min | ~30 min (6 renewals) |
   | **TestFlight** | **daily, max 6 renewals in one week — tester rate ignored** | **~6 days** |

   This is exactly why Device B showed **"Renews 13 August"** while Tester #2
   is configured for a five-minute Monthly cadence: the setting was not being
   applied, because the purchase was made on TestFlight. Nothing was
   misconfigured. *(Source: Apple's current TestFlight documentation, reported
   2026-08-12 — external, not observed here. The 13 August renewal date on
   Device B is consistent with it.)*

   **An earlier version of this step listed the per-tester Subscription Renewal
   Rate as a plausible lever for resetting a TestFlight entitlement. It is
   not** — TestFlight ignores it. Do not reach for it there.

   **Planning consequence.** A TestFlight entitlement lasts roughly six days
   and then lapses on its own. So a clean first-purchase state on the
   distribution artifact arrives **free, about a week later**, or immediately
   with a new tester — but it cannot be manufactured on demand within a
   session. Design TestFlight runs around one purchase. Runs that genuinely
   need repeated first purchases belong in the development sandbox, where the
   accelerated rate applies and a cycle completes in half an hour.

### Two ways this test lies to you

**Verify the environment on Apple's sheet, never on ours.** The app's own
selection screen cannot discriminate: `Etudes.storekit` mirrors App Store
Connect exactly — same display names, same prices. Apple's payment sheet is the
only reliable tell: **"Sandbox"**, with "For testing purposes only" and an
Account line, versus `[Environment: Xcode]` for synthetic.

**Establish entitlement state from evidence, not from the screen.** Solo mode
does **not** mean non-entitled — the app resolves to Solo whenever identity is
absent, whatever the subscription is doing, and on 2026-08-11 a device sat in
Solo with a live entitlement for an hour before that was noticed. With the
diagnostic instrumentation now removed, **Apple's own Manage Membership sheet on
the device is the authoritative check** — it names the plan, the price, the
renewal date and whether access continues after cancellation. Prefer it to App
Store Connect's purchase-history view, which showed a cleared history on
2026-08-12 while the device still held a live, renewing subscription. **Clearing
purchase history does not guarantee any state; see step 4 above.**

### TestFlight remains a required checkpoint

The sandbox loop proves the purchase path. It does not prove the build that beta
testers install — different signing, different distribution path, no debugger.
**Group B must be re-run on a fresh TestFlight build before StoreKit work is
considered settled**, regardless of how many sandbox runs have passed.

## The standing two-device rig

Established 2026-08-11 during D14 and kept deliberately. Most of Group D and
parts of Group E need two live Connected identities, and this is what supplies
them.

| | **Device A** — "SD beta burner" | **Device B** — "SD iPhone" |
|---|---|---|
| Role | **Disposable.** The departing account in destructive rows | **Surviving / control.** Never the account being erased |
| Installs | Release only | Release **and** Debug, side by side |
| iCloud account | its own | a second, different one |
| Sandbox tester | dedicated tester #1 | dedicated tester #2 |
| After a destructive run | **a new sandbox tester, or wait out the current period.** Clearing purchase history does **not** withdraw a live entitlement — see step 4 above | left intact |

### Why the constraints are what they are

**Distinct Connected identities require distinct devices.** Native Sign in with
Apple offers no account picker — it uses whichever Apple Account is signed into
iCloud on that device. A Sandbox Apple Account cannot supply a second identity;
it only pays. So "two real Apple IDs" in Group D's prerequisite is really *two
devices signed into two different iCloud accounts*, and there is no way to fake
it on one handset.

**One sandbox tester per device.** Clearing purchase history is per tester, and
that is how Device A is returned to a clean first-purchase state. A shared
tester would drop Device B's entitlement at the same moment — and Device B is
the control whose inbox the destructive rows are checked against.

### Études Dev, and one trap it creates

Device B also carries **Études Dev** (`com.samueldixon.motivo.dev`), a
long-running local dataset kept for ordinary use. It is a genuinely separate app:
different container, different keychain access group, no App Groups. Nothing it
does can reach the Release install's data, or vice versa.

It **cannot transact.** The `.dev` bundle ID is unknown to App Store Connect, so
with StoreKit Configuration `None` it gets an empty product array — C-29's
signature. Connected testing there is therefore synthetic only, by deliberately
attaching `Etudes.storekit` for that run. **Real-sandbox Connected testing lives
on the Release installation.** Do not put a sandbox subscription through Debug.

**The trap:** Sign in with Apple identifiers are scoped to the development team,
not the bundle ID — observed 2026-08-11, when the fresh Release install landed in
the *same* backend account as Études Dev, avatar and location included. So both
apps on Device B are two clients on **one** Connected account. **Keep Études Dev
closed during any run that reads or writes account B's backend state**, or a
second client will muddy the snapshot.

---

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
| B2 | **C-13 probe:** repeat B1 several times on a slow or throttled connection. **PARTIALLY RUN 2026-08-12 on TestFlight build 131 (Device B) — see the result note, and read step 4 of the development loop before planning a re-run.** The repetition this row asks for **was not runnable**: it assumes a clean first-purchase state can be restored between attempts by clearing the tester's purchase history, and that assumption is false. The single attempt that did run was a genuine distributed-artifact purchase and passed | Purchase must always complete through to sign-in. A permanently spinning Continue button confirms the unterminating loop. **First-run coverage, not a re-test:** the loop made `refreshEntitlement`'s forced re-entry unreachable, so the second, fresh entitlement refresh has never executed in any build. Watch for a wrong entitlement state after a verified purchase — "Purchase verified but no active membership" — as well as for a hang. **This has now been observed: C-38, 2026-08-11.** The alert appears immediately after a successful purchase and Connected activates on the next foreground, so a tester who backgrounds the app before re-reading the screen will record a pass. When running this row, treat the alert itself as the failure and do not let the subsequent recovery erase it |
| B3 | Check pre-existing Group A sessions | Still present, still private. Confirm none appear in another account's feed |
| B4 | Create a session, tap Save without touching Visibility | Observe whether it shares — D-1 behaviour check |
| B5 | Delete and reinstall; Restore Purchases | Entitlement restored, Connected reactivated |
| B6 | Sign out, sign back in | Connected restored; no data loss; no account deletion |
| B7 | **C-36 probe — does the Solo location survive joining?** Set a Location (and a Name) in Solo. Join Connected as in B1. Watch the Location field at the instant sign-in completes, then query `account_directory.location` for the new user **and** check what a second account sees on your profile | The field must not blank out, and the column must hold the location, not `NULL`. Blank field is the read at `ProfileView:1687`; `NULL` in the column is the debounced write ~650 ms later. Both can occur while Profile *later* shows the location again, because `AuthManager:529` repairs the local copy — so **the column is the verdict, not the screen**. Repeat once with the Name field left empty: that path skips the publish entirely and should fail the same way without any race |

### B2 result — 2026-08-12, TestFlight build 131, Device B

**One attempt, and it passed.** Monthly purchase on the distribution artifact,
on real sandbox StoreKit: the purchase completed, **no C-13 hang** (Continue
resolved normally), **no C-38 false-failure alert**, and Connected activated.
Device B held surviving Connected identity, so it went straight to Connected
with no Sign in with Apple prompt — expected, not a deviation.

**The throttled repetitions were not run, and the reason is a defect in this
plan rather than a decision to skip them.** B2's design assumed the tester could
be returned to a first-purchase state between attempts by clearing purchase
history. That does not work on an already-active subscription — the full
observation is in step 4 of the development loop above. Restoring the state
would have meant either creating several more sandbox testers or waiting out
subscription periods, neither of which is worth it to manufacture repetitions.
**On TestFlight specifically, "waiting out the period" means about six days** —
subscriptions there renew daily up to six times regardless of the tester's
accelerated rate, so the repetitions were never going to be runnable in one
session on this artifact. If they are wanted, run them in the development
sandbox, where a full cycle takes half an hour.

**What this does and does not establish.** It establishes the acquisition path
on the artifact beta testers install, which is what C-9 required and which no
sandbox run could supply. It does **not** exercise C-13's hazard condition — a
forced entitlement refresh racing one already in flight — which has still never
occurred in any run, throttled or otherwise. C-13 remains closed on the source
being provably gone and build-verified, exactly as its cell already states; this
run does not strengthen that and was never going to on a single attempt.

**If the repetitions are ever wanted**, budget a fresh sandbox tester per
attempt and use the two shapes designed for it: throttled with the device
untouched after payment (the honest read for C-38, whose alert self-heals on the
next foreground), and throttled with a deliberate lock/unlock immediately after
payment to force a `scenePhase` refresh into the window (the most direct route
to C-13's hazard, accepting that it can mask C-38).

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

**Prerequisite: two real Apple IDs, held at the same time — see "The standing two-device rig" above, which now supplies this.** D5–D8 each need a
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
| D7 | **B-3 retention.** A comments on B's post. A performs Erase All. B views their own post. **Prerequisite, learned the hard way on 2026-08-11: B must follow at least one account other than A.** Comments exist only in feed view by design, and the erase removes the A↔B follow edge — so if A was the only account B followed, B's feed is empty and there is no route to the thread at all. Retention still passes in the database; the client half simply cannot be reached | A's comment is **still there**. It is A's words on B's post, and the settled decision retains it. The author is now unresolvable — confirm the client renders that gracefully rather than crashing or showing a blank row. **The database half is Resolved (2026-08-11); this row is now open only for the rendering half** |
| D8 | **B-19 retention.** A comments on B's post; B replies to A using the owner reply. A performs Erase All. B views their own post. **Same follow prerequisite as D7** | B's reply is **still there**. It is B's words on B's own post; A was merely the addressee. Previously deleted by the `recipient_user_id` clause. Check the recipient renders gracefully — `account_directory` is cascade-deleted, so the name will not resolve. **The database half is Resolved (2026-08-11); this row is now open only for the rendering half** |
| D9 | **Post attachments removed.** A creates a post with an attachment, then performs Erase All. Inspect storage under `users/<A>/<postID>/` | Objects removed. These live under the same prefix as Connected shares but are never referenced by `connected_attachments`, so the preservation rule must not accidentally spare them |
| D10 | **Idempotent retry. DEFERRED — no safe inducement exists yet. See the note below Group D.** As written: induce a mid-sequence failure, call Erase All, confirm `{ success: false, step: … }`, restore the condition and retry | The first call names the step it stopped at and does **not** report success. The retry safely continues — steps already completed are no-ops — and either completes with `success: true` or fails honestly at the next unresolved step. The account must still be signed in and usable between the two attempts, because `auth.users` deletion is strictly last — **with one exception, recorded below** |
| D11 | **No silent success.** Across D5–D9, D12 and D13, confirm `success: true` is returned only when every step completed | The old function reported success unconditionally, so the client's existing `success` check was meaningless. This is what makes it meaningful. **Scope, while D10 is deferred: this confirms the positive direction only.** Every runnable row is a success case, so nothing here exercises a `success: false`. The negative direction is exactly what D10 was for, and it is untested until D10 runs |
| D12 | **B-20 probe — the avatar is removed on Erase All.** A sets an avatar while Connected and confirms it renders for follower B. A performs Erase All. Inspect the `avatars` bucket under `users/<A>/` | The object is gone. This is the ordinary path, where `avatar_key` is correctly set, and it must pass before D13 means anything |
| D13 | **B-20 orphan probe — the null-pointer case.** Reach the state deliberately: with an avatar uploaded, fail **only** the storage DELETE (a proxy blocking `storage/v1/object/avatars/*` is the honest way; the network being off fails the directory patch too and the pending marker then repairs it) while letting the `avatar_key` patch succeed. Confirm the column is null and the object still present. Now perform Erase All and inspect `avatars/users/<A>/` | The object is removed anyway. Pointer-driven deletion leaves it — that is the defect. If the proxy proves impractical, null the column directly in the dashboard and record in the result that the state was simulated rather than provoked. **RUN 2026-08-11: PASS, setup simulated.** The proxy was judged disproportionate — C-33 already establishes reachability from source twice over, and this row tests the deletion's behaviour *given* the state, not how the state arose. The null-key state was created by one authorised `UPDATE` on the disposable account, verified read-only (key NULL, object present) before erasing. **This is the only row that discriminates the fix from the bug**, so D12 passing without it would have meant nothing. Checking the blast radius afterwards found two orphaned avatars from July deletions — filed as B-21 |

| D14 | **B-9, both halves — the received path has never executed.** Staged on A (departing) and B. Requires approved follows in both directions, since the attachment insert policy demands one. **Three legs, one erase:** (1) **B sends to A; A leaves it in their inbox** — this is the row step 1 deletes, and the 2026-08-11 run could not reach it because that account had zero received attachments; (2) **A sends X to B; B soft-deletes it** — tombstone row plus a swept object; (3) **A sends Y to B; B keeps it** — the B-1 guard. Snapshot `connected_attachments` (id, sender, recipient, storage_path, deleted_at) for both accounts and the storage listing under `attachments/users/<A>/` and `users/<B>/`, read-only, before and after. Then A performs Erase All | **1.** The `sender=B, recipient=A` row is **gone** — B-9's untested half. **2.** The `sender=A, recipient=B, deleted_at IS NOT NULL` row is **gone** — step 3b, the new behaviour, and the only assertion the current deployed function would fail. **3.** The `sender=A, recipient=B, deleted_at IS NULL` row **survives**, and B can still open Y — B-1 must not regress. **4.** Object X removed, object Y retained (D5/D6 re-confirmed). **5.** `{ success: true }` (D11, positive direction only). **6.** None of B's other rows touched. **EXPECTED RESIDUE, NOT A FAILURE:** leg 1 leaves B's object under `users/<B>/connected/` with no surviving reference — A's erase only sweeps `users/<A>/`, and B is still alive. That is the same unowned-object lifecycle the function's header already defers to **B-8/B-10 in Phase 4**; record it, do not file it again. **NOT COVERED, and do not let this run imply otherwise:** the two-recipient case — one asset, one live recipient and one soft-deleted — needs a sender plus two distinct recipients, so three accounts. Under step 3b it deletes a row whose object correctly survives, which is intended and remains unverified. **RUN 2026-08-11: PASS on every assertion.** Both accounts on separate devices under different iCloud Apple IDs. Received row deleted (step 1's first ever execution), sender tombstone deleted (step 3b), live sender row and its object survived and the recipient reopened the file. All eight blast-radius counts matched a prediction recorded before the erase. **One unstaged control carried the run:** B already held a soft-deleted row from a third-party sender, which step 3b's `sender_user_id` scoping had to spare — and did | 1 |

**D10 needs a fault-injection path, not just a tester.** Its own suggested
inducement does not work. "Revoke storage permissions or take the bucket
offline" cannot be done from outside the function: it runs as **service role**,
so there is no permission to revoke and nothing a client or a proxy can reach.
Every step is server-side, so the device is not in the path at all — turning the
network off aborts the *call*, not a step within it.

What remains, and why each was set aside:

- **Temporarily deploy a variant that throws at a chosen step.** Technically the
  cleanest demonstration, and never committed. **Declined:** it puts a
  deliberately broken account-deletion path into production for the duration,
  and "briefly" is not a property anyone can guarantee once a session goes
  wrong. The same objection as writing to production, applied to code.
- **Add QA-only failure injection behind an env var.** Rejected outright.
  Permanent fault-injection scaffolding inside a P0 irreversible path is a
  worse defect than the one it verifies.
- **DDL to make one step fail** — a constraint or trigger that raises on the
  delete. A schema write to production, which is the thing the backend rule
  forbids.

**Deferred until a disposable or local backend exists**, where any of the above
is free. Phase 3 brings a local instance for migration tooling; that is the
natural home for this row. Until then B-13's idempotency is **established by
inspection and not by execution** — every delete is `.eq()`-scoped, the storage
sweep re-lists before removing, `maybeSingle()` returns null on a second pass —
and the register should say so rather than implying the retry has been observed.

**One caveat that survives whenever D10 is eventually run.** The row asserts the
account is still signed in and usable between the two attempts. That holds for
every step except the last. If `auth.users` deletion **succeeds but its response
is lost**, the account is genuinely gone while the client sees a failure, and
the retry will return **401 `Invalid session`** — the token no longer resolves
to a user. That 401 is the correct answer, not a defect: it means the deletion
completed. Do not "fix" it by treating 401 as success. The function derives its
subject from the verified token, so accepting an unverifiable one would hand
away the only authorisation gate the function has — and `verify_jwt` is `false`
for exactly that reason (`supabase/config.toml`).

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
| E9 | ~~**B-2 probe:** account A disables directory lookup; account B searches for A's handle and display name~~ **VOID 2026-08-12 — do not run. There is no control to disable.** Connected discovery is always on and relationship privacy is explicit follow approval (settled; `ff2d4ff`), so no tester can put account A into the state this row assumes. B-2's `lookup_enabled` premise is withdrawn — gating either directory RPC on that column would blank names and avatars for existing followers, which is the opposite of correct. B-2's surviving half is enumeration, tracked under B-15 in Phase 4 | Superseded by E12/E13 for access control, and by B-15 for enumeration |
| E10 | **B-11 probe:** obtain a Supabase session for an account with no active entitlement and attempt each Connected operation | After Phase 3: every write and every read of Domain 3 is refused server-side |
| E11 | **C-34 probe — does a replacement propagate?** A sets an avatar; B (an approved follower) opens A's profile and the feed so B's device caches it. A replaces it with a visibly different image. Without relaunching either app, check B's feed rows, People and comments; then check A's own second device if one is available | Today: B keeps the old image until relaunch, and A's second device keeps it indefinitely, across relaunches. Also settles the storage half — inspect `avatars/users/<A>/` and confirm **one** object, overwritten, not two. That inspection is what turns C-34's upsert behaviour from inferred into observed |
| E12 | **B-5 device acceptance, part 1 — directory resolution still works for a signed-in member.** On Device B's **Release** install (the stable Connected control account), after the 2026-08-12 hardening made both directory RPCs authenticated-only. Four representative surfaces, not all thirteen call sites: **(a) feed** — open the feed and confirm owner names and avatars resolve on remote post rows; **(b) session detail and comments** — open a shared session from another member and its comment thread, confirming the owner and every comment author render by name; **(c) People and the follow graph** — open People, Followers and Following, confirming each row shows a name rather than a blank or a raw UUID; **(d) share picker** — begin sharing an attachment and confirm recipient rows resolve. All four go through `get_account_directory_by_user_ids`; if the token were missing on any of them the call is now a visible **401**, not a silent success, so a blank name or an empty list is a real failure and not a cosmetic one | Every surface renders identities exactly as before the change. **Any blank name, raw UUID or empty recipient list is a FAIL** — it means a call site reaches the RPC without a bearer token, which the hardening has now made fatal rather than invisible. Search is deliberately not retested here: V7 already proved it server-side |
| E13 | **B-5 device acceptance, part 2 — the follow-request path is unregressed.** Send one follow request from Device B's Release account to another account | The request is created and appears as outgoing. This exercises `follows_insert_requester`, whose `WITH CHECK` calls `follow_requests_open` — the function left deliberately untouched by the hardening (B-18). A failure here would mean the directory work disturbed the follow policy |

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
