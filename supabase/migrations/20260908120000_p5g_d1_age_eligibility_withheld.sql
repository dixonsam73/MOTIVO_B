-- ============================================================================
-- P5-G / D1 — AGE-ELIGIBILITY WITHHOLDING.
--
-- Approved in `docs/phase-5-g-decision-register.md` §H.
--
-- WHAT THE NEW COLUMN MEANS, AND THIS WORDING IS LOAD-BEARING.
-- It does **NOT** mean "this Études identity is under 13". It means: THE LATEST
-- CONCLUSIVE APPLE RESULT DOES NOT CURRENTLY ESTABLISH CONNECTED ELIGIBILITY.
-- Per Q5, Apple's declared age range describes the Apple Account signed in to
-- iCloud on the device; it is NOT bound or verified against the Études
-- identity, and that account can change. An under-13 reading is therefore
-- ambiguous between "this member is a child" and "the device's Apple Account
-- is now a child's" -- so the safety state is recorded and the age claim is
-- NOT.
--
-- NO THIRD AGE BAND, AND NO PREFERENCE IS REWRITTEN. `age_band` keeps its
-- two-value domain, and `lookup_enabled` / `follow_requests_enabled` are never
-- touched by withholding -- effect is withheld, history is preserved, and a
-- later conclusive eligible band restores the member exactly.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. THE COLUMN.
--
-- NOT NULL DEFAULT false is deliberate and is the CP-2-R1 lesson applied: a
-- strictly two-valued column can never reintroduce the "missing/unresolved
-- resolves PERMISSIVE" hazard. The default covers every existing row, so there
-- is no backfill and no window in which the meaning is undefined.
--
-- No companion timestamp is added. `band_updated_at` already records band
-- movement, when withholding was set decides nothing, and minimisation says do
-- not store what nothing reads.
-- ---------------------------------------------------------------------------
alter table public.account_privacy
  add column if not exists age_eligibility_withheld boolean not null default false;

comment on column public.account_privacy.age_eligibility_withheld is
  'P5-G/D1. TRUE when the latest conclusive Apple age-range result does not establish Connected eligibility. NOT a claim that the member is under 13 -- see the migration header and register Q5.';

-- ---------------------------------------------------------------------------
-- 2. THE EFFECTIVE-STATE HELPERS.
--
-- ONE CONJUNCT EACH, AND THE TWO CONSUMERS NEED NO EDIT.
-- `search_account_directory` calls `account_privacy_discoverable`, and
-- `follow_requests_open` calls `account_privacy_requests_open`; neither inlines
-- the rule. Verified against the deployed definitions before writing this.
--
-- The `coalesce(..., false)` wrapper is untouched, so a MISSING row still
-- resolves CLOSED (CP-2-R1). And the discovery conjunct inside
-- `search_account_directory` is deliberately NOT wrapped in
-- `enforcement_active()`, so THE ENTITLEMENT KILL SWITCH CANNOT RELAX
-- WITHHOLDING -- the kill switch may relax entitlement, never child safety.
-- ---------------------------------------------------------------------------
create or replace function public.account_privacy_discoverable(target_user_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce((
    select p.lookup_enabled
       and not p.age_eligibility_withheld
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
       and not p.age_eligibility_withheld
       and not (p.age_band = 'band_13_17'
                and p.follow_requests_set_under_band = 'band_18_plus')
      from public.account_privacy p
     where p.user_id = target_user_id), false);
$function$;

-- ---------------------------------------------------------------------------
-- 3. THE WRITERS, AND THE ASYMMETRY IS THE SAFETY PROPERTY.
--
-- A client may SET withholding, and can NEVER clear it directly. Clearing
-- happens ONLY as a side effect of presenting a conclusive valid band to
-- `account_privacy_upsert_v1`. So no client call can restore eligibility
-- without a real Apple result having been obtained.
-- ---------------------------------------------------------------------------

-- 3a. A conclusive eligible band CLEARS withholding. One added line.
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
         -- P5-G/D1: a conclusive eligible band is the ONLY thing that clears
         -- withholding. Preferences are deliberately NOT touched here.
         age_eligibility_withheld = false,
         band_updated_at = case when ap.age_band = excluded.age_band then ap.band_updated_at else now() end;

  return query
    select ap.age_band, ap.lookup_enabled,
           (ap.lookup_enabled and not (ap.age_band='band_13_17' and ap.lookup_set_under_band='band_18_plus')),
           ap.follow_requests_enabled,
           (ap.follow_requests_enabled and not (ap.age_band='band_13_17' and ap.follow_requests_set_under_band='band_18_plus'))
      from public.account_privacy ap where ap.user_id = v_uid;
end $function$;

-- 3b. SET withholding. UPDATE-ONLY and PARAMETERLESS.
--
-- UPDATE-only so it can never originate a row -- U4's canonical-writer
-- discipline, applied here. Parameterless so there is no value for a caller to
-- get wrong and, more importantly, NO WAY TO PASS `false`.
create or replace function public.account_privacy_withhold_age_eligibility_v1()
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  update public.account_privacy ap
     set age_eligibility_withheld = true
   where ap.user_id = v_uid;
  if not found then raise exception 'no age band declared' using errcode='23514'; end if;
  return true;
end $function$;

grant execute on function public.account_privacy_withhold_age_eligibility_v1() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. SELF READ GAINS A COLUMN.
--
-- `create or replace` CANNOT change a return type, so this is a DROP and a
-- CREATE, and THE GRANT MUST BE RE-APPLIED AFTERWARDS -- dropping a function
-- drops its privileges with it. Written out because this is exactly the step
-- that gets discovered at the wrong moment.
-- ---------------------------------------------------------------------------
drop function if exists public.account_privacy_self_v1();

create function public.account_privacy_self_v1()
returns table(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean,
              o_follow_requests_enabled boolean, o_follow_requests_effective boolean,
              o_band_updated_at timestamptz, o_age_eligibility_withheld boolean)
language sql
stable security definer
set search_path to ''
as $function$
  select ap.age_band, ap.lookup_enabled,
         (ap.lookup_enabled
            and not ap.age_eligibility_withheld
            and not (ap.age_band='band_13_17' and ap.lookup_set_under_band='band_18_plus')),
         ap.follow_requests_enabled,
         (ap.follow_requests_enabled
            and not ap.age_eligibility_withheld
            and not (ap.age_band='band_13_17' and ap.follow_requests_set_under_band='band_18_plus')),
         ap.band_updated_at,
         ap.age_eligibility_withheld
    from public.account_privacy ap
   where ap.user_id = auth.uid();
$function$;

grant execute on function public.account_privacy_self_v1() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. GUARD. Returns a row, so "no rows returned" is a SYMPTOM rather than a
-- disguise -- the lesson from the U6a apply that reported success and applied
-- nothing.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='account_privacy'
                    and column_name='age_eligibility_withheld'
                    and is_nullable='NO' and data_type='boolean') then
    raise exception 'P5-G/D1 guard: column missing or nullable';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='account_privacy_withhold_age_eligibility_v1') then
    raise exception 'P5-G/D1 guard: withhold RPC missing';
  end if;
  if (select count(*) from information_schema.routine_privileges
       where routine_schema='public' and routine_name='account_privacy_self_v1'
         and grantee='authenticated' and privilege_type='EXECUTE') <> 1 then
    raise exception 'P5-G/D1 guard: self_v1 EXECUTE grant to authenticated not restored after DROP';
  end if;
  if (select count(*) from information_schema.routine_privileges
       where routine_schema='public'
         and routine_name in ('account_privacy_discoverable','account_privacy_requests_open')
         and grantee in ('anon','authenticated','service_role')) <> 0 then
    raise exception 'P5-G/D1 guard: an internal helper became client-executable';
  end if;
end $$;

select 'P5-G/D1 applied' as result,
       (select count(*) from information_schema.columns
         where table_schema='public' and table_name='account_privacy') as account_privacy_columns;
