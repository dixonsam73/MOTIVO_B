-- U6b ROLLBACK NO-OP VERIFICATION — RUN AGAINST PRODUCTION IMMEDIATELY BEFORE
-- APPLYING U6b-1.
--
-- The body is byte-identical to 2026-09-01-u6b-rollback-baseline-production.sql;
-- both are emitted by one generator from one production capture.
--
-- IT PROVES THREE THINGS. (1) The rollback file still matches production, so
-- drift between capture and deploy STOPS the run. (2) Applying it is a no-op.
-- (3) THE SESSION CAN ACTUALLY ALTER ALL 33 POLICIES, including the ten on
-- storage.objects owned by supabase_storage_admin -- the privilege U6b-1 needs,
-- exercised before it needs it, on a statement whose failure costs nothing.
--
-- EXPECTED: one NOTICE and nothing else. Any EXCEPTION is a STOP.

begin;

create temp table _u6b_fp on commit drop as
select (select md5(string_agg(schemaname||'|'||tablename||'|'||policyname||'|'||cmd||'|'||coalesce(qual,'')||'|'||coalesce(with_check,''), E'\n' order by schemaname, tablename, policyname)) from pg_policies where schemaname in ('public','storage')) as pol, (select md5(string_agg(pg_get_functiondef(p.oid), E'\n' order by p.proname)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('add_post_comment','follow_requests_open','get_account_directory_by_user_ids','get_unread_private_comment_groups','has_unread_private_comments','mark_post_comments_viewed','reply_to_commenter','respond_to_commenters','search_account_directory','shadow_observe')) as fn;

do $pre$
declare p text; f text;
begin
  select pol, fn into p, f from _u6b_fp;
  if p <> 'bad893a9528b5b57bc5e73efd905a6ab' then
    raise exception 'ABORT: policy fingerprint is %, expected bad893a9528b5b57bc5e73efd905a6ab. Production has drifted since capture -- regenerate, do not proceed.', p;
  end if;
  if f <> 'bc08dc4fcd953ce9d063b3801d65dccf' then
    raise exception 'ABORT: function fingerprint is %, expected bc08dc4fcd953ce9d063b3801d65dccf. Production has drifted since capture -- regenerate, do not proceed.', f;
  end if;
end
$pre$;

-- =========================================================== FUNCTIONS

CREATE OR REPLACE FUNCTION public.shadow_observe(p_surface text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid    uuid;
  v_clause text;
  v_deny   boolean;
begin
  begin
    v_uid := (select auth.uid());
    if v_uid is null then
      return true;                      -- unauthenticated: nothing to attribute
    end if;
    v_clause := public.membership_state(v_uid);
    v_deny   := not coalesce(public.connected_member_self(), false);

    insert into public.shadow_enforcement_stat as s
      (user_id, surface, decided_clause, bucket_hour, would_deny)
    values (v_uid, p_surface, v_clause, date_trunc('hour', now()), v_deny)
    on conflict (user_id, surface, decided_clause, bucket_hour) do update
      set observations = s.observations + 1,
          last_seen    = now(),
          would_deny   = excluded.would_deny;
  exception when others then
    null;                               -- FAIL OPEN. Deliberate. See above.
  end;
  return true;                          -- the ONLY return value this can have
end
$function$
;

-- GRANTS MUST BE RESTORED EXPLICITLY, AND A REHEARSAL IS THE ONLY REASON THIS IS
-- HERE. `CREATE OR REPLACE FUNCTION` PRESERVES the privileges of a function that
-- already exists -- which is why the nine RPCs below need nothing -- but
-- shadow_observe is DROPPED by U6b, so recreating it produces a NEW function with
-- DEFAULT privileges, and the default grants EXECUTE to PUBLIC. Without these two
-- lines a rollback would silently leave it executable by anon and service_role.
-- The B-23 gate caught it as three function_grants differences; nothing else did.
revoke execute on function public.shadow_observe(text) from public, anon, service_role;
grant  execute on function public.shadow_observe(text) to authenticated;


CREATE OR REPLACE FUNCTION public.add_post_comment(p_post_id uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_can_view boolean;
begin
  perform public.shadow_observe('rpc.add_post_comment');
  if p_body is null or btrim(p_body) = '' then
    return;
  end if;

  select owner_user_id into v_owner
  from public.posts
  where id = p_post_id;

  if v_owner is null then
    raise exception 'post not found';
  end if;

  -- canonical can-view-post: owner OR approved follower of owner
  select (
    (v_owner = auth.uid())
    or exists (
      select 1
      from public.follows f
      where (f.follower_user_id = auth.uid())
        and (f.followed_user_id = v_owner)
        and (f.status = 'approved'::text)
    )
  ) into v_can_view;

  if not v_can_view then
    raise exception 'not permitted';
  end if;

  -- non-owner only
  if auth.uid() = v_owner then
    raise exception 'owner must reply via reply_to_commenter/respond_to_commenters';
  end if;

  insert into public.post_comments (post_id, owner_user_id, author_user_id, recipient_user_id, body)
  values (p_post_id, v_owner, auth.uid(), v_owner, p_body);
end;
$function$
;


CREATE OR REPLACE FUNCTION public.follow_requests_open(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (select public.shadow_observe('rpc.follow_requests_open')) and coalesce(
    (select ad.follow_requests_enabled
     from public.account_directory ad
     where ad.user_id = target_user_id),
    true
  );
$function$
;


CREATE OR REPLACE FUNCTION public.get_account_directory_by_user_ids(user_ids uuid[])
 RETURNS TABLE(user_id uuid, account_id text, display_name text, location text, avatar_key text, instruments text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    ad.user_id,
    ad.account_id,
    ad.display_name,
    ad.location,
    ad.avatar_key,
    ad.instruments
  from public.account_directory ad
  where (select public.shadow_observe('rpc.get_account_directory_by_user_ids'))
    and auth.uid() is not null
    and ad.user_id = any(user_ids);
$function$
;


CREATE OR REPLACE FUNCTION public.get_unread_private_comment_groups(limit_count integer DEFAULT 20)
 RETURNS TABLE(post_id uuid, latest_unread_at timestamp with time zone, unread_rows bigint, latest_author_user_id uuid, latest_body text)
 LANGUAGE plpgsql
 STABLE
AS $function$
begin
  perform public.shadow_observe('rpc.get_unread_private_comment_groups');
  if auth.uid() is null then
    return;
  end if;

  return query
  with unread as (
    select
      c.post_id,
      c.created_at,
      c.author_user_id,
      c.body
    from public.post_comments c
    left join public.post_comment_views v
      on v.post_id = c.post_id
     and v.viewer_user_id = auth.uid()
    where
      -- Viewer-centric: unread addressed to the viewer (owner or commenter)
      c.recipient_user_id = auth.uid()
      -- Don’t show my own outbound comments as unread items
      and c.author_user_id <> auth.uid()
      and c.created_at > coalesce(v.last_viewed_at, 'epoch'::timestamptz)
  )
  select
    u.post_id,
    max(u.created_at) as latest_unread_at,
    count(*) as unread_rows,
    (array_agg(u.author_user_id order by u.created_at desc))[1] as latest_author_user_id,
    (array_agg(u.body order by u.created_at desc))[1] as latest_body
  from unread u
  group by u.post_id
  order by latest_unread_at desc
  limit limit_count;
end;
$function$
;


CREATE OR REPLACE FUNCTION public.has_unread_private_comments()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (select public.shadow_observe('rpc.has_unread_private_comments')) and exists (
    select 1
    from public.post_comments c
    left join public.post_comment_views v
      on v.post_id = c.post_id
     and v.viewer_user_id = auth.uid()
    where auth.uid() is not null
      -- Viewer-centric: unread addressed to the viewer (owner or commenter)
      and c.recipient_user_id = auth.uid()
      -- Don’t treat my own outbound comments as “unread to me”
      and c.author_user_id <> auth.uid()
      and c.created_at > coalesce(v.last_viewed_at, 'epoch'::timestamptz)
    limit 1
  );
$function$
;


CREATE OR REPLACE FUNCTION public.mark_post_comments_viewed(p_post_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.shadow_observe('rpc.mark_post_comments_viewed');
  insert into public.post_comment_views (post_id, viewer_user_id, last_viewed_at)
  values (p_post_id, auth.uid(), now())
  on conflict (post_id, viewer_user_id)
  do update set last_viewed_at = now();
$function$
;


CREATE OR REPLACE FUNCTION public.reply_to_commenter(p_post_id uuid, p_recipient_user_id uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_ok boolean;
begin
  perform public.shadow_observe('rpc.reply_to_commenter');
  if p_body is null or btrim(p_body) = '' then
    return;
  end if;

  select owner_user_id into v_owner
  from public.posts
  where id = p_post_id;

  if v_owner is null then
    raise exception 'post not found';
  end if;

  if auth.uid() <> v_owner then
    raise exception 'owner only';
  end if;

  select exists (
    select 1
    from public.post_comments c
    where c.post_id = p_post_id
      and c.owner_user_id = v_owner
      and c.author_user_id = p_recipient_user_id
      and c.author_user_id <> v_owner
  ) into v_ok;

  if not v_ok then
    raise exception 'invalid recipient';
  end if;

  insert into public.post_comments (post_id, owner_user_id, author_user_id, recipient_user_id, body)
  values (p_post_id, v_owner, v_owner, p_recipient_user_id, p_body);
end;
$function$
;


CREATE OR REPLACE FUNCTION public.respond_to_commenters(p_post_id uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
begin
  perform public.shadow_observe('rpc.respond_to_commenters');
  if p_body is null or btrim(p_body) = '' then
    return;
  end if;

  select owner_user_id into v_owner
  from public.posts
  where id = p_post_id;

  if v_owner is null then
    raise exception 'post not found';
  end if;

  if auth.uid() <> v_owner then
    raise exception 'owner only';
  end if;

  insert into public.post_comments (post_id, owner_user_id, author_user_id, recipient_user_id, body)
  select
    p_post_id,
    v_owner,
    v_owner,
    c.author_user_id,
    p_body
  from (
    select distinct c.author_user_id
    from public.post_comments c
    where c.post_id = p_post_id
      and c.owner_user_id = v_owner
      and c.author_user_id <> v_owner
  ) c;
end;
$function$
;


CREATE OR REPLACE FUNCTION public.search_account_directory(q text)
 RETURNS TABLE(user_id uuid, account_id text, display_name text, location text, avatar_key text, instruments text[])
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
      ad.instruments
  from public.account_directory ad
  where
      (select public.shadow_observe('rpc.search_account_directory'))
      and auth.uid() is not null

      -- Self-exclusion, not a security control. See the warning above.
      and ad.user_id <> auth.uid()

      -- Prevent browse behaviour. Weak; B-15, Phase 4.
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


-- ============================================================ POLICIES

-- public.account_directory (INSERT)
alter policy account_directory_insert_owner on public.account_directory with check ((( SELECT shadow_observe('account_directory.insert'::text) AS shadow_observe) AND (user_id = auth.uid())));

-- public.account_directory (SELECT)
alter policy account_directory_select_owner on public.account_directory using ((user_id = auth.uid()));

-- public.account_directory (UPDATE)
alter policy account_directory_update_owner on public.account_directory using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

-- public.connected_attachments (INSERT)
alter policy connected_attachments_insert_sender on public.connected_attachments with check ((( SELECT shadow_observe('connected_attachments.insert'::text) AS shadow_observe) AND ((sender_user_id = auth.uid()) AND (recipient_user_id <> auth.uid()) AND (storage_bucket = 'attachments'::text) AND (storage_path ~ (((('^users/'::text || (auth.uid())::text) || '/connected/'::text) || (asset_id)::text) || '\.[A-Za-z0-9]+$'::text)) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = connected_attachments.recipient_user_id) AND (f.status = 'approved'::text)))))));

-- public.connected_attachments (SELECT)
alter policy connected_attachments_select_recipient on public.connected_attachments using ((( SELECT shadow_observe('connected_attachments.select'::text) AS shadow_observe) AND (recipient_user_id = auth.uid())));

-- public.connected_attachments (UPDATE)
alter policy connected_attachments_update_recipient on public.connected_attachments using ((( SELECT shadow_observe('connected_attachments.update'::text) AS shadow_observe) AND (recipient_user_id = auth.uid()))) with check ((recipient_user_id = auth.uid()));

-- public.follows (DELETE)
alter policy follows_delete_involved on public.follows using (((follower_user_id = auth.uid()) OR (followed_user_id = auth.uid())));

-- public.follows (INSERT)
alter policy follows_insert_requester on public.follows with check ((( SELECT shadow_observe('follows.insert'::text) AS shadow_observe) AND ((follower_user_id = auth.uid()) AND (status = 'requested'::text) AND follow_requests_open(followed_user_id))));

-- public.follows (SELECT)
alter policy follows_select_involved on public.follows using (((follower_user_id = auth.uid()) OR (followed_user_id = auth.uid())));

-- public.follows (UPDATE)
alter policy follows_update_approve_by_followed on public.follows using ((( SELECT shadow_observe('follows.update'::text) AS shadow_observe) AND ((followed_user_id = auth.uid()) AND (status = 'requested'::text)))) with check (((followed_user_id = auth.uid()) AND (status = 'approved'::text)));

-- public.post_comment_views (SELECT)
alter policy pcv_select_self on public.post_comment_views using ((( SELECT shadow_observe('post_comment_views.select'::text) AS shadow_observe) AND (auth.uid() = viewer_user_id)));

-- public.post_comment_views (UPDATE)
alter policy pcv_update_self on public.post_comment_views using ((( SELECT shadow_observe('post_comment_views.update'::text) AS shadow_observe) AND (auth.uid() = viewer_user_id))) with check ((auth.uid() = viewer_user_id));

-- public.post_comment_views (INSERT)
alter policy pcv_upsert_self on public.post_comment_views with check ((( SELECT shadow_observe('post_comment_views.insert'::text) AS shadow_observe) AND (auth.uid() = viewer_user_id)));

-- public.post_comments (DELETE)
alter policy post_comments_delete_owner_or_author on public.post_comments using (((auth.uid() = owner_user_id) OR (auth.uid() = author_user_id)));

-- public.post_comments (SELECT)
alter policy post_comments_select_visible on public.post_comments using (((auth.uid() = author_user_id) OR (( SELECT shadow_observe('post_comments.select'::text) AS shadow_observe) AND ((auth.uid() = owner_user_id) OR (auth.uid() = recipient_user_id)))));

-- public.post_shares (DELETE)
alter policy post_shares_delete_owner on public.post_shares using ((owner_user_id = auth.uid()));

-- public.post_shares (INSERT)
alter policy post_shares_insert_owner on public.post_shares with check ((( SELECT shadow_observe('post_shares.insert'::text) AS shadow_observe) AND ((owner_user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_shares.post_id) AND (p.owner_user_id = auth.uid())))) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = post_shares.recipient_user_id) AND (f.status = 'approved'::text)))))));

-- public.post_shares (SELECT)
alter policy post_shares_select_recipient on public.post_shares using ((( SELECT shadow_observe('post_shares.select'::text) AS shadow_observe) AND (recipient_user_id = auth.uid())));

-- public.post_shares (UPDATE)
alter policy post_shares_update_recipient on public.post_shares using ((( SELECT shadow_observe('post_shares.update'::text) AS shadow_observe) AND (recipient_user_id = auth.uid()))) with check ((recipient_user_id = auth.uid()));

-- public.posts (DELETE)
alter policy posts_delete_owner on public.posts using ((owner_user_id = auth.uid()));

-- public.posts (INSERT)
alter policy posts_insert_owner on public.posts with check ((( SELECT shadow_observe('posts.insert'::text) AS shadow_observe) AND (owner_user_id = auth.uid())));

-- public.posts (SELECT)
alter policy posts_select_public_or_owner on public.posts using (((owner_user_id = auth.uid()) OR (( SELECT shadow_observe('posts.select'::text) AS shadow_observe) AND (is_public = true) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.follower_user_id = auth.uid()) AND (f.followed_user_id = posts.owner_user_id) AND (f.status = 'approved'::text)))))));

-- public.posts (UPDATE)
alter policy posts_update_owner on public.posts using ((( SELECT shadow_observe('posts.update'::text) AS shadow_observe) AND (owner_user_id = auth.uid()))) with check ((owner_user_id = auth.uid()));

-- storage.objects (SELECT)
alter policy attachments_select_via_visible_post on storage.objects using ((( SELECT shadow_observe('storage.attachments_via_post'::text) AS shadow_observe) AND ((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((lower((storage.foldername(objects.name))[2]) = lower((p.owner_user_id)::text)) AND (EXISTS ( SELECT 1
           FROM jsonb_array_elements(p.attachments) a(value)
          WHERE (((a.value ->> 'bucket'::text) = objects.bucket_id) AND ((a.value ->> 'path'::text) = objects.name))))))))));

-- storage.objects (DELETE)
alter policy attachments_user_delete_auth on storage.objects using (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text))));

-- storage.objects (INSERT)
alter policy attachments_user_insert_auth on storage.objects with check ((( SELECT shadow_observe('storage.attachments_insert'::text) AS shadow_observe) AND ((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text)))));

-- storage.objects (SELECT)
alter policy attachments_user_select_auth on storage.objects using (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text))));

-- storage.objects (UPDATE)
alter policy attachments_user_update_auth on storage.objects using ((( SELECT shadow_observe('storage.attachments_update'::text) AS shadow_observe) AND ((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text))))) with check (((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text))));

-- storage.objects (DELETE)
alter policy avatars_delete_owner_only on storage.objects using (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))));

-- storage.objects (INSERT)
alter policy avatars_insert_owner_only on storage.objects with check ((( SELECT shadow_observe('storage.avatars_insert'::text) AS shadow_observe) AND ((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))));

-- storage.objects (SELECT)
alter policy avatars_select_owner_or_approved_follower on storage.objects using (((bucket_id = 'avatars'::text) AND ((auth.uid() = (split_part(name, '/'::text, 2))::uuid) OR (( SELECT shadow_observe('storage.avatars_select'::text) AS shadow_observe) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.follower_user_id = auth.uid()) AND (f.followed_user_id = (split_part(objects.name, '/'::text, 2))::uuid) AND (f.status = 'approved'::text))))))));

-- storage.objects (UPDATE)
alter policy avatars_update_owner_only on storage.objects using ((( SELECT shadow_observe('storage.avatars_update'::text) AS shadow_observe) AND ((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))))) with check (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))));

-- storage.objects (SELECT)
alter policy connected_attachment_recipient_select on storage.objects using ((( SELECT shadow_observe('storage.attachments_recipient'::text) AS shadow_observe) AND ((bucket_id = 'attachments'::text) AND (EXISTS ( SELECT 1
   FROM connected_attachments ca
  WHERE ((ca.storage_bucket = objects.bucket_id) AND (ca.storage_path = objects.name) AND (ca.recipient_user_id = auth.uid()) AND (ca.deleted_at IS NULL)))))));

do $post$
declare pb text; fb text; pa text; fa text;
begin
  select pol, fn into pb, fb from _u6b_fp;
  select (select md5(string_agg(schemaname||'|'||tablename||'|'||policyname||'|'||cmd||'|'||coalesce(qual,'')||'|'||coalesce(with_check,''), E'\n' order by schemaname, tablename, policyname)) from pg_policies where schemaname in ('public','storage')) into pa;
  select (select md5(string_agg(pg_get_functiondef(p.oid), E'\n' order by p.proname)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('add_post_comment','follow_requests_open','get_account_directory_by_user_ids','get_unread_private_comment_groups','has_unread_private_comments','mark_post_comments_viewed','reply_to_commenter','respond_to_commenters','search_account_directory','shadow_observe'))  into fa;
  if pa <> pb then raise exception 'ABORT: applying the baseline CHANGED the policies (% -> %). Not a no-op.', pb, pa; end if;
  if fa <> fb then raise exception 'ABORT: applying the baseline CHANGED the functions (% -> %). Not a no-op.', fb, fa; end if;
  raise notice 'U6b rollback baseline verified as a byte-identical no-op (policies %, functions %)', pa, fa;
end
$post$;

commit;

-- ADDED 2026-09-01 AFTER P2. This file ended at `commit;`, so the SQL editor
-- reported "Success. No rows returned." -- which is EXACTLY what a submission
-- that ran the wrong text reports. The apply file was built with a returning
-- SELECT for precisely that reason and this one was not; the lesson was applied
-- unevenly. Settling it needed an out-of-band check on pg_policy.xmin.
--
-- Now it returns a row. "No rows returned" is the symptom again, not the pass.
select
  (select md5(string_agg(schemaname||'|'||tablename||'|'||policyname||'|'||cmd||'|'||coalesce(qual,'')||'|'||coalesce(with_check,''), E'\n' order by schemaname, tablename, policyname))
     from pg_policies where schemaname in ('public','storage'))                 as policy_fp,
  (select count(*) from pg_policy where age(xmin) < 200)                        as policies_just_rewritten,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and age(p.xmin) < 200)                            as functions_just_rewritten,
  'ROLLBACK BASELINE VERIFIED AS A NO-OP'                                       as status;
