# Release checklist

The only task list. Tick items off here; put the reasoning in commit messages.
Owner is **S** (Samuel), **A** (agent) or both. Started 2026-09-22.

## A. Decisions (Samuel)

- [ ] **S — Online Safety Act scope and risk assessment.** Run Ofcom's
  [Regulation Checker](https://www.ofcom.org.uk/os-toolkit/regulation-checker/regulation-checker),
  then complete the illegal-content risk assessment with the
  [Online Safety Assessment Tool](https://www.ofcom.org.uk/os-toolkit/assessment-tool).
  A can draft it for S to check. It's required whatever the age decision is.
- [ ] **S — Connected age policy: one hour with a UK online-safety/privacy
  solicitor.** The question: can a low-risk musicians' journal with follow
  approval let 13+ use Connected with a proportionate children's-access/risk
  assessment and the existing 13–17 protections? Or must it be 18+, and if so,
  is Apple's Declared Age Range enough? Take the risk assessment, not the old
  13+ legal packet. Note: an "18+" line in the terms does not by itself settle
  whether children can access the service.
- [ ] **S — Fallback.** If the legal answer stalls, would you ship Solo first and
  add Connected in an update? (Solo has no user-to-user content.)
- [ ] **S — Sharing withdrawal guarantee.** Is "once withdrawn, no earlier
  in-flight request can bring a post back" a product promise? Recommendation:
  **no** for launch. Accept the rare late-commit race as a known limitation with
  honest wording (option S1-X), and don't build S1-Y/S1-Z. Background:
  `docs/phase-6-sharing-repairs-scope-2026-09-22.md`.
- [ ] **S — C-97 / C-99** (video capture route/interruption handling; concurrent
  `StagingStore` writes). Accept as known limitations for launch unless they
  appear in final QA? Recommendation: accept.

## B. Build (agent)

- [ ] **A — Guideline 1.2, all four parts, proportionate.** See
  [Apple Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
  - Filtering: a small objectionable-word filter on posts and comments.
  - Report: an action on posts, comments and profiles. Reports go to S (email
    or a table S checks).
  - Block: removes the follow in both directions and stops new requests.
  - Published contact details: a support email in the app and on the web.
  - Process (S): act on reports promptly (App Review usually expects about 24
    hours; check the current wording). Hide content or suspend accounts from
    the Supabase dashboard. No moderation tooling.
  - Check whether App Review expects users to accept terms that forbid
    objectionable content. If so, add a one-time acceptance on joining Connected.
- [ ] **A — Age implementation to match the legal decision.** Nothing to build if
  13+ with the current protections is accepted, beyond copy and age rating.
- [ ] **A — R1-a:** don't acknowledge an unsent simulated withdrawal
  (`SessionSyncQueue.swift`, client-only, small). Cheap insurance, not a
  blocker.
- [ ] **A — Real build numbers.** Every build reports `1.0 (131)`. Increment
  `CURRENT_PROJECT_VERSION` per upload so a tested build is identifiable.
- [ ] **A — Code coverage in Release.** A Release build made with the scheme
  contained an `__LLVM_COV` segment (~1 MB). Confirm whether Archive includes it,
  and turn it off if so.
- [ ] **A — Any copy changes** from the legal decision and the 1.2 work (About,
  Explore Connected, refusal text).

## C. Configuration (Samuel, in App Store Connect / Supabase / web)

- [x] Founding 500 introductory offer: free first year on both products, no end
  date (seen in ASC 2026-09-21). Remove manually at ~500.
- [ ] Production App Store Server Notifications URL. Keep Sandbox as it is.
- [ ] Production Billing Grace (C-31).
- [ ] Privacy policy published at `etudes.app/privacy`. The draft has an open
  `[AGE]`. Add a backup-retention line from Supabase's published docs.
- [ ] **Then** publish the ASC privacy labels. Nine types are entered and saved;
  mapping in `docs/app-store-privacy-disclosures.md`. Policy first, labels
  second.
- [ ] Terms of use, support URL and contact email live.
- [ ] Age rating set to match the legal decision.
- [ ] Supabase Data Processing Agreement accepted.
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
- Invitations, iPad (with Pencil markup and sketchpad), recorder R1 diagnostics.
- Code slimming when next touched: unused `DirectoryWriteKind.generation` and
  `.creation`; the age-band code if the 18+ route is chosen.
- Deprecation and warning sweeps.
