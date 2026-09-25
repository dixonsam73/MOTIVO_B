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
- [ ] **S — Adult-access adequacy: one hour with a UK online-safety/privacy
  solicitor.** Connected launches 18+ only (settled). The question: is Apple's
  Declared Age Range (including the confirmed adult signal on iOS 26.5)
  adequate to conclude children cannot access Connected? If not, what is the
  minimum that is? Take the risk assessment
  (`Etudes-Ofcom-Risk-Assessment-v2-DRAFT-2026-09-23.docx`), not the old 13+
  legal packet. An "18+" line in the terms does not by itself settle it.
- [ ] **S — Fallback.** If the legal answer stalls, would you ship Solo first and
  add Connected in an update? (Solo has no user-to-user content.)
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

## C. Configuration (Samuel, in App Store Connect / Supabase / web)

- [x] Founding 500 introductory offer: free first year on both products, no end
  date (seen in ASC 2026-09-21). Remove manually at ~500.
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
