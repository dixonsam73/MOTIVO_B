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
