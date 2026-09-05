-- P4-U5 / C-34 — THE AVATAR VERSION SIGNAL (version half only; TTL is Phase 5).
--
-- WHY A SIGNAL IS NEEDED AT ALL. `avatar_key` is content-invariant by design:
-- the upload upserts to the fixed key `users/<uid>/avatar.jpg`, which is what
-- stops stale duplicates accumulating. So replacing an avatar changes the BYTES
-- and nothing else, and every other member's `NSCache` — keyed on
-- "avatars|<avatar_key>", no TTL — keeps serving the previous image.
--
-- THE TRIGGER CONDITION THAT WOULD LOOK RIGHT AND NEVER FIRE.
-- `NEW.avatar_key IS DISTINCT FROM OLD.avatar_key` is FALSE on every
-- replacement, because the client PATCHes the identical value. Measured, not
-- assumed: `BEFORE UPDATE OF avatar_key` fires when the column is TARGETED BY
-- THE SET CLAUSE, whether or not the value changes —
--
--     SET avatar_key = <same value>   -> fires        (the replacement path)
--     SET <other column> = ...        -> does NOT fire (unrelated edits)
--     SET avatar_key = <new value>    -> fires
--
-- so `UPDATE OF` is both sufficient for the defect and narrow enough not to
-- invalidate every member's avatar cache on an unrelated directory edit.
--
-- NULL IS A VALID VERSION AND THERE IS NO BACKFILL. Existing rows keep
-- avatar_version NULL and continue rendering; the client folds NULL into the
-- cache identity as a stable empty component. The first replacement stamps.
-- Rewriting every directory row to seed a version would invalidate every
-- member's cache once for no benefit.
--
-- THE DROP/CREATE HAZARD IS REAL AND IS WHY THE GRANTS ARE RESTATED.
-- Changing a function's RETURNS TABLE requires DROP + CREATE, and Supabase's
-- default privileges on `public` re-grant anon, authenticated and service_role
-- on any NEWLY CREATED object — B-15's recorded warning, operative here. Both
-- functions are `authenticated`-ONLY today (B-5), and both REVOKE/GRANT pairs
-- below exist to put them back exactly, not as decoration.
--
-- G10 IS UNTOUCHED. `get_account_directory_by_user_ids` gains a RETURNED COLUMN
-- and no predicate. It still has no subject-side discoverability filter, which
-- is the only reason undiscoverability and retained attribution can coexist.
-- `search_account_directory` keeps `auth.uid() is not null`, its self-exclusion
-- and its 2-character floor verbatim — B-15 is disposed on measurement, not by
-- changing a number.

begin;

-- 1 ---------------------------------------------------------------- the column
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

-- 6 ------------------------------------------------------------------ GUARDS
-- INSIDE the transaction, asserting the state this text has just produced.
-- "Success. No rows returned." must never be able to disguise a no-op.
do $guard$
declare n int;
begin
  select count(*) into n from information_schema.columns
   where table_schema='public' and table_name='account_directory'
     and column_name='avatar_version';
  if n <> 1 then raise exception 'GUARD 1 FAILED: avatar_version column missing'; end if;

  select count(*) into n from pg_trigger
   where tgrelid='public.account_directory'::regclass
     and tgname='tg_directory_avatar_version' and not tgisinternal;
  if n <> 1 then raise exception 'GUARD 2 FAILED: trigger missing'; end if;

  -- the trigger must be UPDATE OF avatar_key, not a blanket UPDATE
  select count(*) into n from pg_trigger
   where tgrelid='public.account_directory'::regclass
     and tgname='tg_directory_avatar_version'
     and pg_get_triggerdef(oid) like '%UPDATE OF avatar_key%';
  if n <> 1 then raise exception 'GUARD 3 FAILED: trigger is not UPDATE OF avatar_key'; end if;

  select count(*) into n from pg_proc
   where proname in ('search_account_directory','get_account_directory_by_user_ids')
     and pg_get_function_result(oid) like '%avatar_version timestamp with time zone%';
  if n <> 2 then raise exception 'GUARD 4 FAILED: RPCs do not both return avatar_version'; end if;

  -- GRANTS RESTORED EXACTLY: authenticated yes, everyone else no
  if not has_function_privilege('authenticated','public.search_account_directory(text)','EXECUTE')
     or not has_function_privilege('authenticated','public.get_account_directory_by_user_ids(uuid[])','EXECUTE')
  then raise exception 'GUARD 5 FAILED: authenticated lost EXECUTE'; end if;

  if has_function_privilege('anon','public.search_account_directory(text)','EXECUTE')
     or has_function_privilege('anon','public.get_account_directory_by_user_ids(uuid[])','EXECUTE')
     or has_function_privilege('service_role','public.search_account_directory(text)','EXECUTE')
     or has_function_privilege('service_role','public.get_account_directory_by_user_ids(uuid[])','EXECUTE')
  then raise exception 'GUARD 6 FAILED: drop/recreate restored a grant (B-15)'; end if;

  -- G10: the by-ids RPC must still carry NO subject-side filter
  select count(*) into n from pg_proc
   where proname='get_account_directory_by_user_ids'
     and (prosrc like '%entitled_until%' or prosrc like '%lookup_enabled%');
  if n <> 0 then raise exception 'GUARD 7 FAILED: by-ids RPC acquired a subject-side filter (G10)'; end if;
end
$guard$;

-- 7 --------------------- A RETURNING SELECT, so "no rows" is the symptom
select 'u5-avatar-version applied' as result,
       (select count(*) from information_schema.columns
         where table_schema='public' and table_name='account_directory'
           and column_name='avatar_version') as column_present,
       (select count(*) from pg_trigger
         where tgrelid='public.account_directory'::regclass
           and tgname='tg_directory_avatar_version' and not tgisinternal) as trigger_present,
       (select count(*) from pg_proc
         where proname in ('search_account_directory','get_account_directory_by_user_ids')
           and pg_get_function_result(oid) like '%avatar_version timestamp with time zone%') as rpcs_updated;

commit;
