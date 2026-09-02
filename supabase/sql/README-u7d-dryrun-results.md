# U7d — DEPLOYED, DRY RUN PASSED. STOPPED BEFORE P5. 2026-09-02

**NO DESTRUCTIVE EXECUTION HAS HAPPENED. Nothing has been deleted. No scheduler.**
Production now carries the U7b/U7c objects and the worker, all inert until an
explicit `mode: "execute"` invocation.

---

## 1. DEPLOYED STATE

| | |
|---|---|
| `2026-09-02-u7b-apply-production.sql` | applied by the account holder — `U7b APPLIED`, columns 2, functions 2, schedule untouched |
| `2026-09-02-u7c-apply-production.sql` | applied — `U7c APPLIED`, cleanup functions 4, `preview_volatility s`, **`b33_oracle_reachable false`**, schedule untouched |
| `membership_cleanup_v1` | **v1, ACTIVE, `verify_jwt = false`** |
| Other five Edge Functions | **versions unchanged** — `functions deploy` moved only the named one, as U5 established |

**Deployed-bundle verification, not the tree.** The downloaded bundle differs from
source only by **bundler formatting** — type-only imports erased, blank lines
stripped, multi-line imports joined. Verified by content property instead:

| In the deployed bundle | |
|---|---|
| `membership_cleanup_authorised_v1` | 1 — the authority gate is deployed |
| `membership_apply_reconciliation_v1` | 1 — the fresh Apple read goes through the canonical writer |
| `removeVerified` | 3 — every removal site uses the re-listing verifier |
| `retainedPaths.has` | 1 — the sweep is selective |
| `secretEquals` | 2 — the authorisation boundary |
| `from("post_comments")` | **0** — B-19 |
| `from("account_directory").delete` | **0** |
| `deleteUser` in **code** (comments stripped) | **0** — the single textual hit is the prose forbidding it |

**The deployed Apple trust anchor is byte-identical to committed source and
contains no test CA.** Checked because the local e2e substitutes a test CA in a
*copy*; this confirms production pins the genuine Apple Root CA G3.

**Production authorisation boundary, live:** no header → **401**; wrong bearer →
**401**; `GET` → **405**.

---

## 2. STRUCTURAL DELTA AND B-23 — 10 OF 10 PREDICTIONS MATCHED

| Surface | Predicted | **Measured in production** |
|---|---|---|
| `columns` | +2 | **+2** — `cleanup_completed_at`, `cleanup_claimed_at` |
| `functions` | +5 new, 1 modified | **+6 / −1** = 5 new + 1 modified |
| `function_grants` | **+15** | **+15** — 5 functions × 3 grantees |
| `constraints` | 0 | **IDENTICAL** |
| `policies`, `rls_enabled`, `triggers`, `table_grants`, `column_grants`, `storage_buckets` | IDENTICAL | **all IDENTICAL** |

**The corrected grant rule held exactly**: every new function contributes 3 rows,
including `membership_cleanup_lease_v1`, which is granted to nobody and still
contributes 3 — the units error that cost two misses at U7b/U7c did not recur.

**B-23: `GATE NOT MET, 23 problems` → `GATE MET`**, with only the standing
`account_id_format` catalog-serialization exception. **Nothing was repaired
forward.**

---

## 3. DEVICE A SCHEDULE VALUES

| | |
|---|---|
| **Genuine original** | **`2026-11-01 15:16:44+00`** — from the real Apple lapse, `entitlement_ended_at 2026-09-02 15:16:44+00` + 60 days |
| **Temporary fixture value** | **`2026-09-02 20:58:53.620658+00`** |
| Restore statement | `README-u7d-preflight.md` §7, guarded on `cleanup_completed_at is null` |
| `membership.updated_at` | **`2026-09-02 15:16:52+00` — untouched.** The fixture mutation set only `pending_cleanup_at`, so the row still records when Apple's own lapse landed |

The mutation returned exactly one row, with `original_preserved` echoing
`2026-11-01 15:16:44+00`. Its five guards all held: right environment, right
subscription, **value still the genuine original**, not Production-entitled, and
exactly one membership row.

---

## 4. INDEPENDENT PREDICTION — RE-VERIFIED POST-DEPLOY, PRE-MUTATION

Derived from read-only `select`s, **not** from the worker in any mode, and
re-measured immediately before the fixture mutation. **Identical to the
preflight.**

| Subject `5ae3faab…` | |
|---|---|
| own posts | **1** |
| storage objects under the subject | **1** |
| follows (both directions) | **2** |
| comments on the subject's own post (cascade) | **3** |
| the subject's comment elsewhere (retain) | **1** |
| avatar objects | **0** |
| connected attachments, either direction | **0** |

Globals: users 17, posts 101, comments 5, follows 9, attachment objects 15,
avatar objects 3, `connected_attachments` 31, directory 17.

---

## 5. DRY RUN — AND THE COMPARISON

```json
{ "ok": true, "mode": "dry_run", "claimed": false, "deleted": false,
  "identities": 1,
  "results": [{ "user_id": "5ae3faab…", "environments": ["Sandbox"],
    "would_delete": { "posts.owner_user_id": 1,
                      "post_shares.recipient_user_id": 0,
                      "post_comment_views.viewer_user_id": 0,
                      "connected_attachments.recipient_user_id": 0,
                      "connected_attachments_sent_assets": 0,
                      "storage_objects": 1, "avatar_objects": 0 },
    "would_delete_objects": ["users/5ae3faab…/A9527E59-…/678A7F2C-….m4a"],
    "would_retain_objects": [] }] }
```

| Prediction | Dry run | |
|---|---|---|
| 1 eligible identity, Sandbox | 1, Sandbox | ✅ |
| own posts 1 | `posts.owner_user_id` **1** | ✅ |
| storage objects 1 | `storage_objects` **1** | ✅ |
| **the exact object path** | **matches the independently measured path** | ✅ |
| received shares 0 | **0** | ✅ |
| comment views 0 | **0** | ✅ |
| connected attachments received 0 | **0** | ✅ |
| sent assets 0 | **0** | ✅ |
| avatar objects 0 | **0** | ✅ |
| retained objects (none, nothing to retain) | `[]` | ✅ |

**NO MATERIAL DIFFERENCE. Nothing was repaired forward.**

**And the dry run proved its own properties in production:**

| | Measured after two dry runs |
|---|---|
| `cleanup_claimed_at` set on any row | **0 — no lease acquired** |
| `cleanup_completed_at` | **0** |
| schedule | **unchanged** at the fixture value |
| `membership.updated_at` | **unchanged** |
| posts / comments / follows / objects / users | **101 / 5 / 9 / 15 / 17 — all unchanged** |
| **a SECOND dry run** | **still finds 1 identity** — the P4→P5 trap does not exist |

**What the dry run does NOT prove**, by design: that cleanup will proceed. It made
**no Apple request** and evaluated **no authority**. Whether Apple still reports
this subscription lapsed is answered only at execution.

---

## 6. UNEXPECTED PRODUCTION OBSERVATIONS

**One, and it is procedural rather than a defect.**
`supabase functions download` **overwrote the working tree** — the worker's
`index.ts` and all four `_shared/appstore` modules. Restored from git; the tree
is clean and the deployed bundle was verified by content property before
restoring. **Anyone verifying a deployed bundle this way must expect the download
to clobber source and must restore afterwards.**

**No unexpected database observation.** Every production figure matched what was
predicted from it, before and after the deploy.

---

## 7. WHAT P5 WOULD AUTHORISE — THE EXACT IRREVERSIBLE EFFECTS

```
POST …/membership_cleanup_v1
{"mode":"execute","user_id":"<the subject>","limit":1}
```

**Authority path first, and it can still refuse.** Claim the lease → a **fresh
authoritative Apple read** for the Sandbox row, verified against the pinned
anchor and applied through `membership_apply_reconciliation_v1` →
`membership_cleanup_authorised_v1`. **If Apple reports the subscription entitled,
or the schedule is no longer due, the worker returns `refused` and deletes
nothing** — a pass of the authority rule, not a failure.

**If it authorises, these are destroyed and CANNOT be recovered:**

| Irreversible | Count |
|---|---|
| The subject's post | **1** |
| Its storage object (`…678A7F2C-….m4a`) | **1** |
| **Comments on that post, authored by `Samuel Dixon` / `samueldixon`** — destroyed by the ratified cascade, **authorised as disposable 2026-09-02** | **3** |
| Follows, both directions | **2** |

**Retained, and asserted as hard as the deletions:** the subject's comment on
another member's post (**1**), the `account_directory` row and `display_name`,
`auth.users` (**17**, unchanged), and `membership` + `membership_binding`.

**Global effect:** posts **101 → 100**, comments **5 → 2**, follows **9 → 7**,
attachment objects **15 → 14**. Everything else unchanged.

**There is no undo.** No backup of Domain 3 content is taken. The schedule
restore in §3 becomes meaningless once cleanup has run — which is why its guard
is `cleanup_completed_at is null`.

**Still not exercised by this run**, unchanged and accepted: reference-counted
shared sent attachments, received references, received shares, comment-views,
avatar removal and C-33 ordering, B-19's addressed-on-others'-posts retention,
and F-2/F-4/F-5. **Local e2e (75/75) remains the coverage.**

---

## 8. STOPPED

**Awaiting explicit P5 destructive-execution authorisation.** No cleanup executed,
no scheduler, C-58 not started.
