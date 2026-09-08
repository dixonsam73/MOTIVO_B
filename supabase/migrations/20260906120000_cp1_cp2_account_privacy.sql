-- ============================================================================
-- CP-1 + CP-2 — ACCOUNT PRIVACY. FIDELITY CAPTURE OF ALREADY-DEPLOYED STATE.
--
-- THIS MIGRATION ADDS NOTHING NEW. It is a faithful transcription of objects
-- that have been live in production since 2026-09-06/07 (P5-D and P5-E) and
-- that had NO committed SQL artefact anywhere in this repository -- the CP-1
-- and CP-2 server halves existed only inside markdown design documents.
--
-- WHY THIS FILE EXISTS, AND WHY IT IS NOT OPTIONAL.
-- `supabase db reset --local` rebuilt a database with NO `account_privacy`
-- table and ZERO `account_privacy%` functions -- measured 2026-09-08, not
-- assumed. So every local rehearsal of a CP object was a rehearsal of an
-- object that did not exist. This is precisely the B-23 fidelity defect that
-- P4-U7 recorded when U5's server half was applied from `supabase/sql/` and
-- never added to `supabase/migrations/`, leaving local rehearsals running
-- against a six-column RPC while production carried seven. That case at least
-- had a .sql file; this one had none.
--
-- EVERY DEFINITION BELOW WAS READ BACK FROM PRODUCTION
-- (`pg_get_functiondef`, `pg_get_constraintdef`, `information_schema`) ON
-- 2026-09-08 AND TRANSCRIBED, NOT REWRITTEN FROM THE DESIGN DOCUMENTS.
-- Reconstructing from prose would have produced something that resembled
-- production rather than something equal to it.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- CP-1 — the table.
-- ---------------------------------------------------------------------------
create table if not exists public.account_privacy (
    user_id                        uuid        not null,
    age_band                       text        not null,
    band_updated_at                timestamptz not null default now(),
    lookup_enabled                 boolean     not null,
    lookup_set_under_band          text        not null,
    lookup_changed_at              timestamptz,
    follow_requests_enabled        boolean     not null,
    follow_requests_set_under_band text        not null,
    follow_requests_changed_at     timestamptz,
    constraint account_privacy_pkey primary key (user_id),
    constraint account_privacy_user_id_fkey foreign key (user_id)
        references auth.users(id) on delete cascade,
    constraint age_band_values
        check (age_band = any (array['band_13_17'::text, 'band_18_plus'::text])),
    constraint lookup_set_under_band_values
        check (lookup_set_under_band = any (array['band_13_17'::text, 'band_18_plus'::text])),
    constraint follow_requests_set_under_band_values
        check (follow_requests_set_under_band = any (array['band_13_17'::text, 'band_18_plus'::text]))
);

-- RLS ON WITH ZERO POLICIES, AND NO CLIENT GRANT. Every access goes through a
-- SECURITY DEFINER function; there is no direct client DML path at all.
alter table public.account_privacy enable row level security;

revoke all on public.account_privacy from public;
revoke all on public.account_privacy from anon;
revoke all on public.account_privacy from authenticated;
revoke all on public.account_privacy from service_role;

-- ---------------------------------------------------------------------------
-- CP-1 — band before directory. BEFORE INSERT ONLY, deliberately.
-- ---------------------------------------------------------------------------
create or replace function public.tg_account_directory_requires_band()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- MEASURED 2026-09-06: BEFORE INSERT fires on INSERT ... ON CONFLICT DO UPDATE
  -- before the conflict is resolved. A directory row that ALREADY EXISTS for
  -- THIS user_id means the statement is an update in effect and must not be
  -- blocked. Structural, per-row: no count, no ordering, no race-sensitive state.
  if exists (select 1 from public.account_directory ad where ad.user_id = new.user_id) then
    return new;
  end if;
  if not exists (select 1 from public.account_privacy p where p.user_id = new.user_id) then
    raise exception 'age band must be declared before a directory row is created' using errcode='23514';
  end if;
  return new;
end $function$;

drop trigger if exists tg_directory_requires_band on public.account_directory;
create trigger tg_directory_requires_band
  before insert on public.account_directory
  for each row execute function public.tg_account_directory_requires_band();

-- ---------------------------------------------------------------------------
-- CP-1/CP-2 — the effective-state helpers.
--
-- The child-safety override WITHHOLDS EFFECT and destroys no preference
-- history: a preference set under an adult band simply stops being effective
-- once the band is `band_13_17`. `*_set_under_band` is what makes that
-- computable without storing a second copy of the preference.
--
-- `coalesce(..., false)`: a MISSING row resolves CLOSED (CP-2-R1).
-- ---------------------------------------------------------------------------
create or replace function public.account_privacy_discoverable(target_user_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce((
    select p.lookup_enabled
       and not (p.age_band = 'band_13_17'
                and p.lookup_set_under_band = 'band_18_plus')
      from public.account_privacy p
     where p.user_id = target_user_id), false);
$function$;

create or replace function public.account_privacy_requests_open(target_user_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce((
    select p.follow_requests_enabled
       and not (p.age_band = 'band_13_17'
                and p.follow_requests_set_under_band = 'band_18_plus')
      from public.account_privacy p
     where p.user_id = target_user_id), false);
$function$;

-- ---------------------------------------------------------------------------
-- CP-1 — self read.
-- ---------------------------------------------------------------------------
create or replace function public.account_privacy_self_v1()
returns table(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean,
              o_follow_requests_enabled boolean, o_follow_requests_effective boolean,
              o_band_updated_at timestamptz)
language sql
stable security definer
set search_path to ''
as $function$
  select ap.age_band, ap.lookup_enabled,
         (ap.lookup_enabled and not (ap.age_band='band_13_17' and ap.lookup_set_under_band='band_18_plus')),
         ap.follow_requests_enabled,
         (ap.follow_requests_enabled and not (ap.age_band='band_13_17' and ap.follow_requests_set_under_band='band_18_plus')),
         ap.band_updated_at
    from public.account_privacy ap
   where ap.user_id = auth.uid();
$function$;

-- ---------------------------------------------------------------------------
-- CP-1 — establishment. THE DEFAULTS ARE ONE BRANCHLESS EXPRESSION:
-- `(p_age_band = 'band_18_plus')` decides BOTH preferences, so there is no
-- teen branch anybody can forget to write.
-- ---------------------------------------------------------------------------
create or replace function public.account_privacy_upsert_v1(p_age_band text)
returns table(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean,
              o_follow_requests_enabled boolean, o_follow_requests_effective boolean)
language plpgsql
security definer
set search_path to ''
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  if p_age_band not in ('band_13_17','band_18_plus') then raise exception 'invalid age band' using errcode='22023'; end if;

  insert into public.account_privacy as ap
      (user_id, age_band, lookup_enabled, lookup_set_under_band,
       follow_requests_enabled, follow_requests_set_under_band)
  values (v_uid, p_age_band,
          (p_age_band='band_18_plus'), p_age_band,
          (p_age_band='band_18_plus'), p_age_band)
  on conflict (user_id) do update
     set age_band = excluded.age_band,
         band_updated_at = case when ap.age_band = excluded.age_band then ap.band_updated_at else now() end;

  return query
    select ap.age_band, ap.lookup_enabled,
           (ap.lookup_enabled and not (ap.age_band='band_13_17' and ap.lookup_set_under_band='band_18_plus')),
           ap.follow_requests_enabled,
           (ap.follow_requests_enabled and not (ap.age_band='band_13_17' and ap.follow_requests_set_under_band='band_18_plus'))
      from public.account_privacy ap where ap.user_id = v_uid;
end $function$;

-- ---------------------------------------------------------------------------
-- CP-3 — the preference writers. Each stamps `*_set_under_band` from the row's
-- CURRENT band, which is what makes the read-time override computable later.
-- ---------------------------------------------------------------------------
create or replace function public.account_privacy_set_lookup_v1(p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  update public.account_privacy ap
     set lookup_enabled = p_enabled, lookup_set_under_band = ap.age_band, lookup_changed_at = now()
   where ap.user_id = v_uid;
  if not found then raise exception 'no age band declared' using errcode='23514'; end if;
  return p_enabled;
end $function$;

create or replace function public.account_privacy_set_follow_requests_v1(p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  update public.account_privacy ap
     set follow_requests_enabled = p_enabled, follow_requests_set_under_band = ap.age_band, follow_requests_changed_at = now()
   where ap.user_id = v_uid;
  if not found then raise exception 'no age band declared' using errcode='23514'; end if;
  return p_enabled;
end $function$;

-- ---------------------------------------------------------------------------
-- GRANTS. The two helpers are internal: NO client role may execute them, so
-- the membership/privacy oracle stays structurally unbuildable (B-33's rule,
-- applied here).
-- ---------------------------------------------------------------------------
revoke all on function public.account_privacy_discoverable(uuid) from public, anon, authenticated, service_role;
revoke all on function public.account_privacy_requests_open(uuid) from public, anon, authenticated, service_role;

grant execute on function public.account_privacy_self_v1() to authenticated;
grant execute on function public.account_privacy_upsert_v1(text) to authenticated;
grant execute on function public.account_privacy_set_lookup_v1(boolean) to authenticated;
grant execute on function public.account_privacy_set_follow_requests_v1(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- CP-2 — the two CONSUMERS. Both CALL the helpers rather than inlining the
-- rule, which is why a later change to the rule needs no edit here.
-- ---------------------------------------------------------------------------
create or replace function public.follow_requests_open(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- CP-2-R1: the former coalesce(..., true) resolved a MISSING/UNRESOLVED row
  -- PERMISSIVE, opening a contact path into a possible minor by absence. It now
  -- resolves CLOSED. account_directory.follow_requests_enabled is no longer
  -- consulted and joins lookup_enabled as a dead column; both surviving rows
  -- carried the enabled value, so nothing is widened by dropping it.
  -- The permissive literal is deliberately NOT written in this comment: the
  -- acceptance guard greps the source for it, and a comment carrying the pattern
  -- would defeat the check for the rule it explains (U5c-34 / U5d, C-14).
  -- The privacy conjunct is UNCONDITIONAL: the kill switch may relax entitlement,
  -- never child safety.
  select (select public.enforcement_gate('rpc.follow_requests_open'))
     and public.account_privacy_requests_open(target_user_id);
$function$
;

-- The CP-2 discovery clause is the line `and public.account_privacy_discoverable(ad.user_id)`.
-- Transcribed from production 2026-09-08 via pg_get_functiondef, not rewritten.
-- CREATE OR REPLACE keeps the existing grants.
create or replace function public.search_account_directory(q text)
 RETURNS TABLE(user_id uuid, account_id text, display_name text, location text, avatar_key text, instruments text[], avatar_version timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

  with tokens as (
      select distinct lower(token) as token
      from regexp_split_to_table(btrim(q), '\s+') as token
      where token <> ''
  )

  select
      ad.user_id,
      ad.account_id,
      ad.display_name,
      ad.location,
      ad.avatar_key,
      ad.instruments,
      ad.avatar_version
  from public.account_directory ad
  where
      (select public.enforcement_gate('rpc.search_account_directory'))
      and auth.uid() is not null

      -- D-U6-1: a lapsed member becomes UNDISCOVERABLE. Subject-side, and it
      -- respects the kill switch, or a rollback would only half-roll-back.
      -- get_account_directory_by_user_ids deliberately has NO such filter (G10).
      and ((select not public.enforcement_active()) or ad.entitled_until > now())

      -- Self-exclusion, not a security control. See the warning above.
      -- CP-2 / P5-E: EFFECTIVE discovery. UNCONDITIONAL, and deliberately NOT
      -- wrapped in enforcement_active() the way D-U6-1 above is. The kill switch
      -- may relax ENTITLEMENT gating; it must never relax CHILD-SAFETY privacy.
      -- Wrapping it would make `enforcement_enabled = false` expose a 13-17
      -- member who never opted in. Absence of a privacy row resolves FALSE.
      and public.account_privacy_discoverable(ad.user_id)

      and ad.user_id <> auth.uid()

      -- Prevent browse behaviour. 2 is the SMALLEST PRODUCT-VALID floor:
      -- production carries a 2-character display name, so raising it would make
      -- a real member unsearchable by their complete name. B-15, disposed
      -- 2026-09-05 on measurement — see docs/phase-4-u5-acceptance.md.
      and char_length(btrim(q)) >= 2

      -- Every search token must match somewhere
      and not exists (
          select 1
          from tokens t
          where not (
              (ad.account_id is not null
                  and lower(ad.account_id) like t.token || '%')

              or

              (lower(ad.display_name) like '%' || t.token || '%')

              or

              exists (
                  select 1
                  from unnest(coalesce(ad.instruments, '{}')) as instrument
                  where lower(instrument) like '%' || t.token || '%'
              )
          )
      )

  order by
      ad.account_id nulls last,
      ad.user_id

  limit 20;
$function$
;
