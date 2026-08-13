# Études — Working Context

iPhone app: a local-first journal for musicians, with an optional paid
"Études Connected" social layer (Supabase + StoreKit 2 + Sign in with Apple).

Working branch: `feature/solo-connected`. Audit baseline commit: `ec2f52f`.

"MOTIVO" is the legacy working title. The project file, scheme and source
directory are all named MOTIVO; the product is `Etudes.app`, display name
"Études". Renaming is not release work.

Baseline verified at migration: Debug and Release both compile clean
(0 errors). See `docs/audit-findings.md` for what the Release build surfaced.

**Current position: Phase 1 in progress.** Landed and device-verified: C-13
(purchase-path hang), C-24 (reconnect after reinstall), C-1 client half (client
expiry-deletion authority removed), C-2 (Scores survived Erase All).
Verification batch cleared: C-7, C-8, C-19. Filed along the way: C-23, C-25,
C-26, C-27, C-28, from the avatar audit C-33, C-34, C-35 and B-20 (avatar
lifecycle — deletion on erase, and replacement propagation), and C-36 from the
location audit (Solo location published on join, then clobbered). From the
2026-08-13 TestFlight run and the B-14 unit: C-42 (membership screen priced in
USD while Apple's sheet showed GBP), C-41 (vestigial `lookup_enabled` client
plumbing) and C-43 (Unfollow and Remove Follower each delete *both* directional
follow rows).

**`delete_account_v1` is deployed, and QA runs 1 and 2 have both passed.** The
rewrite (`ca00189`) plus the B-20 avatar fix (`5714c53`) carry eight findings.
D5–D9, D11 and D12 ran combined on 2026-08-11, and D13 ran separately the same
day; together they **Resolve B-1, B-3, B-19 and B-20**. D13 is the only run that
proves the avatar fix, because D12's populated `avatar_key` cannot tell the two
implementations apart.

**B-9 joined them on 2026-08-11 via D14**, the third run and the first against
the `step 3b` deploy — the sent-tombstone cleanup, committed and reviewed before
it was deployed. Its received-row path had never executed in any prior run. Three
legs, one erase, and all eight blast-radius counts matched a prediction written
down *beforehand*, which is what made the check binary rather than a reading of
the aftermath. **Three stay open** — B-4 only ever saw the positive direction,
B-12 was never executed, and B-13's D10 is deferred for want of a safe
fault-injection path.

**One lesson from D14 is worth more than the fix.** B-9's cell had justified the
tombstone cleanup as deleting "precisely the rows whose objects were just swept",
and that reasoning was wrong — rows are per-recipient and share one storage path.
The predicate it implied was right; the reason was not. Implemented from the
stated reason, the natural code would have deleted *every* soft-deleted row, and
account B happened to hold one from a third-party sender that the run would then
have destroyed. **Correct a finding's reasoning even when its proposed fix is
right**, because the reasoning is what the next person implements from.

**Filed from D13's blast-radius check: B-21, P3.** Two avatars of accounts
deleted in July were permanently orphaned in the bucket — no `auth.users` row, no
directory row, no pointer, and no policy path that could ever reach them. B-20
observed in production rather than argued from source. Both were the developer's
own earlier beta accounts, so no real user's data was involved; cleared manually
2026-08-11. The row is kept as the observed instance behind B-20.

A whole-backend read-only orphan sweep followed, on the reasoning that the old
function ran for months. **Nothing else was left exposed** — zero orphaned
`posts` (B-4's worst case never materialised), zero orphaned shares, follows,
comment views or `attachments` objects; 30 dead `connected_attachments` rows with
no surviving storage. The avatars bucket was the only place with residue, which
is exactly where the audit had no coverage. **One false positive is recorded on
B-8 as a warning:** an orphan heuristic keyed on the `users/<uid>/` path prefix
flags D5's survivor, because the prefix carries the *sender's* uid and a dead
sender is the correct state for a preserved asset. Any future cleanup must read
liveness from `connected_attachments.deleted_at`, never from the path.

`verify_jwt` is now pinned in `supabase/config.toml` — without it the CLI
defaults to `true` and a deploy would silently change the deletion path's
authorisation configuration.

**C-38 is CLOSED as Unverified — a synthetic-only artefact.** The one deliberate
attempt was run on 2026-08-11 and **did not reproduce it.** A fresh Sandbox Apple
Account on device A gave the clean first-purchase state the attempt needed
(`entitlementRead resolved=notEntitled`, confirmed from the trace rather than
from the screen). The purchase went through Apple's sandbox — verified on Apple's
own payment sheet, headed "Sandbox", not the synthetic `[Environment: Xcode]`
sheet — and **the first entitlement read after the verified transaction already
resolved `entitled`**, with `purchaseGuard isEntitled=true`. There was no stale
read at any point. The single synthetic observation stands and is not retracted;
it simply has never occurred on Apple's pipeline in four runs now. Per the agreed
stopping rule, no further hypotheses are manufactured. It reopens only on a real
observation, and QA B2 is where that would surface.

**Note the run method, because it is more useful than TestFlight for this class
of work:** the shared scheme's Run action is already Release, so clearing the
StoreKit configuration in Run → Options gives a development build on real sandbox
StoreKit with the debugger and live console attached. That is a genuine
real-StoreKit environment and it iterates in minutes rather than in TestFlight
processing time. **The Run action must stay on Release** — Debug carries
`com.samueldixon.motivo.dev`, which App Store Connect does not know, so products
return an empty array and you get C-29's signature instead of a purchase.

**The TestFlight checkpoint is DONE — 2026-08-13, build 131. C-9 is Resolved.**
Group B ran on the distribution artifact: B1, B3, B4, B5 and B6 all passed, B2
counted as a single attempt (its throttled repetitions are not runnable on
TestFlight — see the environment notes), and B7 needs a first-join account. E12
and E13 ran on the same build and carried B-5 to Resolved.

**Directory hardening is complete.** B-5 Resolved — both directory RPCs are now
authenticated-only, at the grant *and* in the body. B-2's `lookup_enabled`
premise was **withdrawn**, not deferred: there is no discovery opt-out in the
product, and gating either RPC on that column would have blanked names and
avatars for existing followers. B-18 closed as **not a defect** — its
anon-executable claim was false against the deployed grant, and its
`SECURITY DEFINER` is load-bearing in the fail-*open* direction.

**B-14 fixed as a column privilege, not a policy predicate**, because RLS cannot
pin a column to its previous value — `WITH CHECK` has no `OLD`. `authenticated`
can no longer UPDATE either participant ID. **Its normal-approval regression
check is pending by choice**, so as not to spend Device B's lapsed-member
fixture; close it opportunistically when B is next entitled.

**A genuine lapse was observed on the artifact, 2026-08-13.** C-1's client
authority removal and C-26's retention both held: Connected withdrawn, identity
kept without re-authenticating, and **nothing deleted** — verified against a
baseline recorded while still entitled, read once before the device foregrounded
and again after. C-1's *local durability* half is **not** covered by that run;
Device B had no local journal to lose.

**C-35 is RESOLVED — 2026-08-13, device-verified end to end.** A lapsed member
deleted their Connected account **without re-subscribing**: every one of eight
counts, nine residue checks and both discriminators matched a prediction
committed before the erase. It took two attempts, and the first failure is worth
more than the fix — **C-35's defect existed twice**, and the second instance was
an entitlement dependency laundered through a `UserDefaults` key
(`AppModeManager` writes the backend runtime mode from `AppMode`, which is
resolved from `isEntitled`). The deletion path had been audited for `isEntitled`,
`AppMode` and `canShowConnectedAccountManagement` and passed, because it
contained none of them **by name**. No grep could have found it; only running it
did. `delete_account_v1` was redeployed the same day (version 6) with the revised
B-1/B-3 semantics and verified byte-identical to source.

**Next: C-44 — Sign in with Apple token revocation. P1, and the largest
remaining compliance item before submission.** Account deletion currently
revokes nothing and we hold no credential that could; the register row carries
the full audit and an auth-flow trace with line numbers. **Its Apple-specific
assumptions were verified against Apple's live documentation on 2026-08-13 and
the row now carries the citations, three corrections and the open questions.**
Endpoints, ES256 client-secret construction, the five-minute single-use code and
`client_id` = bundle ID all held. **Two things did not, and both change the
build:** `/auth/revoke` refuses authorization codes outright, so the `/auth/token`
exchange is mandatory rather than an optimisation; and TN3194's manual-revocation
fallback does **not** dissolve under the store-nothing design — its trigger
merely moves to "no fresh code obtainable". **One assumption is load-bearing and
Apple does not state it:** that a *repeat* authorization for an already-authorized
user still returns a non-nil `authorizationCode`. Establish that on device before
any Edge Function is written; if it is false, the store-nothing design collapses
and TN3194's stored-refresh-token flow becomes mandatory. **Fetch Apple's docs
via `developer.apple.com/tutorials/data/documentation/….json`** — the HTML is an
SPA shell and returns no body text.

**C-45 was filed out of that verification and is also release-blocking.** Études
observes neither `credentialRevokedNotification` nor `getCredentialState`, and
Sign in with Apple is the *only* authentication mechanism — so a `.revoked` or
`.notFound` credential leaves a live Supabase session and Keychain identity with
nothing left to justify them. Built separately from C-44 (no secrets, no backend
surface), but C-44 cannot be called TN3194-compliant until it lands. Then
B-22 (historical residue, needs its own authorisation — `Mo`/`qwerty` is another
tester, treat conservatively), B-14's runtime approval check, and the cheap
investigations C-42, C-39/C-40 and C-28.

**Rig state, updated 2026-08-13 after C-44 gate (b2) — read before planning
device QA.** **Device A now holds a FRESH DISPOSABLE Connected identity**, minted
by a new Sign in with Apple during gate (b2). It is the intended fixture for the
eventual real revoke-and-delete end-to-end test and is meant to be spent. It also
carries **one live Apple refresh token that was minted and abandoned** by the
(b2) exchange — nobody holds it, and the end-to-end revoke clears it. **Device B
Release is a lapsed member still holding a live backend account** — C-35's exact
condition, and shared with the long-running Études Dev install. It was used only
for gate (a), which wrote nothing and made no network call. Do not spend it
casually and never run Erase All on it. Update this line as work lands.

**The four `APPLE_*` Supabase secrets are production infrastructure, not
instrumentation.** `APPLE_SIWA_P8_B64` (base64 of the `.p8` — base64 because a
multi-line PEM gets its newlines mangled in an env var, and the resulting
`importKey` failure looks nothing like its cause), `APPLE_SIWA_KEY_ID`,
`APPLE_TEAM_ID`, `APPLE_CLIENT_ID`. They were set for gate (b2) and deliberately
**retained** when its probe was removed, so that `revoke_apple_identity_v1` needs
no further handling of the private key. The `.p8` itself lives at
`~/.etudes-secrets/` (dir `700`, file `600`), outside the repo; `.gitignore`
already blocks `*.p8` and `*.pem`.

**Temporary instrumentation: REMOVED.** `ActivationTrace.swift` and all 15 call
sites were deleted on 2026-08-11 the moment C-38 closed, as the standing
condition required. Nothing of it ships. Removal was done by restoring the four
touched files to their pre-instrumentation state rather than by hand-editing the
call sites — no client code had landed in between, so the result is provably
identical to the tree before `402418c`, and Debug and Release both compile clean.

It earned its keep three times over: it produced the healthy activation sequence
(`docs/audit-findings.md`, "Activation path — observed behaviour"), killed two
C-38 hypotheses, re-verified C-24 on real StoreKit, and finally closed C-38
itself — the last of which no screen could have done, since the app sits in Solo
with a live entitlement whenever identity is absent, and "stayed Solo" is the
single observation both the healthy and the broken path produce.

**The `privacy: .public` lesson held.** Every line funnelled through one `emit`,
and every line was readable on device — unlike the previous effort. Reuse the
pattern if release-readable logging is ever needed again.

**One tooling correction for next time:** `log stream --device` no longer exists
on this macOS. The working retrospective route is
`sudo log collect --device-name "<device>"` followed by `log show` on the
archive. Running from Xcode is better still — `Logger` output with
`privacy: .public` appears live in the Xcode console, with no root required.

**Previous temporary instrumentation: removed.** `MembershipTrace.swift` and its
thirteen call sites were deleted once QA B2 passed on real StoreKit, as the
standing condition here required. It earned its keep — it diagnosed C-24,
produced C-1's only device evidence, and framed C-13's verification. One
lesson worth keeping: it was labelled "Release-capable by design" but only ever
read through Xcode, and on TestFlight every line arrived as `<private>`,
because `NSLog` with `%@` arguments is redacted when read from a device. If
release-readable logging is ever needed again, use `os.Logger` with
`privacy: .public`.

---

## Architectural invariants — FIXED. Do not revisit.

1. **The local journal is never deleted by any Connected or membership action.**
2. **If nobody else can see it, it does not belong on Supabase.**
3. **Reversible decisions may rely on client-side evidence. Irreversible
   decisions require authoritative server-side evidence.**
4. **Personal durability is independent of Connected membership and follows
   Apple's normal backup model.**

Settled after a four-phase client audit and a Supabase backend audit. Only
genuine new evidence contradicting one of them is grounds to reopen — not a
preference for a different design.

`docs/architecture.md` — the four data domains, plus designed-but-parked work.
`docs/audit-findings.md` — finding register (IDs C-n client, B-n backend).
`docs/qa-plan.md` — manual QA, used at each phase gate and for the RC.

---

## Product principles

These are interaction principles rather than architectural invariants.

- **Reduce ceremony between the musical impulse and the musical record.**
- **Assistance should never override explicit user intent.**
- **Live state is useful; historical state should never become guilt or performance pressure.**
- **Reflection over measurement. Continuity over productivity.**

---

## Settled decisions

- Only sessions the user explicitly shares are uploaded. Solo mode uploads
  nothing. Unsharing deletes the backend post and any storage objects no longer
  required by surviving recipient references.
- Notes and each attachment keep independent privacy controls within a shared
  session. Only explicitly included components upload.
- "Share with followers" defaults ON. This is intentional, chosen from
  TestFlight evidence that the opposite default produced empty feeds. Users
  have a persistent "Default to Private Posts" preference. Copy must describe
  this accurately rather than claiming "private by default" of Connected.
- Client StoreKit governs Études vs Connected (access only). Apple's App Store
  Server Notifications are the sole authority for membership-expiry deletion.
  Explicit user-triggered **Erase All Études Data** remains a valid
  client-initiated destructive action.
- Expiry removes Connected, not the musician. Local journal, Scores, media,
  profile name, avatar, location, instruments, activities, settings and
  preferences all survive untouched.
- **Deleting a Connected account deletes the departing member's own backend
  UGC** — their comments on others' posts, and the Connected attachments they
  sent, rows and objects, even where recipients hold live inbox references.
  **Revised 2026-08-13 on an App Review constraint, not because the earlier rule
  was wrong.** Retention was correct given the architecture as it stood; Apple's
  account-deletion guidance treats content shared with others as UGC that
  deletion must remove, and the deployed representation could not sustain the
  "that is the recipient's copy" defence — `sender_user_id` is NOT NULL with no
  FK, and the path CHECK pins the object under `users/<sender>/`. Verified
  end-to-end on Device A.
- **B-19 is untouched and is the line to hold:** content authored by somebody
  else and merely *addressed to* the departing member must survive. The comments
  predicate is scoped to `author_user_id` alone for exactly that reason.
- **Membership never gates account deletion.** Deletion authority is
  `auth.hasConnectedIdentity`, deliberately entitlement-free — a lapsed member
  must never re-subscribe to delete their account (C-35). It had to be fixed
  twice: the second gate was an entitlement dependency laundered through a
  `UserDefaults` key, invisible to a structural audit for identifiers.
- Recipient copies already adopted into local, recipient-owned storage (Scores),
  and files already downloaded to another person's device, are out of scope —
  no backend deletion can reach them. The confirmation copy says so.
- M13 (iPad) and M14 (personal iCloud sync) are deliberately deferred. Their
  absence is not a defect.

---

## Implementation phases

One phase at a time. Tight scope, green build, explicit verification, reviewed
before moving on. Six bounded, separately reviewable phases — not one rewrite.

1. **Safety** — C-13 first (purchase-path hang); safe `delete_account_v1`;
   directory + follow-policy hardening; remove client expiry-deletion
   authority; Scores erase defect; zero-dependency cleanup; cheap verification
   tests (staged-video measurement, B-6 two-account test).
2. **Durability** — restore Apple backup participation for permanent user
   data, including the reconciliation pass for already-excluded media. Keep
   excluding staging and timer scratch.
3. **Membership authority** — server-side entitlement state; App Store Server
   Notifications; Billing Grace; replay protection; idempotent processing.
4. **Shared-only architecture** — shared-only uploads; remove the accidental
   analytics mirror; purge historic unshared rows; align onboarding, settings
   and App Store privacy disclosures.
5. **Remaining client fixes** — duplicate Score adoption; staged-video work if
   measurement justifies it; playback rate (AttachmentViewerView only, local
   and remote audio/video, discrete 50/75/100%, pitch preserved, no looping,
   no PracticeTimerView changes, no MediaTrimView carry-over, TestFlight soak);
   accessibility and polish.
6. **Cleanup** — obsolete backend code, AVFoundation deprecation sweep,
   architectural leftovers.

Verification gate after each phase. RC QA confirms an already-tested system.

---

## Per-phase working rules

- Restate the agreed scope before proposing any implementation.
- Keep changes strictly within that scope.
- Preserve existing architecture. Prefer subtraction over new abstractions.
- Surface assumptions before making changes; never fill gaps with invented
  behaviour.
- Finish with clear verification steps.
- Verify before asserting. Several audit findings were wrong because behaviour
  was inferred from names and structure rather than checked.

---

## Environment

- iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), deployment target iOS 18.5.
- Flat source layout via `fileSystemSynchronizedGroups` — everything in
  `MOTIVO/` is auto-included in the app target.
- Debug and Release use different bundle IDs, and **only Release can transact.**
  Debug is `com.samueldixon.motivo.dev`, which App Store Connect does not know,
  so `Product.products(for:)` returns an empty array and you get C-29's
  signature — "Membership options are unavailable", no error beneath it —
  instead of a purchase. The shared scheme's Run action is Release. Keep it
  there.
- **The shared scheme no longer pins a StoreKit configuration** (changed
  2026-08-11). Running from Xcode now gets **real StoreKit against Apple's
  sandbox by default**, which is the inverse of the setting that masked C-9,
  C-29, C-30 and C-38. `Etudes.storekit` is retained but **opt-in only**: attach
  it in Run → Options when synthetic behaviour is deliberately wanted, and
  detach it afterwards. A pinned configuration applies **regardless of build
  configuration**, so it silences real StoreKit in Release too — which is
  exactly how a Release QA pass was once mistaken for real-StoreKit evidence.
- **Preferred StoreKit testing loop**, documented in full in `docs/qa-plan.md`:
  Xcode + Release + StoreKit Configuration **None** + a dedicated Sandbox Apple
  Account. **It is not cheaply repeatable — corrected 2026-08-12.** This line
  used to claim that clearing the tester's purchase history in App Store Connect
  restores a first-purchase state "without creating a new account and without
  waiting for a subscription to lapse". **That was written from expectation and
  is false.** Observed on Device B: history cleared, >10 minutes waited, app
  force-quit and relaunched, tester signed out and in, device restarted — and
  the subscription stayed live, with Apple's own Manage Membership sheet showing
  it active and renewing. **Two Apple surfaces disagreed** — Settings → Sandbox
  Apple Account → Subscriptions simultaneously read "You do not have any
  subscriptions". That disagreement is the observation; **where the retained
  entitlement state lives is unknown and is not needed for any current work.**
  **A clean first-purchase state needs a new sandbox
  tester or a waited-out period**, so design runs to need one purchase rather
  than several. Note the one clean run on record, C-38's, used a *fresh* tester
  — clearing has never been observed to work.
- **To *observe* a lapse rather than re-purchase, cancel the subscription.**
  Access runs to the period end, so cancelling converts an open-ended run of
  daily TestFlight renewals into an expiry on a known date. That is the tool for
  C-1 / C-26 lapse testing. Device-side sandbox controls also include **Test
  Interrupted Purchases**, which is Apple's own way to produce the contended
  purchase state C-13's hazard needs — better than throttling. See
  `docs/qa-plan.md` step 4.
- **The two sandboxes keep different time.** Development sandbox (run from
  Xcode) honours the tester's accelerated renewal rate, so a Monthly cycle
  completes in about 30 minutes. **TestFlight ignores that rate entirely** —
  Apple documents daily renewal, up to six times in one week, so a TestFlight
  entitlement lasts roughly six days and cannot be reset on demand. That is why
  Device B read "Renews 13 August" on a tester configured for five minutes;
  nothing was misconfigured. Runs needing repeated first purchases belong in the
  development sandbox.
- **TestFlight is still a required checkpoint before StoreKit work is settled.**
  The sandbox loop proves the purchase path; it does not prove the artifact beta
  testers actually install. Cut a build at the next clean checkpoint and run QA
  Group B against it.
- 193 `#if DEBUG` blocks. Always verify Release as well as Debug.
- Unit test suite is an empty template. "Green build" means compile-clean, not
  test-verified.
- Build: `xcodebuild -project MOTIVO.xcodeproj -scheme MOTIVO -configuration
  {Debug|Release} -destination 'generic/platform=iOS Simulator' build`
