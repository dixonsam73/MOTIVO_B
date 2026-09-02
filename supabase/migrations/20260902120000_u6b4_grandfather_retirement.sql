-- U6b-4 — GRANDFATHER RETIREMENT. THE CLEANUP MIGRATION.
--
-- THIS IS IRREVERSIBLE IN EFFECT AND REQUIRES SEPARATE HUMAN AUTHORISATION.
-- `grandfather_enabled` is the switch that made grandfathering restorable with
-- one boolean. This migration DROPS that switch. After it runs, restoring
-- grandfathering means restoring a table, two columns and two function bodies
-- from the rollback file -- never a flag flip. That is the whole reason P3 is a
-- separate authorisation point rather than a step inside a sequence.
--
-- ITS BEHAVIOURAL DELTA IS ZERO, AND THAT IS MEASURED RATHER THAN HOPED.
-- `grandfather_enabled` has been FALSE in production since 2026-09-01, so
-- `connected_member`'s middle arm already returns false for every identity and
-- `membership_state` already reaches its final `else`. Measured 2026-09-02:
-- 1 identity `sandbox_only`/false and 16 `unknown`/false, all 17 false. This
-- migration removes an arm that is ALREADY INERT. If any identity's state
-- changes, the premise is wrong and the guard aborts.
--
-- WHAT IS DELIBERATELY NOT TOUCHED, each for its own reason:
--
--   shadow_stat_clause_check  -- MUST CONTINUE ACCEPTING 'grandfathered'.
--     A historical telemetry row carries that value (2026-09-01 10:13:15) and
--     the aggregate is keyed on decided_clause, so the before and after of the
--     retirement sit in the same table as evidence. Narrowing the constraint
--     alongside the branch would break existing rows. It is preserved by NOT
--     ACTING, which is the safest form of preservation available.
--
--   u6b_bound_at  -- LIVE STATE, NOT DEAD. It records that binding happened and
--     it makes the bind statement REFUSE to run a second time. The 2026-09-01
--     retirement design listed it as dead; that was written BEFORE U6b bound and
--     is now wrong. Corrected here rather than inherited.
--
--   cutover_at, cutover_identity_count, cutover_verified_at  -- RETAINED as the
--     historical record of a boundary that was declared, verified and is now
--     spent. No function reads cutover_at (measured: zero references in all 28
--     production functions). Dropping them would destroy a fact for no benefit,
--     and CLAUDE.md's standing rule is that cutover_at is never altered.
--
--   enforcement_enabled  -- NOT TOUCHED. It is FALSE and must remain FALSE.
--     This migration is not a bind and must never be combined with one.
--
-- Dependency surface, measured from the verified production snapshot rather than
-- assumed: membership_cutover, grandfather_enabled and grandfather_expires_at
-- are referenced by EXACTLY ONE function, connected_member; the 'grandfathered'
-- literal by EXACTLY ONE, membership_state. Zero policies reference any of them.

-- ============================================================ 1. the predicate
--
-- The middle coalesce arm goes. Two arms remain: authoritative membership, then
-- false. D4's bool_or-over-an-empty-set subtlety and its clause ordering both
-- disappear -- not because they were wrong, but because there is no longer a
-- second clause for the ordering to matter to.
--
-- The environment filter STAYS INSIDE bool_or and does NOT move to the WHERE.
-- That is D4's correction and it survives the simplification: a Sandbox-only
-- identity must produce a non-empty row set whose expression is false, so
-- bool_or returns FALSE rather than NULL. With the grandfather arm gone the
-- fall-through would now be `false` either way -- but leaving the filter in the
-- WHERE would silently re-break the moment anyone adds a third arm.

create or replace function public.connected_member(target_user_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $function$
  select coalesce(
    (select bool_or(
         m.environment = 'Production'
         and (coalesce(m.renewal_date > now(), false)
              or coalesce(m.is_in_billing_retry
                          and m.grace_period_expires_date > now(), false))
       )
       from public.membership m
      where m.user_id = target_user_id),      -- NO environment filter here

    false
  );
$function$;

comment on function public.connected_member(uuid) is
  'Production entitlement, Apple''s formula exactly. U6b-4 removed the '
  'grandfather compatibility arm (B-36): the pre-cutover snapshot had no '
  'entitlement predicate, so it granted Connected to every identity that '
  'existed rather than every identity that paid. Retired, not satisfied.';

-- ================================================================ 2. the state
--
-- Four live values: entitled, expired, sandbox_only, unknown. 'grandfathered'
-- is no longer producible. Historical telemetry rows carrying it remain valid
-- and the check constraint still permits it -- see the header.

create or replace function public.membership_state(target_user_id uuid)
  returns text
  language sql
  stable
  security definer
  set search_path = ''
as $function$
  select case
    when exists (select 1 from public.membership m
                  where m.user_id = target_user_id
                    and m.environment = 'Production')
      then case when public.connected_member(target_user_id)
                then 'entitled' else 'expired' end
    when exists (select 1 from public.membership m
                  where m.user_id = target_user_id)
      then 'sandbox_only'
    else 'unknown'
  end;
$function$;

comment on function public.membership_state(uuid) is
  'Four states: entitled, expired, sandbox_only, unknown. U6b-4 removed '
  '''grandfathered'' as a producible value (B-36). Historical '
  'shadow_enforcement_stat rows carrying it stay valid and permitted.';

-- ======================================================== 3. the dead objects
--
-- CREATE OR REPLACE above preserves EXECUTE grants; a drop-and-create would not.
-- That distinction cost a rollback defect during U6a, where CREATE OR REPLACE on
-- a DROPPED function yielded default privileges including PUBLIC EXECUTE, and
-- only the B-23 gate caught it. The guard below asserts the grants explicitly
-- rather than trusting the mechanism.

drop table public.membership_cutover;

alter table public.membership_control
  drop column grandfather_enabled,
  drop column grandfather_expires_at;
