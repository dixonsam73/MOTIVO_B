# Founding 500 — tomorrow's runbook

**Updated 21 September evening: Step 0 passed in Samuel's manual Xcode run.**
Device steps remain pending for tomorrow. No device action, purchase, sign-in,
deployment, commit or push reported tonight.

Ordered. **Stop at the first failure and report** rather than continuing — later steps
assume earlier ones passed, and a device fixture spent on a broken build is a fixture
that has to be re-made.

---

## Step 0 — DONE. All three suites PASS

**Run by Samuel in Xcode on 21 September evening: `ConnectedOfferPresentationTests`,
`ConnectedRenewalPresentationTests` and `ConnectedTrialReminderTests` all passed.**

So the three files **compile** — which was the specific risk, since a non-compiling
test file had already slipped through once here — and every assertion holds. Two
things I had flagged as reasoned-but-unobserved are now measured:

- **`DateComponentsFormatter` with `weekOfMonth` does render as "1 week" / "2 weeks"**,
  rather than dropping the unit. This was the likeliest genuine failure.
- **Localisation is real**: `en_GB` and `fr_FR` produce different duration and date
  text, so the formatting is not hardcoded English.

**What this does NOT establish:** anything about device or Sandbox behaviour. These are
pure functions run in a simulator against pinned locales. Steps 1–5 are unaffected.

<details>
<summary>The command, retained for re-running</summary>

```bash
cd "/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO"
xcodebuild test -project MOTIVO.xcodeproj -scheme MOTIVO \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MOTIVOTests/ConnectedOfferPresentationTests \
  -only-testing:MOTIVOTests/ConnectedRenewalPresentationTests \
  -only-testing:MOTIVOTests/ConnectedTrialReminderTests
```

Samuel ran this himself, in Xcode; the Auto-mode block that stopped me running it was
not bypassed. To re-run:

- **In Xcode:** open the project, select an iPhone simulator, and Product → Test
  (⌘U). The three suites are `ConnectedOfferPresentationTests`,
  `ConnectedRenewalPresentationTests` and `ConnectedTrialReminderTests` under
  `MOTIVOTests`; individual diamonds in the test navigator run them alone.
- **Or paste the command above into his own terminal.**

If the simulator name is wrong for this machine, `xcrun simctl list devices available`
gives the correct one; nothing else in the command changes.

</details>

---

## Step 1 — Build identity

**THE BUILD NUMBER CANNOT IDENTIFY A BUILD.** `MARKETING_VERSION 1.0` and
`CURRENT_PROJECT_VERSION 131` are hard-coded and never incremented, so every install
from this project reports `1.0 (131)` whatever commit it came from. This is a standing
project limitation, not something introduced here.

**So identify the build by what it does, not by what it says:**

| Discriminator | Only true of today's build |
|---|---|
| Paywall shows **"Free for 1 year"** above the price | The offer-aware copy is new |
| Paywall shows renewal **and** cancellation lines | New |
| Continue is **disabled while products load** | New |
| Profile → Account shows **"Free until \<date\>"** | New |

**Build from this working tree in Xcode and Run to the device.** Then confirm at least
the first discriminator before trusting any later observation — if the paywall looks as
it did yesterday, the device is running an older install and everything after is
meaningless.

**Optional, and Samuel's call:** bumping `CURRENT_PROJECT_VERSION` would make this
answerable directly rather than by inference. It is a one-line project change, it is
not required for tomorrow, and I have not made it.

---

## Step 2 — Nothing to check in ASC

**WITHDRAWN.** An earlier revision asked Samuel to confirm the offer's eligibility is
"new subscribers". **There is no such field on an introductory offer.** Apple determines
eligibility, with at most one introductory offer per subscription group; it is not a
selectable audience setting. Selectable new / existing / expired cohorts belong to **offer
codes**, which is where I carried the idea from; that route was not chosen.

§0 of the launch checklist records the configuration, and **nothing in ASC needs
re-checking before QA.**

---

## Step 3 — Device setup

- **Device A**, the beta burner. Release configuration, **StoreKit Configuration
  None** — a pinned configuration silences real StoreKit even in Release.
- Sign in to the **fresh UK Sandbox tester** in Settings → Developer → Sandbox Apple
  Account. It has never been used, which is what makes Q1 a genuine first purchase.
- **Note the journal session and Scores counts before installing.** An Xcode Run over
  the same bundle id preserves the container, and that is the check that it did.

---

## Step 4 — QA, in this order

Run §3 of `founding-500-launch-checklist-2026-09-21.md`. The ordering below matters
because some checks consume the fixture.

| Order | Checks | Note |
|---|---|---|
| 1 | **Q1, Q2, Q14** | Before purchasing — the eligible-paywall state exists only once |
| 2 | **Q7** | Airplane mode, still before purchasing |
| 3 | **Q4** | **The purchase.** Spends the fresh tester |
| 4 | **Q9a, Q9b, Q9f** | **IMMEDIATELY after the purchase — see below.** The feed card, its Manage action, and the "free trial" wording |
| 5 | **Q9c** | Dismiss, relaunch, card stays gone |
| 6 | **Q5, Q6** | Eligibility must now be false |
| 7 | **Q8** | Profile summary |
| 8 | **Q11** | Restore |
| 9 | **Q12** | Plan change. **Record what Apple does; do not assume** |
| 10 | **Q10** | Cancellation wording |

### Q9 IS REACHABLE, AND IT IS URGENT RATHER THAN IMPOSSIBLE

**I had this exactly backwards and it is corrected here.** I wrote that Q9 "needs the
final 30 days" and so could not be reached in a Sandbox trial lasting minutes. The
window is an **upper bound on the time remaining**, not a lower one:

```
periodEnd - now  <=  30 days
```

A trial expiring in **minutes** satisfies that trivially. **So the card appears
immediately on an accelerated Sandbox trial, for as long as the trial is active.**

**Which makes it urgent, not unreachable.** The whole trial may last minutes, so
Q9a–Q9f must be done **straight after the purchase**, before switching plan or
cancelling — both of which change the state the card depends on, and before the trial
simply expires.

**The widened-window build I proposed is withdrawn.** It solved a problem that does
not exist, and would have meant testing something other than the shipping behaviour.
**Do not edit dates on device either** — nothing needs it.

**Q9d** (earlier than 30 days → no card) is the one genuinely unreachable check here,
because an accelerated trial is never more than 30 days from its end. It stays covered
by the unit tests and unverified on device.

**Q9e** (paid period → no card) becomes reachable once the trial converts, which on
Sandbox happens within the session.

**Q3 and Q13 need an ASC change** (removing an offer) and should not be done on the
same pass as the purchase checks.

---

## Step 5 — What to bring back

For each check: pass, fail, or not reached. For **Q12** specifically, the observed
behaviour rather than a verdict — whether the free period survived the switch, when the
new plan started, and what the paywall and Profile then said.

---

## Known limitations, stated before rather than after

- **Sandbox is not production.** Nothing observed tomorrow establishes public App Store
  behaviour, and no result may be scored against it.
- **A Sandbox year is not a year.** Accelerated renewal means the "free year" will
  elapse in minutes. Q9 is reachable while the trial is active; capture the reminder
  promptly. Record the expiry before attempting Q12; a switch after expiry does not
  test preservation of the free period. Use a separate fresh tester if necessary.
- **Billing Grace is Sandbox-only** (§0), so grace behaviour seen tomorrow says nothing
  about production.
- **The products are *Prepare for Submission*** and the app is not launched.
