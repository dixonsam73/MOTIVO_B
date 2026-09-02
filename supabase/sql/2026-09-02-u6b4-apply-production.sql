-- U6b-4 PRODUCTION APPLY — SELF-VERIFYING. 2026-09-02.
--
-- IRREVERSIBLE IN EFFECT. Before this runs, restoring grandfathering is ONE
-- BOOLEAN. After it, it is 2026-09-02-u6b4-rollback-production.sql. That is why
-- P3 is a separate human authorisation and not a step inside a sequence.
--
-- THIS DENIES NOTHING AND GRANTS NOTHING. enforcement_enabled is FALSE and stays
-- FALSE; the guard asserts it on both sides. This is not a bind and must never
-- be combined with one.
--
-- ITS BEHAVIOURAL DELTA IS ZERO AND THE GUARD PROVES IT RATHER THAN CLAIMING IT.
-- grandfather_enabled has been FALSE since 2026-09-01, so the arm being removed
-- is already inert. Guard B captures the (membership_state, connected_member)
-- census BEFORE the migration and asserts it is IDENTICAL after. If one identity
-- moves, the premise is wrong and the whole transaction aborts.
--
-- ONE SUBMISSION, GUARDS INSIDE, ENDING IN A SELECT THAT RETURNS A ROW.
-- "Success. No rows returned." is the symptom of a submission that ran the wrong
-- text -- it happened on the U6a deploy and cost a full diagnosis cycle.
--
-- The body between the VERBATIM markers is byte-identical to
-- supabase/migrations/20260902120000_u6b4_grandfather_retirement.sql.
--
-- REHEARSED LOCALLY BOTH WAYS. All eight suites green under it (U3 91, U4 99 +
-- e2e 43, U5 59 + e2e 62 + client 60, U6a 3, U6b 54 = 471 assertions, 0 fail),
-- and the rollback returned B-23 GATE MET on the rolled-back instance.

begin;

-- ============================================================ GUARD A -- PRE
do $$
declare n int;
begin
  select count(*) into n from information_schema.tables
   where table_schema='public' and table_name='membership_cutover';
  if n <> 1 then raise exception 'ABORT: membership_cutover absent -- U6b-4 may already have run'; end if;

  -- THE PREMISE. If grandfathering is live, this migration is NOT inert and
  -- would revoke access from every pre-cutover identity in one statement.
  select count(*) into n from public.membership_control where id and grandfather_enabled;
  if n <> 0 then raise exception 'ABORT: grandfather_enabled is TRUE -- U6b-4 assumes it is already false and would change behaviour'; end if;

  select count(*) into n from public.membership_control where id and enforcement_enabled;
  if n <> 0 then raise exception 'ABORT: enforcement_enabled is TRUE -- U6b-4 must not run against bound enforcement'; end if;

  select count(*) into n from public.membership_control where id and u6b_bound_at is not null;
  if n <> 1 then raise exception 'ABORT: u6b_bound_at is not set -- unexpected state'; end if;
end $$;

-- Behavioural census BEFORE, and the membership tables' row counts.
create temporary table u6b4_before on commit drop as
select coalesce(public.membership_state(u.id),'?') as st,
       coalesce(public.connected_member(u.id)::text,'?') as cm,
       count(*) as cnt
  from auth.users u group by 1,2;

create temporary table u6b4_rows_before on commit drop as
select (select count(*) from public.membership)                  as m,
       (select count(*) from public.membership_binding)           as b,
       (select count(*) from public.membership_binding_conflict)  as c,
       (select count(*) from public.membership_notification)      as nt,
       (select count(*) from public.shadow_enforcement_stat)      as ss,
       (select count(*) from auth.users)                          as au;

-- ============ BEGIN VERBATIM 20260902120000_u6b4_grandfather_retirement.sql ===
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
-- ============== END VERBATIM 20260902120000_u6b4_grandfather_retirement.sql ===

-- =========================================================== GUARD B -- POST
do $$
declare n int; d int;
begin
  -- B1. THE BEHAVIOURAL DELTA MUST BE ZERO. This is the whole safety argument.
  select count(*) into d from (
    -- the column is `cnt`, not `n`: `n` is also the PL/pgSQL variable above and
    -- PostgreSQL resolves the ambiguity by refusing. Caught in rehearsal.
    (select st,cm,cnt from u6b4_before
     except
     select coalesce(public.membership_state(u.id),'?'), coalesce(public.connected_member(u.id)::text,'?'), count(*)
       from auth.users u group by 1,2)
    union all
    (select coalesce(public.membership_state(u.id),'?'), coalesce(public.connected_member(u.id)::text,'?'), count(*)
       from auth.users u group by 1,2
     except
     select st,cm,cnt from u6b4_before)
  ) x;
  if d <> 0 then raise exception 'ABORT: the entitlement census CHANGED -- % differing buckets. U6b-4 was supposed to be inert', d; end if;

  -- B2. no membership data moved
  select count(*) into d from (
    (select * from u6b4_rows_before
     except
     select (select count(*) from public.membership), (select count(*) from public.membership_binding),
            (select count(*) from public.membership_binding_conflict), (select count(*) from public.membership_notification),
            (select count(*) from public.shadow_enforcement_stat), (select count(*) from auth.users))
  ) y;
  if d <> 0 then raise exception 'ABORT: a membership/auth row count moved -- U6b-4 writes no data'; end if;

  -- B3. the retired objects are gone
  select count(*) into n from information_schema.tables where table_schema='public' and table_name='membership_cutover';
  if n <> 0 then raise exception 'ABORT: membership_cutover survives'; end if;
  select count(*) into n from information_schema.columns
   where table_schema='public' and table_name='membership_control'
     and column_name in ('grandfather_enabled','grandfather_expires_at');
  if n <> 0 then raise exception 'ABORT: a grandfather control column survives'; end if;
  select count(*) into n from pg_proc p join pg_namespace nsp on nsp.oid=p.pronamespace
   where nsp.nspname='public' and p.prokind='f'
     and (pg_get_functiondef(p.oid) like '%membership_cutover%' or pg_get_functiondef(p.oid) like '%grandfather%');
  if n <> 0 then raise exception 'ABORT: a function still references a retired object'; end if;

  -- B4. THE RETAINED THINGS ARE STILL THERE
  select count(*) into n from information_schema.columns
   where table_schema='public' and table_name='membership_control'
     and column_name in ('cutover_at','cutover_identity_count','cutover_verified_at','u6b_bound_at','enforcement_enabled');
  if n <> 5 then raise exception 'ABORT: a RETAINED control column went missing -- expected 5, found %', n; end if;
  select count(*) into n from public.membership_control where id and u6b_bound_at is not null;
  if n <> 1 then raise exception 'ABORT: u6b_bound_at was disturbed'; end if;
  select count(*) into n from public.membership_control where id and enforcement_enabled;
  if n <> 0 then raise exception 'ABORT: enforcement_enabled is TRUE after the migration'; end if;

  -- B5. HISTORICAL TELEMETRY STAYS VALID. The constraint must still accept
  -- 'grandfathered'; a row in production carries it.
  select count(*) into n from pg_constraint
   where conname='shadow_stat_clause_check' and pg_get_constraintdef(oid) like '%grandfathered%';
  if n <> 1 then raise exception 'ABORT: shadow_stat_clause_check no longer accepts historical grandfathered'; end if;

  -- B6. PRIVILEGES UNCHANGED. CREATE OR REPLACE preserves grants, but the U6a
  -- rollback proved that assumption fails on a DROPPED function, so assert it.
  select count(*) into n from pg_proc p join pg_namespace nsp on nsp.oid=p.pronamespace
   cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r
   where nsp.nspname='public' and p.proname='connected_member' and has_function_privilege(r.rolname,p.oid,'EXECUTE');
  if n <> 0 then raise exception 'ABORT: connected_member became client-reachable -- B-33 regression'; end if;
  select count(*) into n from pg_proc p join pg_namespace nsp on nsp.oid=p.pronamespace
   cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r
   where nsp.nspname='public' and p.proname='membership_state' and has_function_privilege(r.rolname,p.oid,'EXECUTE');
  if n <> 1 then raise exception 'ABORT: membership_state EXECUTE is not exactly service_role -- found % roles', n; end if;

  -- B7. policies untouched
  select count(*) into n from pg_policies where schemaname in ('public','storage');
  if n <> 33 then raise exception 'ABORT: policy count moved to % -- U6b-4 touches no policy', n; end if;
end $$;

select (select count(*) from information_schema.tables
         where table_schema='public' and table_name='membership_cutover')      as cutover_table_rows,
       (select count(*) from information_schema.columns
         where table_schema='public' and table_name='membership_control')      as control_columns,
       (select cutover_at::text from public.membership_control)                as cutover_at_retained,
       (select cutover_identity_count from public.membership_control)          as cutover_count_retained,
       (select u6b_bound_at::text from public.membership_control)              as u6b_bound_at_preserved,
       (select enforcement_enabled from public.membership_control)             as enforcement_enabled,
       (select count(*) from pg_policies where schemaname in ('public','storage')) as policies,
       (select count(*) from public.membership)                                as membership_rows,
       (select count(*) from public.shadow_enforcement_stat
         where decided_clause='grandfathered')                                 as historical_grandfathered_rows,
       'U6b-4 APPLIED -- grandfather mechanism RETIRED, enforcement still OFF'  as status;

commit;
