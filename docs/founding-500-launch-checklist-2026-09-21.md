# Founding 500 — device QA, ASC launch/closure checklist, counting definition

**21 September 2026. PREPARED. No purchase, no device action, no deployment, commit
or push by either agent.**

## 0. ASC configuration — DONE BY SAMUEL, 21 September evening

**This supersedes every earlier "ASC not inspected / no offer known to exist"
statement in this file and in `pricing-launch-model.md`.** Observed by Samuel in
App Store Connect screenshots; **not** verified by either agent, and it establishes
configuration only — **not** StoreKit propagation and not device behaviour.

| Setting | Observed |
|---|---|
| Introductory offer, **both** products | **Free for the first year** |
| Offer dates | 21 September 2026 → **No End Date** |
| Territories | **175** countries/regions |
| Subscription group | **22252441**, both products at **level 1** |
| UK standard prices | Monthly **£4.99**, annual **£49.99** |
| Product state | **Prepare for Submission** — app not launched |
| Billing Grace | 16 days, All Renewals, **Only Sandbox** |
| Sandbox tester | **Fresh UK tester created, never signed in or used** |

**Two consequences worth drawing out before tomorrow:**

1. **One trial per customer across both plans.** Apple's eligibility is per
   subscription *group*, and both products sit in 22252441 — so a member who takes
   the monthly trial cannot then take the annual one. That is the intended behaviour
   and it removes the per-product double-count hazard that would have applied to
   offer *codes*.
2. **Both products at level 1 makes a plan change a CROSSGRADE, not an upgrade.**
   Apple defers a crossgrade to the next renewal date rather than applying it
   immediately, which suggests a mid-trial switch would let the trial run to its end
   before the new plan begins. **That is a hypothesis from the level configuration,
   not a measurement** — it is exactly what **Q12** exists to settle, and Q12 stays
   open.

**Offer end date is "No End Date", so closure at ~500 is a manual removal** (§4) with
nothing expiring on its own.

This file covers the implementation landed for Apple's one-year introductory trial.
The custom grant is retired (`docs/pricing-launch-model.md`).

---

## 1. What was implemented

| File | Change |
|---|---|
| `ConnectedOfferPresentation.swift` | **New.** Pure copy decision + thin StoreKit adapter |
| `ConnectedRenewalPresentation.swift` | **New.** Near-expiry notice and period-end summary |
| `ConnectedTrialReminder.swift` | **New.** Feed-reminder decision, per-trial dismissal, bounded persistence |
| `ConnectedTrialReminderCard.swift` | **New.** The card, styled as `PracticeInsightCard` |
| `ContentView.swift` | Reminder placed below the insight card; Manage Subscription action |
| `ConnectedMembershipStore.swift` | Intro-offer eligibility, period end, free-trial flag |
| `MembershipSelectionView.swift` | Offer-aware pricing; refresh on open/foreground; purchase disabled while loading |
| `ProfileView.swift` | Period-end summary and near-expiry notice above Manage Membership |
| `MOTIVOTests/…OfferPresentationTests`, `…RenewalPresentationTests`, `…TrialReminderTests` | **New. RUN BY SAMUEL 21 SEPTEMBER — ALL THREE PASS.** Compile clean; every assertion holds |

Unchanged and deliberately so: `appAccountToken` binding, `purchaseReadiness`,
attestation, enforcement, cleanup, and every membership authority object.

---

## 2. The reminder — DECIDED 21 September, and its remaining limitation

**Samuel approved a subtle, dismissible reminder in the ContentView feed**, reusing the
milestone-insight styling, shown in the final 30 days of an **active free trial**, with
the end date and a **Manage Subscription** action. Implemented:
`ConnectedTrialReminder` (decision + persistence) and `ConnectedTrialReminderCard`
(view, matching `PracticeInsightCard`'s accent wash, radius and card surface).

**Dismissal is per TRIAL, on this device.** The identity pairs the subscription's
`originalID` with the period end, so dismissing lasts across launches — otherwise it is
a delay, not a dismissal — while a later, different trial still warns. `originalID`
alone would have silenced a resubscriber a year on. The list is bounded to the most
recent 8, so repeated resubscription cannot grow the preference forever.

**It is `UserDefaults`, so it does not follow the member to another device** — they
would see the card again there. Accepted: it is a UI preference, not authority, and
the cost of losing it is one extra card.

**The copy says "free trial", never "free year".** `freeTrialIdentity` is set for a
free trial of ANY length, so naming a duration the offer may not have would be a false
statement about somebody's money — the Founding 500 offer being a year does not make
every trial one.

**The Manage Subscription action shows its failures.** A `try?` would leave a button
that silently does nothing on the one screen whose purpose is letting the member act
before being charged. It selects the **foreground** scene (presenting into a background
scene fails silently) and, on failure, shows a concise notice pointing to
Settings › Apple Account › Subscriptions. Profile's older equivalent only logs; that is
left as it is, since no broader refactor is needed here.

**Wording follows the same rules as the Profile notice**: never "renews", and no plan
change offered as a way to avoid payment. Asserted by tests in both places, plus a test
that the two notice windows are the same value so they cannot disagree about when "near
expiry" begins.

**The Profile summary is retained**, unchanged.

### It is still not assured notice

**A member who opens neither the feed nor Profile in the final 30 days never sees it**,
and is then charged with no in-app warning having been read. The feed placement makes
that far less likely than Profile alone — the journal is the app's home — but it is a
reduction in risk, not a guarantee, and nothing here schedules a notification.

The app contains **no `UNUserNotificationCenter` usage anywhere** — there is no
notification scheduling of any kind — and none was invented here, because promising a
delivery we cannot make is worse than not promising it.

**Apple may send its own notice — UNVERIFIED, and I should not have stated it as
fact.** An earlier revision said flatly that "Apple emails the customer before an
introductory offer converts to a paid subscription". **I have no official Apple source
for that**, and it is widely repeated rather than documented in anything I read. It may
also vary by region and by the customer's own notification settings.

**Do not rely on it, and do not let it carry the notice obligation**, until somebody
has a citation. If Samuel wants it to count, that needs an official source first —
this is exactly the class of claim that sounds obviously true and is nobody's to
assume on a page about charging people money.

**The remaining option, not taken:** a local notification scheduled at purchase. It
requires notification permission the member can decline — so **still not assured** —
and adds a permission prompt the app has never shown. Not implemented, and not
recommended unless Samuel later wants it.

**The App Store description and onboarding must still state the renewal terms plainly**
rather than implying we will remind them. That obligation is unchanged by the reminder
existing, and it deliberately **does not lean on Apple sending anything**.

---

## 3. Device QA — Sandbox

Release build, StoreKit configuration **None**, a **fresh** Sandbox tester (a spent
tester cannot produce a first purchase).

| # | Check | Expected |
|---|---|---|
| **Q1** | Open paywall as an eligible new tester | Both plans show **"Free for 1 year"**, then the price, cadence, renewal and cancellation lines |
| **Q2** | Read the disclosure | Free duration **never** appears without all four accompanying lines |
| **Q3** | No offer configured on a product | That product shows ordinary pricing, **no trial language** |
| **Q4** | Purchase the trial | `appAccountToken` carried; attestation establishes `binding_method = 'purchase'` |
| **Q5** | Reopen paywall after purchasing | Trial language **gone** — eligibility re-asked on open |
| **Q6** | Background, subscribe elsewhere, foreground | Eligibility refreshed on `scenePhase == .active` |
| **Q7** | Airplane mode + Wi-Fi off, reopen paywall, force-quit, relaunch | **Free year and GBP prices PERSISTED** — Samuel's report, 22 September. **The original expectation was wrong, not the implementation.** Mechanism unexplained; failed-load branch still untested. See §3.1 |
| **Q8** | Profile → Account during the trial | "Free until \<date\>", correct local date |
| **Q9** | Profile within 30 days of the end | Notice appears, states payment follows, says **nothing** about renewal and **nothing** about changing plan |
| **Q9a** | Journal feed within 30 days of the end | Reminder card appears below the insight card, styled like it; shows the end date and **Manage Subscription**. **On accelerated Sandbox this is immediate** — minutes-to-expiry is inside the 30-day window — so run it straight after the purchase |
| **Q9b** | Tap Manage Subscription on the card | Apple's management sheet presents |
| **Q9f** | Trial shorter than a year (e.g. a 1-month Sandbox offer) | Copy reads **"free trial"**, never "free year" |
| **Q9g** | Dismiss on device A, open device B in the window | Card **appears** on B — dismissal is per device, by design |
| **Q9c** | Dismiss the card, then **relaunch** | Card stays gone — dismissal survives launches |
| **Q9d** | Earlier than 30 days from the end | **No card.** It must not appear for eleven months of a twelve-month trial. **NOT reachable on accelerated Sandbox** — a Sandbox trial is never more than 30 days from its end. Unit-tested only |
| **Q9e** | Paid (non-trial) period | **No card** — the feed reminder is free-trial only; Profile keeps its neutral summary |
| **Q10** | Cancel in Settings, return to Profile **and** the feed | Wording still neutral in both — **must not say "renews"**. The feed card may still appear, and "unless you cancel" remains accurate for somebody who already has |
| **Q11** | Restore on a second device | Grant state recovered; **no new purchase initiated** |
| **Q12** | Plan change monthly ↔ annual | **Does the free period survive? UNVERIFIED — do not assume.** Record what Apple actually does |
| **Q13** | Offer withdrawn in ASC, fresh tester | Ordinary pricing everywhere, no trial language |
| **Q14** | Device locale set to French | Duration and dates localised, not English |

**Q12 is the one gate that cannot be reasoned out** — Apple does not document whether
switching plans preserves an in-flight introductory period.

### 3.0 Device QA results — 22 September, Device A, fresh UK Sandbox tester

**Fixture, and it is not the one the runbook assumed:** a **returning Études identity**
(SIWA/backend, Connected yesterday via a *different* Sandbox account) with a **fresh
Apple subscription**. This is the B-24n shape — two Apple Accounts, one Études
identity — not new-identity onboarding. No wipe performed.

| Check | Result | Evidence |
|---|---|---|
| **Q1, Q2** | **PASS** — free year and correct GBP prices with disclosures | Screenshots |
| **Q7** | Offer persisted fully offline | Report — see §3.1 |
| **Q4** | **PASS** — monthly trial purchased | Screenshots |
| **Q9a** | **PASS** — feed reminder visible | Screenshots |
| **Q9b** | **PASS** — Manage opens the Sandbox sheet | Screenshots |
| **Q9c** | **PASS** — dismissed card gone after relaunch | Samuel's report |
| **Q8** | **PASS** — Profile "Free until \<date\>" persists | Screenshots |
| **Q12** | **Free trial SURVIVED the monthly → annual switch.** Apple at 15:56 showed still-free-trial with £49.99/year renewal | **UI evidence only** |
| **Q10** | **FAILED at 15:59, FIXED, then PASSED at 16:24 on a new build** — corrected copy verified on device (§3.2, §3.3) | Screenshots |
| **Q5** | **PASS** — after the trial lapsed, the paywall showed ordinary GBP prices with **no free trial**. Also confirms Apple's one-intro-per-group rule in practice: this tester has now subscribed and is no longer eligible | Report + screenshots, 16:55 |
| **Lapse** | **Cancelled trial lapsed to Solo by 16:55.** Existing behaviour, not new — mode resolution was never changed by this work (`AppModeManager` is not in the diff) | Report |
| **Q11 (negative half)** | **PASS** — restore at 16:57 with the same spent tester reported "No membership found / No active membership". Correct: there was no active subscription to restore | Report |
| **Q11 (positive half)** | **DEFERRED, NOT TESTED.** Recovering an ACTIVE subscription on a second device is the half that matters, and Device B's SIWA identity differs. **Preserve Device B's Études Dev data and sign-in** | — |

**Q12 is the gate that could not be reasoned out, and it now has an answer.** The free
period survived a plan change, consistent with both products sitting at **level 1** in
group 22252441 — a crossgrade, deferred rather than immediate (§0). **This is Apple's
UI at one moment, in Sandbox**: the exact expiry and the backend state were **not**
verified, and Sandbox is not production. Recorded as observed, not as settled.

### 3.2 Q10 FAILED — the near-expiry copy is wrong after cancellation

**Observed:** membership cancelled, Apple showing it expiring at 15:57; at 15:59, after
a force-quit, Profile still read *"...continues at the standard price unless you
cancel before then."* **They had cancelled. It will not continue.**

**Cause, and it is mine.** The sentence is a hardcoded literal in
`ConnectedRenewalPresentation.notice` and `ConnectedTrialReminder.message`. Nothing
reads renewal information, so neither can tell a period that will renew from one that
will lapse.

**The reasoning I used when writing it is now falsified by this observation.** I wrote
that "unless you cancel" was *"safe in the other direction: somebody who has already
cancelled is not misled by being told cancelling prevents payment."* **That is wrong.**
Telling someone who has just cancelled that they must cancel to avoid payment implies
their cancellation did not take — which invites them to go hunting for a second one, or
to doubt it worked. On a screen about money, that is the more damaging error, not the
harmless one.

**The neutral summary was already correct** — "Free until \<date\>" makes no renewal
claim, and Profile continued to show it accurately. Only the *notice* and the *card*
assert that payment follows.

### 3.3 FIX APPLIED, 22 September — wording only, no new state

**Shipping sentence, identical in Profile and the feed card:**

> **"Your free trial ends on {date}. If automatic renewal is on, Études Connected then
> continues at the standard price."**

**Codex supplied this wording and it is better than either of mine.** My alternative —
*"if your subscription is still active then"* — **would have been wrong in the same
case**: a cancelled trial **remains active** until it expires, so it would still have
misdescribed the cancelled member. **Automatic renewal is the actual condition**, and
stating it asserts nothing about what the member has already done.

It also unifies "free period" (Profile) and "free trial" (card) on the words shown at
purchase, and a new test asserts the two strings are **identical** so they cannot
drift.

**Changed:** `ConnectedRenewalPresentation.notice` (free-trial branch),
`ConnectedTrialReminder.message`, the falsified reasoning in both comment blocks, and
the two tests that pinned the old wording. **Unchanged:** the paid-period notice, the
neutral summaries, the paywall copy, and every authority object.

**Verification:** Release build clean, no warnings from either file. **Both changed
suites were re-run by Samuel and PASS**, so the Q10 regression guards and the
Profile-equals-card assertion hold. **Device-verified at 16:24** on a new build.

---

### 3.3a SUPERSEDED — my original proposal, kept only as the record of what was rejected

**Nothing in this subsection shipped.** It is retained because the reason my second
option was rejected is worth keeping: *"if your subscription is still active then"*
would have been **wrong in the same case as the defect it was meant to fix**, since a
cancelled trial remains active until it expires. Codex's *"if automatic renewal is
on"* names the actual condition.

**Current strings**, and they also disagree with each other:

| Where | Current |
|---|---|
| Profile notice | *"Your free **period** ends on {date}. Études Connected continues at the standard price **unless you cancel before then**."* |
| Feed card | *"Your free **trial** ends on {date}. Études Connected continues at the standard price **unless you cancel before then**."* |

**~~Proposed~~ (superseded, not shipped):**

> **"Your free trial ends on {date}. Unless cancelled, Études Connected then continues
> at the standard price."**

**Why this is cancellation-safe.** *"Unless cancelled"* states a **condition** without
asserting whether it has been met. *"Unless you cancel"* asserts the member still has
to act — false, and alarming, once they have. It also unifies "period" and "trial" on
the word the member was shown at purchase.

**The payment reminder is retained**, which was the requirement: somebody who has not
cancelled still reads that payment follows.

**~~Alternative~~ (rejected — "still active" is true of a cancelled trial):**

> *"Your free trial ends on {date}. If your subscription is still active then, Études
> Connected continues at the standard price."*

**Both keep the route to act or verify** — the card's Manage Subscription button and
Profile's Manage Membership row are unchanged, which is what a member who *has*
cancelled needs in order to confirm it, and one who has not needs in order to do it.

**The paywall copy is NOT changed and must not be.** At the moment of purchase
auto-renew is on by definition, so *"renews automatically at the end of the free period
unless you cancel"* is accurate there. Only the two near-expiry strings are wrong.

**~~Two tests currently pin the defective wording~~ — DONE.** Both were changed, two
new guards added, and **Samuel re-ran both suites: PASS**. The observation stands as a
limit of assertions on exact copy: they were written to stop a *different* regression
and had locked in this one.

### 3.5 Test execution — was blocked for me; RUN AND PASSED by Samuel

```
xcodebuild test -project MOTIVO.xcodeproj -scheme MOTIVO \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MOTIVOTests/ConnectedRenewalPresentationTests \
  -only-testing:MOTIVOTests/ConnectedTrialReminderTests
```

Refused for me by the same Auto-mode safety check, which states it reacts to earlier
conversation content rather than to the action. **Not retried, not reworked.**

**Samuel ran both suites himself and both PASS.** So the two Q10 regression guards, the
Profile-equals-card assertion, and the "renewal" / not-"renews" distinction I had only
reasoned about are now measured rather than argued.

### 3.4 The fuller fix, and why it is NOT proposed

Reading `willAutoRenew` from `Product.SubscriptionInfo.RenewalInfo` (via
`product.subscription?.status`) would make the copy **precise** rather than merely
true: *"renews on {date} at £X"* versus *"ends on {date}; no further charge"*.

**Cost:** a status fetch, a new published property, refresh points wherever it can go
stale, and a defined behaviour when it cannot be read — which is exactly the kind of
state machinery that should not be added to fix a sentence. **The wording change
removes the falsehood at zero cost.**

Worth doing **only if Samuel wants the stronger statement**, and it is a separate
decision rather than part of this fix.

### 3.1 Q7 CORRECTED — expectation was wrong; behaviour is observed, not explained

**Reported by Samuel, 22 September** (Device A, fresh UK tester, Solo): with airplane
mode on *and* Wi-Fi off, reopening the paywall — and force-quitting and relaunching —
still showed the free year and GBP prices. **This is a user report, not a screenshot or
an API trace**, unlike Q1/Q2.

**Q7 originally expected eligibility to clear to `false` and ordinary pricing to
appear. That expectation was wrong, and the implementation is not at fault.**

**What the source establishes.** In `ConnectedMembershipStore.loadProducts()`:

- `isEligibleForIntroOffer = false` runs **unconditionally, before** the load;
- `refreshIntroOfferEligibility()` sits **inside the `do`**, so it is reached **only if
  `Product.products(for:)` did not throw**.

So a persisting free year requires that **`Product.products(for:)` returned without
throwing and `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` returned
`true`** — including across the force-quit, where nothing in-process survived. That
much is forced by the code together with the report.

**What is NOT established, and I previously asserted it.**

- **The mechanism.** I wrote that StoreKit "almost certainly" serves cached product
  metadata and answers eligibility from local history. **Nothing here measured a
  cache.** What the cold launch supports is that StoreKit *answered successfully*
  while the device was reported offline; by what means is unknown.
- **That eligibility is "whether this customer has ever subscribed, needing no
  network". WITHDRAWN — this was wrong.** Apple's rule involves **at most one
  introductory offer per subscription group** *and* the customer's **current
  subscription status**; it is not a simple ever-subscribed test, and whether it can be
  resolved without a network is not something this exercise established.
- **That the offer and prices shown offline were correct.** They matched Q1/Q2 online,
  and they are plausibly right for a never-subscribed tester — but **`true` was not
  independently verified as the correct answer at that moment**, and cached prices are
  not guaranteed accurate. Q7 records what appeared, not that it was right.

**NO NETWORK GATE IS BEING ADDED.** Refusing to show an offer when unreachable would
invent a new failure mode and gate the answer on a signal that says nothing about
eligibility. The argument for that does not depend on any of the claims withdrawn
above.

**The branch Q7 was reaching for remains UNTESTED.** The guard that matters is that a
**genuinely failed** reload must not leave a stale `true` — structural, on the line
before the load. **Airplane mode does not reach it**, now shown, because the load does
not fail. Reaching it needs `Product.products(for:)` to actually throw. **Covered by
construction; not by device observation.**

**One residual, narrow.** If a member became ineligible elsewhere and then went
offline, a `true` answer could display an offer Apple would not grant. The *outcome*
stays safe — Apple decides at purchase, not us — so the exposure is wrong copy, not a
wrong charge. Q5/Q6 probe the online half.

---

## 3.7 BACKEND VERIFICATION — read-only, 22 September

Run against the linked production project with `supabase db query --linked`, **SELECT
only, no mutation**. UIDs shown as 8-character prefixes, following this project's habit
of not writing production UIDs down in full.

**Identity established from evidence, not assumed.** Today's
`SUBSCRIBED`/`INITIAL_BUY` carries `original_transaction_id` **2000001240320393**, and
exactly one `membership` row carries that otid: uid **`f0ba3610`**. A second Sandbox
identity (`ed6c420b`) exists and was last touched on 21 September; it is **not** this
run and is not scored.

**Note the clock:** stored times are UTC, one hour behind the local times in the QA
report (14:50 UTC = 15:50 BST).

### Predictions committed before the purchase, now scored

| # | Prediction | Result |
|---|---|---|
| 1 | `membership_binding`: 1 row, `created_at == updated_at`, unchanged from yesterday | **PASS.** Created **2026-09-21 12:51:19**, `never_updated = true`. One token survived a **change of Apple Account** and a fresh purchase untouched — the identical-timestamp discriminator that excludes delete-and-remint, same as B-24n |
| 2 | Exactly **one** Sandbox `membership` row for this identity, not two | **PASS.** `rows_for_this_identity = 1` |
| 3 | The row **re-points** to the new `originalTransactionId` | **PASS.** `created_at`/`bound_at` remain 2026-09-21 12:51:30 while `original_transaction_id` is today's 2000001240320393 |
| 4 | `binding_method` **not** re-derived | **PASS.** Still `'purchase'`, `bound_at == created_at` — untouched today |
| 5 | Attestation reports `alreadyEstablished` | **NOT SCORABLE from the backend** — a client outcome. Consistent evidence only: `INITIAL_BUY` landed **`applied`**, not `ignored`/`unestablished`, which requires both a matching token and a pre-existing row |

`membership_binding_conflict`: **0 rows.**

### The lifecycle arithmetic is correct

`renewal_date` and `entitlement_ended_at` both **2026-09-22 15:50:09+00**;
`pending_cleanup_at` **2026-11-21 15:50:09+00** — exactly 60 days. Quarantine scheduled
as designed, and **nothing has been deleted**.

### OBSERVATION — the DOWNGRADE notification landed `stale`

Today's four notifications, all on otid 2000001240320393:

| UTC | Type / subtype | Outcome |
|---|---|---|
| 14:50:10 | `SUBSCRIBED` / `INITIAL_BUY` | **applied** |
| 14:55:30 | `DID_CHANGE_RENEWAL_PREF` / **DOWNGRADE** | **stale** |
| 14:57:43 | `DID_CHANGE_RENEWAL_STATUS` / `AUTO_RENEW_DISABLED` | **applied** |
| 15:50:16 | `EXPIRED` / `VOLUNTARY` | **applied** |

`membership.product_id` reads `com.sdsongs.etudes.connected.monthly`.

### MY EARLIER CONCLUSION IS WITHDRAWN — `product_id` is not wrong

I wrote that "the monthly → annual switch did not reach `membership`" and that
`product_id` is therefore "not a reliable record of the member's current plan".
**Neither follows from this evidence.**

**`product_id` stores the CURRENT product, by design.**
`_shared/appstore/derive.ts:140`:

```ts
const product_id = str(tx.productId) ?? str(ri.productId) ?? str(ri.autoRenewProductId);
```

The **transaction's** product is taken first; `autoRenewProductId` — the *next-renewal
preference* — is only a last-resort fallback. A `DID_CHANGE_RENEWAL_PREF` is exactly
that: a preference for the **next** renewal, not a change to the period in force. So
during a monthly period with an annual preference pending, **`monthly` is the correct
value**, and the cancellation two minutes later (`AUTO_RENEW_DISABLED`, 14:57) meant the
switch never took effect at all. The subscription lapsed as monthly, which is what the
row says.

**And a `stale` outcome alone proves nothing about `product_id`.** Even had that
notification applied, `product_id` would still have derived from `tx.productId` and
still read monthly.

**What remains unestablished:** whether the `stale` outcome was itself correct. That
depends on the renewal-info `signedDate` the payload carried, and **we retain only a
`payload_sha256`**, so the payload cannot be re-read. The ordering guard keys on
renewalInfo's own `signedDate`, and this project has already recorded that a
notification signed later can carry renewal info signed earlier — which would make
`stale` correct — but **that is a mechanism that fits, not evidence that it happened.**

**Recorded as an observation with no established consequence. No defect is claimed and
no fix is proposed.**

### Q12's backend half

The free trial surviving the switch remains **Apple UI evidence only**. The backend
holds no record of a completed switch — correctly, because the switch was a deferred
preference that cancellation prevented from ever happening. So Q12 establishes what
Apple's UI showed at 15:56 local, and nothing more.

---

## 3.6 REMAINING ITEMS — launch blockers vs deferred coverage

Split as Codex asked. **Deferred coverage is not a blocker**; it is a gap recorded so
nobody later mistakes silence for a pass.

### LAUNCH BLOCKERS

| # | Item | Why it blocks |
|---|---|---|
| **B1** | **Production App Store Server Notification URL is unset** | Without it no production lifecycle event reaches the backend: no renewal, cancellation, expiry or refund. Membership state would be established at purchase and then never change. Explicitly release-gating in the decision register |
| **B2** | **App Store description and onboarding must state the renewal terms** | The in-app notice is not assured notice (§2). If the store copy does not say a free year renews at the standard price, the only clear statement is one the member may never open |
| **B3** | **Adult assurance and server trust** | Parked pending Apple Developer Support, and Connected establishment depends on it. Outside this work, and still a gate on launching Connected |
| **B4** | **The ~500 closure runbook does not exist** | §4 lists the steps but there is no rehearsed procedure, and the report it reads lags about a day (§5). **It must be ready BEFORE launch** — writing it while the offer is live and the count is climbing is the worst moment to discover a gap in it |

### DEFERRED COVERAGE — RECORDED GAPS, NOT ACCEPTED

**Nobody has accepted these.** They are gaps written down so silence is not mistaken
for a pass; **their disposition is Samuel's and has not been sought.** The "Disposition"
column is what is *known* about each, not a decision.

| # | Gap | What is known |
|---|---|---|
| **D1** | **Q11 positive** — restore an **active** subscription on a second device | Device B's SIWA identity differs; **its Dev data and sign-in are preserved**. The negative half passed. Needs a device with a matching identity |
| **D2** | **Q6** — subscribe elsewhere while backgrounded | Needs a live subscription on another device. The same refresh path was exercised by Q5 |
| **D3** | **Q9e** — a **paid** period shows no card | The trial was cancelled, so it lapsed rather than converting. Covered by unit test |
| **D4** | **Q9f** — a trial shorter than a year | **The configured offer is one year on both products, so no short trial exists to test. Covered by unit test and by the copy being length-agnostic. NOT pursued — no short-trial variant is being added for this.** |
| **D5** | **Q9d** — earlier than 30 days → no card | **Unreachable on accelerated Sandbox** (§3.1). Unit-tested only |
| **D6** | **Q3, Q13** — a product with no offer | Needs an ASC offer removed; should not share a pass with purchase checks. Exercises the same `isEligible == false` branch Q5 already passed |
| **D7** | **Q14** — French locale on device | Unit-tested (`en_GB` ≠ `fr_FR`). A device pass costs a language change and relaunch |
| **D8** | **The failed-load branch** — a genuinely throwing `products(for:)` | Airplane mode provably does not reach it (§3.1). Covered by construction |
| **D9** | **Whether the `stale` DOWNGRADE outcome was correct** | **NOT a `product_id` defect — that conclusion is withdrawn (§3.7).** `product_id` correctly holds the current product. Whether `stale` was right depends on the payload's renewal-info `signedDate`, and only a `payload_sha256` is retained, so it cannot be re-read |

### FIRST-PRODUCTION-PURCHASE FOLLOW-UP — not a pre-launch gate

**Every observation in this file is Sandbox, on a development build.** That cannot be
cleared before launch, because the first production purchase *is* the first production
test of this path. It is therefore a **follow-up to schedule at launch**, not a blocker
to clear beforehand: confirm on the first real subscriber that the offer presented, the
purchase bound, the notification arrived at the production URL (B1) and membership
established.

### CLOSED TODAY

Q1, Q2, Q4, Q5, Q8, Q9a, Q9b, Q9c, **Q10** (failed, fixed, re-verified at 16:24), Q11
negative half, and Q12's Apple-UI half.

**Backend predictions: FOUR of five scored, all passing** (§3.7). **Prediction 5 —
attestation reporting `alreadyEstablished` — is UNSCORED**, not passed: it is a client
outcome and no backend query can settle it. An earlier revision said "all five", which
was wrong.

Both changed test suites re-run by Samuel and passing.

---

## 4. ASC launch and closure checklist

**Launch**

1. ~~Configure a **1-year Free introductory offer** on **both** Connected products.~~
   **DONE 21 September (§0).**
2. ~~Eligibility: **new subscribers** only.~~ **WITHDRAWN — there is no such field on
   an introductory offer.** Apple defines the eligibility itself (never subscribed in
   the group) and it is not selectable. Selectable new / existing / expired cohorts
   belong to **offer codes**, which is where this was carried from; that route was not
   chosen. Nothing to configure or confirm.
3. ~~Verify both products are in the one subscription group.~~ **DONE — group
   22252441, both level 1 (§0).**
4. Sandbox-verify with the fresh UK tester before any public exposure (§3).
5. App Store description: mention the free year and that it **renews at the standard
   price unless cancelled**. Do not promise a reminder we do not send (§2).
6. **Production App Store Server Notification URL** remains a separate, release-gating
   item and is **not** discharged here.

**Closure, around 500**

7. Samuel watches trial starts (§5 definition) and **removes the introductory offer
   from both products** when approaching 500.
8. **Remove from both, or the remaining product keeps granting trials.**
9. Overshoot is accepted; withdrawal is not instantaneous and in-flight purchases land.
10. Update the App Store description and onboarding to the ordinary price.
11. **Existing trials are unaffected** — withdrawal stops new grants only, and must
    never be described as ending anyone's free year.

---

## 5. Production counting definition

**Count: new production Connected subscriptions whose initial transaction carried the
introductory offer, across monthly and annual, in the `Production` environment.**

Excluded, explicitly:

- Solo users and app downloads — **never** part of the count;
- **Sandbox and TestFlight** — different environment, never production;
- renewals of an existing subscription;
- resubscriptions by a customer who already had one;
- a member switching plan mid-trial, which must not count twice.

**Where the number comes from.** App Store Connect's **Subscription Report**, which
gives *"the total number of Active Subscriptions, Subscriptions with Introductory
Prices, and Marketing Opt-Ins"*, with the **Subscription Event Report** covering
introductory-price conversions. Sum across the two products.

- [Subscription Report](https://developer.apple.com/help/app-store-connect/reference/reporting/subscription-report/)
- [Sales and Trends reports availability](https://developer.apple.com/help/app-store-connect/reference/reporting/sales-and-trends-reports-availability/)
- [View subscription data](https://developer.apple.com/help/app-store-connect/view-sales-and-trends/view-subscription-data/)

**Our own `membership` table is not the source** — it records what attestation
established, which lags the purchase and misses anyone who has not opened the app, so
it would undercount.

### THE COUNT IS NOT LIVE, AND THE CAP DEPENDS ON THAT

**Daily reports are available the following day, generally by 8 a.m. Pacific Time**
[Apple, reports availability]. So the number Samuel watches is **at best about a day
old**, and there is no real-time figure.

**This is the mechanism behind the accepted overshoot, and it should be planned for
rather than discovered:**

- at a day's lag, a day's worth of trial starts can land after the figure that
  prompted withdrawal;
- withdrawal itself is not instantaneous, and in-flight purchases still land;
- so the practical rule is to **withdraw on the trend, before 500 is reached**, not on
  seeing 500 — e.g. act at ~450 if uptake is tens per day, or nearer 490 if it is a
  handful.

**Neither ASC nor our data makes "the 500th subscriber" exact**, and no promise
depending on that precision should be made. The promise is a free year for early
members while the offer is open, which is what the manual cap delivers.

---

## 6. Still open

- **§2's residual** — the reminder is decided and implemented; it is still not
  *assured* notice, and the App Store copy obligation stands.
- **Q12 plan-switching** — unverified, device gate.
- **ASC configuration** — **done by Samuel (§0)**. Nothing outstanding: the
  "new-subscribers eligibility field" I previously listed as unconfirmed **does not
  exist** on an introductory offer.
- ~~**The three new test files have never been compiled or run.**~~ **CLOSED
  21 September** — Samuel ran them in Xcode and all three suites pass. The Auto block
  on my running `xcodebuild test` was never bypassed; he ran them himself. Two
  reasoned-but-unobserved points are now measured: `weekOfMonth` renders as "weeks",
  and `en_GB` / `fr_FR` genuinely differ. **Simulator only — this says nothing about
  device or Sandbox behaviour.**
- **Adult assurance and server trust** — parked, outside this work.
