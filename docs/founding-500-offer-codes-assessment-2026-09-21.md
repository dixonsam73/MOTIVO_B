# Founding 500 — Apple offer codes vs a custom grant, short assessment

**21 September 2026. ASSESSMENT ONLY. No ASC change, no purchase, no implementation,
no scope switch.** Samuel's clarification: the first 500 are people who **subscribe to
Connected** — never downloads, never Solo users — and he prefers App Store Connect as
the controlling interface if practical.

Evidence classes as before: **[DOC]** Apple's documentation, **[LOCAL]** measured here,
**[UNMEASURED]**.

---

## 1. The headline

**Both Apple routes are viable, and the custom grant is now the least attractive of
the three.** Neither Apple route expresses "the first 500 *subscribers*" — but neither
does the custom grant (§7), which is a correction to my earlier claim.

**A twelve-month Free duration is documented** [DOC], so the question I flagged as
possibly fatal is answered. **The choice is now a product judgement**: which promise
Samuel wants to make (§7's table), not a technical elimination.

---

## 2. What offer codes give us for free — and it is a lot

A code-redeemed subscription **is an ordinary Apple subscription**. So the entire
membership architecture already handles it:

| Design section | Under offer codes |
|---|---|
| §3.1 `founding_place` table | **Not needed** |
| §3.2 serialised allocation | **Not needed** — Apple counts redemptions |
| §3.3 predicate changes | **Not needed** — `connected_member` already sees it |
| §3.3 visibility propagation | **Not needed** — `membership_entitled_until` already feeds the four cached columns |
| §5 grant-only quarantine and cleanup | **Probably not needed — a HYPOTHESIS, not a conclusion.** An Apple row exists, so U7's existing machinery applies in principle. But a **no-auto-renew** offer expires differently from an ordinary lapse, and neither its expiry notification shape nor its establishment behaviour has been validated. "U7 works unchanged" is what we would be **testing**, not what we know |
| §5.4 no-subscription Apple read | **Not needed** — there IS a subscription |
| §5.5 purchase/cleanup race | **Unchanged** — pre-existing, neither better nor worse |
| §8.1 adult-eligibility prerequisite | **Still required**, and still unresolved |

**"Evaluate avoiding a second grant authority" is exactly right, and this avoids it
entirely.** That is the strongest argument for this route: no new entitlement source,
no new authority predicate, no new destruction path — and FM-1's whole hazard (a
grant that must not impersonate a purchase) simply does not arise, because it *is* a
purchase.

**[DOC]** Free offer type, with **auto-renewal optionally disabled** — Apple's words:
*"a commitment-free trial subscription"*. That satisfies the settled no-automatic-charge
preference **better than the custom grant did**, because Apple enforces it.

---

## 3. What it cannot express

### 3.1 Redemption count is not subscriber order — [DOC], and this is the core mismatch

A cap limits **redemptions of that offer**. It does not limit **subscribers**. Anyone
may subscribe at full price at any time without touching the code, so:

- the 400th subscriber may be the 1st redeemer;
- the 501st subscriber may still redeem, if fewer than 500 have;
- **the offer can still be open after 500 people have subscribed**, and can be
  exhausted before 500 have.

**So "first 500 subscribers" becomes "the first 500 who redeem this code".** That is a
different promise. It is a perfectly reasonable promise — arguably a cleaner one — but
it must be *made* rather than assumed, and the App Store description and onboarding
copy must say it.

### 3.2 The cap is per product, not per group — [DOC]

Offer codes are configured **per individual subscription product** (*"Select the
subscription from the list"*), not per group. Monthly and annual are two products, so:

- a 500-cap on each gives **up to 1000 free years**;
- a shared 500 across both **is not expressible**.

**Two workable answers**, neither requiring code: offer the Founding code on **one
product only** (simplest — annual, since the offer is a year), or set two caps summing
to 500 and accept that the split is fixed in advance and cannot rebalance.

### 3.3 Bypass and sharing — [DOC]

A **custom code** is one string, redeemable by anyone who learns it. Apple limits each
customer to **one redemption per offer** and eligibility can be restricted to **new
subscribers** (never subscribed in the group) — both genuinely useful — but nothing
stops the string being posted publicly and the 500 going to strangers.

**One-time-use codes** avoid that (unique per person) but need distribution, which for
a launch offer means a mechanism Samuel does not have.

---

## 4. The binding collision — the finding that could decide this

**[LOCAL], from the SDK interface, and it is structural rather than an inference:**

```swift
@MainActor public static func presentOfferCodeRedeemSheet(in scene: UIWindowScene) async throws
```

**It takes a scene and nothing else.** There is no purchase-options parameter, so
**the redeem sheet cannot supply `appAccountToken`** — nor can the App Store
redemption URL, which does not involve our app at all.

**That is the limit of what the signature establishes.** What follows is a
**prediction from the deployed code, not a theorem**, and Codex is right to insist on
the distinction:

1. *Predicted:* the resulting subscription carries no token, so its
   `SUBSCRIBED`/`INITIAL_BUY` notification resolves to no binding and lands
   `ignored`/**`unmapped`**.
2. *Predicted:* membership is then established on the **legacy-claim path** at first
   attestation — client JWS → server sees no Apple token → Set App Account Token →
   independent re-read → `binding_method = 'legacy_claim'`.

**A fresh code-redeemed transaction's actual token and establishment behaviour is a
Sandbox measurement** (§6 check 2). It is entirely possible Apple behaves differently
than the absent parameter suggests.

**That path works.** S-1/S-2/S-3 proved it end to end on genuine Apple Sandbox. But it
**directly contradicts a settled rule**: U5f's 2026-08-23 correction says *"the legacy
path serves subscriptions that PREDATE bound purchase; it is not a fallback for new
ones"*, because its safety argument is that the token-less population is **finite and
shrinking**. Minting 500 new legacy-claim members makes it grow.

**Whether that matters is a real judgement, not a blocker:** 500 is finite, bounded and
one-off, which is arguably within the spirit of the original reasoning rather than
against it. But it reopens a settled decision, so it needs saying out loud rather than
discovering later.

---

## 5. Offer code vs a withdrawn introductory offer — CORRECTED

**My first table got the binding row backwards, and it was the row that mattered.**

| | Capped offer code | 1-year intro offer, withdrawn near 500 |
|---|---|---|
| Cap | **Apple-enforced**, exact on redemptions | **Manual** — someone watches and switches it off |
| Overshoot | None | **Possible, not certain.** Withdrawal is not instantaneous and in-flight purchases may land. How much depends on how closely it is watched |
| Auto-renew off | **Yes**, Apple-enforced [DOC] | **No** — it rolls into the standard price. Against the no-automatic-charge preference |
| Eligibility | New subscribers only, one per customer [DOC] | New/expired subscribers, by Apple's own rule |
| **Binding** | **Redeem sheet cannot supply the token** (§4) — predicted legacy-claim path | **✅ TOKEN PRESERVED.** The purchase still goes through our paywall via `product.purchase(_:appAccountToken:)`, and Apple applies the intro offer to an eligible customer automatically. **`binding_method = 'purchase'`, no settled rule reopened** |
| Later trial for #501+ | Separate offer, unaffected | **May be consumed** — Apple's one-intro-per-group rule. **[UNMEASURED]** |
| Visible to non-Founders | Code must be known | **Shown to everyone** on the paywall until withdrawn |

**The correction, stated plainly:** I wrote "No token — same problem" against the intro
offer. That is wrong. An introductory offer is applied by Apple **to an ordinary
purchase**, and our ordinary purchase is `MembershipSelectionView` → `purchase(_:
appAccountToken:)` at `:324`/`:333`, which already carries the binding token and
refuses StoreKit without it. **The intro-offer route therefore preserves ownership
binding completely and reopens nothing.** The redeem-sheet signature is a *different
API* and its limitation does not transfer.

So the two routes trade differently from how I first presented them:

- **Offer code** buys an Apple-enforced cap and Apple-enforced no-auto-renew, and
  costs the binding token (predicted) plus a reopened settled rule.
- **Intro offer** keeps binding and provenance intact, and costs a manual cap, a
  charge at the end unless the member cancels, public visibility, and possibly the
  later trial for #501+.

**Neither is clearly worse now.** My "clearly worse" verdict on the intro offer is
withdrawn — it rested on the binding error.

---

## 6. Minimal remaining checks

**Check 1 is now answered from documentation, and Samuel does not need to look.**
Apple's pricing and availability reference lists Free offer durations as 3 days,
1 week, 2 weeks, 1 month, 2 months, 3 months, 6 months and **1 year** [DOC]. A
twelve-month free offer is a documented option. **Whether this account is configured
with any offers remains uninspected**, which is a different question and not one to
send him hunting for now.

Two checks remain, both Sandbox, neither urgent:

1. **Does a code-redeemed subscription arrive unbound, and how does it establish?**
   [UNMEASURED] — §4's prediction, testable with a Sandbox offer code on a fresh
   tester. Also exercises the legacy-claim path end to end.
2. **How does a no-auto-renew offer expire, and does U7's existing machinery handle
   it?** [UNMEASURED] — §2's hypothesis. This is the one I would not skip if the
   offer-code route is chosen, because it sits on the destructive path.

---

## 7. Recommendation — revised

**Both routes are now viable and the choice is a product judgement, not a technical
elimination.** I no longer recommend waiting on a blocking check, because the
duration question is answered.

**Neither route gives subscriber-order precision on its own, and my claim that the
custom grant does is withdrawn — Codex is right.** A grant counts *grant claims*, not
Apple subscriptions: someone subscribing at full price without claiming a place means
grant #500 is not subscriber #500. Offer codes count *redemptions*. **Both count their
own thing.**

Getting "first 500 **subscribers**" from either would require **routing control** —
every route into a Connected subscription passing through one counter before the
purchase, and the paths that bypass the app (App Store product page, Settings,
redemption URL) either closed or accepted as leakage. That is a bigger commitment than
either option as described, and I do not recommend it for a launch offer.

**The practical question for Samuel is therefore which promise to make:**

| Promise | Route |
|---|---|
| "The first 500 who claim it" | **Offer code.** Apple enforces the cap; no auto-charge; one product only, or a fixed split |
| "A free year for early members, while places last" | **Intro offer.** Keeps binding and provenance; needs watching; charges at the end unless cancelled |
| "Exactly the first 500 subscribers" | **Neither, without routing control.** Not recommended |

**If he wants the simplest thing that keeps every settled rule intact, it is the
intro-offer route** — it changes no architecture at all, preserves binding, and needs
no new authority. **If he wants Apple to enforce the cap and guarantee no surprise
charge, it is the offer code**, at the cost of §4's reopened rule pending measurement.

**Either way the custom grant is now the least attractive of the three**, which is a
reversal from where this started and is worth saying plainly: it is the only one that
adds a second entitlement authority and a grant-only destruction path.

**F1's device session is only needed by the custom-grant route.** If Samuel picks
either Apple route, that session becomes unnecessary — which is a reason to settle the
product choice before running it.
