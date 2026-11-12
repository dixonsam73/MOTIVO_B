-- B-48 and avatar image names per upload (prepared 2026-11-12).
--
-- 1. THE REFERENCE MUST BE IN ITS OWNER'S FOLDER (B-48).
--    account_directory.avatar_key is text its owner can write, and nothing
--    checked its value. delete_account_v1 and membership_cleanup_v1 delete the
--    object it names with the service role, wherever it points. A member could
--    name another member's avatar and have it deleted with their own account
--    or at their own expiry. The CHECK below allows NULL, the old fixed name,
--    or a per-upload name, each only in the folder of the row's own user_id.
--    Existing rows are checked first: if any does not conform this raises,
--    lists them, and changes nothing. It never alters or deletes a reference.
--
-- 2. A NAME PER UPLOAD.
--    The image had one fixed name, users/<uid>/avatar.jpg, so a delete could
--    not say WHICH image it meant, and a delete that arrived late removed a
--    newer photo stored under the same name. New builds store each image as
--    users/<uid>/avatar-<32 lowercase hex>.jpg and delete by that exact name.
--    INSERT and DELETE accept the old name or the new form, in the caller's
--    own folder only. UPDATE is deliberately NOT widened: a per-upload image
--    is written once and can never be overwritten. SELECT is unchanged (it
--    already works on the folder). The membership gate on INSERT is unchanged.
--
-- Old builds write only the old name, so every policy and the CHECK still pass
-- for them. Neither Edge Function changes: both already delete every object in
-- users/<uid>/.

do $b48_pre$
declare
  bad integer;
  ids text;
begin
  if (select with_check from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and policyname = 'avatars_insert_owner_only' and cmd = 'INSERT' and roles = '{authenticated}')
     is distinct from $q$(( SELECT enforcement_gate('storage.avatars_insert'::text) AS enforcement_gate) AND ((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))))$q$ then
    raise exception 'B-48: avatars_insert_owner_only is not in the expected state; nothing was changed';
  end if;
  if (select qual from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and policyname = 'avatars_delete_owner_only' and cmd = 'DELETE' and roles = '{authenticated}')
     is distinct from $q$((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))$q$ then
    raise exception 'B-48: avatars_delete_owner_only is not in the expected state; nothing was changed';
  end if;
  -- Relied on, not changed: an UPDATE can only ever reach the old fixed name.
  if (select with_check from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and policyname = 'avatars_update_owner_only' and cmd = 'UPDATE' and roles = '{authenticated}')
     is distinct from $q$((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))$q$ then
    raise exception 'B-48: avatars_update_owner_only is not in the expected state; nothing was changed';
  end if;
  if exists (select 1 from pg_constraint where conname = 'account_directory_avatar_key_own_folder') then
    raise exception 'B-48: the constraint already exists; nothing was changed';
  end if;
  select count(*), string_agg(user_id::text, ', ' order by user_id::text) into bad, ids
    from public.account_directory
   where (avatar_key is null
          or avatar_key = 'users/' || user_id::text || '/avatar.jpg'
          or avatar_key ~ ('^users/' || user_id::text || '/avatar-[0-9a-f]{32}\.jpg$')) is not true;
  if bad > 0 then
    raise exception 'B-48: % existing avatar reference(s) are not in their owner''s folder. Nothing was changed and no reference was altered. user_id: %', bad, ids;
  end if;
end $b48_pre$;

alter policy avatars_insert_owner_only on storage.objects
  with check ((select public.enforcement_gate('storage.avatars_insert'))
     and bucket_id = 'avatars'
     and (name = 'users/' || (auth.uid())::text || '/avatar.jpg'
          or name ~ ('^users/' || (auth.uid())::text || '/avatar-[0-9a-f]{32}\.jpg$')));

alter policy avatars_delete_owner_only on storage.objects
  using (bucket_id = 'avatars'
     and (name = 'users/' || (auth.uid())::text || '/avatar.jpg'
          or name ~ ('^users/' || (auth.uid())::text || '/avatar-[0-9a-f]{32}\.jpg$')));

alter table public.account_directory
  add constraint account_directory_avatar_key_own_folder
  check (avatar_key is null
         or avatar_key = 'users/' || user_id::text || '/avatar.jpg'
         or avatar_key ~ ('^users/' || user_id::text || '/avatar-[0-9a-f]{32}\.jpg$'))
  not valid;

alter table public.account_directory
  validate constraint account_directory_avatar_key_own_folder;

do $b48_post$
begin
  if not exists (select 1 from pg_constraint where conname = 'account_directory_avatar_key_own_folder'
                   and conrelid = 'public.account_directory'::regclass and convalidated) then
    raise exception 'B-48: the constraint is not present and validated';
  end if;
  -- strpos, not LIKE: the pattern holds a backslash, which LIKE reads as an escape.
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
        and ((policyname = 'avatars_insert_owner_only'
              and strpos(with_check, 'enforcement_gate(''storage.avatars_insert''') > 0
              and strpos(with_check, '/avatar.jpg') > 0
              and strpos(with_check, '/avatar-[0-9a-f]{32}\.jpg$') > 0)
          or (policyname = 'avatars_delete_owner_only'
              and strpos(qual, '/avatar.jpg') > 0
              and strpos(qual, '/avatar-[0-9a-f]{32}\.jpg$') > 0))) <> 2 then
    raise exception 'B-48: the avatar policies were not applied';
  end if;
end $b48_post$;
