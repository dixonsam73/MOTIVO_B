-- P4-U7 / C-58 — FOLLOW-SCOPED RETAINED ATTRIBUTION FOR A LAPSED VIEWER.
--
-- PROBLEM (measured, enforcement ON): a lapsed viewer keeps the `follows` row
-- -- SELECT is deliberately ungated so withdrawal stays possible (D-U6-2) --
-- but `get_account_directory_by_user_ids` is VIEWER-gated, so it returns
-- nothing and the client falls through to "User • <last 6 of user_id>".
-- A surviving relationship the viewer is allowed to manage is unintelligible.
--
-- FIX: one additional DISJUNCT. Resolution is also permitted when the viewer
-- holds an APPROVED follow with the requested user_id, in either direction.
--
-- WHY `approved` AND NOT "any row the viewer can already see": an unentitled
-- viewer cannot manufacture an approved row, because approval is a gated UPDATE
-- performed by the OTHER party (follows_update_approve_by_followed). Keying on
-- mere visibility would instead borrow its safety from
-- follows_insert_requester's gate; if that were ever ungated, this RPC would
-- become a self-serve UUID -> identity oracle -- the general resolver B-5
-- hardened these RPCs against. The safety is intrinsic here, not borrowed.
--
-- PURELY ADDITIVE ON THE VIEWER AXIS. The gate stays the FIRST disjunct, so it
-- is still evaluated on every call (preserving shadow_enforcement_stat
-- telemetry) and an entitled viewer short-circuits to exactly today's
-- behaviour. No row the gate would have returned is removed.
--
-- G10 HOLDS: there is still no SUBJECT-side filter. The new clause is about the
-- VIEWER's relationship to the subject, never about the subject's own
-- entitlement. A lapsed author's attribution still resolves for an entitled
-- viewer. Nothing here touches search_account_directory, so a lapsed member
-- stays undiscoverable (D-7 / B-15).
--
-- CREATE OR REPLACE with an UNCHANGED signature and return type, so grants are
-- preserved and no REVOKE/GRANT restoration is needed.

begin;

create or replace function public.get_account_directory_by_user_ids(user_ids uuid[])
 returns table(user_id uuid, account_id text, display_name text, location text,
               avatar_key text, instruments text[], avatar_version timestamp with time zone)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select
    ad.user_id,
    ad.account_id,
    ad.display_name,
    ad.location,
    ad.avatar_key,
    ad.instruments,
    ad.avatar_version
  from public.account_directory ad
  where auth.uid() is not null
    and ad.user_id = any(user_ids)
    and (
      (select public.enforcement_gate('rpc.get_account_directory_by_user_ids'))
      or exists (
        select 1
        from public.follows f
        where f.status = 'approved'
          and ( (f.follower_user_id = auth.uid() and f.followed_user_id = ad.user_id)
             or (f.followed_user_id = auth.uid() and f.follower_user_id = ad.user_id) )
      )
    );
$function$;

-- ------------------------------------------------------------------ GUARDS
-- Inside the transaction, asserting the state this statement just produced.
-- A success message from the thing being asked to act is not evidence.
do $$
declare
  v_src  text;
  v_cols int;
  v_n    int;
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_account_directory_by_user_ids';
  if v_n <> 1 then raise exception 'GUARD 1 failed: expected exactly 1 function, found %', v_n; end if;

  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_account_directory_by_user_ids';

  if v_src not like '%enforcement_gate%' then
    raise exception 'GUARD 2 failed: the viewer gate is no longer present';
  end if;
  if v_src not like '%public.follows%' or v_src not like '%approved%' then
    raise exception 'GUARD 3 failed: the follow-scoped disjunct is absent';
  end if;

  -- G10: no SUBJECT-side membership predicate. This is U6b-J3's assertion.
  if regexp_replace(v_src, '--[^\n]*', '', 'g') like '%connected_member%'
     or regexp_replace(v_src, '--[^\n]*', '', 'g') like '%entitled_until%' then
    raise exception 'GUARD 4 failed: a subject-side predicate appeared -- G10 violated';
  end if;

end $$;

-- Return-type and privilege guards, expressed as a failing SELECT rather than
-- procedurally, so the values are visible in the output.
do $$
declare
  v_res text;
  v_sec boolean;
  v_cfg text;
  v_anon boolean; v_auth boolean; v_svc boolean;
  v_oid oid;
begin
  select p.oid, pg_get_function_result(p.oid), p.prosecdef,
         coalesce(array_to_string(p.proconfig, ','), 'none')
    into v_oid, v_res, v_sec, v_cfg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_account_directory_by_user_ids';

  if v_res not like '%avatar_version timestamp with time zone%' then
    raise exception 'GUARD 5 failed: return type lost avatar_version -- got %', v_res;
  end if;
  if not v_sec then raise exception 'GUARD 6 failed: no longer SECURITY DEFINER'; end if;
  if v_cfg <> 'search_path=public' then
    raise exception 'GUARD 7 failed: search_path changed -- got %', v_cfg;
  end if;

  v_anon := has_function_privilege('anon', v_oid, 'EXECUTE');
  v_auth := has_function_privilege('authenticated', v_oid, 'EXECUTE');
  v_svc  := has_function_privilege('service_role', v_oid, 'EXECUTE');
  if v_anon or v_svc or not v_auth then
    raise exception 'GUARD 8 failed: grants moved -- anon=% authenticated=% service_role=% (expected f/t/f)',
      v_anon, v_auth, v_svc;
  end if;
end $$;

-- A statement that RETURNS A ROW, so "no rows returned" is the symptom rather
-- than the disguise.
select
  p.proname                                                as function_name,
  md5(pg_get_functiondef(p.oid))                           as def_md5,
  p.prosecdef                                              as security_definer,
  has_function_privilege('anon', p.oid, 'EXECUTE')         as anon_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_execute,
  (p.prosrc like '%public.follows%')                       as has_follow_scope,
  (regexp_replace(p.prosrc,'--[^\n]*','','g') like '%connected_member%'
   or regexp_replace(p.prosrc,'--[^\n]*','','g') like '%entitled_until%') as g10_violated
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_account_directory_by_user_ids';

commit;
