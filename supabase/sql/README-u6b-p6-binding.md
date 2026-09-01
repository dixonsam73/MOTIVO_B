# P6 — BINDING ENFORCEMENT. PREDICTIONS, committed 2026-09-01 BEFORE THE FLIP

**NOTHING BELOW IS A RESULT.** `enforcement_enabled` is `false` in production as
this is committed. Every number is a claim that can be wrong.

**Scope discipline: this is one row and a QA fixture, not a migration
programme.** No per-user override, no Production fake entitlement, no allowlist,
no Sandbox entitlement exception. **Genuine Production GRANT-path verification
remains deferred to the first real App Store subscription after public release**
— settled, and nothing here discharges it.

---

## 1. STATE AT THE MOMENT OF WRITING — read from production

| | |
|---|---|
| `enforcement_enabled` / `u6b_bound_at` | **false / null** |
| Device A membership | 1 row, **Sandbox**, `renewal_date` past → **not entitled** |
| Device A `membership_state()` / `connected_member()` | **`sandbox_only` / false** |
| Device B | **no membership row** → `unknown` / false |
| `posts` total | **101** — Device A owns **1**, Device B owns **6** |
| rows with a non-null `entitled_until` | **0** — no Production membership row has ever existed |
| drift | **0** |

## 2. THE QA FIXTURE — a genuine Sandbox resubscription, and nothing else

**Device A is restored by an ordinary Apple Sandbox resubscription on tester 2.**
That is a real purchase through Apple, not fabricated state: it produces a real
`SUBSCRIBED`/`RESUBSCRIBE` notification and a real refreshed `membership` row.

**It gives the one fixture shape we cannot otherwise get: client-Connected and
server-`sandbox_only` simultaneously.** The client resolves `AppMode` from local
StoreKit, so Device A returns to the full Connected UI, while D4 keeps
`connected_member()` false because the row is Sandbox. **That divergence is
exactly what P6 must be tested against**, and it needs no exception of any kind to
produce.

**Predicted afterwards:** `membership_state()` stays **`sandbox_only`**,
`connected_member()` stays **false**, `entitled_until` stays **NULL** everywhere
(the derivation is Production-only), and **drift stays 0**.

## 3. PRE-FLIP PREDICTIONS

| # | Prediction |
|---|---|
| **F-1** | The statement updates **exactly one row** |
| **F-2** | `enforcement_enabled` **false → true**, `u6b_bound_at` **null → set** |
| **F-3** | No membership table moves: `membership` 1, `membership_binding` 1, `membership_cutover` 16, conflicts 0 |
| **F-4** | Policy and function definitions are **untouched** — this writes one boolean and one timestamp |
| **F-5** | Drift stays **0** |

## 4. POST-FLIP PREDICTIONS — deny path

**Both devices are unentitled under the authoritative Production decision.** The
client still shows Connected on Device A, because `AppMode` is local. **That is
the predicted UX and not a defect.**

| # | Prediction |
|---|---|
| **D-1** | **The feed is not empty — it shows ONLY the viewer's own posts.** The owner branch of `posts_select_public_or_owner` stays open. Device A sees **1**, Device B sees **6** |
| **D-2** | Opening another member's post: **not found** |
| **D-3** | Publishing a session: **refused** |
| **D-4** | Commenting: **refused**, `not permitted` |
| **D-5** | Another member's attachment bytes: **refused** |
| **D-6** | **Own** attachment bytes: **still readable** — `attachments_user_select_auth` is untouched (D-U6-4) |
| **D-7** | Directory search: **returns nothing** |
| **D-8** | **Own profile loads and edits** — D-U6-3 |
| **D-9** | **Account deletion stays reachable** — D-U6-2 and C-35. **Confirm reachable; DO NOT run it** |
| **D-10** | Telemetry gains rows with **`enforced = true`** and **`would_deny = true`**, sitting beside the historical `enforced = false` rows rather than merging |

**Subject-side is unobservable in this run and that is expected, not a gap.**
Every `entitled_until` is NULL because no Production membership row has ever
existed, so no viewer is entitled and nothing reaches the subject branch. The
subject rule is covered by U6b acceptance locally (`U6b-F1`/`F2`) and by the
release gate.

## 5. STOP CONDITIONS — roll back immediately

- **Any carve-out failing:** own material unreadable, own profile uneditable, or
  **account deletion unreachable**. These are D-U6-2/3/4 and C-35, and they are
  the only failures that are *dangerous* rather than merely wrong.
- Anything failing on a path predicted to **succeed**.
- An **error** where an empty or filtered result was predicted — a denied `SELECT`
  returns zero rows, never an exception.
- Any row moving in `membership`, `membership_binding`, `membership_cutover` or
  `membership_binding_conflict`.
- Drift ≠ 0.

**NOT a stop:** unentitled devices being denied, or a feed showing only your own
posts. That is the unit working.

## 6. ROLLBACK

```sql
update public.membership_control set enforcement_enabled = false, updated_at = now() where id;
```

**One row, effective on the next predicate evaluation** — the flag is read live
inside the gate on every call, so there is no partially-applied window and no
cache.

**`u6b_bound_at` is deliberately NOT cleared.** It records that binding happened,
which stays true after a rollback. The consequence is intended: **P6's guard
requires `u6b_bound_at IS NULL`, so it cannot be re-run silently after a
rollback** — a second bind must be a conscious act, not a repeat.

## 7. WHAT P6 DOES NOT ESTABLISH

**Nothing about the GRANT path.** No Production membership row exists, so no
identity is entitled and the allow branch is never exercised in production. That
is the release gate, unchanged: **before a second paying subscriber exists, the
first genuine App Store subscription is verified end to end.** P6 proves the deny
path and the carve-outs; it cannot and does not prove the grant path.

---

# P6 RESULT — BOUND, THEN ROLLED BACK. DENY-PATH QA **INCOMPLETE**. 2026-09-01

## What happened, as facts

| | |
|---|---|
| **Bound** | `enforcement_enabled = true`, `u6b_bound_at` = **2026-09-01 16:52:52.452956+00** |
| **Rolled back** | `enforcement_enabled = false` at **2026-09-01 16:58:29.176354+00** |
| **`u6b_bound_at`** | **retained, deliberately** — it records that binding happened, which stays true |
| **Now** | `enforcement_enabled` **FALSE**. **U6b-1 remains deployed and INERT** |

## The structural bind SUCCEEDED and every prediction held

All ten guards passed and the returned row matched exactly: `enforcement_enabled t`,
`bound t`, membership 1, binding 1, cutover 16, conflicts 0,
`posts_visible_to_others` 0.

Verified independently afterwards: `enforcement_active()` **true**, Device A
`sandbox_only` / false, **drift 0**, and the policy fingerprint **unchanged at the
U6b-1 value** — proof that P6 wrote one boolean and one timestamp and nothing else.

**F-1 to F-5 all hold.**

## THE BEHAVIOURAL DENY-PATH QA IS INCOMPLETE, AND IS NOT RECORDED AS ANYTHING ELSE

**A Supabase service incident was in progress during the QA window.** Device
symptoms observed under it — an empty feed with its empty-state message *absent*,
and author attribution rendering as `User` instead of the stored display name —
are the shape of **failed** requests rather than denied ones: a denial returns
zero rows and would render the empty state.

**So the observations are contaminated and cannot be scored.** Of D-1 to D-10,
**none is recorded as passed or failed.**

**What the telemetry shows is the whole behavioural evidence there is:**

```
16:54:13  sandbox_only (Device A)  rpc.has_unread_private_comments  deny=true  n=3
16:56:36  unknown      (Device B)  rpc.has_unread_private_comments  deny=true  n=6
16:56:39  unknown      (Device B)  storage.attachments_recipient    deny=true  n=1
```

**Three rows, ten observations, two surfaces.** `posts.select` **never fired**, so
D-1 — the prediction that the feed shows only the viewer's own posts — went
**untested rather than falsified**, and publish, comment, own-attachment,
own-profile and account-deletion-reachable were never exercised at all.

**THE DENY PATH IS NOT VERIFIED IN PRODUCTION.** The two surfaces that were
exercised both denied gracefully, which is consistent with the design and is not
a substitute for the gate.

## What must happen before P6 is attempted again

1. The Supabase incident is **resolved**.
2. Both devices relaunched with enforcement **off**, confirming normal behaviour —
   a clean baseline before re-binding.
3. **A re-bind is a conscious act, not a repeat.** `u6b_bound_at` is set, so
   `2026-09-01-u6b-2-bind-production.sql` will **refuse** on its first
   precondition. That is by design.
4. Device A's `sandbox_only` fixture re-established if it has lapsed again — its
   `renewal_date` was 17:21:02.

**C-55 is open and unrelated to enforcement**; it does not block P6, but Device A
cannot serve as a QA fixture while it is unobservable.
