# Release checklist

The only task list. Tick items off here; put the reasoning in commit messages.
Owner is **S** (Samuel), **A** (agent) or both. Started 2026-09-22.

## A. Decisions (Samuel)

- [ ] **S — Online safety paperwork.** Drafted 2026-09-23 (Desktop): risk
  assessment v2, online safety policy, Terms of Use, privacy policy, and the
  legitimate-interests assessment. Remaining: send the solicitor pack; confirm
  the risk ratings; approve and date each document; **register SD Songs
  Limited on the NCA's CSEA Industry Reporting Portal**. Done: takedown and
  suspension tests passed, and the support auto-reply is live (both
  2026-09-23; commands in `supabase/README.md`).
- [x] **S — Adult-access decision: risk-based approach (option 3), decided
  2026-10-15, watching for Apple's UK measures (option 2).** Simkins advice
  (2026-10-15): Apple's Declared Age Range, including "confirmed", is helpful
  evidence but not a sufficiently certain basis to conclude children can't
  access Connected (no visibility of the method used; UK not among Apple's
  enhanced-verification regions; Ofcom's Aylo/Pornhub investigation shows
  responsibility stays with the provider). Options: (1) a recognised highly
  effective age-assurance provider; (2) wait for Apple in the UK; (3) proceed
  on Apple's signal, with enforcement risk "materially lower" for a service
  like Connected. Chosen 3, because Connected isn't broadcasting: members are
  seen only by people they approve and see only those they follow. Revisit if
  Apple extends its measures to the UK, Connected grows, or Ofcom guidance
  changes. Solo confirmed outside the OSA. Fee at the upper end, so any
  further call or question is charged by time.
  **Follow-up advice 2026-10-16** (on the Apple UK age-confirmation update;
  not charged): Apple's guidance now confirms age confirmation applies to UK
  accounts (credit card, ID, in some cases account information), which
  removes their earlier concern that the UK wasn't covered. Accepting only
  Apple-`confirmed` adults and sending everyone else to Solo **materially
  strengthens** the risk-based approach; they put the risk as **extremely
  low**. They still won't call `confirmed` highly effective age assurance:
  per Ofcom's Pornhub investigation, the provider must satisfy itself through
  due diligence and testing. That evidence so far: the 2026-10-16 device QA
  (`docs/qa-plan.md` Group AG), C-113 and Apple Feedback FB25211228.
  Added to both assessment drafts on 2026-10-16 (backups
  `.before-followup-advice.docx.bak`): the advice and the testing in the
  children's access assessment (Stage 1 and Method), and in the risk
  assessment's "Age position", whose stale "development build" paragraph now
  says the gate is built.
  **Earlier record:** solicitor engaged 2026-10-07. Scope
  accepted: short email answers on (1) age assurance, (2) whether Solo is
  outside the OSA, and (4) the privacy policy and terms **for OSA compliance
  only**, plus practical steps to comply if Apple's Declared Age Range isn't
  sufficient. Fee estimate £1,000–£2,000 + VAT; asked them to confirm no more
  than £2,000 + VAT without approval, and for a separate estimate for a UK
  data-protection and consumer-rights review of the policy and terms (to
  decide after the Scope findings). Q3 (risk ratings), Q5 and Q6 not
  instructed. Apple's two support replies and documentation findings were
  sent with the acceptance. Fee cap of £2,000 + VAT without written approval
  confirmed. Onboarding: ID, proof of address, two confirmations (beneficial
  owner per Companies House, checked 2026-10-07; not a PEP), signed
  engagement letter and £1,000 + VAT on account. Advice expected early to mid
  the week after onboarding completes. **Engagement letter received
  2026-10-08** (Simkins LLP; Stephen Cartwright, supervised by Helena
  Franklin; client partner Euan Lawson): scope as agreed, fees £1,000–£2,000
  with the £2,000 + VAT cap in writing (fees only; small charges such as the
  AML check are extra), £1,200 on account. Liability limited to £3m and 3
  years (standard). Confirm their bank details by phone before paying.
  **Data-protection and consumer review of the policy and terms: deferred.**
  The red-flag review (no redrafting) was quoted at £2,500–£3,000 + VAT,
  excluding follow-ups. Samuel doesn't want that spend at this stage; revisit
  after the OSA findings, or after launch revenue. Meanwhile, cross-check the
  privacy policy against the ICO's free privacy notice generator.
  Connected launches 18+ only (settled). The question: is Apple's
  Declared Age Range (including the confirmed adult signal on iOS 26.5)
  adequate to conclude children cannot access Connected? If not, what is the
  minimum that is? Take the risk assessment
  (`Etudes-Ofcom-Risk-Assessment-v2-DRAFT-2026-09-23.docx`), not the old 13+
  legal packet. An "18+" line in the terms does not by itself settle it.
  **Apple asked directly** (Developer Support case 102970072468): what an 18+
  result establishes, self-declared versus checked, `checkedByOtherMethod`,
  accuracy evidence, server verification, and whether results change. The
  reply only pointed to the App Store age rating, so none of it is answered
  yet. Next: ask for escalation to Developer Technical Support, or post on
  the Developer Forums. Tell the lawyer either way. **Apple's docs answer part
  of it** (AgeRangeDeclaration, checked 2026-09-26): current values are
  `selfDeclared`, `guardianDeclared` and `confirmed` ("a scrutinized method,
  like a credit card or government ID"). The granular `paymentChecked`,
  `governmentIDChecked` and `checkedByOtherMethod` ("unspecified method") are
  deprecated. So the app can tell self-declared from confirmed, but not which
  check was used. The forums (~90 threads) have no Apple-engineer answers.
  Sharpest question for the lawyer: is accepting only `confirmed` 18+ (which
  would need iOS 26.5 for joining Connected) adequate? **Apple's second reply
  (2026-09-29):** confirms bracket plus "how set" metadata, and says higher
  checks (credit card, ID) are routed in regulated regions (Utah, Texas,
  Louisiana, Brazil, Australia, Singapore). The **UK isn't listed**, so many UK
  adults may only ever be `selfDeclared`, and "`confirmed` only" could exclude
  them. No mention of accuracy evidence, server verification or later
  changes. If the lawyer leans towards "`confirmed` only", measure how often
  UK accounts come back `confirmed` with a temporary beta readout first.
  Apple's overview adds: the data is user-declared and "may be" confirmed;
  "You are solely responsible for ensuring compliance"; the system may
  override age gates by region; and the result is on-device only, with no
  server-verifiable form, so the server must trust the app's report.
- [ ] **S — Fallback.** If the legal answer stalls, would you ship Solo first and
  add Connected in an update? (Solo has no user-to-user content.)
- [x] **S — Pricing: decided 2026-10-09.** Études is a **paid download at
  £4.99** (pay once for what runs on the device; subscribe for what runs on
  the servers). Connected stays a subscription, and only works if you own the
  app, which a paid download guarantees with no code. Founding 500 is
  unchanged. App upgrades (iPad, Pencil sketching) are included for owners,
  but launch marketing doesn't mention them (decided 2026-10-09): announce it
  when an upgrade ships, and never say "free forever". No
  "first N downloads free": give promo codes deliberately instead (beta
  testers, teachers, a few reviewers). Fallback if paid downloads look weak:
  free download, trial, then a one-time unlock (£6.99 considered), which is a
  normal update. Listing copy never names other apps.
- [x] **S — Aggregate storage abuse (B-46): decided 2026-09-25.** No
  per-member quota at launch. Keep the spend cap on, and check usage weekly
  after launch (query in `supabase/README.md`, downloads in the dashboard).
  Build an enforced quota only if usage shows a need.
- [x] **S — Sharing withdrawal guarantee: accepted as a known limitation**
  (2026-09-23). Not a product promise. In rare cases a share that reaches the
  server after a withdrawal can bring a post back for followers. The owner's
  own feed keeps showing it as unshared, so they wouldn't notice. Any later
  save with Share off sends a fresh withdrawal and removes it. S1-Y/S1-Z are
  not built. Background: `docs/history/phase-6-sharing-repairs-scope-2026-09-22.md`.
- [x] **S — C-97 / C-99 accepted as known limitations** (2026-09-23). C-97: rare
  wrong or missing audio in video if an external mic drops or iOS resets
  audio mid-take (interruption handling itself is fixed and device-tested).
  C-99: a very fast burst of attachments could in theory lose track of one
  before saving. Revisit only if seen in testing.

## B. Build (agent)

- [x] **A — Guideline 1.2, all four parts, proportionate.** Built 2026-09-22 (`MOTIVO/Moderation.swift`). Device QA passed 2026-09-23 on Release installs A + B (report, both filters, block, offline block/retry, unblock). Badge fix `8cbcd8e` device-checked. Support mailbox set up and receiving. See
  [Apple Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
  - Filtering: a small objectionable-word filter on posts and comments.
  - Report: an action on posts, comments and profiles. Reports open a
    prefilled email to support.
  - Block (on this device): removes the follow in both directions, then hides
    the person's requests, comments, posts and sends.
  - Published contact details: a support email in the app and on the web.
  - Process (S): act on reports promptly (App Review usually expects about 24
    hours; check the current wording). Hide content or suspend accounts from
    the Supabase dashboard. No moderation tooling.
  - Contact: reports and Contact Support go to `support@etudes.app` (set up
    and receiving, 2026-09-23).
  - Check whether App Review expects users to accept terms that forbid
    objectionable content. If so, add a one-time acceptance on joining Connected.
- [ ] **A — Adult-only gate for Connected** on Apple's Declared Age Range
  (risk-based approach), replacing the 13–17 pathway. Refuse anything under 18
  and fail closed to Solo; never gate account deletion. **Decided 2026-10-15:
  accept only `confirmed` adults.** Most UK adults pass automatically (account
  age or a credit card on file); anyone else is told how to confirm ("Confirm
  you're 18+ in Settings → [your name] → Personal Information → Age
  Confirmation, then try again"). `.confirmed` needs iOS 26.5, so devices on
  26.4 get "update iOS to join Connected". Solo is unaffected. Self-declared or
  guardian-declared 18+ is refused.
  **Must also keep an anonymous count of joins refused as under 18** (a
  number only, no user id). It's the evidence the children's access
  assessment relies on at its reviews. It needs a small server-side counter,
  so it gets a single round of Codex review.
  **Progress 2026-10-15.** Client built (not device-tested): the pure rule
  (`ConnectedAgeGate`), Connected mode gated on a confirmed adult on this
  device, re-checked at launch, foreground and sign-in for Connected
  identities only, join refusal and Profile's paused notice with Try Again,
  and the 13–17 client code removed. Server **applied to production
  2026-10-15** with Samuel's approval, after local rehearsal and one Codex
  round (one finding, fixed: rollback locks the counter first): the
  anonymous `connected_age_refusals` counter (month, reason, count; an
  indicator, not an audited figure) and `account_privacy_upsert_v1` limited
  to `band_18_plus`. Read back: final row as expected, anon can't read the
  table, counter empty, 2 privacy rows, 0 teen rows. Apply/rollback in
  `supabase/sql/2026-10-15-adult-gate-*`. The app counts refused join
  attempts anonymously (public anon key only; launch re-checks not counted).
  The count is an **indicator, not an audited figure** (attempts, not people;
  inflatable). Privacy: the policy draft's "Age" row is replaced (2026-10-15,
  backup `.before-adult-gate.docx.bak`); label recommendations are in
  `docs/app-store-privacy-disclosures.md` §8 (S to decide). Accepted limits: C-112.
  **Device QA 2026-10-16** (`docs/qa-plan.md`, Group AG result): refusal
  and count pass on Device A; Device B (confirmed) passes after a re-check
  loop fix (`927c336`); sandbox age fixtures were ignored, so the under-18
  and paused rows rest on unit tests. **Found C-113**: after confirming,
  Apple kept returning the old self-declared answer, so the copy now asks
  people to confirm before Continue and the refusal points to Support
  (`ffd3b87`). Apple Feedback **FB25211228** filed. Left: retry Device A
  on a later day, remove the diagnostic log (`a5f881d`). 15 test refusals are in the
  production count (October 2026, incl. the 2026-10-18 retry, which was
  still stale).
- [ ] **S — Approve the children's access assessment.** Drafted 2026-10-15
  (`ETUDES legal documents/Etudes-Childrens-Access-Assessment-DRAFT-2026-10-15.docx`),
  following Ofcom's April 2025 guidance and record template. Stage 1: yes
  (no highly effective age assurance). Stage 2: child user condition **not
  met**, a reasoned judgement under the risk-based approach (paid app plus
  subscription, adult positioning, Apple 18+ gate, approval-only design, no
  browsable content, no evidence of child users), acknowledging that music
  appeals to children and pre-launch evidence is thin. Must be completed
  within three months of launch. **Early review three months after launch**
  using the refused-join count and support reports, then at least annually.
  Triggers include Apple extending enhanced verification to the UK (which
  could make Stage 1 "no"). If the conclusion ever becomes "met", the
  children's risk assessment and safety duties apply, and opening Connected
  to 13+ with the existing teen protections becomes worth considering.
- [ ] **S — Recurring: watch Apple's UK age confirmation.** **Finding
  2026-10-15:** Apple has asked UK users to confirm they're 18+ since iOS 26.4
  (March 2026; Ofcom welcomed it), a fact both Apple Support and the
  solicitors' advice missed. Methods (support.apple.com/en-gb/125662): how
  long you've had an Apple Account, a credit card on file or added (not
  debit), or a passport/driving licence/ID scan. Unconfirmed users keep child
  safety settings and can't download 18+ apps. Samuel's account shows
  "Confirmed 18+" by account age. It supports the risk-based approach but
  isn't highly effective: account age isn't on Ofcom's list, and apps can't
  see which method was used. Recorded in both assessments. Not sent to the
  solicitors; decide after the readout test, and if sent, cap the reply
  (e.g. within £300 + VAT). Check every month or two for changes, such as
  Apple dropping account age or telling apps the method.
- [x] **A + S — Age readout test, done 2026-10-15.** On Device B (iOS 27,
  build 1789 · 631257e), Samuel's UK account ("Confirmed 18+", by account age)
  returned **"Range: 18 to none · Set by: confirmed"**. So Apple's UK
  confirmation, even account-age-based, reaches apps as `.confirmed`. The
  readout was removed as a verified pure deletion (app source identical to
  `631257e^`).
- [x] **A — Documents updated for the legal advice** (2026-10-15; previous
  versions kept as `.before-advice.docx.bak` in "ETUDES legal documents").
  Terms: proactive-technology disclosure (s.10(7)), the complaint categories
  (s.21) and the right to claim for breach of contract (s.72). Privacy policy:
  a child-friendly Solo section (ICO Children's Code). Risk assessment: the
  decision recorded, child users "Possible", grooming Medium (adds no
  measures), and a children's access assessment to do.
- [x] **A — Align the server upload limit to 50 MiB (B-45).** Decided
  2026-09-24: 50 MiB per file at launch. Oversized files can't be published
  (trim, replace or keep private); no automatic video compression in v1. Set
  the `attachments` bucket's `file_size_limit` from 150 MiB to 52428800, as a
  migration plus a guarded production statement. Production database change,
  so one Codex review round. Prepared and rehearsed locally 2026-09-24:
  `supabase/migrations/20260924120000_b45_attachments_upload_limit.sql`, apply
  and rollback in `supabase/sql/2026-09-24-b45-upload-limit-*-production.sql`,
  check `supabase/tests/b45/check-upload-limit.sh` (50 MiB accepted, 50 MiB + 1
  refused, guards hold; cleanup restores the bucket even if the check fails).
  Codex review 2026-09-25: no objection, subject to the project-wide limit
  (section C, Pro upgrade). **Applied to production 2026-09-25** with
  Samuel's go-ahead; read back `attachments` = 52428800, still private, 14
  MIME types, 16 objects, `avatars` unchanged.
- [x] **A — R1-a:** don't acknowledge an unsent simulated withdrawal
  (`SessionSyncQueue.swift`, client-only, small). Cheap insurance, not a
  blocker. Done 2026-10-18: held instead (C-115).
- [x] **A — Real build numbers.** A "Stamp Build Number" script sets the build
  number to the git commit count and records the short hash. Both show at the
  foot of the Profile page, e.g. `Version 1.0 (1747 · abc1234)`. When uploading,
  leave Xcode's "Manage Version and Build Number" option unticked so the number
  stays tied to the commit.
- [x] **A — Privacy Policy and Terms of Use links in the app** (Apple 5.1.1,
  3.1.2): Profile's Account card and the membership screen, pointing at
  `etudes.app/privacy` and `etudes.app/terms`. Device-checked 2026-09-23. They
  work once those pages are live. Also add both URLs in App Store Connect.
- [x] **A — Code coverage in Release.** Not an issue: an Archive has no coverage
  instrumentation. Only plain `xcodebuild build` runs added it.
- [ ] **A — Any copy changes** from the legal decision and the 1.2 work (About,
  Explore Connected, refusal text).
- [x] **A — "Tell someone about Études" share button** (decided 2026-10-09,
  built 2026-10-18). "Tell Someone About Études" in both Profile Account
  cards opens the share sheet with the App Store link
  (`LegalLinks.appStore`) and Samuel's wording; Connected members also see
  that they're found by name only if "Let other members find you" is on. No
  contacts, no backend. The Connected introduction now says you can send a
  link from Profile, not "invite". The "sketch" line in About was already
  gone. Checked in the simulator; not yet on a device. Private invitations
  stay post-launch (section E).
- [x] **A — Save spontaneous recordings as a thought** (scoped 2026-10-11,
  built 2026-10-11, **not device-verified**). Part A: idle shows **Start
  Timer** alone; running and paused carry one **Reset**, whose card offers
  "Reset timer" (time only, draft kept) or "Reset and discard draft" (the old
  confirmed whole-draft discard, named truthfully) when attachments are
  staged; with none, Reset just resets. Never a second control on the timer
  row (Samuel, 2026-10-11). One shared "started since reset" check (a persisted start
  marker plus running/elapsed evidence) drives the "+" actions, Save thought
  and the timer card, so a pause under one second no longer looks idle. Part
  B: with media staged and no practice started, a **Save Thought** button opens
  the thought editor with the media carried in (copy; originals kept); after
  the durable local save the timer consumes exactly the committed ids, inside
  the editor's finalisation and independent of the sharing alert. The button
  is text only, slate blue-grey, last on the page beneath the attachments
  card. Also fixed
  on the way: the editor's thumbnail flag for a newly staged photo, trimmed
  video declared as MOV after a trim in the editor, and id-keyed titles for
  audio/video saved through the editor (C-108 to C-110). Known boundary:
  the Core Data save and the staging consumption are not one step (C-111).
  **Refinements 2026-10-11 (not device-verified):** in Thought mode the
  editor orders Attachments → Thread → Time → Notes when media came in from
  the timer (a written thought keeps Thread → Time → Notes with the attachment
  controls after), sharing after Notes, and the one save action is in the
  toolbar. A thought made from the timer (Save Thought or Add thought) closes
  back to the timer with a quiet "Thought saved · View" notice; View opens
  the entry in the existing detail view. Other editor entry points keep their
  navigation. In the journal, a thought with no written heading takes a
  member-given recording title as its heading; a generated name is not one,
  and an unnamed thought has no heading. The month card then carries one
  quiet kind indicator on its date line (with a count when there are
  several); the week card keeps its date, preview and favourite control
  (`ThoughtMediaSummary.swift`).
  **Onboarding for capture (2026-10-11):** first launch no longer opens the
  "+" panel; one-word captions (Audio, Photo, Video) sit under the recorders
  until each is used once; About now leads with capture and Save Thought,
  explains Start Timer, Finish and Add session, and no longer says "sketch";
  Profile's navigation rows are tappable across their full width; the
  unreachable Voice Memos
  and Camera help sheets are removed.
  Tests: `SaveThoughtHandoffTests`, `C84SessionPreservationTests` (updated);
  also corrected the `P6I01SaveOrderingTests` pin that C-107 had left stale.
  Simulator smoke check passed 2026-10-11 (iPhone 17 Pro, iOS 26.5, Debug,
  fresh install): record → Save thought → journal with "Thought saved";
  clip consumed and stays gone after relaunch; second clip saves as another
  thought; Start → Reset timer (confirmed) keeps the clip and shows Save
  thought again. Device QA still to do (Device B, Études Dev, test data only): the
  verification list in the scope — clips → Save thought (audio, video, mixed,
  rename, trim, subset, cancel/relaunch), Start → Reset timer while running,
  paused and within one second, Discard draft before and after Start, the
  largest supported video, VoiceOver, large text and Reduce Motion.
- [ ] **A — "Show streaks and totals" switch** (decided 2026-10-09; optional
  for launch). One switch in Profile → Settings, **default on** (today's
  behaviour unchanged). Off hides the Journal summary's total and "n-day
  streak" (`ContentView.swift`, `summaryBodyContent`) and the timer's
  "This week • …" line (`PracticeTimerView.swift`, `temporalSummaryLine`).
  Me keeps all its stats. Same window as the share button. Copy may mention
  it only once it ships.

- [ ] **A — iPhone Duo compatibility before launch** (decided 2026-10-11).
  iPhone Duo (Apple's foldable) goes on sale 23 October 2026 on iOS 27.1.
  Apps built with the iOS 26 SDK sit centred with empty space on its inner
  display; from April 2027 every submission must use the iOS 27 SDK and
  include iPhone Duo screenshots. So switch the launch build to Xcode 27.1
  (iOS 27.1 SDK; Duo simulator in Device Hub), run Apple's "get my app ready
  for iPhone Duo" check, and fix the flagged patterns: `UIScreen.main.bounds`
  in `AddEditSessionView`, `PostRecordDetailsView` and three charts in
  `MeView`; the phone-idiom check in `MediaTrimView`; review the
  interface-orientation reads in `CameraCaptureView` and `VideoRecorderView`
  (capture rotation, probably fine). Make today's iPhone layout sit well on
  the unfolded screen (capped width, centred, nothing stretched) and check
  the vertical tab and tool bars the 27.1 SDK brings. Test folding and
  unfolding with the timer running and during a recording. This is iPhone
  compatibility, not iPad work; the iPad adaptation (section E, under
  consideration) would share it. Apple: [prepare](https://developer.apple.com/iphone-duo/prepare/),
  [submission news, 5 Oct 2026](https://developer.apple.com/news/?id=kkphp5qo).
  **Progress 2026-10-18:** the flagged patterns are fixed without Xcode 27.1:
  sizing now follows the app's window (`WindowMetrics`), not the screen, and
  `MediaTrimView` uses the compact height size class instead of the device
  kind. The capture orientation reads only set recording rotation, so they
  stay. On iPhone the window is the screen (checked on the simulator by
  `WindowMetricsTests`), so the iPhone layout is unchanged. **Left:** install
  Xcode 27.1 (beta since 18 September; Samuel downloads it), build with the
  27.1 SDK, run Apple's Duo check and the Duo simulator, then the unfolded
  layout and fold/unfold tests above.
- [x] **A + S — iOS 27 compatibility check** (iOS 27 public 2026-09-26).
  S: update one test device to iOS 27 and run the practice tools, a
  recording, playback, and a Connected purchase and sign-in on the current
  TestFlight build. A: trial build with Xcode 27 (Debug, Release, Archive,
  unit tests) without switching the project over. **A done 2026-09-26, clean:**
  Xcode 27.0 (needs macOS 26.6) builds Debug and Release with no new warnings
  (42 vs 44 on 26.6); the Archive succeeds and is correctly stamped; unit tests
  on the iOS 27.0 simulator: 1,090 passed, 0 failed, 49 skipped (46 need the
  local Supabase stack, 3 are timing-dependent by design). **S partly done
  2026-09-26:** on Device B, iOS 27: all recorders, practice tools, playback,
  and Connected sign-in and purchase work. **Complete.** Needs Xcode 27 installed
  alongside Xcode 26.6 as `Xcode-27.app`, not over it. Keep shipping
  TestFlight builds with Xcode 26.6 until the trial is clean. Minimum stays
  iOS 26.4.

## C. Configuration (Samuel, in App Store Connect / Supabase / web)

- [ ] **Private sync on the shipping configuration**
  (`docs/sync-trial/production-configuration.md`). Done 2026-11-10: the App
  ID's iCloud/CloudKit (only the new container `iCloud.com.sdsongs.etudes`)
  and Push capabilities; the CloudKit schema exported from the trial
  container, corrected (three fields, C-184) and deployed to Production.
  The Release preflight passed and build 1908 (`9dd52ff`) went to
  TestFlight as Internal Only on 2026-11-10 (section D's checkpoint).
  Left: **remove the test journal from Samuel's own iCloud** (the
  Production private database of his main Apple Account holds the fixture
  journal, and the Development one the preflight's) before he turns sync
  on for real; until then sync stays off in Études on Device B. The app's
  own "Remove Études Data from This Device" is **not** a route for this:
  it keeps the iCloud copy by design (C-181), as do turning sync off and
  deleting the app. The targets, the two routes that do delete the zone
  and the safeguards are proposed in `personal-icloud-cleanup-proposal.md`
  (session notes folder, beside the checkpoint script); nothing has been
  cleaned up. Widening distribution waits for review.

- [x] Founding 500 introductory offer: free first year on both products, no end
  date (seen in ASC 2026-09-21). Remove manually at ~500.
- [ ] **App price £4.99** in App Store Connect (Pricing and Availability),
  set before submission. Check the Paid Apps agreement, tax and banking are
  active.
- [ ] **Promo codes** for beta testers, teachers and a few reviewers at
  launch (check ASC for current limits).
- [ ] **Re-read the terms, privacy policy, App Store description and
  `etudes.app` for "Solo is free"** wording now that the app is paid. (The
  app's own copy only says "free" about the Connected trial; checked
  2026-10-09.)
- [ ] Production App Store Server Notifications URL. Keep Sandbox as it is.
- [ ] Production Billing Grace (C-31).
- [ ] Privacy policy published at `etudes.app/privacy`. Drafted 2026-09-23
  (Desktop). Its backup line ("up to 7 days") is true on Free and Pro. Before
  publishing: approve the age row (replaced 2026-10-15 for the built gate;
  see `docs/app-store-privacy-disclosures.md` §8), add
  the date, then publish. The internal legitimate-interests assessment (LIA)
  for the safety, age-check and support uses was drafted 2026-09-23 (Desktop).
  Approve it alongside the policy.
- [ ] **Supabase: Free through beta, Pro at launch** (decided 2026-09-23). Free
  has no backups, 1 GB file storage, 5 GB/month downloads, and pauses after a
  week of inactivity, so open the app now and then during beta. Upgrade to Pro
  (about $25/month, daily backups kept 7 days, **spend cap on**; B-46) on
  launch day. Keep the cap on until real usage and paying members justify
  turning it off.
  **At the upgrade, set Storage's project-wide upload limit to at least
  52,428,800 bytes** (B-45). Supabase applies it on top of the bucket limit,
  and Free can't go above 50 MB, which may be less than the app's 50 MiB. If
  it's lower, some files the app allows would fail to publish.
- [ ] `etudes.app/terms` published, holding your terms including the safety
  section. The app links to it, and to `/privacy`. Full Terms of Use drafted
  2026-09-23 (Desktop), including the safety section and relying on Apple's
  standard EULA for the app licence. Holding pages live at both addresses
  (checked 2026-09-23); replace them with the final text before App Review.
- [ ] **Launch-day privacy policy check:** re-read it against the launch
  build. Finalise the provisional age row for the adult-only gate, set the
  "Last updated" date, and confirm nothing else has changed. The Supabase
  upgrade to Pro needs no change (backups are worded "up to 7 days").
- [ ] **Then** publish the ASC privacy labels. Nine types are entered and saved;
  mapping in `docs/app-store-privacy-disclosures.md`. Policy first, labels
  second.
- [x] Privacy Policy URL (`https://etudes.app/privacy`) entered in App Store
  Connect, 2026-09-23 (holding page for now).
- [ ] Support URL in App Store Connect, and a Terms of Use link in the app
  description.
- [ ] Age rating set to match the legal decision.
- [ ] Supabase Data Processing Agreement accepted.
- [ ] **ICO data protection fee:** SD Songs Limited, Tier 1, £52/year. No
  exemption covers running Connected, and beta test accounts already count,
  so pay now. Check the ICO register first in case the company is already
  listed.
- [ ] App Review notes. Explain follow approval (strangers can't see content),
  how to reach Connected, and the report/block locations.

## D. Final QA — TestFlight build, one run

Name the device **and** install for each step. Use a fresh Sandbox tester for
the join.

- [ ] Clean first join with the Founding 500 offer: Sign in with Apple → trial
  purchase → Connected works on the first attempt.
- [ ] Share a session, see it from the other device; unshare, and it disappears.
- [ ] Report, block, and the word filter.
- [ ] Account deletion (lapsed and active).
- [ ] Erase All on a disposable install (never Device B).
- [ ] Backup and restore on one device: journal, Scores and media survive.
- [ ] Smoke test: recording, tuner, metronome, Lists, playback speed.
- [ ] Adult-only gate: `docs/qa-plan.md` Group AG on Device A (Release,
  Sandbox Apple Account), including AG0's cache-trap probe and the refusal
  count arithmetic.
- [ ] **TestFlight checkpoint for the private sync** (script written
  2026-11-04: `testflight-checkpoint-device-script.md` in
  `~/Library/Application Support/Claude/side-session-notes/local_6d93116d-9187-4503-8840-a388a10459a9/`;
  after section C's sync item). **Run 2026-11-10 on build 1908: parts 1
  to 4 passed; part 5 is blocked and was omitted** (record under "Sync",
  C-187 to C-189). Device A (iPhone 16e) and the iPad (TestFlight, fresh),
  both on Samuel's main Apple Account, which earlier text called the
  trial account; Device B unused. Part 5 needs a Connected identity
  verified disposable, separate from the fresh Sandbox purchase tester:
  Sign in with Apple on either device is Samuel's real account
  (`0f33f6b8…`). Switching the Apple Account under the existing install
  is not enough (its journal and state are bound to the main account):
  part 5 needs a **fresh install and a fresh journal made under the
  disposable Apple Account**, the Apple identity and the exact backend
  user id verified before anything is deleted, and a second writer to
  that account's iCloud journal that is not the iPad. In this order (same
  notes folder): **first** the sustained-upload trial,
  `sustained-upload-trial-script.md`, on a build carrying the send-gate
  observation (C-190), TestFlight on Device A and the iPad — **run
  2026-11-11 on build 1912 and passed** (record under "Sync"); **then**
  part 5 — **run 2026-11-11 on build 1914: completed, with an imported
  location reaching the backend (C-192) and a typed location undone
  (C-193); both corrected the same day and the affected cases rerun on
  build 1918, and the avatar read-back corrected and checked on build
  1922 the next day; records under "Sync"** — `part5-connected-isolation-script.md`, on a
  development-signed Release build with a dedicated simulator as the
  second writer, proved to sync before anything is measured. Part 5's
  coverage is therefore the Development CloudKit environment only. Parts:
  (1) pre-flight on the production container's Development environment
  with a development-signed Release build and the fixture — enable, the
  ≈ 830 MB first upload (C-174's one-send gate under load; its root cause
  is not verified, so a recurrence is recorded, not explained away),
  relaunches, the comparator over the cable (upgraded role, 0 failures),
  Offline and Waiting-for-Wi-Fi wording; (2) the populated upgrade with
  sync off: fixture into a development-signed Release install, opened once,
  then the TestFlight build installed over it, data kept, toggle still off;
  (3) explicit enablement on Production and a second large first upload;
  (4) the iPad restoring from the set-up card with the new progress
  wording, the four entry kinds, scores, lists, profile and avatar checked,
  then edits both ways incl. a rename seen without a relaunch (C-177) and a
  deletion; (5) a Connected member with sync on: a fresh Sandbox tester
  joins on Device A, a second writer changes location and avatar by sync,
  and the backend's `account_directory` row values, the avatar object and
  the API write log are read before and after (unchanged until the person
  edits on Device A, the positive control) — the unit-only
  isolation case (`SyncTestConnectedIsolationTests`) on a device — then
  Delete Account leaves the iCloud journal and the restore card brings it
  back. The TestFlight installs turned out to be readable over the cable
  (devicectl, 2026-11-10), so parts 2 to 4 have state files and container
  copies as well as the screen.

## E. After launch / known limitations (not release work)

- Sharing: the late-commit race family (S1), retention hygiene (D2/D3), the
  wider sharing redesign.
- Supabase ticket SU-478356 (physical deletion and retention). Don't wait on it.
- G7: first real expiry cleanup, earliest 2026-11-01, happens on its own.
- Gate 6 part 3: production grant at the first real subscription.
- B-34 (shadow telemetry blind to denied writes). Observability only.
- Invitations, iPad (with Pencil markup and sketchpad, plus private iCloud sync; agreed plan in `docs/architecture.md`, "iPad and private sync"), recorder R1 diagnostics.
- **iPad before launch: under consideration, not decided (2026-10-16).** The
  option being weighed is independent iPhone and iPad versions at launch
  (markup and manuscript sketches on both, no sync, the separation disclosed
  before purchase and on first run), estimated at 9.5–13.5 agent-weeks and
  about 3½–5 months elapsed against 3–6 weeks for iPhone first. No
  implementation is authorised. Decisions already taken for the iPad work,
  whenever it happens:
  - **Preserve the existing appearance, navigation, controls and behaviour.**
    The work is spacing, sizing and adapting the layout as sections open and
    close. Lists, attachments and the audio recorder keep their buttons (tap
    to open, tap again to close). No sidebar, no new selector, no replacement
    navigation. **The Journal list/detail redesign is not approved.**
  - **Timer in landscape: workspace direction preferred**, exact arrangement
    to be worked out in the app.
  - **One page at a time:** agree its adaptations, implement, test the
    relevant window sizes and open/closed states, refine, Samuel signs off,
    then the next page. Every step keeps the iPhone experience unchanged.
    Build setting to make this safe: the app target's
    `TARGETED_DEVICE_FAMILY` is per configuration, so Debug can be `1,2`
    while pages are adapted and Release stays `1` until the last page is
    signed off.
  - **The Duo shares this work.** The unfolded Duo is the wide case and the
    folded Duo the narrow one; both are near-square or small, so size in
    points, not by device. Ink works by finger (no Pencil on Duo).
  - The Scores library and manuscript mock-ups (reviewed with Codex,
    2026-10-16) are design references, not specifications.
  - **Minimal preparation for a future merge of two journals:** a persisted
    install id; sketch and ink records carry their UUID, install id, created
    and modified dates, and (for ink) the score UUID, page and a SHA-256 of
    the PDF at first save. Merge policy, if it comes: union, de-duplicate
    only by normalised name or identical hash, **keep both** of anything
    ambiguous (two ink layers named by device and date), never infer
    deletions. No Core Data or sync work before launch.
  - **If option 2 is chosen, revise:** the "one journal from the first iPad
    release" requirement and "iPhone shows ink read-only" in
    `docs/architecture.md`; the privacy policy's "stays on the iPhone"; the
    App Store description; an iPad first-run notice; M13/M14 in `CLAUDE.md`.
- **Private sync trial, Checkpoint 1: passed 2026-10-18.** Separate "Études
  Sync Test" installs (`SyncTest` configuration, bundle id
  `com.samueldixon.motivo.synctest`, development container
  `iCloud.com.samueldixon.motivo.synctest`, code under `MOTIVO/SyncTest/`,
  `#if SYNCTEST` until the 2026-11-04 integration) on Device B and the iPad Pro 11" M4 (iPadOS 27.0.1),
  same iCloud account, no Connected. `CKSyncEngine` with Core Data
  persistent-history change tracking across every context, an outbox and
  history token written atomically together, Session and Attachment
  records, media as `CKAsset` files materialised at `Documents/<id>.<ext>`,
  attachments held until their session arrives, record-level conflict rule
  by `userModifiedAt` with the loser's text logged, journal bound to the
  iCloud user record and never deleted on account events. Model V11 adds
  preserved ids and `userModifiedAt` (lightweight). Passed: Thought and
  photo both ways, edit, offline conflict, interrupted sync with relaunch,
  deletion; 11 unit tests. **Finding: `CKSyncEngine` needs silent pushes**
  (`aps-environment` plus `remote-notification`); without them the device
  never learns the database changed. Études proper has no push capability
  yet, so shipping sync needs it. Untested: account sign-out, per-app iCloud
  off, account switch, large media, Scores/lists/profile, Connected. Still
  separate: profile name/avatar/location sync (2–3 days plus the
  `ProfileView` save-observer isolation fix).
  **Checkpoint 2, representative subset: passed 2026-10-18.** Études Dev's
  container was copied read-only from Device B (`devicectl`, file by file;
  the directory form fails), verified by `docs/sync-trial/verify_container_copy.py`
  (112 sessions, 83 attachments, 102 files, 832 MB, nothing missing), and a
  subset from 2026-07-01 built through Core Data with the app's model by
  `docs/sync-trial/make_subset.swift` (22 sessions, 24 attachments, 236 MB;
  scratch, Connected caches and backend ids stripped). Pushed into a fresh
  iPhone Sync Test install: bootstrap uploaded 46 records / 187.6 MB in
  ~20 s. Empty iPad cold-imported everything in ~70 s; counts match; media
  opens; a star toggled on the iPhone appeared on the iPad at once. Études
  Dev untouched. **Findings:** the per-attachment privacy map
  (`AttachmentPrivacy.json`) isn't synced and defaults to private, so the
  iPad's journal cards hide thumbnails and attachment counts (must move onto
  the Attachment record for shipping); the `Instrument` relationship is
  needed (an entry showed "Instrument" where the iPhone shows "Bass
  Guitar"); owner-key adoption did not fire on the iPad (records carry the
  owner; early exits now logged). The full copies live outside the repo in
  `~/Documents/Xcode projects/EtudesDev-container-copy-2026-10-18` and
  `…/EtudesDev-subset-2026-07-01`.
  **Checkpoint 2, full history: passed 2026-10-19.** The whole journal
  (112 sessions, 83 attachments, 679 MB; prepared by `make_subset.swift`
  with cutoff 2000-01-01, verified) uploaded from a fresh iPhone Sync Test
  install in ~75 s (195 records); the empty iPad imported all 195 records
  in 4 min 48 s, owner key adopted, every entry and medium opening, new
  Thoughts still crossing. **Findings:** (1) deleting records server-side
  for the reset left tombstones that a fresh engine applied to the restored
  full copy, removing 47 real entries from the trial copy (Études Dev
  unaffected); a restored backup after deletions elsewhere would lose them
  the same way, so resets delete the zone (diagnostics button) and the
  product must state that sync is not backup; (2) the engine delivers a
  cold import only after every asset in the batch has downloaded, so the
  journal is empty for ~5 min and then complete: a visible first-sync state
  is needed; (3) owner adoption had never been wired to the engine (fixed).
  **Trial complete.** Untested remains as listed: account sign-out, per-app
  iCloud off, account switch; Scores, privacy map, Instrument/Tag
  relationships, profile; Connected with sync on.
  **Stage B, identity: passed 2026-10-19.** The bound private zone is the
  journal; no new identifier. One Apple user id (K1, `Session.ownerUserID`)
  or none per journal, enforced (`JournalOwnership`): a device without a
  key adopts the journal's single owner only after its first complete fetch
  and over the whole store; a device with a key is never overwritten; mixed
  owners are kept, reported on the diagnostics screen and held back from
  upload. Upload eligibility is ownership alone, never a screen filter.
  Ownership is merged separately from content (`JournalImporter`): an
  owner-only change is not a user edit, never beats a notes edit and never
  re-sends media (both arrival orders unit-tested); `Attachment.ownerUserID`
  is not synced and follows the session. Custom instruments and activities
  sync without an owner and are stamped with the local install key
  (`local:<install>`) on import; duplicates by normalised name collapse to
  the smallest id on every device, keeping the loser's order and visibility.
  Saved Lists sync as records by id (two lists with the same name both
  survive). Stores looked up under "no owner" (Lists and list settings,
  ensembles, tint maps, saves, profile location and avatar) are copied into
  the owner scope once per owner, never overwriting, never deleting the
  source (`JournalOwnerStoreMigration`). Adoption sets the Keychain key and
  nothing else: no Connected session, publishing, directory or avatar work.
  C-114 refusal and withdrawal unchanged; the sign-in's local half is now
  `AuthManager.applyLocalSignIn`. 20 unit tests (`SyncTestIdentityTests`).
  Device run on fresh Sync Test installs with disposable data (Études and
  Études Dev untouched): two Solo journals made in Airplane Mode (2
  sessions, a photo, a saved list, a custom instrument each) converged to 4
  sessions, both lists, one instrument, media both ways, re-import without
  duplicates; an iPad notes edit against the iPhone's owner step kept the
  notes, took the owner, media bytes unchanged; the iPad adopted the owner
  with no Connected identity and all content intact; a different owner was
  refused; the withdrawal kept the key and a Thought still crossed.
  **Findings:** (1) a change of list lookup scope was sent as two deletions
  and applied on the other device — fixed (a scope change never infers
  deletion; the no-owner stores are merged on whichever launch first sees
  the key); the lists came back from the untouched "device" copies. The
  production sign-in has the same lookup move without the merge (C-116).
  (2) Clearing the owner key while the journal holds owned entries re-adopts
  it at once, by the rules; the trial reset button now suspends the rules
  first. (3) Editing the other device's session is blocked until the
  Instrument relationship syncs (`AddEditSessionView` Save needs an
  instrument object). (4) Launching in Airplane Mode needs no relaunch: the
  iCloud account check passes from the system's cache even on a fresh
  install (an assumption at the time, corrected in stage C). (5) `ProfileStore`
  hydration writes the backend id as a custom-row owner (C-117, separate).
  **Pre-shipping requirement, erase (Samuel, 2026-10-19):** removing local
  data from one device must not silently delete the private iCloud journal
  or the copies on other devices; deleting the journal everywhere needs a
  separate, explicit action; pausing sync alone must not leave local-reset
  deletions queued for when sync resumes; the implementation must define
  and test what happens when sync is re-enabled. Today `LocalFactoryReset`'s
  batch deletes would be tracked as deletions. Not a stage-B change.
  Hands-on: agent ≈ 1 h implementation and tests, ≈ 35 min device-run fixes,
  ≈ 25 min waiting on builds; Samuel ≈ 40 min at the devices, ≈ 25 min
  waiting on fixes. Reset rule: Delete server zone, Clear owner key (both
  devices), delete both apps, reinstall.
  **Stage C, session round trip: passed 2026-10-20.** (1) Profile instruments (`Instrument`, what
  `Session.instrument` points at) now sync by id and name; a session and a
  custom-instrument mirror carry their instrument link (`instrumentRef` +
  `instrumentName`). A link resolves by id, then by a recorded alias, then
  by name against this device's instruments, and only then creates the row
  under the local profile with the sender's id. Two devices that each had
  "Cello" before they met keep their own rows and an alias maps the other
  device's id (nothing deleted or re-keyed, so per-instrument list settings
  keep working); a rename reaches the aliased row; an Instrument deleted on
  the other device is removed here only when it is the same row. Instruments
  are sent before sessions. This is what lets the editor save the other
  device's sessions (`AddEditSessionView` Save needs an instrument object).
  (2) A failed first iCloud check (offline, or no iCloud account yet) is no
  longer terminal: the journal and pending work are kept, the check is
  retried on a 5/10/20/40/60 s backoff and at once when the network path is
  satisfied (`NWPathMonitor`), and a later CloudKit sign-in event starts
  the engine rather than "resuming" one that never started. Network
  unavailability is never treated as an account change; a bound-account
  mismatch still pauses and is not retried. (3) C-116 fixed in production
  (`0bc7891`, separate commit): `LocalOwnerStoreMigration` runs once per
  owner from `applyLocalSignIn`; the trial's adoption path uses the same
  code. Verified by tests: both sides holding lists merge by id with
  neither lost; the same name twice stays two lists; repeat or interruption
  neither loses nor duplicates; a scope change never produces cloud
  deletions; a list deleted after the merge is not brought back. The other
  merged stores: ensembles by id, tint entries and saves by key (union);
  per-context list settings and autofill flags are single values, so where
  both scopes set the same context the owner's value stands and the
  pre-sign-in value is left in place but not applied (reported, not
  changed). 9 unit tests (`SyncTestInstrumentSyncTests`); Debug, Release
  and SyncTest build. **Device run (Sync Test installs, disposable data,
  Études and Études Dev untouched):** the iPhone's stage-B sessions gained
  their instrument on the iPad and could be saved; a new iPhone session
  with Viola, notes and a photo opened on the iPad with the right
  instrument and photo, was edited and saved, the edit reached the iPhone,
  and a title edit went back at once; an iPad started in Airplane Mode kept
  a Thought pending and sent it on reconnect without a relaunch; a fresh
  iPad install launched offline imported all 18 records on reconnect,
  aliased both devices' "Oud" ids to its own, created "Viola", and sent its
  Thought with no media re-sent. **Findings:** (6) an edit to a session
  that had arrived by sync was sent with the notes the engine had imported
  (the long-lived import context's cached copy; the iPhone never saw the
  iPad's edit) — fixed, outgoing records and send conflicts read a fresh
  copy, unit-tested (C-118); (7) editing a session re-saves its attachments
  and each save re-sends the media file, 4 MB per edit here — a cost for
  the inventory stage (C-119); (8) an owner-only pending save meeting its
  own server copy is logged as a tie conflict with identical content —
  noise, to tidy; (9) the retry for a failed first iCloud check is
  unit-tested only: not reachable on these devices (see stage B (4)).
  Hands-on: agent ≈ 14 min items 1–3, ≈ 12 min device-run fix, ≈ 20 min
  waiting on builds; Samuel ≈ 22 min at the devices, ≈ 8 min waiting.
  **Stage D, media and conflict noise: passed 2026-10-20.** An outgoing
  attachment record carries its file only when the file is new to the
  server or its SHA-256 differs from what the server holds (`fileHash` on
  the record; `JournalAssetPolicy`; a size/mtime cache so an unchanged file
  is hashed once). A metadata edit sends the record alone and CloudKit keeps
  the asset. A replaced file arrives with a new hash and is written into
  place, the old file removed, no duplicate attachment; the creator's own
  file is otherwise never touched. Owner-only pending saves are flagged
  (`JournalSyncPendingChange.ownerOnly`), sent as a partial record (just
  the owner key), and are never a content conflict: the server's content is
  taken and the owner re-sent; a genuine concurrent edit is still reported
  with its losing text. Diagnostics now separate record counts from media:
  "Media uploads" (files set on sent records, bytes), "Attachment records
  sent, metadata only", "Media downloaded (transport)" and "Media written
  to this device". 8 unit tests (`SyncTestMediaTests`). Device run
  (disposable session, 35 MB video): initial upload 1 file / 35 MB, played
  on the iPad; title, notes and instrument edits arrived with Media uploads
  unchanged (a session edit does not touch the attachment record at all);
  a PDF added (+1 upload) and renamed arrived with uploads unchanged and
  one metadata-only attachment record; a photo added during Airplane Mode,
  once with reconnect and once with a relaunch while offline, uploaded
  exactly once each, opened on the iPad, two attachments on both devices.
  **Replacement (22:25):** the 35 MB video trimmed and replaced in place
  on the iPhone sent 4 attachment records with 1 media upload (3.8 MB, the
  clip) and 3 metadata-only; the iPad logged "Replaced media for … from the
  other device", the trimmed clip plays there, same attachment set, no
  duplicate. **Interrupted transfers (2026-10-21, 80 MB clips from Photos,
  Network Link Conditioner 3G):** (a) ~15 s of Airplane Mode after
  "willSendChanges" never surfaced to the engine — no failure event, the
  same send invocation completed 3 min 25 s after it began; whether bytes
  were resumed or re-sent beneath CloudKit is not observable from the app.
  (b) Force-quit after "willSendChanges": after relaunch the outbox still
  held the attachment and its session; under the throttle every retry ran
  exactly 3 min and ended "cancelled with an error" (CloudKit's
  per-operation timeout), four cycles, each a restart; with the throttle
  lifted the next send completed in a minute (84 MB, one upload, no
  duplicate), the clip plays on the iPad. So: pending work survives
  termination; a retry restarts the operation; a large asset on a link
  too slow to finish within the operation timeout cannot complete until
  the link improves (C-120). **Isolated PDF rename, iPad counters before →
  after:** Records received 44 → 45; asset bytes delivered by CloudKit
  237.3 → 248.7 MB (the PDF, ~11 MB, fetched again); bytes written to media
  storage 218.8 → 218.8 MB. **What the measurements establish:** no file was set on any
  record sent for a metadata change (upload count and bytes unchanged,
  record counts rising). On the receiving side, with the current record
  structure and fetch implementation, changing attachment metadata can
  cause the unchanged asset to be fetched again; "Asset bytes delivered by
  CloudKit" sums the sizes of asset files handed to the app with fetched
  records and is not a network measurement. Asset-field exclusion through
  lower-level fetch operations, or a separate record for frequently edited
  metadata, are options to assess before metadata edits to large audio or
  video become frequent; neither is started. **Findings:** (10) audio and video renames
  live in the per-device title store (C-47), not on the record, so they do
  not sync; only PDF renames write `displayName`. That is the "attachment
  titles" inventory item: writing `displayName` at the two rename sites and
  reading it in the viewers. Not started. C-119 fixed.
  Hands-on: agent ≈ 15 min implementation and tests, ≈ 10 min waiting on
  builds, ≈ 5 min diagnosis and records; Samuel ≈ 25 min at the devices,
  ≈ 5 min waiting. Completion checks (20–21 Oct): agent ≈ 15 min, ≈ 2 min
  waiting; Samuel ≈ 35 min at the devices, ≈ 12 min waiting on throttled
  sends. Untested: a mid-transfer cut on an unthrottled link long enough
  to fail an operation (the ~15 s cut did not); recovery after a device
  restart rather than an app force-quit.
  **Stage E, account change and erase/unlink: passed and accepted
  2026-10-21; final build 1833 (`32d9075`)** (unit tests, simulator, Device A
  account switch, iPad/iPhone sections 1–4, final erase check on 1833; two
  defects found on device and fixed, C-124 and C-127).
  One account guard (`JournalAccountGuard`: bound user, current user,
  unlinked, removal flags) is asked by outgoing batches, fetched zone and
  database changes (imports AND remote deletions), list imports and the
  manual Fetch/Send controls; until now only sends were guarded (C-122).
  When it refuses, the `CKSyncEngine` instance is dropped, not merely
  ignored: nothing is fetched from or sent to a non-bound account, its
  state serialization is never saved, and events from a dropped instance
  are discarded; on return to the bound account a new instance is built
  from the last state saved while bound. Account changes reach one
  `reconcile` path from the engine's event and the system `CKAccountChanged`
  notification; a failed check retries on the stage-C backoff (one timer)
  and on network return. Paused states, all keeping the journal and the
  outbox: Waiting for iCloud (no account, signed out, or iCloud off for the
  app; retried), Linked to a different iCloud account (not retried;
  re-evaluated on the next account change), Unlinked (persisted; explicit
  re-enable), Local copy removed (persisted; explicit re-enable), Local
  removal in progress. Local saves reach the durable outbox in every state;
  only transport waits for an engine. **Unlink** persists; the outbox is
  kept and history keeps feeding it. **Local removal** (`JournalLocalRemoval`):
  the production erase `LocalFactoryReset.perform` is bracketed under
  `#if SYNCTEST` (no third caller): *begin* writes the marker, empties the
  outbox and drops the engine in one atomic write before the first row is
  deleted; the change tracker discards history while the marker is set;
  *finish* fast-forwards the history token recording nothing, clears server
  knowledge, hashes, held files, list fingerprints, aliases and engine
  state, and leaves sync off. An interrupted removal is completed at the
  next launch before any engine exists. **Re-enable**: retained copy on the
  bound account resumes with the outbox and history; removed copy gets a
  fresh engine that fetches the cloud journal again (binding kept, so a
  different account still stays paused); the `JournalSyncEngine` object is
  rebuilt so the post-erase install key is current. Connected account
  deletion runs through the same bracket, so its local reset cannot reach
  the private iCloud journal. 9 unit tests (`SyncTestAccountAndEraseTests`;
  54 SyncTest tests green): the guard for every state; the erase's batch
  deletes DO reach persistent history as deletions without the marker
  (C-121, the hazard demonstrated) and are discarded with it, before and
  after a relaunch; an interrupted removal recovered at launch queues
  nothing; re-enable after removal imports the cloud journal once; unlink
  persists with pending work and edits made while unlinked; pending work
  survives sign-out, switch and relaunch and resumes only for the bound
  account; a wiped list library infers no deletions. Debug, Release and
  SyncTest build. **Simulator run (iPhone 17 Pro simulator, no iCloud
  account, fresh Sync Test install):** a Thought made while "Waiting for
  iCloud" sat in the outbox and survived relaunch; Unlink persisted across
  relaunch with the outbox intact, a session made while unlinked joined it,
  Re-enable kept all three; Simulate interrupted removal then relaunch:
  recovered at launch, outbox empty, "Local copy removed", Re-enable
  returned to Waiting for iCloud with nothing stale; Profile → Erase All
  Études Data with a pending Thought: bracket logged begin/finish, outbox
  emptied, no deletion queued, sync off, app at first launch. **Fixed on
  the way:** the first failed iCloud check scheduled two retry timers (the
  path monitor's initial callback), and the diagnostics list was
  re-identified on every status change, resetting its scroll (C-123).
  **Device coverage still needed (Samuel, script in the notes folder):**
  per-app iCloud toggle with pending work and an edit while paused;
  unlink/reconnect across the two devices; interrupted removal and the
  production erase on the iPad's disposable copy with the cloud and iPhone
  checked unchanged and the journal fetched back. **Account switch, Device A
  (SD beta burner, iPhone 16e, iOS 26.6.1), 2026-10-21, passed.** Device A
  is on its own Apple Account (iCloud user `_bf8836ca…`), not the trial's
  (`_cd10ca7e…`); Sync Test was installed beside the untouched Études
  Release 1818 and the same install carried through A → main account → A
  with no reinstall or clearing. On A: "DA-1" sent, then offline "DA-2" with
  a photo made pending and the app force-quit; the state file over the cable
  showed the two pending changes, records sent 2, binding `_bf88…`, and the
  same after the device-wide sign-out and sign-in (both app containers kept;
  iOS's "previous data will be removed" covers synced system data only). On
  the main account: paused at launch with "linked to a different iCloud
  account", Fetch now and Send now refused (logged), "DA-3" made and queued
  (outbox 3), force-quit and relaunch paused again with Fetch refused; no
  engine activity, server knowledge and sent count unchanged; the iPhone's
  zone stayed at 27 records with no DA entry while an "E5" Thought from the
  iPhone synced normally and never reached Device A. Back on A: the system
  account notification rebuilt the engine from saved state without a
  relaunch ("Engine built from saved state (iCloud account changed
  (system))") and 2 s later it sent exactly 3 records with 1 media upload
  (2.9 MB), no conflicts, nothing held back; A's zone holds 5 records
  (Instrument, DA-1, DA-2 + attachment, DA-3), the iPhone's 28 (27 + E5),
  and the two sets of record ids share nothing; after a relaunch Device A
  shows DA-1/2/3 once each with the photo and no E5. Two accidental taps on
  the diagnostics "Reset engine state" button (beside Probe zone) during
  the run rebuilt a fresh engine and re-imported the whole zone by id on
  each device, with no duplicates and no loss; the button now sits on its
  own row behind a confirmation. Unit tests cover the guard sequence and
  the device run covered CloudKit's real account-change delivery.
  **Limitations/decisions:** no automatic migration or merge between
  accounts; after a removal the binding is kept (a new account on an erased
  device needs the binding cleared, not built); whether CloudKit completes
  an upload in flight when the engine is dropped is not observable, and the
  outbox re-sends it (same record id, tie goes to the server, no duplicate);
  the per-app iCloud toggle's exact CloudKit error is to be observed on
  device; "Delete my journal everywhere" is outside this stage.
  **iPad and iPhone run (Sync Test installs, disposable data, 2026-10-21
  13:12–14:03), all four sections passed; state files read over the cable
  at each step.** (1) iCloud off for the app: a Thought with a photo made
  offline (outbox 2), the Études Sync Test toggle under Saved to iCloud
  turned off, network back: the system account notification fired, the
  check failed with "No iCloud account is configured", engine dropped and
  "Signed out of iCloud, or iCloud is off for this app; journal and pending
  changes kept"; a notes edit merged into the pending save; relaunch paused
  again, outbox 2; toggle back on: the backoff retry rebuilt the engine
  ("Engine built from saved state (retry)"), 2 records and 1 media upload
  (686 KB) sent once, the iPhone shows the edited Thought once. So iCloud
  off for the app is indistinguishable from signed out to CloudKit, and is
  handled as such. (2) Unlink on the iPhone: engine dropped, a Thought made
  while unlinked queued (outbox 1) and kept across relaunch, Fetch now and
  Send now refused three times, the iPad's Thought sent meanwhile not
  imported; Re-enable sent the pending Thought. **Defect (C-124):** the
  iPad's Thought did NOT arrive on re-enable, nor on a manual fetch: an
  engine rebuilt from saved state was answered "no changes" by CloudKit's
  daemon, because the push for that change had arrived while no engine
  existed to act on it; the same had happened to the iPad that morning
  after a push-triggered background launch (the engine is now built after
  the asynchronous account check, so the push preceded it). Nothing was
  lost: a later change on the iPad pushed again and the iPhone fetched both
  (the engine's token was still old). Fixed the same hour: on every
  activation of an engine from saved state the app runs its own
  `CKFetchDatabaseChangesOperation` against a token it keeps after each
  fetch cycle (`catchUpToken`); if the Journal zone moved meanwhile the
  engine is built fresh and refetches the zone. Re-checked on device: unlink,
  a Thought from the iPad, Re-enable → "Catch-up: the zone changed while no
  engine was running; building a fresh engine", 35 records refetched by id,
  no duplicates, the Thought present with no further push. Cost: a full
  refetch (records and, unless CloudKit's asset cache still has them, their
  files) on an activation that follows a missed change; how often that
  happens in use is not known, so it is not called rare. A delta catch-up
  through the app's own zone fetch is the better long-term shape and is
  kept beside the receiver-download optimisation item. (3) Interrupted removal
  on the iPad: rows deleted and the app exited before finish; relaunch
  recovered it ("2 leftover row(s) removed locally", finished, outbox 0,
  sync off); the iPhone's zone unchanged at 35 with the database probe
  reporting no zone changes; Re-enable built a fresh engine, 35 records
  back, the Oud instrument aliased not duplicated, the iPad's own
  instrument rows re-sent by the post-removal bootstrap (same ids, metadata
  only). (4) Offline erase: Airplane Mode and Wi-Fi off, "E4 pending before
  erase" made (outbox 1, confirmed unsent), Erase All Études Data while
  still offline, set up again; diagnostics "off (local copy removed)",
  outbox holding only the new setup instrument; back online no send; the
  iPhone's zone still 35, no zone change, no E4; Re-enable: fresh engine,
  35 records back, Journal matching the iPhone, E4 gone as defined.
  **Also seen:** the engine dropped at the erase was still alive five
  minutes later and attempted a scheduled fetch, ignored by the guard as
  designed ("Event from a dropped engine ignored"); the ownership rules ran
  during the erase, after the owner key was deleted and before the rows
  were, and re-adopted the owner (C-126, fixed: no evaluation while a
  removal is in progress); and the iPad's background launch while locked
  logged "Adoption stopped: the owner key holds a different value" because
  the Keychain was unreadable (C-125, open, harmless).
  Hands-on: agent ≈ 15 min reading and design, ≈ 20 min code and tests,
  ≈ 20 min simulator run and the two fixes, ≈ 20 min guiding the Device A
  run and reading state files, ≈ 25 min guiding the iPad run, ≈ 15 min
  diagnosing and fixing C-124 (code, tests, install); ≈ 12 min waiting on
  builds and test runs beyond what overlapped with the simulator work,
  ≈ 8 min waiting during the device runs. Samuel: ≈ 35 min at Device A and
  the iPhone plus ≈ 15 min on iCloud sign-out/sign-in prompts; ≈ 40 min at
  the iPad and iPhone plus ≈ 10 min waiting on the C-124 fix and fetches.
  **Final check (build 1832, then 1833 `32d9075`, iPad, corrected offline
  sequence):** on 1832 the erase ran with no ownership line between "Local
  removal begun" and "finished" (C-126 held), queued no deletion, left sync
  off; the iPhone's zone unchanged (36, no E7). The log also showed an
  activation that had stalled in the catch-up check during an offline
  relaunch, completing when the network returned and building an engine on
  the removed copy for ~20 ms before the queued re-check dropped it; it
  fetched and sent nothing (C-127, fixed in 1833: an activation that awaited
  abandons itself when a dormancy generation or the guard's decision moved
  meanwhile; the catch-up call is time-boxed at 15/20 s). Repeated on 1833
  with the offline relaunch included: the relaunch settled on Running after
  the time-out, the erase dropped the live engine, nothing between begin
  and finish, outbox only the setup instrument, back online no send, the
  iPhone's zone 37 with no E8, Re-enable rebuilt fresh, Journal matching
  (38 records both sides), owner adopted after the first complete fetch.
  **Qualifications kept for the shipping record (Samuel, 2026-10-21):**
  dropping an engine does not immediately stop all its activity (a dropped
  instance attempted a scheduled fetch five minutes later); the account
  guards and the rejection of stale-engine callbacks remain essential, and
  a focused code review of those protections and the durable erase
  sequence is required before enabling production sync (no broad review
  commissioned). The catch-up performs a full refetch in some
  circumstances; it stays beside receiver-download optimisation and is not
  described as rare without evidence from use. Final-check time: agent
  ≈ 20 min including the C-127 fix, ≈ 7 min waiting; Samuel ≈ 25 min at
  the devices, ≈ 10 min waiting on the 1833 build.
  **Stage F, journal metadata: passed 2026-10-21; final build 1840
  (`8fe4a28`).** Already synced before: session fields (incl. `isPublic`,
  `areNotesPrivate`), PDF `displayName`, the thumbnail star, media by hash,
  instruments, lists. Not synced: audio/video titles (per-device UserDefaults
  store, C-47), the attachment privacy map (file), favourites (saves in
  UserDefaults per viewer), selected PDF pages (UserDefaults). **Design:** the
  side store becomes a field of the owning record and Core Data stays the
  clock. Under SYNCTEST each write point (the single title writer,
  `AttachmentPrivacy.setPrivate`, `PDFSelectedPagesStore.setPages`,
  `FeedInteractionStore.toggleSaved`) also touches its row through the
  `metadata` author, so `userModifiedAt` stamps as a user edit, history
  queues the row (a stamp-only change under that author counts and is never
  owner-only), and the record builder reads the side store; a title also
  lands on `Attachment.displayName`. Fields: `isPrivate` 0/1, `selectedPages`
  JSON ("[]" = whole document), `isSaved` 0/1, `displayName` ("" = no name /
  cleared); an absent field is no information and leaves the receiving store
  alone, so private-by-default still applies where no choice exists. Imports
  write the stores store-only (no hook, no loop), and the title import
  removes per-device overrides so an older local name cannot hide a synced
  one. Metadata sends never carry the file. **Migration** once per device,
  idempotent, flag last: rows with side-store values are queued as
  `metadataOnly` with their existing stamps (titles moved to `displayName`
  under the unstamped `migration` author); meeting a server copy without
  the fields they stay queued and go on top of its change tag, meeting one
  with the fields they yield; a later real edit elsewhere still wins. The
  trial's Solo installs have no privacy toggle in the UI (Connected only), so
  diagnostics flips the newest attachment's choice; the privacy entries
  themselves exist in Solo (every attachment gets an explicit "shared" at
  creation). 13 unit tests (`SyncTestMetadataTests`), 69 SyncTest tests
  green; Debug, Release and SyncTest build. **Device run (iPhone and iPad
  Sync Test installs, disposable entries, state files read over the cable):**
  (1) migration, fixture made on 1833 (a Thought with an audio clip renamed
  `MIG audio name`, its PDF set to page 1, the row hearted): on 1836 the
  iPhone queued 1 title, 11 privacy choices, 1 page selection, 1 favourite
  and sent them metadata only; the iPad showed the name, "Page 1", the heart,
  and the Journal cards that had had no thumbnail since Checkpoint 2 now show
  one (the explicit privacy entries arrived). (2) Titles both ways on 1838,
  metadata only (media uploads unchanged at 15 files); a cleared video name
  arrived as the default label; names survived relaunch. The viewer treats
  an empty audio name as "leave it" by design (video and the editor's
  attachments card can clear), so audio clearing was exercised through the
  video. (3) Privacy both ways on 1839 through the diagnostics control.
  (4) Favourites both ways. (5) PDF pages both ways including the return to
  the entire document. (6) Offline on the iPad: rename, heart, privacy flip
  and page selection made in Airplane Mode, kept across a relaunch while
  offline, sent on reconnect as 3 records with 0 media uploads, all four
  present on the iPhone. **Defects found and fixed during the run:** (a) on
  first launch of 1835 the migration's 15 queued rows were all dropped: the
  same launch refetched the whole zone and every refetched copy met its
  queued row with an identical stamp (tie → server), and old-format records
  without `displayName` wiped the migrated names; fixed in 1836
  (`metadataOnly` rows survive a copy without the fields; absent
  `displayName` is no information; this build always writes it). (b) The
  migration's sends re-uploaded 3 files, 10.9 MB, whose server hash the
  iPhone had never learned (pre-stage-D attachments); fixed in 1837
  (metadata sends are asset-free whatever the device knows). (c) A privacy or
  page touch on an attachment was discarded by the tracker's
  ownership-only rule; caught by a unit test, fixed in 1838. (d) Journal rows
  showed a favourite written by the import only once rebuilt; the rows and
  the detail screen now re-read it on the store change (1840). **Measured:**
  one rename on the iPad re-saved the session's 6 attachment records
  (metadata only on the sender) and the iPhone fetched **267 MB** of
  unchanged asset data for them and wrote 0 bytes (C-130: the receiver
  fetches the asset of every changed attachment record; stays a separate
  inventory item). The catch-up's full refetch ran on **every relaunch after
  the other device had written while this app was closed**: three times on
  the iPhone and once on the iPad today, 39–41 records each, up to 203 MB of
  asset transport when the daemon's cache was cold (C-131). **Limitations:**
  whole-record conflict rule, so two devices editing different metadata of
  the same row at the same moment keep only the later record; two devices
  holding different per-device titles for the same clip at migration keep
  whichever migrated first; privacy is not a user action in Solo; hearts and
  titles sync under the viewer scope of the owner key (an un-owned journal
  syncs favourites under "unknown"). Hands-on: agent ≈ 20 min reading and
  design, ≈ 35 min code and tests, ≈ 30 min fixes during the device run,
  ≈ 25 min guiding and reading state files; ≈ 25 min waiting on builds and
  tests. Samuel: ≈ 50 min at the devices (fixture, migration, six sections,
  the isolated measurement), ≈ 25 min waiting on the five builds.
  **Stage G, receiver-download optimisation (C-130, C-131): passed
  2026-10-21; final build 1844 (`e9363ab`).** (1) *Why one rename saved six
  attachment records.* Two sources, found with a tracker diagnostic that logs
  each attachment update's changed keys and author: the editor's Save ran
  `AttachmentCommitService.applyThumbnailFlags`, which set `isThumbnail` on
  every attachment of the session to the value it already had; and the
  editor's "apply pending replacements" step wrote every attachment's
  resolved `fileURL` back (the map holds all existing attachments, not only
  replacements), which after each reinstall differs from the stored path
  because the app container moves. Both fixed at source (write only a value
  that changes; write `fileURL` only for a different file), with two nets
  under SYNCTEST: the stamp observer drops keys set to the value they
  already hold, and a `fileURL`-only change counts as content only when the
  file's hash differs from the server's. An ordinary rename now queues one
  record. (2) *Record layout.* An attachment's name, star, privacy choice and
  page selection live on a small `AttachmentMeta` record ("<id>-meta"); the
  content record keeps kind, dates, session link, file and hash. A metadata
  edit queues only the meta record, so the engine's own fetch delivers a
  small record and never the file; a content change still carries the file
  by the stage D hash rule. Meta records arriving first are held; legacy
  fields on an old content record count only until a meta record is known;
  deleting an attachment deletes both records; a meta deletion alone deletes
  no row. Attachment ids, session links, files and side stores are
  untouched. One-time transition: every attachment queued its meta record
  (13 small records per device, 0 media) and a records-only pass
  established the app's own zone token (41 and 54 records, 0 files). (3)
  *Incremental catch-up.* When the database check says the zone moved while
  no engine ran, the app fetches the zone's delta with its own zone token and
  without the asset field, imports it through the importer, and fetches a
  file only for attachment records whose hash this device does not hold; the
  engine keeps its saved state. A fresh engine remains the fallback for an
  expired token or a deleted zone, logged and shown as "Last catch-up".
  7 unit tests (`SyncTestReceiverTests`), 76 SyncTest tests green; Debug,
  Release and SyncTest build. **Device run (iPhone and iPad Sync Test
  installs, state files read over the cable before and after each isolated
  operation; counters are records sent/received, sender media uploads, asset
  bytes delivered to the app, bytes written to media storage):** isolated
  rename through the editor path: iPhone 1 record sent, 0 uploads; iPad 0
  asset bytes delivered, 0 written (on 1842 the same rename still sent six
  content records and delivered 378 MB, which is what exposed the path
  rewrite). Privacy, page selection and heart: three small records, 0 asset
  bytes delivered either way. Relaunch catch-up: iPad closed, iPhone renamed
  and hearted, iPad reopened: "Catch-up (the zone changed while no engine
  was running): 2 changed record(s), 0 deletion(s), 0 file(s) fetched",
  engine built from saved state, both changes present; offline variation:
  the check timed out, the engine came from saved state, and on reconnect
  its own fetch brought the change, 0 asset bytes, no full refetch. New
  photo: 1 upload 4.68 MB, iPad delivered and wrote 4 675 267 bytes; replaced
  photo: 1 upload 2.44 MB, iPad wrote 2 438 816, one attachment, no
  duplicate. Interrupted 84 MB clip (force-quit after Save, relaunch): sent
  once, iPad delivered and wrote 84 085 390 bytes once, plays. Deletions:
  an attachment as two remote deletions (content and meta); a session as 4
  deletions through the iPhone's relaunch catch-up, nothing resurrected.
  Existing trial journal intact through the transition, 0 held metadata
  records. **Fixed during the run:** a heart imported by the relaunch
  catch-up landed under the placeholder viewer scope (the scope was read
  after the catch-up; C-133). **C-134, investigated from the evening's
  state-file snapshots (after Samuel's clue that one clip was renamed
  repeatedly):** the 191 MB fetch at 21:28 delivered the eight content
  records the iPhone had itself sent at 20:58 and 21:09 (the C-132 path
  rewrites, including the repeatedly renamed clip 685EE81F and the newest
  video F2094F40) plus two meta records; the 2.4 MB at 21:53 was its own
  replaced-photo content record sent at 21:46. Every rename since 1842
  logged `["displayName", "userModifiedAt"] → meta`: renaming never saved
  the content record. The engine's serialized state hash changed only on
  fetches and engine builds, never after a send (unchanged across the 20:58,
  21:09, 21:32, 21:36 and 21:46 sends), so after a relaunch the engine
  fetches with a token that predates its own sends and gets them back with
  their files. Recurring, not one-time: after any relaunch that follows a
  content send with no fetch in between; metadata echoes are small. **Fix
  (build 1846), as first built:** after a send that saved content records the
  engine fetched once ~3 s later while the app was alive, so the persisted
  state passed its own writes; and a delivered record whose change tag this
  device already holds is skipped (no import work) and counted in diagnostics
  as "Own-write echoes" with the asset bytes that came with it. **Acceptance
  2026-10-26 (iPhone and iPad on 1846), CORRECTED the same day (C-135):**
  the post-send `fetchChanges()` trapped inside CloudKit on every call, so
  the "relaunches" in that acceptance after the photo send (12:20) and the
  delete-and-add (12:24) were the app ending (crash reports 12:20:17 and
  12:24:22), not deliberate relaunches, and the "no echo" seen on the
  engine's fetch after them was partly the catch-up's doing. What that
  acceptance did demonstrate stands: three renames of the same clip then a
  force-quit and relaunch of the iPhone gave three meta records, a relaunch
  catch-up of 2 changed records with 0 files, no content record fetched, 0
  asset bytes delivered on either device; the new photo (3.44 MB) and the
  delete-and-add (1.33 MB) were each delivered and written once by the iPad.
  **Replacement behaviour, build 1854 (`22c89b3`) on device:** the manual
  post-send fetch is gone (C-135); the engine's own push-triggered fetch
  after a send covers the common case and the echo skip the rest. The same
  three checks: three renames (`F1`–`F3`) then force-quit and relaunch:
  catch-up 2 records, 0 files, the iPhone's asset bytes delivered unchanged;
  a new photo (7.62 MB, 1 upload) then force-quit and relaunch: catch-up 4
  records, 0 files, no echo bytes on the iPhone, the iPad's asset bytes up by
  exactly the photo; a replacement (3.44 MB, 1 upload, 2 deletions) then
  force-quit and relaunch: catch-up 3 records, 2 deletions, 0 files, the
  iPad's asset bytes up by exactly the file, one attachment, no duplicate.
  No crash report on either device after 14:20. The iPad's two own-write
  echoes were small records with 0 bytes. **Limitations:**
  after a relaunch the engine may re-deliver changes the catch-up already
  imported (idempotent; costs assets only for content records); the
  catch-up's zone token advances only when a catch-up runs, so each one
  re-reads what changed since the previous one (records only, files by
  hash); the transition left the legacy name/star fields on old content
  records (ignored once a meta record exists).
  Hands-on: agent ≈ 20 min investigation and design, ≈ 50 min code,
  ≈ 25 min tests, ≈ 30 min fixes during the device run (path rewrite, scope
  order), ≈ 35 min guiding and reading state files; ≈ 40 min waiting on
  builds and tests. Samuel: ≈ 70 min at the devices, ≈ 20 min waiting on
  the four builds.
  **Stage H, private profile: passed 2026-10-26; final build 1851
  (`0c455b6` plus the record commit).** Scope: name, location, primary
  instrument and avatar through the bound private journal, no Connected
  login. Already synced before: profile instruments (stage C); the stage B
  owner-store merge only copied location and avatar between scopes on one
  device. **Design.** Two fixed-name records in the Journal zone: `Profile`
  ("profile": `name`, `location`, the primary as the stage C instrument link
  `instrumentRef` + `instrumentName`, `userModifiedAt`) and `ProfileAvatar`
  ("profile-avatar": the derived 256 pt PNG as `file` with `fileHash`,
  clocked by the file's modification date, which the import also sets). A
  text edit queues only the Profile record, so it never carries or delivers
  the avatar. Clears are explicit ("" for a field; the avatar record saved
  with no asset and `fileHash ""`); the avatar record is never deleted, so a
  removal always has a clock. Change detection is a fingerprint scan as for
  saved Lists (the Profile row has no stamp attribute; location and avatar
  live outside Core Data): `ProfileStore.setLocation`, the avatar writers and
  a save touching Profile schedule one (3 s debounce, held while a Profile
  text field has focus), every activation runs one. A profile nobody has
  filled in (name and location empty) is never uploaded and a change to it
  is not an edit, so the app's automatic default primary instrument never
  beats an established profile. Conflicts: the existing rule, whole record,
  newer clock wins, ties to the server, displaced values in the conflict
  log. A profile that predates the build is sent WITHOUT a clock; two such
  profiles merge field by field (a blank never displaces a value; two values
  resolve to the longer, equal length by Unicode order), independent of
  arrival order, so both devices compute the same result and converge in one
  round; a displaced avatar is kept as a file with a Restore button in
  diagnostics (restoring is a clocked edit). Imports write the avatar byte
  for byte (a re-encode would change the hash and bounce it) through writers
  that set no Solo→Connected pending marker; `ProfileView` re-reads name,
  location, primary and avatar on the import notification so a stale screen
  is not written back on close, and values the sync put on screen schedule
  no directory write. Connected isolation: the only remote paths need a
  Connected identity (`ProfileMaintenancePolicy`, directory hydration); a
  SYNCTEST-only `ConnectedWriteWitness` counts every attempt at the four
  entry points (directory upsert, avatar-key patch, avatar upload, avatar
  delete) and diagnostics shows it. An erase resets the scan baseline to the
  empty profile (nothing erased is sent; anything typed before re-enable is
  a clocked edit). 10 unit tests (`SyncTestProfileTests`): the merge rule
  (deterministic, symmetric, displaced values), default profile never sent
  and an established one arriving (row created when absent), clocked edits
  and explicit clears, imported clears staying cleared, primary resolution
  by alias/name without duplicates, avatar by hash on its own record with
  text edits carrying none, verbatim avatar import with no Connected marker
  and clocked removal/conflicts, migration yielding to a real edit and two
  established profiles converging, no Connected write and the remote paths
  refusing without an identity, erase reset. 87 SyncTest tests green;
  Debug, Release and SyncTest build. **Device run (iPhone and iPad Sync
  Test installs, disposable values, state files read over the cable;
  builds 1848 → 1851):** (1) transition with two different established
  profiles (`H-Phone`/Bristol/avatar A/Oud vs `H-Pad`/no location/avatar
  B set later/Viola): both devices converged in one round to
  `H-phone · Bristol · Viola` and avatar B (newer file); the iPad logged
  "merged field by field" with "displaced: name (this device): H-Pad ·
  instrument (this device): Oud", the iPhone kept avatar A as a displaced
  copy with its Restore button. (2) Name, location and primary instrument
  edited in both directions, each one small record, instrument list without
  duplicates, all values intact after force-quit of both. (3) New avatar
  from the iPhone (1 upload, iPad delivered and showed it in Profile and on
  the home button), removal from the iPad (iPhone's gone, "none (removed)"
  on both, still gone after relaunch), set again (arrived once). (4) Name
  and location edits with avatar uploads and avatar bytes delivered
  unchanged on both devices. (5) Location cleared on the iPad: empty on the
  iPhone, still empty after relaunching both and reopening Profile. (6)
  iPad offline: name and location edited, app force-quit and reopened
  offline (values kept, "save Profile" in the outbox), one record sent on
  reconnect, both values on the iPhone. (7) Clocked conflict: iPad offline
  `H16-pad`, iPhone `H16-phone` ~2 min later, iPad online: `H16-phone` on
  both, iPad conflict "displaced: name (this device): H16-pad". (8)
  "Connected writes attempted" 0 on both devices throughout; Connected
  identity "no". (9) Existing journal, media and instruments intact.
  **Verified in tests only:** the merge rule's symmetry over every field
  combination, the erase reset, the policy refusal without an identity. On
  device the isolation evidence is the witness counter and the absence of a
  pending avatar marker; no real Connected identity was involved.
  **Defects found and fixed during the run:** (a) every post-send
  `fetchChanges()` from C-134 trapped inside CloudKit 3 s after a send with a
  file, seven of seven today including the two photo sends of the C-134
  acceptance on 1846 (the app relaunched each time; the acceptance's
  "relaunch" was partly that); 1849's deferral until no engine fetch was in
  flight did not help; removed in 1850, the echo skip stays (C-135). The
  manual Fetch now on an idle engine does not trap. (b) Profile commits
  locally on every 650 ms typing pause, so one name edit went up as five
  records with intermediate values logged as displaced on the other device,
  and an emptied name field (cleared before retyping, then a pause) went up
  as `name ""` and opened onboarding on both devices (the setup gate is "no
  name"); debounce 3 s in 1849, scan held while a Profile field has focus in
  1851, after which a typed name is one record (C-136). (c) A pending save
  dropped by an import stayed in the engine's own list and went up once more
  with the values just taken (one redundant record); fixed after the run,
  not device-verified. **Found, not fixed (production, not sync):** clearing
  the name in Profile sends a Debug or Release build to onboarding after the
  650 ms local commit, because the setup gate is evaluated live (C-137).
  **Measured:** the avatar PNG is 241 KB from the iPad and 1.0–2.7 MB from
  the iPhone (the 256 pt downscale renders at the screen scale), so avatar
  sends are not small; the engine re-delivered the iPad's own avatar record
  once (241 KB, skipped as an echo). **Limitations:** whole-record
  conflicts (a later edit of one field carries the other device's whole
  profile); the original full-size avatar is not synced, the other device
  re-crops from the 256 pt copy; a profile with only a primary instrument
  (no name or location) does not travel; the app's automatic primary default
  is a profile edit once the profile is established; an imported empty name
  opens onboarding on the receiving device by the app's existing gate.
  Hands-on: agent ≈ 35 min reading and design, ≈ 50 min code and tests,
  ≈ 50 min fixes and state-file analysis during the device run, ≈ 15 min
  records; ≈ 35 min waiting on builds and tests. Samuel: ≈ 60 min at the
  devices, ≈ 20 min waiting on the four builds and installs.
  **Stage H follow-up (Samuel's five items): passed 2026-10-26; final
  build 1856 (`26d9cd0`).** (1) *C-134 corrected* (text above and C-134's
  row) and the three checks repeated on 1854: renames, new media and a
  replacement, each followed by a force-quit and relaunch of the sender:
  no crash, the intended content on the receiver once, the sender's asset
  bytes delivered unchanged throughout. (2) *Primary instrument alone:* a
  tap in the instrument list is recorded as a choice (`profilePrimaryChosen`
  in the state file; an erase clears it) and from then on a primary change
  is an edit even with no name or location; a pre-existing primary-only
  profile goes up at first sight without a clock. The app's own default on a
  never-filled profile is still not an edit. Unit-tested (upload, record,
  import onto an empty device resolving by name without a duplicate row);
  on device a chosen primary travelled both ways with no duplicate. A bug
  the new test caught before any build: after an import whose primary
  resolved to this device's own row (`oud` arriving where `Oud` exists) the
  fingerprint recorded the record's spelling, so the next scan saw a phantom
  edit; the fingerprint now comes from what the device holds. (3) *C-137,
  production, separate commits `3e85cc6` and `dfa9361`:* the name is
  mandatory (set-up cannot finish without one), so `ProfileNameCommitPolicy`
  commits the stored name for an empty draft, the typed name otherwise;
  `save()` and the directory snapshot use it and the field shows the kept
  name again when an edit ends empty (a notice was tried and dropped: it
  never displayed, and the instant reappearance is preferred). The set-up
  gate is unchanged; its input can no longer read empty for an established
  person. Tests: `C137ProfileNameCommitTests` (clear, retype, relaunch as a
  fresh read; set-up still validates), plus a SyncTest test that the emptied
  field never reaches a record. On the iPhone (Sync Test install, the same
  production code): the name cleared and left for 5 s came straight back,
  no onboarding, the iPad unchanged, intact after a relaunch; cleared and
  retyped went up as one record. (4) *Connected isolation with an identity:*
  `SyncTestConnectedIsolationTests` arranges a valid-looking identity on
  the real `AuthManager` (Apple id, access token, backend id, Connected
  mode, a loopback base URL with a URLProtocol stub that records and fails
  every request): an imported profile and avatar leave no pending marker,
  the avatar promotion makes no request, the screen's hydration filter
  publishes nothing for the hydrated values, an unrelated session save and
  the location rewritten on close change none of that, and the member's
  own avatar edit still attempts its upload (one request to the avatars
  path, marker kept on failure). The screen itself is not mounted; its
  `onChange` wiring is represented by the pure filter it consults. Device
  coverage had no identity at all ("Connected writes attempted" 0 on both
  devices throughout, including after every step of this follow-up). (5)
  *Merge rule narrowed in wording, confirmed in code:* the longer-value
  tie-break is reachable only when neither side has a clock (the one-time
  meeting of two pre-existing profiles) and is an arbitrary tie-breaker,
  not a judgement of correctness; displaced values stay in the conflict
  log and a displaced avatar in a file. A test asserts a newer shorter
  value wins and an unclocked profile yields to any clocked record. Also
  closed: the redundant send after a lost conflict survived in one path
  (the conflict resolved by the relaunch catch-up before any engine existed;
  the engine then restored its own pending list and sent the record once
  more); an engine built from saved state now drops any pending change the
  outbox no longer holds (`JournalPendingReconcile`, pure, unit-tested); on
  device the iPad, force-quit offline with a pending name and reopened,
  logged "Dropped 1 pending change(s)…" and its records-sent count did not
  move. 94 SyncTest tests green (the C-137 tests also green under the Debug
  scheme); Debug, Release and SyncTest build. No crash report on either
  device since 14:20. **Limitations unchanged:** whole-record conflicts;
  the full-size avatar is not synced; iPhone avatar PNGs 1–2.7 MB (recorded,
  not optimised); an imported empty name cannot arise any more, but a
  deliberate change of the setup gate remains Samuel's call. Hands-on:
  agent ≈ 25 min reading and design, ≈ 55 min code and tests, ≈ 30 min
  fixes and state-file analysis during the device run, ≈ 15 min records;
  ≈ 40 min waiting on builds, tests and installs. Samuel: ≈ 35 min at the
  devices, ≈ 25 min waiting on the three builds and the iPhone reconnect.
  **Stage I, Scores library: passed 2026-10-27; final build 1862
  (`075d123`).** Scope (Samuel, 2026-10-26): the whole library,
  including documents no entry refers to: PDFs, titles, favourites, the
  cover-page field (exercised through diagnostics; no chooser screen
  exists), additions, deletions and the reading position. Scores stay in
  their UserDefaults index and `Documents/Scores` files; no move into Core
  Data. **Design.** Three records per item, named from its id: `Score`
  ("score-<id>": the PDF as `file` with `fileHash`, file name, page count,
  created date, the C-5 source id and the title at creation; written once,
  a library PDF never changes), `ScoreMeta` ("score-<id>-meta": title,
  favourite, cover page, `userModifiedAt`) and `ScorePosition`
  ("score-<id>-position": last viewed page with its own clock, so a page
  turn can never displace a rename under the whole-record rule). A rename,
  favourite or cover change queues the meta record alone (asset-free, by
  the stage F/G rules), so no unchanged PDF is uploaded or delivered.
  Change detection is a fingerprint scan (`JournalScoreSync`, the Lists and
  profile pattern): the store's write points call `JournalScoreMirror`; the
  engine scans 3 s after a metadata write; a reading position is saved
  locally on every page turn but shared only at an explicit boundary, the
  viewer's dismissal (`ScoreLibraryStore.viewerDidClose`) or the app going
  to the background (Samuel's clarification during the device run,
  2026-10-26: no idle publishing; build 1859 had a 10 s idle rule, and the
  iPad resumed on the page the iPhone was sitting on); every activation
  scans metadata, and positions once at the transition. The first scan is the transition: every item queued
  with its file, its metadata and position without a clock, so a real edit
  anywhere beats them. **Combining libraries:** union by id; ids and file
  names are UUIDs minted at import, so two libraries are disjoint and
  nothing is merged, whatever the titles or bytes; the same id (a restored
  copy) meets the existing rule: newer clock wins the whole meta record,
  ties (two unclocked copies) to the server, the displaced values in the
  conflict log; a differing file for the same id takes the server's and
  keeps the local one in `Application Support/SyncTest/DisplacedScores`
  by hash; a repeated import of the same id updates the one item. Imports
  write the file first, then the index entry through the store (no hook,
  so no loop); meta and position records arriving before their item are
  held (`awaitingScore`) and land with it. The catch-up fetches a Score's
  file only when the item or its file is missing here or the hash differs.
  **Reading position (approved behaviour):** opening a score reads the
  latest synced page; the open viewer holds the page it was opened with
  (`TimerScoreViewerRequest` is immutable, the restore runs once), so a
  remote page never moves someone's reading; the currently open score and
  the last-opened date stay device-local, so opening here opens nothing
  there; both devices reading the same score each keep their page and the
  later dismissal or backgrounding becomes the saved position; imported
  pages are clamped to the page count; a displaced page is counted, not
  logged as a conflict. Found on 1860: with the iPhone's viewer open on
  page 1, the iPad's pages 3 and 2 were written into the iPhone's saved
  page and the dismissal published 2; now the store knows which score's
  viewer is on screen (`openViewerID`), a remote position for it is
  recorded but not written, and the dismissal or backgrounding publishes
  the page on screen with a fresh clock even if unchanged (1861). Found on
  1861: backgrounding queued the position but the app was suspended before
  the engine sent it; the background handler now takes background time
  around the scan and a manual `sendChanges()` (1862). An item made here from its content record alone
  (title at creation) takes its first meta record quietly; two genuinely
  pre-existing copies still log the displaced values.
  **Journal attachments (C-138, both directions):** a library delete keeps
  a PDF any pdf attachment's stored path resolves to (production fix
  `b4ea8bf`, a dependency of this stage); the importer's remote attachment
  deletion now goes through the guarded `AttachmentStore.deleteAttachmentFile`,
  so an attachment deleted elsewhere never removes this device's library
  PDF; a remote library deletion uses the same keep rule. On the receiving
  device a PDF that is both a library item and an attachment is two
  files, so deleting either never affects the other; the PDF travels
  twice (once per record), accepted for the trial and recorded as a later
  optimisation. **Damaged index (C-139):** reported once, nothing sent, no
  deletion inferred, imports and remote deletions refused, bytes
  untouched. An erase resets the baseline (nothing erased is sent; a
  score added before re-enable is a clocked new item). Diagnostics
  section "Scores library (stage I)": items, exchanged, uploads, asset
  bytes delivered, records sent without a file, positions sent/displaced,
  held records, the newest score with a cover-page control, and a re-send.
  15 unit tests (`SyncTestScoreSyncTests`) plus 5 production
  (`C138ScoreLibraryTests`): transition and edits, cadences, union by id
  with equal titles and no duplicate on repeat, held records, the same id
  with different metadata (unclocked tie, newer local kept and resent,
  newer server applied, displaced values logged) and with a different
  file, damaged index (no send, no deletion, no overwrite), position
  clamp/newer/older with no conflict entry and no touch on metadata or
  the open score, deletions both ways with a referenced file kept, the
  importer's guarded removal, erase baseline, send conflict. 17 tests in `SyncTestScoreSyncTests` after the device
  run; 143 SyncTest tests green; Debug, Release and SyncTest build.
  **Device run (iPhone and iPad Sync Test installs, 2026-10-26 evening and
  2026-10-27, builds 1859 → 1862, both state files read over the cable
  after every step, deltas against the previous read; "asset bytes
  delivered" is what CloudKit handed the app, never network traffic):**
  (1) transition with differing fixtures made on 1856 (iPhone 3 items
  incl. a scan, a rename, a star and a page-2 position; iPad 2 items, one
  with the same title as an iPhone one): 3 and 2 files uploaded once,
  both libraries 5 items with both `I-Mozart` present, files open, no
  duplicate after relaunching both (one-time cost: each device's own
  records came back as own-write echoes after its first relaunch, 4.0 and
  9.9 MB delivered and skipped, 0 written). (2) Rename, favourite each
  way and the cover page from diagnostics: one `ScoreMeta` each, 0
  uploads, 0 asset bytes delivered either way; the cover thumbnail changed
  on both. (3) A 5 KB import and a 9.56 MB three-page scan each delivered
  and written once; a deletion applied as three record deletions and one
  item removed. (4) C-138 both ways: the attachment deleted on the iPad,
  the iPhone's library file still on disk (27,290 bytes, read over the
  cable) and the item opening; the library item deleted on the iPhone,
  the entry's PDF still opening on both devices. (5) Offline on the iPad:
  import, rename and star made in Airplane Mode, kept across an offline
  relaunch, sent on reconnect as 3 records with 1 upload, present once on
  the iPhone. (6) Reading position on 1862: iPad dismissed on page 3 →
  iPhone opened on 3; iPhone sat on page 1 with the viewer open while the
  iPad resumed on 3, moved to 2 and dismissed → the iPhone's viewer never
  moved; the iPhone dismissed on 1 → both reopened on 1; the iPad moved to
  2 and went to the background → "Background send finished", the iPhone
  opened on 2; no "Currently Open" card for a score opened only on the
  other device. (7) Three imports with a force-quit before the third was
  sent: the outbox held it, uploads +3 exactly, the iPad's relaunch
  catch-up fetched the three files once (45,314 bytes, their exact total),
  no duplicate after a further relaunch. (8) Erase on the iPad: outbox
  emptied, no deletion queued, the iPhone untouched; re-enable refetched
  the zone (journal and media included, several minutes) and the restored
  library equalled the iPhone's item by item: same 9 ids, favourites,
  cover pages and positions, each file written once. (9) Journal, media,
  profile and lists intact on both; Connected writes attempted 0; no crash
  on either device. **Defects found and fixed during the run:** (a) with
  the viewer open on page 1, the iPad's pages 3 and 2 were written into
  the iPhone's saved page and its dismissal published 2 (1861, see
  above); (b) backgrounding queued the position but the app was suspended
  before the send (1862, see above); (c) the first meta record for an
  item made from its content record was logged as a conflict (1861).
  Clarified by Samuel during the run: no idle publishing (1859 had a 10 s
  idle rule; 1860 removed it). **Measured costs, not faults:** the own-write
  echo after a relaunch or a fetch that follows a send re-delivers this
  device's own score files (C-134; up to 9.9 MB in one fetch here),
  skipped and never written; a re-enable after an erase refetches the
  whole zone with every file. Hands-on (estimated from the state-file
  timestamps; Samuel did not report times): agent ≈ 2 h 40 min design,
  code and tests, ≈ 1 h 40 min fixes during the device run, ≈ 1 h 30 min
  reading state files and guiding, ≈ 30 min records; ≈ 1 h 45 min waiting
  on builds, tests and installs. Samuel ≈ 2 h 25 min at the devices over
  the two days (fixture included), ≈ 50 min waiting on the four builds,
  the re-enable fetch and my reads.
  **Limitations:** whole-record conflicts on the meta record (a later
  edit of one field carries the other device's title, star and cover);
  a PDF held as both a library item and a journal attachment is uploaded
  and delivered once per record (later: cross-record reuse by hash); a
  scanned score embeds its page images and can be large, and C-120 applies
  to it in full: on a link too slow for CloudKit's per-operation timeout
  it stays pending, retried from the start each cycle, until the link
  improves, so a sufficiently large scan may not arrive at all while the
  connection stays poor (recorded; no size cap, no transfer work in this
  stage); the cover page has no chooser screen; a library item whose file
  is missing here is not sent; a remote deletion that arrives while the
  index is unreadable leaves the item here, and it is uploaded again once
  the index reads.
  **Stage J, settings, colours, recovery, mobile data, removal wording and
  the missing-score state: PASSED on device 2026-11-03; final build 1880
  (`31bb9e9`, the C-149 commit) plus this record's commit; built 2026-10-27,
  clarified 2026-10-28, device run 2026-10-28 and 2026-11-03 on builds 1867
  to 1880, commits `3de231a` … `31bb9e9` (seventeen, all unpushed).** Scope (Samuel, 2026-10-27): primary activity; Lists
  defaults, autofill choices and typed presets per (activity, instrument)
  context; the Journal Tint preference; consistent thread and instrument
  colours; a user-facing recovery view for displaced text; media over Wi-Fi
  by default with a per-device option; device-only removal wording; a
  visible unavailable state for a score whose file is missing. Tool
  visibility, layout and working settings (metronome, drone, tuner, tasks
  pad, strips, hints, insights range) stay per device, as do active timers,
  drafts and unfinished recordings. **Design.** (1) *Settings*: one small
  `Setting` record per choice ("setting-tintMode", "setting-primaryActivity":
  `value`, `userModifiedAt`), so a change to one never displaces the other;
  a custom primary activity travels as "custom:<name>" and resolves to the
  receiving device's spelling by normalised name. (2) *Lists contexts*: one
  `ListContext` record per (activity, instrument) context ("listctx-<hash>"
  of the activity reference and the instrument's NAME, never its local id,
  so the same context shares a record on both devices whatever the aliasing
  of stage C): default list id ("" = none), autofill flag (0/1, absent =
  never set), typed preset (JSON lines; a legacy `[String]` preset is
  carried in the typed shape), clock. On arrival the instrument name
  resolves to this device's row and the settings are written under its id;
  a record whose instrument is not here yet is held and lands with it.
  Explicit clears travel as values; absent fields carry no information;
  deletions are never inferred for contexts. (3) *Colours*: thread colours
  need no record: production's `Theme.ThreadTint.primeWeightedSlots`
  already rebuilds the thread map from usage whenever a thread view
  renders (rank by count, ties by name, slots handed out in rank order
  from the hero palette first; a label in the old map but not in the
  counts keeps a slot after the ranked ones), so on a single device a
  thread's colour already moves when its rank moves, and two devices with
  the same journal and the same ranking produce the same map in whatever
  order the entries arrived. The trade-off, stated rather than changed:
  while the journals merge, each device's ranking changes once, so a
  thread can change colour once on each device, then both agree and stay;
  a synced thread record would fight the usage rebuild (ping-pong). The
  tie-break is a locale-aware name comparison, so two devices in different
  languages could in principle rank a tie differently (both trial devices
  are en-GB); and production primes the one map from whichever screen
  last rendered (Journal: the whole journal; Insights: the sessions in
  the chosen range), a pre-existing quirk sync does not change. The instrument map is one
  `TintMap` record ("tint-instrument": label → slot) merged by UNION with
  the server's slot standing where both assign the same label, and a label
  only this device has that sits on a slot a server label holds moved to the
  next free colour before the sanitiser runs (device run 2026-10-28: Sitar
  and Tabla were both given slot 3 offline, and the sanitiser's name order
  had moved the FIRST upload's label; now only the later device's own new
  label moves, and when all four visible colours are taken two labels share
  one, as production already allows); removals are
  never sent (a label a device drops, its primary or a sanitiser move, is
  not a change), so existing assignments are kept wherever possible, a
  clash is settled once and both devices, running the same deterministic
  sanitiser, converge (unit-tested with the real sanitiser). No repeated
  sends: a map is queued only when it differs from the last exchanged map
  by an addition or a move AND its fingerprint differs from what is already
  queued; a sanitiser move after a merge is one further send, after which
  the exchanged map equals the local one. (4) *Change
  detection*: a fingerprint scan on the defaults-change notification
  (800 ms debounce, with the Lists scan), at activation and after imports;
  settings and contexts are clocked at the scan that finds the change. (5)
  *Recovery*: every conflict entry now carries readable fields ("Title
  (this device)": the value that lost), a subject and a restore handle;
  Profile → "Displaced by sync" lists unresolved entries with Copy and,
  for session title/notes, attachment names, profile name/location, score
  titles and the displaced avatar, Restore, which is a NEW edit through the
  app's own writers (clocked now, wins everywhere); Dismiss removes an
  entry; no version history. (6) *Media over mobile data* (C-141). The
  rule (Samuel, 2026-10-28): option OFF → media waits on mobile data and on
  a personal hotspot (`isExpensive`), "Media waiting for Wi-Fi"; option ON
  → both carry media; Low Data Mode (`isConstrained`, which iOS lets the
  person set per Wi-Fi network as well as for mobile data) pauses media
  whatever the option says, "Media paused by Low Data Mode", because
  allowing mobile data never overrides the person's own system-wide
  request; ordinary Wi-Fi and wired links carry media whatever the option;
  text, settings, metadata and deletions sync on any link. While media is
  held, outgoing records that would carry a file stay in the outbox, and
  the app's asset-free delta catch-up holds by name each record whose
  file it needs ("n to receive"); when the hold lifts those are fetched
  with their files and the held uploads go. **The engine never fetches
  (C-149, 2026-11-03).** `CKSyncEngine` fetches every asset with its
  record and cannot leave files out; the first design rebuilt it without
  automatic sync only while media was held, and each return to automatic
  sync then re-fetched, with files, everything changed meanwhile (104 MB
  on mobile data at 12:44 on 2026-11-03, own uploads echoed back on both
  devices). Now the engine is built with automatic sync off always and
  only sends; the app's records-only catch-up, with its own zone token,
  is the only fetch: on activation (the whole zone, records only, when
  there is no token yet, which marks the first complete fetch that
  ownership adoption waits on), on every silent push (the app's own
  `CKDatabaseSubscription` "etudes-journal-app-wake" and the engine's,
  through `SyncTestAppDelegate`; `remote-notification` is in
  `Info-SyncTest.plist` only, the production `Info.plist` line added in
  `3de231a` was taken out again — ordinary builds have no CloudKit or push
  entitlement, no engine, no subscription and no
  `registerForRemoteNotifications`; `#if SYNCTEST` until 2026-11-04, since
  then compiled everywhere with the engine built, and push asked for, only
  once sync is turned on), on the
  foreground, on a 75 s poll while the app is active (pushes are Apple's
  and best effort: four sends took eight minutes to arrive by push on
  2026-11-03, C-147), and from the diagnostics; a file is fetched by name
  only where it is new here, never when the file held matches the
  server's hash. One catch-up runs at a time. A hold change rebuilds
  nothing: a change of reason is a status change, held → allowed releases
  what waited and asks for a send. Outgoing work is unchanged: a send is
  asked for 1.5 s after each queue and after each catch-up, which is also
  the retry for deferred sends. Recovery is defined in
  `JournalCatchUp.recovery(for:)`: a transient error waits for the next
  trigger; an expired zone token clears it and re-reads the whole zone
  records-only (the one unavoidable full fetch); a missing or deleted
  zone drops engine state and tokens and rebuilds fresh, the zone
  recreated on the next send. The account decision before every fetch,
  send and activation, `isCurrent` for engine events, and the dormant
  states (unlink, removal, account mismatch) are untouched. What the app
  enforces is which records it hands to CloudKit and which files it
  fetches; a transfer CloudKit has already begun finishes on its own
  schedule, mobile data included, and the app cannot pause or cancel it
  (C-148): a 132 MB upload begun on Wi-Fi at 12:04:57 survived the cut to
  mobile data and was on the server by 12:08:13 with no app counter
  showing any of it, so "Media over mobile data off" means no NEW file
  transfer starts on mobile data. A rebuilt engine (account transitions
  only, now) asks the server which files it already holds before its
  first batch, so such an upload is not sent again.
  (7) *Removal wording* (SYNCTEST): "Remove Études Data from This Device",
  confirm word REMOVE, and the confirmation says the private iCloud
  journal and other devices are unchanged, sync is turned off on this
  device and re-enabling can download the journal again; the Connected
  deletion keeps its backend behaviour and says it does not erase the
  private iCloud journal or copies on other devices. The binding is kept
  after removal; "delete everywhere" is not built (Samuel). (8) *Missing
  score file* (C-140, production): `ScoreLibraryStore.missingFileIDs`; the
  row says "Unavailable on this device — file missing", a tap explains and
  does not open, the entry is kept; the Profile sync rows count them; the
  scan records `scoresWithoutFile`; C-139 unchanged.
  **Reconciliation rules, for the record.** *Initial* (the first scan after
  the build, or the first time two existing devices meet): a pre-existing
  setting or list context goes up without a clock and two unclocked copies
  go to whichever reached the server first (the other device's values are
  listed as displaced, copy-only); the instrument map is the union with the
  first upload standing on a clash; nothing is deleted. *Later edits*: the
  newer clock wins the whole small record, ties go to the server, the
  displaced value is kept for recovery; a restoration is a new clocked edit.
  Unit tests: `SyncTestSettingsSyncTests` (14), `SyncTestTransferGateTests`
  (5), `C138ScoreLibraryTests` +1 (C-140). Totals reconciled 2026-10-28:
  stage I's "143" was the ten SyncTest suites plus `C138ScoreLibraryTests`,
  `C5ScoreAdoptionIdentityTests`, `SchemeConfigurationGuardTests` and
  `PDFScoreEffectOrderingTests` (30 production score tests); the first
  stage J count, "132", was the SyncTest suites plus `C138` only, so the
  drop was a narrower selection, not lost tests. The stage I selection
  plus the stage J suites and `StoreMigrationCompatibilityTests` is now
  165 tests green under the SyncTest configuration. The
  full-target run also shows seven order-dependent sharing tests
  (`JournalDeleteQueuedPublishTests`, `P6I02…`, `P6I03…`) that pass in
  isolation, as recorded under "Test hygiene".
  Final totals 2026-11-03 on `31bb9e9`: the same selection is 170 tests
  green under SyncTest (the five added: unsent-edit-only displacement for
  the profile and avatar, the catch-up serialiser and recovery map, the
  file-carrying types and the no-refetch rule); Debug and Release build.
  **Device run (iPhone "SD iPhone" and iPad, both Sync Test installs, iOS
  and iPadOS 27.0.1; 2026-10-28 on 1867–1870, 2026-11-03 on 1871–1880;
  evidence is each device's state file read over the cable, never a
  network counter):** *Section 1, settings* — Journal Tint and primary
  activity both ways, identical clocks on both state files; an explicit
  reset to the default travels; an offline edit sent once on reconnect;
  tool toggles stayed per device. Rule learnt: a device at a default
  sends nothing at the transition, so an explicit value beats a default.
  *Section 2, list contexts* — Viola held different ids on the two devices
  and shared one record; default list, autofill off and a typed preset
  both ways; an offline default change sent once; a Lute instrument and
  its context arriving together created the instrument first. *Section 3,
  colours* — two clashes: on the first the sanitiser moved the FIRST
  upload's label (fixed `0c82b23`: the later device's own new label
  relocates to the next free slot, the first upload stands); on the
  second both new labels wrapped to the shared fifth slot, maps identical
  on both, one send each, stable across relaunch; thread colours matched
  once primed from the same screen. *Section 4, recovery* — a conflicting
  notes edit, a profile name and a profile photo each displaced on the
  loser with Copy and Restore; each Restore went up as a new clocked edit
  and the other device applied it as a plain import. Found and fixed:
  the loser's ordinary later edit appeared on the WINNER's list with
  Restore (C-144, profile, avatar, settings, list contexts, score
  metadata: displaced only while this device's save is unsent); the same
  photo uploaded twice (C-145). *Section 5, mobile data* — step 3 held
  the iPad's photo, profile photo and score ("3 to receive") and the
  iPhone's own photo ("1 to send") while text, the score rename, the
  tint and a deletion crossed; released once each by the option (step 6)
  and by joining Wi-Fi (step 7), avatar byte counter up by exactly the
  two profile photos; the held state survived two relaunches (step 5);
  Low Data Mode paused media with the option on, on Wi-Fi (both devices,
  since iCloud syncs the network setting) and on mobile data, and
  released on Standard (step 8); the hotspot step was not exercised
  (Device A has no data plan; the rule is unit-tested and a real
  hotspot-flagged path on 2026-10-28 held and released correctly). Found
  and fixed in this section: the push wait (C-147), the in-flight upload
  resent by a rebuilt engine and fetched back on release (C-148), and the
  engine's own re-fetch of everything with files on each return to
  automatic sync (C-149, the mechanism change above). *Section 6,
  missing score file* — the item stayed listed as unavailable with the
  count at 1, took a rename from the iPhone while unavailable, and the
  iPhone's re-send restored exactly the missing file (203,871 bytes
  written); the re-send route uploads the whole library (19.7 MB), so
  C-150 proposes self-restore from the server. *Section 7, device-only
  removal* — the confirmation text as designed; after REMOVE three
  launches logged no fetch, send or subscription save, server knowledge
  and tokens cleared, the binding kept; Re-enable brought everything back
  once (160 records, 47 files). The onboarding name typed before
  re-enabling beat the cloud name by the newer-clock rule: **C-151,
  unresolved**, not accepted as user behaviour. *C-149 re-run on 1880
  (R1–R7, 14:00–14:32, about 45 minutes with the build):* pushes, the
  poll and the foreground each drove a catch-up; seven deletions arrived
  by poll and push; held downloads and uploads released once by the
  option and by Wi-Fi; offline work survived two relaunches and went up
  once; Low Data Mode paused and released; removal and re-enable as in
  section 7 with the first fetch app-driven. Counters over the whole
  re-run: the iPhone downloaded 6,314,487 bytes, exactly what the iPad
  sent, and the iPad 12,322,719 bytes, exactly what the iPhone sent; echo
  bytes and echo records 0 on both devices; every file fetched by name
  once. One unavoidable records-only read of the whole zone happened on
  the iPad at the 1880 launch (its zone token had never been established
  under the old mechanism; 0 files). Also seen: an offline notes edit on
  the iPhone displaced when the iPad added a photo to the SAME entry
  (whole-record rule, known), and the status says "Running" rather than
  "offline" in Airplane Mode (polish, not done). *Remaining limitations:*
  the whole-record rule for a session when one device edits text and the
  other adds media; the four-colour palette shares a slot from the fifth
  label on; thread colours primed per screen; an in-flight transfer is
  CloudKit's (C-148); the derived avatar is 256 points at screen scale
  (C-146); the re-send route for a missing score uploads the library
  (C-150); C-151 (fixed 2026-11-03, below); C-143 (Lists manager popover, production, iOS 27).
  **C-151 workflow, built 2026-11-03 (unit-tested; device verification is
  Samuel's call).** Two halves, SYNCTEST only. *Online restoration:* the
  set-up screen shows a card above the name field (`SyncTestRestoreCard`,
  rule `JournalRestoreOffer.decide`, pure): after a device-only removal,
  "Restore from iCloud" re-enables sync from there (the binding was kept),
  the first fetch fills the empty Profile row and links the primary
  instrument to it (the import now creates the row before it resolves the
  instrument), so the set-up gate closes by itself and the name step is
  skipped; a cloud name arriving while the screen is up replaces the field
  with a note; while the first fetch is pending the card says so and
  offers a retry after a failed catch-up; while sync is paused it names the
  reason; after a complete fetch with no cloud profile it says so. *Offline
  setup:* a profile edit found by the scan before this device's first
  complete fetch, while no cloud profile has reached it (narrowed
  2026-11-03: an edit after a cloud profile arrived through a rejected
  send is a real edit), is clocked but **provisional** (`profileStampProvisional`
  in the state file, shown on the diagnostics' Profile clock row): it
  merges as UNCLOCKED, so a clocked cloud profile wins the whole record
  and the typed name and instrument are on the Displaced by sync list with
  Restore (a new clocked edit, which wins everywhere); against an unclocked
  cloud profile (every pre-existing profile after the stage H transition,
  until edited) each cloud field that holds anything wins outright and the
  typed values fill only what the cloud lacks (corrected 2026-11-03: the
  first build used the established profiles' length tie-break here, so a
  longer typed name would have replaced the cloud name on both devices,
  listed as displaced but still overwritten; `SyncTestProfileTests` +1, the
  selection 181 tests green under SyncTest). The mark
  clears at every profile import and at the first complete fetch, where a
  typed clock stands if the cloud holds no profile (logged). The outgoing
  record still carries the clock, so a first device's typed profile is a
  real one. Unit tests: `SyncTestProfileTests` +2 (the device scenario of
  section 7 with "Temp" against "Name A", restore, the pure rule both
  ways; the online restore with the gate's two conditions and the offer's
  states). The selection is 172 tests green under SyncTest; Debug and
  Release build. **Device run PASSED 2026-11-03 on build 1883 (`c083bcd`
  plus the record commit and `e2f394c`'s files in the tree), iPad and
  iPhone "SD iPhone", both Sync Test installs; evidence is each state file
  read over the cable, in the notes folder under `c151-state`.** Step 0:
  the iPhone put "Name A" back (both devices held "Temp" from the
  afternoon's defect); the iPad took it by push. *Section A, online:* iPad
  removal 15:01:29; after relaunch the set-up card offered the restore and
  "Sync re-enabled for a removed local copy" 15:01:40 came from it; engine
  built fresh; "Profile record: server newer; applied → Name A"; first
  complete fetch 15:01:43 (161 records, 13 deletions, 47 files); no
  "Profile edited" line, outbox empty, no Displaced entry, both devices on
  the same profile clock (15:00:43, the iPhone's edit); the set-up screen
  closed by itself. *Section B, offline:* iPad removal 15:03:36; Airplane
  Mode; relaunch, offer tapped 15:04:08 (engine built, every send failed
  with CKError 3, network); "Temp" and "Piano" typed at 15:04:38 and
  15:04:43, both logged "(before the first complete fetch: provisional,
  yields to a cloud profile)"; on reconnect the first fetch 15:05:18
  applied "Name A" with "(typed before the first complete fetch:
  unclocked)", the typed profile was never sent (the 6 records sent after
  were the instrument, lists and list contexts), and the iPad holds one
  Displaced entry: Name (this device) "Temp", Instrument (this device)
  "Piano", unclocked, with Restore; the iPhone's profile is unchanged (same
  clock, same values). Seen, not a defect: the instrument "Piano" added at
  set-up travelled to the iPhone as an ordinary instrument record (stage
  C's rule; the profile's primary is what C-151 governs); and the status
  says "Running" while offline, the sends failing with CKError 3 (polish,
  already noted). Not exercised: Restore on the entry (section 4 of the
  stage J run covered a profile-name restore); the entry was left for
  Samuel. Commit note: `c083bcd` and `5db7b7e` also carry the storage-full
  session's then-uncommitted hunks in the shared engine, state, diagnostics
  and Profile-section files and its C-152 row; `e2f394c` completes them.
  **iCloud storage-full handling, built 2026-11-03 (C-152; simulated
  refusals only): PASSED on device 2026-11-03, build 1885 (`2812754`),
  iPhone "SD iPhone" and iPad Sync Test installs.** `CKSyncEngine` does not
  retry `quotaExceeded` and drops the change from its pending list; the
  outbox kept it but nothing re-queued it before the next activation, and
  every refusal was logged twice per attempt. Now: `JournalSendFailure`
  names what each failed save means; `JournalStorageFull` keeps one
  episode per full period in the state file, begun by the first refused
  record or zone save and logged once (later refusals counted in the
  diagnostics); the one send path waits for its cadence (2, 4, 8, then
  every 15 min after each refusal for a push or poll; a 2-minute floor for
  a change, the foreground, activation or a backgrounding; "Send now"
  ignores it), re-adds the whole outbox the engine dropped and sends once,
  in the builder's order; the episode ends on an accepted save (a deletion
  or zone save alone counts only when nothing waits), logged once;
  fetches, held media and the journal untouched. Profile: "Running ·
  iCloud storage full" and what waits; diagnostics: state, next attempt,
  episodes, and a 10-minute simulation that refuses every send locally
  exactly as a real refusal reaches the app (nothing sent to the server;
  in memory only). `SyncTestStorageFullTests` (8). The selection is 180
  tests green under SyncTest; Debug and Release build. Note: the C-151
  commits (`c083bcd`, `5db7b7e`) carried this work's engine, state file,
  diagnostics and Profile edits and the C-152 row from the shared
  checkout; the helper and test files landed with the storage-full commit.
  Device script: side-session notes, `storage-full-device-script.md`.
  **Step 0 before integration (focused review, 2026-11-03; C-153 to
  C-159): built and unit-verified 2026-11-03; device scenarios below.**
  The review (three read-only passes over the deleting paths, the catch-up
  token, pending work and displaced-text recovery; report in the
  side-session notes) found six defects in the data-loss category, all in
  `MOTIVO/SyncTest/`: B1 the catch-up applied an older server copy, or the
  device's own echoed write, over a newer local edit when no save was
  pending (C-153); B2 an accepted older send cleared a newer pending edit
  from the outbox and a kill then lost it (C-154); B3 import conflicts were
  decided from the import context's stale copy and recorded the stale text
  as displaced (C-155); B4 a history-processing run straddling a removal
  could queue the removal's own deletions for the next re-enable (C-156,
  suspected, guarded); B5 a fetch in flight re-imported the journal after a
  device-only removal (C-157); B6 a record whose file fetch failed was
  imported without its file and left behind the token (C-158). Of the
  eight hardening items H1–H5 are fixed (failed state-file writes and a
  rolled-back import save keep the zone token; a server win waits for its
  recovery entry to be on disk; a recovered removal leaves the profile and
  library unclocked; the zone save is queued after the reconcile) and
  H6–H8 deferred as noise and a bounded leak (C-159). Reproductions:
  `SyncTestStep0Tests` ran first against the unfixed code and failed on
  B1, B3 (with a retained registered object: "typed here" replaced by
  "other device", displaced text "v1"), B5, B6 and H2 exactly as the
  scenarios predicted; B4's race was not reproduced and stays suspected
  (its guard is tested through a hook between the read and the commit);
  B2's pure rule is tested. After the fixes the selection is 192 tests
  green under SyncTest (11 new); Debug and Release build. Three product
  decisions are set out as scenarios in the report (a cleared iCloud zone,
  what a lost session keeps, ownerless entries) and nothing here depends
  on them.
  **Device scenarios, build 1888 (`765d2ea`), iPhone "SD iPhone" and iPad
  Sync Test installs, 2026-11-03 19:22–19:40 (state files over the cable):**
  *(a) offline notes edit meets a photo added to the same entry* — order 1
  (iPhone edit newer): the deferred edit went up once on reconnect, the
  iPad imported it, no displaced entry on either device; order 2 (iPad
  photo newer): the whole-record rule applied, both photos on both devices,
  the iPhone listed "Notes (this device)" with exactly the typed text
  ("E / iPhone notes, order 2"), Restore went up as one record and the
  iPad applied it, entry resolved. Own-write echoes skipped on both devices
  after every send ("Own-write echo: n record(s) already held, skipped";
  iPhone echoes +4, iPad +3); bytes received equal to the other device's
  upload exactly (1,137,683 and 2,357,000). *(b) remove during a fetch* —
  two attempts: the iPad's fetch of a 132 MB video (19:32:37) and of an
  84 MB video (19:39:02) each completed before REMOVE could be reached
  (8 s and 24 s later), and the restore's first fetch (172 records,
  51 files) took 5 s, so the in-flight case is NOT reachable by hand on
  this Wi-Fi; both removals were clean (outbox empty, no deletion queued,
  server knowledge cleared), two relaunches each stayed paused with no
  fetch or send, "Restore from iCloud" on the set-up card brought the full
  journal back both times with the set-up screen closing by itself, and
  the iPhone's counters and log show no deletion applied. B5's guard and
  C-156's second guard therefore stand on the unit tests and the code
  reading; the removal and restore paths are device-verified. *(c) file
  fetch cut mid-catch-up* — not attempted: the same two-second fetches
  leave no window to cut; B6 stands on `testB6` (hold and refusal) and
  the stage J section 5 device evidence for the hold-and-release path it
  reuses. Hands-on: Samuel ≈ 20 min at the devices for (a) and (b) plus
  ≈ 10 min for the storage-full check earlier; agent ≈ 1 h 10 min for the
  review's fixes, tests and records, the rest waiting on builds.
  **Independent review of Step 0 (Codex, 2026-11-03) and its six items,
  C-160 to C-165: fixed and unit-verified 2026-11-03.** R1 a removal whose
  marker could not be saved went on deleting; R2 the lifecycle was checked
  once before the import sequence, not at each family or the token commit;
  R3 a record's change tag was recorded before the batch's save, so a
  rolled-back save made the retry skip it as an echo; R4 a re-created
  outbox entry reused revision zero, so an old acknowledgement settled a
  newer edit; R5 the rejected-send handler overwrote local text without a
  saved recovery entry; R6 a held download was released after the fetch,
  not after a durable import. Method: the seams the tests need (the
  catch-up's apply sequence and the media release's apply half as callable
  steps with a hook between families, a change-tag seam, a Bool from the
  removal entry point, a test-only current-user) were added first with no
  behaviour change, `SyncTestStep0ReviewTests` ran against them, then the
  fixes went in. **Genuine pre-fix reproductions: R2, R3, R5** (the later
  families and the first-fetch state applied after the removal; the retried
  record skipped as an echo; the local text overwritten). **R1, R4 and R6
  failed in that first run for test-setup reasons, not the defect** (an
  unstarted engine has no iCloud user, so its decisions refused anyway; the
  importer's queue is held weakly and the test had dropped it; the test's
  view context lacked the app's merge policy), so their pre-fix failure is
  not demonstrated here: R1 is source-traced (the old entry point called
  `goDormant(currentDecision())`, a no-op for an allowed account); R4's rule
  failure was reproduced by Codex in an isolated check; R6 is source-traced
  (every fetched name was removed from the hold). All six pass against the
  fixes through their calling paths. The six fixes: a refused removal
  stops transport and `LocalFactoryReset.perform` erases nothing and says
  so; every record family and the token commit check the generation at
  their own boundary, the synchronous ones under an import lock that the
  removal entry point also takes, the main-actor ones inside their
  main-actor step; known change tags and system fields are written after
  the batch's save (a copy the local side won over is still recorded at
  once, so the resend carries the server's tag); one persisted monotonic
  outbox sequence; the rejected-send handler keeps the edit queued when the
  recovery entry or the save fails; a hold is released only for a durably
  applied record; the knowledge is committed inside the importer's own
  `save()`, so a direct caller gets the same contract as a batch. Two
  pre-existing tests moved with the contract: `SyncTestMetadataTests`
  gained the save its scenario implied before reading the server's change
  tag, and `SyncTestReceiverTests` needed the in-batch meta knowledge the
  importer now keeps until the save. Tests: `SyncTestStep0ReviewTests` (6)
  plus `SyncTestStep0Tests` B2 rewritten to relative revision
  comparisons; the selection is 198 tests
  green under SyncTest; Debug and Release build. Not changed on device
  (no install); the import lock's interaction with a removal on the main
  thread is covered by `testR2` and by reading, not by a device run.
  *Device evidence (state files over the cable, 17:24–17:34):* with the
  simulation on, the iPhone's first refused send at 17:25:56 logged ONE
  episode line (3 saves refused, 3 waiting); three later bursts of edits
  (eight changes in all: five sessions, a Thought's photo with its meta
  record, two deletions) added no line; a change 2 min 4 s after the
  refusal was allowed one attempt (refused, counted as attempt 2, not
  logged); a foreground 50 s after that did nothing; a foreground 2 min
  50 s after it made attempt 3; Profile read "Running · iCloud storage
  full" with the waiting line. End simulation at 17:32:08; the foreground
  at 17:33:17 (past the 2-minute floor) sent for real: "Sent 6 record(s);
  1 media upload(s), 2,597,715 bytes" and "iCloud storage available again
  after 3 refused attempt(s)". Counters: iPhone `recordsSent` +6 (the six
  saves, once), `assetUploads` +1; iPad `recordsReceived` +6 in one push
  catch-up with the 2 deletions and 1 file, `assetBytesDownloaded` up by
  exactly the photo's 2,597,715 bytes, no held attachment (the session
  arrived with it), no duplicate. The iPad showed no episode. Not
  exercised: sections 4 (held media under the full state, mobile data)
  and 5 (zone refusal), both unit-covered only.
  **Independent review of Step 0, round 2 (Codex, 2026-11-03), four items,
  C-166 to C-169: fixed and unit-verified 2026-11-03.** R7 a replacement
  file whose copy failed still counted as an applied import (row applied,
  previous file removed, server hash recorded, download hold released);
  R8 instrument and custom rows were known before their save (C-162's
  gap, so a rolled-back save made the retry skip them); R9 the
  attachment-metadata branch of the rejected-send handler lacked C-164's
  guards (no recovery entry, save failure ignored, pending send dropped);
  R10 the deferred list, score and settings rejected-send handlers had no
  lifecycle check. Same method: the one seam needed (the three deferred
  handlers as one callable step carrying the generation it snapshots)
  went in first with no behaviour change; **all four are genuine pre-fix
  reproductions** — on `eb4cd55` the four tests failed through their
  calling paths exactly as the review predicted (17 assertion failures,
  none for set-up reasons) — and pass against the fixes. The fixes: media
  is put in place through a staging copy BEFORE the row is touched, and
  the previous file's removal and the new hash are committed only with
  the row's save (a failed copy changes nothing and the record is fetched
  again); instrument and custom rows use the after-save knowledge; the
  metadata branch mirrors the session/attachment contract (a migrated
  transition copy is simply superseded, as the catch-up does); the
  deferred handlers check the generation inside their apply step. R10's
  test drives the list branch; the score and settings branches share its
  guard and are source-traced. **Codex's check of `d0062cb` left three
  bounded cases, R11–R13 (C-166 extended, C-170), fixed and
  unit-verified 2026-11-03, each reproduced first on `d0062cb`:** R11 a
  copy failing in the ordinary catch-up let the batch complete and
  advance its token with no retry (the record is now held by name in
  `awaitingMedia`; a hold that cannot be written leaves the batch
  incomplete, so the token is kept); R12 a replacement at the row's own
  materialised path overwrote its bytes before the recovery entry and
  the save (the previous bytes are now moved beside the file, named by
  the hash they belong to, put back on a rolled-back save or a refused
  conflict, and removed only after the save; tested with the recovery
  write failing and with the database save failing); R13 the custom-row
  and Instrument branch of `resolveSendConflict` recorded the server copy
  as known, ignored a failed save and dropped the pending send (now
  known and settled only once the save is committed, so a resend
  meanwhile is rejected and resolved again). Tests:
  `SyncTestStep0ReviewTests` (13); the selection is 205 tests green under
  SyncTest; Debug and Release build. No device run.
  **Follow-ups before main-build integration (agreed 2026-11-03), both
  done:** the bounded C-151 workflow (device-verified on build 1883 except
  the unclocked-cloud-profile case, unit only by decision) and the iCloud
  storage-full handling and recovery (above; simulated quota failures only).
  **Main-build integration, sync OFF by default (2026-11-04; C-171 to
  C-173):** the 20 files under `MOTIVO/SyncTest/` compile in every
  configuration and the 45 `#if SYNCTEST` hooks in production code are
  gone; one compile-time fact remains, `JournalSyncCapability.buildSupportsSync`,
  true only for the isolated SyncTest configuration, which alone carries the
  container entitlement, the push entitlement and the `remote-notification`
  mode (its bundle id, entitlements, Info.plist and development container are
  unchanged; Debug and Release carry none of them). The switch is the state
  file: with none, `JournalSyncCoordinator.startIfNeeded` builds nothing — no
  state store, no engine (the only place a `CKContainer` is made), no push
  registration (now asked for only once an engine exists), and the metadata,
  profile and score mirrors at the app's write points are inert — so a person
  who never turns sync on, and App Review, see the app exactly as it was.
  Turning it on (Profile → "iCloud sync (trial)" toggle, or the set-up card
  "Turn on iCloud sync", offered before a name is asked for so a second
  device restores instead of typing a name that is then displaced) writes
  the file with the history token fast-forwarded to that moment (C-173: with
  no token the history is read from its beginning, deletions included) and
  builds the engine; off is the stage E unlink (journal kept, edits tracked,
  nothing moves); a device-only removal leaves the file, so the restore card
  and the interrupted-removal recovery work as before, and the erase bracket
  answers "nothing to bracket" with no store (C-171: it would have refused
  every ordinary erase). Persistent history tracking and the `app`
  transaction author are on for every build (a tracked store cannot go back,
  and the switch must work without a relaunch); with sync off nobody reads
  the history (it grows slowly; pruning is a later optimisation). The
  ownerless-entry filter and the removal wording follow "sync in use" at
  runtime (P3 stays open). The diagnostics screen and the two destructive
  diagnostics are `#if DEBUG`. Existing trial installs keep syncing (their
  files exist). Tests: `SyncOffByDefaultTests` runs in every configuration —
  a fresh install starts nothing and leaves no directory; local use with
  sync off (insert, edit, delete, every write-point hook, the erase bracket,
  a disable) changes nothing beyond the app's own history transactions; two
  source guards (only the engine makes a `CKContainer` or `CKSyncEngine`,
  only the coordinator builds an engine, push registration goes through the
  coordinator, one `#if SYNCTEST` left) and a configuration guard (Debug and
  Release use `MOTIVO.entitlements` and `Info.plist` with no iCloud, push or
  `remote-notification`; the trial entitlements name only the trial
  container) — and, under SyncTest, the switch write, the fast-forward (a
  row made and deleted before the switch is never read back), the next
  launch starting from the file, and off = unlink with the file kept. The
  selection (15 `SyncTest*` suites, `C138ScoreLibraryTests`,
  `SyncOffByDefaultTests`) is 180 tests green under SyncTest; Debug and
  Release build; the ordinary Debug `MOTIVOTests` run is 1,199 tests with
  the known order-dependent failures only (7 cases in
  `JournalDeleteQueuedPublishTests`, `P6I02…` and `P6I03…`, all green when
  their three suites run alone: 56 of 56). Tools for the trial, read-only on the device:
  `docs/sync-trial/compare_containers.py` (two container copies compared
  field by field: sessions, attachments and their order, instrument and
  directory names, profile row, file hashes, privacy map, chosen defaults),
  `load_container_copy.sh` and `pull_container_copy.sh` (file by file over
  the cable).
  **Populated upgrade trial, Device A (iPhone 16e "SD beta burner", Sync
  Test install, trial iCloud account; 2026-11-04 13:39–13:56; C-174):**
  fixture = the verified 2026-10-18 Études Dev container copy (112 sessions,
  83 attachments, 102 Documents files incl. 7 scores, 832 MB, the privacy
  map, four avatar files, its UserDefaults with 45 Connected/backend keys
  dropped and 594 kept; store pre-V11, no history tracking), loaded file by
  file into a never-launched install of build 1893 (111 files, every size
  checked; devicectl makes the missing directories). *In-place upgrade,
  sync off:* first open showed the journal at once (no set-up screen), 112
  entries, the profile, 8 instruments, the sync toggle OFF; photo, video,
  audio and PDF entries, Scores (7) and the Lists manager opened; force-quit
  and reopen the same. The Lists manager was empty: the fixture's lists are
  keyed by the Études Dev owner scope and the owner key had been cleared, so
  the ownerless device looks under "device" — they came back once ownership
  adoption ran (below). Container pull #1 compared with the fixture by
  `compare_containers.py`: **0 failures** — every session and attachment
  field, attachment order, instrument and directory names, profile row, all
  102 file hashes, the privacy map and the chosen defaults identical; the
  store now V11 with history tracking on and one empty, author-less
  transaction (the migration's touch); no `SyncTest` directory and no state
  file on disk (sync off leaves no trace). *Turning sync on:* 13:52:13 the
  switch written, bootstrap 278 records + 121 directory rows, the metadata
  migration (7 titles, 79 privacy choices, 3 page selections), the meta,
  profile, tint, instrument-colour, scores (7 with files) and list-context
  transitions each logged once; 13:52:14 first fetch (empty zone), owner
  adopted (`000703…`, no Connected service), 13 lists queued; **13:52:18 the
  app crashed** (C-174: CloudKit's precondition at the entry of
  `CKSyncEngine.sendChanges`, best read as a second send fired 1.5 s into
  the 760 MB first upload after the engine's own account-change event re-ran
  activation; symbolised against the 23G83 device symbols); 13:52:23 the
  relaunch rebuilt the engine from saved state and sent 250 + 89 records with
  79 + 4 media uploads, 763,335,211 bytes, by 13:52:34; the next catch-up
  echo-skipped the device's own 295 records; outbox 0, conflicts 0, 339
  records known. Two relaunches: every counter delta 0, nothing re-sent or
  re-imported. Container pull #2 compared with the fixture: **0 failures, 2
  notes** — no edit stamps (`userModifiedAt` 0 of 112) and the 7 titles moved
  from the title store onto `displayName`, each equal to the store's entry.
  The fix (`JournalSendGate`, one send in flight) went into build 1894.
  **Receiver, iPad Pro 11" M4 (fresh Sync Test install, same trial account;
  14:08–14:12; C-175, C-176):** build 1894's set-up screen showed no "Turn
  on iCloud sync" card (C-175: the card started empty and SwiftUI never ran
  its appear-time decision; reproduced on the simulator, fixed in 1895 and
  verified there); on 1895 the card appeared, "Turn on iCloud sync" with no
  name typed: 14:08:20 switch written, bootstrap 0, engine built, first
  fetch; 14:12:02 one pass imported 339 records and 91 files
  (763,335,211 bytes, exactly Device A's upload), created the 8 instruments,
  merged the profile field by field (no clock on either side), applied the
  avatar, 7 scores with files and reading positions, 9 settings and 13
  lists; first complete fetch finished, owner adopted (`000703…`), the
  set-up screen closed by itself; outbox 0, nothing held, conflicts 0. After
  adoption it re-sent its 13 lists and 7 list-context settings unclocked
  (24 records, the stage J transition on a new owner scope); Device A
  reads them as "same values". Container pull #3 compared with the fixture
  as a receiver: **0 failures** — every session and attachment field,
  attachment order, instrument and directory names, profile row, all 83
  attachment files and 7 scores identical by content (materialised as
  `<id>.<ext>`, by design), the privacy choices of every existing
  attachment, the 7 score-library items, the 3 live page selections, the 13
  lists under the owner scope identical. Not synced, by design or gap: the
  fixture's one Connected ensemble; stale privacy, page and title entries
  for attachments that no longer exist (763, 28 and 30). Hands-on: the
  entries, scores, lists and profile checked on the iPad; **one difference
  found: an audio entry Device A titles "Little fugue in A minor" showed its
  UUID** — 13 of the fixture's recordings predate the title store and carry
  their typed name only as the file name, which the sync does not carry
  (C-176: fixed in 1896 by a one-off pass that moves such a stem onto
  `displayName`). *On 1896 (14:28):* Device A's launch ran the pass once
  ("File-name titles: 10 recording(s)…", the other 3 named files already
  had stored titles), sent 10 records; the iPad imported them by push 6 s
  later and its store and title store hold all 13 titles (checked over the
  cable); the open journal screen showed the new title only after a
  relaunch (C-177, carried: an imported title does not refresh an open
  screen). Relaunches on both: counters unchanged apart from those records;
  conflicts 0 throughout. *Pair (14:31–14:33):* a Thought with a photo on
  Device A went up as 3 records and one 12,672,323-byte upload and the iPad
  imported the 3 records with the file; the iPad's notes edit went up as 1
  record and Device A imported it a second later; a Thought made on the iPad
  by mistake and deleted went up and netted out (Device A never saw it);
  own-write echoes skipped on both, outbox 0, conflicts 0. **Outcome:** the
  in-place upgrade of a real, populated, pre-V11 store and the first-time
  history tracking, transitions and bootstrap are device-verified field by
  field, as is a fresh receiver's cold import; four findings in the run
  (C-174 crash at first send, C-175 missing set-up card, C-176 file-named
  titles, C-177 screen refresh), three fixed and verified on device in the
  same run, one carried. Both installs now run 1896 with the fixture journal
  on the trial account (the new baseline); Device B's Sync Test was deleted
  for the run. Hands-on: Samuel ≈ 1 h 15 min across Parts 1–4 (incl. the
  iCloud account switch and three reinstalls); agent ≈ 3 h of which the
  three 800 MB container pulls and the upload/import waits were ≈ 40 min.
  **Independent review through `3158850` (Codex, 2026-11-04):** no new
  data-safety blocker; sync stays off by default and Debug and Release
  cannot enable it. Carried: the comparator's gaps (a receiver's missing
  media is a note, not a failure; avatar files and profile preferences are
  not covered), so "0 failures" alone is not enough for a future trial
  without the hands-on checks; C-174 is a plausible mitigation, not a
  verified root cause. Decided (Samuel, 2026-11-04): P3 stays as tested
  (ownerless entries visible only while sync is in use); ensembles stay
  outside the private sync, with Connected, and the wording says so; C-177
  fixed first, then the set-up card and Profile toggle wording (sync is
  optional, needs the same iCloud account, off keeps local data and stops
  transfers, what was uploaded stays in iCloud). **Both done 2026-11-04
  (`0d75ff1`, build 1898 on Device A and the iPad):** C-177 device-checked
  — a recording renamed "Am Fugue" on the iPad changed on Device A's open
  journal with no relaunch; the set-up card and the Profile toggle carry
  the agreed wording (and name ensembles as Connected's). Selection 182
  tests green; Debug and Release build.
  **TestFlight preparation (2026-11-04; C-178 to C-180) — built and tested:**
  (1) the comparator's gaps closed (C-178): a receiver's missing media fails,
  the avatar PNGs are compared by content, and location, name, primary
  instrument, Journal Tint, the instrument colour map, primary activity, the
  Lists contexts, favourites, saved Lists, the score index, recording titles
  and page selections are compared by meaning; self-tested on the trial's
  copies (copy2 upgraded: 0 failures; copy3 receiver: exactly the 10 C-176
  titles it genuinely lacked when pulled; a clone with one video and the
  avatars removed: fails on both). (2) The person-facing status (C-179):
  `JournalSyncStatusSummary`, pure from the state file and three facts the
  engine now publishes (the network path, the first fetch's progress, the
  last transient send failure): "Restoring from iCloud" with records → files
  → applying counts on the Status row and the set-up card; "Still to upload:
  n entries, m files (x MB) and k other changes"; "Offline" in plain words;
  "Waiting for Wi-Fi" / "Media paused by Low Data Mode" with the action;
  "Signed out of iCloud", "Linked to a different iCloud account" and "iCloud
  storage is full" with what to do; "Up to date" only when nothing waits.
  Engine rules unchanged; `SyncTestStatusSummaryTests` (8). (3) The
  container identifier per configuration (C-180): the build setting
  `ETUDES_CLOUDKIT_CONTAINER` → Info.plist `EtudesCloudKitContainer` →
  `JournalSyncCapability`; SyncTest sets the trial container (read back from
  the built bundle), Debug and Release unset; the guard test ties the
  setting to each configuration's entitlements, push and
  `remote-notification`, and checks what the running bundle resolved.
  Selection 190 tests green under SyncTest (16 `SyncTest*` suites,
  `C138ScoreLibraryTests`, `SyncOffByDefaultTests`; the source guard now
  asserts NO `#if SYNCTEST` is left in the app); Debug and Release build;
  ordinary Debug `MOTIVOTests` 1,199 tests with the known order-dependent
  failures only (the same 7 cases). **Prepared, waiting on
  Samuel (nothing applied):** `docs/sync-trial/production-configuration.md`
  — App ID `com.sdsongs.etudes` (iCloud/CloudKit with the NEW container
  `iCloud.com.sdsongs.etudes`, Push), the Release enablement as
  `docs/sync-trial/production-configuration.patch` (a Release-only
  `MOTIVO-Release.entitlements` with `aps-environment`, the container and
  CloudKit; `remote-notification` in `Info.plist`; the build setting in the
  Release configuration), the CloudKit schema (every record type and field
  the engine writes, listed; `cktool` export from the trial container →
  validate → import into the production container's Development
  environment → deploy to Production in the Console, with a check after
  each step), and the recommendation that Release's flag flips at the
  checkpoint by applying the patch in one commit, never before the schema
  is in Production. Privacy policy and terms: the replacement text for
  optional sync, device-only removal, the Connected deletion's split and
  ensembles staying outside is drafted beside the current text in
  `docs/sync-trial/policy-drafts-icloud-sync.md` (the Desktop drafts and
  the website still say journal data stays on the iPhone and that a
  Connected deletion erases it). The checkpoint itself: section D below.
  **Correction pass (2026-11-05, Codex's six findings on the preparation;
  C-181):** (1) "rollback at any time" withdrawn — withdrawing the
  capability after sync was used, then an erase, then restoring it would
  have sent the erase as cloud deletions; the erase bracket now opens the
  state store on a build that cannot sync, tested in every configuration
  (C-181). (2) The checkpoint script separates the purchase's fresh Sandbox
  tester from the Sign in with Apple identity (the device's Apple Account),
  and requires the backend user to be verified disposable before the
  Connected test and its deletion. (3) "Up to date" is never said after a
  failed or incomplete later check or while records are held for data
  that has not arrived; regression test added (C-179). (4) The comparator
  checks that each score's index entry names the right file by content and
  that an upgraded device's original avatar photo is untouched; both
  demonstrated false passes now fail (C-178). (5) A Release fixture with
  the preferences as `com.sdsongs.etudes.plist`, and the bundle and both
  plist arguments explicit in every cable and comparator command. (6) The
  configuration guard checks the running configuration by bundle id, so
  Debug stays disabled after Release enablement (C-180). Policy drafts:
  the deletion wording covers a person who turned sync on once and off
  since. C-174's root cause stays unverified. Selection 192 tests green
  under SyncTest; Debug and Release build; the ordinary Debug run is 1,200
  tests (the erase test runs there too) with the same 7 known
  order-dependent failures only.
  **Follow-up (2026-11-05, Codex's two remaining findings; C-182, C-183):**
  the set-up screen's restore card now decides "nothing" on any build that
  cannot sync (after an erase the remembered state is unlinked and would
  have been offered), and `reenable` guards the capability — the
  every-configuration erase test continues through the card's own decision
  path and the restore action: no engine, no push registration. The
  displayed status is refreshed on the catch-up's failure branch and on
  every exit of the import batch; a SyncTest test drives the real engine
  from "Up to date" through an incomplete import and a real failed
  CloudKit fetch, reading the status object. Selection 193 tests green
  under SyncTest; Debug and Release build; `SyncOffByDefaultTests` (6)
  green in Debug too. Carried: the engine-path status test needs a
  simulator with NO iCloud account signed in (its real catch-up must fail
  at CloudKit); and C-174's root cause remains unverified — the mitigation
  is defensive, and the preflight and checkpoint record a recurrence rather
  than explain it away.
  **Production cloud configuration done (Samuel, 2026-11-10; C-184):** App
  ID capabilities and the new container; the schema deployed to Production
  after a correction — the trial container's export lacked
  `Session.userInstrumentLabel`, `Session.userActivityLabel` and
  `Score.sourceAttachmentID` (Codex found them), because CloudKit's
  Development environment creates a field only when a non-nil value is
  saved and the trial journal never held one; the preparation document had
  wrongly called the trial schema complete. All three added as STRING. The
  Production export equals the corrected Development export byte for byte
  and `docs/sync-trial/check_schema.py` (new: the code's 15 record types and
  73 fields against an export) reports 0 gaps on it and exactly those three
  on the original. A Development-environment preflight cannot catch this
  kind of gap (fields appear just in time there), so the checker is the
  gate before any Production build sends.
  **Release preflight, Device A (iPhone 16e "SD beta burner", Études
  Release, development-signed, the production container's Development
  environment, Samuel's main iCloud account; 2026-11-10 14:51–15:35;
  C-185, C-186):** the enablement patch applied as `50135a5` (**build
  1906**). Before any device step: selection 193 green under SyncTest; the
  ordinary Debug run 1,200 tests with the 7 known failures only, its
  configuration guard passing in the Debug host with Release enabled; the
  built Debug bundle carries no container, the built Release bundle
  `iCloud.com.sdsongs.etudes` and `remote-notification`; the device build
  signed with `aps-environment`, the container and CloudKit under
  "iOS Team Provisioning Profile: com.sdsongs.etudes" (the proof the App ID
  step took). Device A's Études 1818 replaced (confirmed disposable; Device
  B untouched) and the Release fixture loaded into the never-launched
  install: 111 files, every size equal, 835,899,008 bytes, 54 s.
  *First open, attempt 1 — a test-setup failure (C-185):* no entries, no
  avatar and an age-range prompt. A Connected sign-in from September
  (Apple user `001325…`, backend user `F0BA3610…`, Samuel's second Apple
  ID) had survived the app's deletion in the Keychain, so the journal
  filter hid the fixture's `000703…` entries; the data was intact (112
  sessions over the cable) and the publish queue empty. Release has no way
  to drop an owner key but the erase, and with the sign-in held the erase
  is Delete Account: Samuel chose to delete that test account (its
  revocation sheet would have presented his main Apple ID; cancelled, so
  revocation was not attempted and the deletion ran on the stored session,
  as designed). Reinstalled, fixture reloaded (111 files verified).
  *First open, attempt 2, sync off:* the journal at once, 112 entries, the
  profile and avatar, toggle off, no age prompt; over the cable no state
  file, no identity key, the age-gate result untouched. Container pull A
  compared with the fixture (`--role upgraded`, both plists explicit):
  **0 failures** — sessions, attachments and order, directories, the
  profile row, 102 file hashes, both avatar images and originals, the
  preferences; store V11 with history tracking.
  *Explicit enablement (15:19:02):* each transition logged once; the first
  fetch failed "zone does not exist" (a new container; see C-186); the
  engine's account-change event fired at 15:19:03, the moment that
  preceded C-174's trap in the trial, and nothing trapped; 250 records
  with 14 files (327,958,337 bytes) at 15:19:11 and 69 records with 69
  files (435,376,874 bytes) at 15:19:15 — 763,335,211 bytes, the trial's
  figure; the poll at 15:20:2x completed the first fetch (own records
  echo-skipped), the owner key was adopted and 21 more records (lists,
  their contexts) went up: 340 sent, 339 known, outbox 0, conflicts 0, no
  crash. **C-174 did not recur; its root cause remains unverified** (one
  clean run under the gate is not a reproduction of the absence).
  *Relaunches (15:22:16, 15:22:42):* "Up to date" at once; every counter
  delta 0. Container pull B compared with the fixture: **0 failures**, 10
  notes (17 titles moved onto `displayName`, one instrument colour from
  the union).
  *Status wording on the device:* "Up to date — Everything on this device
  is in iCloud" after the upload; **Offline** with what waits (Airplane
  Mode; a Thought queued 15:26:09, its saves deferred, sent 15:26:30);
  **Waiting for Wi-Fi** — "1 file (2.9 MB) to send. Text and settings
  still sync. Turn on Media over mobile data below to send and receive
  them now" (option off, Wi-Fi off, 4G signal: upload held 15:32:51, sent
  3 s after Wi-Fi returned); and the row left "Up to date" by itself when
  a later check failed (C-183 on a device). Two wording faults, C-186. An
  earlier step-7 attempt was void: the "Media over mobile data" option had
  been switched on on the device, so a 12.7 MB photo rightly went over 4G.
  End state: 349 records, 779,221,867 bytes sent, conflicts 0, no
  storage-full episode. (Every "bytes sent" figure in this record and the
  next is the app's counter: the sizes of the files in records the server
  acknowledged. It is not measured network traffic.) Evidence (two container copies, both comparison
  reports, the enablement timeline, state snapshots):
  `~/Library/Application Support/Claude/side-session-notes/local_6d93116d-9187-4503-8840-a388a10459a9/preflight-2026-11-10/`.
  Not exercised: Low Data Mode wording, a second device, anything on
  Production or TestFlight. **Carried to the checkpoint:** Device A now
  signs in with Apple as Samuel's MAIN identity, so the checkpoint's
  Connected part needs a disposable Apple Account decided first; and the
  script gains a "clear any earlier sign-in before the fixture" step.
  **Internal TestFlight checkpoint, parts 2 to 4 (Device A and the iPad,
  TestFlight build 1908 from commit `9dd52ff`, the Production environment,
  Samuel's main Apple Account; 2026-11-10 17:18–21:09; C-187 to C-189):**
  *The archive.* Built from a clean tree as `Etudes 1908 (9dd52ff)`. An App
  Store Connect export of it (TestFlight Internal Only, not uploaded) was
  read: bundle `com.sdsongs.etudes` 1.0 (1908), the one container
  `iCloud.com.sdsongs.etudes`, `icloud-container-environment` Production,
  `aps-environment` production, `get-task-allow` false, Cloud Managed
  Apple Distribution with the team's store profile, no StoreKit file.
  Samuel uploaded the same archive from Organizer, which signs its own
  export: the uploaded bytes themselves were not read.
  *Accounts.* Device A and the iPad show the same Apple Account in
  Settings, and both state files are bound to the same user record
  (`_cd4f590c…`) in the production container.
  *Part 2, the populated upgrade with sync off.* The preflight's install
  (sync on, Development) was deleted, never updated in place; build 1906
  reinstalled, the fixture loaded (111 files, 835,899,008 bytes, each by
  size) and opened once: journal, profile and avatar on screen, toggle
  off, no state file, no sign-in in the preferences, container copy
  against the fixture **0 failures**. TestFlight 1908 installed over it:
  the device reports 1908, all 102 media files are present by size, still
  no state file, the toggle still off.
  *Part 3, explicit enablement on Production.* On at about 20:17:54; the
  first fetch found no zone (the C-186 wording again: "Restoring from
  iCloud" with the raw text for 78 s); the account-change event fired and
  nothing trapped; 250 records by 20:18:04 and 89 more with all 83 media
  by 20:18:08 (339 records, 763,335,211 bytes); first complete fetch
  20:19:12; outbox 0, conflicts 0, no crash log. **What the figures do
  and do not show.** 763,335,211 is the sum of the sizes of the files in
  the records the server acknowledged; network traffic was not measured.
  All 83 media were acknowledged within about 5 s of the first batch (13 s
  in the preflight, 11 s in the 2026-11-04 trial after its relaunch). A
  hypothesis, not established: iCloud already held this content for the
  account, so little was transferred. Either way, no run so far has kept
  an upload active for minutes while further sends were asked for, so the
  one-send gate has not been shown under a sustained upload, and
  **C-174's root cause remains unverified**. A trial with media this
  account has never stored is prepared
  (`sustained-upload-trial-script.md`). Two relaunches: every counter
  unchanged.
  *Part 4, restoration on the iPad and edits both ways.* A deviation
  first (C-187): the fresh install asked for an age range on the set-up
  screen, because the iPad's Keychain still held a Connected sign-in to a
  backend user that no longer exists (`ab70e211…`: 0 users, 0 directory
  rows, read by Samuel; his real account is `0f33f6b8…`). Études was
  closed with the card unanswered; at the next launch the app had dropped
  the sign-in itself and the red button read "Remove Études Data from
  This Device". Restore from the set-up card 20:42:24 to 20:48:16 (5 min
  52 s): 339 records, 91 files, 763,335,211 bytes of files delivered to
  the app (the same figure as Device A's acknowledged sizes), nothing held, conflicts 0, one owner with a matching
  key, nothing sent back. Container copy against the fixture as a
  receiver: sessions, attachments, every media file by content, scores,
  lists, settings, profile and avatars equal; one flag, explained
  (C-189). On screen: the four media kinds, 7 scores, lists, the profile,
  8 instruments and the recording's title all right. Push works on
  Production: two reading positions from the iPad reached Device A in
  about 3 s each. A Thought with a photo from Device A (4,112,329 bytes,
  a real upload, 3 s) was on the iPad 2 s later with its file; the iPad's
  notes edit and a rename showed on Device A's open journal within 3 s
  (C-177 holds); the iPad's deletion was applied on Device A in 1 s. Two
  relaunches on both: "Up to date" at once, nothing re-sent.
  *Samuel's real Connected account* was read twice by Samuel: at
  20:41:48, which is 36 s before the restoration began (20:42:24) but
  about 8 minutes after the iPad's first launch with the dead sign-in
  held (about 20:33), and at 21:11:52, after the run. Every value was
  identical (name, location, no avatar key, the 8 instruments, 1 post,
  last sign-in 2026-10-16, and the same `auth.users.updated_at`,
  2026-11-10 15:31:21 UTC). So the row did not change between the two
  reads, which cover the restoration and the edits. That is weaker than
  "nothing wrote to it": a write of identical values would not show, the
  first launch precedes the baseline, and no API log was read. What
  stands beside it: neither test install held credentials for that
  account (Device A no sign-in at all; the iPad's was for a user that no
  longer exists). The 15:31 timestamp predates the iPad install by five
  hours and was not made by Device A; Samuel thinks he opened Études on
  Device B that day, which is the likely cause, not an established one.
  *Omitted or not exercised:* part 5 (blocked on a disposable identity;
  its old steps also relied on an `updated_at` column that
  `account_directory` does not have, replaced in the prepared script by
  row values, the avatar object and the write log); Low Data Mode
  wording; Offline and Waiting for Wi-Fi under TestFlight (seen in the
  preflight only); a sustained upload. C-186 and C-188 are carried as
  limitations of the internal trial. Evidence (the export's entitlements, two container copies and
  comparison reports, both timelines, state snapshots, the account
  reads):
  `~/Library/Application Support/Claude/side-session-notes/local_6d93116d-9187-4503-8840-a388a10459a9/testflight-2026-11-10/`.
  **Sustained-upload trial (Device A sender, the iPad receiver, TestFlight
  build 1912 from commit `f26de0a`, Production, Samuel's main Apple
  Account; 2026-11-11 13:37–14:21; C-190, C-191):** the first run with
  the send-gate observation, on media this account had never stored and
  an uplink capped at 2 Mbps (Network Link Conditioner on Device A).
  *Baseline:* both installs on 1912, every queue empty, the kept-request
  counter at 0; every figure below is a change from it.
  *Fresh media:* five videos recorded in Études with Airplane Mode on and
  Wi-Fi off (the sends were refused with CloudKit's network-unavailable
  error). Read from the state file before release: **5 files, 174,818,100
  bytes**, 15 records queued, nothing acknowledged. Floor at 2 Mbps: 699 s.
  *The upload was sustained.* Released at about 13:52:31; two minutes
  later nothing was acknowledged. It finished at 14:09:22, 16 min 51 s
  after release, across three sends.
  *Sends asked for during it were kept, 13 times, and none trapped.* The
  first send kept six requests (the app's own checks at 34.2, 111.6 and
  187.3 s; a notes edit at 207.6 s; a new Thought at 244.6 s; a return to
  the foreground at 284.9 s). Each is a line in the log with the time the
  send had been in flight and five attachment records still unsent.
  *Interruption one, a force-quit* after those: relaunch at 13:58:06
  rebuilt the engine from saved state, a new send began two seconds
  later with all 18 records still queued, and kept five more requests,
  among them another notes edit at 214.5 s.
  *Interruption two, the connection* after that: Airplane Mode with Wi-Fi
  off; the send failed with network-unavailable after 396.4 s in flight,
  the kept request ran once and failed the same way, every record stayed
  queued. After the connection returned the next send began at the next
  poll, about a minute later, not at once (C-186(c) again); it kept two
  more requests and was acknowledged after 200.2 s: **19 records, 5
  files, 174,818,100 bytes, each once**.
  *Receiver:* the iPad imported the 19 records and fetched the five files
  (174,818,100 bytes) by 14:09:52.
  *Content, from both containers pulled over the cable:* the five videos
  identical by SHA-256 and size, each present once on each device; 118
  sessions and 88 attachments on each, every id unique, the same sets
  (no duplicate journal items); outbox, waiting files and held records
  empty on both; conflicts 0. The comparator's two flags are explained
  and not losses: C-189, and C-191 (the stored colour map; Samuel
  compared the colours on screen and they match). Two relaunches on each
  device: "Up to date" at once and every counter unchanged. No crash log
  on either device.
  *What this does and does not show.* The one-send gate held while an
  upload stayed active for minutes and further sends were asked for,
  through two interruptions, on this build and these devices. **It does
  not establish C-174's root cause, which remains unverified**: the trap
  did not occur, so nothing was learned about why it once did. The last
  send's 200 s for 174.8 MB is quicker than the cap allows alone; the
  three sends together ran for about 15 minutes, so the likeliest reading
  is that iCloud kept the parts sent before each interruption. That is
  inferred from the timings, not measured. Evidence (both timelines, the
  full event logs, state snapshots, both container copies, the
  comparison):
  `~/Library/Application Support/Claude/side-session-notes/local_6d93116d-9187-4503-8840-a388a10459a9/upload-trial-2026-11-11/`.
  **Part 5, a Connected member with sync on (Device A and a dedicated
  simulator, development-signed Release build 1914 from `2e19e07`, the
  disposable Apple Account `contact@samuel-dixon.com`; 2026-11-11
  14:33–17:03; C-192 to C-194). Coverage: the production container's
  Development CloudKit environment only; no TestFlight build and nothing
  on Production CloudKit. The backend is the production Supabase project.**
  **Result: the run completed. An imported location reached the backend
  three times out of three; an imported avatar never did. A location
  typed by hand was undone by the app twice. Deletion removed only the
  disposable account, and its iCloud journal restored.**
  *Preparation, as corrected after Codex's review.* Device A held no
  Connected identity but its preferences named Samuel's `000703…` as the
  journal's owner in 26 places. Samuel ran the app's own "Remove Études
  Data from This Device" (log: "no deletions queued… the cloud journal is
  untouched"; the iPad's record counts did not move; afterwards no Apple
  identity in the preferences). Études was then deleted, Device A signed
  in to the disposable account, a fresh Sandbox Apple Account added, and
  a new simulator signed in to the same account. Backend before any
  sign-in: two users, Samuel's and a beta tester's.
  *Stage A, passed.* First open: set-up screen, no age card, no owner, no
  backend id, no state file. A Solo journal (four entries, a photo, an
  audio recording, "Alpha", an avatar) had no owner in the store before
  sync was turned on. Sync on: 10 records, bound to iCloud user
  `_ec5579ae…` (not the main account's), "Ownerless journal". **The
  simulator is a usable second device for this container:** it restored
  10 records and 3 files in about 5 s, stayed Solo, sent an edit that
  reached Device A in 1 s by push, and received one from Device A in 73 s
  at its poll (a simulator gets no push).
  *Stage B.* The first two tries at joining were refused by the adult
  gate as `unconfirmed_adult`. The cause was not C-113: the fresh Sandbox
  Apple Account's **Age Assurance** fixture was unset, and a
  development-signed build takes its age answer from there. With Revoke
  App Consent and the fixture set to 18+ confirmed, the join went through
  (the gate was not altered). Identity verified in full: one new user,
  **X = `fae6cdb8-4dc8-411c-ba8a-a79966b479ef`**, created 15:45:05, whose
  Apple `provider_id` and `sub` equal the id on the device,
  `001325.eec54efbacdd44f9b733754d3f136e2b.1755`, character for character;
  the journal's four entries adopted that owner and stayed listed on both
  devices. Calibration: a hand edit of the location and of the avatar
  showed in the database read (location, `avatar_version`, the object's
  etag, size and time) and in the write log filtered by the user, so both
  checks detect a write.
  *A control, and the first unexpected result (C-193).* Opening Profile
  on Device A with nothing pending and nothing typed put the old location
  back: the field showed "Alpha", not the "Alpha Two" typed eight minutes
  before, and the app wrote "Alpha" to the backend, the device and iCloud
  (PATCH at 15:58:26 in a burst that re-read the signed-in user and the
  membership binding).
  *Stage C, the measurement* (every read compared on its values, leaving
  out the read time and `entitled_until`, which Apple's renewals move):
  | | Backend location | Backend avatar object |
  |---|---|---|
  | B0, 16:04:11 | Alpha | 97,219 bytes, version 15:50:20 |
  | B1, import one ("Beta" and a photo), Profile closed | **Beta** | unchanged |
  | B2, then Profile opened, left, force-quit, reopened | Beta | unchanged |
  | B3, import two ("Delta" and a photo), Profile held open | **Delta** | unchanged |
  | B4, hand edits ("Gamma" typed, a new photo) | **Delta** | **changed** (90,520 bytes, version 16:18:32) |
  Device A received each import by push within a second or two and
  showed it, in place when Profile was open. The write log shows a PATCH
  to `account_directory` from X whenever an avatar import arrived, the
  app returned to the foreground or Profile was opened or left, each with
  a re-read of the signed-in user; no upload to the avatar bucket except
  the hand edits'. **So an imported location reaches the directory row
  (C-192), and an imported avatar does not.** At B4 the avatar edit held
  and the typed "Gamma" was replaced 15 s later by "Delta", the value in
  the device's local location slot (C-193 again).
  *Samuel's reading, recorded as his:* a Connected member's profile is
  one profile and is shared by design; the only privacy control is "Let
  other members find you". On that reading the location following the
  member is expected and the avatar staying behind is the inconsistency.
  The sync was built and unit-tested on the opposite rule (an import
  never publishes). The fields disagreed with each other either way.
  He decided the same day: one shared profile (the rerun record below).
  *Stage D.* Before deletion: Device A still held X exactly, its outbox
  was empty, and Device A, iCloud and the simulator agreed on "Delta" and
  the final avatar. Deviations: the script asked for "Gamma" to be there,
  which the app had undone; and Device A showed one displaced-photo entry
  (C-194). Samuel deleted the account at 16:26:34 (Apple asked for a
  sign-in first, naming the disposable account). After: no user X, no
  directory row, no avatar object, no posts; the user list is the two
  from the start, identical; **Samuel's own row identical to the
  reference in every column at every read of the run**. Device A: no
  backend id, no Apple identity, "no deletions queued… the cloud journal
  is untouched", the binding kept; the simulator's journal untouched.
  Restoration from the set-up card at 17:01:59: 12 records and 3 files in
  2 s, the same four entries by id as on the simulator, "Delta" and the
  final avatar, Solo, no age card and no sign-in prompt, outbox empty,
  conflicts 0.
  *Left as it is, on Samuel's word only:* Device A and the simulator on
  the disposable account with the small journal, sync on, Development
  environment; the Sandbox Apple Account. Evidence (state and preference
  snapshots at each step, every backend read as pasted):
  `~/Library/Application Support/Claude/side-session-notes/local_6d93116d-9187-4503-8840-a388a10459a9/part5-2026-11-11/`.
  **Part 5 rerun: one shared profile (C-192) and typed locations (C-193),
  2026-11-11 18:50–19:50, builds 1917 (`d2c9c32`) and 1918 (`27f799d`).**
  A policy change and its test, not a second verdict on the run above.
  *Decision (Samuel):* Études has one shared profile; a profile change
  arriving through iCloud, from a Solo device included, updates the same
  owner's Connected profile, location and avatar alike; a Solo device
  gains no Connected credentials and publishes nothing. Coverage as
  before: **Development CloudKit only** (development-signed Release on
  Device A, the simulator "Etudes Part 5", the disposable Apple Account);
  the production Supabase project. Script
  `part5-rerun-shared-profile-script.md`, same notes folder.
  *Identity.* Before: the two known users only. A fresh Sandbox purchaser.
  The join at 19:09:03 made exactly one new user, **X2 =
  `0d569065-a369-476a-83e8-ddb99a4466ac`**, whose Apple identity equals
  the one on the device character for character (`001325…1755`, the
  disposable account, as in the first run). Samuel's row was identical to
  its reference at the start, after the join and at the end.
  | Case | Device A | Backend row and avatar object |
  |---|---|---|
  | Solo, before the join (1917): simulator sets "Hotel" and a photo | received by push 18:54:26; avatar marked for publication; no backend id | no user exists |
  | Join (1917) | marker cleared | location **Hotel**; object uploaded 19:09:16 but **avatar_key NULL** (the finding below) |
  | M1, import with Profile closed (1918): "India" and a photo | applied 19:22:22 and 19:23:18, untouched | **India**; object 19:23:18, key set, version 19:23:23 |
  | M2, import with Profile open (1918): "Juliet" and a photo | both changed on the open screen, 19:36:03 and 19:36:12 | **Juliet**; object and version 19:36:13 |
  | M3, typed "Kilo" and a chosen photo on Device A (1918) | sent 19:41:28 and 19:41:47 | **Kilo**; object and version 19:41:42 |
  | M3 after background, reopening Profile, force-quit and relaunch | "Kilo" and the photo throughout (Samuel); both location keys "Kilo" | identical to the read before, in every value |
  | M4, three and a half idle minutes (19:44:40–19:48:14) | no counter changed on either device | identical again at 19:49:29 |
  *Found at the join, fixed in `27f799d`.* The Solo-held location was
  published and the photo was uploaded, but the row's `avatar_key` and
  `avatar_version` were NULL: the pending avatar is promoted before the
  first directory row exists, the key PATCH matched no row, PostgREST
  answered success and the marker was cleared. The patch must now return
  the row, and the first-row hydration promotes again once the row is
  published. **The join was not repeated on build 1918** (it needs another
  new user): on a device this fix has unit-test cover only. X2's key was
  set by the next avatar publish (M1).
  *No loop, and the same profile everywhere.* Device A sent nothing
  through iCloud after any import-driven publish (records sent stayed at
  26 through the join, M1 and M2; the two at M3 are the typed edit). The
  simulator received "Kilo" and the photo at 19:42:28. At the end both
  devices show "Kilo", and the avatar file is byte-identical in all four
  copies (identity and local copy on each; SHA-256 `b0fc173d76cdbd06…`).
  Conflicts 0 on Device A; the simulator's 1 is the first run's.
  No photo change arrived as a removal first in this run (C-194 stays
  open; its path is covered by unit test only).
  *Not covered:* Production CloudKit and TestFlight; two Connected devices
  with sync on (the loop guard between them rests on unit tests and the
  code); a Connected device with sync off changing the avatar, which a
  sync-on device did not pick up at this build (corrected in the pass
  below); the fixed join on a device (run in the pass below).
  *Left at the end of this run:* X2 in production (private posts on, 0
  posts, "let other members find you" off), Device A Connected as X2 on
  build 1918 and the simulator Solo; X2 was used again and then deleted by
  Samuel in the pass below. Evidence:
  `…/part5-rerun-2026-11-11/` in the same notes folder.
  **Avatar correction pass after Codex's review, 2026-11-11 20:40 to
  2026-11-12 12:00, builds 1920 (`d6543e9`) and 1922 (`62bc081`).** Three
  device checks, on verified disposable users only; coverage as before,
  **Development CloudKit only**. Plan, the guarded script and every read:
  `…/avatar-pass-2026-11-11/` in the same notes folder.
  *What changed (C-192, second pass).* The blanket "no read-back while sync
  is on" is replaced: a device records the version its own publication
  produced, follows only a newer one, treats a newer version showing the
  picture it already holds as an echo (nothing written), and applies a
  different picture or a removal at once with sync off and after it has
  stood two minutes with sync on. The pending-avatar marker changes under
  one lock. A waiting photo is attached whenever any write evidences the
  owner's row.
  *Second device.* The simulator cannot pass Apple's age check, so it
  cannot be Connected. By Samuel's decision the "other device" was the
  backend itself: he ran `backend_avatar_edit.sh`, which makes the app's
  own two writes in the app's order as the service role, guarded to the one
  disposable user. **Two physical Connected devices were not tested**; the
  pair is covered by `TwoConnectedPublishersTests`, a model on the app's
  own decision functions. The iPad was not switched; the age gate was not
  bypassed.
  | Check | Device A (sync on) | Backend afterwards |
  |---|---|---|
  | First launch on 1920, user X2: the standing photo | downloaded, measured as the picture it holds, version recorded; files unchanged, nothing sent | unchanged since 19:41 |
  | **Replacement** made on the backend 20:47:44 | relaunched 20:48:13; new picture written 20:50:21 (the two-minute wait); sent through iCloud once; simulator had it 20:51:15, byte-identical | version still 20:47:44: not published back |
  | **Removal** made on the backend 20:52:58 | relaunched 20:54:19; photo removed 20:56:29; sent once; simulator removed it 20:57:53 | key NULL, version still 20:52:58, no object |
  | **Fresh join**, build 1920, user X3 (21:12:46) | photo uploaded 21:13:02, key patch matched no row, marker kept | **failed**: row present, avatar_key NULL five and fifteen minutes later |
  | The same user after installing 1922 | attached at the launch, 21:29:21; publication recorded; nothing sent | key and version set |
  | **Fresh join**, build 1922, user X4 (2026-11-12 11:54:51) | no relaunch, no edit; marker cleared; version 11:55:05.496451 recorded | **passed**: key set, version 11:55:05.496451, object 11:55:05, 14 s after the account was created |
  *The failure on 1920 and its fix (`62bc081`).* The own row has three
  writers (the hydration snapshot, the Profile screen, set-up). `27f799d`
  promoted again only after the hydration's own publish; at that join the
  row was created by another writer and an idle app never retried. Now the
  one profile write announces an evidenced own row and the account attaches
  a waiting photo then.
  *Identities.* Each join used a fresh Sandbox purchaser and was verified
  before anything was measured: X3 `ce8b7689-…` and X4 `e56086bc-…`, each
  exactly one new user with the disposable address and Apple identity
  `001325…1755`. X2 and X3 were deleted by Samuel in the app (X3 while its
  membership was lapsed); the user list returned to the original two each
  time. Samuel's own row was identical to its reference at every read.
  *Not covered:* two physical Connected devices; a real second device
  making the backend change; Production CloudKit and TestFlight. *Limits
  of the design:* a real change reaches a sync-on device two minutes after
  the launch that first sees it; a replacement so close to the held
  picture that it measures the same (tolerance 6 of 255 on a 32 x 32
  rendering) is treated as an echo; each Connected device still publishes
  an imported change once. C-194 stays deferred.
  *Left as it is, on Samuel's word only:* **X4 exists in production**
  (photo attached, private posts on, 0 posts); Device A Connected as X4 on
  build 1922, the simulator Solo, both on the disposable account; four
  Sandbox Apple Accounts used.
  **Avatar safety, third pass after Codex's results review, 2026-11-12
  (`492da2f`). Automated tests only; no device was used, by instruction.
  The join evidence above stands as it was.**
  *A replacement delayed beyond the wait was a lasting deletion, two
  ways.* (a) A device whose iCloud is behind applied a published removal
  after the wait and clocked it "now", so the replacement, chosen earlier
  and delivered late, lost to it on every device. A change read back from
  the Connected profile is now clocked a millisecond after the state it
  displaces, so it loses to anything newer the journal brings. (b) A
  device with the journal's removal of the OLD photo waiting published it
  over the NEW photo another device had already published. A removal is
  now published only when the profile still shows the picture it removes
  (`AvatarRemovalGuard`, by a remembered rendering of the removed photo);
  otherwise it is withdrawn and the profile's photo comes to the device.
  *The read-back's check and write are one step* under the lock the
  sync's writers take, so an iCloud import lands before or after, never
  between. The Profile screen's own fill uses the same writer.
  *Found by the new overlap test: a deadlock present since `d6543e9`.* The
  avatar marker was a UserDefaults value written under that lock; its
  change notification waits for the main thread when posted from the
  sync's thread, and the main thread hung if it asked for the lock
  meanwhile. The marker is now a small file. **Builds 1920 and 1922 carry
  this hazard** (Device A and the simulator only; it did not occur in the
  runs above). Neither has been replaced.
  *Tests.* Six tests reproduced the two issues on `6c6006e` before the fix
  (log kept beside the evidence, `third-pass-reproduction-before-fix.log`).
  Full target on `492da2f`: 1,424 tests (SyncTest scheme), 1,231 (Debug),
  the seven known order-dependent failures; C-195 in one of three runs.
  *Limits that remain:* none of this pass ran on a device or with two
  real Connected devices; an OLDER PHOTO published late over a newer one
  (not a removal) can still be read back as a real replacement after the
  wait; a removal made by hand on a device whose profile shows a photo
  that device has not yet seen is withdrawn and has to be made again; the
  check before publishing a removal and the removal itself are two
  requests, milliseconds apart. C-194 stays deferred.
  **Avatar safety, fourth pass, 2026-11-12 (`16d6170`): an outdated
  removal against a newer publication. Automated tests only.** The last
  limit above was the fault: after a removal's check and before its
  deletion, another device could publish a new photo, and the removal
  then deleted that photo's image (it has one fixed name) and cleared its
  reference. Five tests reproduced it on `b33fdae`
  (`fourth-pass-reproduction-before-fix.log`). *The fix:* every write of
  the avatar reference is conditional on `avatar_version`, the stamp the
  server puts on each reference write, as a filter on the request, so the
  server checks and writes in one statement. A removal writes the
  reference first and deletes the image only once that write is
  accepted; a refused write deletes nothing and the device looks again.
  A publication reads the version before storing the image, and if its
  reference write is refused (a removal landed in between) it stores the
  image again. *This reverses C-33's order* (image first), which is what
  deleted the newer photo; a failed image delete now leaves an image with
  no reference until the device retries (the marker is kept), and account
  deletion sweeps the folder in any case (B-20). Full target: 1,431 tests
  (SyncTest scheme), 1,233 (Debug), the seven known failures.
  *What it cannot close:* the storage API has no conditional delete. If
  this device's reference write is accepted and its one delete request,
  already sent, reaches the server only after the other device has been
  refused, read again, stored again and written its reference, that
  image is deleted with its reference set. Closed by the next entry: an
  image name per upload, so a delete names exactly one image.
  **An avatar image name per upload, and B-48, 2026-11-12 (`4c8a4c1`
  server files, `a38a72b` app and tests). The server change is PREPARED
  AND NOT APPLIED.** Each upload
  is stored as `users/<uid>/avatar-<32 hex>.jpg`, written once and never
  overwritten, and every delete names one image, so a delete that arrives
  late can only remove the old one. The old fixed name stays valid and is
  never written by this build. *What the device deletes* is decided by a
  record it keeps in a file (`AvatarWorkLedger`), after Codex's
  correction: the exact image a reference write of its own displaced,
  whoever stored it, once the server accepted that write; and its own
  uploads whose reference write can no longer be accepted or was never
  sent. An image whose reference write is pending, failed, or was made
  with its answer lost is never deleted: it stays on record until a read
  of the row shows a strictly later version and another reference. A
  delete that fails stays on record and is retried at the next
  publication, removal, or first read of the row after launch. *The
  record comes first* (final correction after Codex's review of the
  implementation, same day): no upload and no reference write is sent
  unless its record has been written to the file, and memory never holds
  more than the file. A failed write stops that attempt, and any retry,
  before the request; a record that exists and cannot be read stops
  everything and is not written over. Before this a failed write was
  ignored, a reference write could go out with only the upload on
  record, and the clean-up after a restart deleted that image while the
  request was pending. *B-48,*
  found while planning this: `avatar_key` was unchecked text and two
  service-role sweeps delete what it names; a CHECK now ties it to the
  row's own folder. *Server:* migration `20261112120000`, preflight,
  apply and policy-only rollback in `supabase/sql/` with
  `README-b48-avatar-names-deployment.md`. The rollback keeps the
  ownership constraint (Codex's second correction) and refuses while any
  per-upload image exists. **Order: server first** (a new build cannot
  publish a photo against the old INSERT policy). Codex's SQL review
  passed 2026-11-12; Samuel runs the preflight and then the apply. *Evidence, all local:* `supabase/tests/b48/rehearse.sh`, 78
  checks with real member sessions (guards, storage policies, the
  reference check, rollback); `p6-single-delete/e2e.sh`, 82 checks (both
  Edge Functions, unchanged, remove a referenced image and a second one
  in the folder, either form); the fidelity gate differs from the
  snapshot in exactly the two policies and the constraint. App: 101
  focused tests, among them the delayed delete outlasting another
  device's refused and repeated publication, for a removal and for a
  replacement, and the unanswered, lost-answer and late-arriving
  reference writes, and a record that cannot be written or read (those
  fail with the old fault put back: 25 assertions). Full target, run
  before the final correction: 1,453 tests (SyncTest scheme), 1,252
  (Debug), the seven known order-dependent failures and no other (the
  local Supabase stack was up, so the tests that need it ran). After it:
  the focused tests on both schemes, and the Release build.
  *Not covered:* guarantees hold between builds from this one on (an
  older build still overwrites the fixed name and writes without a
  condition); an older PHOTO published late over a newer one can still
  be read back as a replacement; an image left by a device that never
  runs again, or a fixed-name image an older build left unreferenced,
  stays until account deletion or expiry (decision D4); nothing ran on a
  device or against the hosted backend. First real use is at the
  internal TestFlight checkpoint (D5).
- Code slimming when next touched: unused `DirectoryWriteKind.generation` and
  `.creation`; the age-band code once the adult-only gate replaces it.
- Deprecation and warning sweeps.
- **Sampled cello drone** (agreed 2026-10-09; a good first update). A second
  drone sound beside the synth tone, driven by the same pitch, A4 reference
  and volume controls: a looped, crossfaded sampler in place of
  `DroneRenderKernel`, nearest recorded note retuned. Record it in-house, and
  get a short written release from the cellist. Recording spec: one note
  every 3 semitones from cello C2 upwards (about 13–15 files), 8–15 s
  steady sustain with the attack, no vibrato, tuned to A=440, WAV 48 kHz
  24-bit mono, dry or lightly roomy, matched levels, named like
  `cello_C2.wav`. Open: how to cover A5–A6, above the cello (recorded
  harmonics, or the option stops at the cello's range). Adds about 2–5 MB.
  New audio engine, so write a one-page scope first. Loop quality needs
  listening on a device. Copy mentions it only once it ships.
- **Manuscript sketch as a Thought** (idea 2026-10-11; scope agreed
  2026-10-16, about 3–4 agent-weeks for a single page, about 1 more for
  additional pages). Digital manuscript paper with freehand drawing, finger
  or Pencil; no recognition, engraving, playback or symbol editing. Paper,
  chosen before drawing: single staff with printed treble, bass, alto or no
  clef; piano (paired staves, clefs and braces printed); plain. Printed
  clefs are part of the paper, not a symbol palette. Controls: pen with a few
  thicknesses, eraser, undo/redo, zoom/pan, save/discard, recovery of
  unfinished work. Fixed page size and staff positions; screen size and
  orientation change the view, never the staves. A sketch button on the
  timer page opens the pad without starting the timer; a sketch is a
  **fourth staged kind** (`StagingStore` knows audio, video and image) in
  the existing hand-off (`TimerThoughtHandoff.swift`): Save Thought before
  the timer starts, absorbed into the session if the timer is started, a
  normal session attachment during a session. Saved Thoughts are never
  absorbed by a later Start (true today; pin with a test). Output is a PDF
  (`AttachmentKind.pdf` already flows through editor, viewer, journal rows
  and sharing) with the editable `PKDrawing` kept as a sidecar keyed by
  attachment id, which must follow the editor's staged-to-final id
  migration; reopening and editing regenerates the PDF and thumbnail.
  Sharing a viewable PDF is enough; exchanging editable sketches is out of
  scope. No separate sketchbook screen.
- **Score markup** (scope agreed 2026-10-16, about 2.5–3.5 agent-weeks).
  Draw and erase over PDFs in the Scores library through PDFKit's
  `PDFPageOverlayViewProvider` with a `PKCanvasView` per page on the
  existing single-page viewer; read-only until Markup is entered; Pencil
  draws and a finger turns pages when a Pencil is paired. Editable ink kept
  per (score UUID, page) beside the Scores directory with a manifest;
  save/discard and recovery. Sharing exports a **flattened copy**; the
  source PDF is never altered. No revision history, per-session snapshots,
  score-first Practice or page turners. Open questions: the overlay's
  behaviour under single-page mode and autoscaling (a 2–3 day spike settles
  it); clef glyph source for the sketch paper (paths, or a bundled OFL
  font); exported ink is raster at a chosen scale.
  **Design consideration, not an approved layout (2026-10-11):** when
  manuscript capture arrives, reassess PTV's capture controls together rather
  than adding another row. Consider a stave/pen or treble-clef launch icon,
  clearly distinct from the musical-note session-setup control, and direct
  access to written thoughts alongside audio, video and manuscript.
- A suspended member lands in Solo with no explanation. Optional: a short
  "account suspended, contact support" message.
- Block is per device. "Reply to all commenters" still fans out server-side to
  a blocked commenter. It's rare, and they can no longer see the post.
- Test hygiene: 3–7 order-dependent "ownerless/signed-out" tests
  (`P6I02…`, `P6I03…`, `JournalDeleteQueuedPublishTests`) fail in full-suite
  runs at `5c77beb` and pass when run alone.
