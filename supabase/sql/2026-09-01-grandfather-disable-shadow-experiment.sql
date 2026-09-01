-- GRANDFATHER SHADOW EXPERIMENT — set grandfather_enabled = false while U6a is
-- still SHADOW-ONLY, so the window shows exactly what U6b would deny while
-- denying nothing.
--
-- Predictions GF-1..GF-9 are committed in README-grandfather-retirement.md §5.
-- ROLLBACK is one row: see the tail of this file.
--
-- WHY THIS IS SAFE, AND THE GUARD CHECKS IT RATHER THAN TRUSTING THIS COMMENT:
-- nothing reads connected_member() to DECIDE anything. Its only reader is
-- shadow_observe, which returns true on every path. The guard below asserts,
-- against the live catalog and at the moment of the change, that no policy
-- references an entitlement predicate directly and that the observer is still
-- the inert one. A safety premise that is only asserted in prose is a premise
-- nobody checked.
--
-- ONE SUBMISSION, GUARD INSIDE, ENDING IN A SELECT THAT RETURNS A ROW.
-- "Success. No rows returned." is the symptom of a submission that ran the wrong
-- text -- it happened on the U6a deploy and cost a full diagnosis cycle.

begin;

do $gf$
declare
  n integer; m_before integer; b_before integer; c_before integer; x_before integer;
begin
  -- PRECONDITION 1 — the singleton control row, grandfathering currently ON
  select count(*) into n from public.membership_control where id and grandfather_enabled;
  if n <> 1 then
    raise exception 'ABORT: expected exactly 1 control row with grandfather_enabled = true, found %', n;
  end if;

  -- PRECONDITION 2 — the cutover boundary is the one this experiment was
  -- designed against. A different snapshot means different predictions.
  select count(*) into n from public.membership_control
   where cutover_at = timestamptz '2026-08-17 19:08:27.125223+00'
     and cutover_identity_count = 16;
  if n <> 1 then
    raise exception 'ABORT: cutover boundary or identity count is not the expected one';
  end if;

  -- PRECONDITION 3 — ENFORCEMENT IS NOT BOUND. This is the whole safety
  -- argument. After U6b binds, flipping this flag is a live access change and
  -- this statement must NOT be used.
  select count(*) into n from public.membership_control where u6b_bound_at is null;
  if n <> 1 then
    raise exception 'ABORT: u6b_bound_at is set -- enforcement is BOUND. This experiment is only safe while shadow-only.';
  end if;

  -- PRECONDITION 4 — NO POLICY CONSULTS AN ENTITLEMENT PREDICATE DIRECTLY.
  -- Checked against the live catalog, not assumed from the deployment record.
  select count(*) into n from pg_policies
   where schemaname in ('public','storage')
     and (coalesce(qual,'')||' '||coalesce(with_check,'')) ~ '(connected_member|membership_state|connected_member_self)\s*\(';
  if n <> 0 then
    raise exception 'ABORT: % policies reference an entitlement predicate directly -- this flag would change access, not telemetry', n;
  end if;

  -- PRECONDITION 5 — the observer is still the inert one: fail-open, and no
  -- path that returns false.
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'shadow_observe'
     and p.prosrc like '%exception when others%'
     and p.prosrc !~* 'return\s+false';
  if n <> 1 then
    raise exception 'ABORT: shadow_observe is not the inert fail-open observer';
  end if;

  -- PRECONDITION 6 — 23 policies still carry the observer (U6a intact)
  select count(*) into n from pg_policies
   where schemaname in ('public','storage')
     and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%';
  if n <> 23 then
    raise exception 'ABORT: % policies carry the observer, expected 23', n;
  end if;

  -- capture the membership tables so the change can be proven to touch none
  select count(*) into m_before from public.membership;
  select count(*) into b_before from public.membership_binding;
  select count(*) into c_before from public.membership_cutover;
  select count(*) into x_before from public.membership_binding_conflict;

  -- THE CHANGE — one row, one boolean
  update public.membership_control
     set grandfather_enabled = false,
         updated_at = now()
   where id;
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'ABORT: expected to update exactly 1 control row, updated %', n;
  end if;

  -- POSTCONDITION 1 — the flag is off
  select count(*) into n from public.membership_control where id and grandfather_enabled = false;
  if n <> 1 then
    raise exception 'ABORT: grandfather_enabled is not false after the update';
  end if;

  -- POSTCONDITION 2 — GF-9: not one membership table moved
  select count(*) into n from public.membership;
  if n <> m_before then raise exception 'ABORT: membership row count moved % -> %', m_before, n; end if;
  select count(*) into n from public.membership_binding;
  if n <> b_before then raise exception 'ABORT: membership_binding moved % -> %', b_before, n; end if;
  select count(*) into n from public.membership_cutover;
  if n <> c_before then raise exception 'ABORT: membership_cutover moved % -> %', c_before, n; end if;
  select count(*) into n from public.membership_binding_conflict;
  if n <> x_before then raise exception 'ABORT: membership_binding_conflict moved % -> %', x_before, n; end if;

  -- POSTCONDITION 3 — GF-1/GF-2: all 15 grandfather-dependent identities now
  -- decide false, and land on 'unknown' rather than 'expired'.
  select count(*) into n from public.membership_cutover c
   where not exists (select 1 from public.membership m where m.user_id = c.user_id)
     and (public.connected_member(c.user_id) is distinct from false
          or public.membership_state(c.user_id) is distinct from 'unknown');
  if n <> 0 then
    raise exception 'ABORT: % grandfather-dependent identities did not resolve to unknown/false', n;
  end if;
end
$gf$;

commit;

-- Returns a ROW. No UID is selected.
select
  (select grandfather_enabled from public.membership_control)                as grandfather_enabled,
  (select count(*) from public.membership_cutover c
    where not exists (select 1 from public.membership m where m.user_id=c.user_id)
      and public.connected_member(c.user_id) = false)                        as pre_cutover_now_denied,
  (select count(*) from public.membership_cutover c
    where not exists (select 1 from public.membership m where m.user_id=c.user_id)
      and public.membership_state(c.user_id) = 'unknown')                    as now_unknown,
  (select count(*) from public.membership_cutover c
    where not exists (select 1 from public.membership m where m.user_id=c.user_id)
      and public.membership_state(c.user_id) = 'grandfathered')              as still_grandfathered,
  (select public.membership_state(b.user_id)  from public.membership_binding b) as device_a_state,
  (select public.connected_member(b.user_id)  from public.membership_binding b) as device_a_connected,
  (select count(*) from public.membership)                                   as membership_rows,
  (select count(*) from public.membership_binding)                           as binding_rows,
  (select count(*) from public.membership_cutover)                           as cutover_rows,
  (select count(*) from public.membership_binding_conflict)                  as conflicts,
  'GRANDFATHER DISABLED -- shadow only, nothing enforced'                    as status;

-- =========================================================== ROLLBACK
-- One row, effective on the next predicate evaluation. The flag is read live
-- inside connected_member() on every call, so there is no partially-applied
-- window and no cache to clear.
--
--   begin;
--   do $rb$
--   declare n integer;
--   begin
--     update public.membership_control set grandfather_enabled = true, updated_at = now() where id;
--     get diagnostics n = row_count;
--     if n <> 1 then raise exception 'ABORT: expected 1 row, updated %', n; end if;
--     select count(*) into n from public.membership_cutover c
--      where not exists (select 1 from public.membership m where m.user_id = c.user_id)
--        and public.connected_member(c.user_id) = true;
--     if n <> 15 then raise exception 'ABORT: expected 15 identities restored, got %', n; end if;
--   end
--   $rb$;
--   commit;
--   select grandfather_enabled, 'ROLLED BACK' as status from public.membership_control;
