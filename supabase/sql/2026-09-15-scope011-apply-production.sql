begin;
-- A2 — SCOPE 011 PRODUCTION APPLY (20260915160000), guarded. REQUIRES A1 APPLIED AND VERIFIED.
-- Generated 2026-09-15 by claude-evidence/scope012/gen_artifacts.py. DO NOT HAND-EDIT: regenerate.
--
-- Body: supabase/migrations/20260915160000_scope011_verified_sandbox_entitlement.sql, verbatim, including its
-- own recompute and guard. PRE requires the B-39 bodies, so it cannot run before A1.
--
-- ONE SUBMISSION. Every abort-worthy check runs BEFORE COMMIT: a raise aborts the
-- whole submission and nothing is changed. Score the RESPONSE BODY (an error object,
-- or the final verification row), never the CLI exit code, which is 0 on error.
-- Cached-column drift in PRE aborts; it is never silently repaired.
-- B-40's three functions must be, and must stay, at their production md5.
-- The file starts with `begin;` so a positional submission is never parsed as a CLI flag.

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =================================================================== PRE guards
do $s12pre$
declare v text; n bigint;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('connected_member', 'membership_entitled_until', 'membership_apply_state_v1', 'account_privacy_requests_open', 'account_privacy_self_v1', 'account_privacy_upsert_v1');
  if n <> 6 then raise exception '[A2 scope011 apply PRE] expected exactly one function for each of the 6 targets, found %', n; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member');
  if v is distinct from '8e39f78402ec6402f690bcfa8935a8d4' then raise exception '[A2 scope011 apply PRE] % md5 is %, expected %', 'connected_member', v, '8e39f78402ec6402f690bcfa8935a8d4'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1');
  if v is distinct from 'e77f869be62c319012203cb2fafbbe2d' then raise exception '[A2 scope011 apply PRE] % md5 is %, expected %', 'membership_apply_state_v1', v, 'e77f869be62c319012203cb2fafbbe2d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until');
  if v is distinct from 'e74146e4d9e5dc752e7fec34a3d3797f' then raise exception '[A2 scope011 apply PRE] % md5 is %, expected %', 'membership_entitled_until', v, 'e74146e4d9e5dc752e7fec34a3d3797f'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_requests_open');
  if v is distinct from 'f730fb8adba2011f0600f16ef6883d5d' then raise exception '[A2 scope011 apply PRE] % md5 is %, expected %', 'account_privacy_requests_open', v, 'f730fb8adba2011f0600f16ef6883d5d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_self_v1');
  if v is distinct from '1f87a5832b702c369f169217b2eaceae' then raise exception '[A2 scope011 apply PRE] % md5 is %, expected %', 'account_privacy_self_v1', v, '1f87a5832b702c369f169217b2eaceae'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_upsert_v1');
  if v is distinct from '13df8a41f6011aba4e68fdd5ea615065' then raise exception '[A2 scope011 apply PRE] % md5 is %, expected %', 'account_privacy_upsert_v1', v, '13df8a41f6011aba4e68fdd5ea615065'; end if;
  v := md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), ''));
  if v is distinct from '9ae51ea9798396177f2799754692c9ff' then raise exception '[A2 scope011 apply PRE] membership_state comment md5 is %, expected %', v, '9ae51ea9798396177f2799754692c9ff'; end if;
  n := ((select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id)) + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id)) + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id)) + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id)));
  if n <> 0 then raise exception '[A2 scope011 apply PRE] cached entitlement drift is % -- refusing; drift is assessed, never repaired here', n; end if;
  perform set_config('s12.others', (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || pg_get_functiondef(p.oid) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname, pg_get_function_identity_arguments(p.oid))) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname <> all (array['connected_member', 'membership_entitled_until'])), true);
  perform set_config('s12.policies', (select md5(coalesce(string_agg(schemaname || '.' || tablename || '.' || policyname || '|' || permissive || '|' || roles::text || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by schemaname, tablename, policyname), '')) from pg_policies where schemaname in ('public', 'storage')), true);
  perform set_config('s12.acl', (select md5(string_agg(p.proname || '=' || coalesce(array_to_string(p.proacl, ','), '<null>'), '|' order by p.proname)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('connected_member', 'membership_entitled_until', 'membership_apply_state_v1')), true);
  perform set_config('s12.membership', (select count(*)::text || ':' || md5(coalesce(string_agg(m.user_id::text || '|' || m.environment || '|' || coalesce(m.apple_status::text, '-') || '|' || coalesce(m.renewal_date::text, '-') || '|' || coalesce(m.pending_cleanup_at::text, '-') || '|' || coalesce(m.entitlement_ended_at::text, '-'), '#' order by m.user_id, m.environment, m.original_transaction_id), '')) from public.membership m), true);
  perform set_config('s12.enforcement', (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control), true);
end
$s12pre$;

-- ======================================================================== BODY
-- ===== BEGIN VERBATIM 20260915160000_scope011_verified_sandbox_entitlement.sql =====
-- SCOPE 011 — VERIFIED APPLE SANDBOX MEMBERSHIP COUNTS AS CONNECTED ENTITLEMENT.
--
-- LOCAL ONLY UNTIL A SEPARATE, AUTHORISED PRODUCTION DEPLOYMENT, which requires
-- B-39 (20260914120000) deployed first. Prediction:
-- docs/phase-5-scope011-sandbox-entitlement-prediction.md.
--
-- WHY. App Store Review and TestFlight / Xcode Release builds purchase in Apple's
-- Sandbox. Before this change `connected_member()` counted Production rows only, so
-- a reviewer's or tester's server-verified purchase was refused by enforcement
-- behind a Connected UI. Samuel approved counting VERIFIED Sandbox membership
-- (D4 revised in principle, 2026-09-15).
--
-- WHAT CHANGES. B-39's two bodies, verbatim, except ONE expression each:
--     m.environment = 'Production'   ->   m.environment in ('Production', 'Sandbox')
-- Two literals, not configuration: nothing can be mis-set, and an unknown future
-- environment still confers nothing. The environment test stays INSIDE bool_or.
--
-- WHAT DOES NOT CHANGE. Apple's formula; B-39's revoked rule; ownership binding
-- and JWS claim checks (establishment and the canonical writer are untouched);
-- pending_cleanup_at scheduling; cleanup authority (live Apple read, then
-- membership_cleanup_authorised_v1); enforcement and every policy; grants
-- (CREATE OR REPLACE preserves them, asserted below); environment labels on rows.
-- membership_state keeps its four values -- only its comment is updated.
--
-- No BEGIN/COMMIT here: the guards below run inside whatever transaction applies
-- this file, and any failure aborts it.

-- ============================================================ 1. the predicate
create or replace function public.connected_member(target_user_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $function$
  select coalesce(
    (select bool_or(
         m.environment in ('Production', 'Sandbox')
         -- B-39: a revoked subscription is never entitled. coalesce keeps the
         -- row expression strictly two-valued, so bool_or is NULL only when
         -- there are no rows at all.
         and coalesce(m.apple_status, 0) <> 5
         and (coalesce(m.renewal_date > now(), false)
              or coalesce(m.is_in_billing_retry
                          and m.grace_period_expires_date > now(), false))
       )
       from public.membership m
      where m.user_id = target_user_id),      -- NO environment filter here

    false
  );
$function$;

-- ===================================================== 2. the cached deadline
create or replace function public.membership_entitled_until(target_user_id uuid)
  returns timestamptz
  language sql stable security definer set search_path = ''
as $$
  select max(case
           when m.apple_status = 5
             then coalesce(m.revocation_date, m.renewal_info_signed_date)
           else greatest(
                  m.renewal_date,
                  case when m.is_in_billing_retry then m.grace_period_expires_date end
                )
         end)
    from public.membership m
   where m.user_id = target_user_id
     and m.environment in ('Production', 'Sandbox');
$$;

-- ======================================================= 3. the state's comment
comment on function public.membership_state(uuid) is
  'Four states: entitled, expired, sandbox_only, unknown. U6b-4 removed '
  '''grandfathered'' as a producible value (B-36). Historical '
  'shadow_enforcement_stat rows carrying it stay valid and permitted. '
  'Scope 011 (2026-09-15): sandbox_only means the identity holds only Sandbox '
  'rows -- provenance, not denial. An active verified Sandbox membership is '
  'entitled; the recorded would_deny says whether access was refused.';

-- ============================================ 4. recompute the four cached columns
-- Only identities holding Sandbox rows can change; the propagation trigger keeps
-- them current afterwards.
update public.posts p
   set owner_entitled_until = public.membership_entitled_until(p.owner_user_id)
 where p.owner_user_id in (select m.user_id from public.membership m where m.environment = 'Sandbox')
   and p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id);
update public.post_shares s
   set owner_entitled_until = public.membership_entitled_until(s.owner_user_id)
 where s.owner_user_id in (select m.user_id from public.membership m where m.environment = 'Sandbox')
   and s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id);
update public.follows f
   set followed_entitled_until = public.membership_entitled_until(f.followed_user_id)
 where f.followed_user_id in (select m.user_id from public.membership m where m.environment = 'Sandbox')
   and f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id);
update public.account_directory d
   set entitled_until = public.membership_entitled_until(d.user_id)
 where d.user_id in (select m.user_id from public.membership m where m.environment = 'Sandbox')
   and d.entitled_until is distinct from public.membership_entitled_until(d.user_id);

-- =================================================================== 5. guards
do $guard$
declare v_n int;
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('connected_member', 'membership_entitled_until')
     and pg_get_functiondef(p.oid) like '%environment in (''Production'', ''Sandbox'')%';
  if v_n <> 2 then
    raise exception 'scope011 guard: expected both functions to carry the Production/Sandbox literal pair, found %', v_n;
  end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'connected_member'
                    and pg_get_functiondef(p.oid) like '%coalesce(m.apple_status, 0) <> 5%') then
    raise exception 'scope011 guard: B-39 revoked conjunct missing from connected_member';
  end if;

  if has_function_privilege('anon', 'public.connected_member(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.connected_member(uuid)', 'execute')
     or has_function_privilege('anon', 'public.membership_entitled_until(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.membership_entitled_until(uuid)', 'execute') then
    raise exception 'scope011 guard: a client role can execute an entitlement function';
  end if;

  select (select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id))
       + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id))
       + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id))
       + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id))
    into v_n;
  if v_n <> 0 then
    raise exception 'scope011 guard: % cached entitlement values differ from the recomputed deadline', v_n;
  end if;
end
$guard$;

select 'scope011 verified: literal pair in both functions, revoked rule kept, clients cannot execute, cached drift 0' as scope011_status;
-- ===== END VERBATIM =====

-- =================================================================== RECOMPUTE
-- (inside the verbatim migration)

-- ================================================================== POST guards
do $s12post$
declare v text; n bigint;
begin
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member');
  if v is distinct from '53775fd4dd46661ffd0a85d0a191c60a' then raise exception '[A2 scope011 apply POST] % md5 is %, expected %', 'connected_member', v, '53775fd4dd46661ffd0a85d0a191c60a'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until');
  if v is distinct from '962d8c937cdc03cbe7a06f2d0da0a84e' then raise exception '[A2 scope011 apply POST] % md5 is %, expected %', 'membership_entitled_until', v, '962d8c937cdc03cbe7a06f2d0da0a84e'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1');
  if v is distinct from 'e77f869be62c319012203cb2fafbbe2d' then raise exception '[A2 scope011 apply POST] % md5 is %, expected %', 'membership_apply_state_v1', v, 'e77f869be62c319012203cb2fafbbe2d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_requests_open');
  if v is distinct from 'f730fb8adba2011f0600f16ef6883d5d' then raise exception '[A2 scope011 apply POST] % md5 is %, expected %', 'account_privacy_requests_open', v, 'f730fb8adba2011f0600f16ef6883d5d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_self_v1');
  if v is distinct from '1f87a5832b702c369f169217b2eaceae' then raise exception '[A2 scope011 apply POST] % md5 is %, expected %', 'account_privacy_self_v1', v, '1f87a5832b702c369f169217b2eaceae'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_upsert_v1');
  if v is distinct from '13df8a41f6011aba4e68fdd5ea615065' then raise exception '[A2 scope011 apply POST] % md5 is %, expected %', 'account_privacy_upsert_v1', v, '13df8a41f6011aba4e68fdd5ea615065'; end if;
  v := md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), ''));
  if v is distinct from '2a5375a43415b878823c3d51b856624f' then raise exception '[A2 scope011 apply POST] membership_state comment md5 is %, expected %', v, '2a5375a43415b878823c3d51b856624f'; end if;
  if (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || pg_get_functiondef(p.oid) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname, pg_get_function_identity_arguments(p.oid))) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname <> all (array['connected_member', 'membership_entitled_until'])) is distinct from current_setting('s12.others') then raise exception '[A2 scope011 apply POST] a non-target public function changed'; end if;
  if (select md5(coalesce(string_agg(schemaname || '.' || tablename || '.' || policyname || '|' || permissive || '|' || roles::text || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by schemaname, tablename, policyname), '')) from pg_policies where schemaname in ('public', 'storage')) is distinct from current_setting('s12.policies') then raise exception '[A2 scope011 apply POST] a policy changed'; end if;
  if (select md5(string_agg(p.proname || '=' || coalesce(array_to_string(p.proacl, ','), '<null>'), '|' order by p.proname)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('connected_member', 'membership_entitled_until', 'membership_apply_state_v1')) is distinct from current_setting('s12.acl') then raise exception '[A2 scope011 apply POST] EXECUTE grants on a target changed'; end if;
  if (select count(*)::text || ':' || md5(coalesce(string_agg(m.user_id::text || '|' || m.environment || '|' || coalesce(m.apple_status::text, '-') || '|' || coalesce(m.renewal_date::text, '-') || '|' || coalesce(m.pending_cleanup_at::text, '-') || '|' || coalesce(m.entitlement_ended_at::text, '-'), '#' order by m.user_id, m.environment, m.original_transaction_id), '')) from public.membership m) is distinct from current_setting('s12.membership') then raise exception '[A2 scope011 apply POST] membership rows, schedules or end dates changed'; end if;
  if (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control) is distinct from current_setting('s12.enforcement') then raise exception '[A2 scope011 apply POST] enforcement_enabled changed'; end if;
  if (has_function_privilege('anon', 'public.connected_member(uuid)', 'execute') or has_function_privilege('authenticated', 'public.connected_member(uuid)', 'execute') or has_function_privilege('anon', 'public.membership_entitled_until(uuid)', 'execute') or has_function_privilege('authenticated', 'public.membership_entitled_until(uuid)', 'execute')) then raise exception '[A2 scope011 apply POST] a client role can execute an entitlement function'; end if;
  n := ((select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id)) + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id)) + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id)) + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id)));
  if n <> 0 then raise exception '[A2 scope011 apply POST] cached entitlement drift is % after recompute', n; end if;
end
$s12post$;

commit;

-- ====================================================== verification (read-only)
select jsonb_build_object(
  'artifact', 'A2 scope011 apply',
  'committed', true,
  'connected_member_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member'),
  'membership_entitled_until_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until'),
  'membership_apply_state_v1_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1'),
  'membership_state_comment_md5', md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), '')),
  'cached_drift', ((select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id)) + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id)) + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id)) + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id))),
  'membership', (select count(*)::text || ':' || md5(coalesce(string_agg(m.user_id::text || '|' || m.environment || '|' || coalesce(m.apple_status::text, '-') || '|' || coalesce(m.renewal_date::text, '-') || '|' || coalesce(m.pending_cleanup_at::text, '-') || '|' || coalesce(m.entitlement_ended_at::text, '-'), '#' order by m.user_id, m.environment, m.original_transaction_id), '')) from public.membership m),
  'enforcement_enabled', (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control),
  'observed_at', now())::text as s12_verification;
