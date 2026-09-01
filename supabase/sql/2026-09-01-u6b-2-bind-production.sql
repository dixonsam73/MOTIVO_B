-- U6b-2 — BIND ENFORCEMENT. THIS ONE DENIES.
--
-- Predictions F-1..F-5 and D-1..D-10 are committed in README-u6b-p6-binding.md
-- BEFORE this runs. Rollback is one row: see the tail.
--
-- ONE SUBMISSION, GUARD INSIDE, ENDING IN A SELECT THAT RETURNS A ROW.
-- "Success. No rows returned." is the symptom of a submission that ran the wrong
-- text -- it happened on the U6a deploy and it happened again on the U6b P1
-- verifier, which is why every mutating file here now returns a row.
--
-- PREREQUISITES, ASSERTED BELOW RATHER THAN REMEMBERED: U6b-1 deployed, 23
-- policies gated with zero bare calls, 4 subject-gated, 9 RPCs gated, drift zero,
-- and enforcement not already bound.

begin;

create temp table _u6b2_before on commit drop as
select (select count(*) from public.membership)                  as m,
       (select count(*) from public.membership_binding)          as b,
       (select count(*) from public.membership_cutover)          as c,
       (select count(*) from public.membership_binding_conflict) as x;

do $bind$
declare n int; mb int; bb int; cb int; xb int;
begin
  -- PRECONDITION 1 — the singleton control row, currently UNBOUND
  select count(*) into n from public.membership_control
   where id and enforcement_enabled = false and u6b_bound_at is null;
  if n <> 1 then
    raise exception 'ABORT: expected exactly 1 control row that is unbound with enforcement_enabled=false, found %', n;
  end if;

  -- PRECONDITION 2 — U6b-1 is deployed and intact
  select count(*) into n from pg_policies where schemaname in ('public','storage')
    and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_gate%';
  if n <> 23 then raise exception 'ABORT: % policies carry the gate, expected 23', n; end if;

  select count(*) into n from pg_policies where schemaname in ('public','storage')
    and (coalesce(qual,'')||' '||coalesce(with_check,'')) like '%enforcement_gate%'
    and (coalesce(qual,'')||' '||coalesce(with_check,'')) not like '%( SELECT enforcement_gate%';
  if n <> 0 then raise exception 'ABORT: % BARE gate calls -- binding must not ship the per-row Filter cliff', n; end if;

  select count(*) into n from pg_policies where schemaname in ('public','storage')
    and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_active%';
  if n <> 4 then raise exception 'ABORT: % policies carry the subject check, expected 4', n; end if;

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.prosrc like '%enforcement_gate%';
  if n <> 9 then raise exception 'ABORT: % RPCs carry the gate, expected 9', n; end if;

  -- PRECONDITION 3 — no uuid-taking entitlement predicate is client-reachable.
  -- Checked at the moment of binding, not assumed from the deployment record.
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
    cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r
   where ns.nspname='public' and p.proname in ('membership_entitled_until','connected_member')
     and has_function_privilege(r.rolname,p.oid,'EXECUTE');
  if n <> 0 then raise exception 'ABORT: a uuid-taking entitlement predicate is client-reachable'; end if;

  -- PRECONDITION 4 — visibility state agrees with authoritative membership.
  -- Binding on drifted data would deny the wrong people.
  select (select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id))
       + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id))
       + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id))
       + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id))
    into n;
  if n <> 0 then raise exception 'ABORT: % rows drift between stored and recomputed visibility', n; end if;

  -- THE BIND — one row, one boolean, one timestamp
  update public.membership_control
     set enforcement_enabled = true,
         u6b_bound_at        = now(),
         updated_at          = now()
   where id;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'ABORT: expected to update exactly 1 control row, updated %', n; end if;

  -- POSTCONDITION 1 — bound
  select count(*) into n from public.membership_control
   where id and enforcement_enabled = true and u6b_bound_at is not null;
  if n <> 1 then raise exception 'ABORT: the control row is not bound after the update'; end if;

  -- POSTCONDITION 2 — the membership tables are not this statement's business
  select m, b, c, x into mb, bb, cb, xb from _u6b2_before;
  if mb <> (select count(*) from public.membership)
     or bb <> (select count(*) from public.membership_binding)
     or cb <> (select count(*) from public.membership_cutover)
     or xb <> (select count(*) from public.membership_binding_conflict) then
    raise exception 'ABORT: a membership table moved during the bind (was %/%/%/%)', mb, bb, cb, xb;
  end if;
end
$bind$;

commit;

-- Returns a ROW. No UID is selected.
select
  (select enforcement_enabled from public.membership_control)            as enforcement_enabled,
  (select u6b_bound_at is not null from public.membership_control)       as bound,
  (select count(*) from public.membership)                               as membership_rows,
  (select count(*) from public.membership_binding)                       as binding_rows,
  (select count(*) from public.membership_cutover)                       as cutover_rows,
  (select count(*) from public.membership_binding_conflict)              as conflicts,
  (select count(*) from public.posts where owner_entitled_until > now()) as posts_visible_to_others,
  'U6b-2 BOUND -- enforcement is LIVE'                                   as status;

-- =========================================================== ROLLBACK
--
--   update public.membership_control
--      set enforcement_enabled = false, updated_at = now()
--    where id;
--   select enforcement_enabled, u6b_bound_at, 'ROLLED BACK' as status
--     from public.membership_control;
--
-- One row, effective on the next predicate evaluation: the flag is read live
-- inside the gate on every call, so there is no partially-applied window.
--
-- u6b_bound_at IS DELIBERATELY NOT CLEARED. It records that binding happened,
-- which stays true after a rollback -- and it means THIS FILE'S precondition 1
-- refuses to run a second time. A re-bind must be a conscious one-line act, not
-- a repeat of the deploy.
