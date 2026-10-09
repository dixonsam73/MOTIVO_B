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
- [ ] **S — Adult-access adequacy: solicitor engaged 2026-10-07.** Scope
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
  unchanged. App upgrades (iPad, Pencil sketching) are included for owners;
  in public copy say "included with your purchase", not "free forever". No
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
- [ ] **A — Adult-only gate for Connected**, replacing the 13–17 pathway, using
  whatever mechanism the legal answer says is adequate. Then finalise the
  provisional grooming rating in the risk assessment.
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
  publishing: confirm the provisional age row once the adult-only gate exists, add
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

## E. After launch / known limitations (not release work)

- Sharing: the late-commit race family (S1), retention hygiene (D2/D3), the
  wider sharing redesign.
- Supabase ticket SU-478356 (physical deletion and retention). Don't wait on it.
- G7: first real expiry cleanup, earliest 2026-11-01, happens on its own.
- Gate 6 part 3: production grant at the first real subscription.
- B-34 (shadow telemetry blind to denied writes). Observability only.
- Invitations, iPad (with Pencil markup and sketchpad, plus private iCloud sync; agreed plan in `docs/architecture.md`, "iPad and private sync"), recorder R1 diagnostics.
  **When sync or the Connected-deletion split ships, update the privacy
  policy and terms:** both currently say journal data stays on the iPhone and
  that deleting a Connected account erases the iPhone's Études data.
- Code slimming when next touched: unused `DirectoryWriteKind.generation` and
  `.creation`; the age-band code once the adult-only gate replaces it.
- Deprecation and warning sweeps.
- A suspended member lands in Solo with no explanation. Optional: a short
  "account suspended, contact support" message.
- Block is per device. "Reply to all commenters" still fans out server-side to
  a blocked commenter. It's rare, and they can no longer see the post.
- Test hygiene: 3–7 order-dependent "ownerless/signed-out" tests
  (`P6I02…`, `P6I03…`, `JournalDeleteQueuedPublishTests`) fail in full-suite
  runs at `5c77beb` and pass when run alone.
