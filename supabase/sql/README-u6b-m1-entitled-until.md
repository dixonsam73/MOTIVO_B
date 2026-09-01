# M1 — `entitled_until` DENORMALISATION. COMPLETE DESIGN, 2026-09-01.
# NOT IMPLEMENTED

**Nothing built, nothing deployed.** Decisions taken: **M1**; retained-comment
attribution accepted as historical and not a live presence; `follows_select_involved`
stays open.

---

## 0. A CORRECTION TO THE POLICY COUNT — it is 23/33, NOT 28/33

**I said 28 and that was wrong.** All four subject-gated **policies** are already
inside U6a's 23: `posts_select_public_or_owner`, `post_shares_select_recipient`,
`attachments_select_via_visible_post` and
`avatars_select_owner_or_approved_follower`. The fifth subject surface,
`search_account_directory`, is an **RPC, not a policy**.

**So the count is unchanged: 23 of 33 policies modified.** Subject-side gating
**deepens four existing quals** rather than touching new policies. The delta is
smaller than I told you, not larger — and the RPC count stays 9.

## 1. THE ONE CANONICAL DERIVATION

```sql
create function public.membership_entitled_until(target_user_id uuid)
  returns timestamptz language sql stable security definer set search_path = ''
as $$
  select max(greatest(
           m.renewal_date,
           case when m.is_in_billing_retry then m.grace_period_expires_date end
         ))
    from public.membership m
   where m.user_id = target_user_id
     and m.environment = 'Production';
$$;
```

**It is granted to NOBODY.** Not `authenticated`, not `anon`, not `service_role`.
It is reachable only from `SECURITY DEFINER` callers, so **no uuid-addressable
oracle is created** — D4 and B-33 are untouched.

**Three properties, each deliberate:**

- **`greatest` ignores NULLs in PostgreSQL** — it returns NULL only when every
  argument is NULL — so a row with no grace period yields `renewal_date`
  unchanged, with no `coalesce` gymnastics.
- **The grace term is `case when is_in_billing_retry then grace_period_expires_date end`,
  not the bare column.** Apple's formula requires retry **combined with** an
  unexpired grace period; **billing retry alone does not entitle**, and this is
  the exact line where the local matrix's rows 3 and 4 diverge.
- **`environment = 'Production'` matches D4 exactly.** A Sandbox row confers no
  visibility, so `sandbox_only` identities are invisible as authors just as they
  are unentitled as viewers.

## 2. THE FOUR COLUMNS — chosen so every gated surface reads a column it already reaches

| Table | Column | Subject | Serves |
|---|---|---|---|
| `posts` | `owner_entitled_until` | `owner_user_id` | `posts_select_public_or_owner`, **and** `attachments_select_via_visible_post` through its existing `exists (… from posts p …)` join |
| `post_shares` | `owner_entitled_until` | `owner_user_id` | `post_shares_select_recipient` |
| `follows` | `followed_entitled_until` | `followed_user_id` | `avatars_select_owner_or_approved_follower`, through its existing `exists (… from follows f …)` join |
| `account_directory` | `entitled_until` | `user_id` | `search_account_directory` |

**Four columns, five surfaces.** The storage policies need no column of their own
because **their quals already join the table that carries one** — which is also
why no column is added to `storage.objects`, a Supabase-managed table this project
should not be altering.

**`account_directory` is the reason a join-based design fails and this one does
not:** `account_directory_select_owner` is **owner-only**, so a policy joining to
another member's directory row sees nothing. Each column lives on a table the
viewer can already read for the row in question.

## 3. WHO MAINTAINS THEM — NOT the two write paths, and that is the stronger answer

**The question presupposes the weaker design.** If `membership_establish_v1` and
U4's canonical writer each maintained these columns, the semantics would live in
two places and **a third writer added later would silently skip them** — which is
exactly the failure this constraint exists to prevent.

**Instead: the writers touch `membership` only, and a single trigger derives
everything.**

```
tg_membership_propagate_entitled_until   AFTER INSERT OR UPDATE OR DELETE ON public.membership
  -> recompute membership_entitled_until(user_id)
  -> UPDATE posts / post_shares / follows / account_directory for that user
```

Plus **four BEFORE INSERT OR UPDATE row triggers**, one per table, that set the
column from the same function for newly created rows.

**Five triggers, one derivation, zero duplicated semantics.** The writers cannot
forget, a future writer cannot skip, and **the manual `membership` DELETE we ran
for G11 would have been covered automatically.**

**The columns are server-derived and client writes to them are impossible:** the
BEFORE triggers overwrite unconditionally, **and** INSERT/UPDATE on the four
columns is revoked from `authenticated` — B-14's precedent, and assertable in
`column_grants`.

## 4. LIFECYCLE

| Event | `membership` change | `entitled_until` becomes | Write needed? |
|---|---|---|---|
| **Initial establishment** | INSERT by attestation | `renewal_date` | yes, trigger fires |
| **Renewal** | UPDATE, `renewal_date` moves out | the new `renewal_date` | yes |
| **Voluntary cancellation** | UPDATE, auto-renew off | **unchanged** — still paid through | yes, no-op in effect |
| **Billing Grace** | retry true + grace set | `greatest(renewal_date, grace)` — **extended** | yes |
| **Billing retry, grace expired** | retry true, grace past | `greatest(renewal_date, past)` → past | yes |
| **Expiry** | often **no write at all** | already in the past | **NO — time does it** |
| **Resubscription** | UPDATE/INSERT, future date | future again → visible | yes |
| **Membership row absent** (deleted, or never established) | DELETE, or nothing | **NULL** → `NULL > now()` is NULL → not visible | yes on DELETE |

**`NULL > now()` evaluates to NULL, which a policy treats as false.** Absence is
never visibility, matching "absence is never entitlement" one level down.

## 5. BACKFILL — and its result today is startling but correct

Four `UPDATE … SET col = public.membership_entitled_until(subject)` statements at
migration time, inside the same transaction.

**PREDICTED RESULT: every row backfills to NULL.** There are **zero Production
membership rows** in production and there never have been — every membership row
ever created is Sandbox.

**So immediately after binding, the entire Connected corpus is invisible to
everyone.** That is **correct, not a regression**: nobody is entitled, so
viewer-side gating already denies every request. Subject-side gating denying the
same requests is consistent. **It must be predicted rather than discovered**, or it
will read as catastrophic when it is merely true.

## 6. DRIFT DETECTION — mechanical, re-runnable, and it belongs in production too

```sql
select
 (select count(*) from public.posts p
   where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id))
 + (select count(*) from public.post_shares s
   where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id))
 + (select count(*) from public.follows f
   where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id))
 + (select count(*) from public.account_directory d
   where d.entitled_until is distinct from public.membership_entitled_until(d.user_id))
 as drift_rows;   -- MUST be 0
```

`is distinct from` rather than `<>`, so **NULL-vs-NULL counts as agreement and
NULL-vs-value counts as drift** — the case a naive comparison silently passes.

**The check is time-independent**: both sides are stored/derived timestamps, not
booleans, so it neither drifts nor needs re-baselining as time passes. It goes in
the acceptance suite **and** in the standing production checks.

## 7. WHAT HAPPENS WHEN THE TIMESTAMP PASSES AND NO WORKER RUNS

**Nothing is written, and nothing needs to be.** `entitled_until > now()` simply
stops being true. **This is the entire reason M1 stores a timestamp instead of a
boolean** — a boolean would need a worker to flip it, no worker exists until U7,
and a stale boolean is a member visible after lapse.

**Consequence worth stating: expiry requires no infrastructure at all.** The
lapse-to-invisible transition is exact to the second, needs no notification, no
scheduler and no reconciliation, and cannot be missed.

## 8. ROLLBACK SHAPE

**The kill switch must disable subject-side gating too**, or the rollback only
half-rolls-back. Each of the five subject checks is written as:

```
and ((select not public.enforcement_active()) or <subject_col> > now())
```

`enforcement_active()` is zero-argument and discloses only a global flag — not an
oracle — and **the `(select …)` form makes it an InitPlan evaluated once per
query**, not per row, preserving G4-S3's 278ms-vs-3.9ms property. The per-row cost
stays a bare timestamp comparison.

| Level | Action | Effect |
|---|---|---|
| **Operational** | `enforcement_enabled = false` — **one row** | Viewer **and** subject gating both inert. Columns and triggers remain, harmlessly maintained |
| **Structural** | rollback baseline restores the 23 policies and 9 RPCs; drop 5 triggers, 4 columns, `membership_entitled_until` | Returns to the pre-U6b schema |

## 9. QA IMPLICATIONS

- **Local grant matrix gains a second axis**: 9 entitlement states × {entitled
  author, lapsed author}. Rows 3 and 4 — grace unexpired versus grace expired —
  are where a mistaken `greatest` term would show, and they are now the same
  assertion on both axes.
- **New assertion: the retention half, as hard as the hiding half.** A lapsed
  author's comments, their `get_account_directory_by_user_ids` attribution, and
  their live-referenced sent attachments must all **still resolve**.
- **New assertion: drift = 0** after every fixture mutation in the suite.
- **New assertion:** `membership_entitled_until` carries EXECUTE for **nobody**,
  and the four columns carry no INSERT/UPDATE for `authenticated`.
- **Production QA is unchanged and still deny-side only.** The subject-side half
  needs an entitled viewer *and* a lapsed author simultaneously; Gate 6 already
  established an entitled viewer is unobtainable before release. **Subject-side
  verification is LOCAL-ONLY pre-release.**
- **The release gate widens**: the first real subscriber verifies the grant path
  **and** that a lapsed author is invisible to them.

## 10. ONE MEASUREMENT REQUIRED BEFORE IMPLEMENTATION — B-33's lesson, applied early

**Claim to be tested, not assumed:** a `SECURITY DEFINER` trigger function fires
for an `authenticated` caller **without** that role holding EXECUTE on it, so
`membership_entitled_until` can stay granted to nobody.

**B-33 exists because exactly this class of assumption — "a function reached
indirectly needs no grant" — was written into a deployed comment and was FALSE.**
It is correct-sounding and unfalsifiable by reading. The experiment is local,
cheap and binary: create the trigger, insert as `authenticated`, observe whether it
fires or raises `permission denied for function`.

**If it fires:** implement as designed. **If it does not:** the trigger function
needs a grant — and since trigger functions take no arguments, granting it is
still **not** an oracle, so the design survives with one extra grant. **Either
outcome is safe; only the unmeasured version is not.**

---

## NO NEW PRODUCT DECISION AND NO NEW SECURITY EXCEPTION

- No entitlement override, allowlist or Sandbox exception.
- `connected_member(uuid)` and `membership_state(uuid)` remain ungranted;
  `membership_entitled_until(uuid)` joins them, granted to nobody.
- D4 untouched. B-33 untouched. B-5's hardened directory untouched.
- The retention rules are asserted, not merely preserved.
- **One measurement stands between this design and implementation.**
