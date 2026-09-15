# B-39 (audit A1) — prediction, written before any backend change

2026-09-14, at `3c68d81`. **Local rig only.** Any production deployment is
presented separately after validation, with its own prediction and B-23 gate.

## 1. The rule, and why this signal

**`apple_status = 5` ends entitlement, whatever the dates say. A transaction's
`revocation_date` alone never does.** When `apple_status` is absent, the existing
date formula applies unchanged.

Settled from Apple's reference (fetched 2026-09-14), correcting this unit's first
premise:

- **Upgrades are not revocations.** `isUpgraded` is set on the superseded
  transaction and Apple sends a new one; StoreKit Test's `cancelDate` ("equivalent
  to `revocationDate`") is explicitly **not** set on upgrade. `revocationDate`
  means refunded, or revoked from Family Sharing. The earlier claim that an
  upgrade sets `revocationDate` was wrong and is corrected in the test file.
- **`status` is subscription-level.** Apple: status 5 — "The auto-renewable
  subscription is revoked. The App Store refunded the transaction or revoked it
  from Family Sharing", current as of the notification's `signedDate`; present
  for every auto-renewable subscription notification and in each
  `lastTransactions` entry.

**Transaction selection, verified in source, is why `revocation_date` is not
enough:**

| Path | Transaction stored | Source |
|---|---|---|
| Reconciliation | `lastTransactions` entry for the `originalTransactionId` — the lineage's latest | `appstore_reconcile_v1/index.ts:211` |
| Cleanup worker's live read | same | `membership_cleanup_v1/index.ts:331` |
| Notifications | **the notification's own transaction** | `appstore_notifications_v1` → `deriveFromNotification` |

A REFUND notification carries the refunded transaction, which may be an
**earlier** period while the subscription is active; its `revocation_date`
would then describe a transaction that is not the current one. Reconciliation is
operator-invoked (service-role HTTP; the only scheduled workflow is cleanup), so
the notification path cannot simply defer to it — routing refunds to
`needs_reconciliation` would stop them taking effect at all.

## 2. Every site, inventoried

The formula is decided in **three** SQL functions and mirrored in **one**
TypeScript function. Everything else calls these.

| Site | Change |
|---|---|
| `connected_member(uuid)` | per-row: `coalesce(apple_status, 0) <> 5 and (date formula)` — stays strictly two-valued |
| `membership_entitled_until(uuid)` | a status-5 row contributes `coalesce(revocation_date, renewal_info_signed_date)` instead of its future dates |
| `membership_apply_state_v1` | `v_entitled` gains the same conjunct; a status-5 lapse ends at `coalesce(v_revoked, v_signed)` |
| `derive.ts` `entitledAt` | same conjunct (diagnostics only) |

**Inherit the fix without edits:** `membership_state()`,
`connected_member_self()` and every U6a/U6b policy (via `connected_member`);
`membership_cleanup_authorised_v1` (calls `connected_member`); the four cached
columns and `tg_membership_propagate_entitled_until` (via
`membership_entitled_until`).

**Deliberately unchanged:** the non-revoked lapse branch of the writer, which
already prefers `v_revoked` for `entitlement_ended_at`; anti-sliding; the
born-lapsed floor; F11; UPDATE-ONLY. No grants, comments, tables or triggers
change.

## 3. Predictions

**P1 — `supabase/tests/b39/acceptance-refund.sh`.**
`pre`: fails exactly B39-R2…R9, E1, E2, V1, M1…M3, S1…S3 (17); every control and
discriminator passes, including **P1** (earlier-period refund stays entitled),
**U1** (upgrade stays entitled) and **N1** (status absent: date formula).
`post`: **zero failures**.

**P2 — `supabase/tests/b39/modules.ts`.** `pre`: fails exactly T1, T2. `post`:
zero failures.

**P3 — no existing suite changes result.** No fixture in `supabase/tests` uses
status 5, so u3, u4 acceptance, u5 acceptance, u6b, u7 primitive, u7
born-lapsed and p4 u7 each produce the **same** pass/fail result after the fix
as before it. The pre-fix results are recorded first, not assumed green.

**P4 — B-23 gate.** Pre-fix the local rebuild matches the committed production
snapshot (GATE MET, standing `account_id_format` exception only). Post-fix it
differs in **exactly three `functions` rows** — `connected_member`,
`membership_entitled_until`, `membership_apply_state_v1` — and in no other
surface. The gate therefore reports NOT MET post-fix, which is the correct
local-only state until a production deploy.

Any miss is recorded as a miss and diagnosed before continuing.

## 4. Pre-fix results (run 2026-09-14, each suite after its own `db reset --local`)

| Check | Result | Against prediction |
|---|---|---|
| `b39/acceptance-refund.sh` `pre` | 18 passed, 17 failed — **exactly the predicted set** | P1 met |
| `b39/modules.ts` `pre` | 4 passed, 2 failed (T1, T2) | P2 met |
| u3 acceptance | 90 passed, **1 failed** (A16b, stale trigger count) | recorded baseline — B-42 |
| u4 acceptance | 98 passed, **1 failed** (A57c, stale trigger count) | recorded baseline — B-42 |
| u5 acceptance | 59 passed, 0 failed | baseline |
| u6b acceptance | **exit 3** after its first fixture check (CP-1 band refusal, confirmed by probe) | recorded baseline — B-42 |
| u7 half A / half B | 47/0 and 20/0 | baseline |
| p4/u7 acceptance | 19 passed, **7 failed** (same CP-1 refusal) | recorded baseline — B-42 |
| B-23 gate | **GATE NOT MET — 19 problems**, none B-39's | **P4 MISSED** — predicted GATE MET. Diagnosed as B-41 (local rebuild no longer reproduces production). Post-fix gate is therefore scored as *the same 19 plus exactly the three B-39 function rows* |

**The writer was verified verbatim before the change:** a diff of the drafted
`membership_apply_state_v1` against `20260902130000_u7b_cleanup_primitive.sql`
shows only the three marked B-39 statements.

## 5. Post-fix results (same procedure, migration `20260914120000_b39_revoked_status_ends_entitlement.sql` applied)

| Check | Result | Against prediction |
|---|---|---|
| `b39/acceptance-refund.sh` `post` | **35 passed, 0 failed** | P1 met |
| `b39/modules.ts` `post` | **6 passed, 0 failed** | P2 met |
| u3, u4, u5, u7 half A, u7 half B, p4/u7 | **pass/fail per assertion id identical to pre-fix** (differences are only timestamps printed inside PASS lines) | P3 met |
| u6b | exit 3 at the same fixture step as pre-fix | P3 met (B-42 unchanged) |
| B-23 gate | 22 problems = **the same 19 + exactly** `functions connected_member`, `functions membership_apply_state_v1`, `functions membership_entitled_until` | P4 (as re-scored after the recorded miss) met |

**Local only. Nothing is deployed.** A production deployment needs its own
prediction, the B-23 gate re-proved (which first needs B-41), and explicit
authorisation.

## 6. Follow-up coverage and A1's acceptance status (2026-09-14)

**Notification → derivation → ingestion** (`supabase/tests/b39/notification-ordering.sh`,
shipping `deriveFromNotification` + shipping `membership_ingest_notification_v1`;
JWS verification not exercised): **11 passed, 4 failed — exactly as predicted.**
Current-period refund, earlier-period refund, reversal and the stale control all
behave correctly. **N4/N5 — a newer refund or reversal whose renewal info is
signed earlier than the stored row — are refused `stale`.** Filed as **B-43,
Unverified**: the mechanism is measured, Apple's behaviour is undocumented, and
B-39 did not change ordering.

**A1 acceptance status, precisely:**

| Claim | Status |
|---|---|
| Revocation ends entitlement, cached visibility and starts quarantine; reversal restores | **Met locally** — 35/35, 6/6, and through notification ingestion (N1–N3) |
| No regression in existing local suites | **Met for the assertions that execute**; U6b and p4/u7 abort early, so their later assertions did not run (B-42) |
| Full backend validation | **NOT met** — B-23 gate not met (B-41), suites broken (B-42); plan in `docs/phase-5-b41-b42-restoration-plan.md` |
| Newer-notification ordering (B-43) | **Open question**, conditional on Apple behaviour; not part of A1's fix |
| Production | **Not deployed**; separately authorised, after B-41/B-42 |

**A1 is therefore locally implemented and locally accepted, not release-accepted.**

## 7. Status update — 2026-09-14, after B-41/R1 and B-42/R2

**Section 6's table is retained as written and is superseded in two rows.** B-41
is resolved in the local reproduction (G1 GATE MET) and B-42 is resolved (u6b
64/64, p4/u7 26/26), so:

| Claim | Status now |
|---|---|
| No regression in existing local suites | **Met** — every local acceptance suite now runs to completion with B-39 present |
| Local backend validation | **Met for the backend acceptance suites and the B-23 gate** (differing from production only by B-39's intended local change). **Not a clean sweep:** p4 u2c U2c-2/U2c-4 and p4 u1-baseline's six documented flips remain, neither caused by B-39 |

Unchanged: B-43 open and conditional; production not deployed. **B-43's
ordering check exits 0 when its failure set matches the prediction — "prediction
matched" is not "all behaviour passed".**
