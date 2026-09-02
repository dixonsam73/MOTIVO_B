-- U6b-2b — RE-BIND ENFORCEMENT after the aborted first attempt. THIS ONE DENIES.
--
-- NOT a replay of 2026-09-01-u6b-2-bind-production.sql. That statement's first
-- precondition requires `u6b_bound_at IS NULL` and will REFUSE, by design: a
-- re-bind must be a conscious act, never a repeat of the deploy. This file is the
-- conscious act, and it asserts the OPPOSITE precondition -- that binding has
-- happened before -- so the two can never be confused for one another.
--
-- WHAT IS DELIBERATELY NOT DONE: `u6b_bound_at` is NOT rewritten. It records when
-- enforcement was FIRST bound (2026-09-01 16:52:52) and that stays true.
-- `updated_at` carries the time of this change.
--
-- ONE SUBMISSION, GUARD INSIDE, ENDING IN A SELECT THAT RETURNS A ROW.

begin;

create temp table _u6b2b_before on commit drop as
select (select count(*) from public.membership)                  as m,
       (select count(*) from public.membership_binding)          as b,
       (select count(*) from public.membership_binding_conflict) as x;

do $rebind$
declare n int; mb int; bb int; xb int;
begin
  -- PRECONDITION 1 — currently UNBOUND, and previously BOUND. This is a re-bind.
  select count(*) into n from public.membership_control
   where id and enforcement_enabled = false and u6b_bound_at is not null;
  if n <> 1 then
    raise exception 'ABORT: expected the control row to be enforcement_enabled=false WITH u6b_bound_at already set (a re-bind). Found %. If u6b_bound_at is null this is a FIRST bind -- use 2026-09-01-u6b-2-bind-production.sql.', n;
  end if;

  -- PRECONDITION 2 — U6b-1 intact
  select count(*) into n from pg_policies where schemaname in ('public','storage')
    and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_gate%';
  if n <> 23 then raise exception 'ABORT: % policies carry the gate, expected 23', n; end if;

  select count(*) into n from pg_policies where schemaname in ('public','storage')
    and (coalesce(qual,'')||' '||coalesce(with_check,'')) like '%enforcement_gate%'
    and (coalesce(qual,'')||' '||coalesce(with_check,'')) not like '%( SELECT enforcement_gate%';
  if n <> 0 then raise exception 'ABORT: % BARE gate calls -- the per-row Filter cliff', n; end if;

  select count(*) into n from pg_policies where schemaname in ('public','storage')
    and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_active%';
  if n <> 4 then raise exception 'ABORT: % policies carry the subject check, expected 4', n; end if;

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.prosrc like '%enforcement_gate%';
  if n <> 9 then raise exception 'ABORT: % RPCs carry the gate, expected 9', n; end if;

  -- PRECONDITION 3 — no uuid-taking entitlement predicate is client-reachable
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
    cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r
   where ns.nspname='public' and p.proname in ('membership_entitled_until','connected_member')
     and has_function_privilege(r.rolname,p.oid,'EXECUTE');
  if n <> 0 then raise exception 'ABORT: a uuid-taking entitlement predicate is client-reachable'; end if;

  -- PRECONDITION 4 — visibility state agrees with authoritative membership
  select (select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id))
       + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id))
       + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id))
       + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id))
    into n;
  if n <> 0 then raise exception 'ABORT: % rows drift between stored and recomputed visibility', n; end if;

  -- PRECONDITION 5 — NO PRODUCTION ENTITLEMENT EXISTS.
  -- If one appeared, the deny-path QA below would no longer be the whole story
  -- and the grant path would need the settled release-gate treatment instead.
  select count(*) into n from public.membership where environment = 'Production';
  if n <> 0 then raise exception 'ABORT: % Production membership rows exist -- stop and re-plan; this is no longer a deny-path-only run', n; end if;

  -- PRECONDITION 6 — REMOVED 2026-09-02, AND DELIBERATELY NOT REPLACED.
  --
  -- It required exactly ONE LIVE Sandbox fixture, and its own comment said why:
  -- "do not bind without something to test", made structural after the first
  -- attempt burned its window with nothing to score. **THAT WAS QA READINESS,
  -- NOT A PRODUCTION SAFETY INVARIANT, AND P6 DISCHARGED IT** -- the deny-path
  -- evidence for the sandbox_only class exists and is committed. Keeping it
  -- would have forced a fresh Apple Sandbox subscription to satisfy a spent
  -- guard, on a tester already at Apple's ~12-renewal cap.
  --
  -- A REPLACEMENT WAS DRAFTED AND REJECTED ON MEASUREMENT, NOT ON TASTE. The
  -- candidate was "zero Sandbox membership rows may read connected_member =
  -- true" -- the half that looked like a genuine invariant. It fails twice:
  --
  --   (i) IT CANNOT FIRE. Precondition 5 already asserts zero Production
  --       membership rows, and with the grandfather arm retired (U6b-4)
  --       connected_member is false for EVERY identity. The count is
  --       structurally 0, so the assertion can never fail -- the C56-7 defect,
  --       a check that only looks like verification.
  --
  --   (ii) IT WOULD MIS-FIRE IF PRECONDITION 5 WERE EVER RELAXED. An identity
  --        holding BOTH a Sandbox and a live Production subscription is
  --        explicitly permitted -- "one identity may hold both a Sandbox and a
  --        Production membership" -- and reads connected_member = true, so the
  --        guard would count its Sandbox row and abort on a LEGITIMATE state.
  --        Measured locally, not reasoned: connected_member=true,
  --        state=entitled, guard counts 1.
  --
  -- Simultaneously vacuous now and wrong later. **PRECONDITION 5 -- zero
  -- Production membership rows -- already carries the load**, and the
  -- environment-separation invariant itself is established elsewhere: U6b
  -- acceptance E5 (sandbox_only -> DENY), D4's own design record, and the live
  -- production check run during this bind's preflight. The final bind does not
  -- acquire a testing subsystem to re-prove them.

  -- THE RE-BIND. u6b_bound_at is NOT rewritten.
  update public.membership_control
     set enforcement_enabled = true,
         updated_at          = now()
   where id;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'ABORT: expected to update exactly 1 control row, updated %', n; end if;

  -- POSTCONDITION 1 — bound, and the original bind timestamp preserved
  select count(*) into n from public.membership_control
   where id and enforcement_enabled = true
     and u6b_bound_at = timestamptz '2026-09-01 16:52:52.452956+00';
  if n <> 1 then raise exception 'ABORT: not bound, or u6b_bound_at was altered'; end if;

  -- POSTCONDITION 2 — the membership tables are not this statement's business
  select m, b, x into mb, bb, xb from _u6b2b_before;
  if mb <> (select count(*) from public.membership)
     or bb <> (select count(*) from public.membership_binding)
     or xb <> (select count(*) from public.membership_binding_conflict) then
    raise exception 'ABORT: a membership table moved during the re-bind (was %/%/%)', mb, bb, xb;
  end if;
end
$rebind$;

commit;

-- Returns a ROW. No UID is selected.
select
  (select enforcement_enabled from public.membership_control)              as enforcement_enabled,
  (select u6b_bound_at::text from public.membership_control)               as u6b_bound_at_preserved,
  (select updated_at::text from public.membership_control)                 as rebound_at,
  (select count(*) from public.membership where environment='Production')  as production_rows,
  (select count(*) from public.membership)                                 as membership_rows,
  (select count(*) from public.membership_binding)                         as binding_rows,
  (select count(*) from public.membership_binding_conflict)                as conflicts,
  (select count(*) from public.posts where owner_entitled_until > now())   as posts_visible_to_others,
  'U6b-2b RE-BOUND -- enforcement is LIVE'                                 as status;

-- =========================================================== KILL SWITCH
--
--   update public.membership_control
--      set enforcement_enabled = false, updated_at = now()
--    where id;
--   select enforcement_enabled, u6b_bound_at, updated_at, 'ROLLED BACK' as status
--     from public.membership_control;
--
-- One row, effective on the next predicate evaluation: the flag is read live
-- inside enforcement_gate() on every call, so there is no partially-applied
-- window and no cache. u6b_bound_at is never cleared.
