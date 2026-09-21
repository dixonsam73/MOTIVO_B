# Founding 500 — shared handover for fresh Codex and Claude windows

## Current instruction and working arrangement

Samuel explicitly reconfirmed on 21 September: **Founding 500 is a launch requirement**,
intended to give Connected an initial community. He now requests fresh windows for both
agents to scope it. This authorises investigation, design and scope documents, not product
implementation or deployment. Do not re-ask whether the offer is wanted.

Claude proposes a bounded design and scope. Codex independently reads current source,
challenges the design and checks evidence. Reconcile before presenting Samuel with a
plain-English scope, genuine decisions and implementation sequence. Samuel signs off the
scope before implementation. Do not spend time creating work to keep agents occupied.
No substitute agents; coordinate with the real new Claude window once identified. The old
Claude task is `Account ID/handle removal discussion`; do not send Founding work there.
No new eight-minute automation is active for Founding; the completed recorder automation
is paused. If continuing the established cadence, bind it to the actual new task and scope.

## Repository checkpoint

- Repo: `/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO`.
- Branch: `feature/solo-connected`.
- Latest locally observed commit: `1a4c09f` — `Record which audio input the video recorder actually has`.
- Previous commit: `b479487` — handle removal and fresh-join publication fixes.
- Samuel says he will push the recorder commit. Push is NOT confirmed by this handover.
  Check current git state; do not push on his behalf or infer remote state from a cached ref.
- Recorder R1 final local acceptance: 1070 passed, zero failed, six standing skips; Release
  passed, no added compiler warnings; no new device QA required for that diagnostic. No
  wider recorder work is authorised. `docs/recorder-reliability-codex-review-2026-09-21.md`.
- Protected/unrelated changes remain: `AGENTS.md`, the two invitation documents, earlier
  Codex review/handover documents and `release-priority-review-2026-09-21.md`. Do not sweep
  them into commits, rewrite them, or discard them. This handover itself is newly untracked.

## Settled product direction

Read `docs/pricing-launch-model.md` in full. Its offer is:

- Solo remains permanently free and fully useful.
- Connected normal price: £4.99/month or £49.99/year (recorded product direction; do not
  claim current ASC configuration has been checked).
- First **500 unique production accounts that actually activate Connected** receive
  **12 months free from each account's own activation**. Downloads and installations do
  not count. This is an explicit server-authoritative Études grant, not an Apple purchase.
- Atomic allocation, safe under concurrency and retries; reinstall/device changes do not
  award a new grant or reset its dates.
- After expiry a Founder may subscribe at the normal price, without another introductory
  trial. Later non-Founder members are intended to receive a one-month StoreKit trial.
  **These are requirements to check for feasibility, not proof StoreKit can enforce them.**
- Explain the offer calmly; show activated Founders their status and exact expiry date.
  No countdowns or places-remaining marketing. Once allocated, stop offering Founder places.
- A Founder grant must not impersonate `purchase`/`legacy_claim`, revive grandfathering,
  or become a test/operational bypass in the authority predicate.
- Expiry without paid access follows the existing lapse policy: Solo and hidden Connected
  presence, ordinary 60-day quarantine, eventual cleanup. Local private data survives.
  Account deletion remains distinct and must stay reachable without membership/eligibility.

## Important facts not to inherit blindly

The pricing note is dated 3 September and is not an implementation design. Its statement
that membership is Production-only is obsolete: scope 011 admitted verified Sandbox
membership on 15 September. Read current code and later deployment records.

An Apple identity's stability is not proof that deleting and recreating a Supabase account
preserves `auth.users.id`. Do not rely on the old note's UUID assertion to solve repeat grants
after account deletion. Establish supported lifecycle facts and minimise retained identity
data; identify any retention/legal decision rather than invent it.

New Founder activations have no Apple transaction to label Sandbox/Production. Therefore
"production accounts only" and keeping beta/testing out of the 500 need an explicit design,
not a trusted client flag or the assumption that a StoreKit environment is always available.

## Questions the design must answer

1. **Grant and allocation authority:** smallest durable representation, canonical writer,
   atomic place allocation, retry idempotence, simultaneous 500th/501st activations, and a
   lost response after successful activation. Define what event starts the twelve months,
   server clock/calendar semantics, and what the user sees if allocation closes mid-flow.
2. **Effective access:** how real grants and Apple entitlements combine without corrupting
   Apple provenance. Cover client mode, server enforcement/visibility, offline/stale state,
   launch/foreground/restore, sign-out and another device. No private-library sync is implied.
3. **Expiry and cleanup:** inspect U7's actual authorisation, not just scheduling arithmetic.
   Existing cleanup requires a live Apple authority check; a Founder may have no Apple
   subscription. Propose a separately reviewable authority design that preserves safety for
   paid members and prevents cleanup when a valid grant or subscription exists. Merely
   writing `pending_cleanup_at` is not sufficient and must never authorise deletion.
4. **Conversion and offers:** whether/how a Founder can subscribe early, renewal and overlap,
   refunds/revocations of paid access while a grant survives, and the exact post-Founder
   no-additional-trial requirement. Verify current Apple documentation and relevant local
   StoreKit code: an Études grant is not necessarily Apple subscription-group trial history.
   Surface infeasible requirements/options; do not quietly promise eligibility control.
5. **Account lifecycle and allocation permanence:** existing beta accounts, existing paid
   subscribers, repeat activation, account deletion/recreation, whether deleted accounts
   return places to the pool, and abuse controls proportionate to a small launch. These
   unanswered product choices should be grouped for Samuel, not silently settled.
6. **User experience and release:** eligibility before activation/purchase, Founder display,
   expiry wording, paid conversion without surprise charging, post-500 onboarding, support
   recovery, rollout/rollback and final QA. Keep terms/copy and ASC changes conditional on
   the final reviewed legal/product position.

## Hard boundaries

- Adult-only Connected is agreed direction, NOT implemented or legally/evidentially settled.
  Read `adult-only-connected-rescope-2026-09-18.md`. Apple/solicitor/assurance/server-trust
  answers remain pending. Design an explicit dependency/interface; do not invent adequate
  assurance, change the current band protections, or let a Founder bypass future eligibility.
- Sharing protocol implementation remains frozen. Provider SU-478356 may clarify storage
  guarantees but is not a blanket blocker on this scope. Do not fold sharing redesign into it.
- Do not mutate live SQL, secrets, ASC settings, credentials or devices; no purchases, resets,
  deployment, commit or push. Read-only source/local evidence first; separately scope any
  necessary live inspection without exposing credentials or personal data.
- Preserve Phase 3's carried obligations: C-31, B-34, B-11 Gate 6 part 3 and G7. G7 cannot
  be forced before natural maturity. Do not mark any phase closed by this planning work.
- iPad is a separate later planning conversation. Samuel requires Apple Pencil Scores markup
  and a manuscript sketchpad for its launch. No iPad, iCloud or migration work here.

## Read first, then inspect the relevant current implementation

1. This handover and `docs/pricing-launch-model.md`.
2. Current instructions, with dated history treated as history; `docs/architecture.md` for
   data boundaries and `docs/release-priority-review-2026-09-21.md` for latest decisions.
3. `docs/adult-only-connected-rescope-2026-09-18.md`.
4. Membership/StoreKit client, canonical membership SQL, enforcement/visibility, attestation
   and cleanup worker; relevant U5/U6/U7 and B-39/scope011 deployment records.
5. `docs/fresh-join-f3-evidence-2026-09-21.md` and
   `docs/lapsed-profile-device-qa-2026-09-21.md`: preserve the recent publication fix.

Do not read every historical document or rerun the whole suite just to begin scoping.
Current mechanisms and focused counterexamples matter more than document volume.

## Expected output of these new windows

Claude: one proposed Founding 500 design/scope with current-vs-proposed behaviour, minimal
data/authority changes, lifecycle cases, external dependencies, grouped product questions,
implementation units and meaningful acceptance tests. Explicitly label unknowns.

Codex: independent source-grounded review of that proposal, identifying correctness risks,
unnecessary machinery and any missing release requirement. Reconcile with Claude, then give
Samuel a concise recommendation and only the decisions needed before implementation.

The goal is a launchable, maintainable offer—not a new general promotions platform.
