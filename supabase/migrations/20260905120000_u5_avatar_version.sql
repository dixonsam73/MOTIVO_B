-- P4-U5 SERVER HALF, REPLAYED FOR THE LOCAL STACK ONLY.
--
-- FOUND BY P4-U7, 2026-09-05. U5's server half was applied to PRODUCTION from
-- `supabase/sql/2026-09-05-u5-avatar-version.sql` and was never added here, so
-- `supabase db reset --local` rebuilt a stack WITHOUT `avatar_version`: the
-- local RPCs returned 6 columns while production returns 7.
--
-- THAT IS A B-23 FIDELITY DEFECT, not a cosmetic one. A local rehearsal of any
-- change to these objects would have been rehearsed against the wrong
-- definition -- which is exactly how it was caught: a CREATE OR REPLACE that is
-- correct against production failed locally with "cannot change return type".
--
-- THIS FILE CHANGES NOTHING IN PRODUCTION. Production already holds this state,
-- verified by md5 against `supabase/schema/functions.json`. It exists so the
-- local reproduction matches what is deployed.

alter table public.account_directory
  add column if not exists avatar_version timestamptz;

-- 2 ------------------------------------------------------------ the stamp
create or replace function public.tg_stamp_avatar_version()
returns trigger
language plpgsql
as $fn$
begin
  new.avatar_version := now();
  return new;
end
$fn$;

-- 3 ----------------------------------------------------------- the trigger
drop trigger if exists tg_directory_avatar_version on public.account_directory;
create trigger tg_directory_avatar_version
  before update of avatar_key on public.account_directory
  for each row execute function public.tg_stamp_avatar_version();

-- 4 ------------------------------- search_account_directory: +avatar_version
-- Body reproduced VERBATIM apart from the one added output column.
drop function if exists public.search_account_directory(text);

create function public.search_account_directory(q text)
returns table(user_id uuid, account_id text, display_name text, location text,
              avatar_key text, instruments text[], avatar_version timestamptz)
language sql
stable
security definer
set search_path to 'public'
as $function$

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
$function$;

revoke all on function public.search_account_directory(text) from public;
revoke all on function public.search_account_directory(text) from anon;
revoke all on function public.search_account_directory(text) from service_role;
grant execute on function public.search_account_directory(text) to authenticated;

-- 5 ------------------- get_account_directory_by_user_ids: +avatar_version only
drop function if exists public.get_account_directory_by_user_ids(uuid[]);

create function public.get_account_directory_by_user_ids(user_ids uuid[])
returns table(user_id uuid, account_id text, display_name text, location text,
              avatar_key text, instruments text[], avatar_version timestamptz)
language sql
stable
security definer
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
  where (select public.enforcement_gate('rpc.get_account_directory_by_user_ids'))
    and auth.uid() is not null
    and ad.user_id = any(user_ids);
$function$;

revoke all on function public.get_account_directory_by_user_ids(uuid[]) from public;
revoke all on function public.get_account_directory_by_user_ids(uuid[]) from anon;
revoke all on function public.get_account_directory_by_user_ids(uuid[]) from service_role;
grant execute on function public.get_account_directory_by_user_ids(uuid[]) to authenticated;

