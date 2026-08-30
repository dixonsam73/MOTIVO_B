-- U6a — SHADOW ENFORCEMENT. OBSERVATIONAL ONLY.
--
-- This migration adds NO enforcement. public.shadow_observe() returns true on
-- every path, so every policy below evaluates exactly as it did before and no
-- request's outcome changes. That is a property of the code, not a promise, and
-- the acceptance suite proves it by comparing row counts with the observer
-- attached and detached (G4-S2).
--
-- B-33: EXECUTE **is** checked against the invoking role for a function
-- referenced from an RLS policy qual -- measured, not assumed, in
-- supabase/tests/u6a/execute-in-policy.sh. So the predicate reachable from RLS
-- is a ZERO-ARGUMENT SECURITY DEFINER wrapper granted to `authenticated`.
-- connected_member(uuid) and membership_state(uuid) stay ungranted, because
-- granting the uuid-taking form makes it a membership oracle over every user.
--
-- EVERY POLICY REFERENCE IS `(select public.shadow_observe(...))`, NEVER BARE.
-- A bare call lands in the per-row Filter: 278ms against 3.9ms at 5000 rows.
-- Both forms are functionally correct, so review cannot catch it -- G4-S3 does.
--
-- The three objects are named OUTSIDE the membership% namespace deliberately.
-- membership% means authoritative lifecycle state whose functions are not
-- executable by `authenticated`; shadow_observe IS. Telemetry is not membership
-- state. Where a name would have kept an assertion green dishonestly, the
-- assertion is re-pointed instead -- see U4 A57b and U5 A67c.

-- ========================================================== 1. the aggregate
--
-- BOUNDED BY CONSTRUCTION, in the shape of membership_notification_reject_stat
-- and membership_binding_conflict. One row per identity x surface x clause x
-- hour, with a counter -- never an append-only log. B-29 was filed for exactly
-- the unbounded-durable-write shape, and a shadow window that appends a row per
-- read query is that shape with a friendlier name.
create table public.shadow_enforcement_stat (
  user_id        uuid        not null references auth.users(id) on delete cascade,
  surface        text        not null,
  decided_clause text        not null,
  bucket_hour    timestamptz not null,
  would_deny     boolean     not null,
  observations   bigint      not null default 1,
  first_seen     timestamptz not null default now(),
  last_seen      timestamptz not null default now(),
  primary key (user_id, surface, decided_clause, bucket_hour),
  constraint shadow_stat_bucket_aligned
    check (bucket_hour = date_trunc('hour', bucket_hour)),
  constraint shadow_stat_clause_check
    check (decided_clause in ('entitled','expired','sandbox_only','grandfathered','unknown')),
  constraint shadow_stat_observations_positive check (observations > 0),
  constraint shadow_stat_surface_bounded check (length(surface) between 1 and 64)
);

comment on table public.shadow_enforcement_stat is
  'U6a shadow window. Observational only -- nothing reads this to decide anything. Bounded aggregate, not a log.';

-- Same posture as every membership table: no client role holds anything.
revoke all on public.shadow_enforcement_stat from public, anon, authenticated, service_role;
alter table public.shadow_enforcement_stat enable row level security;

-- ================================================ 2. the viewer predicate
--
-- ZERO ARGUMENT, so there is nothing to aim: the oracle is structurally
-- unbuildable rather than merely discouraged.
create function public.connected_member_self() returns boolean
  language sql stable security definer set search_path = ''
as $$ select public.connected_member((select auth.uid())) $$;

comment on function public.connected_member_self() is
  'Zero-argument entitlement predicate for the CALLER only. B-33: a policy qual cannot reference the ungranted uuid-taking form.';

revoke execute on function public.connected_member_self() from public, anon, service_role;
grant  execute on function public.connected_member_self() to authenticated;

-- ==================================================== 3. the shadow observer
--
-- RETURNS TRUE ON EVERY PATH -- U6a is non-binding by construction.
-- FAIL-OPEN -- telemetry that can fail a request is not telemetry. A full disk
-- must never deny a member their feed, so the write is wrapped and its failure
-- is swallowed deliberately.
create function public.shadow_observe(p_surface text) returns boolean
  language plpgsql volatile security definer set search_path = ''
as $$
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
$$;

comment on function public.shadow_observe(text) is
  'U6a shadow observer. ALWAYS returns true and never raises. Records what enforcement WOULD have decided. Denies nothing.';

revoke execute on function public.shadow_observe(text) from public, anon, service_role;
grant  execute on function public.shadow_observe(text) to authenticated;

-- ============================================ 4. the three surgical policies
--
-- D-U6-4 and Q1: a branch reducing to `= auth.uid()` on an ownership column
-- stays OPEN, so a lapsed member keeps reading their own retained material.
-- Only the branch reaching ANOTHER member's content is observed.

-- posts.select -- own posts open, the follow-graph branch observed
alter policy posts_select_public_or_owner on public.posts
  using (
    (owner_user_id = auth.uid())
    or ((select public.shadow_observe('posts.select'))
        and (is_public = true)
        and (exists (select 1 from public.follows f
                      where f.follower_user_id = auth.uid()
                        and f.followed_user_id = posts.owner_user_id
                        and f.status = 'approved')))
  );

-- post_comments.select -- Q1: ONLY the author branch stays open
alter policy post_comments_select_visible on public.post_comments
  using (
    (auth.uid() = author_user_id)
    or ((select public.shadow_observe('post_comments.select'))
        and ((auth.uid() = owner_user_id) or (auth.uid() = recipient_user_id)))
  );

-- storage.avatars_select -- own avatar open, the follower branch observed
alter policy avatars_select_owner_or_approved_follower on storage.objects
  using (
    (bucket_id = 'avatars'::text)
    and ((auth.uid() = (split_part(name, '/'::text, 2))::uuid)
      or ((select public.shadow_observe('storage.avatars_select'))
          and exists (select 1 from public.follows f
                       where f.follower_user_id = auth.uid()
                         and f.followed_user_id = (split_part(objects.name, '/'::text, 2))::uuid
                         and f.status = 'approved')))
  );

-- ======================================= 5. the twenty whole-predicate policies
-- account_directory.insert
alter policy account_directory_insert_owner on public.account_directory
  with check ((select public.shadow_observe('account_directory.insert'))
     and ((user_id = auth.uid())));

-- connected_attachments.insert
alter policy connected_attachments_insert_sender on public.connected_attachments
  with check ((select public.shadow_observe('connected_attachments.insert'))
     and (((sender_user_id = auth.uid()) AND (recipient_user_id <> auth.uid()) AND (storage_bucket = 'attachments'::text) AND (storage_path ~ (((('^users/'::text || (auth.uid())::text) || '/connected/'::text) || (asset_id)::text) || '\.[A-Za-z0-9]+$'::text)) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = connected_attachments.recipient_user_id) AND (f.status = 'approved'::text)))))));

-- connected_attachments.select
alter policy connected_attachments_select_recipient on public.connected_attachments
  using ((select public.shadow_observe('connected_attachments.select'))
     and ((recipient_user_id = auth.uid())));

-- connected_attachments.update
alter policy connected_attachments_update_recipient on public.connected_attachments
  using ((select public.shadow_observe('connected_attachments.update'))
     and ((recipient_user_id = auth.uid())))
  with check ((recipient_user_id = auth.uid()));

-- follows.insert
alter policy follows_insert_requester on public.follows
  with check ((select public.shadow_observe('follows.insert'))
     and (((follower_user_id = auth.uid()) AND (status = 'requested'::text) AND follow_requests_open(followed_user_id))));

-- follows.update
alter policy follows_update_approve_by_followed on public.follows
  using ((select public.shadow_observe('follows.update'))
     and (((followed_user_id = auth.uid()) AND (status = 'requested'::text))))
  with check (((followed_user_id = auth.uid()) AND (status = 'approved'::text)));

-- post_comment_views.insert
alter policy pcv_upsert_self on public.post_comment_views
  with check ((select public.shadow_observe('post_comment_views.insert'))
     and ((auth.uid() = viewer_user_id)));

-- post_comment_views.select
alter policy pcv_select_self on public.post_comment_views
  using ((select public.shadow_observe('post_comment_views.select'))
     and ((auth.uid() = viewer_user_id)));

-- post_comment_views.update
alter policy pcv_update_self on public.post_comment_views
  using ((select public.shadow_observe('post_comment_views.update'))
     and ((auth.uid() = viewer_user_id)))
  with check ((auth.uid() = viewer_user_id));

-- post_shares.insert
alter policy post_shares_insert_owner on public.post_shares
  with check ((select public.shadow_observe('post_shares.insert'))
     and (((owner_user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_shares.post_id) AND (p.owner_user_id = auth.uid())))) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = post_shares.recipient_user_id) AND (f.status = 'approved'::text)))))));

-- post_shares.select
alter policy post_shares_select_recipient on public.post_shares
  using ((select public.shadow_observe('post_shares.select'))
     and ((recipient_user_id = auth.uid())));

-- post_shares.update
alter policy post_shares_update_recipient on public.post_shares
  using ((select public.shadow_observe('post_shares.update'))
     and ((recipient_user_id = auth.uid())))
  with check ((recipient_user_id = auth.uid()));

-- posts.insert
alter policy posts_insert_owner on public.posts
  with check ((select public.shadow_observe('posts.insert'))
     and ((owner_user_id = auth.uid())));

-- posts.update
alter policy posts_update_owner on public.posts
  using ((select public.shadow_observe('posts.update'))
     and ((owner_user_id = auth.uid())))
  with check ((owner_user_id = auth.uid()));

-- storage.attachments_insert
alter policy attachments_user_insert_auth on storage.objects
  with check ((select public.shadow_observe('storage.attachments_insert'))
     and (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text)))));

-- storage.attachments_recipient
alter policy connected_attachment_recipient_select on storage.objects
  using ((select public.shadow_observe('storage.attachments_recipient'))
     and (((bucket_id = 'attachments'::text) AND (EXISTS ( SELECT 1
   FROM connected_attachments ca
  WHERE ((ca.storage_bucket = objects.bucket_id) AND (ca.storage_path = objects.name) AND (ca.recipient_user_id = auth.uid()) AND (ca.deleted_at IS NULL)))))));

-- storage.attachments_update
alter policy attachments_user_update_auth on storage.objects
  using ((select public.shadow_observe('storage.attachments_update'))
     and (((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text)))))
  with check (((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text))));

-- storage.attachments_via_post
alter policy attachments_select_via_visible_post on storage.objects
  using ((select public.shadow_observe('storage.attachments_via_post'))
     and (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((lower((storage.foldername(objects.name))[2]) = lower((p.owner_user_id)::text)) AND (EXISTS ( SELECT 1
           FROM jsonb_array_elements(p.attachments) a(value)
          WHERE (((a.value ->> 'bucket'::text) = objects.bucket_id) AND ((a.value ->> 'path'::text) = objects.name))))))))));

-- storage.avatars_insert
alter policy avatars_insert_owner_only on storage.objects
  with check ((select public.shadow_observe('storage.avatars_insert'))
     and (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))));

-- storage.avatars_update
alter policy avatars_update_owner_only on storage.objects
  using ((select public.shadow_observe('storage.avatars_update'))
     and (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))))
  with check (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))));
-- ============================================== 6. the nine RPC bodies
--
-- post_comments has NO INSERT/UPDATE policy: every comment write is
-- SECURITY DEFINER and invisible to policy work. Omitting these would
-- measure two thirds of the surface and report it as the whole.

-- rpc.add_post_comment  (plpgsql: observe as the first statement)
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
$function$;

-- rpc.reply_to_commenter  (plpgsql: observe as the first statement)
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
$function$;

-- rpc.respond_to_commenters  (plpgsql: observe as the first statement)
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
$function$;

-- rpc.get_unread_private_comment_groups  (plpgsql: observe as the first statement)
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
$function$;

-- rpc.follow_requests_open  (sql: observe folded into the predicate, value-preserving)
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
$function$;

-- rpc.has_unread_private_comments  (sql: observe folded into the predicate, value-preserving)
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
$function$;

-- rpc.mark_post_comments_viewed  (sql: observe folded into the predicate, value-preserving)
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
$function$;

-- rpc.get_account_directory_by_user_ids  (sql: observe folded into the predicate, value-preserving)
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
$function$;

-- rpc.search_account_directory  (sql: observe folded into the predicate, value-preserving)
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

$function$;
