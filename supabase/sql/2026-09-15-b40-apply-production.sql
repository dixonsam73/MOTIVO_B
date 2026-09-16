begin;
-- B-40 PRODUCTION APPLY (20260915150000), guarded.
-- Generated 2026-09-15 by claude-evidence/scope014/gen_b40_artifacts.py. DO NOT HAND-EDIT: regenerate.
--
-- Body: supabase/migrations/20260915150000_b40_teen_follow_requests_closed.sql, verbatim.
-- PRE also requires the deployed B-39/scope 011 bodies and comment, and proves them unchanged in POST.
--
-- ONE SUBMISSION. Every abort-worthy check runs BEFORE COMMIT; a raise aborts the whole
-- submission and nothing changes. Score the RESPONSE BODY (error object or the final
-- verification row), never the CLI exit code. The file starts with `begin;` so a
-- positional submission is never parsed as a CLI flag. No recompute: the rule is read-time.

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =================================================================== PRE guards
do $s14pre$
declare v text; n bigint;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('account_privacy_requests_open', 'account_privacy_self_v1', 'account_privacy_upsert_v1', 'connected_member', 'membership_entitled_until', 'membership_apply_state_v1');
  if n <> 6 then raise exception '[B40 apply PRE] expected exactly one function for each of 6 names, found %', n; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_requests_open');
  if v is distinct from 'f730fb8adba2011f0600f16ef6883d5d' then raise exception '[B40 apply PRE] % md5 is %, expected %', 'account_privacy_requests_open', v, 'f730fb8adba2011f0600f16ef6883d5d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_self_v1');
  if v is distinct from '1f87a5832b702c369f169217b2eaceae' then raise exception '[B40 apply PRE] % md5 is %, expected %', 'account_privacy_self_v1', v, '1f87a5832b702c369f169217b2eaceae'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_upsert_v1');
  if v is distinct from '13df8a41f6011aba4e68fdd5ea615065' then raise exception '[B40 apply PRE] % md5 is %, expected %', 'account_privacy_upsert_v1', v, '13df8a41f6011aba4e68fdd5ea615065'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member');
  if v is distinct from '53775fd4dd46661ffd0a85d0a191c60a' then raise exception '[B40 apply PRE] % md5 is %, expected %', 'connected_member', v, '53775fd4dd46661ffd0a85d0a191c60a'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1');
  if v is distinct from 'e77f869be62c319012203cb2fafbbe2d' then raise exception '[B40 apply PRE] % md5 is %, expected %', 'membership_apply_state_v1', v, 'e77f869be62c319012203cb2fafbbe2d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until');
  if v is distinct from '962d8c937cdc03cbe7a06f2d0da0a84e' then raise exception '[B40 apply PRE] % md5 is %, expected %', 'membership_entitled_until', v, '962d8c937cdc03cbe7a06f2d0da0a84e'; end if;
  v := md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), ''));
  if v is distinct from '2a5375a43415b878823c3d51b856624f' then raise exception '[B40 apply PRE] membership_state comment md5 is %, expected %', v, '2a5375a43415b878823c3d51b856624f'; end if;
  perform set_config('s14.others', (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || pg_get_functiondef(p.oid) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname, pg_get_function_identity_arguments(p.oid))) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname <> all (array['account_privacy_requests_open', 'account_privacy_self_v1', 'account_privacy_upsert_v1'])), true);
  perform set_config('s14.policies', (select md5(coalesce(string_agg(schemaname || '.' || tablename || '.' || policyname || '|' || permissive || '|' || roles::text || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by schemaname, tablename, policyname), '')) from pg_policies where schemaname in ('public', 'storage')), true);
  perform set_config('s14.acl', (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(array_to_string(p.proacl, ','), '<null>'), '|' order by p.proname)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('account_privacy_requests_open', 'account_privacy_self_v1', 'account_privacy_upsert_v1', 'account_privacy_set_follow_requests_v1', 'account_privacy_set_lookup_v1', 'account_privacy_discoverable', 'follow_requests_open')), true);
  perform set_config('s14.privacy', (select count(*)::text || ':' || md5(coalesce(string_agg(a.user_id::text || '|' || a.age_band || '|' || a.lookup_enabled::text || '|' || a.lookup_set_under_band || '|' || a.follow_requests_enabled::text || '|' || a.follow_requests_set_under_band, '#' order by a.user_id), '')) from public.account_privacy a), true);
  perform set_config('s14.follows', (select count(*)::text from public.follows), true);
  perform set_config('s14.enforcement', (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control), true);
end
$s14pre$;

-- ======================================================================== BODY
-- ===== BEGIN VERBATIM 20260915150000_b40_teen_follow_requests_closed.sql =====
-- B-40 / audit A4 — A 13-17 MEMBER'S INBOUND FOLLOW REQUESTS ARE CLOSED, SERVER-SIDE.
--
-- THE DECISION (P5-G / Q2, docs/phase-5-g-decision-register.md §A2): a 13-17 member
-- CANNOT enable inbound follow requests, and no follow-request control is to be added.
-- Reason of record: Études has no moderation, no reporting surface and no guardian
-- channel, so inbound contact from a stranger to a minor has no mitigating control.
-- The young member may still initiate relationships themselves.
--
-- THE DEFECT. `account_privacy_set_follow_requests_v1` is executable by
-- `authenticated` (retained by decision, no client caller) and stamps
-- `follow_requests_set_under_band` with the row's CURRENT band. The effective rule
-- below only closed a teen row whose preference had been set under `band_18_plus`, so
-- a teen calling the writer directly produced an OPEN row, and another member's
-- `follows` insert then passed `follows_insert_requester`.
--
-- THE CHANGE. One expression, in the helper and its two inline mirrors, so the three
-- read paths cannot disagree:
--     effective follow requests := follow_requests_enabled AND age_band <> 'band_13_17'
-- Adults are unchanged by construction (`age_band` is NOT NULL, two values): for
-- `band_18_plus` both the old and new expressions reduce to `follow_requests_enabled`.
-- It is read-time, so it also closes any row already written.
--
-- DELIBERATELY UNCHANGED: signatures, return types, security definer, search_path and
-- grants (CREATE OR REPLACE keeps them); the writer and its grant; discovery
-- (`account_privacy_discoverable`, where a teen's own opt-in stays effective);
-- `follow_requests_open` and the follows policy, which call the helper.
--
-- Bodies transcribed from pg_get_functiondef on the local stack (identical to
-- 20260906120000_cp1_cp2_account_privacy.sql) with only that expression changed.

CREATE OR REPLACE FUNCTION public.account_privacy_requests_open(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((
    select p.follow_requests_enabled
       and p.age_band <> 'band_13_17'
      from public.account_privacy p
     where p.user_id = target_user_id), false);
$function$;

CREATE OR REPLACE FUNCTION public.account_privacy_self_v1()
 RETURNS TABLE(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean, o_follow_requests_enabled boolean, o_follow_requests_effective boolean, o_band_updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select ap.age_band, ap.lookup_enabled,
         (ap.lookup_enabled and not (ap.age_band='band_13_17' and ap.lookup_set_under_band='band_18_plus')),
         ap.follow_requests_enabled,
         (ap.follow_requests_enabled and ap.age_band <> 'band_13_17'),
         ap.band_updated_at
    from public.account_privacy ap
   where ap.user_id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.account_privacy_upsert_v1(p_age_band text)
 RETURNS TABLE(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean, o_follow_requests_enabled boolean, o_follow_requests_effective boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
           (ap.follow_requests_enabled and ap.age_band <> 'band_13_17')
      from public.account_privacy ap where ap.user_id = v_uid;
end $function$;
-- ===== END VERBATIM =====

-- ================================================================== POST guards
do $s14post$
declare v text;
begin
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_requests_open');
  if v is distinct from '8ae56aad5011cb8111203f405aee7812' then raise exception '[B40 apply POST] % md5 is %, expected %', 'account_privacy_requests_open', v, '8ae56aad5011cb8111203f405aee7812'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_self_v1');
  if v is distinct from '2b4384ae3a9c8e7ed241019e38720971' then raise exception '[B40 apply POST] % md5 is %, expected %', 'account_privacy_self_v1', v, '2b4384ae3a9c8e7ed241019e38720971'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_upsert_v1');
  if v is distinct from '050c675daa5f1828295f2039e871acfe' then raise exception '[B40 apply POST] % md5 is %, expected %', 'account_privacy_upsert_v1', v, '050c675daa5f1828295f2039e871acfe'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member');
  if v is distinct from '53775fd4dd46661ffd0a85d0a191c60a' then raise exception '[B40 apply POST] % md5 is %, expected %', 'connected_member', v, '53775fd4dd46661ffd0a85d0a191c60a'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1');
  if v is distinct from 'e77f869be62c319012203cb2fafbbe2d' then raise exception '[B40 apply POST] % md5 is %, expected %', 'membership_apply_state_v1', v, 'e77f869be62c319012203cb2fafbbe2d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until');
  if v is distinct from '962d8c937cdc03cbe7a06f2d0da0a84e' then raise exception '[B40 apply POST] % md5 is %, expected %', 'membership_entitled_until', v, '962d8c937cdc03cbe7a06f2d0da0a84e'; end if;
  v := md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), ''));
  if v is distinct from '2a5375a43415b878823c3d51b856624f' then raise exception '[B40 apply POST] membership_state comment changed'; end if;
  if (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || pg_get_functiondef(p.oid) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname, pg_get_function_identity_arguments(p.oid))) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname <> all (array['account_privacy_requests_open', 'account_privacy_self_v1', 'account_privacy_upsert_v1'])) is distinct from current_setting('s14.others') then raise exception '[B40 apply POST] s14.others changed'; end if;
  if (select md5(coalesce(string_agg(schemaname || '.' || tablename || '.' || policyname || '|' || permissive || '|' || roles::text || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by schemaname, tablename, policyname), '')) from pg_policies where schemaname in ('public', 'storage')) is distinct from current_setting('s14.policies') then raise exception '[B40 apply POST] s14.policies changed'; end if;
  if (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(array_to_string(p.proacl, ','), '<null>'), '|' order by p.proname)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('account_privacy_requests_open', 'account_privacy_self_v1', 'account_privacy_upsert_v1', 'account_privacy_set_follow_requests_v1', 'account_privacy_set_lookup_v1', 'account_privacy_discoverable', 'follow_requests_open')) is distinct from current_setting('s14.acl') then raise exception '[B40 apply POST] s14.acl changed'; end if;
  if (select count(*)::text || ':' || md5(coalesce(string_agg(a.user_id::text || '|' || a.age_band || '|' || a.lookup_enabled::text || '|' || a.lookup_set_under_band || '|' || a.follow_requests_enabled::text || '|' || a.follow_requests_set_under_band, '#' order by a.user_id), '')) from public.account_privacy a) is distinct from current_setting('s14.privacy') then raise exception '[B40 apply POST] s14.privacy changed'; end if;
  if (select count(*)::text from public.follows) is distinct from current_setting('s14.follows') then raise exception '[B40 apply POST] s14.follows changed'; end if;
  if (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control) is distinct from current_setting('s14.enforcement') then raise exception '[B40 apply POST] s14.enforcement changed'; end if;
  if not has_function_privilege('authenticated', 'public.account_privacy_set_follow_requests_v1(boolean)', 'execute') then
    raise exception '[B40 apply POST] the retained writer lost its authenticated grant'; end if;
  if has_function_privilege('anon', 'public.account_privacy_requests_open(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.account_privacy_requests_open(uuid)', 'execute') then
    raise exception '[B40 apply POST] a client role can execute account_privacy_requests_open'; end if;
end
$s14post$;

commit;

-- ====================================================== verification (read-only)
select jsonb_build_object(
  'artifact', 'B40 apply',
  'committed', true,
  'account_privacy_requests_open_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_requests_open'),
  'account_privacy_self_v1_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_self_v1'),
  'account_privacy_upsert_v1_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_upsert_v1'),
  'account_privacy', (select count(*)::text || ':' || md5(coalesce(string_agg(a.user_id::text || '|' || a.age_band || '|' || a.lookup_enabled::text || '|' || a.lookup_set_under_band || '|' || a.follow_requests_enabled::text || '|' || a.follow_requests_set_under_band, '#' order by a.user_id), '')) from public.account_privacy a),
  'enforcement_enabled', (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control),
  'observed_at', now())::text as s14_verification;
