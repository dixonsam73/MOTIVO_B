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
     that. **What was actually observed, stated as observation:** Settings →
     Developer → Sandbox Apple Account → Subscriptions read **"You do not have
     any subscriptions"** while the in-app Manage Membership sheet
     simultaneously showed the plan **active, £4.99/month, renewing 13 August**.
     Both are Apple's UI. **So two Apple surfaces disagreed, and the app kept a
     live entitlement throughout. That is the whole finding.**
     **Everything beyond it is hypothesis and is labelled as such:** it is
     *plausible* that the clear applies to the sandbox account while the device
     retains its own entitlement state, but nothing here establishes **where the
     retained state actually lives**, nor whether the two surfaces query the
     same source at different scopes. An earlier version of this step asserted
     that mechanism as fact on the strength of the disagreement alone. It does
     not follow, and settling it is not needed for any current work — the
     operational rule is simply that clearing does not withdraw a live
     entitlement.
   - **Cancelling does not give an immediate reset either** — access continues
     to the period end by design. **But do not read that as "cancelling is
     useless", which an earlier version of this step implied.** Cancelling
     stops the renewal chain, so it converts an open-ended run of daily
     TestFlight renewals into a **lapse on a known date** — which is exactly the
     tool to reach for when the *goal is to observe an expiry* rather than to
     re-purchase. Use it deliberately for C-1 / C-26 lapse testing.

   **Device-side sandbox controls worth knowing about** (Settings → Developer →
   Sandbox Apple Account → Account Settings), found 2026-08-12 and previously
   undocumented here:

   | Control | Use |
   |---|---|
   | **Allow Purchases & Renewals** | Toggle off to block renewals — a second route to a scheduled lapse |
   | **Test Interrupted Purchases** | **Apple's own way to produce a delayed/contended purchase.** Closer to C-13's actual hazard — a forced entitlement refresh racing one already in flight — than Network Link Conditioner, which only approximates it. Prefer this for B2 |
   | **Renewal Rate** | The accelerated cadence, e.g. Every 5 minutes. Applies in the development sandbox; **ignored on TestFlight** |
   | **Clear Purchase History** | Same effect as the App Store Connect action; see above for what it does and does not reach |
   | **Initiate Transaction** | Server-initiated purchase testing |

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
   | **Development sandbox** (run from Xcode) | the tester's configured accelerated rate, e.g. Monthly ≈ 5 min | **unknown — see the correction below. Do not plan around a figure here; cancel instead** |
   | **TestFlight** | **daily, max 6 renewals in one week — tester rate ignored** | **~6 days** |

   This is exactly why Device B showed **"Renews 13 August"** while Tester #2
   is configured for a five-minute Monthly cadence: the setting was not being
   applied, because the purchase was made on TestFlight. Nothing was
   misconfigured.

   **The RATE difference between the two environments is observed here. The
   "how long until it stops" figure is NOT, and an earlier version of this step
   asserted one. Corrected 2026-08-13.**

   What is well evidenced:

   - **Device B (TestFlight):** purchased 12 Aug, renewed daily, still live on
     13 Aug — the tester's five-minute rate ignored throughout.
   - **Device A (development sandbox, same tester rate of five minutes):** on
     13 Aug at 14:17 Apple's sheet read "Renews 13 August", i.e. the next
     renewal still ahead *that same day*. A daily cadence purchased the previous
     morning would already have rolled over to "Renews 14 August", so A was
     demonstrably on the accelerated rate and B was not.

   **What was WRONGLY claimed and is now withdrawn:** that a development-sandbox
   subscription stops after about six renewals, i.e. roughly thirty minutes. That
   figure came from documentation plus a single incidental observation — Device A
   appearing to expire the same day it was purchased on 12 Aug — and it did not
   survive a deliberate test. On 13 Aug the subscription was still renewing well
   past thirty minutes, across repeated background/foreground cycles and a
   force-quit. **The two observations are in tension and the reason is not
   established. Do not manufacture one.**

   **The operational rule that does hold: to end a sandbox subscription, CANCEL
   it. Do not wait for it to stop on its own.** Cancelling bounds the lapse to
   the end of the current period — minutes at an accelerated rate — and is
   deterministic in a way that waiting demonstrably is not.

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
| A2 | Complete setup; log a session with notes, photo, audio. **PROXY HALF REASSIGNED TO PHASE 4, 2026-08-14 — it would fail today, by design rather than by defect.** No proxy has ever been used in this project, and this row was never marked as unrun | Saves locally. **The local half stands and is covered by A1/A3 and every Group A run to date.** The "**no network traffic**" assertion is **not** true of the system as it stands: unshared sessions and their notes are currently uploaded (D-2), which is precisely what Phase 4's shared-only work removes. Asserting it now would either fail correctly or, worse, be waved through. **Phase 4 owns it**, and it is the natural acceptance test for shared-only uploads — the one measurement that distinguishes "we changed the upload code" from "nothing leaves the device". Run it with a proxy against a Solo install with no account at all |
| A3 | Import 3 PDFs to Scores; favourite one, rename one, attach a page range to a session | All persist across relaunch; attachment reopens at the right pages |
| A4 | Record a 30s video, background the app, return | Returns promptly. **Time it** — small-scale C-3 probe |
| A5 | Repeat with a 5-minute video | Hang or kill on foreground confirms C-3 |

### C-3 measurement — RESULT, 2026-08-14. SEVERITY DOWNGRADED to P3.

Device A, Release, three rungs, thresholds fixed beforehand. **The app was never
killed:** every line across all three rungs came from **PID 1180**, spanning
20:23 to 20:43, so the jetsam/watchdog outcome that would have made this P1 did
not occur even with 279 MB of video staged.

| Rung | Staged | Bytes | `mainActorMs` (each) | Median |
|---|---|---|---|---|
| 1 | 1 video (~30 s) | 19.1 MB | 51.6 · 53.2 · 54.8 · 56.6 · 50.8 | **53.2** |
| 2 | 2 videos (+~2 min) | 93.6 MB | 159.2 · 120.7 · 118.3 | **120.7** |
| 3 | 3 videos (+~5 min) | 278.7 MB | 472.7 · 322.9 · 266.7 | **322.9** |

**Verdict: 322.9 ms sits in the 250–1 000 ms band — P3.** Worst single
foreground observed was 472.7 ms, still under a second. `P1?` is retired.

**Scaling: roughly 35 ms fixed + ~1 ms/MB.** The per-MB cost is 2.8 at rung 1,
0.91 at rung 2 and 1.09 at rung 3 — so the fixed AVFoundation setup and decode
dominate at small sizes and the byte term takes over later. **The extrapolation
written after rung 2 predicted 220–300 ms and the observed median was 323 ms, so
it under-predicted** — recorded because the habit of checking a prediction
against the outcome matters more when the prediction was only roughly right.

**A cold/warm split appears and widens with size:** invisible at rung 1, ~40 ms
at rung 2, ~206 ms at rung 3. The first foreground after staging is always the
slowest.

**WHAT THE MILLISECONDS DO NOT CAPTURE, AND IT IS THE BETTER ARGUMENT FOR THE
PHASE 5 FIX.** The measurement is of *latency*; the mechanism also costs:

- **~279 MB held resident** in a `@State` array for as long as the attachments
  stay staged — not just during the foreground transition.
- **The same 279 MB written to `tmp` on EVERY foreground**, because
  `generateVideoThumbnail(from:id:)` writes a full surrogate copy before
  decoding. That is flash wear and battery on a path the user hits constantly,
  and it is invisible in a latency figure.

Neither makes it P1 today. Both are why the Phase 5 fix is worth doing on its
merits rather than only when a stopwatch complains.

**No refactor was performed**, per the committed rule: Phase 1 owned the
severity, Phase 5 owns the fix.

**Instrumentation removed the same day**, as the standing condition requires.
Verified as a pure deletion: `git diff` against the pre-probe commit is empty,
so the tree is byte-identical to its state before the probe existed. Debug and
Release both compile clean afterwards.

**One tooling trap worth keeping.** `zsh` has a `log` builtin, so `log show
--archive …` fails with "too many arguments" — and with `2>/dev/null` in the
pipeline that error is swallowed and an unreadable archive looks exactly like an
empty one. **Use `/usr/bin/log` explicitly, and never suppress stderr while
diagnosing why a log is empty.** `sudo log collect --device-name "<device>"
--output <path>` also refuses to overwrite an existing archive, so use a fresh
path per run.

### C-3 measurement — PROCEDURE AND STOPPING RULE, written 2026-08-14 before running

**What Phase 1 owns is the severity, not the fix.** C-3's mechanism is not in
doubt and was re-verified in source today; Phase 5 owns any change. This run
exists only to decide whether `P1?` becomes P1, P2 or P3.

**The mechanism, restated so the measurement targets the right thing.** On every
`scenePhase == .active`, inside the SwiftUI `onChange` closure and therefore
**synchronously on the main actor**, `hydrateTimerFromStorage()` calls
`Data(contentsOf:)` for each staged attachment — the **whole** video into RAM —
and then `generateVideoThumbnail(from:id:)` **writes that data back out** to
`tmp/<id>.mov` (`PracticeTimerView:4705`) and runs a synchronous
`AVAssetImageGenerator.copyCGImage`. So per foreground, per staged video: a full
read, a full write, and a synchronous decode, before the UI can respond.

**MEASURED ON DEVICE A, NOT THE SIMULATOR, AND THE REASON IS NOT CAUTION.** The
cost is disk I/O, memory pressure and AVFoundation decode. The simulator uses
the Mac's SSD and CPU and is not subject to jetsam or the watchdog, so it would
**systematically understate** every term and could not observe the one outcome
that would make this P1. A simulator number here would be worse than no number,
because it would look like evidence.

**Instrumentation: one line, temporary.** `[C-3] foreground mainActorMs=… videos=…
videoBytes=… otherBytes=…`, `os.Logger` at `privacy: .public` — Release-readable
because the rig runs Release, and a `#if DEBUG` probe would not exist in the build
under test (C-44's lesson). It reports a duration and byte counts only: no
filename, no id, no user content. It times the whole `.active` branch rather than
`hydrateTimerFromStorage` alone, because what C-3 is about is the user-visible
stall, and that whole branch blocks the main actor. **Standing condition: this
comes out as soon as the severity is recorded**, as `ActivationTrace` and
`MembershipTrace` did.

**Fixture constraint discovered while scoping this, and it shapes the run.** The
only route into `stageVideoURL` is the in-app `VideoRecorderView`
(`PracticeTimerView+Sheets:254`) — there is **no import-from-Photos path for a
staged video** — so a "5-minute video" fixture means genuinely recording for five
minutes. The run is therefore designed to escalate and stop early rather than to
start at the worst case.

**PROCEDURE — escalate, and stop at the first rung that settles it.**

| Rung | Fixture | Action |
|---|---|---|
| 1 | ~30 s video staged, unsaved | background → foreground ×3, record `mainActorMs` |
| 2 | ~2 min | as above |
| 3 | ~5 min | as above — only if rungs 1–2 have not already crossed a threshold |

Three foregrounds per rung, because the first may be warmed differently by the
recorder having just written the file. **Record the median, and report all three.**

**STOPPING RULE — thresholds fixed before any number is seen.**

| Observed at any rung | Verdict |
|---|---|
| Watchdog kill, or app visibly frozen > 5 000 ms | **P1 confirmed.** Stop immediately; the fix is Phase 5's and becomes a release blocker |
| 1 000 – 5 000 ms | **P2.** A real, user-visible stall. Stop escalating; Phase 5 fixes on UX grounds |
| 250 – 1 000 ms | **P3.** Perceptible but tolerable. Record and move on |
| < 250 ms at rung 3 | **Severity overstated — downgrade to P3** and record the numbers as the reason |

**Do not refactor on the strength of this, whatever it shows.** Phase 5 owns the
fix, and the register's `1 (measure) / 5 (fix)` split is deliberate. The one thing
this run may change is the severity and the priority Phase 5 gives it.

**No production Supabase access is involved at any point.**

## Group B — Connected acquisition

| # | Steps | Expected |
|---|---|---|
| B1 | Profile → Explore Connected → Continue → Monthly → purchase | Sandbox purchase, then SIWA, then Connected active |
| B2 | **C-13 probe:** repeat B1 several times on a slow or throttled connection. **PARTIALLY RUN 2026-08-12 on TestFlight build 131 (Device B) — see the result note, and read step 4 of the development loop before planning a re-run.** The repetition this row asks for **was not runnable**: it assumes a clean first-purchase state can be restored between attempts by clearing the tester's purchase history, and that assumption is false. The single attempt that did run was a genuine distributed-artifact purchase and passed | Purchase must always complete through to sign-in. A permanently spinning Continue button confirms the unterminating loop. **First-run coverage, not a re-test:** the loop made `refreshEntitlement`'s forced re-entry unreachable, so the second, fresh entitlement refresh has never executed in any build. Watch for a wrong entitlement state after a verified purchase — "Purchase verified but no active membership" — as well as for a hang. **This has now been observed: C-38, 2026-08-11.** The alert appears immediately after a successful purchase and Connected activates on the next foreground, so a tester who backgrounds the app before re-reading the screen will record a pass. When running this row, treat the alert itself as the failure and do not let the subsequent recovery erase it |
| B3 | Check pre-existing Group A sessions | Still present, still private. Confirm none appear in another account's feed |
| B4 | Create a session, tap Save without touching Visibility | Observe whether it shares — D-1 behaviour check |
| B5 | Delete and reinstall; Restore Purchases. **iOS-level app deletion only — never "Erase All Études Data", which is a backend account deletion and would destroy the state this row checks survives.** **CORRECTED 2026-08-12: this row asks for a step that is unreachable on a successful run, and the reason is by design.** There are two outcomes, and the *better* one has no Restore button. **(a) Automatic recovery — the expected pass.** The Keychain survives app deletion and the entitlement is account-bound, so the reinstalled app restores identity and entitlement unaided and lands in Connected. **(b) Automatic recovery fails** — the app sits in Solo, and only then is Restore Purchases reachable. `restorePurchases()` has exactly one UI entry point, `MembershipSelectionView:217`, reached only via Profile → *Explore Connected* → Continue; `ProfileView:317` renders that section only in the `else` branch of `canShowConnectedAccountManagement`, which is true only when `mode == .connected`. **So Restore is unreachable to anyone already Connected — correct, since the control exists for the state where recovery did not happen.** Do not manufacture a failure state to expose the button. Record Restore as *not applicable* whenever (a) occurs | **(a) is the pass**: entitlement and identity restored automatically, Connected reactivated, no SIWA sheet, no blank-chevron state, no Solo fallback. Local journal and Scores are **empty and correctly so** — the container is gone. **Note after Phase 2 (C-4): this expectation does not change.** Deleting and reinstalling an app is not a backup restore; nothing is reinstated either way. The old reason clause said the loss was permanent *because* media did not participate in backup, which stops being true after Phase 2 while the expected outcome stays the same. Do not "fix" this row. The backend must be **untouched**: verify against a count baseline recorded *before* the run, and treat any new `auth.users` row as a failure — it would mean the reinstall minted a new account instead of restoring the existing one |
| B6 | **PASS — 2026-08-12, TestFlight build 131, Device B.** Signed out normally; local journal, Scores and local attachments all intact; no backend or account deletion; signed back in with SIWA and Connected restored, with existing local data, backend posts and follow relationships unchanged. **Confirmed backend-side rather than from the screen:** `auth.users` for Device B still shows `created_at = 2026-07-23`, so sign-in restored the *same* row rather than minting a new one — the failure this row exists to catch. Note what was **not** covered: nobody checked the Location field across the sign-out, so C-27 is untouched by this run | Sign out, sign back in | Connected restored; no data loss; no account deletion |
| B7 | **C-36 probe — does the Solo location survive joining?** Set a Location (and a Name) in Solo. Join Connected as in B1. Watch the Location field at the instant sign-in completes, then query `account_directory.location` for the new user **and** check what a second account sees on your profile | The field must not blank out, and the column must hold the location, not `NULL`. Blank field is the read at `ProfileView:1687`; `NULL` in the column is the debounced write ~650 ms later. Both can occur while Profile *later* shows the location again, because `AuthManager:529` repairs the local copy — so **the column is the verdict, not the screen**. Repeat once with the Name field left empty: that path skips the publish entirely and should fail the same way without any race |

### Pre-lapse baseline — 2026-08-12 12:5x, taken while Device B was still entitled

Device B's TestFlight subscription will expire on its own. **C-26's claim is that
a lapse deletes nothing** — no server-side authority exists to act on expiry, and
since C-1 the client has none either — so this is the prediction to check
afterwards. Recorded now because it cannot be taken after the fact.

| | 12 Aug ~12:52 | **13 Aug 11:20 — use this one** |
|---|---|---|
| `auth.users` | 16 | 16 |
| `account_directory` | 16 | 16 |
| `posts` (Device B's own) | 98 (3) | **99 (4)** |
| `follows` (edges touching Device B) | 8 (6) | 8 (6) |
| `post_comments` | 4 | 4 |
| `connected_attachments` rows | 35 | 35 |
| `attachments` storage objects | 10 | **11** |
| `avatars` storage objects | 4 | 4 |

Device B's directory row, all present: display name, account ID, **location**,
avatar key, **8** instruments, `lookup_enabled` and `follow_requests_enabled`
both true. `auth.users.created_at = 2026-07-23 13:42:16Z` — the value that
proves identity was not re-minted.

**Re-baselined 13 Aug 11:20, and the reason is the Études Dev trap this plan
already warns about.** Between the two readings the developer recorded two real
practice sessions in **Études Dev** on Device B. That is a different app with a
different bundle ID and its own container — but SIWA identifiers are
team-scoped, so it writes to the **same backend Account B**, and its writes land
in exactly the counts a lapse run is watching. The deltas (+1 post, +1 storage
object, +2 instruments) are entirely its work. **Nothing was deleted, so C-26's
claim is untouched by this.**

The lesson is operational rather than a finding: **the second client is
invisible in the numbers.** A reading taken while Études Dev is in use cannot
distinguish its writes from the app under test, and "two sessions recorded, one
post created" is the kind of discrepancy that would send someone hunting a
defect that does not exist. Keep Études Dev closed for the remainder of this
run.

**Pre-lapse device state, 2026-08-12 12:57.** The subscription was **cancelled
deliberately**, to convert an open-ended run of daily TestFlight renewals into an
expiry on a known date — cancelling is the tool for *observing* a lapse, as
distinct from resetting to a first-purchase state, which it does not do. Apple's
sandbox sheet then read **"You have cancelled your subscription. Your
subscription ends on 13 August"**, offering *Renew £4.99/month*. **Études
remained Connected immediately afterwards**, which is correct: cancellation stops
renewal and does not withdraw a still-active entitlement.

Device B is being left untouched from that point. When the lapse occurs, the app
state is to be **observed before anything is manipulated** — no relaunch, no
sign-out, no Profile edits — so that what is recorded is the app's own response
to expiry rather than a response to being prodded.

**Every one of these must be unchanged after the lapse.** Any movement
contradicts C-26 and is a finding. On the device, expect: Connected withdrawn,
app drops to Solo, and local journal, Scores, media, profile name, avatar,
location, instruments and settings all survive untouched — C-1's verified
behaviour, which has never been observed on the distribution artifact.

**Do not run "Erase All Études Data" on Device B when it lapses.** That is
C-35's condition and it would destroy the account and the two-device control
fixture with it. C-35 belongs on a disposable account.

### C-35 destructive run — RESULT, 2026-08-13. PASS on every assertion.

Device A deleted **while lapsed, without re-subscribing**. All eight counts,
all nine A-residue checks and both discriminators matched the prediction below,
which was committed before the erase.

**Counts:** `auth.users` 16→15, directory 16→15, posts 100→98, comments 6→3,
`connected_attachments` 36→35, attachment objects 13→10, avatar objects 4→3,
follows 8→6. **A residue: zero on all nine.** **Account B untouched** — 4 posts,
6 attachment objects, directory row and avatar all unchanged, with comments
authored 3→2, the single loss being the predicted cascade.

**The two discriminating assertions both held.** `b105d553` — A's **live**
Connected attachment to B — was deleted **with its storage object**, which is
the row the previous function explicitly preserved; that is what distinguishes
the deployed semantics from their predecessor rather than merely re-passing a
test the old code would also have passed. And `944a70cb` — B's own reply on B's
own post, merely addressed to A — **survived**, proving the new comments
predicate did not overreach into B-19's territory. A predicate that wrongly
reached `recipient_user_id` would have passed every other line in the table.

**IT TOOK TWO ATTEMPTS, AND THE FIRST FAILURE IS THE MOST VALUABLE THING HERE.**
Attempt one was refused with *"Études Connected is not currently available.
Please try again"* — a retry that could never succeed. `performDeleteAccount`'s
second guard read `BackendEnvironment.shared.isConnected`, a runtime
service-selection mode that `AppModeManager` sets to `.localSimulation` for
`.solo`, and `AppMode` is resolved from `isEntitled`. So C-35's defect existed
twice, and the second instance was an **entitlement dependency laundered through
a `UserDefaults` key**. The deletion path had been audited for `isEntitled`,
`AppMode` and `canShowConnectedAccountManagement` and passed, because it
contained none of them by name. **No grep could have found it; only running it
did.** Nothing was deleted by the failed attempt — it returned before any
backend call — so the fixture survived intact and was reused without restaging.
Fixed at `863f2a9` by gating on `BackendConfig.isConfigured`, which is what the
request actually needs and is independent of `AppMode`.

**Device side CONFIRMED, and it is not provable from the counts above because
none of it has a backend representation.** On Device A the journal and the Scores
library are both **empty** and the app returned to onboarding — so the local
factory reset reached Scores, which is C-2's fix still holding on a path C-2
never tested. On Device B **the photo A sent is gone from the inbox, and A's
comment is gone from the thread** — the revised B-1 and B-3 semantics visible in
the UI rather than inferred from a row count, and the clearest demonstration that
this is a product behaviour change and not merely a database one.

### C-35 destructive run — PREDICTION, written 2026-08-13 before the erase

Device A (`92d6b718`) deleted while **lapsed**, without re-subscribing, against
the revised deletion semantics deployed as `c4f6d0f` (version 6). Account B
(`dfaf8d18`) is the control. Written first so the check is binary — D14's rule.

**Fixture staged, all six comment cases present:**

| Comment | Post owner | Author | Recipient | Fate |
|---|---|---|---|---|
| `6ed7b788` | **B** | **A** | B | **DELETED — revised B-3** |
| `e9325a3c` | A | A | B | deleted (author step, and cascade) |
| `68691822` | A | **B** | A | **deleted BY CASCADE ONLY** with A's post |
| `944a70cb` | **B** | **B** | **A** | **MUST SURVIVE — B-19 discriminator** |
| `4862883b` | B | B | dead | must survive |
| `f0daf6d7` | B | dead | B | must survive (B-22 residue) |

**Predicted counts:**

| | Before | After |
|---|---|---|
| `auth.users` | 16 | **15** |
| `account_directory` | 16 | **15** |
| `posts` | 100 | **98** |
| `post_comments` | 6 | **3** |
| `connected_attachments` | 36 | **35** |
| `attachments` objects | 13 | **10** |
| `avatars` objects | 4 | **3** |
| `follows` | 8 | **6** |
| A: posts / comments / follows / comment_views | 2 / 2 / 2 / 1 | **0 / 0 / 0 / 0** |
| **B: posts** | 4 | **4 — unchanged** |
| **B: comments authored** | 3 | **2** — `68691822` cascades with A's post |
| **B: attachment objects** | 6 | **6 — unchanged** |
| **B: attachment rows** | 5 | **4** — the A→B row goes |

**Exact objects to be removed (4):**

```
attachments/users/92d6b718…/CC2B351B…/F453E774….jpg      post attachment
attachments/users/92d6b718…/DCE002F7…/2ECDA3A3….jpg      post attachment
attachments/users/92d6b718…/connected/30a975b5….jpg      Connected send to B  <- revised B-1
avatars/users/92d6b718…/avatar.jpg                       avatar
```

**The two assertions that make this discriminating.** `b105d553` — A's live
Connected attachment to B, `deleted_at IS NULL` — **must be deleted along with
its object**. Under the previous semantics it was explicitly *preserved*, so
this single row distinguishes the deployed function from its predecessor. And
`944a70cb` **must survive**: a predicate that wrongly reached `recipient_user_id`
would pass every other assertion in this table and fail only that one.

**Device-side, verified separately because none of it has a backend
representation:** both Scores PDFs gone, both journal sessions gone, the photo
gone, app at first-launch state. **Expected NON-effect:** any copy of A's photo
already downloaded to B's device persists — backend deletion cannot reach
another device, which is why the confirmation copy says so.

### Lapse result — 2026-08-13 ~11:20, TestFlight build 131, Device B

The subscription cancelled on 12 Aug at 12:57 expired as scheduled. **PASS on
both claims under test, and both for the first time on the distribution
artifact.**

**Backend: nothing deleted, nothing added.** Two reads taken — one *before*
Device B foregrounded, one *after* it had launched, run, and had SIWA performed
on it — and every value is identical to the re-baseline: `auth.users` 16,
`account_directory` 16, `posts` 99 (Device B's own 4), `follows` 8 (6 touching
B), `post_comments` 4, `connected_attachments` 35, `attachments` objects 11,
`avatars` objects 4, Device B's instruments 8, and
`auth.users.created_at = 2026-07-23 13:42:16Z`. **C-26's retention claim is now
observed rather than argued, and C-1's removal of client expiry authority held
on the artifact beta testers install.**

**Device: Connected withdrawn, identity kept.** The app resolved to Solo, and
**did not require Sign in with Apple** — identity survived the lapse
untouched, matching C-1's recorded behaviour. Profile name, avatar and location
all present. SIWA was then performed *voluntarily*, to see whether Manage
Membership would open; it did not, and the app correctly **remained in Solo**,
because identity without an entitlement resolves to Solo by design.

**Manage Membership is unreachable in Solo, and that is the C-35 gate, not a new
finding.** `ProfileView:317` renders `appSettingsSection` only when
`canShowConnectedAccountManagement` is true, i.e. `mode == .connected` — the
same gate that hides Restore Purchases from Connected users, here hiding account
management from a lapsed one. C-35 already owns this and is unchanged. Note the
lapsed member is *not* stranded: Explore Connected → Continue still reaches
`MembershipSelectionView`, which offers both purchase and Restore Purchases.

**What this run does NOT establish, stated so a green result is not read as
broader than it is.** C-1 also claims the **local journal, Scores and media
survive expiry**, and **this run cannot speak to that**: B5 deleted the Release
container the previous day, and the two practice sessions recorded since went
into Études Dev, a different container. There was nothing local to survive.
Profile name, avatar and location showing is likewise consistent both with local
preservation *and* with re-hydration from `account_directory` via
`fetchSelfRow`; this run does not discriminate between them. The local-durability
half of C-1 remains verified only by the 2026-08-09 development-build run.

### Pre-B5 backend baseline — 2026-08-12, recorded *before* the run

B5 deletes the app at the iOS level and reinstalls. **App deletion is not
account deletion**, so the prediction is that every one of these is unchanged
afterwards. Written down first, so the check is binary rather than a reading of
the aftermath — D14's lesson.

| | Baseline |
|---|---|
| `auth.users` | 16 |
| `account_directory` | 16 |
| `posts` (Device B's own) | 98 (3) |
| `follows` | 8 |
| `post_comments` | 4 |
| `connected_attachments` rows | 35 |
| `attachments` storage objects | 10 |
| `avatars` storage objects | 4 |

**Any movement here is a failure**, and specifically a 17th `auth.users` row
would mean the reinstall minted a new account instead of restoring the existing
one — the worst outcome this row can produce.

### B5 result — 2026-08-12, TestFlight build 131, Device B

**Reinstall half: PASS, via automatic recovery.** Release/TestFlight Études
deleted at the iOS level (Études Dev untouched), build 131 reinstalled from
TestFlight. Onboarding appeared briefly and dismissed itself, then the app landed
directly on the timer **in Connected, already signed in** — no SIWA sheet, no
blank-chevron state, no Solo fallback. **That re-verifies C-24's fix on the
distribution artifact**, where it had previously been verified only on a
development build and under the synthetic StoreKit configuration.

**The backend was untouched, checked against a baseline recorded before the
run.** All eight counts identical: `auth.users` 16, `account_directory` 16,
`posts` 98 (Device B's own 3), `follows` 8, `post_comments` 4,
`connected_attachments` 35, `attachments` objects 10, `avatars` objects 4.
**No 17th user row** — the reinstall restored `dfaf8d18…` rather than minting a
new account, which is the worst outcome this row can produce. Device B's
directory row also survived intact: display name, account ID, location, avatar
key, six instruments, both flags true.

**Restore Purchases: NOT APPLICABLE, not skipped.** Automatic restoration
succeeded, and the control is unreachable from Connected by design — see the row
above for the mechanism. Opening Manage Membership reaches Apple's own sandbox
sheet (headed `[Sandbox]`, £4.99/month, renewing 13 August, offering only Cancel
Subscription), which is Apple's UI and has no Restore button by nature. A
failure state was deliberately **not** manufactured to expose ours.

**C-36 probe on this path — did NOT reproduce, and that is informative.** The
empty container after reinstall is exactly the condition C-36 needs, so Profile
was opened deliberately and left on screen for over a minute. Location rendered
**"London" immediately, with no blank state at any point**, and
`account_directory.location` was still populated afterwards. The reason is
structural: a reinstall has an existing `account_directory` row, so hydration
seeds the user-scoped local value from the backend before Profile mounts, and
`ProfileView:1687` reads a populated field — no change, no debounce, no `NULL`
write. A **first join** has no backend row to hydrate from, which is precisely
the absence C-36 turns on. **B7 still owns the finding; this run does not
weaken or close it.**

**Two observations, neither a defect.** The brief onboarding flash is the empty
container being detected and then superseded once Keychain identity restored.
And the feed correctly shows posts originally authored through the **Debug**
client under Account B — because SIWA identifiers are team-scoped, so Études Dev
and the Release install have always been two clients on one backend account.
No container crossover is implied, and the deleted container could not have
supplied them.

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

### C-28 / C-48 destructive run — RESULT, 2026-08-14. PASS on every assertion.

Device A, Release from `ea0beb2`, built and installed from the clean tree so the
binary provably carried the fix. Every container, log and backend assertion below
matched the prediction committed at `995603f` before the erase.

**Container — all target paths absent.** `ReceivedConnectedAttachments/` gone,
`CommentsStore.json` gone, `tmp/…SelectedPages….pdf` gone, `Documents/Scores/`
gone, both local media gone. What remains is an empty `Documents/`, empty
`MOTIVO/` and `Profiles/`, `tmp/TemporaryItems`, and a rebuilt Core Data store.
**The first three would all have survived on the pre-fix build** — they are the
test.

**Release log, in the predicted order:**

```
[C-44] revocation reason=delete-account outcome=revoked
[LocalFactoryReset] begin (stage 5c) reason=erase-all-etudes-data-connected
[C-28] localReset receivedAttachmentsRemoved=2 temporaryFilesRemoved=1
[C-48] localReset commentsStoreFileExisted=true
```

**The counts are the result, not the decoration.** `receivedAttachmentsRemoved=2`
and `commentsStoreFileExisted=true` establish that the files were present when the
wipe ran — which no post-hoc absence check can. `temporaryFilesRemoved=1` matched
the predicted 1-not-2 exactly, because `tmp/TemporaryItems` is a directory with no
path extension. Revocation succeeded and preceded the reset; no manual-revocation
notice appeared, which is itself an assertion (`didRevoke == true`).

**Backend 9/9.** `auth.users` 16→15, `account_directory` 16→15,
`connected_attachments` 33→31, `follows` 8→6; `posts` 98, `post_comments` 2,
`post_comment_views` 9, `avatars` 3 unchanged. A is zero on every per-account
measure. B intact: 4 posts, directory row, 8 objects.

**`attachments` objects stayed at 10, as predicted.** Both received objects live
under the *sender's* prefix and A's sweep is scoped to `users/<A>/`, so they
survive unreferenced the moment their rows go — D14's expected residue, +2 on
B-8's Phase 4 pile. **A count of 8 would have meant the function reached outside
the departing member's prefix.**

**Both overreach checks held:** the PDF exported to Files and the photo saved to
Photos both survived. The boundary is verified in both directions.

**ONE DEVIATION — filed as C-49, and it is navigation only.** The app landed on
the journal rather than first-launch onboarding. A force-quit and relaunch showed
onboarding correctly, which both proves the reset cleared persistent state and
eliminates the competing mechanism: the onboarding gate lives only in
`appRoute.route == .timer`, and dismissing Profile revealed `.content`
underneath. No data implication; every other assertion on this run passed.

**B-14 closed incidentally.** The `connected_attachments` insert policy requires
an approved follow, so staging this fixture forced a real request → approval
cycle — the runtime check B-14 had been holding Device B for. See its row.

### C-28 / C-48 destructive run — PREDICTION, written 2026-08-14 before the erase

Device A (`44a6018e…`, directory `c45verification`) deletes its Connected account
via **Delete Account & All Études Data**, on a Release build installed from
`ea0beb2`. Account B (`dfaf8d18…`) is the control. Written first so the check is
binary — D14's rule.

**The verdict is the container, not the screen.** `ReceivedConnectedAttachmentStore.items`
is in-memory and empty after any reset, so a broken implementation and a fixed one
look identical in the UI. Same trap as D13 and C-34.

**Two fixture states are SIMULATED, NOT PROVOKED, under the D13 precedent.**

1. **`CommentsStore.json`** — a synthetic file (fabricated bodies, non-sensitive
   placeholder ids) placed in A's container. The real write path is **unreachable
   in the shipping UI** (see C-48's four-link proof), so it cannot be provoked at
   all on a current install. Genuine legacy residue *was* observed read-only on
   Device B (7 KB, 2026-01-10); none of that file's data was copied.
2. **`tmp/SYNTHETIC-QA-FIXTURE-SelectedPages-….pdf`** — placed directly. The state
   is **source-proven reachable** via a real supported path: A sends a
   page-selected Score subset to another Connected member
   (`ConnectedAttachmentShareUI:488`), which exports to `tmp/` and never cleans up.
   Provoking it would have required a second Études Dev cycle and another follow
   direction, and was judged not worth it.

**In both cases the assertion under test is the RESET's behaviour given the state,
not the creation path.** D13's reasoning exactly, and stronger here for C-48,
because the state was observed in production first.

**Container baseline, read 2026-08-14 12:04:**

| Path | Baseline |
|---|---|
| `…/ReceivedConnectedAttachments/83704256….pdf` | 53 KB — received original, adopted |
| `…/ReceivedConnectedAttachments/f207e3b0….jpg` | 306 KB — received original, not adopted |
| `Documents/Scores/057BB98E….pdf` | 53 KB — **the adopted copy; same size, same minute as the original** |
| `Documents/Scores/40712B3C….pdf` | 11.2 MB — pre-existing Score |
| `Documents/EBF6F8A7….mov` | 5.3 MB — local attachment |
| `Documents/FA313C95….jpg` | 12.1 MB — local attachment |
| `Library/Application Support/CommentsStore.json` | 1 KB — synthetic |
| `tmp/SYNTHETIC-QA-FIXTURE-SelectedPages-….pdf` | 642 bytes — synthetic |

**Backend baseline:** `auth.users` 16, `account_directory` 16, `posts` 98,
`follows` 8, `post_comments` 2, `connected_attachments` 33,
`post_comment_views` 9, `attachments` objects 10, `avatars` objects 3.
A's own measures: 0 posts, 0 comments authored, 0 addressed, **2 follows**
(both directions, both approved, created 10:21), **2 received**, 0 sent,
0 comment views, **0 storage objects under A's own prefix**, no avatar.

**PREDICTED CONTAINER AFTER THE ERASE**

| Assertion | Expected | Fails on the pre-fix build? |
|---|---|---|
| `ReceivedConnectedAttachments/` | **absent** — both originals gone | **YES — 2 files survive** |
| `CommentsStore.json` | **absent** | **YES** |
| `tmp/…SelectedPages….pdf` | **absent** | **YES** |
| `Documents/Scores/` | empty — both PDFs gone | no (C-2 holds) |
| `Documents/*.mov`, `*.jpg` | absent | no |
| App state | returns to onboarding | no (C-46 holds) |

**PREDICTED RELEASE LOG — the discriminator the filesystem cannot supply.**
An empty directory afterwards is produced equally by "the wipe ran", "the wipe
threw" and "this build predates the wipe":

```
[C-44] revocation reason=delete-account outcome=…      (BEFORE the reset)
[LocalFactoryReset] begin (stage 5c) …
[C-28] localReset receivedAttachmentsRemoved=2 temporaryFilesRemoved=1
[C-48] localReset commentsStoreFileExisted=true
```

`temporaryFilesRemoved=1` and not 2: `tmp/TemporaryItems` is a directory with no
path extension and cannot match the sweep.

**PREDICTED BACKEND**

| | Before | After |
|---|---|---|
| `auth.users` | 16 | **15** |
| `account_directory` | 16 | **15** |
| `connected_attachments` | 33 | **31** — B-9 step 1, A is recipient on both |
| `follows` | 8 | **6** |
| `posts` | 98 | **98 — unchanged** |
| `post_comments` | 2 | **2 — unchanged** |
| `post_comment_views` | 9 | **9 — unchanged** |
| `attachments` objects | 10 | **10 — UNCHANGED, see below** |
| `avatars` objects | 3 | **3 — unchanged** |

**THE STORAGE COUNT NOT MOVING IS A PREDICTION, NOT AN OVERSIGHT.** Both received
objects live under `users/dfaf8d18…/connected/` — the **sender's** prefix — and A's
erase sweeps only `users/<A>/`, where A has zero objects. So both survive as
unreferenced residue the moment their rows are deleted. That is D14's documented
"expected residue, not a failure"; it adds two objects to **B-8**'s Phase 4 pile
and must not be filed again. **A storage count of 8 would mean the function had
reached outside the departing member's prefix, which would be a serious defect.**

**EXTERNAL SURVIVORS — the only overreach checks in this run**

| | Expected |
|---|---|
| The PDF exported to **Files** | **SURVIVES** |
| The photo saved to **Photos** | **SURVIVES** |

Anything else disappearing from Files or Photos means the reset reached outside
Études-managed storage, which the settled product rule forbids.

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

**DISPOSITION OF C1–C4, C11 AND C12 — recorded 2026-08-14 at the Phase 1 exit.**
These six rows carried no execution status of any kind: not run, not deferred,
not blocked. That is a gap in the *record*, not necessarily in the coverage, and
the two are separated below. **No new QA was manufactured to tick them.** Each is
marked satisfied by later evidence, superseded by architecture, or given a named
later-phase owner — and where only part of a row is covered, the uncovered part
is named rather than absorbed. C5–C10 are Phase 3 as always and are untouched by
this pass.

| # | Steps | Expected |
|---|---|---|
| C1 | Cancel the sandbox subscription, let it lapse, foreground the app. **SATISFIED IN PART BY LATER EVIDENCE — the lapse run, 2026-08-13, TestFlight build 131, Device B; see "Lapse result" above.** Backend read twice, once before the device foregrounded and once after it had run: every value identical, nothing deleted, `created_at` unchanged. App dropped to Solo, no "Membership Ended" alert, identity kept. **The local-data half of this row is NOT covered by that run and must not be read as if it were** — Device B had no local journal to lose, because B5 had deleted the container the previous day. That half rests on the 2026-08-09 development-build run and is recorded on C-1 as such. **No proxy was used**, so "no `delete_account_v1` call is issued" is established structurally (C-1 removed the pipeline; see C12) rather than observed on the wire | App drops to Solo. Local sessions, Scores and attachments **all intact**. **No "Membership Ended" alert** — the client is no longer authoritative about membership state, so it makes no claim about it. The **backend account and posts survive**: no client-initiated cleanup exists, and server cleanup arrives with Phase 3. **No account-deletion request is issued from the device** — confirm via proxy that no `delete_account_v1` call occurs |
| C2 | Repeat C1 with the device in Airplane Mode when foregrounding, then re-enable networking. **DESTRUCTIVE HALF SUPERSEDED BY ARCHITECTURE; RECOVERY HALF → PHASE 3.** The capability this row probes for **no longer exists in the client**: C-1's fix at `6109116` removed the detect → arm → gate → delete pipeline outright, `handleMembershipState` does nothing but `applyActivation`, and C-28's convergence check found exactly two callers of `LocalFactoryReset.perform`, both user-initiated Erase All. A capability that was removed cannot be probed for by provoking it — the honest check is the structural one (C12), and inventing a device run here would prove only that a deleted code path did not execute. **What is genuinely still worth observing is the reversible half — that access returns cleanly once connectivity is restored — and that belongs to Phase 3**, which changes what "the entitlement resolves" means and will re-exercise this path anyway | **C-1 probe.** A transient or unverifiable negative read *may* drop access to Solo — that is permitted, because it is reversible and invariant 3 allows reversible decisions on client evidence. The invariant under test is that **nothing irreversible or destructive follows from client entitlement evidence**: no `delete_account_v1` call, no Connected identity or session cleared on the device, backend account and posts intact. Access must return once connectivity is restored and the entitlement re-resolves |
| C3 | While entitled, sign out of the App Store account in iOS Settings, then foreground Études. **SAME DISPOSITION AS C2** — destructive half superseded by C-1's structural removal of the client deletion pathway; recovery half owned by Phase 3. **One partial observation exists already:** on 2026-08-13 SIWA was performed voluntarily on the lapsed Device B and the app correctly **remained in Solo**, identity intact, backend untouched — an un-entitled session that resolved without destroying anything | **C-1 probe.** Same invariant as C2: dropping to Solo is permitted, destroying anything is not. Backend account survives, Connected credentials remain on the device, and access returns when the entitlement resolves again |
| C4 | Force-quit during the drop to Solo, relaunch. **SATISFIED BY LATER EVIDENCE — the 2026-08-09 genuine-lapse run, recorded on C-1.** The lapse was observed across a force-quit and relaunch, with `auth.init appleID=true backendID=true token=true` on the far side and the Supabase account still live, proven afterwards by Erase All finding and deleting it | The mode transition completes idempotently. Still no client-initiated deletion. Local data intact |
| C5 | Let expiry occur, then re-subscribe **before** the server has processed cleanup | Entitlement restored; Connected reactivated; Connected data intact. The server must recognise the renewal and abandon any pending cleanup |
| C6 | Failed payment on renewal (Billing Grace Period) | Entitlement retained throughout grace. App stays Connected. No cleanup at any point during grace |
| C7 | **Server authority:** let a subscription expire and grace lapse, then **never launch the app again**. Inspect the backend after the cleanup window | Domain 3 cleanup completes server-side with no device involvement. `posts`, `post_shares`, `connected_attachments`, storage objects and `account_directory` handled per the settled decision. **CORRECTED 2026-08-14 — this row used to say comments authored on others' posts are "retained", which was the pre-2026-08-13 rule and is now wrong.** Expiry cleanup must match `delete_account_v1`'s deployed semantics: comments the departing member **authored** are deleted (`author_user_id` alone), and comments authored by *others* and merely addressed to them **survive** (B-19 — never add `recipient_user_id`). Note the separate question this row does **not** settle: whether expiry cleanup should be identical to account deletion at all is Phase 3's design decision, and if it diverges, say so here explicitly rather than inheriting by default |
| C8 | Deliver the same expiry notification twice (replay) | Second delivery is a no-op. No double deletion, no error surfaced, cleanup state unchanged |
| C9 | Deliver a malformed or unsigned notification | Rejected on signature verification. Nothing is deleted |
| C10 | **Decoupling:** with cleanup already complete server-side, launch the app while still un-entitled | App is in Solo, local journal intact, no crash and no attempt to reach Domain 3 endpoints. Re-subscribing produces a clean new Connected identity |
| C11 | ~~**C-19 probe:** set a location while Connected, let membership expire, foreground the app **without opening Profile**~~ **SUPERSEDED BY ARCHITECTURE — C-19 is Resolved, and the mechanism this row probes for no longer exists.** The mounted-`ProfileView` dependency was a *consequence* of the expiry path clearing identity; since C-1, expiry does not clear `backendUserID` at all, so `profile.<backendUserID>.location` stays resolvable and the only code that deletes it is `wipeLocalIdentityForFactoryReset`, reachable solely from Erase All. Corroborated on device: the 2026-08-09 lapse occurred with no `ProfileView` mounted and `auth.init` reported `backendID=true` on relaunch. **Related but NOT covered here:** C-27, the sign-*out* direction, which is a live P3 owned by Phase 5, and which B6 explicitly did not check | Superseded. Location survives expiry unconditionally, with no mounted-view dependency |
| C12 | Confirm by code inspection and by proxy that Erase All is the **only** client-initiated destructive action remaining. **CODE-INSPECTION HALF SATISFIED; PROXY HALF → PHASE 3.** The inspection has been done three times over and by three different routes, which is why this half is closed rather than merely assumed: C-1's fix removed every client entitlement path to `deleteCurrentConnectedAccount`; C-35's work re-audited the deletion path and found the *second* gate that a name-based grep could not see; and C-28 established by source that `LocalFactoryReset.perform` has exactly two callers, `ProfileView:1671` (Solo) and `:1744` (Connected), differing only in a `reason` string. **The proxy half has never been run — no proxy has been used anywhere in this project — and it is assigned to Phase 3**, which is when a *new* client→deletion path could plausibly appear, since server-side authority is the change that would introduce one. Run it then as a regression on the whole client, not as an archaeology exercise now | Invariant check. Any client path to backend deletion other than Erase All is a regression |

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
| D7 | **B-3 — DELETION, not retention. THIS ROW WAS REWRITTEN 2026-08-14; ITS PREVIOUS EXPECTED RESULT IS NOW WRONG AND MUST NOT BE RUN.** Until 2026-08-13 this row asserted that A's comment on B's post **survived** A's erase, which was correct under the rule then in force. The rule was revised on Apple's account-deletion guidance: a departing member's own backend UGC is deleted. Anyone running the old wording would record a false failure, or "fix" the function to match it. **ALREADY EXECUTED — C-35 run, 2026-08-13, PASS.** A commented on B's post; A performed Erase All; the row was checked in the database and the thread was viewed on Device B. Do not re-run: this was verified against a prediction committed before the erase, with all six comment cases staged at once. See "C-35 destructive run" above | A's comment is **GONE** — `6ed7b788`, deleted by the `author_user_id` predicate, and observed absent from the thread on B's screen rather than only from a row count. `post_comments` 6→3, B's authored count 3→2. **The rendering half of this row is MOOT** — the comment does not survive, so there is no unresolvable *author* to render. The surviving-recipient case is D8's |
| D8 | **B-19 retention. DATABASE HALF DONE TWICE — 2026-08-11 and again on the C-35 run, 2026-08-13, which is the discriminating one.** A comments on B's post; B replies to A using the owner reply; A performs Erase All. Do not re-run it: `944a70cb` survived an erase whose whole point was that A's own comments go, so the two revisions are proven separable. **RENDERING HALF — OPEN, AND IT NEEDS NO STAGING. A live fixture already exists in production.** The follow prerequisite this row used to carry is **withdrawn**: the C-35 run rendered the thread on Device B after A's deletion, so the "feed is empty" blocker is disproved. **Fixture, confirmed read-only 2026-08-14 — two rows, both the exact shape, both on public posts owned by Account B (`dfaf8d18`), both authored by B, both with a recipient that is absent from `auth.users` and has no `account_directory` row:** `944a70cb` on post `81e080cc` (recipient `92d6b718`, Device A's identity deleted 2026-08-13) and `4862883b` on post `0671771f` (recipient `5a32e9e7`). Reach them as **Account B**, which is the post owner — `posts_select_public_or_owner`'s owner clause needs no follow edge, and B currently has **zero** approved outgoing follows, so this incidentally settles C-39's contradiction too. **Route: Études Dev under a synthetic entitlement**, the same route used for the C-28 staging and the B-6 regression — it reaches Account B without spending Device B's lapsed Release fixture and without a purchase. **Premise narrowed by source read 2026-08-14, so this is an acceptance confirmation rather than an open risk:** `CommentsView` never hydrates or renders `recipientUserID` (`:767-768`), using it only for fan-out collapsing and reply eligibility (`:1370`, `:1441`), and every name path falls back to `"User"` (`:260`, `:876`) | B's reply is **still there** — B's words on B's own post; A was merely the addressee. **The single assertion: the thread renders gracefully with the recipient identity missing.** No crash, no blank or broken screen, no pathological placeholder — no raw UUID, no empty name row, no "null"/"undefined", no spinner that never resolves. B's own reply should read as B's ("You"), and the thread should scroll and dismiss normally. **A FAIL is any of those symptoms; the *absence* of the recipient's name is NOT a fail**, because the recipient is not a render site — that is the point of the source read. **RUN 2026-08-14 ON DEVICE B / ÉTUDES DEV — PASS. B-19 IS NOW FULLY RESOLVED AND THIS ROW IS CLOSED.** The `944a70cb` thread on post `81e080cc` — recipient `92d6b718`, deleted 2026-08-13, no `auth.users` row and no directory identity — **opened instantly**. The surviving comment rendered normally: author **"You" with avatar**, body intact ("C35 test comment response from Device B"), **no raw UUID, no blank or broken identity UI, no null/undefined, no spinner and no delay.** Screenshot retained. The existing production fixture was used; nothing was staged, no account was created and no destructive action was taken. **The predicted non-failure held** — the recipient's name is simply absent, because it is never rendered — so this confirms the mechanism read from source rather than merely reporting that nothing looked wrong |
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
| E8 | ~~**B-6 probe, part 1 — revocation:** A (approved follower) records the path of B's public post attachment; B unshares; A attempts access~~ **SUPERSEDED 2026-08-14 — DO NOT RUN. B-6 is RESOLVED by structural hardening, not by demonstration.** The policy was fixed rather than probed: `ALTER POLICY attachments_select_via_visible_post` now binds an attachment to **its own post's owner**, verified live in `pg_policies` (`qual` contains `owner_user_id`, re-confirmed read-only 2026-08-14). A dependency check ran before any SQL and found no legitimate cross-owner reference that the binding would break — one writer, one path shape, all 6 existing references under their own owner's prefix | Superseded. The acceptance evidence is the **legitimate** direction, which is what a naive binding would have destroyed: on Device A, an approved follower of Account B, B's posts render in A's feed **and their attachments open**. That regression passed on device, and it is the only path that actually exercises this policy |
| E8b | ~~**B-6 probe, part 2 — the decisive test.**~~ **SUPERSEDED 2026-08-14 — DO NOT RUN, AND DO NOT TREAT IT AS OUTSTANDING.** This row asked for a crafted PostgREST insert of fabricated data into **production** to demonstrate an exploit whose mechanism was already established from the deployed policy. That was declined deliberately, and the finding was closed by removing the mechanism instead. Demonstrating an old exploit against a policy that no longer permits it would prove nothing and would still be a production write | Superseded. **The requirement it stood for is met by construction plus regression:** the invariant now enforced is that an attachment referenced by a post must belong to *that post's owner* — not to the current viewer, which is the obvious predicate that would have broken every approved-follower read. Structural verification was seven-for-seven (only `qual` moved; policy name, command, roles, `with_check` and the nine other snapshot files byte-identical; policy re-read from `pg_policies` rather than trusted from the snapshot) |
| E9 | ~~**B-2 probe:** account A disables directory lookup; account B searches for A's handle and display name~~ **VOID 2026-08-12 — do not run. There is no control to disable.** Connected discovery is always on and relationship privacy is explicit follow approval (settled; `ff2d4ff`), so no tester can put account A into the state this row assumes. B-2's `lookup_enabled` premise is withdrawn — gating either directory RPC on that column would blank names and avatars for existing followers, which is the opposite of correct. B-2's surviving half is enumeration, tracked under B-15 in Phase 4 | Superseded by E12/E13 for access control, and by B-15 for enumeration |
| E10 | **B-11 probe:** obtain a Supabase session for an account with no active entitlement and attempt each Connected operation | After Phase 3: every write and every read of Domain 3 is refused server-side |
| E11 | **C-34 probe — does a replacement propagate?** A sets an avatar; B (an approved follower) opens A's profile and the feed so B's device caches it. A replaces it with a visibly different image. Without relaunching either app, check B's feed rows, People and comments; then check A's own second device if one is available | Today: B keeps the old image until relaunch, and A's second device keeps it indefinitely, across relaunches. Also settles the storage half — inspect `avatars/users/<A>/` and confirm **one** object, overwritten, not two. That inspection is what turns C-34's upsert behaviour from inferred into observed |
| E12 | **PASS — 2026-08-12, TestFlight build 131, Devices A and B. All four surfaces.** Scoped down beforehand to (c) alone, because Device B followed nobody approved and the rest had no remote content; staging the A↔B edge in B3 made all four reachable. No blank names, no raw UUIDs, no missing users, no permission or auth failures. **B-5 device acceptance, part 1 — directory resolution still works for a signed-in member.** On Device B's **Release** install (the stable Connected control account), after the 2026-08-12 hardening made both directory RPCs authenticated-only. Four representative surfaces, not all thirteen call sites: **(a) feed** — open the feed and confirm owner names and avatars resolve on remote post rows; **(b) session detail and comments** — open a shared session from another member and its comment thread, confirming the owner and every comment author render by name; **(c) People and the follow graph** — open People, Followers and Following, confirming each row shows a name rather than a blank or a raw UUID; **(d) share picker** — begin sharing an attachment and confirm recipient rows resolve. All four go through `get_account_directory_by_user_ids`; if the token were missing on any of them the call is now a visible **401**, not a silent success, so a blank name or an empty list is a real failure and not a cosmetic one | Every surface renders identities exactly as before the change. **Any blank name, raw UUID or empty recipient list is a FAIL** — it means a call site reaches the RPC without a bearer token, which the hardening has now made fatal rather than invisible. Search is deliberately not retested here: V7 already proved it server-side |
| E13 | **PASS — 2026-08-12, executed incidentally by B3's staging rather than as a separate step.** Two `follows` rows were created after the hardening was applied: `92d6b718 → dfaf8d18` at 10:46:43Z, and `dfaf8d18 → 92d6b718` at **10:58:08Z from Device B on TestFlight 131** — the artifact and direction this row specifies. Both were then approved, so the UPDATE path ran too. The four older `requested` rows are July / 11 August and are not evidence. **B-5 device acceptance, part 2 — the follow-request path is unregressed.** Send one follow request from Device B's Release account to another account | The request is created and appears as outgoing. This exercises `follows_insert_requester`, whose `WITH CHECK` calls `follow_requests_open` — the function left deliberately untouched by the hardening (B-18). A failure here would mean the directory work disturbed the follow policy |

**E8b needed a method, not just a tester — and the answer was to remove the
mechanism instead of demonstrating it. RESOLVED 2026-08-14; NOTHING HERE IS
OUTSTANDING.** The paragraphs below are kept as the record of why a production
exploit write was declined, not as work waiting for a method.

It was written as though it were a UI test and it is not: the app offers no way
to type a storage path, so "create a post whose attachment references that path"
cannot be done by using the app. It requires a crafted PostgREST insert with A's
access token, setting the `attachments` jsonb by hand — a developer action, and a
deliberate write of fabricated data to production. That is the same category of
action declined for B-6 earlier, which is why B-6 read "mechanism established
from schema; runtime confirmation pending" for as long as it did.

**How it actually closed.** The policy was hardened (`ALTER POLICY`, binding an
attachment to its post's owner), the change was verified structurally against the
catalog and re-read from `pg_policies`, and the **legitimate** cross-owner read —
an approved follower opening a followed member's attachment — was regression-
tested on device. The declined options are recorded so nobody re-opens the
question: a local Supabase instance in Phase 3, a disposable project, or a single
crafted production insert under a disposable account. **None is needed.** If a
future change to this policy ever wants an exploit demonstration, run it on the
Phase 3 local instance — never on production.

## Group F — Backup and restore

| # | Steps | Expected |
|---|---|---|
| F1 | Genuine **encrypted Finder backup → restore onto Device A** (disposable). Encrypted so the Keychain restores too, which exercises the Connected-identity half. **Not substitutable by inspecting resource flags** — that establishes what the API reports, never what Apple's backup daemon copied | After Phase 2: journal, attachment media and Scores all present and openable; stored absolute paths are stale but every consumer resolves by filename. **CORRECTED 2026-08-15 — the pre-Phase-2 control is NOT "empty Scores".** The Scores index lives in `UserDefaults` (`scoreLibrary_v2`) and restores, so the broken state is a **fully populated library whose every PDF is missing** — titles, favourites and resume state that open to nothing. Anyone expecting emptiness would read that as a pass |
| F2 | Prove the **existing-install** half: a media file written *before* Phase 2, which therefore carries the exclusion attribute, must become backup-eligible through reconciliation **and survive a genuine restore** | Present after restore. If it is absent while a post-Phase-2 file is present, reconciliation did not reach item-level flags — the specific failure the design guards against, since a child's own attribute survives its parent being un-flagged and `Documents/Scores/` was flagged at both levels |
| F3 | After restore, **publish a session** with a non-private attachment | All non-private attachments upload. Pre-Phase-2 this silently omitted them: `resolveLocalFileURL` had no filename fallback, so `loadIncludedAttachments` skipped the attachment rather than blocking publish, and the post arrived with its media missing and no error |
| F4 | After restore, **delete a session** that has attachments, then inspect `Documents/` | The media files are gone. Pre-Phase-2 the deletion paths passed the raw stored path, found nothing, and returned silently — orphaning the files forever with nothing in the UI to show for it |
| F5 | After restore, confirm **Erase All** still removes everything | Unchanged. The factory-reset sweeps are directory- and extension-based and never read `Attachment.fileURL`, so they are path-independent by construction |

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
