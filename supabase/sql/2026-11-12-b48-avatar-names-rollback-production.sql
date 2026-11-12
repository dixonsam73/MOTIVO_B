-- B-48 + avatar names: ROLLBACK OF THE TWO STORAGE POLICIES ONLY. Review before use.
--
-- THE OWNERSHIP CONSTRAINT IS NOT ROLLED BACK. account_directory_avatar_key_own_folder
-- is the fix for B-48 and stays whatever happens to the policies; it accepts
-- the old name, so it never stands in the way of an old build or of this script.
--
-- DEPENDENCIES. Read before running.
--   * A build that stores per-upload names can only upload under the widened
--     INSERT policy. Restoring the old INSERT policy while such a build is
--     installed anywhere means that build can no longer publish a photo. Roll
--     the APP back first (an old build reads a per-upload reference and writes
--     the old name), then this.
--   * Once any per-upload image exists, its owner can only delete it under the
--     widened DELETE policy. This script therefore REFUSES while any per-upload
--     image or reference exists. In that state do not roll the policies back:
--     roll back the app only.
-- Run: supabase db query --linked -f supabase/sql/2026-11-12-b48-avatar-names-rollback-production.sql
-- Expect the final row: rolled back | t   (policies old, constraint still validated).
-- The exit code is 0 even on failure: read the response.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
do $b48_rollback_guard$
declare
  images integer;
  refs integer;
begin
  if (select with_check from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and policyname = 'avatars_insert_owner_only' and cmd = 'INSERT' and roles = '{authenticated}')
     is distinct from $q$(( SELECT enforcement_gate('storage.avatars_insert'::text) AS enforcement_gate) AND (bucket_id = 'avatars'::text) AND ((name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)) OR (name ~ (('^users/'::text || (auth.uid())::text) || '/avatar-[0-9a-f]{32}\.jpg$'::text))))$q$
     or (select qual from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and policyname = 'avatars_delete_owner_only' and cmd = 'DELETE' and roles = '{authenticated}')
     is distinct from $q$((bucket_id = 'avatars'::text) AND ((name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)) OR (name ~ (('^users/'::text || (auth.uid())::text) || '/avatar-[0-9a-f]{32}\.jpg$'::text))))$q$ then
    raise exception 'B-48 rollback: the avatar policies are not in the B-48 state; re-review required. Nothing was changed';
  end if;
  select count(*) into images from storage.objects
   where bucket_id = 'avatars' and name ~ '/avatar-[0-9a-f]{32}\.jpg$';
  select count(*) into refs from public.account_directory
   where avatar_key ~ '/avatar-[0-9a-f]{32}\.jpg$';
  if images > 0 or refs > 0 then
    raise exception 'B-48 rollback: % per-upload image(s) and % reference(s) to one exist. Their owners need the widened DELETE policy. Nothing was changed', images, refs;
  end if;
end $b48_rollback_guard$;

alter policy avatars_insert_owner_only on storage.objects
  with check ((select public.enforcement_gate('storage.avatars_insert'))
     and (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))));

alter policy avatars_delete_owner_only on storage.objects
  using (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))));
COMMIT;
select
  case when (select with_check from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'avatars_insert_owner_only')
            = $q$(( SELECT enforcement_gate('storage.avatars_insert'::text) AS enforcement_gate) AND ((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))))$q$
        and (select qual from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'avatars_delete_owner_only')
            = $q$((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))$q$
       then 'rolled back' else 'NOT ROLLED BACK' end as result,
  coalesce((select convalidated from pg_constraint
             where conname = 'account_directory_avatar_key_own_folder'
               and conrelid = 'public.account_directory'::regclass), false) as ownership_constraint_still_validated;
