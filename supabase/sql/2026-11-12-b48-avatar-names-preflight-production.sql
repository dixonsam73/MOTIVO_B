-- B-48 preflight. READ ONLY: one SELECT, no transaction, changes nothing.
-- Run: supabase db query --linked -f supabase/sql/2026-11-12-b48-avatar-names-preflight-production.sql
-- Always returns one row. Go on to the apply only if:
--   nonconforming = 0 and nonconforming_user_ids is null,
--   insert_policy_as_expected, delete_policy_as_expected, update_policy_as_expected are all true,
--   constraint_exists is false.
-- If nonconforming is not 0: STOP and report the listed user_ids. The apply
-- would refuse in any case; no reference is to be changed or deleted to make
-- it pass without a decision.
select
  (select count(*) from public.account_directory) as directory_rows,
  (select count(*) from public.account_directory where avatar_key is null) as no_reference,
  (select count(*) from public.account_directory
    where avatar_key = 'users/' || user_id::text || '/avatar.jpg') as old_name_in_own_folder,
  (select count(*) from public.account_directory
    where avatar_key ~ ('^users/' || user_id::text || '/avatar-[0-9a-f]{32}\.jpg$')) as new_name_in_own_folder,
  (select count(*) from public.account_directory
    where (avatar_key is null
           or avatar_key = 'users/' || user_id::text || '/avatar.jpg'
           or avatar_key ~ ('^users/' || user_id::text || '/avatar-[0-9a-f]{32}\.jpg$')) is not true) as nonconforming,
  (select string_agg(user_id::text, ', ' order by user_id::text) from public.account_directory
    where (avatar_key is null
           or avatar_key = 'users/' || user_id::text || '/avatar.jpg'
           or avatar_key ~ ('^users/' || user_id::text || '/avatar-[0-9a-f]{32}\.jpg$')) is not true) as nonconforming_user_ids,
  (select with_check from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'avatars_insert_owner_only' and cmd = 'INSERT' and roles = '{authenticated}')
    is not distinct from $q$(( SELECT enforcement_gate('storage.avatars_insert'::text) AS enforcement_gate) AND ((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))))$q$ as insert_policy_as_expected,
  (select qual from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'avatars_delete_owner_only' and cmd = 'DELETE' and roles = '{authenticated}')
    is not distinct from $q$((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))$q$ as delete_policy_as_expected,
  (select with_check from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'avatars_update_owner_only' and cmd = 'UPDATE' and roles = '{authenticated}')
    is not distinct from $q$((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))$q$ as update_policy_as_expected,
  exists (select 1 from pg_constraint where conname = 'account_directory_avatar_key_own_folder') as constraint_exists,
  (select count(*) from storage.objects where bucket_id = 'avatars') as avatar_objects,
  (select count(*) from storage.objects where bucket_id = 'avatars'
      and name !~ '^users/[0-9a-f-]{36}/avatar(-[0-9a-f]{32})?\.jpg$') as objects_with_any_other_name;
