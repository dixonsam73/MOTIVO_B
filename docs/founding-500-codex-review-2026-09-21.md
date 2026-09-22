# Founding 500 — independent Codex review

## Current authorisation — Apple introductory trial approach supersedes custom grants

**22 September, backend report independently reviewed:** Claude reports read-only
evidence of applied INITIAL_BUY, AUTO_RENEW_DISABLED and VOLUNTARY EXPIRED events
for today's transaction, one matching Sandbox membership row, historical binding
timestamps and zero binding conflicts. Client attestation outcome remains unscored;
do not describe all five predictions as passed. Codex reviewed the recorded results,
not an independently executed database query. A stale renewal-preference event does
NOT establish product drift: derive.ts prioritises the current transaction product,
which may remain monthly while annual is the next renewal preference. Claude verified
this source distinction and withdrew the drift conclusion. Production purchase
verification is a first-real-purchase follow-up, not a prelaunch test achievable in
Sandbox. Outstanding coverage is not silently accepted by Samuel; closure procedure
readiness belongs before launch.

**22 September 16:57, expired restore:** after Restore Purchases and authentication
with the same Sandbox tester, screenshot shows "No membership found — No active
Études Connected membership was found", over ordinary monthly/annual pricing.
Negative restore result PASS; this does not verify restoration of an active
subscription or second-device identity binding.

**22 September, latest device evidence through 16:55:** Samuel reports both revised
test suites passed in Xcode. Updated build installed; 16:24:11 screenshot verifies
the new conditional automatic-renewal wording in Profile, without clipping. This
supersedes the pending test status below. Revised feed-card copy is source-reviewed
and unit-tested, not yet visually exercised because that trial's card was dismissed.
After the cancelled trial elapsed, Samuel reports Device A returned to Solo with
Explore Connected in Account. At 16:55:16 the paywall screenshot shows GBP 4.99/month
and GBP 49.99/year, no free-trial wording: post-expiry ineligible display PASS.
Exact expiry timestamp and backend binding remain unverified. Device B restore is
deferred because its SIWA identity differs; preserve its Études Dev practice data
and Apple sign-in. An expired-subscription restore on A would be a separate negative
check, not a substitute for active-subscription restoration on another device.

**22 September, cancellation-copy correction reviewed:** Profile and journal reminder
now both say: "Your free trial ends on {date}. If automatic renewal is on, Études
Connected then continues at the standard price." Reviewed both production strings
and updated tests, including agreement between the two surfaces. No renewal-state
machinery added. Claude reports Release build clean; updated test execution was
rejected by Claude's automatic approval review citing earlier conversation content.
Changed tests therefore await Samuel's manual Xcode run; yesterday's passes do not
cover these edits. Device verification of revised wording remains outstanding.

**22 September, Q7 reconciliation:** Samuel confirms unchanged offer after offline
force-quit/relaunch, then reconnects Device A to the network and Xcode. Claude corrected
checklist section 3.1 after independent review: Airplane Mode is not a reliable way
to force a StoreKit load failure. Offline offer persistence is observed, not proof
of a cache mechanism or current price accuracy. Failed-load fallback remains untested
on device. No code change warranted by this observation alone. Next is Apple's
Sandbox purchase sheet, checking trial and subsequent price before confirmation.
Samuel clarifies the SIWA/backend identity previously had Connected with another
Sandbox tester. This fixture is an existing Études identity plus a fresh Apple Sandbox
tester, NOT fresh identity onboarding. Verify new subscription binding after purchase;
do not erase the existing account or its data.

**Device QA, 22 September:** Samuel reports fresh Sandbox tester signed in,
latest build installed on Device A, starting in Solo. Online screenshot at 15:36
shows both one-year free offers, GBP 4.99/month and GBP 49.99/year thereafter,
automatic renewal and cancellation disclosure without clipping: Q1/Q2 visual PASS.
After requested offline reopen, Samuel reports the screen unchanged. Q7's predicted
ordinary-price fallback was NOT observed; not scored PASS. Source clears eligibility
before product loading, then asks StoreKit again; no evidence yet distinguishing
StoreKit cached responses, unfinished refresh, or a missing refresh trigger. Offline
cold-launch observation pending. No purchase reported.

**Final evening check-in, 21 September:** Samuel reports all three suites passed
in his manual Xcode run: `ConnectedOfferPresentationTests`,
`ConnectedRenewalPresentationTests`, and `ConnectedTrialReminderTests`. Codex checked
Claude's matching final response and updated checklist/runbook. This supersedes the
earlier pending-test status below; Codex has not independently inspected an xcresult.
Device/Sandbox QA remains pending for tomorrow. Monitoring stays paused for the night
at Samuel's request. No further tests, implementation, deployment, commit or push.

**Evening preparation complete, 21 September 20:37 UTC:** Codex reviewed the
tomorrow runbook and Claude corrected the reversed Sandbox reminder-window claim,
invented introductory-offer eligibility field, and permission-workaround suggestion.
Codex also corrected the residual contradictory final bullet and eligibility wording.
Runbook: `docs/founding-500-runbook-2026-09-22.md`. No code or device changes in
this preparation pass; HEAD remains f758a84. Monitoring paused. First step tomorrow
is Samuel's manual run of the three named test suites, then build/install and device
QA if they pass. Test execution remains blocked for Claude by its reported automatic
review of earlier conversation content. No test pass or release readiness claimed.

**Evening preparation authorised by Samuel, 21 September:** continue useful local
preparation with Claude and eight-minute independent review; device testing is
deferred until tomorrow. No device sign-in, purchase or install tonight. Finish a
short ordered test runbook and reconcile current documentation with the screenshot
evidence below. Do not repeat passed builds without changes or bypass the existing
test-execution approval block. When preparation is complete or only blocked test
execution/device QA remains, pause monitoring and report the exact next step.

**ASC changes performed by Samuel and observed in screenshots tonight:** monthly
and annual each show Free for the first year, 21 September 2026 to No End Date,
175 countries/regions. Both products now show level 1 in group 22252441. UK standard
prices observed: monthly GBP 4.99, annual GBP 49.99. Products remain Prepare for
Submission; app is not launched. Billing Grace screenshot shows 16 days, All
Renewals, Only Sandbox Environment. Fresh UK Sandbox tester created by Samuel;
no sign-in or purchase reported. This supersedes earlier 'ASC not inspected/changed'
statements; does not establish StoreKit propagation or successful device testing.

**Review checkpoint, 21 September, 19:26 UTC:** feed reminder corrections reviewed
in source: generic free-trial wording, 44-point dismissal target, foreground Apple
subscription sheet and visible failure guidance. Local dismissal is scoped to trial
identity; Profile summary remains. Claude reports final Debug/Release builds clean.
No device or visual QA has been performed by this reviewer. The three new test files
remain uncompiled/unrun under Claude's reported Auto-review block. Implementation
review is ready for verification, not launch sign-off. Eight-minute monitoring paused
at the user-assisted test/device QA boundary. Next: resolve test execution, inspect
current ASC subscription settings, then fresh-Sandbox purchase/restore/cancellation,
plan-switching and reminder visual/dismissal QA. No deploy, commit or push.

**Reminder decision approved by Samuel, 21 September:** proceed with a subtle,
dismissible reminder in the ContentView feed, reusing the existing milestone-alert
formatting. Show it for an active free trial in its final 30 days, with the end
date and a Manage Subscription action. Respect dismissal across launches for that
trial; avoid repeated nagging and avoid carrying dismissal to a different trial.
Keep wording accurate for cancellation (an expiry date alone does not prove renewal).
Keep the Profile summary. This is an in-app reminder, not assured delivery outside
the app. Update the checklist and run permitted verification; existing test-execution
approval blocks must not be bypassed. Eight-minute independent reviews resume.

Samuel has now explicitly instructed Claude and Codex to proceed with the bounded
work below, with independent Codex reviews every eight minutes, stopping only for
a genuine product decision, device QA, or an actual execution/permission blocker.
Études remains beta/TestFlight, NOT publicly launched. Age assurance is parked
pending the Apple Developer Support reply; do not reopen that work here.

Agreed direction: Apple's one-year introductory free trial on Connected subscriptions.
Count new production Connected trial starts across monthly and annual, never Solo
downloads or Sandbox/TestFlight tests. Samuel monitors uptake and removes launch
offers around 500; modest overshoot is acceptable, no exact allocation machinery.
Automatic paid renewal is accepted with clear upfront terms and notice near expiry.
Monthly/annual choice exists at signup and should be available for review near expiry;
do not assume switching preserves the free period until tested. Apple owns entitlement
and renewal; retain existing binding/attestation/enforcement architecture.

Authorised work now:
1. Retire the custom-grant implementation direction in durable scope notes. Preserve
   historical reviews without treating them as active requirements. No grant ledger,
   new entitlement authority or grant-only cleanup system is to be implemented.
2. Remove only the temporary F1 probe and its five-line call site, preserving other
   changes. It has never been run on a device; no private extraction is needed.
3. Implement offer-aware monthly/annual selection using current StoreKit offer and
   eligibility data; clear free duration, subsequent localised price, billing cadence,
   automatic renewal and cancellation information; ordinary pricing when no eligible
   offer exists. Preserve mandatory appAccountToken and purchase/restore behaviour.
4. Inspect existing reminder and subscription-management capabilities and prepare/
   implement the smallest appropriate renewal-date and plan-review experience.
   Do not invent email infrastructure or promise delivery when notifications are
   disabled. Ask Samuel only for a material unresolved product choice, with concrete
   options after completing independent work. Plan switching remains a QA gate.
5. Run meaningful local tests/builds for affected behaviour, including offer absence,
   ineligibility, localisation and existing binding invariants. Prepare concise device
   QA for Sandbox trial, restore, cancellation, plan change and offer withdrawal.
6. Prepare the short ASC launch/closure checklist and production counting definition.

No live ASC edits, purchases, device changes, production deployment, TestFlight upload,
commit or push authorised. Protected unrelated files remain untouched. Claude's
reported Auto-mode block must not be evaded; if it persists, report the exact blocked
action and reason and request the minimal user intervention. No replacement Claude
window or permission-mode changes without Samuel's instruction.

21 September 2026. Planning only. Samuel has confirmed Founding 500 as a launch
requirement. This review authorises no implementation, deployment, commit or push.

## Final reconciliation outcome — supersedes pending labels below

**Subsequent Samuel sign-off, 21 September 2026:** agreed to the reconciled scope
and all three product recommendation groups. Former beta testers receive **no
special code, reserved places, migration or exception**; they may activate normally
from the public app. Samuel will notify them before launch himself; no agent outreach
is requested. No retrospective grant for existing paid subscribers; spent places
never return to the pool. Minimal pseudonymous retention to prevent repeat grants
is approved in principle, with form, duration and privacy review unresolved.
Conversion at expiry, in-app trial suppression, stopping before payment on signing
failure, and honouring valid external purchases are approved.

The conditional review below predates that product sign-off. Its technical evidence,
adult-only, cleanup protocol and privacy gates remain open; no cleanup exception,
implementation, deployment, commit or push is approved by this review record.
The design hash below identifies the reviewed technical revision **before** the
subsequent decision note was added.

**Conditional planning acceptance.** Independently checked Claude's revised design,
including its explicit R1–R7 dispositions and five final consistency corrections.
The two readers now agree on the practical scope and review boundaries. This is
acceptance of a planning direction with named gates, **not** an implementation-ready
SQL/protocol specification, Samuel's scope sign-off, evidence of successful runtime
behaviour, or permission to deploy.

Reviewed final design SHA-256:
`95833f686edd722dc0d488a88f2ac588221558ef097757ce940d32c00ea686fe`.
After Claude finished, Codex corrected one remaining Group B1 sentence to match
the already-agreed §3.1: anonymisation preserves the spent marker, rather than
"drops every attribute". No substantive new design choice was introduced.

The final corrections cover serialised/idempotent allocation; a permanent spent
place even after account deletion; separate real grant authority and visibility;
combined client access with expiry/identity handling; genuine grant completion for
F3 publication; server eligibility as an unresolved prerequisite; stop-before-payment
if Founder trial suppression cannot be prepared; and grant-preserving rollback.
Arbitrary grant revocation is optional and excluded from the baseline.

**Three product decision groups remain for Samuel**, with these recommendations:

- Public-store activation qualifies, including former beta testers after moving to
  the public build; beta QA never consumes places. No retrospective grant for an
  already-paying member. Spent places are never recycled.
- Decide whether preventing repeat grants after account deletion warrants retaining
  a minimal pseudonymous identifier, and settle its form/retention period with the
  privacy position. Anonymous capacity accounting does not require that identifier.
  Neither a hash nor an HMAC alone resolves the privacy decision.
- Offer conversion at expiry, avoiding paid/free overlap; enforce no extra trial
  on the in-app route, stop before payment if signing fails, and honour valid
  external Apple purchases without promising global trial suppression.

**Evidence/protocol gates remain real work**, owned by F1 and the separately reviewed
F3 cleanup unit: production admission behaviour, no-purchase Apple responses,
coverage after Apple Account changes, unestablished paid subscriptions, and purchase
versus deletion ordering. An API accepting AppTransaction IDs does not establish
these properties. No executable cleanup change is accepted here. Full ordinary lapse
and eventual cleanup remain FM-2 requirements. Disabled cleanup is safe interim
behaviour only; a public staged exception needs Samuel's explicit decision, a named
owner and dated completion gate before first Founder maturity, with grant-aware
vetoes on every cleanup path. G7 is not expanded or closed.

Adult-only assurance and the server trust/access contract remain separately owned
release dependencies. Public Founder allocation cannot open before that contract
is settled. Existing band protections, account deletion access and the local journal
remain protected.

**Sequence agreed:** evidence/interfaces → private ledger and atomic claim →
separately reviewed cleanup → client/status/conversion → validation and separately
authorised launch configuration. Samuel's scope approval precedes implementation;
F1 live measurements, if needed, must be scoped without credential disclosure or
unrequested purchase/device changes.

**Final checkpoint:** local HEAD and a fresh read-only remote query both returned
`f758a8409efc8992caadc63883b66b3ddafc0f0e`. Only the two new Founding documents were
created in this work, plus the one consistency edit noted above. The existing
`AGENTS.md` and two modified invitation documents remain untouched. No source,
test, configuration or backend changes; no builds, tests, deployments, commits or
pushes by Codex. Coordination used only the identified new Claude task.

## Checkpoint and coordination

### F1 independent review — 21 September, first scheduled check

**Second diagnostic / first Apple-offer review.** Error logging and launch instructions
are materially corrected; no reason to remove static error type names. Preparation
is not yet approved for execution. Resolve these bounded items:

1. Offer comparison incorrectly says an introductory-offer purchase has no token.
   The existing `Product.purchase(...appAccountToken:)` path can carry an intro
   offer AND the binding token. The redeem-sheet signature is a different API.
   Correct the table and recommendation. Missing purchase-options on that sheet
   supports inability to supply the token there; a fresh-code transaction's exact
   token and establishment behaviour remains a Sandbox measurement, not a theorem.
2. 'Overshoot certain' is false; manual withdrawal risks overshoot, it does not
   guarantee it. Likewise a custom grant originally counts grant claims, not all
   Apple subscriptions globally: it does not automatically satisfy subscriber-order
   precision either. Explain routing/control needed for either option.
3. Apple's pricing reference explicitly lists one year under Free offer durations:
   https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/in-app-purchase-and-subscriptions-pricing-and-availability
   Treat year duration as documented, account configuration uninspected. Do not
   send Samuel to inspect ASC just because the first help page links to the list.
   Native entitlement reuse is promising but 'U7 works unchanged' still needs
   no-auto-renew offer expiry/establishment validation; make it a hypothesis.
4. Private file proposal: only verified expected-bundle evidence may produce it;
   stale-file deletion before a new read is good. An ordinary launch is inert, so
   cannot also promise to delete that file. Specify a separate explicit cleanup
   action that never calls AppTransaction or rewrites the file; verify device and
   host removal before removing probe code. Use a permission-restricted location
   outside repo for host copy, and a reader that keeps the ID and request URL out of
   command arguments/output/errors. Do not build a whole secure-transfer platform.

Keep this comparison short and practical. No device actions or ASC mutations yet.

**Latest product clarification — Apple-managed alternative to assess alongside F1.**
Samuel prefers simplicity and App Store Connect as controlling interface if practical.
The first 500 are people who SUBSCRIBE TO CONNECTED, never app downloads or Solo
users. A later conversion from Solo counts only when subscribing. He has not asked
us to stop the diagnostic work, nor authorised implementing the bespoke ledger.
Assess a bounded Apple offer-code alternative before any custom grant work:
https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes
Apple documents free offers, optional disabled auto-renewal, custom-code redemption
limits, new-subscriber eligibility and Sandbox codes. Compare an offer capped at 500
with a one-year introductory offer manually withdrawn near 500. Do not equate first
500 code redemptions with first 500 subscribers without explaining the join flow,
bypass paths and cap across monthly/annual products. Examine existing binding and
attestation for code redemption, expiry and restore; actual runtime remains unproven.
Preserve earlier no-automatic-charge preference unless Samuel changes it. Existing
backend membership infrastructure remains; evaluate avoiding a second grant authority.
Provide a short recommendation and minimal remaining checks, not another large
architecture document. No ASC configuration change, purchase, deployment or scope
switch implementation is authorised. Diagnostic corrections/review continue.

**Diagnostic preparation review — first pass, not approved for execution.**

- `F1AppTransactionProbe` publicly prints `String(describing: error)` for thrown
  and unverified results. Truncating to 200 characters is NOT sanitisation: an ID,
  credential fragment or URL can be shorter. Replace arbitrary descriptions with
  fixed allowlisted categories/numeric codes; do not print unknown descriptions,
  NSError userInfo, URLs or embedded payloads. Remove the false token-length claim.
- Home-screen launch does not inherit Xcode's Run arguments. Repeat the second
  measurement through Xcode with the argument explicitly supplied; distinguish
  that from an ordinary Home-screen launch, which should remain inert.
- P1 overgeneralises: one throw proves only this invocation failed, not that all
  development installs lack AppTransaction. P2 must distinguish verified from
  unverified, and neither the environment string nor client verification alone
  measures acceptance by our server chain verifier. Record unexpected Production
  values too without turning them into public-distribution evidence.
- The normal app startup still runs beside this probe, including existing auth/
  attestation/queue work. State that the probe introduces no such calls, not that
  the whole test session guarantees no backend effects. Scope existing-session
  effects before device execution; do not invent a large lifecycle bypass.
- S4 private transfer was explicitly part of the authorised preparation. Do not
  replace it with D merely to avoid presenting a reviewable mechanism. Prepare a
  concrete minimal private transfer/reader proposal (no public logging, no whole
  personal-container download), including retention and removal, for independent
  review. The user need not choose internal plumbing. No live call is authorised.
- Cleanup should remove only the five inserted lines and probe file. Do not direct
  a future operator to discard the whole MOTIVOApp.swift working diff; other edits
  may have arrived by then. Verify the targeted reversal against the recorded base.

Build successes are compile evidence only; device signing/install remains untested.
Please correct these and report a concise disposition. No device execution yet.

**Samuel's subsequent instruction: proceed with diagnostic preparation.** Études
is still beta/TestFlight, NOT publicly launched. Samuel can create a fresh Sandbox
tester; Device A (Beta Burner) is the proposed test device. He has offered to clear
its app data if needed, but no agent should delete it or change accounts now.
He reports nothing set up at the App Store yet; do not infer that the already-used
Sandbox IAP products do not exist. Introductory-offer settings remain uninspected.

Claude may now prepare temporary F1 instrumentation and a local diagnostic build,
with independent Codex review before device execution. First record its removal
condition, precise signing/install route, and private handling/transfer of the
AppTransaction identifier. Public output is presence-only, no raw ID, digest, JWS
or credentials. Keep the probe inert unless explicitly invoked for this test;
no automatic purchase, auth, backend write or activation. Use the established app
target/bundle, preserve unrelated changes, and keep a clear reversible diff.
No feature/F2 implementation, deployment, upload to TestFlight, commit or push.
No device install, uninstall, reset, account switch or live Apple request yet:
prepare the reviewable steps and return the short instructions Samuel will need.
Fresh tester history, fresh local installation, Sandbox admission and public App
Store admission are distinct evidence; do not claim one proves the others.
Samuel can create the unused tester now without signing it in. Ask for current ASC
settings only when needed; do not block useful diagnostic preparation on them.
Eight-minute independent reviews resume for this bounded preparation, stopping
when it is ready for Samuel's device actions or another concrete input is needed.

**Subsequent disposition: revision 3 desk review accepted, live gates OPEN.**
Claude applied the six corrections and a final consistency pass: external purchases
may lack tokens (not all do); summary tables no longer contradict caching and client
risk corrections; the device proposal acknowledges an instrumented same-bundle update;
an existing installation cannot close fresh-install evidence; raw appTransactionID
must stay out of public logs. No live test or feature implementation is approved.
The test's private identifier transfer, exact build/signing compatibility and data
preservation checks must be made concrete for the selected device before execution.
Prefer presence-only public logging; a stable truncated digest is not anonymisation.
F1 is complete only as a desk-review/test-scoping deliverable, not as runtime evidence.
Next user input: select an appropriate test device/account and approve the bounded
instrumentation/read-only Apple check. ASC offer configuration also remains uninspected.
Scheduled reviews pause at this input boundary; no automatic F2 progression.

Reviewed `founding-500-f1-evidence-2026-09-21.md`. Useful SDK and notification
inspection, but **not yet accepted**. Documentation corrections only requested:

1. **Binding already precedes purchase.** `MembershipSelectionView.swift:324`
   refuses StoreKit without the server-issued token and passes it at line 333.
   A Founder conversion preserving that invariant cannot become unmapped merely
   because the original grant did not create a binding. Early binding is optional,
   not a newly proved requirement or a product question for Samuel. External
   purchases may lack our token even when a binding exists. Distinguish these cases.
2. **Notification delivery is positive evidence, not complete coverage.** The
   unestablished row observation is valid, and attribution is missing as stored;
   delayed, failed or absent notifications cannot prove no purchase. An additive
   user column is one candidate, not an accepted sufficient protocol. Preserve
   canonical live authority and the separate F3 review.
3. **Schema optionality is not destructive authority.** A matching bundleId plus
   missing data does not prove a complete absence of subscriptions. The proposed
   'authority obtained → may proceed' row is premature. Missing/ambiguous data
   must block destruction until the actual absence contract and coverage are proved.
4. **An async throwing getter does not disprove caching.** It proves callers must
   await and handle errors. Likewise cold launch/reinstall alone does not measure
   cache-versus-network use. Narrow both claims to what is actually observed.
5. **Do not call reinstall destructive of nothing.** Études is local-first;
   deleting its app can remove journal data. Remove reinstall from the initial
   session. Any later test needs an explicitly disposable installation and separate
   approval. A probe outside the source folder also needs a concrete hosting/signing
   arrangement: a different bundle does not establish Études AppTransaction behaviour.
   Sandbox findings must not be scored as Production admission evidence.
6. **A trivial SDK shim does not remove client risk.** Product/account binding,
   option attachment, freshness, error handling and signed-option preparation remain
   client integration responsibilities. Correct 'risk entirely server-side'. Keep
   invalid/expired-signature behaviour unmeasured and avoid duplicative encoding
   claims beyond passing compact JWS to the documented API.

Resolve these before escalating questions. Skip the optional simulator probe unless
it answers a necessary gate; do not ask Samuel to adjudicate internal schema choices.
No product, deployment, commit or push authority has changed.

Initial local HEAD: `15af5c9beb852c0d7638141cc97ed0a4836aeab2`, on
`feature/solo-connected`. A fresh read-only `git ls-remote` returned that exact
remote branch value, independently confirming the push; the handover's older
`1a4c09f` checkpoint is superseded. Protected document changes were present.
While this review was running, another session committed the nine historical
review/handover documents at `f758a84`. That commit contains no product changes.
Codex did not create it or contact the old recorder task.

The new real Claude task is **Founding 500 membership architecture review**,
local session `9749f40a-ae52-465a-b118-497182674536`. Identified through the app
and contacted there. No substitute agent and no automation created.

## Independently established current behaviour

| Surface | Evidence and consequence |
|---|---|
| Apple membership | `20260816120000_u3_membership_schema.sql:70` requires Apple transaction/product/environment and ownership provenance. A Founder must not be inserted as a fictional purchase. |
| Effective server access | `20260915160000_scope011_verified_sandbox_entitlement.sql:29` accepts verified Production **and Sandbox** rows and preserves B-39's revoked-status exclusion. The September 15 deployment result records this as deployed; no live backend reinspection performed here. |
| Visibility | The same migration's `membership_entitled_until` feeds four cached columns. `20260901120000_u6b_binding.sql:211` propagates changes only from `membership`. A new grant source needs equivalent propagation; changing only `connected_member` leaves visibility inconsistent. |
| Client | `ConnectedMembershipStore.swift:83` is StoreKit-only. `MOTIVOApp.swift:472` explicitly sends `.notEntitled` to Solo. A Founder must survive a negative StoreKit refresh through a combined access resolver, while Apple attestation retains its Apple-only input. |
| Restore | `MembershipSelectionView.swift:387` currently treats no StoreKit entitlement as no active membership. Restore/sign-in must also recover the server grant without allocating or restarting one. |
| Profile publication | `ProfileView.swift:262` accepts owner/generation-scoped Apple attestation completions. Grant activation needs an equivalent genuine completion signal; do not fabricate Apple provenance or lose F3's initial-publication retry. Preserve lapsed-owner maintenance and A→B→A guards. |
| Cleanup selection | `20260902140000_u7c_preview_path.sql:56` selects from Apple membership rows only. A Founder without one is never selected. |
| Cleanup authority | The worker refreshes every selected Apple row (`membership_cleanup_v1/index.ts:357`), refuses any failed/ambiguous read, then asks `membership_cleanup_authorised_v1` (`:421`). Its SQL gate checks effective non-membership plus a due schedule; it relies on the caller for freshness. A due timestamp alone is never authority. |
| Explicit deletion | `delete_account_v1/index.ts:444` deletes the auth user. Existing membership/binding foreign keys cascade. A new auth UUID is not a permanent deduplication key across account deletion. |

The fresh-join evidence establishes publication after a successful purchase but
not a clean first-attempt join. The lapsed-profile evidence establishes existing
owner maintenance while expired. Neither should be broadened into blanket QA.

## Review requirements for the proposal

1. **Bounded allocation.** One explicit grant per eligible account; fixed 500
   production places; a transaction that serialises allocation and checks an
   existing award before checking exhaustion. Lost responses and concurrent
   same-account requests return the original dates. Aborted transactions consume
   no place. Deletion must not silently replenish the pool. Use server-defined
   twelve calendar months with explicit UTC/leap-day semantics, not device time.
2. **Real evidence for admission.** No trusted client `isProduction` flag.
   An Apple-signed AppTransaction is a candidate distribution-evidence source,
   not proof that the App Store account and SIWA account are the same person.
   Define verification, cross-account replay handling, beta-to-public transitions,
   and the separate approved adult-eligibility dependency.
3. **Access composition.** A valid grant OR valid Apple access, still subject to
   identity/backend and future eligibility requirements. Grant cache is reversible
   UI evidence only, account-scoped, bounded by expiry, cleared on sign-out,
   protected from late responses after identity changes. Handle expiry while the
   app remains open and restore on another device.
4. **Whole-identity quarantine.** An old due Apple schedule cannot become
   destructive the instant the Founder grant ends. Conversely, an expired grant
   cannot shorten the quarantine after later paid access ends. Compute the end
   of effective access, preserve a full ordinary quarantine, and cover renewals,
   grace, revocations, overlap, gaps and cleanup completion/rejoin.
5. **No-Apple-row is not proof of no purchase.** A successful purchase can precede
   attestation; U4 deliberately cannot establish its membership row. Before
   allowing grant-only cleanup, resolve how a newly paid but not-yet-established
   subscription prevents deletion. Define purchase/establishment versus cleanup
   ordering, including a purchase during an in-flight cleanup. A short SQL lock
   cannot protect the whole later storage-deletion sequence.
6. **Keep authority boundaries.** Separately review grant-only destruction authority;
   preserve live Apple refresh for every known Apple source and fail closed on
   ambiguity. A grant must also veto the existing Apple cleanup path. Keep the
   expiry retention matrix and local library untouched. Dry run stays nonmutating.
7. **Minimal recovery and rollout.** Stop new allocation independently of serving
   already-issued grants. Deployment rollback cannot erase the promise or restore
   an Apple-only cleanup worker that ignores grants. Support can inspect the award
   and retry reads; no arbitrary date extension or admin grant platform is needed.

## Apple offer feasibility — independently checked

There is a real supported in-app route: pass
`Product.PurchaseOption.introductoryOfferEligibility(compactJWS:)` with a
server-signed `allowIntroductoryOffer: false`. Apple's current documentation
requires the product and a customer transaction identifier; an AppTransaction ID
can serve before any in-app purchase. Signing uses the In-App Purchase key and
the feature-specific audience/nonce; it is not the existing API bearer token.
The installed Xcode StoreKit interface also exposes the method (`:1648`).

This establishes API feasibility, **not** a successful Études purchase test and
not global control over Apple-owned purchase surfaces. Scope an explicit
acceptance run and decide what the no-extra-trial promise means outside the
app. Do not create duplicate products or a second subscription group merely on
the obsolete premise that no suppression API exists. Later-member trial copy
must reflect Apple's actual eligibility and configured offer.

Sources read on 21 September 2026:

- [Apple: signed request claims](https://developer.apple.com/documentation/storekit/generating-jws-to-sign-app-store-requests)
- [Apple: introductory offer purchase option](https://developer.apple.com/documentation/storekit/product/purchaseoption/introductoryoffereligibility(compactjws:))
- [Apple: introductory offer setup](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions)
- [Apple: Get All Subscription Statuses](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses) accepts AppTransaction IDs as well as subscription transaction IDs. This is a possible aid to grant-only cleanup; no-purchase response semantics and account association still need evidence.
- [Apple: Get App Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-app-transaction-info) documents a stable app-download identifier, distinct from the Études identity.

## Proposal review status

Reviewed Claude's initial `founding-500-design-2026-09-21.md` in full. The separate
grant, combined predicates, visibility propagation and non-purchase flow are the
right direction. A bounded, row-derived grant is legitimate entitlement, not the
retired grandfather/test bypass. **Initial proposal is not ready for scope sign-off.**
The following corrections are needed; they do not require a promotions platform.

### R1 — Allocation contention is not exhaustion (§3.2)

`SKIP LOCKED` can find no row while the final place is merely locked by a transaction
that later rolls back. Returning `pool_exhausted` then sends a rightful claimant to
payment while a place remains. The same-account UNIQUE loser is also described only
as a rollback, not an idempotent successful response. Use a short serialised allocation
transaction (500 lifetime claims is tiny), or explicitly distinguish busy/retry from
durable exhaustion and re-read the winner. Do not say all counting under a lock is
incorrect. The internal RPC must receive the verified caller UUID from the Edge
Function; `auth.uid()` under the service role must not be mistaken for the user.

### R2 — The cleanup evidence gate is narrower and harder than proposed (§5.4)

Apple's current endpoint documentation **does establish AppTransaction ID support**;
that is no longer D5's open question. What remains is the no-subscription response
contract, trustworthy binding/coverage when App Store accounts change, pending
purchase/attestation, and the race between an authority check and later storage
deletion. Successful API support alone does not prove the whole design safe.
An active or ambiguous unestablished subscription must veto destruction without
turning U7 into a second ownership-establishment writer. Never treat a 404 or malformed
200 as proof of absence. Review this protocol separately before any executable cleanup
change. The additive 60-day conjunct is useful; its NULL fallback must fail closed
for a grant candidate with missing end evidence. Make mixed-source leasing and
completion explicit so two source rows cannot hand the same identity to two workers.

### R3 — The client requires actual recomputation, not just a date (§3.5 / §5.1)

A stored expiry and `Date()` comparison do not automatically wake SwiftUI at expiry.
`MOTIVOApp.handleMembershipState` currently overrides mode on a StoreKit change.
Every activation path needs the combined resolver plus an expiry event while open.
Specify identity-scoped caching, late-response suppression, sign-out, revoked/absent
status invalidation and what offline stale evidence means. Storing a date does not
guarantee accurate device time or protect against later server revocation. If two
completion producers share the F3 consumer, their sequence identifiers must not collide;
keep owner/generation checks. Restore must recover an existing grant, not allocate one.

### R4 — Adult eligibility is not satisfied by UI placement (§8)

The rescope explicitly says current access predicates have no age term and the
client-supplied band is not settled server assurance. A directly callable claim
endpoint cannot rely on the introduction screen having run. Define an unresolved
server eligibility prerequisite at claim and an access dependency for returning
Founders; release activation stays closed until the separate adult-only work provides
that contract. Preserve all existing protections meanwhile.

### R5 — Do not silently relax the no-extra-trial requirement (§6)

The proposal's automatic unsigned purchase fallback is a product change. Recommend
preparing a fresh signed option before StoreKit and stopping before payment if it
cannot be prepared; retry later without charging. If Samuel prefers fail-open discounting,
ask explicitly. A signature fetched on screen appearance can expire before the tap;
handle that case and Apple Account changes. Keep paid ownership binding mandatory.
Also remove the claim that ASC has no offer: only the local StoreKit file was inspected.
Configure offers per subscription product and show trial language only when applicable.
An external purchase must be honoured, but a particular Settings flow receiving a trial
is not a guaranteed acceptance-test outcome. Test the actual Apple result.

### R6 — Reduce and correct the product questions (§7)

- Exactly 500 and status-plus-expiry without scarcity marketing are settled; D3/D6
  are routine design choices, not new decisions for Samuel.
- A former beta user later using the public App Store build can supply Production
  evidence. Distinguish testing never consuming places from permanently excluding
  people who beta-tested; no operator exception is inherently required.
- A spent anonymous place can remain without retaining an Apple identifier. Separate
  never recycling capacity from deduplication/offer eligibility after deletion. HMAC
  is still a retained pseudonymous identifier, not automatically a legal resolution.
- An early purchase charges under Apple's purchase terms; it does not automatically
  start after the free year. Recommend conversion at expiry to avoid needless paid/free
  overlap, or ask explicitly about immediate paid overlap. Suppressing an introductory
  offer is not demonstrated to consume Apple's lifetime intro eligibility.
- Arbitrary grant revocation/admin tooling is optional new scope. Omit unless Samuel
  wants it; if retained, both client invalidation and support semantics are in scope.
- Include the omitted existing paid-subscriber choice: no retrospective grant by default;
  any early overlap or benefit for an already-paying member needs an explicit rule.

### R7 — Production proof and rollback need a real plan (§3.4 / §9)

Environment evidence is a signed historical app transaction, not proof of the current
binary or equality of App Store and SIWA identity. Pin Production for the production
pool, document cross-identity replay/first-claim limits, and minimise raw JWS retention.
Do not introduce a production environment-switch secret merely for testing. Use
isolated fixtures/staging for successful test grants; real distribution behaviour
remains an explicit verification gate. The categorical assertion that all Xcode runs
produce locally-signed AppTransactions is not established by the reviewed evidence.

Rollout must keep allocation closed until authority/cleanup/client prerequisites
are ready. After a real award, disabling new allocation must preserve existing access;
restoring an old Apple-only predicate/worker is not a safe rollback. Unverified
destructive behaviour remains disabled/fail-closed, with a named release obligation
rather than an assertion that dry-run proves deletion safety.

## Practical scope recommendation, pending reconciliation

Keep five implementation units after Samuel approves the corrected scope:

1. Resolve and demonstrate admission evidence, adult-eligibility interface, and
   cleanup/no-purchase authority; no live destructive experiment.
2. Build the private 500-place ledger and atomic claim; integrate both access and
   visibility with existing Apple membership.
3. Implement separately reviewed combined-source quarantine and cleanup, including
   purchase races, mixed-source leases and fail-closed recovery.
4. Add Founder onboarding, account-scoped access/status recovery, exact expiry,
   F3 publication, and conversion with signed trial suppression.
5. Validate isolated concurrency/lifecycle cases, real Apple/TestFlight behaviour
   appropriate to each path, rollout/rollback, then separately authorise launch
   configuration and activation. Do not consume public places in beta QA.

Only three product decision groups should normally reach Samuel: how existing beta
users and already-paying members qualify; what minimal repeat-grant identifier may
survive account deletion and for how long; and whether conversion is offered only
at expiry with the no-extra-trial rule scoped to the in-app purchase route. Technical
unknowns stay evidence gates, not invitations to relax deletion safety. Exactly 500,
twelve months per activation, free Solo, no automatic billing and ordinary lapse
retention remain requirements.

Reconciliation with Claude is pending at this revision. Automatic approval review
initially blocked transmitting R1–R7 because the message contained non-public
repository architecture and review findings. Samuel subsequently explicitly approved
sharing this review with the identified new Claude task. Delivery was verified in
that task; Claude was asked to read the current R1–R7 sections and amend its design.
The earlier Claude reconciliation addressed an earlier review revision and is not
Codex acceptance of the later proposal. No rejection workaround used.
No tests or builds run: this is a design review, not implementation validation.
