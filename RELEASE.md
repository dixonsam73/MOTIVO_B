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
  all `#if SYNCTEST`) on Device B and the iPad Pro 11" M4 (iPadOS 27.0.1),
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
  after the catch-up; C-133). **Observed, not fixed:** once, after a
  relaunch, the iPhone's engine fetched back the eight content records this
  device had itself sent before the relaunch, with their files (191 MB
  delivered, 0 written): its saved token predated its own sends. It recurred
  once more on a later engine fetch (the replaced photo's content record,
  2.4 MB); recorded as C-134. **Limitations:**
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
  **When sync or the Connected-deletion split ships, update the privacy
  policy and terms:** both currently say journal data stays on the iPhone and
  that deleting a Connected account erases the iPhone's Études data.
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
