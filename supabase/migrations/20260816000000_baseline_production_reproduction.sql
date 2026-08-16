-- Phase 3 U1 / B-23 — baseline migration.
--
-- Reproduces the production backend AS IT EXISTS AT U1 ENTRANCE. This is a
-- REPRODUCTION, not a redesign: no Phase 3 membership object appears here,
-- and nothing in it is applied to production. supabase/schema/ remains the
-- observed-truth authority; this file is the reproducible source measured
-- against it by the ten-file fidelity gate.
--
-- Generated from the committed structural snapshot plus read-only catalog
-- reads (pg_attribute for exact column types, pg_indexes for index DDL),
-- then reviewed. Ordering: tables -> constraints -> indexes -> RLS ->
-- functions -> triggers -> policies -> grants -> storage buckets.

-- ----------------------------------------------------------------- tables
create table if not exists public.account_directory (
  user_id uuid not null,
  account_id text,
  display_name text not null,
  lookup_enabled boolean default false not null,
  location text,
  avatar_key text,
  instruments text[],
  follow_requests_enabled boolean default true not null
);

create table if not exists public.connected_attachments (
  id uuid default gen_random_uuid() not null,
  asset_id uuid not null,
  sender_user_id uuid not null,
  recipient_user_id uuid not null,
  storage_bucket text default 'attachments'::text not null,
  storage_path text not null,
  filename text not null,
  mime_type text default 'application/pdf'::text not null,
  byte_count bigint not null,
  page_count integer default 1 not null,
  created_at timestamp with time zone default now() not null,
  saved_to_scores_at timestamp with time zone,
  deleted_at timestamp with time zone,
  viewed_at timestamp with time zone,
  attachment_name text
);

create table if not exists public.follows (
  follower_user_id uuid not null,
  followed_user_id uuid not null,
  status text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table if not exists public.post_comment_views (
  post_id uuid not null,
  viewer_user_id uuid not null,
  last_viewed_at timestamp with time zone default now() not null
);

create table if not exists public.post_comments (
  id uuid default gen_random_uuid() not null,
  post_id uuid not null,
  owner_user_id uuid not null,
  author_user_id uuid not null,
  recipient_user_id uuid not null,
  body text not null,
  created_at timestamp with time zone default now() not null
);

create table if not exists public.post_shares (
  id uuid default gen_random_uuid() not null,
  post_id uuid not null,
  owner_user_id uuid not null,
  recipient_user_id uuid not null,
  created_at timestamp with time zone default now() not null,
  viewed_at timestamp with time zone
);

create table if not exists public.posts (
  id uuid default gen_random_uuid() not null,
  session_id uuid,
  owner_user_id uuid not null,
  is_public boolean default false not null,
  session_timestamp timestamp with time zone,
  title text,
  duration_seconds integer,
  activity_type text,
  activity_detail text,
  instrument_label text,
  mood smallint,
  effort smallint,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now(),
  attachments jsonb default '[]'::jsonb not null,
  notes text
);

-- ------------------------------------------------------------ constraints
alter table public.account_directory add constraint account_directory_pkey PRIMARY KEY (user_id);
alter table public.connected_attachments add constraint connected_attachments_pkey PRIMARY KEY (id);
alter table public.follows add constraint follows_pk PRIMARY KEY (follower_user_id, followed_user_id);
alter table public.post_comment_views add constraint post_comment_views_pkey PRIMARY KEY (post_id, viewer_user_id);
alter table public.post_comments add constraint post_comments_pkey PRIMARY KEY (id);
alter table public.post_shares add constraint post_shares_pkey PRIMARY KEY (id);
alter table public.posts add constraint posts_pkey PRIMARY KEY (id);
alter table public.account_directory add constraint account_directory_account_id_key UNIQUE (account_id);
alter table public.connected_attachments add constraint connected_attachments_asset_recipient_unique UNIQUE (asset_id, recipient_user_id);
alter table public.post_shares add constraint post_shares_unique UNIQUE (post_id, recipient_user_id);
alter table public.account_directory add constraint account_id_format CHECK (((account_id IS NULL) OR (((char_length(account_id) >= 3) AND (char_length(account_id) <= 24)) AND (account_id ~ '^[a-z0-9_]+$'::text))));
alter table public.account_directory add constraint account_id_lowercase CHECK (((account_id IS NULL) OR (account_id = lower(account_id))));
alter table public.connected_attachments add constraint connected_attachments_nonnegative_page_count CHECK ((page_count >= 0));
alter table public.connected_attachments add constraint connected_attachments_nonnegative_size CHECK ((byte_count >= 0));
alter table public.connected_attachments add constraint connected_attachments_not_self CHECK ((sender_user_id <> recipient_user_id));
alter table public.connected_attachments add constraint connected_attachments_sender_storage_path CHECK (((storage_bucket = 'attachments'::text) AND (storage_path ~ (((('^users/'::text || (sender_user_id)::text) || '/connected/'::text) || (asset_id)::text) || '\.[A-Za-z0-9]+$'::text))));
alter table public.connected_attachments add constraint connected_attachments_supported_mime_types CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text, 'image/heic'::text, 'image/heif'::text, 'audio/mpeg'::text, 'audio/mp4'::text, 'audio/x-m4a'::text, 'audio/wav'::text, 'audio/aac'::text, 'video/mp4'::text, 'video/quicktime'::text])));
alter table public.follows add constraint follows_no_self CHECK ((follower_user_id <> followed_user_id));
alter table public.follows add constraint follows_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text])));
alter table public.account_directory add constraint account_directory_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.follows add constraint follows_followed_user_id_fkey FOREIGN KEY (followed_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.follows add constraint follows_follower_user_id_fkey FOREIGN KEY (follower_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.post_comments add constraint post_comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;
alter table public.post_shares add constraint post_shares_post_id_fkey FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE;

-- ---------------------------------------------------------------- indexes
create index if not exists connected_attachments_asset_idx ON public.connected_attachments USING btree (asset_id);
create index if not exists connected_attachments_recipient_active_idx ON public.connected_attachments USING btree (recipient_user_id, created_at DESC) WHERE (deleted_at IS NULL);
create index if not exists post_comments_post_id_author_idx ON public.post_comments USING btree (post_id, author_user_id);
create index if not exists post_comments_post_id_created_at_idx ON public.post_comments USING btree (post_id, created_at);
create index if not exists post_comments_post_id_recipient_idx ON public.post_comments USING btree (post_id, recipient_user_id);
create index if not exists posts_session_id_idx ON public.posts USING btree (session_id);

-- -------------------------------------------------------------------- RLS
alter table public.account_directory enable row level security;
alter table public.connected_attachments enable row level security;
alter table public.follows enable row level security;
alter table public.post_comment_views enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_shares enable row level security;
alter table public.posts enable row level security;

-- ------------------------------------------------------------- functions
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
$function$;

CREATE OR REPLACE FUNCTION public.enforce_connected_attachment_recipient_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
    if new.id is distinct from old.id
       or new.asset_id is distinct from old.asset_id
       or new.sender_user_id is distinct from old.sender_user_id
       or new.recipient_user_id is distinct from old.recipient_user_id
       or new.storage_bucket is distinct from old.storage_bucket
       or new.storage_path is distinct from old.storage_path
       or new.filename is distinct from old.filename
       or new.mime_type is distinct from old.mime_type
       or new.byte_count is distinct from old.byte_count
       or new.page_count is distinct from old.page_count
       or new.created_at is distinct from old.created_at
    then
        raise exception
            'Connected attachment identity and payload metadata are immutable';
    end if;

    if old.saved_to_scores_at is not null
       and new.saved_to_scores_at is distinct from old.saved_to_scores_at
    then
        raise exception
            'saved_to_scores_at cannot be changed once set';
    end if;

    if old.deleted_at is not null
       and new.deleted_at is distinct from old.deleted_at
    then
        raise exception
            'deleted_at cannot be changed once set';
    end if;

    return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.follow_requests_open(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select ad.follow_requests_enabled
     from public.account_directory ad
     where ad.user_id = target_user_id),
    true
  );
$function$;

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
  where auth.uid() is not null
    and ad.user_id = any(user_ids);
$function$;

CREATE OR REPLACE FUNCTION public.get_unread_private_comment_groups(limit_count integer DEFAULT 20)
 RETURNS TABLE(post_id uuid, latest_unread_at timestamp with time zone, unread_rows bigint, latest_author_user_id uuid, latest_body text)
 LANGUAGE plpgsql
 STABLE
AS $function$
begin
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
$function$;

CREATE OR REPLACE FUNCTION public.has_unread_private_comments()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
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
$function$;

CREATE OR REPLACE FUNCTION public.mark_post_comments_viewed(p_post_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into public.post_comment_views (post_id, viewer_user_id, last_viewed_at)
  values (p_post_id, auth.uid(), now())
  on conflict (post_id, viewer_user_id)
  do update set last_viewed_at = now();
$function$;

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
$function$;

CREATE OR REPLACE FUNCTION public.respond_to_commenters(p_post_id uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
begin
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
$function$;

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
      auth.uid() is not null

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

$function$;

CREATE OR REPLACE FUNCTION public.whoami()
 RETURNS uuid
 LANGUAGE sql
AS $function$
  select auth.uid();
$function$;

-- ---------------------------------------------------------------- trigger
-- Only ONE trigger is ours. The other four in the snapshot
-- (enforce_bucket_name_length_trigger, protect_buckets_delete,
-- protect_objects_delete, update_objects_updated_at) are created by the
-- Supabase storage extension and were verified byte-identical on the local
-- stack before this baseline was written. Do not recreate them.
CREATE TRIGGER connected_attachments_recipient_update_guard BEFORE UPDATE ON public.connected_attachments FOR EACH ROW EXECUTE FUNCTION enforce_connected_attachment_recipient_update();

-- ------------------------------------------------------------- policies
create policy "account_directory_insert_owner" on public.account_directory as permissive for insert to authenticated
  with check ((user_id = auth.uid()));

create policy "account_directory_select_owner" on public.account_directory as permissive for select to authenticated
  using ((user_id = auth.uid()));

create policy "account_directory_update_owner" on public.account_directory as permissive for update to authenticated
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));

create policy "connected_attachments_insert_sender" on public.connected_attachments as permissive for insert to authenticated
  with check (((sender_user_id = auth.uid()) AND (recipient_user_id <> auth.uid()) AND (storage_bucket = 'attachments'::text) AND (storage_path ~ (((('^users/'::text || (auth.uid())::text) || '/connected/'::text) || (asset_id)::text) || '\.[A-Za-z0-9]+$'::text)) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = connected_attachments.recipient_user_id) AND (f.status = 'approved'::text))))));

create policy "connected_attachments_select_recipient" on public.connected_attachments as permissive for select to authenticated
  using ((recipient_user_id = auth.uid()));

create policy "connected_attachments_update_recipient" on public.connected_attachments as permissive for update to authenticated
  using ((recipient_user_id = auth.uid()))
  with check ((recipient_user_id = auth.uid()));

create policy "follows_delete_involved" on public.follows as permissive for delete to authenticated
  using (((follower_user_id = auth.uid()) OR (followed_user_id = auth.uid())));

create policy "follows_insert_requester" on public.follows as permissive for insert to authenticated
  with check (((follower_user_id = auth.uid()) AND (status = 'requested'::text) AND follow_requests_open(followed_user_id)));

create policy "follows_select_involved" on public.follows as permissive for select to authenticated
  using (((follower_user_id = auth.uid()) OR (followed_user_id = auth.uid())));

create policy "follows_update_approve_by_followed" on public.follows as permissive for update to authenticated
  using (((followed_user_id = auth.uid()) AND (status = 'requested'::text)))
  with check (((followed_user_id = auth.uid()) AND (status = 'approved'::text)));

create policy "pcv_select_self" on public.post_comment_views as permissive for select to authenticated
  using ((auth.uid() = viewer_user_id));

create policy "pcv_update_self" on public.post_comment_views as permissive for update to authenticated
  using ((auth.uid() = viewer_user_id))
  with check ((auth.uid() = viewer_user_id));

create policy "pcv_upsert_self" on public.post_comment_views as permissive for insert to authenticated
  with check ((auth.uid() = viewer_user_id));

create policy "post_comments_delete_owner_or_author" on public.post_comments as permissive for delete to authenticated
  using (((auth.uid() = owner_user_id) OR (auth.uid() = author_user_id)));

create policy "post_comments_select_visible" on public.post_comments as permissive for select to authenticated
  using (((auth.uid() = owner_user_id) OR (auth.uid() = author_user_id) OR (auth.uid() = recipient_user_id)));

create policy "post_shares_delete_owner" on public.post_shares as permissive for delete to authenticated
  using ((owner_user_id = auth.uid()));

create policy "post_shares_insert_owner" on public.post_shares as permissive for insert to authenticated
  with check (((owner_user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_shares.post_id) AND (p.owner_user_id = auth.uid())))) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = post_shares.recipient_user_id) AND (f.status = 'approved'::text))))));

create policy "post_shares_select_recipient" on public.post_shares as permissive for select to authenticated
  using ((recipient_user_id = auth.uid()));

create policy "post_shares_update_recipient" on public.post_shares as permissive for update to authenticated
  using ((recipient_user_id = auth.uid()))
  with check ((recipient_user_id = auth.uid()));

create policy "posts_delete_owner" on public.posts as permissive for delete to authenticated
  using ((owner_user_id = auth.uid()));

create policy "posts_insert_owner" on public.posts as permissive for insert to authenticated
  with check ((owner_user_id = auth.uid()));

create policy "posts_select_public_or_owner" on public.posts as permissive for select to authenticated
  using (((owner_user_id = auth.uid()) OR ((is_public = true) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.follower_user_id = auth.uid()) AND (f.followed_user_id = posts.owner_user_id) AND (f.status = 'approved'::text)))))));

create policy "posts_update_owner" on public.posts as permissive for update to authenticated
  using ((owner_user_id = auth.uid()))
  with check ((owner_user_id = auth.uid()));

create policy "attachments_select_via_visible_post" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((lower((storage.foldername(objects.name))[2]) = lower((p.owner_user_id)::text)) AND (EXISTS ( SELECT 1
           FROM jsonb_array_elements(p.attachments) a(value)
          WHERE (((a.value ->> 'bucket'::text) = objects.bucket_id) AND ((a.value ->> 'path'::text) = objects.name)))))))));

create policy "attachments_user_delete_auth" on storage.objects as permissive for delete to authenticated
  using (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text))));

create policy "attachments_user_insert_auth" on storage.objects as permissive for insert to authenticated
  with check (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text))));

create policy "attachments_user_select_auth" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text))));

create policy "attachments_user_update_auth" on storage.objects as permissive for update to authenticated
  using (((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text))))
  with check (((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text))));

create policy "avatars_delete_owner_only" on storage.objects as permissive for delete to authenticated
  using (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))));

create policy "avatars_insert_owner_only" on storage.objects as permissive for insert to authenticated
  with check (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))));

create policy "avatars_select_owner_or_approved_follower" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'avatars'::text) AND ((auth.uid() = (split_part(name, '/'::text, 2))::uuid) OR (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.follower_user_id = auth.uid()) AND (f.followed_user_id = (split_part(objects.name, '/'::text, 2))::uuid) AND (f.status = 'approved'::text)))))));

create policy "avatars_update_owner_only" on storage.objects as permissive for update to authenticated
  using (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))))
  with check (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))));

create policy "connected_attachment_recipient_select" on storage.objects as permissive for select to authenticated
  using (((bucket_id = 'attachments'::text) AND (EXISTS ( SELECT 1
   FROM connected_attachments ca
  WHERE ((ca.storage_bucket = objects.bucket_id) AND (ca.storage_path = objects.name) AND (ca.recipient_user_id = auth.uid()) AND (ca.deleted_at IS NULL))))));

-- ---------------------------------------------------------------- grants
-- Normalise first: the local stack grants broadly by default via ALTER
-- DEFAULT PRIVILEGES, so an additive-only approach would not reproduce
-- B-14, whose whole substance is a privilege that is ABSENT.
revoke all on public.account_directory from anon, authenticated, service_role;
revoke all on public.connected_attachments from anon, authenticated, service_role;
revoke all on public.follows from anon, authenticated, service_role;
revoke all on public.post_comment_views from anon, authenticated, service_role;
revoke all on public.post_comments from anon, authenticated, service_role;
revoke all on public.post_shares from anon, authenticated, service_role;
revoke all on public.posts from anon, authenticated, service_role;

grant delete on public.account_directory to authenticated;
grant insert on public.account_directory to authenticated;
grant references on public.account_directory to authenticated;
grant select on public.account_directory to authenticated;
grant trigger on public.account_directory to authenticated;
grant truncate on public.account_directory to authenticated;
grant update on public.account_directory to authenticated;
grant delete on public.account_directory to service_role;
grant insert on public.account_directory to service_role;
grant references on public.account_directory to service_role;
grant select on public.account_directory to service_role;
grant trigger on public.account_directory to service_role;
grant truncate on public.account_directory to service_role;
grant update on public.account_directory to service_role;
grant delete on public.connected_attachments to anon;
grant insert on public.connected_attachments to anon;
grant references on public.connected_attachments to anon;
grant select on public.connected_attachments to anon;
grant trigger on public.connected_attachments to anon;
grant truncate on public.connected_attachments to anon;
grant update on public.connected_attachments to anon;
grant delete on public.connected_attachments to authenticated;
grant insert on public.connected_attachments to authenticated;
grant references on public.connected_attachments to authenticated;
grant select on public.connected_attachments to authenticated;
grant trigger on public.connected_attachments to authenticated;
grant truncate on public.connected_attachments to authenticated;
grant update on public.connected_attachments to authenticated;
grant delete on public.connected_attachments to service_role;
grant insert on public.connected_attachments to service_role;
grant references on public.connected_attachments to service_role;
grant select on public.connected_attachments to service_role;
grant trigger on public.connected_attachments to service_role;
grant truncate on public.connected_attachments to service_role;
grant update on public.connected_attachments to service_role;
grant delete on public.follows to authenticated;
grant insert on public.follows to authenticated;
grant references on public.follows to authenticated;
grant select on public.follows to authenticated;
grant trigger on public.follows to authenticated;
grant truncate on public.follows to authenticated;
grant delete on public.follows to service_role;
grant insert on public.follows to service_role;
grant references on public.follows to service_role;
grant select on public.follows to service_role;
grant trigger on public.follows to service_role;
grant truncate on public.follows to service_role;
grant update on public.follows to service_role;
grant delete on public.post_comment_views to authenticated;
grant insert on public.post_comment_views to authenticated;
grant references on public.post_comment_views to authenticated;
grant select on public.post_comment_views to authenticated;
grant trigger on public.post_comment_views to authenticated;
grant truncate on public.post_comment_views to authenticated;
grant update on public.post_comment_views to authenticated;
grant delete on public.post_comment_views to service_role;
grant insert on public.post_comment_views to service_role;
grant references on public.post_comment_views to service_role;
grant select on public.post_comment_views to service_role;
grant trigger on public.post_comment_views to service_role;
grant truncate on public.post_comment_views to service_role;
grant update on public.post_comment_views to service_role;
grant delete on public.post_comments to authenticated;
grant references on public.post_comments to authenticated;
grant select on public.post_comments to authenticated;
grant trigger on public.post_comments to authenticated;
grant truncate on public.post_comments to authenticated;
grant delete on public.post_comments to service_role;
grant insert on public.post_comments to service_role;
grant references on public.post_comments to service_role;
grant select on public.post_comments to service_role;
grant trigger on public.post_comments to service_role;
grant truncate on public.post_comments to service_role;
grant update on public.post_comments to service_role;
grant delete on public.post_shares to authenticated;
grant insert on public.post_shares to authenticated;
grant references on public.post_shares to authenticated;
grant select on public.post_shares to authenticated;
grant trigger on public.post_shares to authenticated;
grant truncate on public.post_shares to authenticated;
grant update on public.post_shares to authenticated;
grant delete on public.post_shares to service_role;
grant insert on public.post_shares to service_role;
grant references on public.post_shares to service_role;
grant select on public.post_shares to service_role;
grant trigger on public.post_shares to service_role;
grant truncate on public.post_shares to service_role;
grant update on public.post_shares to service_role;
grant delete on public.posts to authenticated;
grant insert on public.posts to authenticated;
grant references on public.posts to authenticated;
grant select on public.posts to authenticated;
grant trigger on public.posts to authenticated;
grant truncate on public.posts to authenticated;
grant update on public.posts to authenticated;
grant delete on public.posts to service_role;
grant insert on public.posts to service_role;
grant references on public.posts to service_role;
grant select on public.posts to service_role;
grant trigger on public.posts to service_role;
grant truncate on public.posts to service_role;
grant update on public.posts to service_role;

-- Column-level grants: present in column_privileges but NOT at table level.
-- This is where B-14 lives — authenticated may UPDATE follows.status and
-- .updated_at, and neither participant id.
grant update (status, updated_at) on public.follows to authenticated;

-- Function EXECUTE grants.
--
-- REVOKE FROM PUBLIC FIRST, and this is load-bearing rather than tidy.
-- has_function_privilege() answers "can this role execute?", which is true
-- when the privilege comes from PUBLIC as well as when it is held directly.
-- Postgres grants EXECUTE to PUBLIC by default, so revoking only from anon,
-- authenticated and service_role would leave every function executable and
-- would silently fail to reproduce B-5's directory hardening.
revoke execute on function public.follow_requests_open(target_user_id uuid) from public;
revoke execute on function public.get_account_directory_by_user_ids(user_ids uuid[]) from public;
revoke execute on function public.get_unread_private_comment_groups(limit_count integer) from public;
revoke execute on function public.search_account_directory(q text) from public;

grant execute on function public.add_post_comment(p_post_id uuid, p_body text) to anon;
grant execute on function public.add_post_comment(p_post_id uuid, p_body text) to authenticated;
grant execute on function public.add_post_comment(p_post_id uuid, p_body text) to service_role;
grant execute on function public.enforce_connected_attachment_recipient_update() to anon;
grant execute on function public.enforce_connected_attachment_recipient_update() to authenticated;
grant execute on function public.enforce_connected_attachment_recipient_update() to service_role;
revoke execute on function public.follow_requests_open(target_user_id uuid) from anon;
grant execute on function public.follow_requests_open(target_user_id uuid) to authenticated;
grant execute on function public.follow_requests_open(target_user_id uuid) to service_role;
revoke execute on function public.get_account_directory_by_user_ids(user_ids uuid[]) from anon;
grant execute on function public.get_account_directory_by_user_ids(user_ids uuid[]) to authenticated;
revoke execute on function public.get_account_directory_by_user_ids(user_ids uuid[]) from service_role;
grant execute on function public.get_unread_private_comment_groups(limit_count integer) to anon;
grant execute on function public.get_unread_private_comment_groups(limit_count integer) to authenticated;
grant execute on function public.get_unread_private_comment_groups(limit_count integer) to service_role;
grant execute on function public.has_unread_private_comments() to anon;
grant execute on function public.has_unread_private_comments() to authenticated;
grant execute on function public.has_unread_private_comments() to service_role;
grant execute on function public.mark_post_comments_viewed(p_post_id uuid) to anon;
grant execute on function public.mark_post_comments_viewed(p_post_id uuid) to authenticated;
grant execute on function public.mark_post_comments_viewed(p_post_id uuid) to service_role;
grant execute on function public.reply_to_commenter(p_post_id uuid, p_recipient_user_id uuid, p_body text) to anon;
grant execute on function public.reply_to_commenter(p_post_id uuid, p_recipient_user_id uuid, p_body text) to authenticated;
grant execute on function public.reply_to_commenter(p_post_id uuid, p_recipient_user_id uuid, p_body text) to service_role;
grant execute on function public.respond_to_commenters(p_post_id uuid, p_body text) to anon;
grant execute on function public.respond_to_commenters(p_post_id uuid, p_body text) to authenticated;
grant execute on function public.respond_to_commenters(p_post_id uuid, p_body text) to service_role;
revoke execute on function public.search_account_directory(q text) from anon;
grant execute on function public.search_account_directory(q text) to authenticated;
revoke execute on function public.search_account_directory(q text) from service_role;
grant execute on function public.whoami() to anon;
grant execute on function public.whoami() to authenticated;
grant execute on function public.whoami() to service_role;

-- -------------------------------------------------------- storage buckets
-- Bucket definitions are configuration, not user content. No storage OBJECT
-- and no user row is reproduced here or anywhere in this baseline.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 157286400, array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/heif', 'video/mp4', 'video/quicktime', 'audio/m4a', 'audio/mp4', 'audio/x-m4a', 'audio/mpeg', 'audio/wav', 'audio/aac'])
on conflict (id) do update set name = excluded.name, public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/jpeg'])
on conflict (id) do update set name = excluded.name, public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
