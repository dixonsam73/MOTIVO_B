begin;
-- R1 — B-39 PRODUCTION ROLLBACK to the pre-B-39 production bodies, guarded. RUN R2 FIRST IF A2 IS APPLIED.
-- Generated 2026-09-15 by claude-evidence/scope012/gen_artifacts.py. DO NOT HAND-EDIT: regenerate.
--
-- Body: the three pre-B-39 definitions exactly as captured from production by H1
-- (pg_get_functiondef, md5-equal to H2 and to the committed snapshot).
-- Recompute: the four cached columns for identities holding apple_status = 5 rows.
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
  if n <> 6 then raise exception '[R1 B-39 rollback PRE] expected exactly one function for each of the 6 targets, found %', n; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member');
  if v is distinct from '8e39f78402ec6402f690bcfa8935a8d4' then raise exception '[R1 B-39 rollback PRE] % md5 is %, expected %', 'connected_member', v, '8e39f78402ec6402f690bcfa8935a8d4'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1');
  if v is distinct from 'e77f869be62c319012203cb2fafbbe2d' then raise exception '[R1 B-39 rollback PRE] % md5 is %, expected %', 'membership_apply_state_v1', v, 'e77f869be62c319012203cb2fafbbe2d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until');
  if v is distinct from 'e74146e4d9e5dc752e7fec34a3d3797f' then raise exception '[R1 B-39 rollback PRE] % md5 is %, expected %', 'membership_entitled_until', v, 'e74146e4d9e5dc752e7fec34a3d3797f'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_requests_open');
  if v is distinct from 'f730fb8adba2011f0600f16ef6883d5d' then raise exception '[R1 B-39 rollback PRE] % md5 is %, expected %', 'account_privacy_requests_open', v, 'f730fb8adba2011f0600f16ef6883d5d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_self_v1');
  if v is distinct from '1f87a5832b702c369f169217b2eaceae' then raise exception '[R1 B-39 rollback PRE] % md5 is %, expected %', 'account_privacy_self_v1', v, '1f87a5832b702c369f169217b2eaceae'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_upsert_v1');
  if v is distinct from '13df8a41f6011aba4e68fdd5ea615065' then raise exception '[R1 B-39 rollback PRE] % md5 is %, expected %', 'account_privacy_upsert_v1', v, '13df8a41f6011aba4e68fdd5ea615065'; end if;
  v := md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), ''));
  if v is distinct from '9ae51ea9798396177f2799754692c9ff' then raise exception '[R1 B-39 rollback PRE] membership_state comment md5 is %, expected %', v, '9ae51ea9798396177f2799754692c9ff'; end if;
  n := ((select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id)) + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id)) + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id)) + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id)));
  if n <> 0 then raise exception '[R1 B-39 rollback PRE] cached entitlement drift is % -- refusing; drift is assessed, never repaired here', n; end if;
  perform set_config('s12.others', (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || pg_get_functiondef(p.oid) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname, pg_get_function_identity_arguments(p.oid))) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname <> all (array['connected_member', 'membership_entitled_until', 'membership_apply_state_v1'])), true);
  perform set_config('s12.policies', (select md5(coalesce(string_agg(schemaname || '.' || tablename || '.' || policyname || '|' || permissive || '|' || roles::text || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by schemaname, tablename, policyname), '')) from pg_policies where schemaname in ('public', 'storage')), true);
  perform set_config('s12.acl', (select md5(string_agg(p.proname || '=' || coalesce(array_to_string(p.proacl, ','), '<null>'), '|' order by p.proname)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('connected_member', 'membership_entitled_until', 'membership_apply_state_v1')), true);
  perform set_config('s12.membership', (select count(*)::text || ':' || md5(coalesce(string_agg(m.user_id::text || '|' || m.environment || '|' || coalesce(m.apple_status::text, '-') || '|' || coalesce(m.renewal_date::text, '-') || '|' || coalesce(m.pending_cleanup_at::text, '-') || '|' || coalesce(m.entitlement_ended_at::text, '-'), '#' order by m.user_id, m.environment, m.original_transaction_id), '')) from public.membership m), true);
  perform set_config('s12.enforcement', (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control), true);
end
$s12pre$;

-- ======================================================================== BODY
CREATE OR REPLACE FUNCTION public.connected_member(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.membership_entitled_until(target_user_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select max(greatest(
           m.renewal_date,
           case when m.is_in_billing_retry then m.grace_period_expires_date end
         ))
    from public.membership m
   where m.user_id = target_user_id
     and m.environment = 'Production';
$function$;

CREATE OR REPLACE FUNCTION public.membership_apply_state_v1(p_user_id uuid, p_environment text, p_original_transaction_id text, p_state jsonb, p_notification_uuid uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- 60 DAYS IS A HARD CONSTANT AND PRODUCTION CANNOT SHORTEN IT. It is used
  -- ONCE, here, at scheduling; U7's worker afterwards reads only the stored
  -- timestamp. That separation is what lets the deadline behaviour be exercised
  -- with fixture rows instead of a config override or a clock.
  c_quarantine   constant interval := interval '60 days';

  v_signed       timestamptz := (p_state->>'renewal_info_signed_date')::timestamptz;
  v_renewal      timestamptz := nullif(p_state->>'renewal_date', '')::timestamptz;
  v_grace        timestamptz := nullif(p_state->>'grace_period_expires_date', '')::timestamptz;
  v_retry        boolean     := coalesce((p_state->>'is_in_billing_retry')::boolean, false);
  v_revoked      timestamptz := nullif(p_state->>'revocation_date', '')::timestamptz;
  v_product      text        := nullif(p_state->>'product_id', '');
  v_entitled     boolean;
  v_prev         public.membership%rowtype;
  v_ended        timestamptz;
  v_cleanup      timestamptz;
begin
  -- HARD PRECONDITIONS, restated here even though most are also constraints.
  -- This is the only function that may schedule cleanup, so a caller that
  -- reached it with incomplete or unmapped state is a DEFECT and must stop
  -- rather than write. Every one of these is unreachable from the entry points
  -- below, which is the point: if one ever fires, the bug is upstream.
  if p_user_id is null then
    raise exception 'membership_apply_state_v1: no user_id' using errcode = '22004';
  end if;
  if v_signed is null then
    raise exception 'membership_apply_state_v1: no renewal_info_signed_date' using errcode = '22004';
  end if;
  if v_product is null then
    raise exception 'membership_apply_state_v1: no product_id' using errcode = '22004';
  end if;
  if p_original_transaction_id is null then
    raise exception 'membership_apply_state_v1: no original_transaction_id' using errcode = '22004';
  end if;
  -- OWNERSHIP IS A PRECONDITION OF WRITING, not a property checked afterwards.
  if not exists (select 1 from public.membership_binding b where b.user_id = p_user_id) then
    raise exception 'membership_apply_state_v1: no live binding for %', p_user_id
      using errcode = '23514';
  end if;

  select * into v_prev
    from public.membership m
   where m.user_id = p_user_id and m.environment = p_environment;

  -- NO ROW MEANS NO AUTHORITY TO CREATE ONE. Returned as data, not raised: a
  -- mapped notification arriving before establishment is an ordinary thing to
  -- happen, not a fault, and it must be recorded rather than lost.
  if not found then
    return jsonb_build_object(
      'outcome', 'ignored',
      'needs_establishment', true,
      'reason', 'no authoritative membership row; ownership establishment belongs to U5');
  end if;

  -- Apple's own service formula, identical in meaning to connected_member()'s
  -- per-row expression and to Transaction.currentEntitlements on device.
  -- isInBillingRetryPeriod alone does NOT entitle.
  v_entitled := coalesce(v_renewal > now(), false)
             or coalesce(v_retry and v_grace > now(), false);

  if v_entitled then
    -- Resubscription, refund reversal or grace recovery CANCELS pending cleanup.
    -- QA C5 / G6c.
    v_ended   := null;
    v_cleanup := null;
  else
    -- The instant entitlement actually ended, preferring Apple's own dates over
    -- our clock so the 60 days is measured from the truth rather than from when
    -- we happened to hear about it. GREATEST ignores NULLs unless all are NULL.
    v_ended := coalesce(v_revoked, greatest(v_renewal, v_grace), now());
    -- Never slide an already-recorded end forward: that would silently extend
    -- quarantine every time a later notification arrived.
    if v_prev.entitlement_ended_at is not null then
      v_ended := least(v_prev.entitlement_ended_at, v_ended);
    end if;
    v_cleanup := v_ended + c_quarantine;

    -- U7b. THE QUARANTINE IS NEVER RETROACTIVELY SPENT.
    --
    -- THE BORN-LAPSED CASE, left explicitly open by U5b and closed here. A row
    -- established while Apple already reported not-entitled carries no schedule
    -- (F11: membership_establish_v1 writes NULL to both columns on every insert
    -- path, unconditionally). The FIRST transition observed afterwards computes
    -- v_ended from Apple's own dates -- and for a subscription that lapsed eight
    -- months ago that is eight months in the past, so v_ended + 60 days lands
    -- SIX MONTHS AGO and the schedule is due the instant it is written.
    --
    -- The consequence is not theoretical and the timing is the worst available:
    -- the identity in this state is the dormant pre-cutover subscriber U5 exists
    -- to rescue, who is holding the app open right now, being denied by
    -- enforcement, and is therefore the person most likely to resubscribe within
    -- minutes. Quarantine exists so that resubscribing restores their presence
    -- whole. A deadline already past gives them none of it.
    --
    -- entitlement_ended_at IS NOT TOUCHED and remains Apple's own truth. Only
    -- the SCHEDULE is floored, so no fact is falsified -- the row still records
    -- exactly when entitlement ended.
    --
    -- THE GUARD IS `v_prev.pending_cleanup_at is null`, WHICH IS WHAT KEEPS THIS
    -- FROM BECOMING A SLIDING DEADLINE. It fires only where no schedule existed;
    -- an already-recorded schedule is never pushed out, so the anti-sliding rule
    -- immediately above survives intact. On an ordinary lapse v_ended is
    -- approximately now(), v_cleanup is sixty days in the future, and the second
    -- condition CANNOT be true -- which is asserted in both directions rather
    -- than assumed, because a guard that never fires and a guard that always
    -- fires are both defects and only one of them is visible.
    if v_prev.pending_cleanup_at is null and v_cleanup <= now() then
      v_cleanup := now() + c_quarantine;
    end if;
  end if;

  -- ORDERING IS ENFORCED IN THE STATEMENT, NOT IN THE CALLER. The predicate makes
  -- an out-of-order delivery a no-op by construction, so two concurrent
  -- notifications cannot interleave into a lost update. No updated row is
  -- 'stale', not an error.
  --
  -- The key is renewalInfo's OWN signedDate, never the notification's: a
  -- notification signed later can carry renewal info signed earlier.
  --
  -- binding_method and bound_at are ABSENT from this statement, and their absence
  -- is the correction. Ownership is established once, by U5; rebinding is a
  -- security and account-recovery event for explicit operator disposition, never
  -- ordinary application logic (B-24).
  update public.membership m
     set original_transaction_id   = p_original_transaction_id,
         product_id                = v_product,
         apple_status              = (p_state->>'apple_status')::smallint,
         renewal_date              = v_renewal,
         grace_period_expires_date = v_grace,
         is_in_billing_retry       = v_retry,
         auto_renew_status         = (p_state->>'auto_renew_status')::smallint,
         expiration_intent         = (p_state->>'expiration_intent')::smallint,
         revocation_date           = v_revoked,
         renewal_info_signed_date  = v_signed,
         last_notification_uuid    = coalesce(p_notification_uuid, m.last_notification_uuid),
         entitlement_ended_at      = v_ended,
         pending_cleanup_at        = v_cleanup,
         updated_at                = now()
   where m.user_id = p_user_id
     and m.environment = p_environment
     and v_signed > m.renewal_info_signed_date;

  if not found then
    return jsonb_build_object(
      'outcome', 'stale',
      'entitled', v_entitled,
      'reason', 'renewal_info_signed_date not newer than the stored row');
  end if;

  return jsonb_build_object(
    'outcome', 'applied',
    'entitled', v_entitled,
    'entitlement_ended_at', v_ended,
    'pending_cleanup_at', v_cleanup);
end
$function$;

-- =================================================================== RECOMPUTE
update public.posts t
   set owner_entitled_until = public.membership_entitled_until(t.owner_user_id)
 where t.owner_user_id in (select m.user_id from public.membership m where m.apple_status = 5)
   and t.owner_entitled_until is distinct from public.membership_entitled_until(t.owner_user_id);
update public.post_shares t
   set owner_entitled_until = public.membership_entitled_until(t.owner_user_id)
 where t.owner_user_id in (select m.user_id from public.membership m where m.apple_status = 5)
   and t.owner_entitled_until is distinct from public.membership_entitled_until(t.owner_user_id);
update public.follows t
   set followed_entitled_until = public.membership_entitled_until(t.followed_user_id)
 where t.followed_user_id in (select m.user_id from public.membership m where m.apple_status = 5)
   and t.followed_entitled_until is distinct from public.membership_entitled_until(t.followed_user_id);
update public.account_directory t
   set entitled_until = public.membership_entitled_until(t.user_id)
 where t.user_id in (select m.user_id from public.membership m where m.apple_status = 5)
   and t.entitled_until is distinct from public.membership_entitled_until(t.user_id);

-- ================================================================== POST guards
do $s12post$
declare v text; n bigint;
begin
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member');
  if v is distinct from '4c8733fbece816ed381f955a22b0f6f9' then raise exception '[R1 B-39 rollback POST] % md5 is %, expected %', 'connected_member', v, '4c8733fbece816ed381f955a22b0f6f9'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until');
  if v is distinct from '77c80981c1fdbf2862c34b3e151e7f84' then raise exception '[R1 B-39 rollback POST] % md5 is %, expected %', 'membership_entitled_until', v, '77c80981c1fdbf2862c34b3e151e7f84'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1');
  if v is distinct from 'd1b4d46af44f41953a97afae88e3f1f0' then raise exception '[R1 B-39 rollback POST] % md5 is %, expected %', 'membership_apply_state_v1', v, 'd1b4d46af44f41953a97afae88e3f1f0'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_requests_open');
  if v is distinct from 'f730fb8adba2011f0600f16ef6883d5d' then raise exception '[R1 B-39 rollback POST] % md5 is %, expected %', 'account_privacy_requests_open', v, 'f730fb8adba2011f0600f16ef6883d5d'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_self_v1');
  if v is distinct from '1f87a5832b702c369f169217b2eaceae' then raise exception '[R1 B-39 rollback POST] % md5 is %, expected %', 'account_privacy_self_v1', v, '1f87a5832b702c369f169217b2eaceae'; end if;
  v := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'account_privacy_upsert_v1');
  if v is distinct from '13df8a41f6011aba4e68fdd5ea615065' then raise exception '[R1 B-39 rollback POST] % md5 is %, expected %', 'account_privacy_upsert_v1', v, '13df8a41f6011aba4e68fdd5ea615065'; end if;
  v := md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), ''));
  if v is distinct from '9ae51ea9798396177f2799754692c9ff' then raise exception '[R1 B-39 rollback POST] membership_state comment md5 is %, expected %', v, '9ae51ea9798396177f2799754692c9ff'; end if;
  if (select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || pg_get_functiondef(p.oid) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname, pg_get_function_identity_arguments(p.oid))) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname <> all (array['connected_member', 'membership_entitled_until', 'membership_apply_state_v1'])) is distinct from current_setting('s12.others') then raise exception '[R1 B-39 rollback POST] a non-target public function changed'; end if;
  if (select md5(coalesce(string_agg(schemaname || '.' || tablename || '.' || policyname || '|' || permissive || '|' || roles::text || '|' || cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''), '#' order by schemaname, tablename, policyname), '')) from pg_policies where schemaname in ('public', 'storage')) is distinct from current_setting('s12.policies') then raise exception '[R1 B-39 rollback POST] a policy changed'; end if;
  if (select md5(string_agg(p.proname || '=' || coalesce(array_to_string(p.proacl, ','), '<null>'), '|' order by p.proname)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('connected_member', 'membership_entitled_until', 'membership_apply_state_v1')) is distinct from current_setting('s12.acl') then raise exception '[R1 B-39 rollback POST] EXECUTE grants on a target changed'; end if;
  if (select count(*)::text || ':' || md5(coalesce(string_agg(m.user_id::text || '|' || m.environment || '|' || coalesce(m.apple_status::text, '-') || '|' || coalesce(m.renewal_date::text, '-') || '|' || coalesce(m.pending_cleanup_at::text, '-') || '|' || coalesce(m.entitlement_ended_at::text, '-'), '#' order by m.user_id, m.environment, m.original_transaction_id), '')) from public.membership m) is distinct from current_setting('s12.membership') then raise exception '[R1 B-39 rollback POST] membership rows, schedules or end dates changed'; end if;
  if (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control) is distinct from current_setting('s12.enforcement') then raise exception '[R1 B-39 rollback POST] enforcement_enabled changed'; end if;
  if (has_function_privilege('anon', 'public.connected_member(uuid)', 'execute') or has_function_privilege('authenticated', 'public.connected_member(uuid)', 'execute') or has_function_privilege('anon', 'public.membership_entitled_until(uuid)', 'execute') or has_function_privilege('authenticated', 'public.membership_entitled_until(uuid)', 'execute')) then raise exception '[R1 B-39 rollback POST] a client role can execute an entitlement function'; end if;
  n := ((select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id)) + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id)) + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id)) + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id)));
  if n <> 0 then raise exception '[R1 B-39 rollback POST] cached entitlement drift is % after recompute', n; end if;
end
$s12post$;

commit;

-- ====================================================== verification (read-only)
select jsonb_build_object(
  'artifact', 'R1 B-39 rollback',
  'committed', true,
  'connected_member_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'connected_member'),
  'membership_entitled_until_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_entitled_until'),
  'membership_apply_state_v1_md5', (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = 'membership_apply_state_v1'),
  'membership_state_comment_md5', md5(coalesce(obj_description('public.membership_state(uuid)'::regprocedure, 'pg_proc'), '')),
  'cached_drift', ((select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id)) + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id)) + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id)) + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id))),
  'membership', (select count(*)::text || ':' || md5(coalesce(string_agg(m.user_id::text || '|' || m.environment || '|' || coalesce(m.apple_status::text, '-') || '|' || coalesce(m.renewal_date::text, '-') || '|' || coalesce(m.pending_cleanup_at::text, '-') || '|' || coalesce(m.entitlement_ended_at::text, '-'), '#' order by m.user_id, m.environment, m.original_transaction_id), '')) from public.membership m),
  'enforcement_enabled', (select coalesce(bool_or(enforcement_enabled)::text, 'null') from public.membership_control),
  'observed_at', now())::text as s12_verification;
