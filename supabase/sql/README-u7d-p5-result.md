# U7d P5 — EXECUTED IN PRODUCTION. THE WORKER **REFUSED**. NOTHING WAS DELETED. 2026-09-03

**`membership_cleanup_v1` was invoked exactly once in `mode: "execute"` against
the accepted Device A fixture. It performed a genuine live Apple read, applied it
through the canonical writer, consulted the authority gate, and DECLINED to
delete anything.**

**This is a PASS of the cleanup-authority rule, and it is the most load-bearing
rule in Phase 3.** It is not a failure, and it must not be repaired forward.

---

## 1. FRESH PREFLIGHT — EVERY ITEM MATCHED

| Check | Required | Observed |
|---|---|---|
| Local / remote HEAD | `1d4ac3d…` | **both `1d4ac3d…`** |
| Working tree | clean | **CLEAN** |
| `membership_cleanup_v1` | v1, ACTIVE, `verify_jwt=false` | **v1, ACTIVE, false** |
| `cleanup_claimed_at` | NULL | **NULL** |
| `cleanup_completed_at` | NULL | **NULL** |
| Schedule | `2026-09-02 20:58:53.620658+00`, due | **matched, `is_due = true`** |
| `pg_cron` | 0 | **0** |
| Enforcement | on + active | **true / true** |
| Conflicts | 0 | **0** |
| `connected_member` / state | false / `sandbox_only` | **false / `sandbox_only`** |
| Globals | 17 / 101 / 5 / 9 / 15 / 3 / 31 / 17 | **all identical** |
| Subject rows | 1 post, 2 follows, 3 cascading comments, 1 retained comment, 1 object, 0 conn-att | **all identical** |

**No material drift. P5 proceeded on the accepted state.**

---

## 2. THE WORKER RESULT — VERBATIM

```json
{ "ok": true, "mode": "execute", "identities": 1,
  "results": [ { "user_id": "5ae3faab…",
                 "decision": "refused",
                 "reason": "no schedule remains due after refresh",
                 "deleted": false } ] }
```

---

## 3. WHAT APPLE SAID, AND WHY IT REFUSED — THE MECHANISM

**The live Apple read genuinely happened, and the row proves it independently of
the worker's own output:**

| Column | Before P5 | After P5 |
|---|---|---|
| `renewal_info_signed_date` | `2026-09-02 15:16:44+00` | **`2026-09-03 08:14:36.792+00`** |
| `updated_at` | `2026-09-02 15:16:52+00` | **`2026-09-03 08:14:37+00`** |
| `cleanup_claimed_at` | NULL | `2026-09-03 08:14:36+00` |
| **`pending_cleanup_at`** | `2026-09-02 20:58:53+00` *(the fixture)* | **`2026-11-01 15:16:44+00`** |
| `entitlement_ended_at` | `2026-09-02 15:16:44+00` | **unchanged** |
| `apple_status` / `expiration_intent` / `auto_renew_status` | 2 / 1 / 0 | **unchanged** |

**`renewal_info_signed_date` moved to a signature timestamped minutes before the
call. Only Apple can produce that**, and it passed the pinned Apple Root CA G3 in
the deployed bundle. So the fresh authoritative read is evidenced by the data, not
merely reported by the worker — and because the writer's ordering predicate is
`v_signed > m.renewal_info_signed_date`, the row could only move if the
reconciliation genuinely applied.

**Apple still reports the subscription expired**, ended `2026-09-02 15:16:44+00`.
The canonical writer therefore recomputed the schedule from **Apple's own dates**:

```
v_ended   = 2026-09-02 15:16:44+00      (Apple's truth, unchanged)
v_cleanup = v_ended + 60 days = 2026-11-01 15:16:44+00
```

**The reconciliation OVERWROTE the artificial fixture value with the genuine,
correctly-derived schedule.** The authority gate then found no schedule due —
`2026-11-01` is eight weeks away — and refused.

---

## 4. THE FINDING THAT MATTERS MORE THAN THE RUN

**THE FIXTURE-ADVANCE APPROACH IS STRUCTURALLY INCAPABLE OF CAUSING A CLEANUP,
AND THE REASON IS THE SAFETY PROPERTY WORKING.**

Both parties accepted the fixture advance in good faith. It cannot work, and it
could not have been made to work by any careful editing:

- Cleanup **must** be preceded by a fresh authoritative Apple read — the standing
  rule, and the whole point of U7.
- That read is **applied through the canonical writer**, which **derives**
  `pending_cleanup_at` from Apple's dates rather than preserving what is stored.
- So **any hand-edited schedule is erased by the very step that must run before
  deletion.** The scheduling column is not authority, and the system enforces that
  by recomputing it.

**This is exactly the standing rule made mechanical:** *"No stored membership
record, notification, scheduled timestamp, client state or local cache is
sufficient authority for irreversible expiry cleanup."* A stored timestamp cannot
authorise cleanup **even when an operator writes it deliberately**. That is
stronger than the rule as written, and it was demonstrated rather than argued.

**Consequence: the earliest genuine authorised cleanup for Device A is
`2026-11-01 15:16:44+00`.** There is no legitimate shortcut. Editing
`entitlement_ended_at` instead is **not** an option and must not be attempted: it
is Apple's own recorded truth rather than a scheduling column, it would be
falsifying provenance in the B-24 sense, and it would be recomputed away by the
next reconciliation regardless.

**THE ARTIFICIAL FIXTURE VALUE IS GONE, AND NOTHING RESTORED IT BY HAND.** The
row now carries the genuine value derived from Apple. No artificial state remains
in production — which is a better outcome than the restore statement would have
produced, and it happened as a side effect of the safety machinery rather than of
cleanup work.

---

## 5. INDEPENDENT VERIFICATION — SCORED ON THE DATABASE, NOT ON WORKER OUTPUT

**Nothing was deleted. Every figure below was read back from production after the
call.**

| | Before | After | |
|---|---|---|---|
| `auth.users` | 17 | **17** | unchanged |
| `posts` | 101 | **101** | unchanged |
| `post_comments` | 5 | **5** | unchanged |
| `follows` | 9 | **9** | unchanged |
| storage `attachments` objects | 15 | **15** | unchanged |
| storage `avatars` objects | 3 | **3** | unchanged |
| `connected_attachments` | 31 | **31** | unchanged |
| `account_directory` | 17 | **17** | unchanged |
| Subject's post | 1 | **1** | present |
| Subject's storage object | 1 | **1** | present |
| Subject's follows | 2 | **2** | present |
| **The 3 `samueldixon` comments, by id** | 3 | **3** | **all present** |
| **The subject's retained comment, by id** | 1 | **1** | present |
| `membership` / `membership_binding` | 1 / 1 | **1 / 1** | retained |
| `membership_binding_conflict` | 0 | **0** | no conflict |
| `enforcement_enabled` / `enforcement_active()` | true | **true / true** | unchanged |
| `cleanup_completed_at` | NULL | **NULL** | correct — no completion on a refusal |

**No orphaned doomed object**: the one object the dry run named is still present,
because no removal was attempted. **No authentication or account side effect**:
`auth.users` unchanged at 17, no sign-out path involved, enforcement untouched.

---

## 6. ONE BEHAVIOURAL OBSERVATION, NOT A DEFECT

**A `refused` identity keeps its lease until it expires.** `cleanup_claimed_at` is
`2026-09-03 08:14:36+00` and `membership_cleanup_complete_v1` correctly did not
run, so the claim clears itself after the one-hour lease rather than immediately.

**Correct by design** — the lease is crash-recoverable and expiry is its release
mechanism. Worth recording because under U7e a scheduler would skip a refused
identity for up to an hour after each refusal. Harmless at any plausible cadence,
and **not** a reason to add release-on-refusal machinery: releasing eagerly would
mean a refusal path that writes, which is the kind of extra mutation this unit has
twice chosen against.

---

## 7. CAN U7d CLOSE? — HALF, HONESTLY

**DISCHARGED IN PRODUCTION:**

1. Both migrations deployed; **structural delta 10 of 10**; **B-23 GATE MET**.
2. Worker deployed, bundle verified by content property, genuine Apple anchor,
   production authorisation boundary **401 / 401 / 405**.
3. Dry run **matched the independent prediction exactly**, acquired **no lease**,
   wrote nothing, and repeated without blocking the execute.
4. **THE AUTHORITY PATH, END TO END, AGAINST GENUINE APPLE** — claim, live read,
   pinned-anchor verification, application through the canonical writer, gate
   decision, refusal, zero deletion. **This is U7's central safety claim and it is
   now production-verified.**

**NOT DISCHARGED, AND CANNOT BE UNTIL 2026-11-01:**

5. The **destructive** half — the retention/deletion matrix against production
   data. It was never reached, because the authority gate correctly refused.

**So U7d is a PARTIAL PASS: the authority half is proven in production, the
deletion half is not.** Recording it as "passed" outright would claim production
verification of deletions that never ran.

**The local e2e suite (75/75) remains the only coverage for the deletion
behaviour**, unchanged and accepted. **F-2, F-4 and F-5 remain honestly
unexercised** — this run supplied no evidence for them, since no removal was
attempted.

---

## 8. WHAT REMAINS

| | |
|---|---|
| **U7d completion** | Re-run `mode: "execute"` **on or after `2026-11-01 15:16:44+00`**, when the schedule Apple's own dates produce is genuinely due. No fixture, no shortcut. The predicted irreversible effects are unchanged and already accepted |
| **U7e** | The scheduler and its credential boundary — **not started**, and explicitly still requiring that no service-role credential be stored in or exposed from PostgreSQL |

**Nothing else changed. No scheduler, C-58 not started, U6 untouched.**
