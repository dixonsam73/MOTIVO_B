-- B-38 ROLLBACK. Restores the pre-fix state: guard trigger and function removed;
-- the stamping trigger, table grants and column are untouched by apply and rollback.
-- Reviewed with the apply script; Samuel authorised the deployment on 2026-09-20.
-- The executable body below is unchanged from the reviewed text.
begin;
-- >>> B38 ROLLBACK BODY
drop trigger if exists tg_directory_avatar_guard on public.account_directory;
drop function if exists public.tg_guard_avatar_version();
do $$
declare
  t regclass := to_regclass('public.account_directory');
begin
  if exists (select 1 from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_guard')
     or to_regprocedure('public.tg_guard_avatar_version()') is not null then
    raise exception 'B-38 ROLLBACK: guard still present';
  end if;
  if (select row(pg_get_triggerdef(oid), tgenabled, tgfoid) from pg_trigger where tgrelid = t and tgname = 'tg_directory_avatar_version')
     is distinct from row('CREATE TRIGGER tg_directory_avatar_version BEFORE UPDATE OF avatar_key ON public.account_directory FOR EACH ROW EXECUTE FUNCTION tg_stamp_avatar_version()'::text,
                          'O'::"char", to_regprocedure('public.tg_stamp_avatar_version()')::oid) then
    raise exception 'B-38 ROLLBACK: stamping trigger not in its original state';
  end if;
end $$;
-- <<< B38 ROLLBACK BODY
commit;
select 'B-38 rolled back' as result;
