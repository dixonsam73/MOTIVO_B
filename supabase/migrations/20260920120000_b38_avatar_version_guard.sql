-- B-38 — server-derive public.account_directory.avatar_version.
--
-- REPLAY OF A PRODUCTION CHANGE, so a rebuilt local baseline reproduces it and the
-- B-23 gate stays meaningful. Production itself was changed by the guarded script
-- supabase/sql/2026-09-20-b38-avatar-version-guard.sql. This file mirrors the OBJECT
-- DEFINITIONS it creates, not that script verbatim: the pre/post guards live there,
-- and this replay uses `create or replace` plus `drop trigger if exists` so it is
-- idempotent on a local rebuild. This project does not use `supabase db push`.
--
-- A client-supplied avatar_version is discarded on every INSERT and UPDATE, for
-- EVERY role. This trigger fires BEFORE tg_directory_avatar_version (same-timing
-- row triggers run in name order), so an UPDATE that targets avatar_key is still
-- re-stamped to now().

create or replace function public.tg_guard_avatar_version() returns trigger
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

drop trigger if exists tg_directory_avatar_guard on public.account_directory;
create trigger tg_directory_avatar_guard
  before insert or update on public.account_directory
  for each row execute function public.tg_guard_avatar_version();
