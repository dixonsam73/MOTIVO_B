# Founding 500 — F1 evidence and test plan

> **HISTORICAL, 21 September 2026 evening.** F1 gathered admission evidence for the
> **retired custom-grant route** (`docs/pricing-launch-model.md`), so **the F1 device
> session is no longer required** and the probe has been removed as a pure deletion.
>
> Two things here remain live and are carried forward rather than lost: the SDK
> findings in §2 about `introductoryOfferEligibility` — **client risk is not removed
> by a trivial shim**, and the compact JWS is passed unencoded — and §2.4's
> observation that the local `Etudes.storekit` file says nothing about App Store
> Connect. **§2.4 is now superseded in fact:** Samuel configured the offers on
> 21 September, recorded in §0 of `founding-500-launch-checklist-2026-09-21.md`.
>
> Nothing else here is an active requirement.

**21 September 2026. F1 IS AN EVIDENCE UNIT. NO PRODUCT CODE, NO IMPLEMENTATION.**

Authorised by Samuel on 21 September after his sign-off on the three product decision
groups: read-only source and documentation, isolated non-product probes, and the
*scoping* of any live inspection before it is performed. **No purchase, no device
change or reset, no production mutation, no credential disclosure, no deployment, no
commit, no push, no feature implementation, and no automatic progression to F2.**

Evidence is separated into three classes throughout and never mixed:

| Class | Meaning |
|---|---|
| **[DOC]** | Apple's own published documentation, fetched and cited |
| **[LOCAL]** | Measured on this machine — installed SDK, repository, certificates |
| **[UNMEASURED]** | Requires a device or a live Apple call. **Scoped here, not performed** |

Nothing in this document is a device result or a runtime observation. Where an
earlier design claim is corrected by measurement, the correction is recorded rather
than applied silently.

---

## 1. Summary of what F1 has established so far

| # | Question | Status |
|---|---|---|
| 1 | Does `introductoryOfferEligibility(compactJWS:)` exist and is it usable at our deployment target? | **CLOSED [LOCAL]** — yes, with no availability branching, and it is a trivial client shim (§2) |
| 2 | Do StoreKit-testing artefacts fail the pinned anchor? | **CLOSED [LOCAL]** for the StoreKit-testing configuration; the certificate is self-signed (§3) |
| 3 | Is `AppTransaction.shared` a cheap cached read? | **PARTLY [LOCAL]** — it is `get async throws`, so callers must await and handle a throw. **Caching is NOT disproved** (§4.1) |
| 4 | Does the SDK expose `storeType` to distinguish TestFlight? | **CLOSED [LOCAL] — NO.** It does not exist in the installed SDK (§4.3) |
| 5 | Does a pending purchase leave attributable server-side evidence? | **[LOCAL] — attribution depends on binding/token history**, including for external purchases (§5.4). Delivery is a veto only; absence proves nothing (§5.1) |
| 6 | Fresh-install `AppTransaction` behaviour | **[UNMEASURED], and the proposed session CANNOT close it** — it installs over an existing install (§6.2a). Closing it needs a disposable installation and separate approval |
| 7 | Apple's no-subscription response contract | **[UNMEASURED] but MATERIALLY NARROWED [DOC]** — three response shapes, not two, and Apple's own words require failing closed on the 404 (§6.0). Final answer device-gated *via the same session as 6* |

**REVISION 3.** Six Codex corrections accepted at revision 2, five more at revision 3;
§10 carries both sets. **Five of my conclusions are withdrawn outright** — a
binding-token requirement whose premise was false; a "may proceed" authority row
inferred from schema optionality; a session step that would have deleted a local-first
app's container; "external purchases are never attributable", which overstated the gap
Apple's renewal behaviour already closes; and a plan that claimed to install
instrumentation without an install. **The container one is the one to read first
(§6.2).**

---

## 2. Signed introductory-offer suppression

### 2.1 The signing claims — [DOC]

Apple's *Generating JWS to sign App Store requests* specifies, for introductory-offer
eligibility: `productId`; `allowIntroductoryOffer` (*"A Boolean value, `true` or
`false`, that determines whether the customer is eligible for an introductory
offer"*); and `transactionId` (*"The unique identifier of any transaction that belongs
to the customer. You can use the customer's `appTransactionID`, **even for customers
who haven't made any Apple In-App Purchases in your app**"*), alongside `iss`, `iat`,
`aud: "introductory-offer-eligibility"`, `bid` and `nonce`.

### 2.2 The client symbol — [LOCAL], and it is weaker machinery than assumed

Measured in the installed SDK interface
(`iPhoneOS26.5.sdk/.../StoreKit.swiftmodule/arm64e-apple-ios.swiftinterface`, line
1648 — Codex's citation is exact):

```swift
@backDeployed(before: iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4, visionOS 2.4)
public static func introductoryOfferEligibility(compactJWS: Swift.String) -> StoreKit.Product.PurchaseOption {
        Self.custom(key: "introOfferEligibilityParam", value: compactJWS)
    }
```

Four things follow, and the third and fourth are new:

1. **Availability is a non-issue.** The enclosing extension is `@available(iOS 15.0,
   …)` and there is **no further `@available` on the function**. With
   `IPHONEOS_DEPLOYMENT_TARGET = 26.4` (measured in `project.pbxproj`, four
   configurations) it is unconditionally callable, with **no `#available` branching**.
2. **`@backDeployed(before: iOS 18.4)`** means the body ships in our binary below
   18.4 and the OS provides it from 18.4 up. Irrelevant at our target; recorded so
   nobody re-derives it.
3. **The body is visible and is a one-line shim — but that does NOT make the client
   risk-free.** I wrote *"essentially none of the risk lives on the client"*; **Codex
   correction 6 is right and it is withdrawn.** What the shim establishes is only that
   *this one call* cannot fail for availability reasons. Client integration still owns:
   preparing the signed option before StoreKit is reached; its freshness at the moment
   of the tap; attaching it to the right product and the right account; keeping the
   mandatory `appAccountToken` binding alongside it; and handling the failure to
   prepare it (design §6.2's stop-before-payment). **A green compile proves close to
   nothing** — the "a green endpoint and a dead verifier look the same from outside"
   shape the U4a gate was built for.
4. **Pass the compact JWS as the API documents, and do not pre-encode it.** The
   signature takes `compactJWS: String` and the shim stores that string directly. My
   earlier framing contrasted this with the neighbouring
   `promotionalOffer(_:compactJWS:)`, which base64-encodes internally; **that
   comparison is narrowed away** as Codex asks, because the obligation is simply to
   pass what the documented API asks for. No claim is made about the other API's
   requirements.

### 2.3 What remains unmeasured

- Whether the App Store honours `allowIntroductoryOffer: false` for an Apple Account
  with **no purchase history** in our group. [UNMEASURED]
- Whether an incorrectly signed or expired JWS is rejected loudly or ignored silently.
  **This matters more than the success case:** silent ignoring would mean suppression
  appears wired and does nothing, and §6.2's stop-before-payment rule would never
  fire. [UNMEASURED]
- **[DOC, and unchanged]** Purchases begun outside the app carry no option from us.
  Apple scopes promotional and win-back offers to *"existing and previously
  subscribed customers"*, so neither reaches a Founder who never bought through
  Apple. The promise stays scoped to the in-app route, as Samuel approved.

### 2.4 App Store Connect

**Still uninspected**, and the design's withdrawal of the "no offer exists" claim
stands. The local `Etudes.storekit` carries `"introductoryOffers": []` on both
products [LOCAL] — evidence about the **local test configuration only**. Whether a
one-month offer exists in ASC, and on which products, is an account-holder question
(§8, Q3).

---

## 3. Admission evidence — what fails closed, measured

### 3.1 The pinned anchor — [LOCAL]

`_shared/appstore/apple_root_ca_g3.ts` embeds Apple Root CA G3 as the sole anchor.
`jws.ts:verifyChain` requires `x5c.length >= 3`, ignores the payload's own root
entirely, and verifies the intermediate against **our** anchor.

### 3.2 StoreKit-testing artefacts cannot pass it — [LOCAL], and this narrows a claim I withdrew

`/Applications/Xcode.app/Contents/PlugIns/IDEStoreKitEditor.ideplugin/Contents/Resources/StoreKitTestCertificate.cer`:

```
subject = CN=StoreKit, O=StoreKit, OU=StoreKit, C=US
issuer  = CN=StoreKit, O=StoreKit, OU=StoreKit, C=US      <- self-signed
```

Self-signed, no Apple chain. An artefact signed by it presents no three-certificate
Apple chain and is refused at `verifyChain`'s first guard.

**Precisely what this does and does not establish.** It establishes that a run using a
**StoreKit Testing configuration** cannot produce an admissible app transaction —
fail-closed, as wanted. It establishes **nothing** about an Xcode run with StoreKit
configuration **None**, which is this project's preferred loop and which uses *real*
Apple Sandbox StoreKit. In that configuration the artefact comes from Apple and would
verify; what its `receiptType` says is [UNMEASURED]. My original design sentence —
"the Founder path cannot be exercised from Xcode at all" — was correctly withdrawn on
Codex R7, and this is the narrower true statement that replaces it.

### 3.3 Client-side environment values — [LOCAL]

`AppStore.Environment` exposes exactly `production`, `sandbox`, `xcode`. The
**server-verified** payload (`JWSAppTransactionDecodedPayload.receiptType`) carries
only production or sandbox [DOC] — consistent, because an Xcode-signed artefact never
reaches Apple's servers and cannot pass §3.1. Pinning `Production` server-side, in
code, remains correct.

---

## 4. `AppTransaction` — one design paraphrase corrected, one assumption removed

### 4.1 `shared` is `async throws` — [LOCAL]

```swift
public static var shared: StoreKit.VerificationResult<StoreKit.AppTransaction> {
  get async throws
}
public static func refresh() async throws -> StoreKit.VerificationResult<StoreKit.AppTransaction>
```

**What this does and does not establish — narrowed after Codex correction 4.** It
establishes that callers must `await` and must handle a thrown error: `shared` is a
**call that can fail**, so the claim flow cannot treat it as a value that is simply
there. It does **NOT** establish that caching is absent — an `async throws` getter is
entirely compatible with returning cached information, and Apple's prose saying it
returns cached data is not contradicted by the signature. My earlier wording implied
the signature disproved the caching claim; **that inference is withdrawn.** Both may
be true, and which applies on a fresh install is [UNMEASURED].

**Consequence for the design, unchanged and modest:** the claim path needs a defined
behaviour when `shared` throws — refuse the claim calmly and retry later. Since no
place is consumed on a failed claim (design §3.2), refusing is cheap and is the
recommended default.

### 4.2 Fields available — [LOCAL]

`appTransactionID` (`@backDeployed(before: iOS 18.4)`, no availability problem at
26.4), `bundleID`, `environment`, `originalAppVersion`, `originalPurchaseDate`,
`originalPlatform`, `signedDate`, `deviceVerification`, `deviceVerificationNonce`,
`appID`, `appVersion`, `preorderDate`, `jsonRepresentation`. The JWS for the server
comes from the enclosing `VerificationResult.jwsRepresentation` [LOCAL].

### 4.3 `storeType` does NOT exist — [LOCAL]

A documentation summary consulted while drafting the design listed
`AppTransaction.storeType` among its properties. **It appears zero times in the
installed SDK interface.** No design text depended on it (`storeType` appears nowhere
in the design document), but the assumption is removed explicitly so it is not
reintroduced: **TestFlight is distinguished by `environment` / `receiptType`, and by
nothing else.**

---

## 5. Pending-purchase protection — evidence found, and two of my conclusions withdrawn

### 5.1 A delivered notification is POSITIVE evidence, and is not coverage — [LOCAL, corroborated by production record]

A purchase generates an App Store Server Notification that reaches
`appstore_notifications_v1` whether or not the client ever runs. Reading
`membership_ingest_notification_v1`:

- token resolves to **no** live binding → `ignored` / **`unmapped`**;
- token resolves to a live binding but **no membership row exists** → `ignored` /
  **`unestablished`**, because U4 is UPDATE-ONLY and will not originate a row.

Not theoretical: the B-24n record of 2026-08-30 documents it in production —
`SUBSCRIBED`/`INITIAL_BUY` landed `ignored`/`unestablished` at 14:58:15, delivery
beating attestation.

**Codex correction 2, accepted, and it is the difference between an observation and a
protection.** A delivered row proves a purchase happened. **Its absence proves
nothing** — a notification can be delayed, can fail delivery, or can never arrive, and
Sandbox does not retry at all (U4's own record). So this evidence can only ever
**veto** a destruction; it can never **authorise** one, and it does not reduce the
need for the canonical live Apple authority read. I described it as "a second,
already-deployed evidence source for the veto"; that is right only in the vetoing
direction, and the document now says so in both places rather than once.

### 5.2 It is not attributable to an identity as stored — [LOCAL]

`membership_notification`'s columns: `id, notification_uuid, environment,
notification_type, subtype, original_transaction_id, signed_date, received_at,
outcome, failure_category, request_id, payload_bytes, payload_sha256, delivery_count,
last_received_at`.

**No `user_id` column and no `app_account_token` column.** The resolved user
(`v_user`) is computed inside the ingest function and **discarded** — the update
writes only `outcome` and `failure_category` — and the payload survives only as a
`payload_sha256`, so the token cannot be recovered afterwards.

**So as deployed, `membership_notification` cannot attribute a pending purchase to an
identity.** Stating that precisely matters, because the row's existence looks like
sufficient protection and is not.

### 5.3 WITHDRAWN: "the Founder claim must establish a binding token"

**I claimed a Founder's later conversion would land `unmapped` because the grant
created no binding. That is wrong, and Codex correction 1 is right.**

Binding **already** precedes purchase, and it is enforced by the shipping code rather
than by convention. `MembershipSelectionView.swift:324` refuses to reach StoreKit
without the server-issued token — `guard case .ready(let token) = Self.purchaseReadiness(...)`
— and `:333` passes it as `appAccountToken:`. `loadBindingToken()` runs on appear with
one retry inside the purchase path. **A Founder converting through the in-app paywall
therefore always holds a binding before the purchase exists**, so the resulting
notification lands `unestablished`, not `unmapped`, with no change to the claim path
at all.

Establishing a binding earlier, at claim time, is therefore **optional** — a possible
tidiness, not a newly proved requirement, and **not a question for Samuel.** It is
removed from §8 for that reason.

### 5.4 Where attribution can fail — and "external" is NOT a single case

**CORRECTED AGAIN. I wrote that an external purchase carries no token "whether or not
a binding row exists" and is "unattributable in principle". That is too strong.**
Apple applies `Set App Account Token` to *"the current renewal transaction and all
subsequent renewals"*, and a token carried at purchase persists into future renewals —
which is exactly what S-3 measured on genuine Apple Sandbox on 2026-08-25, where a
real `DID_RENEW` ingested as `applied` because Apple carried our token into it.

So the discriminator is **whether that subscription already carries our token**, not
where the transaction was initiated:

| Route | Token carried | Notification | Attributable in principle |
|---|---|---|---|
| In-app conversion (`:324`/`:333`) | **yes, always** — the guard refuses StoreKit without it | `unestablished` | yes |
| Renewal of a subscription bound at purchase | **yes** — Apple carries it into renewals (S-3) | `unestablished` | yes |
| Resubscription where Apple still reports our token on that `originalTransactionId` | **likely yes**, and **[UNMEASURED]** — Apple does not document token survival across a lapse, and this project's standing rule forbids depending on `originalTransactionId` surviving every lapse-and-rejoin shape | `unestablished` if so | conditionally |
| A **new** subscription begun outside the app, never bound | **no** | `unmapped` | **no** |

**Only the last row is unattributable**, and it is the one Samuel approved honouring
without promising suppression (design §6.8). Calling every external purchase
unattributable would have overstated the gap and understated what the deployed binding
already achieves.

**What does not change:** the unattributable row is real, it cannot be closed by
earlier binding, and §5.1's rule still governs — delivery vetoes, absence proves
nothing.

### 5.5 What follows, and what does not

**It does not follow that an additive `user_id` column is the answer.** That is **one
candidate among several** and Codex correction 2 declines it as an accepted protocol;
it would not help §5.4's external route at all. **It is an internal F3 schema question,
not F1's and not Samuel's**, and it is removed from §8.

What does follow, and is unchanged: the canonical **live Apple authority read** remains
the primary protection, the notification stream can only ever add a veto on top of it,
and **the whole grant-only destruction protocol stays owned by the separate F3
review.** Neither this section nor §6.0 reduces that.

### 5.6 What none of this touches

The **dynamic** race (design §5.5) — a purchase landing *after* the authority check,
during the multi-second destructive sequence. Unchanged, pre-existing to Founding 500,
owned by the F3 protocol review.

---

## 6. Scoped live inspection — NOT PERFORMED, requires Samuel's authorisation

The two remaining F1 questions are **device-gated, and they are one session, not two**
— which is itself a scoping result worth having.

### 6.0 Narrowed by documentation alone — [DOC], no live call

Two fetches narrowed §5.4.1 without touching Apple's API, and one of them supplies
Apple's *own* instruction to fail closed.

**(a) An empty or absent `data` is schema-legal.** `StatusResponse` declares `data`,
`environment`, `appAppleId` and `bundleId` **all `required: false`**. So a well-formed
200 carrying no subscription array is representable in Apple's own schema, and the
worker **must not treat absent `data` as malformed**. Apple does not document the
no-subscription case explicitly, so this makes the "empty 200" branch *plausible*
rather than established — it remains [UNMEASURED].

**This turns the two-branch table in design §5.4.1 into three shapes — and, after
Codex correction 3, ALL THREE CURRENTLY BLOCK:**

| Shape | Reading | Worker, as things stand |
|---|---|---|
| Well-formed `StatusResponse` naming **our** `bundleId`, with no subscription data | **candidate** absence — not proved | **block**, pending the measured contract |
| 404 `TransactionIdNotFoundError` | **ambiguous** (see (b)) | block, retry later |
| Unparseable body, or a 200 not identifiable as our app's `StatusResponse` | no answer | block, retry later |

**I originally wrote "authority obtained → may proceed" against the first row. That is
premature and it is withdrawn.** `required: false` in Apple's schema means a field
*may be absent from the object*; it does **not** mean that an absent field asserts
"this customer has no subscriptions". Treating a schema optionality as a positive
statement of absence would be inferring destructive authority from silence — the same
error as reading a success message as evidence that the intended text ran. **Missing or
ambiguous data must block destruction until the actual absence contract and its
coverage are proved**, which is §6.2's measurement and the F3 review's to accept.

What the documentation does establish is narrower and still useful: **the discriminator
must include `bundleId` matching ours**, since a response we cannot attribute to our
own app is not an answer about our app at all — and absent `data` must not be
classified as *malformed*, because Apple's schema permits it.

**(b) A 404 is a REQUEST fault, not an absence of subscriptions — and Apple says not
to act on it.** `TransactionIdNotFoundError` is code **4040010**, documented as
arising when the JWT's `bid` does not match the transaction, or when the request is
made in a **different environment** from the one that generated the id. Apple's own
guidance is explicit: *do not unlock the service or content associated with the
transaction id unless the error is resolved.*

Two consequences, both already aligned with the design:

1. **It is Apple's own words for design §5.4.1's fail-closed rule.** If a 404 is not
   sufficient to *grant* access, it is certainly not sufficient to *destroy* content.
   The rule now rests on Apple's documented instruction rather than only on our
   caution.
2. **The environment must be derived from the stored `source_environment`, not
   guessed.** A Production `appTransactionId` queried against Sandbox returns exactly
   this 404 — indistinguishable, from the response alone, from a genuine absence. The
   design already stores `source_environment` on the place row; this is the reason it
   is load-bearing rather than descriptive, and querying the wrong host would
   manufacture the ambiguous branch on every call.

**What is still unmeasured after this:** whether an Apple Account that holds the app
and has *never* subscribed returns the first shape or the second. Documentation
cannot settle it; §6.2 can.

### 6.1 Why they are inseparable

Apple's no-subscription response contract can only be exercised by calling *Get All
Subscription Statuses* with an `appTransactionId` belonging to an Apple Account that
holds the app and **no Connected subscription**. An `appTransactionId` can only be
obtained by running the app on a device signed into that account. So obtaining the
input for question 7 **is** question 6.

### 6.2 Proposed session — REVISED TWICE, and both revisions corrected an error of mine

**REINSTALL IS REMOVED, AND CALLING THIS SESSION "DESTRUCTIVE OF NOTHING" WAS WRONG.**
My first version included *"a delete-and-reinstall of the app only"* and headed the
table *"minimal, and destructive of nothing"*. **Codex correction 5 is right and this
is the most serious error in the document.** Études is local-first: deleting the app
removes its container, and with it the journal, Scores, media and the attachment
privacy map. That is **architectural invariant 1** — the local journal is never
deleted by any Connected or membership action — and I proposed it in a document about
a membership feature. The phrase "the app only" was doing work it cannot do; there is
no "only" about an Études container.

**Reinstall is removed from the session entirely.** If cache-versus-network behaviour
ever needs measuring, it requires an **explicitly disposable installation on a device
holding no wanted data**, and **separate approval of its own**. It is not part of F1's
proposed session and is not requested here.

| Step | Action | What is actually involved |
|---|---|---|
| S0 | **Build and install an instrumented Études build over the existing install**, same bundle id, no uninstall | **This IS an install, and my earlier "no install, no delete" was incoherent** — instrumentation cannot appear without one. An in-place update over the same bundle id **preserves the data container**; it does **not** delete the journal, Scores or media. It **does rotate the container UUID**, which this project established from the Phase 2 restore and which is routine rather than a restore artefact. Nothing here deletes anything |
| S1 | Device already signed into an Apple Account with **no** Connected subscription | No purchase, no reset, no account change |
| S2 | The instrumentation reads `AppTransaction.shared`, recording: did it throw; how long it took; whether any system prompt appeared; `environment`; `bundleID`; and **a presence flag only** for `appTransactionID` — not the value, and **not a digest of it** (§6.3) | Read-only. Records no JWS and no identifier |
| S3 | Repeat on a later cold launch | Ordinary app use. Records what a cold launch returns; it does **not** measure cache versus network |
| S4 | With the `appTransactionID` — handled out of band, never through a public log — a **read-only** `GET /inApps/v1/subscriptions/{id}` against the environment named by `source_environment`, never a guessed host | GET only, no mutation |
| S5 | Record the response **shape** only: HTTP status; whether `bundleId` matches ours; whether subscription data is absent or empty; or 404 `4040010` | §6.0's contract, which **blocks destruction either way** until F3 accepts it |

### 6.2a What this session CANNOT close

**It cannot close the fresh-install gate, and must not be scored as if it did.** S0
installs *over an existing Études installation*, so whatever `AppTransaction.shared`
returns may come from state that install already held. The question F1 opened —
**what a genuinely first-run install returns, and whether it prompts** — is a
*first-run* question, and an existing install cannot answer it by construction.

So this session answers: *does `shared` throw, what environment does it report, does a
prompt appear, and what does Apple return for that identifier.* Those are worth
having. **The fresh-install behaviour stays [UNMEASURED]**, and closing it would need
an explicitly disposable installation on a device holding no wanted data, with
separate approval — which §6.2 does not request and F1 does not need in order to
report.

### 6.3 Where the diagnostic must live — I had this backwards

I wrote that the diagnostic *"must live outside `MOTIVO/`"*, reasoning from C-53:
`fileSystemSynchronizedGroups` auto-includes everything in that directory, which is
how `Etudes.storekit` came to ship inside a Release binary.

**The premise is true and the conclusion does not follow — Codex correction 5, second
half.** `appTransactionID` and the app transaction are properties of **an Apple Account
and a specific app**. A separate bundle has its own app transaction and its own
provenance, so **it cannot establish anything about Études' AppTransaction behaviour.**
Putting the probe outside the app target would measure the wrong app.

**The correct arrangement is this project's established one**, which I should have
reached for: a **temporary instrumentation file inside the Études target**, carrying a
standing removal condition — deleted the moment F1 is scored, with the removal verified
as a **pure deletion** against the pre-probe tree — exactly as `ActivationTrace`,
`MembershipTrace`, `JWSFreshnessProbe` and `C42StorefrontProbe` were. C-53's lesson is
not "keep probes out of the target"; it is **"know what the target includes, and
remove what must not ship"**. It must log through `os.Logger` with `privacy: .public`
(the Release-readability lesson), and **what may go into a public log is deliberately
narrow.**

**`appTransactionID` MUST NOT appear in a public log.** It is a stable, globally unique
identifier for an Apple Account and this app, persisting across devices, redownloads
and refunds — a pseudonymous personal identifier, not a diagnostic value. I listed it
among the recorded fields; that is corrected. **Presence only, and NOT a digest — tightened at Codex's preference.** I first proposed
recording a truncated digest so two observations could be correlated. A digest of a
stable identifier is a **stable pseudonymous correlator**: it still distinguishes one
Apple Account from another and still persists across devices and reinstalls, so it
inherits the property that made the raw value unloggable while looking safer. The
correlation it would buy is not worth that, and two observations on one device in one
session need no correlator. **The instrumentation records a boolean — an identifier
was obtained, or was not.** The identifier needed for S4 is transferred out of band and
never read from a device log.

The JWS is likewise never logged, under the standing bearer-artefact rule. Publicly
loggable: whether the call threw, its duration, whether a prompt appeared,
`environment`, and `bundleID`.

**This changes the authorisation being sought**, and it is stated plainly rather than
buried: a temporary file in the app target is a larger ask than a separate throwaway
bundle, and it is the only arrangement that answers the question.

### 6.4 Sandbox is not Production admission evidence

Whatever this session returns on a Sandbox-signed device establishes **Sandbox**
behaviour. The design admits `Production` only, in code (design §3.4), so a Sandbox
observation can show the *shape* of the artefact and the *shape* of Apple's response —
never that production admission works. **Real distribution behaviour stays an explicit
verification gate held until release** (design §9.2), and no Sandbox result may be
scored against it.

### 6.5 What I have NOT done, and will not without authorisation

- Not read, used or disclosed the In-App Purchase key at `~/.etudes-secrets/`.
- Not made any Apple API call.
- Not touched a device, simulator, build or test.
- **Not probed with a deliberately invalid transaction id.** That would establish the
  *404* branch only, which is **not** the branch that matters — "no such transaction"
  and "this customer has the app and no subscription" are different questions, and
  conflating them would produce a confident wrong answer to §5.4.1.

### 6.6 The simulator probe is WITHDRAWN

I offered an isolated simulator probe as a cheap partial step. **It is withdrawn**, on
§6.3's own reasoning and on Codex's instruction to skip it unless it answers a
necessary gate. A simulator probe would run under a **different bundle or with no App
Store provenance at all**, so it would measure something that is not Études' app
transaction — the same error as hosting the diagnostic outside the target. It answers
no gate that §6.2 does not answer properly, and it is not requested.

## 7. Revised F1 status against the design document

| Design claim | F1 disposition |
|---|---|
| §6 `introductoryOfferEligibility` available at target | **Confirmed [LOCAL]**, and it is a one-line shim. **It does NOT follow that client risk is removed** — preparation before StoreKit, freshness at the tap, product/account binding, the mandatory `appAccountToken` and stop-before-payment all remain client responsibilities (§2.2.3) |
| §6 encoding of the JWS | **Narrowed [LOCAL]:** pass the compact JWS as the API documents; do not pre-encode. No claim is made about any other API's requirements (§2.2.4) |
| §3.4 "`shared` returns cached information" | **Not disproved.** `get async throws` establishes only that callers must await and handle a throw; caching is entirely compatible with it. My inference against Apple's prose is withdrawn (§4.1) |
| §3.4 Xcode runs cannot produce an admissible artefact | **Narrowed and now measured** for StoreKit-*testing* only [LOCAL]. Configuration "None" remains [UNMEASURED] |
| §3.4 environment pinned in code | **Supported** [LOCAL]: three client values, two server values, no reason for a secret |
| §5.4.1 no-subscription contract | **Still [UNMEASURED], but the branch table is corrected from two shapes to three [DOC]**, the discriminator is `bundleId`, and the 404 must query the stored `source_environment` or it is self-inflicted (§6.0) |
| §5.4.3 unestablished purchase must veto | **Evidence found [LOCAL]; attribution absent as stored.** Attribution depends on token history, not on where the purchase began: a **new, never-bound** external purchase lacks the token; a **renewal** of a bound subscription carries it (S-3); a **resubscription** is conditional and **[UNMEASURED]** (§5.4). Delivery vetoes, never authorises (§5.1) |
| §5.5 dynamic race | **Unchanged.** Owned by the F3 protocol review |
| ASC offer state | **Still uninspected.** §2.4 |

---

## 8. Questions for Samuel — HELD, NOT ESCALATED

**Nothing here is escalated.** Two of my four proposed questions were not Samuel's to
answer, and the remaining two are held pending Codex's acceptance of this revision.

### 8.1 Withdrawn — these were never Samuel's

- **~~Q1, the simulator probe.~~** Withdrawn on its own merits (§6.6): it would
  measure a different bundle's app transaction and answers no gate.
- **~~Q4a, "should the Founder claim establish a binding token?"~~** Withdrawn because
  the premise was false (§5.3). Binding already precedes purchase at
  `MembershipSelectionView.swift:324`/`:333`. Early binding is an optional tidiness,
  not a requirement, and never a product decision.
- **~~Q4b, the additive `user_id` column on `membership_notification`.~~** Withdrawn as
  an **internal schema choice owned by the F3 review** (§5.5). Asking the account
  holder to adjudicate a column is the wrong escalation, and it would not help the
  external-purchase route anyway.

### 8.2 Held, pending Codex acceptance of this revision

- **The device session (§6.2).** Held rather than asked, because §6.3 materially
  changed what is being requested — a **temporary instrumentation file inside the
  Études app target** under a standing removal condition, not a separate throwaway
  bundle. That is a larger ask and should reach Samuel only once Codex has accepted
  the revised shape, including the removal of reinstall and the Sandbox/Production
  boundary. It needs his choice of device and Apple Account; I have inspected no
  device.
- **App Store Connect: does a one-month introductory offer exist, on which products?**
  Genuinely an account-holder question and genuinely open — nothing in ASC has been
  inspected, and the local `.storekit` file says nothing about it. Held only so that
  the F1 questions reach him once, together, rather than in instalments.

### 8.3 Not questions at all

Adult assurance, server trust, and the retention form and period remain open and are
**outside F1**. Nothing in this document advances or prejudges them.

---

## 9. What this document does not establish

- **No device, simulator, build, test, Apple API call or ASC inspection was
  performed.** No credential was read or disclosed. No file in `MOTIVO/` was touched.
- Every `[LOCAL]` result is from the **installed Xcode 26.5 SDK and this repository**,
  not from runtime. A symbol existing in an interface is not a symbol behaving
  correctly — §2.2's point 3 is the reason to keep saying so.
- F1 questions 6 and 7 remain **open**, and they are the ones that gate F2's admission
  design.
- Adult assurance and server trust, and the privacy-retention form and period, remain
  open and are **outside F1** entirely.
- **No F2 work has begun, and none is authorised by this document.**

---

## 10. Dispositions on Codex's F1 review

| | Disposition | Where |
|---|---|---|
| **1** Binding already precedes purchase | **Agree — my claim's premise was false.** Verified at `MembershipSelectionView.swift:324` (`guard case .ready(let token)`) and `:333` (`appAccountToken: token`). An in-app conversion always carries the token, so it lands `unestablished` with no change to the claim path. Early binding is optional, not proved, and **removed from the questions**. The cases are now distinguished in a table — **and that table was itself too strong at revision 2 and is corrected below (row 7)** | §5.3, §5.4, §8.1 |
| **2** Delivery is positive evidence, not coverage | **Agree.** A delivered row proves a purchase; **absence proves nothing** — delayed, failed or never-sent, and Sandbox never retries. It can only ever **veto**, never authorise, and it does not reduce the canonical live Apple authority read. The additive column is **one candidate, not an accepted protocol**, and is returned to the F3 review | §5.1, §5.5 |
| **3** Schema optionality is not destructive authority | **Agree — premature, and withdrawn.** `required: false` says a field may be absent from the object; it does not assert "no subscriptions exist". The "authority obtained → may proceed" row is gone and **all three shapes now block** pending the measured contract. What survives is narrower: the discriminator must include `bundleId`, and absent `data` must not be classed as malformed | §6.0 |
| **4** Async throwing getter does not disprove caching | **Agree.** It establishes only that callers must await and handle a throw. Apple's "returns cached information" is **not contradicted** by the signature, and my inference is withdrawn. S3 likewise no longer claims to measure cache versus network — a cold launch alone cannot | §4.1, §6.2 S3 |
| **5** Do not call reinstall destructive of nothing | **Agree, and this was the most serious error in the document.** Études is local-first; deleting the app removes the journal, Scores, media and privacy map — **invariant 1**, proposed inside a membership document. Reinstall is **removed from the session**; any later test needs an explicitly disposable installation and separate approval. On hosting, **I had it backwards**: a separate bundle has its own app transaction and cannot establish Études' behaviour, so the diagnostic must be **temporary instrumentation inside the Études target** under a standing removal condition, verified as a pure deletion — the project's established pattern. Sandbox results are explicitly barred from being scored as Production admission evidence | §6.2, §6.3, §6.4 |
| **6** A trivial shim does not remove client risk | **Agree.** "Risk entirely server-side" is withdrawn; client integration still owns preparation before StoreKit, freshness at the tap, product and account binding, the mandatory `appAccountToken`, and stop-before-payment. Invalid/expired-signature behaviour stays **[UNMEASURED]**. The encoding comparison is narrowed to the one obligation that matters: pass the compact JWS as documented, do not pre-encode | §2.2 |

### Revision 3 — final consistency pass

| | Disposition | Where |
|---|---|---|
| **7a** §7 repeated withdrawn claims | **Agree.** The status table still carried "risk is entirely server-side", "raw, not base64" and "`shared` returns cached information — **Withdrawn**". All three now match the corrected bodies rather than contradicting them two sections later | §7 |
| **7b** External purchases **may**, not **never**, lack tokens | **Agree — I overstated it in the direction that flatters the gap.** Apple applies the token to *"the current renewal transaction and all subsequent renewals"*, which **S-3 measured on genuine Apple Sandbox**: a real `DID_RENEW` ingested as `applied` because Apple carried our token into it. So a renewal of a bound subscription **is** attributable; a resubscription is conditional and **[UNMEASURED]**, under the standing rule never to depend on `originalTransactionId` surviving a lapse; only a **new, never-bound** external purchase is unattributable. Four rows, not two | §5.4 |
| **7c** The plan said "no install" | **Agree — incoherent.** Instrumentation cannot appear without a build and an install. S0 now says so: an in-place update over the same bundle id, which **preserves the data container** while rotating its UUID (routine, established in Phase 2). Nothing is deleted, and the plan no longer implies the instrumentation arrives by magic | §6.2 S0 |
| **7d** An existing install cannot close the fresh-install gate | **Agree, and it is a real limit on what the session is worth.** Installing over an existing Études install cannot answer a *first-run* question by construction. The session's value is narrowed to: does `shared` throw, what environment, does a prompt appear, what does Apple return. **Fresh-install behaviour stays [UNMEASURED]** and would need a disposable installation and separate approval | §6.2a |
| **7e** `appTransactionID` must not reach public logs | **Agree.** It is a stable, globally unique per-Apple-Account identifier persisting across devices, redownloads and refunds — a pseudonymous personal identifier, not a diagnostic. I had listed it among the recorded fields under `privacy: .public`. The instrumentation records a **presence flag only** — tightened further at Codex's preference from the truncated digest I first proposed, because a digest of a stable identifier is still a stable pseudonymous correlator. S4's identifier is transferred out of band | §6.2 S2, §6.3 |

**Also actioned from the review's closing instructions:** the optional simulator probe
is **withdrawn** (§6.6) rather than deferred, because §6.3's reasoning disqualifies it;
the internal schema choice is **not** put to Samuel (§8.1); and **no question is
escalated** — both surviving ones are held in §8.2 pending Codex's acceptance of this
revision, since §6.3 materially changed what the device session actually asks for.

### Pre-execution obligations — required before any F1 device step runs

Recorded here so they are not lost while check-ins are paused. **None is produced in
this document, and none is requested yet.**

1. **A concrete signing and install plan** for the instrumented same-bundle build:
   which signing identity and provisioning profile, and how the install is performed
   as a **data-preserving in-place update** rather than a replace. "It preserves the
   container" is an assertion until the mechanism is written down.
2. **A private transfer route for the `appTransactionID`** from device to the S4 API
   call, given that it may not appear in any public log. The route, and where the
   value rests in the meantime, must be named.
3. **Samuel's choice of device and Apple Account**, and his approval of the bounded
   test. Not asked yet.
4. **The standing removal condition**, stated before the instrumentation is written:
   deleted the moment F1 is scored, with the removal verified as a pure deletion
   against the pre-probe tree.

**Unchanged by this revision:** the canonical live Apple authority read remains the
primary protection; grant-only destruction stays owned by the separate F3 protocol
review; the dynamic purchase/cleanup race is untouched; and adult assurance, server
trust and retention remain open and outside F1.
