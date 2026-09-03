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
| C6 | Failed payment on renewal (Billing Grace Period). **REWRITTEN 2026-08-16 — see gate G6b below, which is the runnable form of this row.** Reaching this state needs a *billing failure*, not a cancellation: disable **Settings → App Store → Sandbox Account → "Allow Purchases &amp; Renewals"** on the device. Billing retry and grace durations are not separately configurable — Apple derives them from the tester's renewal rate | Entitlement **retained** throughout grace; app stays Connected; no cleanup scheduled at any point during grace. **And the assertion this row did not previously carry: once grace lapses without recovery, billing retry outside grace is NOT entitled** — Apple's formula entitles `isInBillingRetryPeriod` only *combined with* an unexpired `gracePeriodExpiresDate`. Access ends and quarantine starts there |
| C7 | **Server authority:** let a subscription expire and grace lapse, then **never launch the app again**. Inspect the backend after the cleanup window | Domain 3 cleanup completes server-side with no device involvement. `posts`, `post_shares`, `connected_attachments`, storage objects and `account_directory` handled per the **expiry** retention matrix in `CLAUDE.md`. **THE 2026-08-14 CORRECTION TO THIS ROW IS WITHDRAWN, 2026-08-16.** That correction asserted "expiry cleanup must match `delete_account_v1`'s deployed semantics" on the grounds that retention was "the pre-2026-08-13 rule and is now wrong". **That was an inference, not a decision, and it was unsupported**: the 2026-08-13 revision was scoped to *explicit account deletion* by its own text and justified by Apple's *account-deletion* guidance, which says nothing about subscription expiry; `docs/architecture.md`'s "On expiry" table was untouched by it. The same cell then declared the question open — so this row asserted a requirement and left it unsettled in one breath. **The question is now settled and the answer is that they DIVERGE**, which is exactly what this row asked to be stated explicitly rather than inherited. **Expiry RETAINS** comments the lapsed member authored on other members' surviving posts, and sent attachments while a live recipient reference remains, and retains `auth.users` and the `account_directory` row (undiscoverable, `display_name` intact). **Explicit account deletion still removes them** — `author_user_id` alone — and comments authored by *others* and merely addressed to the departing member survive in both (B-19, never add `recipient_user_id`). Cleanup runs only after a live authoritative Apple read; the 60-day quarantine precedes it. Runnable form: gates G7, G9 and G10 below |
| C8 | Deliver the same expiry notification twice (replay) | Second delivery is a no-op. No double deletion, no error surfaced, cleanup state unchanged |
| C9 | Deliver a malformed or unsigned notification | Rejected on signature verification. Nothing is deleted |
| C10 | **Decoupling:** with cleanup already complete server-side, launch the app while still un-entitled | App is in Solo, local journal intact, no crash and no attempt to reach Domain 3 endpoints. Re-subscribing produces a clean new Connected identity |
| C11 | ~~**C-19 probe:** set a location while Connected, let membership expire, foreground the app **without opening Profile**~~ **SUPERSEDED BY ARCHITECTURE — C-19 is Resolved, and the mechanism this row probes for no longer exists.** The mounted-`ProfileView` dependency was a *consequence* of the expiry path clearing identity; since C-1, expiry does not clear `backendUserID` at all, so `profile.<backendUserID>.location` stays resolvable and the only code that deletes it is `wipeLocalIdentityForFactoryReset`, reachable solely from Erase All. Corroborated on device: the 2026-08-09 lapse occurred with no `ProfileView` mounted and `auth.init` reported `backendID=true` on relaunch. **Related but NOT covered here:** C-27, the sign-*out* direction, which is a live P3 owned by Phase 5, and which B6 explicitly did not check | Superseded. Location survives expiry unconditionally, with no mounted-view dependency |
| C12 | Confirm by code inspection and by proxy that Erase All is the **only** client-initiated destructive action remaining. **CODE-INSPECTION HALF SATISFIED; PROXY HALF → PHASE 3.** The inspection has been done three times over and by three different routes, which is why this half is closed rather than merely assumed: C-1's fix removed every client entitlement path to `deleteCurrentConnectedAccount`; C-35's work re-audited the deletion path and found the *second* gate that a name-based grep could not see; and C-28 established by source that `LocalFactoryReset.perform` has exactly two callers, `ProfileView:1671` (Solo) and `:1744` (Connected), differing only in a `reason` string. **The proxy half has never been run — no proxy has been used anywhere in this project — and it is assigned to Phase 3**, which is when a *new* client→deletion path could plausibly appear, since server-side authority is the change that would introduce one. Run it then as a regression on the whole client, not as an archaeology exercise now | Invariant check. Any client path to backend deletion other than Erase All is a regression |

## Phase 3 — server-authoritative membership: PLANNED GATES

**Recorded 2026-08-16 at U0. NONE OF THESE HAS BEEN RUN.** Every row below is a
plan. No PASS state is recorded anywhere in this section, and none may be added
until the gate has actually executed against a prediction committed beforehand.
The scope they implement is frozen in `CLAUDE.md`'s Phase 3 section.

**One environment fact governs the whole group, and it is easy to miss.** Apple
retries a failed V2 notification five times (1h, 12h, 24h, 48h, 72h) **in
production only. In the sandbox environment the App Store attempts delivery
exactly once.** Every run below happens in sandbox, so a single dropped response
is unrecoverable by retry — which is why reconciliation (G3) is exercised from
the first run rather than treated as an optimisation.

**Fixture cost for the whole group:** one fresh sandbox tester · Device A ·
**two subscription cycles on that tester** · Device B read-only as the
visibility and attribution observer · the B-23 local instance. **No second Apple
ID, no second device, and Device B is never written to.**

### The lifecycle branches — G6a, G6b, G6c

**These replace a single "cancel → grace → expiry" gate that could never have
worked.** Voluntary cancellation is a renewal-*preference* change and does not
produce Billing Grace; grace follows only a *billing failure*. The two are
mutually exclusive ends of one subscription, so they need two cycles — but one
tester, because branch B opens with a **resubscription**, and it is the clean
first-purchase state that the rig cannot cheaply restore, not a resubscription.

| # | Steps | Load-bearing assertions |
|---|---|---|
| G6a | **Voluntary cancellation.** Purchase → turn off auto-renew → remain entitled to the paid-through date → expiry | Entitlement is **continuous to the paid-through date**; **Billing Grace is never entered** (its appearance is a fail); at expiry `DERIVE` goes false, the presence is hidden, `pending_cleanup_at` is set. Local journal untouched throughout |
| G6b | **Billing failure.** Resubscribe → disable **Settings → App Store → Sandbox Account → "Allow Purchases & Renewals"** → renewal fails → Grace → no recovery → retry outside Grace | (1) The record reaches a state where `DERIVE` is true **because of grace** and not an unexpired `renewalDate` — a future `gracePeriodExpiresDate` together with `isInBillingRetryPeriod` — and **access is retained throughout**. (2) After grace lapses without recovery **`DERIVE` becomes false**, presence hidden, quarantine scheduled. (3) Apple's own `status` is consistent at each step |
| G6c | **Resubscribe during quarantine** — the G6a→G6b transition, scored separately | QA C5. `pending_cleanup_at` cleared; presence visible to Device B again; posts, follows and comments all present and unchanged |

**G6a/G6b assert authoritative state, not notification choreography.** The
specific `notificationType`/`subtype` sequence delivered, and its ordering, are
**recorded as observations, not pass/fail** — a surprising sequence is worth
knowing, but **any sequence Apple legitimately produces that yields the
authoritative states above is a PASS**. A missing or differently-shaped
notification is a finding to record, not a lifecycle failure. Genuine fails are:
access lost during grace; access retained after grace lapses; no quarantine
scheduled at entitlement loss; or the record disagreeing with Apple when
reconciled. **This wording exists because the earlier version was brittle enough
to turn a correct lifecycle into a false failure.**

### Quarantine — Q1 to Q8

**The 60 days is used once, at scheduling; the worker afterwards reads only the
stored timestamp.** That separation is what lets the duration stay a hard
constant production cannot shorten, while the worker's deadline behaviour is
exercised by writing fixture rows whose `pending_cleanup_at` is already past or
future — **test data in a disposable environment, not a config override, not a
clock, and not a line of code in the production path.** The reconciliation
outcomes use a seam that must exist anyway: Apple's sandbox and production App
Store Server API live on different hosts, so the base URL is necessarily
configuration.

| # | Assertion | Evidence level |
|---|---|---|
| Q1 | Scheduling computes entitlement end + 60 days | **Real Apple sandbox.** Read the row after G6a's genuine expiry: `pending_cleanup_at − entitlement_ended_at = 60d` exactly. Costs no waiting |
| Q2 | The worker refuses to act before the deadline | Local, deterministic — fixture row with a future deadline |
| Q3 | Resubscription before the deadline cancels cleanup and restores presence whole | **Real Apple sandbox** — G6c, free |
| Q4 | After a due deadline the worker becomes eligible | Local, deterministic — fixture row with a past deadline |
| Q5 | Even when due, cleanup cannot execute without the live Apple read | Local. **The call must be observed to happen BEFORE any mutation** — a worker that deletes first and asks second passes every other row here |
| Q6 | Apple unreachable or erroring → no cleanup, retried later | Local — stub returns 5xx, then a timeout, then a malformed body. Nothing deleted in any case |
| Q7 | Apple reporting entitlement → cleanup aborts, schedule clears | Local — stub returns `status 1` |
| Q8 | Apple confirming non-entitlement → the expiry-specific policy runs | Local for the full retention matrix, **and once for real at G7** |

**Q2 and Q4–Q7 are stronger locally than they could ever be against Apple** —
Q6's three failure modes cannot be induced against Apple at all.

### The remaining gates

| # | Covers | Notes |
|---|---|---|
| G1 | B-4, B-12, B-13, B-9's two-recipient subcase | Local destructive suite on the B-23 instance. Stopping rule below |
| G2 | C8, C9 | Ingestion in observe-only mode. **AMENDED 2026-08-20 in two places, both because the original wording asserted something no correct implementation could produce.** (i) **Status codes:** structural reject → **400** with nothing written; signature-verification failure → **5xx**; verified and durably handled → **200**, including outcomes we refused downstream. The old "answered 200" rested on the premise that a payload failing verification was never valid; **U4a falsified it** — the catastrophic case is a verifier that rejects *everything*, which is exactly what the official Apple library does on this runtime, and under 200 every legitimate notification lost that way is lost permanently while 5xx buys production's five retries across 72 hours. Sandbox never retries either way. (ii) **Replay:** `'duplicate'` is **structurally unwritable** — the partial unique index on `notification_uuid` forbids a second row (B-26) — so the assertion is now **`delivery_count` 1 → 2 with `membership` unchanged and the first delivery's `outcome` preserved**, which proves the replay was *seen and refused* rather than merely unprocessed. Per-notification outcome is `applied`/`stale`/`ignored`/`rejected`; `'duplicate'` is **returned** to the caller, never stored |
| G3 | Missed-notification recovery | With one delivery deliberately dropped, the record still converges to Apple's answer. **STILL OPEN, and its instrument was BROKEN until 2026-08-23 — see B-32.** `appstore_reconcile_v1 mode=notification_history` reported `apple_notification_count: 0` unconditionally, so the comparison G3 depends on could not have been made: a genuine gap and a quiet Apple were indistinguishable. **B-32 IS NOW RESOLVED — deployed 2026-08-23 and reconciled against real Apple history: Apple's 14 uuids and our 14 are IDENTICAL, zero lost, zero unexplained.** So G3's **instrument now works and has a real verified baseline**. **G3 ITSELF REMAINS OPEN**, and the distinction is deliberate rather than pedantic: what has been proven is that *nothing was lost during ordinary traffic*. G3 as specified requires a delivery to be **deliberately dropped** and the record to then converge via `mode=reconcile` — that scenario has not been exercised, and it is the half that proves RECOVERY rather than mere agreement. It is now runnable, where before it was not |
| G4 | B-11 shadow half — **U6a** | Per denied request, **which clause would have decided it**, against a prediction committed before the window opens |
| G5 | Lapsed-member deletion **reachability only** | **NON-DESTRUCTIVE. The button is not pressed.** Control present and enabled on a lapsed Device A, confirmation sheet reaches its typed-confirmation state, grants and policies for both destructive endpoints unchanged under enforcement. **This is not the executed evidence and must not be recorded as such** |
| G7 | C7's destructive half | **NAMED DEFERRED OPERATIONAL VERIFICATION — owner U7, earliest `2026-11-01 15:16:44+00`. NOT a U7 or Phase 3 closure blocker** (2026-09-03). Expiry cleanup on Device A's account. Full blast radius per measure, D14/D15 style, **including the two assertions that prove the policies distinct: a retained comment on another member's post SURVIVES, and `auth.users` SURVIVES**. **WORDING CORRECTED 2026-09-03. This cell read "Expiry cleanup on Device A's account, ***allowlisted***", and that word is SUPERSEDED rather than deleted** — it referred to the D4 per-identity allowlist, which was **REJECTED OUTRIGHT ON 2026-08-20**, four days after this row was written, because it placed a shippable exception inside the predicate defining paid access. **The row therefore described its own precondition in terms of a mechanism that will never exist**, and a later reader could have concluded G7 was blocked on building one. The C-52 shape: a document written under a rule that changed and was never re-read. **NO ALLOWLIST IS NEEDED AND NONE WILL BE BUILT.** Device A's identity is `sandbox_only`, is already denied by live enforcement, and its cleanup is authorised by the ordinary path — the same path that correctly **REFUSED** on 2026-09-03 because Apple's own dates put the quarantine deadline in the future. **The only remaining precondition is elapsed time.** **WHY THIS IS DEFERRED RATHER THAN BLOCKING:** the destructive implementation is discharged locally (`supabase/tests/u7/e2e-worker.sh`, 75/75, full retention matrix), and the production AUTHORITY path is discharged in production against genuine Apple. What remains is one calendar-dependent observation, carried exactly as **Gate 6 part 3** is carried on B-11 — *"unobtainable before public release and NOT a bind precondition"* — and as Phase 1 carried C-36/B-4/B-12/B-13 and Phase 2 carried C-51. See `supabase/sql/README-u7e-preflight.md` §1 |
| G8 | C12 proxy half | Zero `delete_account_v1` and zero cleanup-endpoint calls on the wire outside an explicit Erase All |
| G9 | **Executed lapsed account deletion — LAST** | After G7, on the same identity, no renewal at any point. Possible because expiry retains `auth.users`, the directory row and all device state, so `hasConnectedIdentity` is still true and `ProfileView:1753`'s entitlement-free branch is reachable — **C-35's exact condition.** Post-cleanup the account holds precisely what expiry retained, which deletion must remove, so this is the discriminating pair. **Honest limit: this exercises C-35's *authority* half in full but its blast radius against a reduced account. The full-account version was already device-verified 2026-08-13 and those rows are Resolved; Phase 3 does not owe it again** |
| G10 | Retained-comment attribution after expiry | **Backend half:** the comment row survives with `author_user_id` intact; `auth.users` and the directory row survive; `display_name` non-empty and unchanged; `avatar_key` null; the by-ids RPC returns the row; `search_account_directory` does not. **Client half:** Device B opens the thread on its own post and the retained comment renders with **the lapsed member's actual display name**. **Fail on** generic `"User"` (`CommentsView:1033` is the exact fallback site), a raw UUID, a blank identity row, a spinner that never resolves, or broken UI. Device B is **read-only** and spends nothing; the fixture is created by G7 itself. This is the expiry-specific *author* direction created by the retention decision — deliberately **not** B-19, which is the deletion *recipient* direction and stays closed |
| G11 | **Dormant pre-cutover return** | **Runs BEFORE U6b binds**, so a defect costs a fix rather than a lockout. **Server half (local, deterministic):** pre-cutover identity, valid Apple status from the stub, no membership row, grandfather clause disabled → `connected_member()` false before attestation and true after; the row carries Apple's values, not the client's; a 5xx stub leaves **no row and no `pending_cleanup_at`**; a retry succeeds. **Client half (Device A + proxy):** during branch B while genuinely entitled, delete *only* the membership row under explicit authorisation on the disposable account — the simulated-setup pattern D13 used and recorded — disable the clause, cold-launch, and observe that the attestation request is issued **unconditionally, not gated on Connected mode or on a row existing**, the row is created, and Connected is reached without a second launch or a re-purchase. **Stale-session variant:** with the Supabase session no longer refreshable, Sign in with Apple returns the **same** backend identity and attestation then succeeds. **Fail if a new identity is minted or the member lands in a state offering only re-purchase.** Rides on C12's proxy — no new instrument |

### What each U6 gate proves — they do not share one metric

**This distinction is the point.** One metric was standing in for four questions.

| Gate | Answers | Does NOT prove |
|---|---|---|
| **U6a** shadow | Are enforcement's *decisions* correct for traffic that occurred? | **Anything about users who generated no traffic** |
| **U6b** bind | Is it safe to make enforcement binding? **RESTATED AGAIN 2026-09-01 — B-36; GATE 6 CORRECTED 2026-09-02.** Requires **G11 passed** (**DONE, 16 of 16**) **and the enforcement-path Sandbox QA mechanism resolved — GATE 6 IS SETTLED AND SUBSTANTIALLY DISCHARGED.** **This cell previously read "Gate 6 — NOT MET, ON THE CRITICAL PATH", and that wording was superseded by `README-gate6-enforcement-qa.md` §4 on the same day it was written and never re-read** — the C-52 shape, and it produced a wrong roadmap a day later. **The settled decision is that the smallest mechanism is NO PRODUCTION MECHANISM:** TestFlight/Sandbox cannot create genuine Production entitlement, and no Production Sandbox override, allowlist, QA bypass or fake Production membership will be built. Three parts: **(1) DENY path in production — DISCHARGED at P6**, on genuine `sandbox_only` and `unknown` identities; **(2) GRANT path locally against the real policies — DISCHARGED**, U6b acceptance group E plus L3/L4; **(3) GRANT path in production at the FIRST REAL SUBSCRIPTION — a post-public-release release gate**, verified before any second paying subscriber exists. Part 3 is unobtainable before public release and is NOT a bind precondition. **The grandfather-population condition is RETIRED, not satisfied.** It was unsatisfiable by construction — the cutover snapshot has NO entitlement predicate, so identities that never subscribed can never acquire authoritative state — and it protected a pre-release beta cohort the account holder has confirmed need not be preserved. **The mechanism is being retired instead**, after a reversible `grandfather_enabled = false` shadow experiment run while enforcement is still non-binding. **The consequence Gate 6 was raised for is REAL AND ACCEPTED, not eliminated: once binding, a Sandbox tester reads `sandbox_only` and is denied server-side while the client still shows Connected from local StoreKit.** That is the *designed* behaviour of a genuinely unentitled identity, and it is what makes the production DENY path testable at all. It is not a defect to be worked around. | — |
| **U6c** remove | Is the migration provenance safe to delete? **SUPERSEDED IN DIRECTION 2026-09-01 — B-36.** With the grandfather mechanism retired outright this collapses into an ordinary cleanup migration: drop `connected_member()`'s middle arm, drop `membership_cutover`, drop the three dead `membership_control` columns. **No twelve-month clock, no liveness check, no post-phase obligation.** The previous form — either every snapshot UID has authoritative state or twelve months elapse, plus a liveness check keyed on `max(auth.sessions.updated_at)` per B-35 — is retained as the CONDITIONAL form and **returns in full the moment a production customer exists** | — |
| **G11** | Does a dormant pre-cutover payer reach Connected with the clause off? **PASSED 2026-09-01, 16 of 16, zero falsifiers.** Attestation fired unattended on a cold launch and re-established the row in ~40s; the binding row was untouched, proving no Set App Account Token PUT; zero Apple notifications were involved. **Proves the MECHANISM, not the POPULATION** — the precondition was manufactured by deleting the row, so a genuinely dormant identity with a years-old JWS remains untested | — |

## U5a — F3b GATE. PROCEDURE AND PREDICTION, committed 2026-08-20 BEFORE execution

**NOTHING BELOW IS A RESULT. THE GATE HAS NOT BEEN RUN.** It is written and
committed first, in the D14/D15 style, so the outcome is scored against a
prediction rather than read off the aftermath.

### The question, and why it cannot be answered by reading

U5 must decide whether a **short freshness window on a client-supplied
transaction JWS** is a viable replay control (finding F3, decision D3). Apple's
transaction payload carries no field we choose, so there is no challenge to bind
a submission to; a freshness window is the only cheap control left, and it works
only if `Transaction.currentEntitlements` returns a **freshly signed**
representation per read rather than a **stored historical** one.

**APPLE'S DOCUMENTATION DOES NOT ANSWER IT.** Checked 2026-08-20 against the
references for `VerificationResult`, `jwsRepresentation`, `signedDate` and
`Transaction.currentEntitlements`: none states when the App Store produced the
signature, whether a read contacts the App Store, or whether a refresh is
possible at all. The single hint runs the *other* way — `jwsRepresentation` is
described as "the same as its counterpart in the App Store server APIs", which
reads like a stored artefact. **A hint is not a result.** This is the same shape
as the U4a gate: two plausible routes, and only running them settled it.

**`deviceVerification` was examined as an alternative and does not solve this.**
It binds a transaction to a device via `AppStore.deviceVerificationID`, and the
nonce is generated by StoreKit rather than supplied by us — so a server that
never sees the device cannot use it as a challenge, and a replaying client can
send the matching identifier just as easily as the legitimate one. Recorded here
because it is the obvious thing the next reader will reach for.

### Instrument

`MOTIVO/JWSFreshnessProbe.swift`, plus two call sites in `MOTIVOApp.swift`
(launch, foreground). **TEMPORARY INSTRUMENTATION with a standing removal
condition** — deleted the moment the gate is scored, as `ActivationTrace` and
`MembershipTrace` were.

- **Read-only.** No network, no purchase, no `AppStore.sync()`, no binding, no
  membership establishment. It reads an existing local entitlement and emits log
  lines.
- **`os.Logger`, `privacy: .public`, one funnel.** Release-readable, because
  Release is the only build that can hold a sandbox entitlement at all.
- **It never logs the JWS.** Under U5's protocol the JWS *is* the ownership
  proof, so writing one into a device log — readable over a cable, collected
  wholesale by `log collect` — would manufacture the exact leak U5 is designed
  around. A 12-hex SHA-256 prefix answers "same bytes or different bytes" and is
  useless as a credential.
- **It scores its own cross-launch comparison** into `vsPrevious=`, rather than
  leaving the tester to diff console lines by eye. Three device observations in
  this project have already been misread because the first one involved a cache.
- **It emits `env=`.** A run reporting `Xcode` was made against a pinned StoreKit
  configuration and is signed by Xcode's local test certificate, not Apple's —
  so its freshness behaviour says **nothing** about Apple's. That is the F1 trap,
  caught in the evidence rather than in the tester's memory of Run → Options.
- **It emits `txID=` and `expires=`, and this is what makes the gate sound.**
  `originalID` alone cannot tell a re-signature from a sandbox **renewal**, and
  the accelerated renewal rate can fire inside the gate's own ten-minute step —
  so without this the commonest way to get a false P1 would have been invisible.
  See "THE RENEWAL CONFOUND" below.

### Fixture — what it costs, and what it must not cost

**F3b needs an ENTITLED device, not a FRESH one.** A clean first-purchase state
is the expensive thing the sandbox rig cannot cheaply restore; an entitlement
that already exists is free to read repeatedly. **So F3b rides on the G6a
branch-A purchase and spends no sandbox cycle of its own** — run it immediately
after that purchase, before G6a's cancellation step.

| Fixture | Impact |
|---|---|
| Sandbox tester's clean first-purchase state | **CONSUMED** — but shared with G6a branch A, so the marginal cost is zero if sequenced as above |
| **C-36 / QA B7 fresh-first-join account** | **NOT CONSUMED — see below. This is the one that must not be spent by accident** |
| Device B Release (lapsed control) | Untouched. Not used at any step |
| Any backend row | **NONE CREATED.** No sign-in occurs, so no `auth.users`, no `membership`, no `membership_binding`, no directory row |

**Why C-36 is safe, stated precisely, because the two fixtures look adjacent and
are not.** They are different scarce resources on different Apple accounts:

- **F3b spends** a *sandbox tester's* first-purchase state. The sandbox tester
  lives in **Settings -> App Store -> Sandbox Account** and is used only for
  purchases.
- **C-36 needs** a *primary Apple ID that has never joined Études Connected*.
  Sign in with Apple uses the device's **primary Apple Account**, not the sandbox
  tester.

**They never touch, provided the run does not sign in** — and it has no reason
to, because `Transaction.currentEntitlements` is pure StoreKit and the probe
makes no network call at all. The current shipping flow makes this easy: purchase
happens **before** sign-in, and the sign-in sheet presented afterwards is simply
dismissed. **This is the last window in which that is true** — D2 inverts the
flow at U5f, after which joining requires signing in first, and a future F3b-like
run would have to be planned around it.

**Device A's primary Apple ID is in any case ALREADY SPENT for C-36 purposes** —
identity `5ae3faab...` was minted on it 2026-08-15 and its credential has since
been revoked, and the rig notes already record that it "is **not** a C-36 fixture
and must not be used as one". So F3b cannot make C-36 worse than it already is.
**The no-sign-in instruction is cheap insurance for the day a genuinely fresh
Apple ID is provisioned on that device**, not a live risk today.

### THE RENEWAL CONFOUND — read this before scoring anything

**The development sandbox honours the tester's accelerated renewal rate, so a
Monthly cycle can complete in about thirty minutes — inside this gate's own
ten-minute step.** A renewal legitimately produces a **new transaction** with a
new signature and a later `signedDate`, which reads exactly like a re-signature
and would be scored as P1. That is a wrong answer arrived at honestly, and it
would select a freshness window the design cannot support.

**Two independent defences, and use both:**

1. **Set the sandbox tester's renewal rate to the SLOWEST available** before
   starting, so the window is unlikely to be crossed at all.
2. **The probe emits `txID=`.** `Transaction.id` changes on renewal and does not
   change on a re-signature, so the two are separable in the evidence rather than
   in the tester's recollection. Any step whose `txID` moved is reported as
   **`vsPrevious=RENEWED_notEvidence`** and **is not evidence about freshness**.
   Re-run that step.

`expires=` is emitted alongside for the same reason: it makes an approaching
renewal boundary visible before it is crossed.

### The exact Device-A procedure

**Preconditions — all four, verified before step 1:**

| # | Precondition | How to confirm |
|---|---|---|
| 1 | Release build from a clean tree at `e157b1c` or later, installed on **Device A** via Xcode Run | The scheme's Run action is Release again (C-52) |
| 2 | **Run -> Options -> StoreKit Configuration reads `None`** | Confirm visually. The shared scheme no longer pins one, but a per-user Run -> Options selection is the same setting and must be seen to be clear. **The probe's `env=` line is the backstop, not the check** |
| 3 | Settings -> App Store -> Sandbox Account is the dedicated sandbox tester, **renewal rate at its slowest** | Settings, before launching |
| 4 | **DO NOT SIGN IN WITH APPLE AT ANY POINT** | See the C-36 note above |

**Steps. Each captures one or more log lines; nothing is scored until the end.**

| Step | Action | Expected line(s) |
|---|---|---|
| 1 | Profile -> Connected -> Continue -> Membership -> purchase **Monthly**. Apple's sheet must read **"Sandbox"**. When the sign-in sheet appears afterwards, **dismiss it** | — |
| 2 | Force-quit. Cold launch | `reason=launch1`, then `reason=launch2` ~3s later |
| 3 | Home (background), wait ~30s, foreground | `reason=foreground` |
| 4 | Force-quit. Cold launch | `reason=launch1` |
| 5 | Wait **>= 10 minutes without launching**. Cold launch | `reason=launch1` |
| 6 | Profile -> Restore Purchases (`AppStore.sync()`), then background and foreground | `reason=foreground` |

**Reading the evidence.** With Xcode attached the lines appear live in the
console (`Logger` + `privacy: .public`). Detached, use
`sudo log collect --device-name "<device>"` then:

```
log show --predicate 'subsystem == "com.sdsongs.etudes" AND category == "u5a"'
```

**Scoring order — check these three before looking at the result at all:**

1. **`env=` must read `Sandbox` on every line.** `Xcode` anywhere -> **VOID**,
   precondition 2 failed, re-run.
2. **`txID=` must be constant across steps 2-5.** Any step where it moved is
   `RENEWED_notEvidence` and is re-run, not scored.
3. **`entitlements=0 NOFIXTURE` anywhere -> NOT A RESULT.** The purchase did not
   take; fix that first.

Only then read `vsPrevious=` and `ageSeconds=` against the six predictions below.

### Predicted outcomes, and what each one decides

**Every branch is a valid result.** This gate has no "pass"; it has an answer,
and the answer selects a replay control.

| # | If the evidence shows | Then | D3 becomes |
|---|---|---|---|
| **P1** | `signedDate` advances and `jwsSha256` changes on each cold launch (`vsPrevious=RESIGNED`), with `ageSeconds` consistently small | StoreKit re-signs on read | **A short freshness window (≈5 min) is VIABLE** and is the primary control |
| **P2** | `signedDate` and `jwsSha256` are identical across cold launches (`vsPrevious=UNCHANGED`), `ageSeconds` growing without bound | The representation is stored and historical | **A freshness window is WORTHLESS.** Fall back to one-time consumption by digest, or accept the residual explicitly |
| **P3** | Unchanged across launches but refreshed by `AppStore.sync()` at step 6 | Refresh exists but is user-visible and password-prompting | A window is viable **only** if attestation may trigger `sync()`, which it may not — it prompts. Treat as P2 |
| **P4** | `vsPrevious=ANOMALY_*` — bytes change without the date, or the reverse | Something is not as modelled | **STOP AND REPORT.** Do not design a control on an unexplained observation |
| **P5** | `env=Xcode` on any line | The run was made against a pinned StoreKit configuration | **VOID.** Not evidence about Apple. Re-run after confirming F1's correction |
| **P6** | `entitlements=0 NOFIXTURE` | No entitlement present | **NOT A RESULT.** An absent fixture is not an observation — the U4 `E0` lesson |

**`ageSeconds` at step 1 is the load-bearing number even under P1**, because it
sets the floor for how tight a window can be without failing legitimate users on
a cold launch.

### U5a — F3b RESULT. EXECUTED ON DEVICE A, 2026-08-20. **P2.**

**Scored against the predictions above, which were committed before the run.**

**The three preconditions were checked before the result was read, in the
prescribed order, and all three passed** — this matters, because two of them
exist to void a run rather than to score it:

| Guard | Observed | Verdict |
|---|---|---|
| `env=` on every line | **`Sandbox`** | Not P5. Real Apple, not Xcode's test signer |
| `txID=` constant across steps | **`2000001224581513` throughout** | **Not a renewal.** The confound did not fire |
| Fixture present | `verified=true`, one entitlement | Not P6 |

**The observation.** Across repeated reads, a foreground, multiple cold launches
and more than ten minutes:

```
originalID = 2000001220187383
txID       = 2000001224581513      (unchanged)
signedDate = 2026-08-20T19:57:24.974Z   (unchanged)
jwsSha256  = efa41398b7b3          (unchanged)
expires    = 2026-08-20T20:57:18.000Z
vsPrevious = UNCHANGED             (throughout)
final ageSeconds = 706-709
```

**RESULT: P2.** `Transaction.currentEntitlements` returns a **stored historical
representation**, not a freshly signed one. `signedDate` is fixed at
approximately the purchase instant — 19:57:24, some six seconds after the
transaction's implied purchase time of 19:57:18 — and did not move; `ageSeconds`
grows monotonically with wall-clock time and nothing else.

**The cold launches are what make this conclusive.** The process was destroyed
and rebuilt repeatedly and StoreKit still served **byte-identical** bytes, which
rules out in-process caching and establishes a persisted representation rather
than a per-read signature.

**Honest limits, stated rather than glossed.** This proves stability across cold
launches for ~12 minutes inside a single subscription period. It does **not**
prove behaviour across a renewal (`txID` changes there, which is expected and is
a different question), nor over days. **Step 6 (`AppStore.sync()`) was not
separately reported, and it does not matter:** P3 was written to collapse into
P2 precisely because a control that only works after a password-prompting sync is
unusable on an attestation path. **The gate is robust to that gap by design.**

**The tester deviated from the procedure in one respect and it was safe.** The
renewal rate was set to "Monthly every hour" rather than the slowest available;
the period ran 19:57:18 to 20:57:18 and the last observation was ~48 minutes
clear of the boundary. `txID` constant is the proof that the deviation cost
nothing — which is exactly what that field was added for.

### D3 — DECIDED FROM THE EVIDENCE: no freshness window, no one-time consumption

**A freshness window is not merely weak here, it would BREAK the design's most
important scenario.** Because `signedDate` is fixed at purchase, any window tight
enough to constrain an attacker rejects every legitimate attestation after the
subscription's first minutes — and attestation fires on every launch and
foreground for the life of the subscription. Worse, **a dormant pre-cutover
subscriber's return (G11) presents a JWS signed months or years earlier.** A
freshness window would refuse the single case U5 exists to make self-healing.

**One-time consumption by digest is also rejected**, for a different reason: the
legitimate client presents the *same* JWS on every attestation, so consumption
would refuse the owner's second call. Scoped narrowly enough to be coherent —
consumed only on the establishment path — it adds nothing that
`membership_transaction_unique` and the live-binding conflict rule do not already
provide.

**The residual is accepted explicitly, and it is narrow and statable:** an
attacker who obtains a **legacy, token-less** subscriber's transaction JWS
*before that subscriber ever attests* can bind that subscription to their own
identity. Four structural properties bound it, three already in the schema:

1. **`membership_transaction_unique (environment, original_transaction_id)`** — one
   Apple subscription entitles at most one Études identity, enforced by the
   database, so a replay cannot mint a second entitled identity.
2. **The live-binding conflict rule** — once the owner has bound, any other
   claimant is refused and recorded. The window closes permanently.
3. **The self-extinguishing legacy branch** — reachable only while Apple reports
   no token, and taking it sets one.
4. **D2/U5f sets `appAccountToken` at purchase**, so after U5f every new
   subscription carries a token from birth and the exposed population is the
   pre-U5f cohort: finite, enumerable and shrinking.

The legitimate owner's failure mode is a **refusal that is recorded for operator
disposition** — an account-recovery event, which B-24 already requires — not a
silent loss.

**Two consequences that strengthen the design rather than patch it.**

**(i) The JWS is required ONLY on the establishment path.** After establishment,
refresh runs server-side through `membership_apply_reconciliation_v1` on the
*stored* `original_transaction_id`, with no client artefact at all. That reduces
how often the bearer artefact travels, which is the best available mitigation.

**(ii) P2 VALIDATES THE THREE-ARTEFACT SPLIT rather than complicating it.** A
permanently-stale artefact is exactly why the JWS may answer **who** and must
never answer **now**. Had the gate returned P1 it would have been tempting to let
a fresh JWS stand in for the live Apple read; P2 forecloses that, and B-24's
separation is confirmed by measurement instead of by argument.

**(iii) The no-persist, no-log rule is now LOAD-BEARING rather than cautious.**
Under P1 a leaked JWS would have expired in minutes. Under P2 it is valid for the
life of the transaction, so a leak is permanent. **U5 must never log, store or
echo a transaction JWS anywhere** — the probe already respected this, and the
reason is now stronger than when it was written.

### What this gate does NOT establish

It says nothing about whether a JWS can be *exfiltrated*, nothing about U5's
claim checks (F2), and nothing about ownership. It answers one question about
one API's freshness behaviour, and its result feeds exactly one decision.

---

## U5f — THE NEW JOIN FLOW AND ATTESTATION ORCHESTRATION. 2026-08-23

**The first product-visible U5 unit.** No server surface changed — `git diff`
over `supabase/functions/`, `migrations/` and `config.toml` is **empty**.

| Verification | Result |
|---|---|
| Debug / Release builds | **both SUCCEEDED**, 0 errors |
| Unit tests | **15 of 15**, run normally |
| `client-structural.sh` | **53 of 53** |
| Server/schema surface | **unchanged** |

### The new sequence

```
Explore Connected -> SIWA / backend identity -> ensure_membership_binding()
   -> purchase with .appAccountToken(bindingToken) -> .verified -> attestation
```

**The binding token is a HARD PREREQUISITE of the purchase, and the type system
enforces it**: `purchase(_:appAccountToken:)` takes a non-optional `UUID`, so an
unbound call does not compile.

**CORRECTED 2026-08-23, AND THE ORIGINAL REASONING WAS WRONG IN TWO WAYS.** The
first revision fell back to an unbound purchase when the token could not be
fetched, arguing that refusing "would turn a recoverable binding hiccup into a
lost sale". It **overstated the cost** — StoreKit is never reached, so no money
moves and nothing is lost but a second tap — and it **understated the
consequence**: a subscription created after U5f without a token lands in the
legacy-claim path, **whose entire safety argument is that its population is
finite and shrinking**. The residual risk F3 accepts is bounded precisely because
the token-less cohort predates this flow. A fallback that mints new legacy
subscriptions makes that cohort unbounded and permanent, quietly dismantling the
reason the risk was acceptable in the first place.

**The legacy-claim and orphan-rebind paths are unchanged and still serve genuinely
pre-U5 subscriptions.** They are not a fallback for new purchases.

When the token cannot be fetched, the member sees a calm retryable notice —
*"Setup unavailable … Nothing has been charged — please check your connection and
try again"* — and **zero StoreKit purchase attempts are made**.

**An already-authenticated member sees no extra step**: Continue checks
`hasConnectedIdentity` and goes straight to the paywall.

### Attestation triggers — six, one gate

All six route through `MembershipAttestationCoordinator`, so the invariant is
enforced in exactly one place:

| Trigger | Forced past cooldown |
|---|---|
| launch | no |
| foreground | no |
| local entitlement resolves to entitled | no |
| backend identity becomes available | no |
| immediately after a verified purchase | **yes** |
| Restore Purchases / `AppStore.sync()` | **yes** |

**`C5f-12` is the assertion that matters most.** It parses `MOTIVOApp.swift` and
asserts that **no `attestIfNeeded` call sits behind a `canViewFeed` guard**. Gate
attestation on Connected already being active and the member the mechanism exists
to rescue — the dormant pre-cutover subscriber, in Solo *because* the server does
not know them yet — can never reach it. **G11 would fail silently and forever.**

**Duplicate suppression is single-flight plus a 30s cooldown, IN MEMORY ONLY**
(`C5f-6`). A persisted "already attested" flag would become client-held authority
over server membership, which invariant 3 forbids, and would defeat G11 outright:
the dormant returner's recovery depends on a cold launch attesting again. State
resets every launch, deliberately, and a previous success is never permanent
authority.

### F10 — a verified purchase is a completed purchase

Two changes. In `ConnectedMembershipStore`, a `.verified` transaction whose
entitlement had not yet surfaced used to return **`.failed`** — Apple had taken
the money and the app said "Purchase unavailable", inviting a second purchase.
That branch is gone; the error case is kept as a **gravestone** with no caller
(`C5f-19`).

In the paywall, `postPurchaseNotice` maps the attestation outcome to what the
member is told, and **the common case is silence**:

| Outcome | Told |
|---|---|
| established / alreadyEstablished | **nothing** |
| appleUnavailable / transport / serverError / non-terminal refusal | **nothing** — the next foreground retries |
| **pending** (propagation) | *"Finishing setup — this completes on its own, no action needed."* |
| conflict / terminal refusal | *"Your purchase is safe. Please contact support."* |

`pendingIsCalmAndNotAFailure` asserts the pending copy contains none of *fail,
failed, error, unavailable, problem, try again, retry, cancel, refund, lost* —
**F10 expressed as an executable assertion rather than a style note.** The
unresolvable cases assert *"purchase is safe"* and the absence of *"try again"*,
because the member cannot fix those alone.

### The gate is proven three ways, not asserted

| | |
|---|---|
| **Type** | `purchase()` takes a non-optional `UUID` — an unbound call **does not compile** (`C5f-13a`/`C5f-13b`) |
| **Unit** | `missingBindingTokenBlocksPurchase` — a nil token yields `.blockedNoBindingToken` |
| **Structural** | `C5f-13f` parses the view and asserts the readiness guard **precedes** the only `membershipStore.purchase` call site |

`bindingUnavailableNoticeIsCalm` asserts the copy says *"nothing has been
charged"* and *"try again"*, and contains none of *purchase failed, payment,
refund, declined, error* — it is a transient setup state, not a failed purchase.

### Genuine-Sandbox scenarios unlocked by this unit

Everything below needs deployment first, and none of it is runnable locally:

- **S-1** — a real `currentEntitlements` JWS passes the **pinned** Apple anchor.
- **S-2** — Set App Account Token accepted by Apple and reflected in a later read.
- **B-24's new-purchase path end to end** — bound at source, so ingestion should
  go straight to `applied` rather than `unmapped`.
- **S-3** — the token survives into a real renewal notification. **The single
  assertion that proves the whole protocol**, and it needs a renewal cycle.
- **G11 client half** — delete only the membership row, disable the clause, cold
  launch, and observe the request issued **unconditionally**.
- **F10 on device** — a real purchase where attestation is momentarily pending.

---

## U5e — CLIENT PLUMBING AND F6. 2026-08-23. NO TRIGGERS WIRED

**Two services, one session helper, zero user-visible change.** The purchase and
join flow is untouched and that is **asserted rather than promised**: `C5e-25`
pins that `MembershipSelectionView` still knows nothing about `appAccountToken`,
`C5e-24` that `MOTIVOApp` wires no attestation trigger. SIWA-before-purchase is
U5f.

| Verification | Result |
|---|---|
| Debug build | **SUCCEEDED**, 0 errors |
| Release build | **SUCCEEDED**, 0 errors |
| `client-structural.sh` | **26 of 26** |
| Unit tests | **7 of 7 EXECUTE AND PASS**, once C-54 was fixed the same day — see below |
| Server surfaces touched | **NONE** — `git diff` over `supabase/functions/`, `supabase/migrations/` and `config.toml` is **empty**, so the B-23 delta and every SQL/function suite are structurally unaffected. **They were not re-run for show** |

### The absences are the assertions

A client that *says* it never logs a bearer artefact is worth little. `C5e-1..7`
assert that `MembershipAttestationService` contains no `print`, no `NSLog`, no
`Logger`, no `UserDefaults`, no `Keychain.set`, no file write — **and no mutable
state at all**, so there is nowhere for the JWS to be cached even accidentally.
`C5e-8`/`C5e-9` assert exactly one request body, built as `["jws": jws]`.

`C5e-11` asserts **no `UUID()` anywhere in the binding service**. The token is
the server's to issue; a client-minted one would be a value nobody recorded, and
it would travel into Apple's own records where it is not cheaply correctable.

### F6, and why it was a naming problem

The mode-independent behaviour **already existed** — as
`ensureValidSessionForConnectedAccountCleanup`, which names a *caller's motive*
rather than what it does. That is precisely the defect **C-25** was filed for, so
reusing it for attestation would have re-committed it.

It is now `ensureValidBackendSession(reason:)`, with the cleanup function a thin
alias so the two are **provably identical rather than similar** (`C5e-19`), and
C-44/C-45's reasoning stays findable by the name it uses. `ensureValidSession`
keeps its `isConnected` guard (`C5e-18`) so no existing caller moves.

**The new helper does not sign anybody out** on an unconfigured backend, unlike
`ensureValidSession`. A liveness helper that can revoke a session is the wrong
shape for a path intended to run on every foreground.

### C-54 — RESOLVED the same day. The tests run, and the defect had two layers

`TEST_HOST` points at `MOTIVO.app/MOTIVO`; the product has been `Etudes.app/
Etudes` throughout. **Any `xcodebuild test` fails before compiling a line.**

Two workarounds were tried and both are genuinely blocked. A project-wide
`TEST_HOST=` override makes `MOTIVOUITests` fail — it sets `USES_XCTRUNNER` and
the two are mutually exclusive. A target-scoped build fails in the SPM C targets'
dependency scan. **The fix is one setting in two configurations and was
deliberately not applied while Xcode was open on the project**, this session
having twice watched Xcode overwrite on-disk project edits.

**FIXED 2026-08-23 once Xcode was closed, and the fix uncovered a SECOND stale
reference the first had been hiding.** With `TEST_HOST` corrected the build got
*further* and failed on `@testable import MOTIVO` — the app's Swift module is
**`Etudes`** (`PRODUCT_MODULE_NAME`), so the generated template's import had been
wrong since the rename too. **Neither had ever been reached, for the same
reason: the target could not be built at all.** One further adjustment was needed
— both services are `@MainActor`, so the tests are annotated `@MainActor` rather
than relaxing the shipping types' concurrency surface, which a test-host fix has
no business changing.

**All seven now execute and pass, run normally with no override**, named
individually in the log:

```
attestationBodyIsJwsOnly · attestationBodyHasNoIdentityFields · outcomeMapping
unknownOutcomeIsNotSuccess · bindingTokenDecodes · bindingTokenRefusesJunk
endpointConstruction                                     ** TEST SUCCEEDED **
```

**The project delta is measured rather than asserted: 4 lines, every one of them
`TEST_HOST`, zero references to the UI-test target or `USES_XCTRUNNER`**;
`plutil -lint` passes; Debug and Release build clean; the structural suite still
passes 26 of 26.

**So U5e's client evidence is now: two clean builds, 26 structural assertions and
7 passing unit tests.**

### The standing Phase 3 exit assertion was re-checked, not assumed

`C5e-20` — `LocalFactoryReset.perform` still has **exactly two callers**. It
first reported three; the third was a **doc comment** in
`AccountDeletionTransaction.swift`. The invariant held and the assertion was
wrong. **Third occurrence of that shape in this phase**, after `U5c-34` and
`E5d-STRUCT1/2/5`: a source-text check must target code, and the files that best
explain a rule are exactly the ones that defeat a naive search for it.

---

## B-24n AND F10 — BOTH DISCHARGED ON GENUINE APPLE. 2026-08-30

**Every committed prediction matched. Nothing was repaired forward.** Purchase
14:58 UTC on Device A, U5f build, fresh Sandbox tester, real Apple payment sheet
headed *Sandbox*.

### Resumption verification, before anything was touched

Repo `33d854a` = `origin/33d854a`, tree clean. **All five Edge Functions
unchanged in version AND SHA** — and no version drift is itself informative,
since `secrets set` is known to re-version all five while changing none, so that
rules out a secrets change as well as a redeploy. Fixture: `membership_rows 0`,
`binding_rows 1`, `conflict_rows 0`, **zero notifications in the five-day gap**.

### B-24n — the eight predictions

| # | Predicted | Observed |
|---|---|---|
| 2 | `binding_method = 'purchase'` | **`purchase`** |
| 3 | NEW `original_transaction_id` | **`2000001228947923`** ≠ `2000001220187383` |
| 4 | `pending_cleanup_at` NULL, `entitlement_ended_at` NULL | **both NULL** |
| 5 | `apple_status 1`, `auto_renew_status 1`, Sandbox | **1 / 1 / Sandbox** |
| 6 | `connected_member` false, `membership_state` `sandbox_only` | **false / `sandbox_only`** |
| 7 | `membership_rows 1`, `binding_rows 1` unchanged | **1 / 1** |
| 8 | `membership_binding_conflict` empty | **0** |

**PREDICTION 2 IS AN ORDERING PROOF, LIKE S-2's, AND IT PROVES AN ABSENCE.**
Provenance is derived, never supplied: `membership_establish_v1` writes
`'purchase'` only when the client's Apple-signed JWS token is not distinct from
our stored binding. So `'purchase'` in the row is evidence that **the legacy
branch was never entered and NO PUT was issued to Apple at all**. There is no
other way to observe a call that did not happen.

### The binding row was never touched, and that is the strongest single number

```
binding_created_at : 2026-08-25 17:31:54.005854+00
binding_updated_at : 2026-08-25 17:31:54.005854+00   -- IDENTICAL
```

**Not merely "one row" — the SAME row, never updated since the legacy claim
created it.** `binding_rows = 1` alone would have been satisfied by deleting the
old row and minting a new one; the identical timestamps exclude that.

So one unchanged token survived, in order: a legacy claim, eleven renewals, a
voluntary cancellation, a genuine expiry, deletion of the membership row, **a
change of Apple Account**, and a fresh purchase — and bound the new subscription
on sight. **"The token is an attribute of the identity, not of a subscription"
is now measured rather than argued**, and the Apple-Account change is the part no
local reproduction could have shown: two different Apple Accounts, one Études
identity, one token, two `originalTransactionId`s.

### Prediction 9 — and U4's UPDATE-ONLY invariant proved incidentally

```
SUBSCRIBED / INITIAL_BUY -> ignored / unestablished   14:58:15.504
```

**A pass, and the race resolved in Apple's favour** — delivery beat attestation.
`unmapped` would have falsified B-24n; `unestablished` is the writer's category
for *the binding resolved and there was nothing to update*, which means the
binding matched **on the very first notification of the subscription's life**.

**And the row therefore came from attestation, not from ingestion.** At 14:58:15
no membership row existed and U4's canonical writer created none — the
UPDATE-ONLY rule corrected on 2026-08-20 **exercised against genuine Apple
traffic**, in exactly the window where a writer that originated rows would have
had to invent `binding_method`. That was never a scheduled assertion; the race
produced it.

**`INITIAL_BUY` also gives the clean first-purchase observation** the record
noted the spent F3b fixture could no longer produce.

### Provenance is IMMUTABLE under refresh, and the race is now quantified

Read after three renewals:

```
binding_method : purchase          -- UNCHANGED
bound_at       : 2026-08-30 14:58:20.651151+00   -- UNCHANGED
renewal_date   : 2026-08-30 15:18:13+00          -- advanced
entitlement_ended_at / pending_cleanup_at : NULL / NULL
```

**A refresh must never be able to rewrite HOW ownership was proved**, or a stream
of ordinary renewals becomes a path to laundering provenance. Verified for
`legacy_claim` during S-3; now verified on the purchase path too, across three
`applied` refreshes that moved `renewal_date` and touched nothing else.

**F11 held through REFRESH, not merely through establishment.** Both scheduling
columns stayed NULL while the row was updated repeatedly — scheduling is a
transition out of entitlement, and an entitled row being refreshed has no
transition to make.

**And the race is measured rather than inferred:**

```
14:58:15.504  Apple's SUBSCRIBED arrives -> no row exists -> unestablished
14:58:20.651  attestation establishes the row (bound_at)
```

**5.1 seconds.** Earlier this was argued from the writer's outcome vocabulary —
`unestablished` means *binding resolved, nothing to update*. The two timestamps
now show the sequence directly, and they are the cleanest evidence in the project
that **U4's canonical writer originates nothing**: it met a mapped, complete,
Apple-signed notification with no row to write, and wrote none.

### F10 — passed on its strongest branch

**The app said nothing and Connected activated.** That is the common case the
design specifies: only propagation and unresolvable refusal earn a word. The
inverse — Apple taking the money while the app said "Purchase unavailable" — is
the defect F10 removed, and it did not occur. **No sign-in step appeared**, so
U5f's "an already-authenticated member sees no extra step" holds on device.

### The refresh loop, captured before the fixture expired

```
14:58:15  SUBSCRIBED / INITIAL_BUY  -> ignored / unestablished
15:02:35  DID_RENEW                 -> applied
15:07:35  DID_RENEW                 -> applied
```

**`unestablished` -> `applied` on the SAME subscription, with no intervention.**
That is the direct demonstration that `unestablished` is a transient race state
and not a defect: attestation established the row moments after Apple's first
delivery, and the very next renewal updated it. **Nothing was re-attested and
nothing was repaired** — the design's claim that a later notification completes
it either way is now observed rather than argued.

**AND THIS SUBSCRIPTION HAS NEVER PRODUCED A SINGLE `unmapped` NOTIFICATION.**
That is the bound-at-source signature, and the contrast with S-3 is the whole of
B-24 in two rows:

| Path | Before binding | After binding |
|---|---|---|
| `legacy_claim` (S-2/S-3) | **14 `unmapped`** | `applied` |
| `purchase` (B-24n) | **none — mapped from birth** | `applied` |

The legacy path had to *acquire* its binding through `GET -> PUT -> GET`, and the
14 unmapped notifications are the record of the window before it did. The
bound-at-source path never has that window, because StoreKit hands Apple the
token at purchase.

---

## B-24n AND F10 — PREDICTIONS, COMMITTED BEFORE THE RUN. 2026-08-25

**Written and committed before the device is touched.** B-24n is the half of
B-24 that no evidence in this project has ever reached: **a purchase BOUND AT
SOURCE**. S-2 and S-3 proved the *legacy claim* — token absent, PUT issued, token
observed, then carried into renewals. B-24n proves the ordinary path a real new
member takes, where Apple is handed the token by StoreKit and we never ask it to
set one.

### Fixture state going in — verified, not assumed

`membership_rows = 0`, `binding_rows = 1`. **The binding row was deliberately NOT
deleted**: the token is an attribute of the IDENTITY, not of a subscription, so
the new purchase must carry the SAME token the legacy claim used. Deleting it
would mint a new one and quietly change what is being tested.

The fresh Sandbox tester has no purchase history, so this should be a genuine
**`INITIAL_BUY`** — the clean first-purchase observation the spent F3b fixture
could no longer produce.

### B-24n predictions

| # | Prediction | Falsified by |
|---|---|---|
| 1 | Purchase carries `.appAccountToken(binding)` | Cannot fail — enforced by the type |
| 2 | `binding_method = **'purchase'**` | `'legacy_claim'` |
| 3 | `original_transaction_id` is a **NEW** value ≠ `2000001220187383` | The old id reappearing |
| 4 | `pending_cleanup_at` **NULL**, `entitlement_ended_at` **NULL** | Either non-null — F11 breached |
| 5 | `apple_status = 1`, `auto_renew_status = 1`, `environment = 'Sandbox'` | Anything else |
| 6 | `connected_member()` **false**, `membership_state()` **`sandbox_only`** | `true`, or `'expired'` — D4 breached |
| 7 | `membership_rows = 1`, `binding_rows = **1** (UNCHANGED)` | A second binding row |
| 8 | `membership_binding_conflict` stays **empty** | Any row |

**PREDICTION 2 IS THE WHOLE UNIT, AND IT IS AN ORDERING PROOF LIKE S-2's.**
Provenance is *derived*, never supplied — `membership_establish_v1` sets
`'purchase'` only when the client's JWS token is not distinct from our stored
binding. So `'purchase'` in the row is evidence that **the client's own
Apple-signed JWS already carried our token**, which means the legacy branch was
never entered and **no PUT was issued at all**. The row evidences the absence of
a call, which is the only way to test it from outside.

### PREDICTION 9 — the notification, and the trap in it

**The `SUBSCRIBED`/`INITIAL_BUY` notification must NOT be `unmapped`.**

Two outcomes are both passes, and which one lands is a RACE with no correct
answer:

- **`applied`** — attestation established the row before Apple's notification
  arrived;
- **`ignored`/`unestablished`** — the notification won, so the binding resolved
  but there was no row to update yet. U4's writer is UPDATE-ONLY and **must not**
  originate one.

**`ignored`/`unmapped` FALSIFIES B-24n.** That is the category all 14
pre-binding notifications landed in, and it means Apple did not carry our token
into the purchase. The distinction between `unmapped` and `unestablished` is
exactly the assertion: the first says *no binding matched*, the second says *the
binding matched and there was simply nothing to update yet*.

**Do not "fix" an `unestablished` by re-attesting and calling it `applied`.**
Record which one landed; a later notification will be `applied` either way.

### F10 predictions — the member is told nothing

| # | Prediction | Falsified by |
|---|---|---|
| 10 | No failure copy at any point | "Purchase unavailable", any error alert |
| 11 | Common case says **nothing** and Connected simply activates | Any message where none is warranted |
| 12 | If the entitlement lags: **"Finishing setup — this completes on its own, no action needed"** | The words *fail, error, unavailable, try again, retry, refund, lost* |

**F10 exists because Apple used to take the money while the app said "Purchase
unavailable"**, inviting a second purchase. The unit test pins the vocabulary;
this run pins the behaviour on a real Apple payment sheet.

### What this run does NOT do

No enforcement, no cleanup, no worker, no Production promotion. **`membership`
holding a row again does not entitle anything** — prediction 6 says so
explicitly, and D4 is what makes a Sandbox row honest rather than dangerous.

---

## Q1 DISCHARGED, AND MOST OF G6a, ON GENUINE APPLE — 2026-08-25

**Obtained incidentally while clearing the fixture for B-24n**, which is exactly
how Q1 was always meant to be scored: *"Read the row after G6a's genuine expiry
... Costs no waiting."*

The lifecycle, all four notifications **`applied`** — the binding kept mapping
every type, not just `DID_RENEW`:

```
18:18:10  DID_RENEW                                        -> applied
19:18:08  DID_RENEW                                        -> applied
19:31:39  DID_CHANGE_RENEWAL_STATUS / AUTO_RENEW_DISABLED   -> applied
20:19:03  EXPIRED / VOLUNTARY                               -> applied
```

### Q1 — the quarantine arithmetic, on real Apple dates

| | |
|---|---|
| `entitlement_ended_at` | `2026-08-25 20:19:00` |
| `pending_cleanup_at` | `2026-10-24 20:19:00` |
| Difference | **EXACTLY 60 days** |

**And the end instant came from APPLE, not our clock** — `entitlement_ended_at`
is `20:19:00` exactly, while `updated_at` is `20:19:05.099`. The writer preferred
Apple's own paid-through date over the moment we happened to hear about it, which
is what makes the 60 days measured from the truth.

**THIS IS THE FIRST NON-NULL `pending_cleanup_at` IN THIS PROJECT'S HISTORY, AND
IT IS CORRECT.** Scheduling is a *transition* from entitled to not-entitled;
U5's establishment never schedules (F11), and this row was scheduled by U4's
canonical writer on a genuine expiry. **No worker exists, so nothing acts on it.**

### G6a — voluntary cancellation, and the Cancel/Grace conflation did NOT occur

- **Entitlement was continuous to the paid-through date.** Cancelled 19:31, and
  the subscription stayed `apple_status = 1` and entitled until 20:19.
- **Billing Grace was NEVER entered** — its appearance would have been a fail. No
  `DID_FAIL_TO_RENEW`, no `grace_period_expires_date`, `is_in_billing_retry`
  false throughout. **Cancellation is a renewal-preference change, not a billing
  event**, confirmed on real Apple state rather than argued from the table.
- At expiry: `apple_status = 2`, `expiration_intent = 1` (voluntary), derived
  entitlement false, quarantine scheduled.

**What G6a still does NOT have:** the presence-hidden half, which needs Device B
as an observer and belongs with U6/U7. Recorded as partial rather than passed.

### One prediction of mine was wrong, and the correction is the lesson

I predicted expiry at **19:19**. A further renewal fired at **19:18**, before the
cancellation registered at 19:31, so the subscription ran to **20:19** instead.
**The mechanism was right and the timing assumption was wrong** — I assumed the
cancellation would land before the next hourly renewal, and there was no reason
it had to. With an accelerated renewal rate, any instruction that takes minutes
to carry out can be overtaken by a renewal.

---

## GENUINE APPLE SANDBOX — S-1, S-2 AND S-3 ALL DISCHARGED, 2026-08-25

**The first evidence in this project that is not "verified against a faithful
local reproduction".** Device A, a real Sandbox subscription, Apple's own
servers, the deployed endpoints.

### The fixture, and why the order it was created in did not matter

Purchase on the **pre-U5f build** (F3b-era, `e157b1c`), which is *structurally*
incapable of binding: `product.purchase()` with no options and **zero**
`appAccountToken` references anywhere in it. SIWA was completed **after** the
purchase, which changes nothing — binding requires `ensure_membership_binding`
plus Set App Account Token, and that build has neither.

**Apple confirmed the fixture independently**: the resulting `SUBSCRIBED` /
`RESUBSCRIBE` notification landed `ignored`/**`unmapped`** — Apple's own
statement that the subscription carried no `appAccountToken`.

Two incidental observations worth keeping:

- **Apple REUSED `originalTransactionId 2000001220187383`** across
  lapse-and-resubscribe on the same tester. That is evidence on a question
  `CLAUDE.md` deliberately leaves open. **It does not license depending on it**;
  the standing rule stands.
- **Sign in with Apple returned the SAME `sub` after the credential had been
  manually revoked**, re-authenticating the existing identity (created
  2026-08-15) rather than minting a new one. `auth.users` did not grow.

### S-1 — a genuine Apple JWS against the PINNED anchor

The first-launch attestation POSTed to `membership_attest_v1` and received
**HTTP 200 in ~3.0 s**. A real `currentEntitlements` JWS passed x5c chain
verification against **Apple Root CA G3** and the full claim boundary — bundleId,
`Sandbox`, Monthly, non-Family-Shared.

**This is the half no local evidence could ever supply.** Every local fixture is
signed by a throwaway CA, so a dead verifier and a healthy one are
indistinguishable until a real Apple payload passes the shipping anchor.

**Attestation fired UNATTENDED on the first cold launch**, with no user action —
the invariant `(locally entitled ∧ hasConnectedIdentity ∧ isConfigured)` holding
and nothing else gating it.

### S-2 — the legacy claim, and the ordering is evidenced by the ROW

| | |
|---|---|
| `binding_rows` | 0 -> **1** |
| `membership_rows` | 0 -> **1** |
| `binding_method` | **`legacy_claim`** |
| `environment` / `original_transaction_id` | `Sandbox` / `2000001220187383` |
| `pending_cleanup_at` / `entitlement_ended_at` | **NULL / NULL** — F11 held |
| `conflict_rows` | **0** |

**`legacy_claim` is only reachable through `GET -> PUT -> GET`.** The writer
derives that provenance when the client's JWS did **not** carry our token, and it
writes at all only when **Apple reports our token**. Both true in one row means:
the pre-claim read saw no token, the PUT happened, and an independent re-read
observed ours before establishment. `renewal_info_signed_date` 0.5 s before the
write confirms the state stored came from the **post-claim** read.

**Client and server agree to the millisecond:** `bound_at` 17:31:55.757 UTC
against a client-observed 200 at 17:31:55.779 UTC.

**The 401 seen just beforehand is expected**: a days-old access token, PostgREST
answering 401, `ensureValidBackendSession` refreshing via `/auth/token`, and
everything after succeeding. **The binding row is the proof it resolved** —
`ensure_membership_binding()` is `authenticated`-only and derives identity from
`auth.uid()`, so a stale token could not have created it.

### S-3 — THE SINGLE ASSERTION THAT PROVES THE WHOLE PROTOCOL

At **18:18:10** Apple sent `DID_RENEW` for the same subscription, and ingestion
recorded it **`applied`** with **no failure category**.

**The before/after is as clean as this project will ever get:** 14 notifications
for this tester are `ignored`/`unmapped`; **one** is `applied`. Same
subscription, same `originalTransactionId`, same tester, same endpoint. **The
only thing that changed between them is the binding.**

`applied` requires `membership_resolve_binding_v1` to map an `appAccountToken` to
an identity — so **Apple carried our binding token into a real renewal**, which
is precisely what B-24 predicted and what no stub could demonstrate.

The row refreshed correctly: `renewal_date` 18:19 -> **19:19**, `updated_at`
0.27 s after Apple's signature, `last_notification_uuid` populated.

**Provenance stayed immutable through the refresh** — `binding_method` still
`legacy_claim`, and `bound_at = created_at`, so the canonical writer did not
re-provenance an established row.

### D4 confirmed on a REAL Apple subscription

`connected_member()` = **false** and `membership_state()` = **`sandbox_only`**,
on a live, entitled, Apple-verified Sandbox membership. **A Sandbox subscription
confers no Production entitlement**, demonstrated on genuine Apple state rather
than a fixture.

---

## U5d — RESULTS. 469 assertions green, 2026-08-23. LOCAL ONLY, NOT DEPLOYED

**`membership_attest_v1` implements B-24's protocol end to end.** One Edge
Function, one `config.toml` entry, one `_shared` helper moved. **No SQL** — the
B-23 delta is **unchanged at 20 problems**, exactly the U5b schema delta, which
is how "U5d added no schema surface" is checked rather than asserted.

| Suite | Result |
|---|---|
| U3 acceptance | **97 of 97** |
| U4 modules / acceptance / e2e | **48 / 96 / 43** |
| U5c modules | **68 of 68** |
| U5b acceptance | **55 of 55** |
| **U5d e2e** | **62 of 62**, new |
| **Total** | **469** |

### A30 — THE LOCAL HALF IS DISCHARGED, AND IT IS AN ORDERING PROOF

**A30 is not "the row ends up correct".** An implementation that establishes on
the strength of the PUT's own 200 reaches an **identical final row** and is
wrong, because Apple documents no read-after-write guarantee and P12 already
proved Apple-side propagation is real and indistinguishable from
misconfiguration. So the harness records every outbound request and asserts the
**sequence**.

**Observed call log for the legacy claim (`E5d-A30c`):**

```
GET:2000000999999999 , PUT:2000000999999999 , GET:2000000999999999 , GET:2000000999999999
```

read → **PUT** → independent re-read → authoritative re-read before establishing.

- `E5d-A30e` — at least one Apple **read** happened *after* the PUT.
- `E5d-A30f` — the call *immediately* after the PUT is a **read**, not a write.
- `E5d-A30b` — the row was reached via the claim path (`claimed: true`).
- `E5d-A30d` — provenance derived as `legacy_claim`, not asserted by the caller.

**A correct row in the wrong order fails here.** The genuine-Apple half of A30
remains outstanding and discharges only against Apple (S-2/S-3).

### Every branch of the U5 matrix, proven end to end

| Path | Outcome | Assertions |
|---|---|---|
| New purchase (Apple already has our token) | `established`, provenance `purchase`, **no PUT issued** | E5d-13/14/17 |
| Legacy claim (Apple has no token) | `established`, `legacy_claim`, correct ordering | E5d-A30a–f |
| Orphan rebind (token matches no live binding) | `established` via one PUT | E5d-31/32/33 |
| **Live-binding conflict** | `conflict`, no row, **NO PUT — we never overwrite a live binding** | E5d-34/35/**36**/37 |
| **Propagation delay** | `pending`, `wrote:false`, `retry:true`, **no row** | E5d-24–28 |
| …completed by a later attestation | `established`, **without a second PUT** | E5d-29/30 |
| Terminal Apple refusal (Family Sharing, 4000185) | `terminal_refusal`, no row, **no re-read after a permanent refusal** | E5d-38–41 |
| Retryable Apple failure (PUT 5xx, status 5xx, empty) | `502`, `wrote:false`, no row | E5d-42–48 |
| Idempotent refresh | `already_established`, **provenance immutable** | E5d-21/22/23 |

**E5d-36 is the one to keep.** Apple would happily let us overwrite another
identity's token — that is exactly why our rule has to be the protection, and
this assertion proves the endpoint never even asks.

### The trust boundary, asserted structurally

| # | Assertion |
|---|---|
| `E5d-STRUCT1` | the endpoint imports **and** calls `verifyAttestationJWS` |
| `E5d-STRUCT2` | **the endpoint never calls `verifyAppleJWS`** — B-31's structural half |
| `E5d-STRUCT3` | no identity, environment or transaction id is ever read from the body |
| `E5d-STRUCT4` | the client JWS is never logged |
| `E5d-STRUCT5` | exactly one establishment call site |
| `E5d-STRUCT6` | the endpoint holds no SQL of its own |
| `E5d-STRUCT7` | U5d widened no table privilege |
| `E5d-11` | **a refused claim never reached Apple at all** |

`STRUCT2` is only a one-line check because the live-read verification moved into
`_shared/appstore/readAuthoritativeState`. **That was a design decision taken to
make the assertion possible**: with the endpoint holding no verifier call of its
own, "client input goes through the claim boundary" stops being a reviewer's
judgement about which variable reached which call.

### THREE STRUCTURAL ASSERTIONS FAILED ON A CORRECT FILE, AND THE REASON REPEATED

`STRUCT1`, `STRUCT2` and `STRUCT5` first searched the raw source text — and the
endpoint's own header says *"THIS FUNCTION NEVER CALLS verifyAppleJWS"*. **The
file explaining the rule defeated the check for the rule.** They now strip
comments first.

**This is the second time in two units** — `U5c-34` had the identical shape. The
generalisation is worth more than either fix: **a source-text assertion must
target code, and a well-commented file is exactly the one most likely to defeat
it.**

### A cross-suite state leak, caught by running the suites in sequence

`E5d-4` and `E5d-12` asserted `count(*) from public.membership = 0` **globally**.
They passed standalone and failed at 60/62 when `acceptance.sh` ran first and
left six rows behind. Scoped to the identities under test — which is what "this
request wrote nothing" actually means. **A suite that only ever runs alone can
carry an assertion that is silently order-dependent.**

### The labelled U5 stand-ins are retired

Both U4 suites created their authoritative row with a raw INSERT labelled a
FIXTURE, because U5 did not exist. **They now call the real
`membership_establish_v1`**, so what follows is U4 refreshing a row the real
writer established, with provenance *derived*, rather than one the test
manufactured. `A47f` still asserts structurally that no U4 function inserts, with
U5b's writer excluded by name.

---

## U5c — RESULTS. 406 assertions green, 2026-08-23. LOCAL ONLY, NOT DEPLOYED

**U5c is `_shared/appstore` only: two modules, no SQL, no Edge Function, no
client change.** The B-23 delta is **unchanged at 20 problems** — identical to
U5b's — which is the check that U5c added no schema surface at all.

| Suite | Result |
|---|---|
| U3 acceptance | **97 of 97** |
| U4 modules / acceptance / e2e | **48 / 95 / 43** — U4's verifier behaviour preserved |
| U5c modules | **68 of 68**, new |
| U5b acceptance | **55 of 55** |
| **Total** | **406** |

### THE HOSTILE FIXTURES ARE ALL VALIDLY APPLE-SIGNED, AND THAT IS THE POINT

Every `attest_*` fixture passes signature verification against the test CA. **If
a claim check regresses, the payload does not start failing somewhere else — it
starts being ACCEPTED.** A suite that only fed this code malformed input would
have proved nothing about B-31, because B-31 is precisely the observation that
"Apple signed it" is true of a stranger's subscription too.

| Fixture | Must be | Assertion |
|---|---|---|
| another app's genuine subscription | `foreign_app`, **terminal** | U5c-12, U5c-20 |
| our app, an unrelated product | `foreign_product`, **terminal** | U5c-13, U5c-21 |
| `FAMILY_SHARED` | `family_shared`, **terminal** | U5c-16, U5c-22 |
| Production while only Sandbox attestable | `environment`, **not** terminal | U5c-14, U5c-23 |
| `Xcode` environment | `environment`, even when Production is allowed | U5c-15, U5c-25 |
| a **year-old** JWS | **ACCEPTED** | U5c-9 |

**U5c-9 is the F3b consequence made executable.** A JWS signed a year ago must
verify, because that is G11's dormant pre-cutover subscriber. A freshness window
would have refused exactly the member U5 exists to rescue, and this assertion is
what stops one being reintroduced later by someone who did not read P2.

### A DEFECT WAS INTRODUCED AND CAUGHT BY THE BATTERY, NOT BY REVIEW

**Apple's Set App Account Token answers 200 with an EMPTY BODY.** `request()`
enforces "a 200 whose body we cannot read is NOT an authoritative answer" — which
is exactly right for every read endpoint, and **wrong for a write endpoint that
returns nothing**. As first written, every *successful* token assignment would
have thrown `malformed`, so the legacy claim path would have failed 100% of the
time while Apple was accepting every call — and the failure would have looked
like an Apple problem rather than ours.

It surfaced as `U5c-36..40` reporting SKIP with an unparseable-body error, which
is only visible because the battery asserts the **request shape** against the
real signing path instead of stubbing the signer. The fix is an explicit
`allowEmptyBody` on the one endpoint that needs it; the general rule is
untouched, because the general rule is right.

**The lesson generalises: a safety rule inherited from read paths can be a defect
on a write path, and "it threw" is not the same as "it failed".**

### TWO ASSERTIONS WERE WRONG AND THE WAY THEY WERE WRONG IS KEPT

`U5c-18` originally fed a chain whose **third** certificate was swapped for a
hostile root and expected a refusal. **`verifyChain` ignores `x5c[2]` entirely** —
it verifies the intermediate against OUR anchor, which *is* the pinning property
— so accepting it is correct and the assertion was testing a mechanism that
deliberately does not exist. It now asserts that the substituted root is ignored,
and pinning is asserted the only way that means anything: **the same payload that
passes under the test anchor FAILS under the real Apple Root CA G3** (`U5c-18b`).

`U5c-34` searched the source text for `APPLE_ASSN_ALLOWED_ENVIRONMENTS` and
failed on a **correct** file — `attest.ts` names that variable in its own
explanation of why it must never read it. It now targets the `get(...)` call.

### The claim/trust boundary, asserted rather than described

- **Signature first**, delegated to the unchanged `verifyAppleJWS`. Nothing in a
  payload means anything until Apple has vouched for it.
- Then **bundleId**, **environment**, **product**, **Family Sharing**, and
  **originalTransactionId** — cheapest and most decisive first.
- **Revocation is deliberately NOT checked**: the JWS answers *who*, never *now*.
  That is B-24's split, and F3b's P2 is why it must be.
- **`APPLE_ATTEST_ALLOWED_ENVIRONMENTS` is separate from the ASSN variable**,
  asserted behaviourally (U5c-32: setting the ASSN variable widens nothing) and
  structurally (U5c-34).
- **The JWS is never returned, logged or echoed** — U5c-26/27 on the result,
  U5c-28 on the error message, with U5c-29 confirming the error still names the
  Apple-signed claim so a refusal is diagnosable.

### The re-read is a code path now, not a discipline

`setAppAccountToken` returns `void`, so a 200 **cannot** be mistaken for
confirmation (U5c-36). `observeAppAccountToken` performs a fresh authoritative
read and verifies the nested JWS in its own right against the pinned anchor
(U5c-64). `interpretObservation` names four outcomes, and the third is the one
that had to be impossible to collapse:

| Observation | Outcome | U5d must |
|---|---|---|
| our token | `ours` | establish |
| entry found, **no token yet** | **`propagating`** | **write nothing, retry later — NOT failure** |
| somebody else's token | `foreign` | refuse and record (B-24) |
| no entry at all | `unavailable` | retry — never read as "not bound" |

---

## U5b — RESULTS. 338 assertions green, 2026-08-23. LOCAL ONLY, NOT DEPLOYED

**U5b is the SQL foundation for ownership establishment.** One table, one
function, two grants, two helpers replaced. No Edge Function, no Apple request,
no policy, nothing scheduled, nothing deleted. `_shared/appstore` is U5c; the
attest endpoint is U5d.

| Suite | Result |
|---|---|
| U3 acceptance | **97 of 97** (was 93; +4 from the U5b re-pointing below) |
| U4 modules | **48 of 48**, unchanged |
| U4 acceptance | **95 of 95** (was 94; +1) |
| U4 e2e | **43 of 43** (was 40; +3 from E17's rewrite) |
| **U5b acceptance** | **55 of 55**, new |
| **Total** | **338** |

### THE BLAST RADIUS WAS UNDER-PREDICTED, AND THE MISS IS INSTRUCTIVE

**Predicted: 4 assertions. Actual: 11.** The prediction named A47i, A53b, A54d
and E17 — and those four were exactly right. What it missed were **seven
assertions that pin the privilege surface and the object counts**, which any unit
adding a table, a grant and a function necessarily moves:

| Missed | Suite | Why it moved |
|---|---|---|
| A4, A3h | U3 | assert **zero** client-reachable membership objects; U5b grants `ensure_membership_binding` to `authenticated` |
| A22b | U3 | the same thing observed over real HTTP — the authenticated RPC now returns 200 |
| A41 | U4 | membership table count 6 -> 7 |
| A45 | U4 | `service_role` EXECUTE set gains `membership_establish_v1` |
| A45e | U4 | asserted `ensure_membership_binding` **still ungranted (U5)** — it was written expecting to change |
| A47f | U4 | "no U4 function inserts into membership", scoped by the `membership%` prefix, which U5b's writer also matches |

**None is a defect and none was weakened to pass.** Every one is a deliberate
state change detected by an assertion doing its job — the U3 and U4 cells had
*said* U5 would make this grant. **The lesson is that "which assertions change
their result" is not the same question as "which assertions mention the thing I
am changing", and the first is the one that needs measuring.**

**Three were made STRICTER rather than merely re-pointed:**

- **A4** no longer asserts "zero"; it asserts **exactly one, and precisely which
  one** (`A4u5`: `ensure_membership_binding` reachable by `authenticated` **alone**).
- **A22** splits the binding RPC out of the aggregate — folding it in would let
  "one 2xx somewhere" pass for either role. `A22d` pins anon still refused,
  `A22e`/`A22f` pin that authenticated receives **its own** token over real HTTP,
  which is the half no catalog query can prove.
- **A47f** excludes U5b's writer **by name**, not by weakening the pattern, so it
  still fails if U4's canonical writer ever gains an INSERT.

### E17 was testing the wrong thing in the wrong suite, and the rewrite is stronger

E17 asserted Production entitlement at the end of a chain that is **Sandbox end
to end** — the notification must be Sandbox to pass
`APPLE_ASSN_ALLOWED_ENVIRONMENTS`, and ingestion applies state to the row of the
notification's own environment, so under D4 no Sandbox notification can ever
produce entitlement. **That is correct behaviour, not a test problem.**

It now asserts the **row**, which is what `e2e.sh` is for by its own description.
And it gained force in the process: the fixture carries a **future
`expiresDate`**, so the row looks entitled on its face and must still confer
nothing (`E17d`), with `membership_state` reporting `sandbox_only` rather than
`expired` (`E17e`). **That is D4 observed end to end through the real function
rather than argued in SQL.**

### The assertion most worth keeping — A60

A **Sandbox-only identity that is in the cutover snapshot** must derive `false`.
Under the obvious fix — `and m.environment = 'Production'` in the WHERE clause —
the row set empties, `bool_or` over an empty set is NULL, and the predicate falls
through to the **grandfather** clause, granting Production entitlement to a
sandbox tester *by the compatibility clause*. **The natural implementation fails
in exactly the direction that matters**, which is why the environment test lives
inside `bool_or` instead. `A60c` is its purest form: the same row with every
derivation input NULL, where U3's coalesce lesson has to hold again.

### F11 is asserted behaviourally AND structurally

`A63c`/`A63d` on a live subscription and `A63h` on a **born-lapsed** one — the
dangerous case, where a deadline computed from Apple's own dates could already be
in the past. `A67` adds the structural half: **exactly one function in the whole
schema inserts into `public.membership`, and it is the establishment writer.**

### PREDICTED B-23 DELTA — measured, not estimated

The gate compares local against **production**, so with U5b applied locally and
not deployed it correctly reports **GATE NOT MET — 20 problems**, every one of
them a U5b object. That is the expected pre-deploy state; it returns GREEN after
deploy and recapture, exactly as U4 did.

| Surface | Delta | Detail |
|---|---|---|
| `columns` | **+7** | `membership_binding_conflict` |
| `constraints` | **+5** | its pkey, FK, and three CHECKs |
| `rls_enabled` | **+1** | RLS on the new table |
| `functions` | **+1 new, 2 MODIFIED** | `membership_establish_v1`; `connected_member` and `membership_state` replaced |
| `function_grants` | **+3 new, 1 MODIFIED** | 3 rows for `membership_establish_v1`; `ensure_membership_binding`/`authenticated` flips `can_execute` false -> true |
| `table_grants` | **0** | IDENTICAL |
| `column_grants` | **0** | IDENTICAL |
| `policies` | **0** | IDENTICAL — U5b enforces nothing |
| `triggers`, `storage_buckets` | **0** | IDENTICAL |

**U5b IS NOT PURELY ADDITIVE, and the deployment package must say so.** Like U4
— which modified four CHECK constraints — it **modifies** two function
definitions and one grant row. U3 could be described as "additive and inert";
U5b cannot, and the rollback differs accordingly.

**The `account_id_format` constraint pair in the raw diff is NOT U5b's.** It is
the single declared standing exception in `baseline-exceptions.json`, a
PostgreSQL parenthesisation normalisation, and the gate detects and approves it
as such. Counting it as part of U5b's delta would overstate the change by one.

**Zero table privilege, zero column privilege, zero policy change** — U3's A3f
invariant survives U5b, and the whole client-reachable surface U5 creates is one
argument-less function.

---

### U2 — PREDICTIONS, committed 2026-08-16 BEFORE any destructive run

**Written and committed before execution, in the D14/D15 style.** Nothing below
is a result. Environment: the B-23 local reproduction, gate green at the time of
the run; the real unmodified `delete_account_v1` served by the local edge
runtime; production untouched.

**Fault injection, named and bounded.** B-4 needs a real deletion step to fail
after meaningful work. The three routes Phase 1 declined stay declined — no
temporarily-broken production deploy, no QA-only injection inside the function,
no DDL against production. The fourth route exists only now that B-23 does:
**DDL against a disposable local database.** `supabase/tests/u2/fault-inject.sql`
adds a `before delete on public.posts` trigger that raises. It cannot alter
production because the function's source is untouched and the trigger is **not**
in `supabase/migrations/` — the B-23 gate would fail on an extra trigger if it
ever were.

#### B-4 — honest `success:false`

*Fixture:* three local identities. A departing, B live recipient and third
party, C second live recipient. A owns 2 posts, 2 sent attachment rows, 1
received row, 1 authored comment on B's post, 2 shares, 1 comment view, 1
avatar, 2 attachment objects. Non-vacuous by construction and asserted before
the run.

*Operation:* inject the fault, then POST `/functions/v1/delete_account_v1` with
A's own access token.

| # | Prediction | Fail if |
|---|---|---|
| 4.1 | Response is **HTTP 500** with `success: false` | `success: true`, or a 2xx |
| 4.2 | `step` is **`"posts"`** | any other step, or absent — the point of B-4 is that the failing step is *named* |
| 4.3 | Work before that step **completed**: A's `connected_attachments` rows gone in both directions; A's `users/<A>/` attachment objects gone; A's avatar object gone; A's `post_comment_views` gone; `post_shares` where A is recipient gone; A's authored comment gone | any of these still present — the failure would then be too early to be meaningful |
| 4.4 | Work at and after that step **did not happen**: A's 2 posts, A's follows, A's `account_directory` row and A's `auth.users` row all still present | any absent |
| 4.5 | Protected state intact: B's post, B's reply addressed to A, C's comment, B→C row and its object, B's avatar, B↔C follow | any removed |

#### B-13 — retry and idempotency, scored separately from B-4

*Fixture:* **the actual partial state B-4 leaves behind.** Not a fresh one.

*Operation:* drop the trigger, then retry the same call with the same token.

| # | Prediction | Fail if |
|---|---|---|
| 13.1 | Retry returns **`{"success": true}`** | anything else |
| 13.2 | Already-completed work causes **no** false failure — the re-run of steps 1, 3, 3b, 4 and the early step-5 deletes matches nothing and does not error | any step errors on an empty match |
| 13.3 | Remaining work completes: A's posts, follows, `account_directory` and `auth.users` row all gone | any remains |
| 13.4 | Protected state still intact — same list as 4.5 | any removed |
| 13.5 | A **third** call returns **401 `Invalid session`** | it returns success, or 500. **401 is the CORRECT answer and not a defect**: `auth.users` is gone so the token no longer resolves to a user. Do not "fix" it by treating 401 as success — that would hand away the only authorisation gate the function has |

#### B-12 — pagination past 1000

*Fixture:* account D with **1500** objects under the single prefix
`users/<D>/bulk/`, plus protected bystander E. 1500 rather than 1001 so an
off-by-one in the paging arithmetic is caught too. Not spread across prefixes:
that would leave every list call returning one short page, which is exactly the
already-proven case.

| # | Prediction | Fail if |
|---|---|---|
| 12.1 | Count under `users/<D>/` **before** is **exactly 1500**, all in one folder | fewer, or spread across folders |
| 12.2 | Deletion returns `{"success": true}` | anything else |
| 12.3 | Count under `users/<D>/` **after** is **exactly 0**, counted independently in `storage.objects` and not inferred from the function result | any object remains — a residue of ~500 would be the unpaged first-iteration bug this row exists for |
| 12.4 | E's 2 attachment objects and 1 avatar object **survive** | any removed |

#### B-9 — the two-recipient subcase

*Fixture:* one asset `X`, **one** `storage_path`, **two live recipient rows** —
A→B and A→C. `connected_attachments_asset_recipient_unique` is
`UNIQUE(asset_id, recipient_user_id)` and the path CHECK derives the path from
sender and asset alone, so this is the only shape the case can take.

**The expected policy is reconstructed from the CURRENT deployed function, not
invented here, and it is NOT what the subcase originally described.** B-9's cell
framed it as "step 3b deletes the soft-deleted row while step 3 correctly
preserves the object under B-1" — that framing predates 2026-08-13. Step 2, the
reference-counted preservation, was **removed** in that revision; step 3 now
sweeps `users/<uid>/` unconditionally and step 3b deletes **every** sender row.
So under the settled post-revision semantics — *attachments they SENT are
DELETED, rows and objects, even where a recipient still holds a live reference* —
both recipients lose the reference and the shared object goes.

| # | Prediction | Fail if |
|---|---|---|
| 9.1 | **Both** A→B and A→C rows are deleted | either survives — one surviving row would mean the sender-scoped predicate is not reaching all rows for a shared asset |
| 9.2 | The **single shared object** `users/<A>/connected/<X>.pdf` is deleted | it remains |
| 9.3 | No error arises from two rows naming **one** path — the object is swept once by step 3 and the rows removed by a set-based step 3b | any duplicate-removal error or partial failure |
| 9.4 | The third-party row **B→C** and its object under `users/<B>/` survive | either removed. This is B-9's own lesson: scoping on `sender_user_id` must not reach a row whose sender is somebody else |
| 9.5 | B's and C's accounts, directory rows and own content are untouched | any removed |

**Scored at the agreed evidence level:** *verified against a faithful local
reproduction*, never "verified in production". B-4 and B-13 share one
induced-failure/retry run and stay separately scored.

### U2 — RESULTS, 2026-08-16. ALL FOUR OBLIGATIONS PASS.

**Scored at the agreed evidence level: verified against a faithful local
reproduction, NOT verified in production.** B-23's gate was green immediately
before the run and again afterwards. The function under test was the **real,
unmodified `delete_account_v1`** — `git diff` against HEAD is empty and its last
touching commit is `0f5896d`, before U2 began.

#### B-4 — PASS on all five assertions

*Fixture:* A, B, C. A held 2 posts, 2 sent attachment rows, 1 received row, 1
authored comment on B's post, 2 shares, 1 comment view, 1 avatar object, 2
attachment objects. Every count asserted non-zero before the run.

*Operation:* `u2_b4_fault_posts` installed on the local database, then A's own
token POSTed to the function.

*Observed:* `{"success":false,"step":"posts","error":"Error: U2/B-4 injected
fault: posts delete blocked"}`, **HTTP 500**.

| # | Predicted | Observed |
|---|---|---|
| 4.1 | HTTP 500, `success:false` | **HTTP 500, `success:false`** |
| 4.2 | `step` is `"posts"` | **`"posts"`** |
| 4.3 | Earlier work completed | sent rows 2→0, received 1→0, attachment objects 2→0, avatar 1→0, comment views 1→0, received shares 1→0, authored comments 1→0 |
| 4.4 | Work at/after the failing step did not happen | posts **2**, follows **4**, directory **1**, `auth.users` **1** — all unchanged |
| 4.5 | Protected state intact | B and C unchanged on every measure |

**This is the assertion the 2026-08-11 production run could not make.** That run
was a success case, and the old function returned success unconditionally — so a
green result did not discriminate between the two implementations. A named
failing step does.

#### B-13 — PASS on all five assertions, scored separately

*Fixture:* **the actual partial state B-4 left**, not a fresh one.

| # | Predicted | Observed |
|---|---|---|
| 13.1 | Retry returns `{"success":true}` | **`{"success":true}`, HTTP 200** |
| 13.2 | No false failure from completed work | none — steps 1, 3, 3b, 4 and the early step-5 deletes re-ran against empty sets and returned cleanly |
| 13.3 | Remaining work completes | posts 2→0, follows 4→0, directory 1→0, `auth.users` 1→0 |
| 13.4 | Protected state intact | B and C unchanged |
| 13.5 | Third call returns 401 `Invalid session` | **`Invalid session`, HTTP 401** |

**13.5 is the caveat this plan wrote down long before it could be run, and it
behaved exactly as described.** The 401 is the *correct* answer: `auth.users` is
gone, so the token no longer resolves to a user. Do not "fix" it by treating 401
as success — the function derives its subject from the verified token, and
accepting an unverifiable one would hand away its only authorisation gate.

#### B-12 — PASS. 1500 objects, one prefix.

| # | Predicted | Observed |
|---|---|---|
| 12.1 | Exactly 1500 under one prefix | **1500** under `users/<D>/bulk/`; **distinct folders under `users/<D>/` = 1**, so a single list call had to page |
| 12.2 | `{"success":true}` | **`{"success":true}`, HTTP 200** |
| 12.3 | Exactly 0 after, counted independently | **0**, counted in `storage.objects` rather than inferred from the function result |
| 12.4 | Bystander survives | E's 2 attachment objects and 1 avatar object all present; `storage.objects` total 1503 → 3 |

**A residue of ~500 would have been the unpaged-first-iteration bug this row
exists for.** 1500 rather than 1001 so an off-by-one in the paging arithmetic
would also have surfaced.

#### B-9 two-recipient subcase — PASS. The subcase is now executed.

*Fixture:* one asset, **one** `storage_path`, **two live recipient rows** — A→B
and A→C — plus a third-party row B→C that must survive.

| # | Predicted | Observed |
|---|---|---|
| 9.1 | Both A→B and A→C deleted | **both 0** |
| 9.2 | The single shared object deleted | **0** |
| 9.3 | No error from two rows naming one path | none — swept once by step 3, rows removed set-wise by step 3b |
| 9.4 | Third-party B→C row and object survive | **both present** |
| 9.5 | B and C untouched | unchanged on every measure |

**The prediction deliberately did not follow B-9's original wording, and the
difference is recorded rather than smoothed over.** The cell framed the subcase
as "step 3b deletes the soft-deleted row while step 3 correctly preserves the
object under B-1". That framing predates 2026-08-13, when step 2 — the
reference-counted preservation — was **removed**. Under the deployed function
step 3 sweeps `users/<uid>/` unconditionally and step 3b deletes every sender
row, so both recipients lose the reference and the shared object goes. The
observed behaviour matches the **settled post-revision** semantics, not the
row's pre-revision description.

**What this closes:** the two-recipient shape was unstageable with two real
Apple IDs, which is why it survived Phase 1 and Phase 2. Three local GoTrue
identities cost nothing, and that is the whole reason B-23 came first.

### U3 — PREDICTIONS, committed 2026-08-16 BEFORE any consequential verification

**Nothing below is a result.** Environment: the B-23 local reproduction, rebuilt
from a destroyed state, gate green immediately before U3 changes. **Production is
not touched by U3's local implementation at all.**

**Test ownership is stated honestly. Several assertions belong to U5 or U7 and
are recorded as future gates rather than manufactured U3 passes** — the writers
they test do not exist.

| # | Assertion | Pass | Owner |
|---|---|---|---|
| A1 | Fresh local migration applies from a destroyed environment | `stop --no-backup` → `start` → `db reset --local` exits 0 | U3 |
| A2 | Structural delta matches prediction exactly | Per-surface counts equal the predicted delta | U3 |
| A3 | Membership tables inaccessible to clients | Zero `table_grants`/`column_grants` rows for the five new tables with grantee `anon` or `authenticated`. **STRENGTHENED 2026-08-17: also zero for `service_role`, zero PUBLIC table privileges, and no non-owner grantee at all in `relacl` — see A3c–A3h.** The original wording was satisfiable while `service_role` held whatever the ambient default ACL supplied | U3 |
| A4 | **Zero client-reachable membership objects** | All three helpers: `can_execute=false`, `direct_execute=false`, `public_execute=false` for `anon` and `authenticated`. **Including `ensure_membership_binding()`, which U5 grants, not U3** | U3 |
| A5 | Unknown post-cutover identity fails closed | No membership row, not in snapshot → `connected_member()` = **false** | U3 |
| A6 | Grandfathered pre-cutover identity resolves true | In snapshot, no membership row, control enabled → **true** | U3 |
| A7 | **Real state overrides grandfathering** | Snapshot UID **plus** a not-entitled membership row → **false**. Invariant 8 | U3 |
| A8 | Entitled row resolves true | `renewal_date` in the future → **true** | U3 |
| A9 | Billing Grace derivation | Past `renewal_date` + `is_in_billing_retry` + **future** `grace_period_expires_date` → **true**; grace NULL or past → **false** | U3 |
| A10 | NULL and unknown input fail closed | `connected_member(null)` → **false**; unknown uuid → **false** | U3 |
| A11 | Grandfather switch works | `grandfather_enabled=false` → A6's identity flips to **false** | U3 |
| A12 | Transaction uniqueness | Second row with the same `(environment, original_transaction_id)` → constraint violation | U3 |
| A13 | Cascade on account deletion | Deleting an `auth.users` row removes its membership, binding and cutover rows | U3 |
| A14 | Snapshot finite and frozen | Local snapshot is **empty** (no local identities captured); re-running the population changes nothing | U3 |
| A15 | No policy or function depends on membership | Zero policies referencing `connected_member`; the 33 existing policies byte-identical | U3 |
| A16 | No Apple request, no cleanup, no endpoint | `membership` empty; `pending_cleanup_at` nowhere set; function list unchanged — **U3 deploys no Edge Function** | U3 |
| A17 | Existing Connected behaviour unchanged | All local backend counts and behaviour identical to pre-U3 | U3 |
| A18 | Production snapshot data treated honestly | Cutover contents are **outside** B-23 structural fidelity and asserted separately | U3 |
| A19 | Same identity, repeated `ensure_membership_binding()` → **identical UUID** | Two calls return the same token | U3 |
| A20 | Concurrent first calls → **one row, one token** | Two simultaneous sessions; one binding row results | U3 |
| A21 | One identity cannot obtain another's token | **The function takes no argument** — verified structurally, and by calling it as two different JWTs | U3 |
| A22 | Membership tables not directly readable | Direct `select` as `anon`/`authenticated` denied | U3 |
| A23 | Duplicate `binding_token` rejected | Unique constraint violation | U3 |
| **A24** | **Binding is lifecycle-independent of membership** — **CORRECTED WORDING.** Deleting a membership row must **not** delete the account's binding, and no FK or cascade exists from `membership` to `membership_binding`. **This is only the structural half.** Ordinary expiry cleanup *retaining* both is a behavioural assertion about a worker that does not exist | Binding survives; no such FK in `constraints` | U3 structural half · **U7** behavioural |
| A25 | **Unbound membership row impossible** | Insert with `binding_method` or `bound_at` null → **rejected**. The central rule as a constraint | U3 |
| A26 | Legacy path needs **no fake membership row** | A binding row exists with **zero** membership rows, and `membership_state()` returns `unknown`/`grandfathered` — never a fabricated state | U3 |
| A27 | Dormant snapshot identity acquires binding **lazily** | Identity in the snapshot with no binding row can create one on demand | U3 |
| A28 | `membership_state()` returns exactly the four states | `entitled` / `expired` / `grandfathered` / `unknown` across staged fixtures. **SUPERSEDED AT U5b, 2026-08-20 — it becomes FIVE.** D4's environment separation adds `sandbox_only`, without which a Sandbox-only identity reports `expired` — which is false, and would corrupt U6a's shadow report by making a tester indistinguishable from a member whose Production subscription lapsed. **The U3 result stands as recorded**; this is a forward note, not a retraction | U3 |
| A29 | Mismatched Apple token never produces an entitled row through the real writer | — | **U5 — not U3.** The writer does not exist |
| A30 | Legacy claim calls `Set App Account Token` and re-reads before writing membership | — | **U5 — not U3** |
| A31 | Orphan rebind permitted; live-binding mismatch refused | — | **U5 — not U3** |

### U3 — EXPLICIT DISPOSITION OF EVERY U3-OWNED PREDICTION, 2026-08-17

**Added because five of them had neither a pass nor a deferral.** A19, A20, A21,
A22 and A27 were labelled owner "U3" in the table above and appeared in neither
the acceptance suite nor the results — not run, not declared future work, simply
absent, while the headline read "63 of 63". A29–A31 were properly declared as
U5 gates, which is what made the omission visible by contrast. **Every row above
now has a disposition here, and no row is discharged by silence.**

| Prediction | Disposition |
|---|---|
| A1, A3–A16 | **Executed**, in the suite, from a destroyed environment |
| A2 | **Executed** as the ten-surface delta measurement below — the suite cannot assert it, because the comparison authority is the committed production snapshot rather than the local catalog |
| A17 | **Executed structurally**: A15/A15b/A15c/A16b assert nothing existing moved, and the delta is additive-only with zero modified rows. Behavioural non-regression on production is not claimable locally and is not claimed |
| A18 | **Not a test.** It is the honesty rule that the snapshot's *contents* sit outside B-23 structural fidelity, discharged by `README-u3-deployment.md` §3 and asserted separately at P6–P8 |
| **A19** | **EXECUTED 2026-08-17 — PASS.** Suite assertions A19, A19b |
| **A20** | **EXECUTED 2026-08-17 — PASS.** Suite A20–A20d, genuine concurrency |
| **A21** | **EXECUTED 2026-08-17 — PASS.** Suite A21–A21f, structural and runtime |
| **A22** | **EXECUTED 2026-08-17 — PASS.** Suite A22–A22c over real HTTP, with two credential controls |
| A23–A26 | **Executed**, in the suite |
| **A27** | **EXECUTED 2026-08-17 — PASS.** Suite A27–A27e |
| A28 | **Executed** (A28–A28d) |
| A29, A30, A31 | **U5 — not run, deliberately.** The writers do not exist; a U3 pass would be manufactured |
| A24 behavioural half | **U7.** Ordinary expiry *retaining* both tables is an assertion about a worker that does not exist |
| A32–A40 | **Executed** — added with the cutover correction |

**The five were runnable at U3 all along, and the reason they looked unrunnable
is worth keeping.** `ensure_membership_binding()` is ungranted until U5, and
that was taken to mean its behaviour could not be exercised. But the grant
governs who may **call it through PostgREST**; the function derives its identity
from `auth.uid()`, so setting the same JWT claim PostgREST would set exercises
the real code path with nothing granted and nothing weakened. A22 then tests the
ungranted state itself from outside, over HTTP — which is the half no catalog
query can prove. **Nothing was granted, relaxed or stubbed to make these pass.**

**A24's wording was corrected before running.** The earlier draft described
deleting a membership row as "simulated ordinary expiry". **That is now wrong by
specification**: ordinary expiry explicitly *retains* both `membership` and
`membership_binding`. What U3 can prove is the *structural* independence — that
no cascade ties the binding to a membership row — and the behavioural assertion
belongs to U7's worker.

### U3 — RESULTS. 93 of 93 U3-owned assertions pass, 2026-08-17.

**THE DENOMINATOR MOVED, AND IT IS NOT A RE-SCORING OF THE SAME RUN.** The
2026-08-16 run scored **63 of 63** and that result stands as recorded below. On
2026-08-17 an independent review of the deployment package found three defects —
an environment-dependent privilege model (F1), five predictions with no
disposition (F3), and stale bookkeeping (F4). Fixing the first changed the
migration, and fixing the second added assertions, so **the suite was re-run in
full from a destroyed environment and now scores 93 of 93**. The old denominator
is superseded, not preserved: 63 was the honest count of the assertions that
existed, and it is no longer the count of the assertions that should.

**30 assertions added:** A3c–A3h (privilege determinism, 6), A19–A19b (2),
A20–A20d (4), A21–A21f (6), A22ctl1/ctl2 and A22–A22c (5), A27–A27g (7).

**Local implementation only. Production was not touched.** Run from a genuinely
destroyed environment (`stop --no-backup` → `start` → `db reset --local`), so
both migrations applied from scratch.

**A defect was found by the predictions and fixed before the run counted — which
is the whole reason for writing them first.**

#### The `connected_member()` NULL-propagation defect

**A9a failed on the first run**, and it was not a test bug. A membership row in
billing retry with a NULL `grace_period_expires_date` evaluates
`true AND NULL` → **NULL**, then `false OR NULL` → **NULL**, so `bool_or`
returned NULL *over a row that exists*. The top-level `coalesce` cannot
distinguish that from "no rows at all", so the query **fell through to the
grandfather clause and returned TRUE** for an identity whose real membership
state said otherwise — **a direct violation of invariant 8, real membership
state always wins over grandfathering.**

**Fix:** `coalesce()` each term so the row-level expression is strictly
two-valued. `bool_or` is then NULL if and only if there are no rows, which is
exactly the distinction the clause ordering depends on. **This is a correctness
fix that makes the implementation match the frozen architecture, not a change to
it** — the frozen DDL contained a three-valued-logic bug that violated its own
stated intent.

**Two assertions were added after the fix**, because the original set did not
cover the purest shape: **A9d** (every derivation input NULL on a row that
exists → must be false) and **A9e** (`membership_state` = `expired`, never
`grandfathered`, for that row).

The second failure, **A4c**, *was* a test bug: `pg_class` matched the ten
indexes on the new tables alongside the five tables, and an index has
`relrowsecurity = false` by nature. Fixed with `relkind = 'r'`; RLS was enabled
on all five tables throughout.

#### Results

| Group | Assertions | Result |
|---|---|---|
| Structure | A1, A1b | 5 tables, 3 helpers |
| Client reachability | A3, A3b, A4, A4b, A4c | **Zero** table grants, column grants and EXECUTE for `anon`/`authenticated`; **zero PUBLIC EXECUTE**; RLS on all five |
| Derivation | A5–A11b, A28–A28d | Unknown/NULL fail closed; grandfathered true; **expired row beats grandfather**; entitled true; grace only with an unexpired expiry; switch works both ways |
| Constraints | A12, A23, A25–A25c, Axc | Duplicate `(environment, txn)` refused; duplicate `binding_token` refused; **membership without `binding_method` or `bound_at` refused**; invalid method refused; **`environment = 'Xcode'` refused** |
| Notification | An1–An3 | Rejected row with **no** UUID accepted; accepted row missing UUID/env/date refused; duplicate UUID refused |
| Binding lifecycle | A24, A24b, A26, A26b | Binding survives a membership delete; **no FK membership→binding**; binding exists with zero membership rows |
| Cascade | A13 | Deleting `auth.users` removes membership, binding and cutover rows |
| Inertness | A14–A16b | Zero policies call `connected_member`; 33 existing policies unchanged; no pre-existing function references membership; nothing scheduled; 5 triggers; local snapshot empty |
| **Privilege determinism** | **A3c–A3h** | **Zero table and column grants for `service_role`; zero PUBLIC table privileges; NO non-owner grantee in `relacl` on any of the five tables; `membership_state` EXECUTE for `service_role` present; `connected_member` and `ensure_membership_binding` EXECUTE absent for all three roles** |
| **Binding runtime** | **A19–A21f** | **Repeated call returns the same token with one row; 8 genuinely concurrent sessions all return ONE token and produce ONE row; zero-argument signature with no overload; a second identity gets its own token and never the first's; unauthenticated call refused with 28000 and no row** |
| **Runtime client denial** | **A22ctl1/ctl2, A22–A22c** | **Both credentials first shown to work (controls), then 16 real HTTP probes — 5 tables × 2 roles and 3 RPCs × 2 roles — return ZERO 2xx and ZERO JSON row arrays** |
| **Lazy binding** | **A27–A27g** | **A snapshot identity starts unbound, acquires a binding on demand, and NO membership row is fabricated; `membership_state` reads `grandfathered` for the snapshot identity and `unknown` for a bound non-snapshot one** |

**A29–A31 were not run and are recorded as future U5 gates**, as predicted — the
writers they test do not exist, and a U3 pass would have been manufactured.
**A24's behavioural half belongs to U7** for the same reason.

#### Cutover corrections, applied 2026-08-16 after the package review

The review found that **SERIALIZABLE does not close the concurrent-identity
race** (one rw-edge, no dangerous structure, so no abort — and SSI is right,
because the schedule *is* serializable and the violation is of a business
predicate over application data), and that **the in-transaction assertion could
not detect it** (same snapshot as the INSERT, so it agreed by construction).
A third finding was independent: **`auth.users.created_at` is nullable**, and a
NULL satisfies neither side of the boundary, so such an identity would be
invisible to every check.

Corrections: READ COMMITTED; the in-transaction assertion re-labelled as
coherence and re-run protection; **mandatory post-commit convergence, bounded to
a single repair then stop**; a hard NULL gate; a permanent snapshot-membership
invariant; and `cutover_verified_at` added so completeness is durably
distinguishable from unverified.

**Implementing that exposed a further schema conflict, caught by the suite:**
`membership_control_count_with_cutover` tied `cutover_identity_count` to
`cutover_at`, but the corrected procedure cannot know the final count until
after commit — and CHECK constraints evaluate per statement, so the correct
procedure was literally unexecutable. The constraint is now
`membership_control_count_with_verification`, tying the count to
`cutover_verified_at`, which is what it always meant.

**Nine assertions added: A32–A40.** They cover the new column and its coherence
in both directions, the boundary's totality (a pre-boundary identity captured, a
post-boundary identity excluded and not entitled), idempotent re-running that
still cannot admit a post-cutover identity, the convergence completeness check,
the permanent invariant, the NULL hazard demonstrated in both directions, and
finalisation with its re-run guard. **63 of 63 passed from a destroyed
environment on 2026-08-16** — superseded by the 93 of 93 run below, which
includes all of these.

#### Privilege determinism — the 2026-08-17 correction (review finding F1)

**U3's final privilege state used to depend on which `pg_default_acl` entry
applied to the role that created the tables, and that is not a property a
deployment package may leave to the environment.** The local stack's `postgres`
entry grants `anon`, `authenticated` and `service_role` `Dxtm` on a new public
table; the stock `supabase_admin` entry grants all three `arwdDxtm`. The
migration revoked from `anon` and `authenticated` only, so `service_role` kept
whatever the ambient default supplied — `REFERENCES/TRIGGER/TRUNCATE` here,
full DML elsewhere. **Two consequences, and the second is the dangerous one:**

- the predicted delta of `+15` `table_grants` and `+47` `column_grants` was a
  measurement of the *local* default rather than a prediction about production,
  so P3 could have failed on a deployment that was in fact secure; and
- the migration's own header asserted the `arwdDxtm` shape as production fact
  while §2 predicted numbers derived from the other shape — **two statements
  that cannot both describe one environment**, and neither was evidenced.

**The correction is not to discover which default applies.** It is to stop
depending on it: all five tables are now revoked from `public, anon,
authenticated, service_role`, and all three helpers have EXECUTE revoked from
the same four before `membership_state` is granted back to `service_role`. That
one grant is the entire privilege surface U3 creates. **`current_user` and
`pg_default_acl` are now read at P0 as evidence only, explicitly not as inputs
to the desired state.**

**U3 needs no direct table access** — every read is through a `SECURITY DEFINER`
helper owned by the table owner — so zero is the honest posture rather than a
restriction. **U4 must therefore introduce its own server mutation surface by
explicit grant**, and will find `permission denied for table membership` if it
assumes it inherited one. That is the intended failure: deliberate, at the
point of writing, rather than an accidental privilege discovered later.

#### B-23 gate state after local U3 — expected RED

**90 differences, and every single one is "present locally, absent in
production".** Zero rows absent locally, zero modified; the only non-additive
difference in the whole comparison remains the one approved `account_id_format`
catalog-serialization exception. **Every one of the 90 names a U3 object** — the
four that do not contain the string `membership` are `connected_member` and its
three `function_grants` rows. `table_grants`, `column_grants`, `policies`,
`triggers` and `storage_buckets` are all **IDENTICAL**.

**It was 152 before the privilege correction.** The 62 that went were the
`service_role` table and column grant rows that the ambient default had been
supplying. **That shape is the evidence that U3 is purely additive** — it changes
nothing that exists. The gate returns to green only after the separately
authorised production deployment and recapture.

### U3 — PRODUCTION EXECUTION AND ACCEPTANCE, 2026-08-17. P0–P11 all pass.

**This is the production record. Everything above it is local.** Executed
exactly as `supabase/sql/README-u3-deployment.md` defines, one authorised
checkpoint group at a time, with a report and a stop between each.

#### P0 — pre-flight, read-only

| Assertion | Required | Observed |
|---|---|---|
| `existing_membership_tables` | 0 | **0** — and zero collisions of any kind: relations in any schema, helper names, types, constraint names, index names |
| `null_created_at` — hard gate | 0 | **0** |
| `auth.users` | read fresh | **16** |
| `cutover_at` / `cutover_verified_at` | unset | both tables **absent**, so no state could exist |
| Ownership (P2 query, run early) | zero rows | **zero rows** |
| Baseline ownership | evidence | all 7 tables and 11 functions owned by `postgres` |
| `current_user` / `session_user` | evidence | **`postgres` / `postgres`**, PostgreSQL 17.6 |
| Edge Functions | unchanged | v7 / v1, ACTIVE, `verify_jwt=false` |
| Structural drift | none | `capture-schema.sh` diff **empty** |

**P0 CONFIRMED THAT F1 WAS A REAL DEFECT, NOT A HYPOTHETICAL ONE, AND THIS IS
THE MOST IMPORTANT THING THE PRE-FLIGHT PRODUCED.** Production's governing
`pg_default_acl` for role `postgres` — the role that applies the DDL — grants
`arwdDxtm` on new tables **and** `X` on new functions to `anon`,
`authenticated` **and** `service_role`. Under the pre-review migration,
`service_role` would have silently acquired full DML on all five membership
tables and EXECUTE on two helpers, and the predicted delta would have been wrong
by +35/+188 instead of +15/+47, failing P3 on a deployment that was in fact
secure. The review's determinism fix was load-bearing on this exact database.

#### P1 — structural DDL

Committed migration applied byte-for-byte (`sha256 4cd2e820…`, verified
identical to HEAD before sending) via `supabase db query --linked --file`.
**Exit 0.** 37 statements. No `CASCADE` — the only occurrences in the file are
`on delete cascade` inside the three FK definitions. No existing object touched,
no Edge Function deployed.

#### P2 — security verification

**Every condition zero or exactly as designed:** client table grants 0, client
column grants 0, `service_role` table grants **0**, `service_role` column grants
**0**, PUBLIC table privileges 0, non-owner grantees in `relacl` **0**, tables
without RLS 0, policies on the new tables 0. EXECUTE matrix exactly as accepted —
`membership_state`/`service_role` `can=true direct=true`, every other one of the
nine `false`, `public_execute` false on all nine. **All eight new objects owned by
`postgres`**, one distinct owner.

#### P3 — structural delta

| Surface | Pre-U3 | Post-U3 | Δ | Predicted |
|---|---|---|---|---|
| functions | 11 | 14 | +3 | +3 |
| policies | 33 | 33 | +0 | +0 |
| rls_enabled | 7 | 12 | +5 | +5 |
| triggers | 5 | 5 | +0 | +0 |
| constraints | 24 | 50 | +26 | +26 |
| columns | 60 | 107 | +47 | +47 |
| function_grants | 33 | 42 | +9 | +9 |
| table_grants | 102 | 102 | +0 | +0 |
| column_grants | 523 | 523 | +0 | +0 |
| storage_buckets | 2 | 2 | +0 | +0 |

**90 additive, 0 missing, 0 modified**, every one naming a U3 object; file-level
diff **635 insertions, 0 deletions**. All 800 pre-existing production rows are
present and byte-identical. **Against production's own pre-U3 baseline there are
zero modified rows** — the `account_id_format` exception is a *local-vs-production*
serialization artifact and correctly does not appear here.

#### P4–P8 — the cutover

**One mechanism adaptation, recorded rather than glossed.** The Management API
scopes a session to a single request, so the committed file's "STOP and ROLLBACK
unless …" could not be a human check between the assertion `select` and the
`commit`. The GO conditions were enforced as `raise` statements **inside the same
transaction**, so a failure would have rolled back boundary and population
together. The mutating statements are byte-identical to the committed PHASE 1 and
PHASE 3 — boundary read from the `cutover_at` **column**, predicate-limited
population, `on conflict do nothing`, and PHASE 3's re-run guard intact. Strictly
stronger than the manual gate; identical committed state.

| Step | Result |
|---|---|
| **P4** preconditions | 16 users, `null_created_at` 0, 16 qualifying, cutover/membership/binding all empty, all three control fields NULL |
| **P4** transaction | READ COMMITTED. `boundary_declared` true, `count_still_unset` true, `captured` **16** > 0 |
| **P5** commit | **`cutover_at` = 2026-08-17 19:08:27.125223+00**, captured **16**, count and verified_at still NULL |
| **P6** convergence, fresh snapshot | `missing` **0**, `null_created_at` **0**, `invalid_members` **0** |
| **P7** repair | **NOT REQUIRED and NOT RUN.** PHASE 2b never executed |
| **P8** finalise | materialised **16** = by_predicate **16** = recorded **16**; **`cutover_verified_at` = 2026-08-17 19:09:48.080684+00**; `cutover_at` pinned as a literal and unchanged; permanent invariant 0/0; `membership` and `membership_binding` empty |

**The permitted repair is spent by completion, not held in reserve.** It belonged
to the P6/P7 convergence procedure, which passed on its first fresh snapshot.
**A qualifying-but-missing identity discovered later is a new anomaly for
investigation, never authority to re-run the population** — which is what the
cutover file's permanent-invariant section already says: *"Either is a
stop-and-report, never a silent repair."*

#### P9–P11 — acceptance

**P9.** Fresh recapture, not the P3 artifact: **byte-identical to it on all ten
files**, and all ten match the expected post-U3 state. **Zero UUIDs appear
anywhere in `supabase/schema/`** — the 16-row population is outside structural
capture by design.

**P10. B-23 GREEN, exit 0.** Nine surfaces IDENTICAL; `constraints` carries only
the single previously approved `account_directory.account_id_format`
catalog-serialization exception, mechanically verified on both sides. No new
exception, no unexpected difference.

**P11.** Zero policies call `connected_member`; 33 policies and 5 triggers
unchanged and byte-identical (neither file appears in the snapshot diff); no
pre-existing function references membership; `membership`, `membership_binding`
and `membership_notification` all **empty**; **zero `pending_cleanup_at`**;
control state exactly the verified P4–P8 values; all **16** qualifying identities
materialised with `post_cutover_in_snapshot` 0 and `qualifying_but_missing` 0;
the full P2 security posture re-verified unchanged; `ensure_membership_binding()`
not executable by `anon`, `authenticated` **or** `service_role`; Edge Functions
still exactly two, v7 and v1, ACTIVE, `verify_jwt=false`. **No scheduling or HTTP
extension is installed** (`pg_cron`, `pg_net`, `http` all absent) and no function
references Apple or HTTP, so no Apple request, notification endpoint or cleanup
action exists to be triggered.

#### Two claims, two proofs — do not merge them

**B-23's green gate proves the SCHEMA reproduces. It proves NOTHING about the
16-row cutover population**, and citing it that way would be exactly the
conflation the package was written to prevent. The gate reads system catalogs
only and never touches a user table — which is what keeps production UIDs out of
the repository. **The population was verified separately and by different
evidence:** P4's in-transaction coherence assertions, P6's post-commit
convergence on a fresh snapshot, P8's three-way count agreement, and P11's
re-verification of the permanent invariant.

### U4a — GATE RESULT, 2026-08-19. Route resolved. Two design defects found.

**U4a is the empirical gate B-28 required, and it ran before any U4 implementation
existed.** Its question was narrow: *can the Supabase Edge Runtime verify an
App Store Server Notifications V2 payload — ES256 JWS carrying an x5c
certificate chain — against a pinned Apple Root CA G3?* **Nothing was deployed,
no production object was read or written, no secret was installed and App Store
Connect was not touched.**

**Where it ran, because that is the whole point of the gate.** Inside
`public.ecr.aws/supabase/edge-runtime:v1.74.3` (reporting
`supabase-edge-runtime-1.74.3 (compatible with Deno v2.1.4)`, V8 11.6.189.12) —
**not** a host `deno`, which does not exist on this machine. Every result was
obtained twice: once with the probe as the **main service**, and once inside a
**user worker** spawned via `EdgeRuntime.userWorkers.create`, which is the shape
`supabase functions serve` uses. **The two agreed exactly**, so nothing here
rests on a privilege the shipping context would not have.

**The fixture was built to Apple's real shape rather than to a convenient one**,
and that mattered twice. Apple's actual chain is **P-384 root and P-384
intermediate, both `ecdsa-with-SHA384`**, carrying a **P-256 leaf** whose own
certificate is SHA-384-signed while the JWS over it is ES256/SHA-256 — read
directly off the genuine `AppleRootCA-G3.cer` (583 bytes, sha256
`63343abf…9179`) and `AppleWWDRCAG6.cer` (794 bytes, sha256 `bdd4ed6e…ca30`),
both fetched from Apple's public certificate authority page. **An all-P-256 test
chain would have proved nothing about the link that actually carries Apple's
trust.** The synthetic chain mirrors that shape and, on a second pass, also
carries Apple's marker OIDs — `1.2.840.113635.100.6.2.1` on the intermediate and
`1.2.840.113635.100.6.11.1` on the leaf. **Adding them changed a result and is
why the first Route C reading was not reportable:** without them the official
library rejected the good fixture *correctly*, which is indistinguishable from
rejecting it *wrongly* unless the OIDs are present.

| Route | Verdict |
|---|---|
| `node:crypto` `X509Certificate` | **DEAD.** The class exists and a capability probe reports `hasX509: true`, but **`X509Certificate.prototype.verify` and `.toString` both throw `ERR_NOT_IMPLEMENTED`**. Capability presence is not capability |
| `@apple/app-store-server-library@1.6.0` | **IMPORTS CLEANLY, REJECTS EVERYTHING — including the payload it should accept.** `VerificationException`, `status = 1 (VERIFICATION_FAILURE)`, `cause: Error [ERR_NOT_IMPLEMENTED]: Not implemented: crypto.X509Certificate.prototype.toString` |
| `@peculiar/x509@1.12.3` + Web Crypto | **PROVEN. Adopted.** Full battery below |
| Web Crypto alone | Floor confirmed — P-256/SHA-256 and P-384/SHA-384 sign+verify both `true`. Cannot parse X.509 or walk a chain, so it is a component and not a route |

**The Apple library's failure mode is worse than its failure, and this is the
finding rather than the benchmark.** It returns **the same status for its own
runtime incapacity as for a genuine forgery.** Deployed on this runtime it would
have rejected 100% of real Apple traffic while filling the audit table with rows
that read exactly like an attack — and the ingestion endpoint would have looked
like it was working, because rejecting hostile input is what it is supposed to
do. It fails **closed**, so nothing could have been forged past it; every
legitimate notification would simply have been lost. **A green endpoint and a
dead verifier are the same observation from outside.** The same trap as C-38's
"stayed Solo", where the healthy and broken paths produced one indistinguishable
symptom.

#### Route B — the full battery, identical in main worker and user worker

| Assertion | Result |
|---|---|
| Good payload verifies, outer JWS | **PASS** — `SUBSCRIBED`, uuid `3f1c0e2a…0e77`, `environment: Sandbox` |
| Both **nested** JWS verified independently | **PASS** — `signedTransactionInfo` and `signedRenewalInfo` each verified in their own right, not trusted because the envelope was |
| Tampered payload | rejected — `JWS signature invalid` |
| `alg: none` | rejected — `alg is not ES256: none` |
| `x5c` absent | rejected — `x5c missing or too short` |
| Chain of length 1 | rejected — `x5c missing or too short` |
| Chain reordered | rejected — `leaf lacks Apple OID` |
| Root substituted in `x5c[2]` | rejected — `JWS signature invalid`. **Weaker than its name suggests, and worth knowing why: `x5c` lives in the protected header, so substituting the root changes the signing input and invalidates the signature before any pinning logic runs.** The pinning check below is the one that carries the property |
| **Pinning** — good payload verified against the real Apple anchor | rejected — `intermediate not signed by pinned anchor`. **This is the assertion that proves `x5c[2]` is ignored and our embedded anchor decides** |
| Tampered **nested** `signedTransactionInfo` under a correctly re-signed envelope | rejected — `JWS signature invalid` |
| Expired leaf (verified at a date past `notAfter`) | rejected — `cert not valid at 2028-01-01T…` |

#### The real Apple link, proven rather than simulated

| | |
|---|---|
| `Apple Worldwide Developer Relations Certification Authority G6` verified against `Apple Root CA - G3` | **`true`** — both P-384, `ecdsa-with-SHA384` |
| The same G6 certificate verified against an unrelated root | **`false`** |
| Apple Root CA G3 self-signature | `true`; `notAfter` 2039-04-30 |
| G6 carries `1.2.840.113635.100.6.2.1` | `true` |
| Module import cost | **43 ms** |
| Mean full verification, 20 iterations | **4.51 ms** |

**What this gate did NOT prove, stated rather than glossed. No genuine
Apple-signed ASSN payload was verified, because none can be legitimately
obtained without a deployed endpoint.** The **root→intermediate** link is proven
against Apple's own certificates; the **intermediate→leaf** link and the JWS
signature itself are proven only against a faithful synthetic chain. **The first
genuine Apple-signed payload this project can obtain is Apple's own test
notification at U4i**, and that is where the remaining half of B-28 discharges.
A synthetic chain proves the algorithm; it never proves Apple's chain.

**One filesystem fact that decides an implementation detail.** A user worker
cannot read files mounted beside its source — its code is relocated to
`/var/tmp/sb-compile-edge-runtime/` and `Deno.readTextFile` on the original path
fails with `NotFound`. **The pinned Apple root must therefore be an embedded
constant in source, never a file read at runtime**, which is what the design
wanted anyway and is now a requirement rather than a preference.

### U4a — transaction-boundary proof, 2026-08-19

**Run because the proposed U4 write surface assumed something nobody had
checked.** Three observations against the B-23 instance through PostgREST as
`service_role`:

| # | Observation | Result |
|---|---|---|
| T1 | Two successive `rpc/u4a_txid` calls, each returning `pg_current_xact_id()` | **20888** and **20889** — **two transactions.** Two `.rpc()` calls can never be atomic |
| T2 | One RPC that inserts, then raises | **No row.** One RPC is one transaction and rolls back cleanly |
| T3 | Two RPCs: the first inserts, the second raises | **The first row is committed.** No cross-call atomicity |

**Residue: none, and it was verified rather than assumed.** The four probe
functions and one probe table were created in `public`, dropped, confirmed
absent from `pg_proc` and `pg_class`, and **`verify-baseline.sh` re-run GREEN**
with only the standing `account_id_format` exception. `git status` clean
throughout.

**Consequence — recorded on B-30.** One entry point per path, one transaction per
entry point, with the canonical writer internal and granted to no role.

### G2 AMENDMENT — AGREED 2026-08-20, and implemented in U4d

**G2 currently requires that an unsigned payload be "rejected before parsing
**and answered 200**, since it will never become valid and retrying it achieves
nothing". U4a falsified the premise that generated that wording.** The reasoning
assumed the only reason a payload fails verification is that it was never valid.
**B-28 produced the other reason:** a runtime in which the verifier rejects
*everything*, legitimate traffic included, while reporting it identically. Under
`200`, every notification lost to such a defect is lost permanently. Under
`5xx`, production retries five times across 72 hours and a fix inside that window
recovers them; **sandbox never retries either way, so the choice costs nothing
there.** Proposed: structural rejects `400` with no write, signature failures
`5xx` with a bounded aggregate counter, and `200` for anything durably recorded.

**ACCEPTED 2026-08-20 and now live in `appstore_notifications_v1`.** The G2 row
above carries the amended wording, and `e2e.sh` asserts all three codes against
the real function: E2–E5 return 400 with **zero** rows and **zero** counters
written, E8/E9 return 503 with the bounded counter incremented exactly twice in
a single row, and E14/E21/E23/E25/E27/E31 return 200 for every verified payload
including the ones refused downstream.


### U4 — PREDICTIONS AND RESULTS, 2026-08-20. 207 of 207 local assertions pass.

**U4b–U4g are complete and green. U4h and U4i have NOT been run: nothing is
deployed, no production secret is installed, App Store Connect is untouched and
production has been neither queried nor mutated.** The production package is
`supabase/sql/README-u4-deployment.md`.

**Everything below is "verified against a faithful local reproduction", never
"verified in production"** — and the verified-notification path is verified
against a faithful **copy** of the function whose trust anchor is a test CA. See
the honest limits at the end.

| Suite | Assertions | Result |
|---|---|---|
| `supabase/tests/u4a/run.sh` — route gate, real edge runtime | 25 | **25 pass** |
| `supabase/tests/u4/modules.ts` — verifier, derivation, Apple API failure modes | 48 | **48 pass** |
| `supabase/tests/u4/acceptance.sh` — SQL | 94 | **94 pass** |
| `supabase/tests/u4/e2e.sh` — real function, real database | 40 | **40 pass** |
| `supabase/tests/u3/acceptance.sh` — U3 regression under U4 | 93 | **93 pass** |

#### What the four load-bearing findings look like when exercised

| Finding | Assertion | Result |
|---|---|---|
| **B-25 Limb A** | `renewalDate` absent, `expiresDate` present → **still writable** | U4b-8/9 pass. Writing NULL instead would have derived "expired" and scheduled cleanup on a live subscription |
| **B-25 Limb B** | No `renewalInfo.signedDate` → **no write, no schedule, reconcile instead** | U4b-10/12, A51–A51e, E27–E30. **`pending_cleanup_at` stays null** — ambiguous state schedules nothing |
| **B-26** | Replay → `delivery_count` 1→2, first outcome preserved, `membership` unchanged | A48–A48e, E18–E20 |
| **B-27** | An unmapped notification is `ignored`/`unmapped`, **not** `rejected` | A50/A50b, E21/E22. Apple's own TEST notification is `ignored`/`not_applicable` (E23/E24) |
| **B-29** | Tier 1 writes **nothing**; Tier 2 writes one bounded counter row | E6/E7 zero rows and zero counters; E12/E13 two increments in **one** row; A56–A56g twelve rejects → one row, sample capped at 8 |
| **B-30** | One entry point, one transaction; the canonical writer is unreachable | A45b, A46e — `service_role` cannot call `membership_apply_state_v1` at all |
| **B-24** | No path maps `original_transaction_id` → `user_id`; the writer refuses without a live binding | A50e (structural, over `pg_get_functiondef`), A55 |

#### The ownership correction, agreed and applied 2026-08-20

**An earlier revision let ingestion CREATE the initial `membership` row**, taking
`binding_method = 'purchase'` on the reasoning that `Set App Account Token` has
not shipped, so any token Apple reports must have been attached at purchase.
**The reasoning was sound and the design was still wrong.** `binding_method` and
`bound_at` record *how ownership was proved*, and a value inferred from what has
not been built yet is provenance invented rather than established — a rule that
happens to hold during one unit's window is not a rule the code enforces.

**`membership_apply_state_v1` is now UPDATE-ONLY, and U4 contains no `INSERT INTO
public.membership` at all.** A notification that maps to a live binding and
carries complete Apple state but finds no authoritative row is recorded
`ignored` / **`unestablished`** and flagged `needs_establishment` for U5.

| Assertion | |
|---|---|
| A47 / A47b / A47c | A mapped, complete notification is `ignored`/`unestablished` and creates **no** row |
| A47d | ...and returns `needs_establishment: true` |
| **A47f** | **Structural: zero U4 functions contain an `insert into public.membership`** — over `pg_get_functiondef`, so it cannot drift |
| A47g–A47j | With a **U5 stand-in** row present, the same shape of notification is `applied`, and `binding_method` is untouched |
| A54 / A54a | Reconciliation likewise refuses, with the same reason |
| E14–E14e | The **real function** over HTTP: 200, `ignored`/`unestablished`, `needs_establishment`, and **zero membership rows** |
| E15–E17b | With the stand-in row, refresh works and `binding_method` is untouched |

**The U5 stand-in is a FIXTURE and is labelled as one in both suites.** U5 does
not exist, so the authoritative row is inserted directly by the harness; nothing
in U4 can produce it.

#### The granted-function audit, 2026-08-20

**Four functions carry `service_role` EXECUTE and the audit found none of them
removable**, but two were tightened. `membership_due_for_reconciliation_v1` now
returns **three** columns instead of five — `renewal_info_signed_date` and
`pending_cleanup_at` were never read by the caller, and staleness ordering
happens inside the function, so a scheduling column was leaving the database on a
path with no use for it (A58, A58b). `membership_record_reject_v1` now validates
its own inputs: a malformed digest is dropped rather than stored and an unknown
category is normalised rather than aborting the request (A56h–A56j).

**`membership_record_reject_v1` could technically fold into the ingest entry
point and deliberately does not.** Folding it would put the function that can
write `membership` and `membership_notification` on the code path an
unauthenticated caller reaches by sending garbage. Kept separate, the Tier-2
path can touch nothing but the bounded aggregate whatever goes wrong upstream.
That separation is a security property, not tidiness.

#### Quarantine arithmetic, from the real writer

`pending_cleanup_at − entitlement_ended_at = interval '60 days'` **exactly**
(A52c), the end instant is taken from Apple's own dates rather than our clock
(A52d), a later still-expired notification does **not** slide it forward (A52f),
and re-entitlement through grace **clears both** (A53c/A53d). Billing retry
*alone* does not entitle (A53f); retry with an unexpired grace period does
(A53b).

#### Two harness defects found by running, not by review

Both are recorded because each produced a failure that looked like a defect in
the implementation.

1. **A frozen fixture epoch.** The generator used a hard-coded `NOW`, which had
   aged a year past the real clock, so every fixture derived as EXPIRED, a
   correct writer scheduled quarantine, and an entitlement assertion failed.
   Fixtures now encode offsets from the real clock.
2. **A silently-uncreated fixture.** `e2e.sh` inserted a `membership_binding`
   and discarded the result. `binding_token` is UNIQUE, an earlier suite in the
   same run already held it, the insert failed silently, the notification was
   correctly reported **unmapped**, and three assertions failed. The suite now
   clears the conflict deliberately and **asserts the fixture exists (E0) before
   anything depends on it** — an empty fixture is not a pass, and it must not be
   a silent skip either.

A third, smaller one: `tampered_nested_tx` reused the good notification's UUID,
so ingestion correctly **deduplicated** it and the assertion scored the previous
row. A negative fixture that is silently deduplicated tests nothing.

#### Two U3 assertions were widened, and both are strictly stronger

Neither was relaxed to make U4 pass. **A1** counted tables matching
`membership%` and expected 5, so a correct U4 adding a sixth failed a U3
assertion about U3's own objects; it now **names** the five. **A15c** asserted
that no function outside U3's three references membership — its real intent
being that no *pre-existing product function* was modified to consult it, the
hazard being something like `search_account_directory` quietly acquiring an
entitlement check. It now excludes the whole Phase 3 namespace and still catches
that hazard. U3 re-runs **93 of 93**, its original count.

#### The honest limits

- **No genuine Apple-signed payload has ever been verified by this code.** The
  **root→intermediate** link is proven against Apple's own certificates; the
  intermediate→leaf link and the JWS signature are proven only against a
  faithful synthetic chain. **B-28 discharges at U4i and nowhere earlier.**
- **The mapped path cannot occur in production during the U4 window.** No Apple
  subscription carries an `appAccountToken` until U5 sets one, so the
  applied/stale/ordering behaviour is exercised locally and nowhere else.
- **Reconciliation has never spoken to Apple.** Its client is exercised against
  an injected `fetch`; the first real call is U4i's test notification.
- **The verified-path E2E runs against a copy** whose trust anchor is a test CA.
  The alternative — an environment variable relaxing the anchor — is a
  production-reachable switch on the one control that makes an unauthenticated
  endpoint safe, and was refused.

### U4i — APPLE TEST NOTIFICATION, 2026-08-20. PASS. B-28 DISCHARGED.

**The first genuine Apple-signed payload this project has ever verified**, and
the last thing B-28 was held open for.

| | |
|---|---|
| Request accepted | 2026-08-20 **17:48:27Z**, `testNotificationToken` returned |
| Apple's own view | `firstSendAttemptResult` = **SUCCESS**, attempt 1, `attemptDate` 1787248109170 |
| Our audit row | `received_at` **17:48:30.644874Z** — three seconds later |
| Shape | **`TEST` / `ignored` / `not_applicable` / `delivery_count = 1`** — matches the committed prediction exactly |
| Environment / size | `Sandbox`, 4777 bytes, uuid + signed_date present, digest well-formed |
| Tier-2 reject aggregate | **EMPTY. Zero signature failures, ever** |
| `membership` | **0 rows** — acceptance-window prediction holds |
| Policies consulting membership | **0** — still observe-only |

**WHERE THE ROW LANDED IS THE PROOF, NOT THAT ONE DID.** It is in
`membership_notification` as a verified notification and **not** in
`membership_notification_reject_stat`. Had the verifier been dead — the exact
failure U4a found in `@apple/app-store-server-library`, which rejects everything
while reporting its own incapacity with the same status as a forgery — this
payload would have landed in the reject aggregate with
`failure_category = 'signature'`, and the endpoint would still have answered
healthily from outside. **A green endpoint and a dead verifier are the same
observation from outside; this is the observation that tells them apart.**

#### P12 failed twice first, and the cause was propagation

Two attempts shortly after the App Store Connect change returned **404,
errorCode 4040007 — `ServerNotificationURLNotFoundError`**. A single later retry
succeeded **with no change to App Store Connect and none to production**.

**The discriminator is why waiting was the right response rather than a guess.**
During the failure, `mode=notification_history` returned **HTTP 200** on the same
host with the same secrets in the same deployed function. That proved the five
secrets, the ES256 JWT, the Issuer ID, the Key ID, the `.p8` encoding, the `bid`
claim and the sandbox base URL were all correct and that Apple resolved the app —
leaving Apple's own record of the URL as the only remaining variable, which is
exactly the thing that propagates. **Without that control the same 404 would have
been indistinguishable from a malformed key or a wrong Issuer ID**, and the
reasonable next move would have been to start changing configuration that was
already correct.

**A failed Apple read wrote nothing**, verified in production after both failed
attempts: all three tables still zero.

### Local verification stopping rule — agreed before running

1. **B-23's fidelity gate green at the time of the run**, or the run is not
   evidence at all — neither pass nor fail.
2. Predictions committed first.
3. B-12's fixture **genuinely exceeds 1000 objects** under one prefix. A run at
   or under 1000 does not count, whatever it shows.
4. **One successful faithful-local run discharges the obligation at that
   explicitly qualified evidence level** — recorded as "verified against a
   faithful local reproduction", **never** "verified in production".
5. **No production fault-injection run is manufactured to strengthen the
   wording.** The three routes declined below Group D stay declined.
6. A failure is a real defect: file, fix, re-run.
7. **Any subsequent change to `delete_account_v1` invalidates every affected
   local verification.**
8. B-4 and B-13 share one induced-failure/retry run and stay **separately
   scored**.

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

### Phase 2 erase-regression gate — RUN 2026-08-15. PASS. Phase 2 is closed.

**Why this exists.** Phase 2 U4 moved `AttachmentPrivacy.json` out of
`Application Support/MOTIVO/` to the Application Support **ROOT**. That is
structurally the same shape as C-48 — a permanent file at the root that no
directory sweep reaches — and C-48 is the precedent for what happens when such a
file is assumed covered. The erase is believed correct by construction
(`AttachmentPrivacy.wipeOnDiskAndCacheForFactoryReset()` follows `fileURL()` to
the new location and also sweeps the legacy path), but "believed correct by
construction" is exactly what C-28 and C-48 each disproved on device.

**This gate is DISTINCT from, and must not be conflated with, the others. All
three ran on 2026-08-15 and all three passed, scored separately. Full results are
below, after the predictions; this table is the summary a reader arriving at the
specification needs first.**

| Gate | Scored | Outcome |
|---|---|---|
| **F1/F2** backup/restore acceptance | Group F | **PASS 2026-08-15** on a genuine encrypted Finder backup → restore. **F3 within Group F is NOT EXERCISED and is NOT a pass** — see the F3 row and C-51 |
| **This erase-regression gate (D15)** | here | **PASS 2026-08-15.** Load-bearing assertion **L1** held: the root-level `AttachmentPrivacy.json` (520 B, 10 entries) was present before and **absent** after. 10 of 10 backend measures matched. Received-cache and `CommentsStore.json` assertions **not re-exercised** (empty preconditions) and **not counted as passes** |
| **C-49** opportunistic onboarding acceptance | carried Phase 1 row | **PASS 2026-08-15**, discharged by *this* run and scored separately. **The restore did not discharge it; the deletion did** |
| **F5** erase-after-restore | Group F, satisfied here | **Satisfied by this run** — D15 executed on the restored device, which is F5's condition. See the F5 row for the evidence relationship |

| # | Steps | Expected |
|---|---|---|
| D15 | On a disposable device holding local media, at least one attachment with a **non-default privacy choice** (so the map is non-empty), Scores, and received Connected material: invoke the destructive operation **the device's own state presents**, then inspect the container. **NAME IT CORRECTLY — the two operations are not interchangeable.** `ProfileView:839` selects by `auth.hasConnectedIdentity`: a device holding a Connected identity presents **Delete Account & All Études Data**, confirmed by typing **DELETE**, and that path additionally revokes the Sign in with Apple credential and runs `delete_account_v1`; a genuinely Solo-only device presents **Erase All Études Data**, confirmed by typing **ERASE**. Both converge on `LocalFactoryReset`, which is why the local assertions below are identical either way — but they are different product operations with different blast radii, and a run that records the wrong one has mis-stated what it tested. **Device A will hold a Connected identity at this point (restored from the encrypted backup), so the expected operation is Delete Account & All Études Data / DELETE, and the backend and revocation assertions apply.** | **All previously established C-28/C-48 expectations still hold, unchanged** — `ReceivedConnectedAttachments/` absent, `Documents/Scores/` gone, local `Documents` media absent, `tmp/` export copies absent, `CommentsStore.json` gone, Core Data store rebuilt. **PLUS THE NEW ASSERTION: `Library/Application Support/AttachmentPrivacy.json` is ABSENT.** Check the **root**, not `MOTIVO/` — a run that only inspects `MOTIVO/` passes vacuously, because after U4 the file is not there whether the wipe worked or not. Confirm `Application Support/MOTIVO/` itself contains no `AttachmentPrivacy.json` either (the legacy sweep). Release log should carry `[C-28] localReset receivedAttachmentsRemoved=… temporaryFilesRemoved=…` and `[C-48] localReset commentsStoreFileExisted=…` as before, preceded by `[C-44] revocation reason=delete-account outcome=…` **on the Connected path only** |

**The container is the verdict, not the screen** — the same trap C-28, C-34 and
D13 each set. `AttachmentPrivacy`'s in-memory cache is cleared regardless, so the
app's own privacy UI looks identical whether the file was removed or not.

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
| F2 | Prove the **existing-install** half — **by the file's presence and openability after restore, NEVER by a reconciliation log line**, which F2b explains will not appear: a media file written *before* Phase 2, which therefore carries the exclusion attribute, must become backup-eligible through reconciliation **and survive a genuine restore** | Present after restore. If it is absent while a post-Phase-2 file is present, reconciliation did not reach item-level flags — the specific failure the design guards against, since a child's own attribute survives its parent being un-flagged and `Documents/Scores/` was flagged at both levels |
| F2b | After restore, check whether the reconciliation pass runs at all | **It does NOT run, and that is the pass.** Its completion key `backupReconciliation_v1_complete` lives in `UserDefaults` — matrix row 4, ordinary iOS backup, never touched by `BackupPolicy` — so it restores as `true` and `runIfNeeded()` returns before any traversal. **Expect NO `[C-4] backupReconciliation` line after restore.** An earlier draft of this prediction said to expect `examined=N cleared=0 alreadyEligible=N`; that was wrong and is corrected here. **A line appearing after restore is itself a finding**: it means the key did not restore, or was never written because the source device's pass ended `failed > 0`. Note the corollary — a source device with `failed > 0` correctly carries no key, so reconciliation retries on the restored device, which is the intended behaviour rather than a fault |
| F3 | After restore, **publish a session** with a non-private attachment. **NOT EXERCISED — 2026-08-15, and it is not reachable through the shipping UI.** The only publish trigger is `AddEditSessionView:2081`, reached via the editor's save — and ~80 lines earlier that same save rewrites `attachment.fileURL` from `existingAttachmentURLMap`, which holds **resolved** URLs. So opening and saving a session **self-heals every stale path in it before the publish runs**, and `loadIncludedAttachments` never sees a stale path. Running it would have produced a green result for an assertion the test never reached. **Deliberately not run rather than run and caveated.** **The remaining obligation is C-51, owned by Phase 4** — the *implementation* exposure is already closed by U2, which routes `resolveLocalFileURL` through the canonical resolver; what is outstanding is **runtime verification** of the one route that can still reach upload selection with stale paths, a publish enqueued in `SessionSyncQueue` that flushes after a container rotation. That needs fault injection, and Phase 4 owns it because Phase 4 rewrites the upload-selection surface itself | All non-private attachments upload. Pre-Phase-2 this silently omitted them: `resolveLocalFileURL` had no filename fallback, so `loadIncludedAttachments` skipped the attachment rather than blocking publish, and the post arrived with its media missing and no error |
| F4 | After restore, **delete a session** that has attachments, then inspect `Documents/` | The media files are gone. Pre-Phase-2 the deletion paths passed the raw stored path, found nothing, and returned silently — orphaning the files forever with nothing in the UI to show for it |
| F5 | After restore, confirm **Erase All** still removes everything. **SATISFIED 2026-08-15 BY THE D15 RUN — not by a separate destructive run, and this is an evidence relationship rather than a rename.** F5's condition is *a factory reset executed on a restored device, where stored absolute paths are stale*. D15 instantiated exactly that: it ran on Device A **after** the F1/F2 restore, on a device whose stored paths were demonstrably two container generations stale — F4 had already exercised that staleness on the same device state — and every **populated** fixture was removed: 8 `Documents` files, `Documents/Scores/`, the 4-entry Scores index, the journal (2 sessions / 4 attachments → 0/0, store rebuilt) and the root `AttachmentPrivacy.json`. **One honest caveat, recorded rather than smoothed over:** the operation invoked was **Delete Account & All Études Data** (Device A held a Connected identity), not the Solo-only **Erase All Études Data**. Both converge on `LocalFactoryReset`, so the local sweep behaviour is identical and the Connected path is a strict superset — which is why the D15 row's own local assertions are stated as identical either way. **Carve-outs are D15's, unchanged:** the received cache, `CommentsStore.json`, the local avatar and the legacy privacy-map location were all absent, are recorded as **not re-exercised**, and are **not counted as passes**. **No separate destructive run is required**, and spending one would cost a fixture to re-observe a sweep already observed under the exact condition F5 specifies | Unchanged. The factory-reset sweeps are directory- and extension-based and never read `Attachment.fileURL`, so they are path-independent by construction — which is the property D15 confirmed against genuinely stale paths |

## Device A acceptance run — PREDICTION, written 2026-08-15 before any device mutation

> **NAVIGATIONAL NOTE, added 2026-08-15 at closure — the section below is
> PRESERVED VERBATIM as committed before the runs, and its "NOT RUN" statuses are
> historically correct as of the moment it was written.** They are the provenance
> that makes these gates prediction-first rather than a reading of the aftermath,
> and rewriting them would destroy exactly that. **All three gates have since run
> and all three passed** — results are recorded further down this file, under
> "F1/F2 RESULT" and "D15 + C-49 RESULT", and summarised in Group D's gate table.
> **F3 remains NOT EXERCISED and is not a pass.**

**Three gates, SEPARATELY SCORED. None is run. A pass on one is not a pass on
another, and this section must never be summarised as a single result.**

| Gate | Claim | Status (at time of writing) |
|---|---|---|
| **F1/F2** | Genuine encrypted Finder backup → restore | NOT RUN |
| **D15** | Destructive-operation regression after U4's privacy-map move | NOT RUN |
| **C-49** | Onboarding immediately after that destructive operation | NOT RUN |

### Why the fixture has to be authored by a pre-Phase-2 build

**F2's claim is about provenance, not presence.** It must show that a file
written by code that *excluded it at write time* was made backup-eligible by the
U5 reconciliation and then survived a genuine restore. A file's presence after
restore proves nothing on its own — a post-Phase-2 file would also be present,
via U3, having never been excluded at all. That is a false pass, and it is the
single most likely way this gate gets mis-scored.

Device A's container was inspected on 2026-08-15 and is **genuinely empty**:
`Documents/` has no files and no `Scores/`, Core Data holds **0 sessions and 0
attachments**, and there is no `AttachmentPrivacy.json`,
`ReceivedConnectedAttachments/` or `CommentsStore.json`. So the fixture must be
authored by a build predating `4d28754`, and `a8eb050` — the Phase 1 closure
commit — is the one used.

**F2's load-bearing claim is the provenance chain above.** The
received-cache/adopted-Score control below is a strong additional discriminator
and is *not* a redefinition of F2.

### The provenance discriminator, checked BEFORE the backup

On first launch of the Phase 2 build over the fixture, U5 emits one line. It
separates an honest fixture from a false one before anything is backed up:

- `cleared=N, alreadyEligible=0` ⟹ every file carried the exclusion attribute
  and had it removed. **Pre-Phase-2 provenance confirmed.**
- `alreadyEligible>0, cleared=0` ⟹ the files were never excluded. **The fixture
  is post-Phase-2 and F2 MUST NOT be run against it.**

**The exact expected counts are deliberately NOT asserted here.** They are
derived from the implementation's counting semantics applied to the observed
pre-upgrade inventory, and committed as a concrete number *before* the Phase 2
build is first launched. Asserting an abstract `N = fixture file count` in
advance would be a prediction about arithmetic rather than about behaviour.

### Pre-upgrade fixture inventory and the DERIVED U5 prediction — committed 2026-08-15 before the Phase 2 build was ever launched on Device A

Fixture authored on Device A running **`a8eb050`** (pre-Phase-2 Release, installed
in place; container preserved). That revision excludes at write time —
`AttachmentStore:162` and `ScoreLibraryStore:299` — so every file below carries
the exclusion attribute by construction. Device A's container was empty
beforehand (0 sessions, 0 attachments, no `Documents/` files), so there is no
pre-existing state of uncertain provenance mixed in.

**Data container UUID at fixture time: `AF087FE9-401F-40FE-992A-BC3709D58EE9`**,
read from the stored `Attachment.fileURL` values. This is the value prediction 9
compares against after the restore.

| Location | File | Bytes | sha256 (16) |
|---|---|---|---|
| `Documents/` | `7519234D-…-C84C.jpg` | 12672323 | `0c89acbf8c9bb7f4` |
| `Documents/` | `A386D79E-…-3965.jpg` | 2822459 | `05a19068a7352d9c` |
| `Documents/` | `AF96A061-…-9A20.mov` | 3194738 | `9af818acfb4e7446` |
| `Documents/` | `Audio test .m4a` | 122530 | `20d2c75f76d983c7` |
| `Documents/Scores/` | `5E7A2948-…-6CFA8.pdf` | 11753193 | `0b21a15612f611d3` |
| `Documents/Scores/` | `9543D0F2-…-6D31.pdf` | 148684 | `b5e1e33f998be61e` |
| `Documents/Scores/` | `E56EF28C-…-E478.pdf` | 12109620 | `46212d38e753f1d2` |

Core Data: **2 sessions, 5 attachments**. Two are worth noting because they
exercise paths the filename audit singled out: the audio is **user-renamed**
(`Audio test .m4a` — an arbitrary stem with a space, not a UUID), and one
attachment is a **score-derived PDF whose stored path points into
`Documents/Scores/`**, which is the only case that reaches the resolver's
Scores-branch disambiguation.

**The adopted-Score control is correctly staged:**
`Documents/Scores/9543D0F2-…pdf` and
`App Support/ReceivedConnectedAttachments/bb3ce29f-…pdf` are **byte-identical**
(sha256 `b5e1e33f998be61e`, 148684 bytes) — the same document in a permanent
location and in a backend-derived cache.

`AttachmentPrivacy.json` exists at the **legacy** location
(`App Support/MOTIVO/`, 416 bytes) with 8 entries — **7 explicitly `false`
(included) and 1 explicitly `true`**. Both directions are represented, so a lost
map after restore is distinguishable from a preserved one: losing it makes
everything read `true`, and the seven `false` entries are the discriminator.

#### Derived expected U5 outcome

Derived from the counting semantics in `BackupReconciliation.reconcile()` applied
to the inventory above: roots are `Documents` and `Documents/Scores`, enumeration
is non-recursive and skips hidden files, non-regular files are skipped (so the
`Scores` directory is not counted), and `motivo_vid_*` is skipped (none present).
That gives 4 + 3 = 7 examined. All 7 were written by `a8eb050` and are therefore
excluded, so none can be `alreadyEligible`.

```
[C-4] backupReconciliation traversalComplete=true recordedComplete=true \
      examined=7 alreadyEligible=0 cleared=7 failed=0
```

**`alreadyEligible=0` with `cleared=7` is the F2 provenance discriminator.** Any
`alreadyEligible>0` means a file was not excluded at write time, the fixture is
not purely pre-Phase-2, and **F2 must not be run against it**.

Also predicted at first launch: `AttachmentPrivacy.json` moves to the Application
Support **root** with its 416 bytes and 8 entries unchanged; `MOTIVO/` remains
excluded; the `Documents/Scores` directory flag is cleared.

#### PRE-BACKUP GATE RESULT — 2026-08-15. PASS on every assertion.

**Observed, 09:04:37, Device A, Release, Phase 2 HEAD `3d08529`:**

```
[C-4] backupReconciliation traversalComplete=true recordedComplete=true \
      examined=7 alreadyEligible=0 cleared=7 failed=0
```

**Identical to the prediction committed in `3d08529` before the build was ever
launched.** `alreadyEligible=0` with `cleared=7` is the F2 provenance
discriminator, and it passes: every file carried the exclusion attribute at write
time and had it removed. The fixture is genuinely pre-Phase-2, and F2 may be run
against it honestly.

| Check | Result |
|---|---|
| U5 counts vs prediction | **Exact, 4/4** |
| F2 provenance discriminator | **PASS** |
| U4 privacy map | Moved to root, 416 bytes, **byte-identical**, legacy copy gone |
| Fixture integrity across upgrade | All 7 files **hash-identical** |
| Adoption control | Byte-identical in both locations (sha256 `b5e1e33f998be61e`) |
| Reconciliation re-run | **Did not** — completion key stayed `true` (idempotent on device) |
| Data container UUID | **`AF087FE9-…` unchanged** by the in-place upgrade |

**Final pre-backup inventory: 9 files in `Documents/`** — the 7 pre-Phase-2
fixture files, plus 2 post-Phase-2 controls written by the Phase 2 build
(`6CE4ED70-…jpg` and `Scores/DFA744DC-…pdf`). Core Data holds 3 sessions and 6
attachments; the privacy map at the root has grown to 10 entries.

**The two controls are the point of the pair.** Both classes should be present
after restore, but for different reasons — the 7 because U5 reconciled them, the
2 because U3 never excluded them. If the 7 were ever absent while the 2 were
present, the failure is isolated to U5 rather than to backup participation.

**The container UUID being unchanged by the upgrade matters for prediction 9:** it
establishes that any change observed after the restore is attributable to the
restore itself rather than to reinstalling.

##### One incidental finding — observability, not behaviour

**U4's migration outcome line is not readable on device.** Zero hits for
`AttachmentPrivacy` across an archive containing 9,499 Etudes process lines, while
the `BackupPolicy`/`BackupReconciliation` lines came through cleanly. The
migration provably ran (file at root, byte-identical, legacy gone), so this is a
diagnostic gap, not a defect. Cause: `AttachmentPrivacy` uses `NSLog`, which logs
at info level and is **not persisted**, so `log collect` never sees it;
`Logger.notice` persists. **Same class as the MembershipTrace and C-44 run 1
lessons** — a diagnostic that does not exist in the only build that can execute
the path. It does **not** block D15: the `[C-28]`/`[C-48]` lines use
`Logger.notice`, and D15's new assertion was always specified as a container
check.

##### Tooling correction

**`log` is a zsh builtin on this machine and silently swallows every query**,
reporting "too many arguments" as if the log tool had rejected it. **Use
`/usr/bin/log`.** This cost a diagnostic round trip and would otherwise read as
"the line was never emitted".

### F1/F2 predictions

| # | Assertion | Prediction |
|---|---|---|
| 1 | Privacy map before backup | At Application Support **root**, absent from `MOTIVO/`, contents intact |
| 2 | **F2 — pre-Phase-2 attachment media after restore** | **Present and openable.** The gate |
| 3 | **F2 — pre-Phase-2 Scores PDFs after restore** | **Present and openable** |
| 4 | **Control: same document, opposite outcomes** — a received attachment opened (inbox copy materialised) *and* adopted to Scores | Scores copy **PRESENT**, inbox copy **ABSENT**. One backup, one restore, opposite results — matrix row 5 (adopted scores are recipient-owned and not reconstructible) against row 10 (received cache is backend-derived) |
| 5 | Scores index, favourites, resume state | Present. These restored before Phase 2 too — the pre-fix control was a *populated* library whose files were missing, never an empty one |
| 6 | Privacy choices after restore | Preserved. Any loss fails **closed** (everything reads private), never a leak |
| 7 | Staging scratch after restore | **Absent** — secondary negative control |
| 8 | **F2b** — reconciliation after restore | **Does not run; no `[C-4]` line.** The completion key is in `UserDefaults`, which restores. A line appearing after restore is itself a finding |
| 9 | Container UUID across the restore | **Measured, not assumed.** If unchanged, F3/F4 are recorded as **NOT EXERCISED** — the stale-path consumers were never put under test. That does not invalidate F1/F2 and is not grounds for manufacturing a second-device run |
| 10 | Connected identity after restore | Restored without re-authenticating (encrypted backup restores the Keychain) |
| 11 | F3 publish / F4 delete after restore | Attachments upload; a deleted session's files leave `Documents/`. **Meaningful only if (9) shows a changed UUID** |

### D15 and C-49

Predictions for these are in Group D, "Phase 2 erase-regression gate". They are
scored separately from F1/F2 and from each other, and **C-49's assertion is the
screen shown the instant the destructive operation completes, before any
relaunch** — relaunching destroys the observation.

---

### F1/F2 RESULT — 2026-08-15. F1 PASS, F2 PASS. F3 NOT EXERCISED.

Scored against the predictions committed in `f48ac50` and `3d08529` **before** any
device mutation. Device A, Release, Phase 2 HEAD.

**Backup:** encrypted local Finder backup, `IsEncrypted = true`, dated
`Sat 15 Aug 19:06:13 GMT 2026`, device `SD beta burner`, verified from
`Manifest.plist` before restoring — including that `com.sdsongs.etudes` was
actually captured, so we could have aborted rather than spend the fixture on a
restore with nothing in it.

| # | Assertion | Result |
|---|---|---|
| 2 | **F2 — pre-Phase-2 attachment media present and openable** | **PASS** — 4/4 byte-identical |
| 3 | **F2 — pre-Phase-2 Scores PDFs present and openable** | **PASS** — 3/3 byte-identical |
| — | post-Phase-2 controls present | **PASS** — both |
| 4 | Adopted Score **present**, inbox cache **absent** | **PASS** — Scores copy `b5e1e33f…` present; `ReceivedConnectedAttachments/` restored **empty** |
| 5 | Scores index, favourite, rename, resume | **PASS** — 4 entries, favourite and rename preserved, confirmed on device |
| 1,6 | Privacy map at root; choices preserved | **PASS** — 520 bytes, 10 entries, **byte-identical**, 9 explicitly *included* |
| 7 | Staging / operational scratch absent | **PASS** — `App Support/MOTIVO/` entirely absent from the restore |
| 8 | **F2b — reconciliation does NOT run after restore** | **PASS** — **zero** `[C-4]` lines; the completion key restored as `true` |
| 9 | Data container UUID | **Measured. See the correction below** |
| 10 | Connected identity without re-authenticating | **PASS** — `[C-45] state=authorized`, no SIWA sheet, display name intact, and the destructive button reads **"Delete Account & All Études Data"**, i.e. `hasConnectedIdentity == true`. The Solo *display* is the inactive entitlement, which is the settled semantics — expiry removes Connected, not the musician |
| — | Rendering / openability | **PASS** — 3 sessions with all attachments, 4 scores in the library |
| 11a | **F4 — delete a session with stale paths** | **PASS** — see below |
| 11b | **F3 — publish after restore** | **NOT EXERCISED** — see the F3 row. **This is not a pass and must never be summarised as one** |

**F4 in detail, because it tests two directions at once.** Session 8's two
attachments both carried paths under `AF087FE9…`, a container **two generations
stale**. On delete: the 12.6 MB image was **removed** — pre-U2 the sink would
have taken the raw path, found nothing, returned silently and orphaned it — while
`Documents/Scores/5E7A2948-…pdf` **survived**, because it is a score-derived
attachment and `isProtectedScoreLibraryURL` refuses to delete library originals.
Files 9 → 8, Core Data 3 → 2 sessions and 6 → 4 attachments, sessions 7 and 9
untouched. Both files disappearing would have been a failure.

#### CORRECTION to the pre-backup gate record

`2d10def` recorded "the data container UUID was unchanged by the in-place
upgrade". **That was wrong, and the fault was the query, not the device:** it used
`select distinct ZFILEURL … limit 1`, which samples one row and can never detect a
second value. Surveyed properly, the **pre-backup** database already held
`AF087FE9…` ×5 and `D1F670BF…` ×1.

**The in-place app upgrade rotated the data container.** The split predates the
backup and is not a restore artifact.

**That finding is worth more than the correction.** Stale stored paths are **not
restore-specific — an ordinary app update rotates the container and stales every
absolute path in Core Data.** U2's resolver is therefore load-bearing on *every
update*, not merely on the rare restore the Phase 2 analysis was built around. It
also means the app had been running on five stale paths before the backup and
rendered and reconciled correctly throughout, which is independent evidence the
resolver works.

#### OBSERVATION — the genuine publish exposure, recorded not chased

The publish path's stale-path branch is reachable in exactly one way: a publish
**enqueued in `SessionSyncQueue`** that flushes *after* the container rotates. The
queue is file-backed and survives launches, so an offline publish that queues,
followed by an ordinary app update, would reach `loadIncludedAttachments` with
stale paths — and pre-U2 would have silently dropped the attachments.

**Backup/restore does not preserve that route**, because the queue lives in the
excluded `App Support/MOTIVO/` and did not restore — decision **P5** behaving
exactly as designed: a restored device does not inherit historical pending-publish
intent.

**FILED AS C-51, OWNED BY PHASE 4 — P3, Confirmed gap, NOT resolved.** It was
first written down here as an unassigned observation; it was given an ID and an
owner the same day, in `60c8c06`, so that no Phase 2 obligation was left
ownerless. Read it in four parts, because collapsing them is how it gets misread:

1. **The implementation exposure is already closed by U2**, which routes
   `BackendShim.resolveLocalFileURL` through the canonical resolver. Pre-U2 the
   consequence was a shared post arriving with its media silently missing.
2. **F3 was not exercised because the shipping editor/save route self-heals
   stale paths before publish** — not because it was skipped for convenience.
3. **What remains is runtime/coverage verification** of the queued-publish /
   container-rotation path described above. It needs fault injection — enqueue a
   publish, force a container rotation, then flush — which is the same class of
   blocker as B-4's and B-13's negative directions.
4. **Phase 4 owns that verification**, because Phase 4's shared-only upload
   architecture rewrites the upload-selection surface itself and already carries
   A2's proxy-based network acceptance, the natural vehicle for observing what
   actually uploads. Deliberately **not** Phase 3, which is `delete_account_v1`
   and storage-pagination work — a different subsystem that merely shares the
   blocker.

**Phase 2 was not expanded to manufacture it, and Phase 4 implementation is not
expanded now.**

#### Method findings for anyone re-running this gate

1. **A development-signed app is not restored by a Finder restore.** After the
   restore the app was **entirely absent** — not even a placeholder — because iOS
   re-downloads apps from the App Store and there is no App Store record for a
   dev-signed build. **Installing the same-signed build reattached the restored
   container intact**, so the fixture survived. Real users are unaffected; this is
   purely a property of the test vehicle.
2. The restore also **disables Developer Mode** and **drops developer-profile
   trust**. Both must be restored (the trust check needs Wi-Fi) before the app
   will launch; `devicectl` reports `RequestDenied … profile has not been
   explicitly trusted`.
3. **`log` is a zsh builtin on this machine** and silently swallows every query
   with "too many arguments", which reads exactly like the log tool rejecting the
   predicate. **Use `/usr/bin/log`.**
4. **`devicectl copy from` strips extended attributes**, so on-device backup-flag
   state cannot be read from a container copy. Use the `[C-4]` log line instead.

---

### D15 + C-49 — PREDICTION, written 2026-08-15 before the destructive operation

**One legitimate destructive operation, TWO separately scored gates.** Device A
holds a Connected identity, so the operation presented is **Delete Account & All
Études Data**, confirmed by typing **DELETE** (`ProfileView:839`). This is *not*
the Solo-only Erase All path, though both converge on `LocalFactoryReset`.
Account A = `cfadb7cb-12d3-47cc-ac79-c574e5341eb1`.

#### Which fixtures are genuinely populated — and which are not

**Scoring rule for this run: an empty precondition is NOT a pass.** Assertions
without a populated fixture are recorded as *not re-exercised*, and the existing
2026-08-14 evidence stands on its own rather than being restated as new.

| Fixture | State | Scored? |
|---|---|---|
| **`App Support/AttachmentPrivacy.json` (ROOT)** | **520 bytes, 10 entries** | **YES — the load-bearing new assertion** |
| `Documents/` permanent media | 4 files | YES |
| `Documents/Scores/` PDFs | 4 files | YES |
| Core Data journal | 2 sessions / 4 attachments | YES |
| Scores index (`UserDefaults`) | 4 entries | YES |
| `MOTIVO/` scratch | present, empty of media | YES (directory-level) |
| Legacy `MOTIVO/AttachmentPrivacy.json` | **absent** (migrated away by U4) | **NOT re-exercised** |
| `ReceivedConnectedAttachments/` | **0 files** | **NOT re-exercised** — the excluded cache correctly did not survive the F1/F2 restore. **The 2026-08-14 C-28 device acceptance remains the evidence that a populated cache is removed. This run does not re-prove it and must not claim to** |
| `CommentsStore.json` | **absent** | **NOT re-exercised** — C-48's 2026-08-14 evidence stands |
| `Profiles/` local avatar | **0 files** | **NOT re-exercised** |

#### D15 — local predictions

| # | Assertion | Predicted |
|---|---|---|
| **L1** | **`App Support/AttachmentPrivacy.json` at the ROOT** | present before → **ABSENT after**. **The whole reason D15 exists.** Check the **root**, not `MOTIVO/` — after U4 the file is not in `MOTIVO/` either way, so inspecting only there passes vacuously |
| L2 | `Documents/` permanent media (4 files) | absent |
| L3 | `Documents/Scores/` (4 PDFs) | directory gone |
| L4 | Core Data | 0 sessions / 0 attachments, store rebuilt |
| L5 | Scores index in `UserDefaults` | gone |
| L6 | `MOTIVO/` scratch | wiped (may be recreated empty at next launch) |

#### D15 — backend predictions (blast radius)

Baseline taken read-only immediately beforehand.

| Measure | Before | Predicted after |
|---|---|---|
| `auth.users` | 16 | **15** |
| `account_directory` total / A | 16 / 1 | **15 / 0** |
| `posts` total / A-owned | 101 / 2 | **99 / 0** |
| `post_comments` total / A-authored | 2 / 0 | **2 / 0** — B's survive (B-19) |
| `post_comment_views` | 9 | 9 |
| `connected_attachments` total / A-recipient | 32 / 1 | **31 / 0** |
| `follows` total / A-involved | 8 / 2 | **6 / 0** |
| storage `attachments` total / A-prefix | 17 / 4 | **13 / 0** |
| storage `avatars` | 3 | **3** (A has none) |

**One case is deliberately an observation, not an assertion.** A's single
received-attachment row points at an object under the **sender's** prefix
(`users/dfaf8d18…/`, Account B). Whether that object is swept when A's last live
recipient reference goes is reference-counting behaviour that **B-8 owns in Phase
4**. Either outcome is defensible under the settled rule; it is recorded, and it
is **not** a D15 pass/fail. D15 fails on the backend only if **B's own posts,
directory row or unrelated follows are damaged**.

#### D15 — log predictions

`[C-44] revocation reason=delete-account outcome=…` — **attempted; failure must
not block deletion**. Then `[C-28] localReset receivedAttachmentsRemoved=0
temporaryFilesRemoved=N` (**0 is correct here and is not a pass for the
received-cache assertion**), and `[C-48] localReset
commentsStoreFileExisted=false`.

#### C-49 — SEPARATELY SCORED

**The assertion is the screen shown the instant the operation completes, with NO
relaunch.** Expected: **first-launch onboarding**, not a stale Profile or Journal.
Relaunching destroys the observation, and **later relaunch behaviour cannot
substitute for it** — the deviation filed as C-49 on 2026-08-14 was precisely that
the app landed on the journal and then cleared on relaunch.

---

### D15 + C-49 RESULT — 2026-08-15. D15 PASS. C-49 PASS. Scored separately.

One legitimate destructive operation on Device A: **Delete Account & All Études
Data**, confirmed with **DELETE**, as predicted for a device holding a Connected
identity. Scored against `8487bc1`, committed beforehand.

#### D15 — local (the regression this gate exists for)

| # | Assertion | Before | After | Result |
|---|---|---|---|---|
| **L1** | **`App Support/AttachmentPrivacy.json` (ROOT)** | **520 bytes, 10 entries** | **ABSENT** | **PASS — the load-bearing assertion** |
| L2 | `Documents/` regular files | 8 | 0 | PASS |
| L3 | `Documents/Scores/` | 4 PDFs | directory gone | PASS |
| L4 | Core Data | 2 sessions / 4 attachments | 0 / 0, store rebuilt | PASS |
| L5 | Scores index (`UserDefaults`) | 4 entries | gone | PASS |
| L6 | `MOTIVO/` scratch | present | wiped, recreated empty | PASS |

**NOT RE-EXERCISED — empty preconditions, and NOT counted as passes.** The log
confirms both: `[C-28] receivedAttachmentsRemoved=0 temporaryFilesRemoved=0` and
`[C-48] commentsStoreFileExisted=false`. **Those zeros are the predicted
consequence of the F1/F2 restore correctly not restoring an excluded cache — they
are not evidence that a populated cache is removed.** The genuine 2026-08-14 C-28
device acceptance remains the evidence for that, on its own terms.

#### D15 — backend blast radius: 10 of 10 measures matched

| Measure | Before | Predicted | Actual |
|---|---|---|---|
| `auth.users` | 16 | 15 | **15** |
| A's `auth.users` row | 1 | 0 | **0** |
| `account_directory` total / A | 16 / 1 | 15 / 0 | **15 / 0** |
| `posts` total / A-owned | 101 / 2 | 99 / 0 | **99 / 0** |
| `post_comments` | 2 | 2 | **2** — B's survive (B-19) |
| `connected_attachments` total / A-recipient | 32 / 1 | 31 / 0 | **31 / 0** |
| `follows` (A involved) | 2 | 0 | **0** |
| storage `attachments` total / A-prefix | 17 / 4 | 13 / 0 | **13 / 0** |
| storage `avatars` | 3 | 3 | **3** |

**Observation, as flagged in advance rather than scored:** the object A referenced
as *recipient* lives under the **sender's** prefix (Account B) and **survived** —
5 objects still under `users/dfaf8d18…/con%`. A's reference row went; B's object
did not. That is the conservative outcome and B's data is untouched. Reference
counting here is **B-8, Phase 4**; it was never a D15 assertion.

#### C-49 — SEPARATELY SCORED: **PASS**

**Immediately on completion, without relaunching, the app was on first-launch
onboarding** — "Set up Études — Add your name and your first instrument to
start", with an empty Display name field. Not the journal, not a stale Profile.
The C-49 fix (`dismissProfileAfterSuccessfulErase` → `onEraseComplete` →
`route = .timer`) is device-verified.

**A transient intermediate frame was captured ~30s earlier and is worth recording
so it is not mistaken for a failure later.** Mid-deletion the screen showed
Profile/Settings with a **Sign in with Apple** sheet over it. The log explains it
exactly: `[C-44] revocation reason=delete-account
outcome=notAttempted(authorization/…AuthorizationError/1001)` — 1001 is
*canceled*. That sheet was **C-44's re-authorization request**, needed to obtain
an authorization code for revocation; it did not complete, revocation was
therefore `notAttempted`, and the deletion **continued regardless**, exactly as
the settled semantics require. The app then routed to onboarding and showed
C-44's TN3194 step-2 fallback: *"Your Études account and data have been deleted.
We couldn't remove Études from your Apple Account automatically…"*.

**This is C-44 behaving as accepted, not a new defect**, and it is not reopened.

**Operational note, and the two halves must not be merged.** *As recorded on the
run:* Device A's Apple credential for Études was **NOT** revoked in-app — the
outcome was and remains `notAttempted(authorization/AuthorizationError/1001)`,
and the app showed C-44's TN3194 step-2 manual fallback. **That historical result
stands and must never be rewritten as an in-app revocation success.** *Since the
run:* the user completed the manual Settings step, so no live Études credential
remains on Device A. **Separately outstanding, and unrelated:** the live Apple
refresh token minted and abandoned by the C-44 gate (b2) exchange on 2026-08-13 —
pre-existing operational test residue, not created by Phase 2.

---

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
