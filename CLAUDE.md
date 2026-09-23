# Études — Working Context

iPhone app: a local-first journal for musicians, with an optional paid
**Études Connected** social layer (Supabase + StoreKit 2 + Sign in with Apple).
**Not yet publicly released.** Production holds only beta/test identities.

- Branch `feature/solo-connected`. "MOTIVO" is the legacy name of the project,
  scheme and source folder; the product is `Etudes.app`, displayed as "Études".
  Renaming is not release work.
- `CLAUDE.md` and `AGENTS.md` are the same file, for Claude and for Codex. Keep
  them identical.
- **The release task list is `RELEASE.md`.** It is the only task list.
- History up to 2026-09-22, including every phase record, is in
  `docs/history/CLAUDE-through-2026-09-22.md`. Read it only when you need the
  reasoning behind something. It is not current state.

---

## How we work

**Samuel owns product direction and makes the final call.** Agents recommend,
including recommending that something is not worth doing.

**Before scoping anything, answer three questions in one sentence each:**
1. Does Apple or Supabase already do this? (Founding 500 became Apple's
   introductory offer after a long custom design nobody needed.)
2. Would a real user notice if we didn't do it?
3. If it's wrong, can we fix it after launch?

If (3) is yes: build it simply, test it, ship it. No scope document.

**Proportionality.** Full rigour is only for these four: irreversible loss of a
real user's data; money, subscriptions or ownership; security; and App Review
blockers. Everything else: fix, add a test, write a one-line register entry.

**Warning signs, not rules.** A scope over one page, or a fix for a small bug
heading past ~200 lines, means stop and give Samuel a brief explanation first.

**Review (Codex).**
- Only for production database or Edge Function changes, money/ownership, and
  anything that deletes data.
- One round by default. Findings must name a concrete failure scenario, and
  Samuel decides what is fixed.
- A further round is only for a specific, demonstrated, serious unresolved
  defect, and must not widen the task.
- No reviews of design documents about hypothetical scenarios.

**Documentation.** Reasoning goes in commit messages. Findings go in
`docs/audit-findings.md` as short rows. Tasks go in `RELEASE.md`. No per-step
records, handovers, checkpoints or "fresh window" documents. Correct stale text
in place; don't add a "CORRECTED" paragraph on top of it.

---

## Architectural invariants

1. **The local journal is never deleted by any Connected or membership action.**
   `LocalFactoryReset.perform` has exactly two callers, both user-confirmed, in
   `ProfileView` (Solo erase, Connected delete). Don't add a third.
2. **If nobody else can see it, it does not belong on Supabase.** Only sessions
   the user explicitly shares are uploaded; Solo uploads nothing.
3. **Reversible decisions may rely on client evidence; irreversible ones need
   authoritative server evidence.**
4. **Personal durability follows Apple's normal backup model**, independent of
   Connected.
5. **Age.** Solo has no Études-imposed age restriction. Connected's age policy
   is **pending a legal decision** (see `RELEASE.md`). The shipped code and
   production implement a 13+ design with 13–17 protections (age band, B-40,
   `tg_directory_requires_band`). These stay in force until a decision is made.
   An 18+ direction was recorded on 2026-09-18 and is not implemented. Age
   eligibility must never gate account deletion.

## Settled behaviour — don't change without Samuel

- Leaving Connected is not leaving Études. No subscription event (cancel, grace,
  retry, expiry, refund, revocation) touches local data.
- **Membership never gates account deletion.** A lapsed member must be able to
  delete their account without resubscribing.
- Deleting a Connected account deletes the member's own backend content: posts,
  comments they authored, attachments they sent. Content *addressed to* them by
  others survives (B-19).
- Expiry is not deletion. Expiry cleanup is a separate worker with its own
  retention rules and a 60-day quarantine. It needs a live Apple read before
  acting, and notifications only ever schedule it. The retention matrix is in
  the history file.
- "Share with followers" defaults ON, with a "Default to Private Posts"
  preference. Thoughts default to private but **can** be shared. Never describe
  them as "never shared".
- Unsharing deletes the backend post (demote first, then delete, through the
  durable queue).
- Founding 500 = Apple's one-year introductory offer on both products, withdrawn
  manually around 500. There is no custom grant mechanism.
- M13 (iPad) and M14 (iCloud sync) are deliberately deferred.

## Backend facts

- Membership is server-authoritative and **enforced** through RLS. Verified
  Sandbox membership counts as entitled (scope 011, deployed 2026-09-15), so
  TestFlight and App Review purchases work.
- The expiry cleanup worker is armed (daily 03:17 UTC). Its earliest possible
  real candidate is 2026-11-01. Kill switch: unset `CLEANUP_MODE`.
- Edge Functions: `appstore_notifications_v1`, `appstore_reconcile_v1`,
  `membership_attest_v1`, `membership_cleanup_v1`, `delete_account_v1`,
  `revoke_apple_identity_v1`. `verify_jwt` is pinned in `supabase/config.toml`.
- **Production SQL:** put the guard inside the transaction and end with a
  `SELECT` that returns a row. "Success, no rows" can mean the wrong text ran.
  `supabase db query` runs every statement and returns only the last result.
  **Its exit code is 0 even on failure**, so read the response body.
- `supabase db query --linked` bypasses RLS, so it can never prove a policy
  works. Use PostgREST with a real JWT.
- `supabase storage rm` silently does nothing (CLI 2.113.0). See
  `supabase/README.md` for the working route.
- Every production schema change must also land in `supabase/migrations/`, or
  local rehearsals test the wrong thing.
- Secrets live in `~/.etudes-secrets/` and Supabase secrets, never in the repo.

## Build and test

```
xcodebuild -project MOTIVO.xcodeproj -scheme MOTIVO -configuration {Debug|Release} -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project MOTIVO.xcodeproj -scheme MOTIVO -only-testing:MOTIVOTests -destination '<simulator>'
```

- iPhone only, deployment target **iOS 26.4**, for the whole app.
- **Only Release can make purchases.** Debug's bundle id
  (`com.samueldixon.motivo.dev`) is unknown to App Store Connect, so products
  come back empty. The shared scheme's Run action **must stay Release with no
  StoreKit configuration**. `SchemeConfigurationGuardTests` enforces this; it
  has been silently reverted twice.
- `Etudes.storekit` is opt-in only (Run → Options), and never ships.
- Always check Release as well as Debug; there are many `#if DEBUG` blocks.
- The build number is the git commit count, and the foot of the Profile page
  shows it with the short commit hash (`-dirty` if app source was uncommitted). Set by the "Stamp
  Build Number" script phase.
- Release-readable logging: `os.Logger` with `privacy: .public`. Xcode's console
  shows it live.

## Devices and Sandbox

| Label | Device | Installed |
|---|---|---|
| Device A | iPhone 16e ("SD beta burner") | Release only |
| Device B | iPhone 17 Pro ("SD iPhone") | Release **and** "Études Dev" (Debug) |

- Any device QA step must name the device **and** the install.
- **Never use Samuel's own Études Dev account/history for destructive tests.
  Never run Erase All on Device B.**
- A clean first purchase needs a **fresh Sandbox tester**. Clearing purchase
  history has never worked here.
- Xcode's sandbox renews on an accelerated clock (monthly ≈ minutes). TestFlight
  renews daily, up to ~6 times.
- A final TestFlight checkpoint is still required before release.

## Where things are

- `RELEASE.md` — what's left before launch.
- `docs/audit-findings.md` — finding register (C-n client, B-n backend).
- `docs/qa-plan.md` — manual QA reference.
- `docs/architecture.md` — data domains.
- `docs/app-store-privacy-disclosures.md` — privacy-label mapping.
- `supabase/README.md` — backend operations.
- `docs/history/` — everything historical.
