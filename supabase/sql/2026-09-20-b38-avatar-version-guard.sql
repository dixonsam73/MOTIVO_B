-- B-38 PROPOSED FIX: server-derive public.account_directory.avatar_version.
-- Samuel AUTHORISED this deployment on 2026-09-20, and Codex reviewed this exact
-- text; Claude applies it to the linked production project. Preconditions that
-- still hold: a FRESH production-parity capture and the B-23 gate (both recorded
-- in README-b38-avatar-version-guard.md).
-- The executable body below is unchanged from the reviewed text.
-- One submission: guards inside the transaction, final SELECT returns a row.
-- A replay of the same objects for local baselines is
-- supabase/migrations/20260920120000_b38_avatar_version_guard.sql.
-- The BODY between the markers contains no transaction control, so the local
-- harness can run it verbatim inside an outer rolled-back transaction.
begin;
-- >>> B38 APPLY BODY
do $$
declare
  t regclass := to_regclass('public.account_directory');
begin
  if t is null then raise exception 'B-38 PRE: public.account_directory not found'; end if;
  if exists (select 1 from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_guard') then
    raise exception 'B-38 PRE: guard trigger already present';
  end if;
  if to_regprocedure('public.tg_guard_avatar_version()') is not null then
    raise exception 'B-38 PRE: guard function already present';
  end if;
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_version')
       is distinct from 'CREATE TRIGGER tg_directory_avatar_version BEFORE UPDATE OF avatar_key ON public.account_directory FOR EACH ROW EXECUTE FUNCTION tg_stamp_avatar_version()'
     or (select tgenabled from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_version') is distinct from 'O'
     or (select tgfoid from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_version')
          is distinct from to_regprocedure('public.tg_stamp_avatar_version()') then
    raise exception 'B-38 PRE: stamping trigger not exactly as expected';
  end if;
  if (select row(atttypid::regtype::text, attnotnull, atthasdef) from pg_attribute
       where attrelid = t and attname = 'avatar_version' and not attisdropped)
     is distinct from row('timestamp with time zone'::text, false, false) then
    raise exception 'B-38 PRE: avatar_version is not nullable timestamptz without default';
  end if;
end $$;

-- A client-supplied avatar_version is discarded on every INSERT and UPDATE, for
-- EVERY role (including service_role and postgres). It fires BEFORE
-- tg_directory_avatar_version (same-timing row triggers run in name order), so
-- an UPDATE that targets avatar_key is still re-stamped to now() afterwards.
create function public.tg_guard_avatar_version() returns trigger
  language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.avatar_version := null;          -- nullable, no default; no writer supplies it
  else
    new.avatar_version := old.avatar_version;
  end if;
  return new;
end
$$;
revoke all on function public.tg_guard_avatar_version() from public, anon, authenticated, service_role;

create trigger tg_directory_avatar_guard
  before insert or update on public.account_directory
  for each row execute function public.tg_guard_avatar_version();

do $$
declare
  t regclass := to_regclass('public.account_directory');
  f regprocedure := to_regprocedure('public.tg_guard_avatar_version()');
begin
  if f is null then raise exception 'B-38 POST: guard function missing'; end if;
  if (select prosecdef from pg_proc where oid = f) is distinct from false
     or (select array_to_string(proconfig, ',') from pg_proc where oid = f) is distinct from 'search_path=""' then
    raise exception 'B-38 POST: guard function attributes unexpected';
  end if;
  if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('service_role', f, 'execute') then
    raise exception 'B-38 POST: guard function executable by a client/service role';
  end if;
  if (select row(pg_get_triggerdef(oid), tgenabled, tgfoid) from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_guard')
     is distinct from row('CREATE TRIGGER tg_directory_avatar_guard BEFORE INSERT OR UPDATE ON public.account_directory FOR EACH ROW EXECUTE FUNCTION tg_guard_avatar_version()'::text, 'O'::"char", f::oid) then
    raise exception 'B-38 POST: guard trigger definition unexpected';
  end if;
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_version')
       is distinct from 'CREATE TRIGGER tg_directory_avatar_version BEFORE UPDATE OF avatar_key ON public.account_directory FOR EACH ROW EXECUTE FUNCTION tg_stamp_avatar_version()' then
    raise exception 'B-38 POST: stamping trigger changed';
  end if;
  if (select array_agg(tgname::text order by tgname) from pg_trigger
       where tgrelid = t and not tgisinternal and tgname like 'tg_directory_avatar_%')
     is distinct from array['tg_directory_avatar_guard','tg_directory_avatar_version'] then
    raise exception 'B-38 POST: trigger set or order unexpected';
  end if;
end $$;
-- <<< B38 APPLY BODY
commit;
select 'B-38 applied' as result,
       (select count(*) from pg_trigger where tgrelid = 'public.account_directory'::regclass
          and tgname = 'tg_directory_avatar_guard') as guard_triggers;
