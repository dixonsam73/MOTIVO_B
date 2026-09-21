> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> End-of-window handover written by Claude, stating that nothing was in flight or uncommitted at that moment.
>
> True when written and no longer a description of the tree. Everything it handed over has been implemented, reviewed and committed.
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

Handover to a fresh Claude window — 20 September 2026 (evening)

**Written by Claude (Opus 5) at the end of a long window. Nothing is in flight. Nothing of mine
is uncommitted. Nothing is deployed that is not recorded.**

---

## 1. State

| | |
|---|---|
| Branch | `feature/solo-connected` |
| HEAD | **`79fe153`** — "Record the B-37 production deployment and recapture the schema" |
| Pushed | **Yes, by Samuel.** Local and `origin` agree (0/0) |
| Working tree | Clean **except** five protected/untracked items, none of them mine |

**PROTECTED — do not stage, commit or modify:** `docs/connected-invitations-direction.md`,
`docs/private-connection-invitations-scope-2026-09-17.md`, `AGENTS.md`,
`docs/phase-6-b37-codex-review-2026-09-20.md`, `docs/phase-6-b37-fresh-window-handover-2026-09-20.md`.
The last two are Codex-owned.

## 2. Working rules

- **Claude implements · Codex reviews independently · Samuel approves and pushes.**
- **Claude does not push and does not deploy.** Commits only on explicit per-unit approval.
- Eight-minute Codex check-ins; routine choices settled between Claude and Codex, **serious
  product-changing choices stop for Samuel**.
- **Proportionate work — "one musician with a couple of AI in Hertfordshire, not NASA."**
- Adult/age-assurance architecture is **frozen**. No sharing protocol, no recorder work.
- Never run two `xcodebuild` invocations at once — they share DerivedData and fail with
  `database is locked`. That cost two wasted runs.

## 3. What landed today

**`1940ca3` — B-37 code.** Literal search tokens + per-account search budget.
**`25d032e` — C-97 pending-start cancellation.** Accepted, one sub-gap closed; C-97 stays open.
**`79fe153` — B-37 deployment record + schema recapture.**

**B-37 IS DEPLOYED AND VERIFIED IN PRODUCTION**, 2026-09-20 16:24:00.874241+00. Verification row
`B-37 APPLIED`, independent catalog reads, delta exactly columns +6 / constraints +2 /
rls_enabled +1 / one function replaced with all other surfaces byte-identical, canonical schema
recaptured, **B-23 GATE MET**. Record: `supabase/sql/README-b37-deployment.md` (current status is
at the TOP; everything below it is marked historical).

**One thing carried, and it is INFERRED not observed:** `shadow_enforcement_stat` will begin
recording `rpc.search_account_directory` once a member searches, because the volatility change
lets `enforcement_gate`'s previously-swallowed INSERT land. Measured locally (SQLSTATE 25006);
**not yet seen in production.** Bears on B-34 and C-56, resolves neither. Both counters currently
read zero — **an absence of durable rows, NOT proof nobody has searched.**

## 4. The live work: C-70, profile write path

**Scope written, REVIEWED BY CODEX, and corrected below. NO CODE YET.**
Scope: `/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-opus5-c70-profile-write-scope.md`
Review: `docs/c70-codex-scope-review-2026-09-20.md` — **read it; the corrections below come from
it and two of them change the shape of the work.**

**The mechanism, measured:** `upsertSelfRowOnce` is the only writer for name/account-id/location/
instruments and always sends an upsert. **Postgres evaluates the INSERT policy for
`INSERT … ON CONFLICT DO UPDATE`**, so every edit needs entitlement even when only an UPDATE would
occur — and `account_directory_update_owner`, which is **ungated**, is unreachable from the
client. Locally, with enforcement on: entitled → upsert 200; unentitled → **403/42501**; ordinary
**PATCH 204 succeeds**.

### THE PRODUCT QUESTION WAS ALREADY ANSWERED — do not re-ask it

My scope raised "should a lapsed member be able to edit their own profile?" as a decision for
Samuel. **It is not one. `D-U6-3` decided it before U6a shipped:** *"Self-profile maintenance
allowed while lapsed — `account_directory` SELECT/UPDATE untouched"*
(`supabase/sql/README-u6a-deployment.md:27`), and the U6b plan lists **"Own profile edit — STILL
WORKS — D-U6-3"** among the carve-outs, with device QA step 5 instructing that it be confirmed
(`README-u6b-plan.md:161,416`). Verified by reading both.

**So the ungated owner-UPDATE is deliberate, and the client's upsert defeats it by accident.**
**Adopt B2 — owner UPDATE for an existing row, creation still gated — as RESTORING DOCUMENTED
INTENT, not as a new product decision.** That also means the failing edits observed today are a
carve-out not working as designed, which is a stronger reason to fix it than the one I gave.

### Corrections to my own scope, from the review

- **403/42501 means a POLICY/PRIVILEGE refusal, NOT necessarily membership expiry.** My scope
  leaned on the entitlement reading; the code must not attribute every such failure to
  subscription state.
- **The divergence was never literally silent** — the member saw a red warning. What went wrong is
  that **local persistence was mistaken for remote success**; drop the word "silently".
- **`ProfileStore.hydrateMissingLocalIdentity` fills MISSING fields only** — verified: it writes
  name and location only when the local value is empty, and merges instruments. So it does **not**
  overwrite a non-empty local edit, and my "overwrite versus preserve" question is largely
  answered by the existing contract. **What remains is narrower: deliberate-empty-field
  semantics** — a member who intentionally clears a field would have it refilled on hydration.
  Examine that against the existing contract; **do not broaden this into a hydration redesign.**

### What still needs Codex review before any code

**The exact transport/identity/result protocol.** Specify, then get it reviewed:
owner-bound PATCH and what counts as result evidence (**returned row identity and expected
values**, not a status code); **zero-row handling — 204 is not proof a row changed**; gated
creation when the row is absent; **races between a PATCH and a creation**; ambiguous transport
outcomes; identity switches; **same-owner stale completions**; and — called out specifically —
**account-ID generation must not overwrite a concurrently chosen manual or newer handle.**

**Part A of the scope stands** (distinguish the refusal, never claim success on ambiguity, stop
the UI implying a failed change reached other members while the local value remains the
member's).

## 5. Facts not to re-derive

- **`membership_state()` is NOT an entitlement test.** scope011 (`20260915160000`) widened
  `connected_member()` to `environment in ('Production','Sandbox')` but left `membership_state()`
  filtering on `'Production'`, so it reports `sandbox_only` **whether or not the identity is
  entitled.** Reading it as entitlement produced a confident wrong conclusion today. Use
  `connected_member`.
- **`20260902120000_u6b4_grandfather_retirement.sql` line 69 is SUPERSEDED** by scope011. Read the
  deployed `supabase/schema/functions.json`, not a migration's bytes.
- `capture-schema.sh` with no arguments **overwrites `supabase/schema/`** — use `--local <dir>` or
  a copy for scratch captures, and note a copy run from elsewhere `cd`s wrong and can write `null`.
- `supabase db query --linked` needs **`-f <file>`** for a SQL file; passing it positionally makes
  the CLI parse a leading `--` comment as a flag. Submit via argv, never a shell — `$guard$`
  dollar-quoting would be silently emptied by parameter expansion.
- `lib.sh`'s `sql()` cannot report a CLI-level failure (`set -e` aborts the command substitution
  first); use `|| rc=$?`.
- **Device A is `6fd0a833`**, corroborated by `original_transaction_id 2000001228947923`, Sandbox,
  short renewal cycles. `account_directory.lookup_enabled = false` on it is **protected evidence**;
  `account_privacy.lookup_enabled = true`, `lookup_changed_at 2026-09-10 06:02:41.524643+00`.
  **Preserve both.**

## 6. Open elsewhere, untouched

- **Six sharing/deletion blockers — OPEN. Phase 6 is NOT closed.**
- **C-97** — one sub-gap closed; the blocked-`startSession` condition, the unsynchronised
  `isArmedToRecord` race, and hardware-timing coverage all remain open. No watchdog promised.
- **B-37 residual** — enumeration by a determined subscriber remains possible; allowances are
  provisional; no durable production search row observed yet.
- **F-3** partially measured. **G7** unchanged.

## 7. Evidence

`/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/` — `b37/` (probe results, acceptance
log, apply raw response, B-23 report, post-apply captures, runbook copy), `c97/` (checkpoint, full
suite log, release log, diff), and the C-70 scope at the top level.

**Codex records in the repo:** `docs/c70-codex-scope-review-2026-09-20.md` (the C-70 review),
`docs/phase-6-b37-codex-review-2026-09-20.md`. **Schema authority is the current capture plus
scope011 (active Sandbox accepted) — never an earlier Production-only migration.**

**Unchanged by C-70, and to stay that way:** local ownership, the privacy payload omission (CP-3),
the scope011 entitlement predicate, and every server policy and grant. No age or join-flow
redesign, no sharing protocol, no recorder work, no production mutation, no new credentials, no
account cleanup, no commit, push or device action without approval.
