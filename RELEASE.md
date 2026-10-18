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
- [ ] **A — R1-a:** don't acknowledge an unsent simulated withdrawal
  (`SessionSyncQueue.swift`, client-only, small). Cheap insurance, not a
  blocker.
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
- [ ] **A — "Tell someone about Études" share button** (decided 2026-10-09).
  Client-only: the iOS share sheet with the App Store link and a short
  message. Keep it out of the way, in Profile's Account card. The message or a
  hint should say the recipient finds you by name only if "Let other members
  find you" is on. No contacts access, no backend. With it, change
  `ConnectedIntroductionView.swift:211` ("you can invite them"), which is
  false today, to match. Also reword "sketch" in `AboutEtudesView.swift:64`
  (no drawing tool yet). Private invitations stay post-launch (section E).
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
