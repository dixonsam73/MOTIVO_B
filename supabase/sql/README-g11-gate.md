# G11 — DORMANT PRE-CUTOVER RETURN. PREDICTIONS AND PRE-CAPTURE, committed
# 2026-09-01 BEFORE ANY MUTATION

**NOTHING BELOW IS A RESULT.** Committed first in the D14/D15 discipline so the
gate is scored against a prediction rather than read off the aftermath. Every
value here can be wrong. **No mutation has been made. The deletion in §3 has NOT
been run.**

**G11 has never been run as a scored gate.** Its essential behaviour was seen
incidentally during S-1 on 2026-08-25, where attestation fired unattended on a
first cold launch — but that was an observation, not a scored gate with committed
predictions.

## 0. WHY THIS GATE MATTERS MORE AFTER B-34 AND B-35

Both findings removed evidence, and neither touched this one. B-34: the shadow
window's silence is not evidence. B-35: an auth column's silence is not evidence.
**G11's evidence channel is neither** — it is a durable row written by
`membership_establish_v1` through an Edge Function as `service_role`, and a row
either appears or it does not. **When the surrounding measures got weaker, the
direct demonstration got more important.**

## 1. PRE-STATE — captured read-only from production, 2026-09-01

| | |
|---|---|
| `membership` rows | **1** |
| environment / `binding_method` | **Sandbox / `purchase`** |
| `original_transaction_id` | **2000001228947923** |
| `product_id` | `com.sdsongs.etudes.connected.monthly` |
| `renewal_date` | 2026-09-01 11:28:21+00 — **entitled** |
| `pending_cleanup_at` / `entitlement_ended_at` | **NULL / NULL** |
| row `created_at` | **2026-08-30 14:58:20.651151+00** |
| `membership_binding` rows | **1** |
| binding `created_at` / `updated_at` | **2026-08-25 17:31:54.005854+00** — **IDENTICAL, never updated** |
| `membership_binding_conflict` | **0** |
| `membership_cutover` | **16** |
| `membership_state()` / `connected_member()` for this identity | **`sandbox_only` / `false`** |
| shadow rows / observations | 25 / 50 |
| notifications total / applied | 35 / 19 |

## 2. THE PRECONDITION G11 NEEDS, AND WHY IT MUST BE MANUFACTURED

G11 requires **entitled ∧ has identity ∧ the server holds NO membership row**,
then a cold launch. Device A has the first two and **not** the third. The row is
therefore deleted deliberately, as a scoped production mutation.

**`membership_binding` MUST NOT BE TOUCHED.** It is retained by the expiry matrix
for a load-bearing reason: whether `originalTransactionId` survives a
lapse-and-resubscribe is genuinely ambiguous, and **retaining is correct under
both Apple behaviours while deleting is broken under one** — a deleted binding
would mint a new token, mismatch, and **reject the legitimate owner as a
conflict**.

### What this run WILL and WILL NOT prove — stated before, not after

**WILL:** that a client which is locally entitled, holds a Connected identity,
and is unknown to the server **self-heals unattended on a cold launch**, with no
user action and no user-visible message.

**WILL NOT:** anything about a *genuinely* dormant identity returning with a
years-old JWS. Device A has attested before, so the precondition is manufactured.
**The client cannot tell the difference** — its inputs are identical — which is
what makes this a valid test of the mechanism, and **not** a test of the
population. That residual is not closed by this run and must not be recorded as
if it were.

## 3. PREDICTIONS

### 3a. After the guarded deletion — read-only

| # | Prediction |
|---|---|
| G11-1 | `membership` rows = **0** |
| G11-2 | `membership_binding` rows = **1**, `created_at` and `updated_at` **both still 2026-08-25 17:31:54.005854+00** |
| G11-3 | `membership_binding_conflict` = **0** |
| G11-4 | `membership_state()` = **`grandfathered`** |
| G11-5 | `connected_member()` = **TRUE** |

**G11-4 and G11-5 are counterintuitive and are committed deliberately.** Deleting
the row **increases** what the predicate grants: with no membership row the
`bool_or` is NULL over an empty set, so the identity **falls through to the
grandfather clause**, and it is in the 16-row snapshot. Today it reads
`sandbox_only` / **false** precisely *because* a Sandbox row suppresses that
fall-through. **This is D4's exact reasoning, and the deletion turns it into a
live production observation rather than an argument.**

### 3b. After the cold launch

| # | Prediction |
|---|---|
| G11-6 | Attestation fires **unattended** — no tap, no sign-in, no prompt |
| G11-7 | A `membership` row is established: **1 row** |
| G11-8 | `binding_method` = **`purchase`**, NOT `legacy_claim` — the client's JWS already carries our token, so the legacy branch is never entered and **no Set App Account Token PUT is issued at all** |
| G11-9 | `original_transaction_id` = **2000001228947923**, environment **Sandbox** |
| G11-10 | `pending_cleanup_at` = **NULL** and `entitlement_ended_at` = **NULL** — establishment never schedules cleanup, unconditionally |
| G11-11 | Row `created_at` is **NEW**, later than 2026-08-30 14:58:20.651151+00 |
| G11-12 | **`membership_binding` timestamps STILL IDENTICAL and still 2026-08-25 17:31:54.005854+00** |
| G11-13 | `membership_binding_conflict` remains **0** |
| G11-14 | `membership_state()` returns to **`sandbox_only`**, `connected_member()` to **false** |
| G11-15 | **The app says nothing** — F10's silent path; no "Purchase unavailable", no error |
| G11-16 | No Apple notification is required for establishment — attestation is not ingestion |

**G11-12 IS THE LOAD-BEARING ONE AND IT IS AN ABSENCE PROOF.** Identical
timestamps are the only way to observe that **no Set App Account Token PUT
happened**. Together with G11-8 it re-proves, on a second occasion, the claim
B-24n established: the token is an attribute of the **identity**, and it survives
the membership row being destroyed underneath it.

### 3c. Free assertion — the shadow window should record the transition

The identity's shadow `decided_clause` should read **`grandfathered`** for
observations in the gap and return to **`sandbox_only`** after establishment. A
live production demonstration of D4's fall-through, at no extra cost.

## 4. FALSIFIERS — any one of these STOPS the run and is reported, not repaired

- `binding_method` = `legacy_claim` → the client's JWS did **not** carry the
  token → B-24n's bound-at-source claim is wrong on a second run.
- Binding `updated_at` moves → a PUT **was** issued → the legacy branch was
  entered → same.
- `pending_cleanup_at` set on establishment → violates the settled rule that
  establishment never schedules cleanup.
- A `membership_binding_conflict` row appears → the rebinding rule misfired
  against the legitimate owner.
- Attestation does **not** fire unattended → the U5f invariant is broken, and
  **this is the failure G11 exists to detect**.

## 5. THE FIXTURE IS ON A CLOCK

`renewal_date` was 2026-09-01 11:28:21+00 on a **30-minute** cycle. Under Apple's
~12-renewal cap the entitlement ends roughly six hours after the 09:58 purchase.
**The deletion guard therefore refuses to run on an unentitled row** — deleting it
after the subscription dies would spend the fixture for nothing and leave no way
to score the gate. If that happens, tester 2 can resubscribe; testers are not
consumed by resubscribing.

## 6. COST, ACCEPTED EXPLICITLY

**The deletion destroys B-24n's evidence row.** The finding itself is durable in
`CLAUDE.md` and the U5/U6a records, and G11 re-establishes a row — but the
original `created_at 2026-08-30 14:58:20.651151+00` and its continuity across the
2026-08-30 purchase are **not recoverable**. That cost is accepted for a gate that
has never been scored and is U6b's entry condition.
