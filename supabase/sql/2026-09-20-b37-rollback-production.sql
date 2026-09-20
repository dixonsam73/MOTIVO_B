-- B-37 — GUARDED PRODUCTION ROLLBACK
--
-- Restores production to its pre-B-37 state: the previous
-- search_account_directory definition, and the counter table dropped.
--
-- THE RESTORED TEXT IS NOT RETYPED OR RECONSTRUCTED. It is the definition from
-- supabase/schema/functions.json, which was verified read-only on 2026-09-20 to
-- reproduce production's own md5 3c1026dc34ef4d2e74cade068d168443 exactly. The POST guard
-- re-asserts that md5 after restoring, so a rollback that lands ANYTHING else
-- aborts rather than leaving a plausible-looking wrong function in place.
--
-- SUBMIT AS ONE SUBMISSION. Guards inside the transaction; the final statement
-- returns a row. Never score this on an exit code or a success message.
--
-- WHAT THIS COSTS, stated accurately. NO DOMAIN 3 CONTENT IS TOUCHED IN EITHER
-- DIRECTION -- no posts, comments, attachments or directory rows. But dropping
-- directory_search_budget discards EVERY ACCOUNT'S current counters, and
-- restoring the previous definition returns the directory to UNMETERED search
-- with wildcard characters live again: both browse routes reopen. That is
-- correct for a rollback -- it restores the pre-B-37 state exactly -- and it is
-- a larger statement than "one member's allowance window", which an earlier
-- revision of this header wrongly claimed.

begin;

-- ---------------------------------------------------------------- PRE guards
do $guard$
declare
    v_md5 text;
begin
    select md5(pg_get_functiondef(p.oid)) into v_md5
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'search_account_directory';

    if v_md5 is null then
        raise exception 'PRE-1 FAILED: public.search_account_directory does not exist';
    end if;
    if v_md5 = '3c1026dc34ef4d2e74cade068d168443' then
        raise exception 'PRE-2 REFUSED: production is ALREADY at the pre-B-37 definition -- nothing to roll back';
    end if;
    if v_md5 <> 'e55b8f0b583d70a6eeeab252fc15b8b3' then
        raise exception 'PRE-3 FAILED: the deployed function is neither the pre-B-37 nor the B-37 definition (md5=%). Stop and investigate; this rollback does not know what it would be discarding', v_md5;
    end if;
end
$guard$;

-- ------------------------------------------ the previous definition, verbatim
CREATE OR REPLACE FUNCTION public.search_account_directory(q text)
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

-- The pre-B-37 grant surface, restated so it is explicit rather than inherited.
revoke all on function public.search_account_directory(text) from public;
revoke all on function public.search_account_directory(text) from anon;
revoke all on function public.search_account_directory(text) from service_role;
grant execute on function public.search_account_directory(text) to authenticated;

drop table if exists public.directory_search_budget;

-- --------------------------------------------------------------- POST guards
do $guard$
declare
    v_md5 text;
begin
    select md5(pg_get_functiondef(p.oid)) into v_md5
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'search_account_directory';

    if v_md5 <> '3c1026dc34ef4d2e74cade068d168443' then
        raise exception 'POST-1 FAILED: the restored definition md5 % is not the pre-B-37 3c1026dc34ef4d2e74cade068d168443', v_md5;
    end if;
    if to_regclass('public.directory_search_budget') is not null then
        raise exception 'POST-2 FAILED: the counter table survived the rollback';
    end if;
    if not has_function_privilege('authenticated', 'public.search_account_directory(text)', 'execute')
       or has_function_privilege('anon', 'public.search_account_directory(text)', 'execute')
       or has_function_privilege('service_role', 'public.search_account_directory(text)', 'execute') then
        raise exception 'POST-3 FAILED: the execute surface is not authenticated-only';
    end if;
    if (select count(*) from pg_policies where schemaname = 'public') <> 23 then
        raise exception 'POST-4 FAILED: the policy count changed';
    end if;
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public') <> 42 then
        raise exception 'POST-5 FAILED: the function count changed';
    end if;
end
$guard$;

commit;

-- THE VERIFICATION ROW. If this returns nothing, the submission did not run.
select
    'B-37 ROLLED BACK'                                               as result,
    md5(pg_get_functiondef(p.oid))                                   as function_md5,
    p.provolatile                                                    as volatility,
    (to_regclass('public.directory_search_budget') is null)          as counter_table_gone,
    (select count(*) from pg_policies where schemaname = 'public')   as public_policies,
    now()                                                            as rolled_back_at
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'search_account_directory';
