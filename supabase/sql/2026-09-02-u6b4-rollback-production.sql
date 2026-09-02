-- U6b-4 ROLLBACK — regenerated from PRODUCTION, 2026-09-02.
--
-- Restores the grandfather mechanism: the snapshot table, the two control
-- columns, and both function bodies. Rehearsed end to end locally, and the proof
-- is not that the statements succeeded -- it is that B-23 returned GATE MET on
-- the rolled-back instance, which is structural identity with live production.
--
-- ============================ READ THIS BEFORE RELYING ON IT ================
--
-- THIS ROLLBACK IS STRUCTURALLY COMPLETE AND DATA-COMPLETE ONLY CONDITIONALLY.
--
-- The 16 snapshot rows are destroyed by the DROP. They are RECONSTRUCTED here
-- from auth.users using the RETAINED cutover_at -- which is exactly the original
-- population predicate, so no identifier needs to live in this repository. That
-- reconstruction was verified against production on 2026-09-02 before U6b-4 was
-- offered: 16 rows, 16 recorded, 16 reconstructible, and ZERO discrepancy in
-- BOTH directions.
--
-- IT STOPS BEING EXACT THE MOMENT A PRE-CUTOVER IDENTITY IS DELETED. Guard 5
-- refuses rather than restoring a smaller snapshot that would silently
-- under-grandfather. If it fires, the rollback is genuinely lossy and that is a
-- decision for a person, not for this file.
--
-- captured_at IS NOT RECOVERED. The identities are exact; their capture
-- timestamps become now(). Nothing reads captured_at -- the grandfather clause
-- never did -- so this is a fidelity loss in the record, not in behaviour. It is
-- stated because a rollback that quietly invents data is worse than one that
-- says which column it invented.
--
-- THIS IS WHY P3 IS A SEPARATE HUMAN AUTHORISATION. Before U6b-4, restoring
-- grandfathering is one boolean. After it, it is this file.

begin;

-- ------------------------------------------------------------------ guards
do $$
declare n int; t timestamptz;
begin
  -- 1. we are actually in the post-U6b-4 state
  select count(*) into n from information_schema.tables
   where table_schema='public' and table_name='membership_cutover';
  if n <> 0 then
    raise exception 'ABORT: membership_cutover already exists -- this is not the post-U6b-4 state';
  end if;

  -- 2. enforcement must be OFF. Restoring the grandfather clause while
  --    enforcement is bound would GRANT access to 16 identities in one
  --    statement. That is the one outcome this file must never produce silently.
  select count(*) into n from public.membership_control where id and enforcement_enabled;
  if n <> 0 then
    raise exception 'ABORT: enforcement_enabled is TRUE -- disable enforcement before restoring grandfathering';
  end if;

  -- 3. cutover_at must still be present, or the snapshot is not reconstructible
  select cutover_at into t from public.membership_control where id;
  if t is null then
    raise exception 'ABORT: cutover_at is NULL -- the snapshot cannot be reconstructed';
  end if;

  -- 4. u6b_bound_at must be intact. U6b-4 must not have disturbed it.
  select count(*) into n from public.membership_control where id and u6b_bound_at is not null;
  if n <> 1 then
    raise exception 'ABORT: u6b_bound_at is not set -- unexpected state, stop and investigate';
  end if;
end $$;

-- ----------------------------------------- 1. membership_control, REBUILT
--
-- A DROP-AND-RE-ADD OF THE TWO COLUMNS DOES NOT RESTORE PRODUCTION. PostgreSQL
-- cannot reorder columns, so re-added columns land at positions 9 and 10 while
-- production holds them at 5 and 6. That was caught by B-23 during the local
-- rehearsal -- GATE NOT MET, two UNAPPROVED ordinal_position differences -- and
-- it is NOT allowlistable: the gate's own rule is that a difference which can be
-- reproduced must be reproduced, and this one can. Allowlisting it would have
-- been exactly the "normalise the difference away" failure the gate exists to
-- prevent, and the gate refused it rather than a reviewer noticing.
--
-- So the single-row table is rebuilt with the exact production column order and
-- all five constraints by name. Verified safe before writing this: ZERO foreign
-- keys reference membership_control, ZERO policies, ZERO triggers, one index
-- (the primary key).

create table public.membership_control__u6b4_rebuild (
  id                     boolean     not null default true,
  cutover_at             timestamptz,
  cutover_identity_count integer,
  cutover_verified_at    timestamptz,
  grandfather_enabled    boolean     not null default true,
  grandfather_expires_at timestamptz,
  u6b_bound_at           timestamptz,
  notes                  text,
  updated_at             timestamptz not null default now(),
  enforcement_enabled    boolean     not null default false
);
-- The constraints are added AFTER the rename, not declared here. Every one of
-- the five names is still occupied by the live table at this point, and
-- membership_control_pkey collides first -- an index name is global to the
-- schema, not scoped to its table. Caught in rehearsal, not by review.

-- grandfather_enabled is carried as FALSE and grandfather_expires_at as NULL.
-- THE DEFAULT IS `true` BECAUSE U3's DDL SAID SO AND B-23 COMPARES STRUCTURE;
-- THE VALUE MUST BE `false` BECAUSE THAT IS WHAT PRODUCTION HELD. Without this
-- the rollback restores the mechanism MORE PERMISSIVE than the state it undoes
-- and grandfathers 16 identities the instant it commits. A rollback that grants
-- access nobody asked for is not a rollback. Re-enabling stays a separate,
-- deliberate flip -- the same "stop granting is not start denying" separation
-- the retirement itself used.
insert into public.membership_control__u6b4_rebuild
  (id, cutover_at, cutover_identity_count, cutover_verified_at,
   grandfather_enabled, grandfather_expires_at,
   u6b_bound_at, notes, updated_at, enforcement_enabled)
select id, cutover_at, cutover_identity_count, cutover_verified_at,
       false, null,
       u6b_bound_at, notes, now(), enforcement_enabled
  from public.membership_control;

drop table public.membership_control;
alter table public.membership_control__u6b4_rebuild rename to membership_control;

alter table public.membership_control
  add constraint membership_control_pkey primary key (id),
  add constraint membership_control_single_row check (id),
  add constraint membership_control_count_nonnegative
    check (cutover_identity_count is null or cutover_identity_count >= 0),
  add constraint membership_control_count_with_verification
    check ((cutover_verified_at is null) = (cutover_identity_count is null)),
  add constraint membership_control_verified_needs_cutover
    check (cutover_verified_at is null or cutover_at is not null);

comment on table public.membership_control is
  'Single-row control for the cutover boundary and the bounded grandfather compatibility window.';

alter table public.membership_control enable row level security;
revoke all on public.membership_control from public, anon, authenticated, service_role;

-- ------------------------------------------------------ 2. the snapshot table
create table public.membership_cutover (
  user_id     uuid        not null,
  captured_at timestamptz not null default now(),

  constraint membership_cutover_pkey primary key (user_id),
  constraint membership_cutover_user_fk
    foreign key (user_id) references auth.users(id) on delete cascade
);

comment on table public.membership_cutover is
  'Frozen pre-enforcement identity snapshot. Populated ONCE at production cutover; never appended to for ordinary new users.';

alter table public.membership_cutover enable row level security;
revoke all on public.membership_cutover from public, anon, authenticated, service_role;

-- ------------------------------------------------ 3. reconstruct the snapshot
insert into public.membership_cutover (user_id)
select u.id from auth.users u
 where u.created_at < (select cutover_at from public.membership_control where id);

-- Guard 5 -- the reconstruction must equal what was recorded at U3's cutover.
do $$
declare got int; want int;
begin
  select count(*) into got from public.membership_cutover;
  select cutover_identity_count into want from public.membership_control where id;
  if want is null then
    raise exception 'ABORT: cutover_identity_count is NULL -- cannot verify the reconstruction';
  end if;
  if got <> want then
    raise exception 'ABORT: reconstructed % snapshot rows, recorded count is % -- a pre-cutover identity has been deleted and this rollback is LOSSY', got, want;
  end if;
end $$;

-- --------------------------------------------------- 4. connected_member
-- Byte-identical to the production definition captured 2026-09-02, including
-- the "-- NO environment filter here" comment, which is D4's correction.
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

    (select exists (
       select 1
         from public.membership_cutover c
         cross join public.membership_control k
        where c.user_id = target_user_id
          and k.grandfather_enabled
          and (k.grandfather_expires_at is null
               or now() < k.grandfather_expires_at))),

    false
  );
$function$;

-- ---------------------------------------------------- 5. membership_state
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
    when public.connected_member(target_user_id) then 'grandfathered'
    else 'unknown'
  end;
$function$;

-- ---------------------------------------------------------- 6. the grants
-- CREATE OR REPLACE on an EXISTING function preserves privileges. These lines
-- are belt-and-braces and they exist because the U6a rollback got this wrong:
-- CREATE OR REPLACE on a DROPPED function yields DEFAULT privileges including
-- PUBLIC EXECUTE, and only the B-23 gate caught it. Stated explicitly so the
-- correct end state does not depend on remembering which case applies.
revoke all on function public.connected_member(uuid) from public, anon, authenticated, service_role;
revoke all on function public.membership_state(uuid)  from public, anon, authenticated, service_role;
grant execute on function public.membership_state(uuid) to service_role;

-- ------------------------------------------------------------ final proof
do $$
declare n int;
begin
  select count(*) into n from pg_proc p join pg_namespace nsp on nsp.oid=p.pronamespace
   where nsp.nspname='public' and p.prokind='f' and p.proname='connected_member'
     and pg_get_functiondef(p.oid) like '%membership_cutover%';
  if n <> 1 then raise exception 'ABORT: connected_member does not reference the snapshot after rollback'; end if;

  select count(*) into n from pg_proc p join pg_namespace nsp on nsp.oid=p.pronamespace
   where nsp.nspname='public' and p.prokind='f' and p.proname='membership_state'
     and pg_get_functiondef(p.oid) like '%grandfathered%';
  if n <> 1 then raise exception 'ABORT: membership_state cannot produce grandfathered after rollback'; end if;

  -- and the restored mechanism must be INERT, matching production
  select count(*) into n from public.membership_control where id and grandfather_enabled;
  if n <> 0 then raise exception 'ABORT: grandfather_enabled came back TRUE -- the rollback would grant access'; end if;
end $$;

select (select count(*) from public.membership_cutover)                       as cutover_rows,
       (select cutover_identity_count from public.membership_control)         as recorded_count,
       (select grandfather_enabled from public.membership_control)            as grandfather_enabled,
       (select enforcement_enabled from public.membership_control)            as enforcement_enabled,
       (select u6b_bound_at is not null from public.membership_control)       as u6b_bound_at_preserved,
       (select count(*) from public.membership)                               as membership_rows,
       (select count(*) from public.membership_binding)                       as binding_rows,
       'U6b-4 ROLLED BACK -- grandfather mechanism restored'                  as status;

commit;
