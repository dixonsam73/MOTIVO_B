-- U6b — BINDING ENFORCEMENT AND SUBJECT-SIDE VISIBILITY.
--
-- THIS MIGRATION DENIES NOTHING WHEN APPLIED. `enforcement_enabled` defaults to
-- FALSE, so `enforcement_gate` returns true on every path exactly as
-- `shadow_observe` did, and telemetry continues unchanged. Binding is a separate
-- one-row flip. That separation -- deploy the code, then start denying -- is the
-- same shape the grandfather retirement used and it is now proven twice.
--
-- shadow_observe(text) is REPLACED, not kept. A function called `shadow_observe`
-- that denies requests is the C-25 defect: a name describing a caller's motive
-- rather than what the thing does. F6 was filed for exactly that shape.
--
-- THE ENTITLEMENT PREDICATE IS NOT TOUCHED. connected_member(uuid) answers "is
-- this identity entitled" and never lies; enforcement_gate answers "should this
-- request proceed right now". The kill switch lives in the enforcement layer,
-- never the authority layer, so D4's rejection of in-predicate exceptions stands.

-- ===================================================== 1. the kill switch
--
-- SHIPS OFF. And it cannot become a per-identity allowlist: membership_control is
-- a singleton keyed on a boolean, so there is no per-identity row to add, and
-- enforcement_gate takes no uuid, so there is nothing to aim. Structural, not
-- promised -- the same reasoning as B-33's zero-argument wrapper.
alter table public.membership_control
  add column enforcement_enabled boolean not null default false;

comment on column public.membership_control.enforcement_enabled is
  'U6b kill switch. FALSE = enforcement_gate returns true on every path (shadow). TRUE = binding. Global only; there is deliberately no per-identity form.';

-- ============================================ 2. telemetry across the boundary
--
-- `enforced` GOES INTO THE PRIMARY KEY, for the reason GF-5 proved: decided_clause
-- being in the key is what preserved 11 `grandfathered` rows intact beside the new
-- `unknown` ones when the grandfather flag flipped. The same property makes an hour
-- straddling THIS flip produce two rows rather than one mutated row, so the moment
-- enforcement began stays reconstructable forever.
alter table public.shadow_enforcement_stat
  add column enforced boolean not null default false;

alter table public.shadow_enforcement_stat
  drop constraint shadow_enforcement_stat_pkey;
alter table public.shadow_enforcement_stat
  add constraint shadow_enforcement_stat_pkey
  primary key (user_id, surface, decided_clause, bucket_hour, enforced);

comment on table public.shadow_enforcement_stat is
  'U6a shadow window, U6b enforcement telemetry. The name is historical: rows with enforced=false are observations of what enforcement WOULD have decided; enforced=true rows are what it DID decide. Bounded aggregate, never a log.';

-- ================================================== 3. the enforcement flag read
--
-- Zero argument. Discloses one global boolean and nothing about any identity, so
-- it is not an oracle. Granted to `authenticated` because B-33 measured that
-- EXECUTE *is* checked for a function referenced from a policy qual.
create function public.enforcement_active() returns boolean
  language sql stable security definer set search_path = ''
as $$ select k.enforcement_enabled from public.membership_control k where k.id $$;

revoke execute on function public.enforcement_active() from public, anon, service_role;
grant  execute on function public.enforcement_active() to authenticated;

-- ======================================= 4. THE ONE CANONICAL DERIVATION
--
-- GRANTED TO NOBODY. Reachable only from SECURITY DEFINER callers, so no
-- uuid-addressable entitlement oracle is created and D4/B-33 are untouched.
-- Verified by measurement before this was written: a SECURITY DEFINER trigger
-- function fires for `authenticated` WITHOUT that role holding EXECUTE, and the
-- invoker-rights control failed with `permission denied`, so the test was not
-- vacuous.
--
-- greatest() IGNORES NULLs in PostgreSQL -- it is NULL only when every argument
-- is -- so a row with no grace period yields renewal_date unchanged.
--
-- The grace term is conditional because Apple's formula requires billing retry
-- COMBINED WITH an unexpired grace period. RETRY ALONE DOES NOT ENTITLE, and this
-- single line is where the acceptance matrix's rows 3 and 4 diverge.
--
-- environment = 'Production' matches D4 exactly: a Sandbox row confers no
-- visibility, just as it confers no entitlement.
create function public.membership_entitled_until(target_user_id uuid)
  returns timestamptz
  language sql stable security definer set search_path = ''
as $$
  select max(greatest(
           m.renewal_date,
           case when m.is_in_billing_retry then m.grace_period_expires_date end
         ))
    from public.membership m
   where m.user_id = target_user_id
     and m.environment = 'Production';
$$;

revoke execute on function public.membership_entitled_until(uuid)
  from public, anon, authenticated, service_role;

comment on function public.membership_entitled_until(uuid) is
  'The ONE canonical derivation of visibility. Granted to nobody -- SECURITY DEFINER callers only. Storing a TIMESTAMP rather than a boolean is what makes lapse happen by time passing, with no write, no scheduler and no worker.';

-- ===================================================== 5. the enforcement gate
--
-- ORDER IS INVERTED FROM shadow_observe AND THAT IS THE POINT. The decision is
-- taken FIRST and is NOT wrapped; telemetry is written SECOND and IS wrapped,
-- using the already-computed decision -- so a failed write cannot change an
-- outcome, which the old ordering could not guarantee.
--
-- FAIL CLOSED. An error in the decision path propagates and the request fails.
-- There is no fail-open entitlement fallback anywhere. A wrongly denied member
-- complains within minutes and the kill switch is one row; a wrongly granted
-- non-member is silent and indefinite -- which is exactly how B-11 came to exist.
--
-- The null-uid early return is GONE from the decision path and survives only as
-- "skip the write, there is nothing to attribute". An unauthenticated caller now
-- flows into connected_member(null) -> false: fail-closed by construction rather
-- than by a special case.
create function public.enforcement_gate(p_surface text) returns boolean
  language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_enforcing boolean;
  v_allow     boolean;
  v_uid       uuid;
  v_clause    text;
begin
  v_enforcing := public.enforcement_active();
  if v_enforcing then
    v_allow := coalesce(public.connected_member_self(), false);
  else
    v_allow := true;
  end if;

  begin
    v_uid := (select auth.uid());
    if v_uid is not null then
      v_clause := public.membership_state(v_uid);
      insert into public.shadow_enforcement_stat as s
        (user_id, surface, decided_clause, bucket_hour, would_deny, enforced)
      values (v_uid, p_surface, v_clause, date_trunc('hour', now()), not v_allow, v_enforcing)
      on conflict (user_id, surface, decided_clause, bucket_hour, enforced) do update
        set observations = s.observations + 1,
            last_seen    = now(),
            would_deny   = excluded.would_deny;
    end if;
  exception when others then
    null;                      -- telemetry that can fail a request is not telemetry
  end;

  return v_allow;
end
$$;

comment on function public.enforcement_gate(text) is
  'U6b viewer-side gate. Decision first and unwrapped (FAIL CLOSED); telemetry second and wrapped. Takes no uuid, so it cannot be aimed at an identity.';

revoke execute on function public.enforcement_gate(text) from public, anon, service_role;
grant  execute on function public.enforcement_gate(text) to authenticated;

-- ============================== 6. the four denormalised visibility timestamps
--
-- Each column lives on a table the VIEWER can already read for the row in
-- question. That is why a join-based design fails: account_directory's SELECT
-- policy is owner-only, so a policy joining another member's directory row sees
-- nothing. The storage policies need no column of their own because their quals
-- already join `posts` and `follows` -- which is also why nothing is added to
-- storage.objects, a Supabase-managed table.
alter table public.posts             add column owner_entitled_until    timestamptz;
alter table public.post_shares       add column owner_entitled_until    timestamptz;
alter table public.follows           add column followed_entitled_until timestamptz;
alter table public.account_directory add column entitled_until          timestamptz;

-- ==================================================== 7. maintenance, by trigger
--
-- NOT by the two membership write paths. If membership_establish_v1 and U4's
-- canonical writer each maintained these columns the semantics would live in two
-- places and A THIRD WRITER ADDED LATER WOULD SILENTLY SKIP THEM. A trigger cannot
-- be skipped -- the manual membership DELETE run for the G11 gate would have been
-- covered by this automatically.
create function public.tg_set_entitled_until() returns trigger
  language plpgsql security definer set search_path = ''
as $$
begin
  case tg_table_name
    when 'posts'             then new.owner_entitled_until    := public.membership_entitled_until(new.owner_user_id);
    when 'post_shares'       then new.owner_entitled_until    := public.membership_entitled_until(new.owner_user_id);
    when 'follows'           then new.followed_entitled_until := public.membership_entitled_until(new.followed_user_id);
    when 'account_directory' then new.entitled_until          := public.membership_entitled_until(new.user_id);
  end case;
  return new;
end
$$;

-- Trigger functions inherit EXECUTE for PUBLIC by default. Postgres refuses a
-- direct call to a trigger function anyway, so this is hygiene rather than a
-- hole -- but a SECURITY DEFINER function that reads `membership` should not
-- carry a default grant, and U3 set the standard: revoke so the starting point
-- is a property of the migration and not of the deployment.
revoke execute on function public.tg_set_entitled_until() from public, anon, authenticated, service_role;

comment on function public.tg_set_entitled_until() is
  'Server-derives the visibility timestamp on every INSERT and UPDATE. It OVERWRITES unconditionally, so a client-supplied value is always discarded -- asserted behaviourally rather than left to a column privilege.';

create trigger tg_posts_entitled_until  before insert or update on public.posts
  for each row execute function public.tg_set_entitled_until();
create trigger tg_shares_entitled_until before insert or update on public.post_shares
  for each row execute function public.tg_set_entitled_until();
create trigger tg_follows_entitled_until before insert or update on public.follows
  for each row execute function public.tg_set_entitled_until();
create trigger tg_directory_entitled_until before insert or update on public.account_directory
  for each row execute function public.tg_set_entitled_until();

-- Propagation: membership changes for one identity, its denormalised copies follow.
-- Scope is that identity's own rows, never the corpus.
create function public.tg_membership_propagate_entitled_until() returns trigger
  language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid; v_until timestamptz;
begin
  if tg_op = 'DELETE' then v_uid := old.user_id; else v_uid := new.user_id; end if;
  v_until := public.membership_entitled_until(v_uid);

  update public.posts             set owner_entitled_until    = v_until
   where owner_user_id    = v_uid and owner_entitled_until    is distinct from v_until;
  update public.post_shares       set owner_entitled_until    = v_until
   where owner_user_id    = v_uid and owner_entitled_until    is distinct from v_until;
  update public.follows           set followed_entitled_until = v_until
   where followed_user_id = v_uid and followed_entitled_until is distinct from v_until;
  update public.account_directory set entitled_until          = v_until
   where user_id          = v_uid and entitled_until          is distinct from v_until;

  return null;
end
$$;

revoke execute on function public.tg_membership_propagate_entitled_until() from public, anon, authenticated, service_role;

create trigger tg_membership_propagate
  after insert or update or delete on public.membership
  for each row execute function public.tg_membership_propagate_entitled_until();

-- ======================================================== 8. backfill
--
-- PREDICTED RESULT: every row resolves to NULL, because zero Production membership
-- rows have ever existed -- every membership row ever created is Sandbox. So after
-- binding the entire Connected corpus is invisible to everyone, which is CORRECT
-- rather than a regression: nobody is entitled, and viewer-side gating already
-- denies every request. Predicted here so it is not discovered and misread.
update public.posts             set owner_entitled_until    = public.membership_entitled_until(owner_user_id);
update public.post_shares       set owner_entitled_until    = public.membership_entitled_until(owner_user_id);
update public.follows           set followed_entitled_until = public.membership_entitled_until(followed_user_id);
update public.account_directory set entitled_until          = public.membership_entitled_until(user_id);

-- ============================================ 4. the three surgical policies
--
-- D-U6-4 and Q1: a branch reducing to `= auth.uid()` on an ownership column
-- stays OPEN, so a lapsed member keeps reading their own retained material.
-- Only the branch reaching ANOTHER member's content is observed.

-- posts.select -- own posts open, the follow-graph branch observed
alter policy posts_select_public_or_owner on public.posts
  using (
    (owner_user_id = auth.uid())
    or ((select public.enforcement_gate('posts.select'))
        and ((select not public.enforcement_active()) or posts.owner_entitled_until > now())
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
    or ((select public.enforcement_gate('post_comments.select'))
        and ((auth.uid() = owner_user_id) or (auth.uid() = recipient_user_id)))
  );

-- storage.avatars_select -- own avatar open, the follower branch observed
alter policy avatars_select_owner_or_approved_follower on storage.objects
  using (
    (bucket_id = 'avatars'::text)
    and ((auth.uid() = (split_part(name, '/'::text, 2))::uuid)
      or ((select public.enforcement_gate('storage.avatars_select'))
          and exists (select 1 from public.follows f
                       where f.follower_user_id = auth.uid()
                         and f.followed_user_id = (split_part(objects.name, '/'::text, 2))::uuid
                         and f.status = 'approved'
                         and ((select not public.enforcement_active()) or f.followed_entitled_until > now()))))
  );

-- ======================================= 5. the twenty whole-predicate policies
-- account_directory.insert
alter policy account_directory_insert_owner on public.account_directory
  with check ((select public.enforcement_gate('account_directory.insert'))
     and ((user_id = auth.uid())));

-- connected_attachments.insert
alter policy connected_attachments_insert_sender on public.connected_attachments
  with check ((select public.enforcement_gate('connected_attachments.insert'))
     and (((sender_user_id = auth.uid()) AND (recipient_user_id <> auth.uid()) AND (storage_bucket = 'attachments'::text) AND (storage_path ~ (((('^users/'::text || (auth.uid())::text) || '/connected/'::text) || (asset_id)::text) || '\.[A-Za-z0-9]+$'::text)) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = connected_attachments.recipient_user_id) AND (f.status = 'approved'::text)))))));

-- connected_attachments.select
alter policy connected_attachments_select_recipient on public.connected_attachments
  using ((select public.enforcement_gate('connected_attachments.select'))
     and ((recipient_user_id = auth.uid())));

-- connected_attachments.update
alter policy connected_attachments_update_recipient on public.connected_attachments
  using ((select public.enforcement_gate('connected_attachments.update'))
     and ((recipient_user_id = auth.uid())))
  with check ((recipient_user_id = auth.uid()));

-- follows.insert
alter policy follows_insert_requester on public.follows
  with check ((select public.enforcement_gate('follows.insert'))
     and (((follower_user_id = auth.uid()) AND (status = 'requested'::text) AND follow_requests_open(followed_user_id))));

-- follows.update
alter policy follows_update_approve_by_followed on public.follows
  using ((select public.enforcement_gate('follows.update'))
     and (((followed_user_id = auth.uid()) AND (status = 'requested'::text))))
  with check (((followed_user_id = auth.uid()) AND (status = 'approved'::text)));

-- post_comment_views.insert
alter policy pcv_upsert_self on public.post_comment_views
  with check ((select public.enforcement_gate('post_comment_views.insert'))
     and ((auth.uid() = viewer_user_id)));

-- post_comment_views.select
alter policy pcv_select_self on public.post_comment_views
  using ((select public.enforcement_gate('post_comment_views.select'))
     and ((auth.uid() = viewer_user_id)));

-- post_comment_views.update
alter policy pcv_update_self on public.post_comment_views
  using ((select public.enforcement_gate('post_comment_views.update'))
     and ((auth.uid() = viewer_user_id)))
  with check ((auth.uid() = viewer_user_id));

-- post_shares.insert
alter policy post_shares_insert_owner on public.post_shares
  with check ((select public.enforcement_gate('post_shares.insert'))
     and (((owner_user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((p.id = post_shares.post_id) AND (p.owner_user_id = auth.uid())))) AND (EXISTS ( SELECT 1
   FROM follows f
  WHERE ((f.followed_user_id = auth.uid()) AND (f.follower_user_id = post_shares.recipient_user_id) AND (f.status = 'approved'::text)))))));

-- post_shares.select
alter policy post_shares_select_recipient on public.post_shares
  using ((select public.enforcement_gate('post_shares.select'))
     and ((select not public.enforcement_active()) or post_shares.owner_entitled_until > now())
     and ((recipient_user_id = auth.uid())));

-- post_shares.update
alter policy post_shares_update_recipient on public.post_shares
  using ((select public.enforcement_gate('post_shares.update'))
     and ((recipient_user_id = auth.uid())))
  with check ((recipient_user_id = auth.uid()));

-- posts.insert
alter policy posts_insert_owner on public.posts
  with check ((select public.enforcement_gate('posts.insert'))
     and ((owner_user_id = auth.uid())));

-- posts.update
alter policy posts_update_owner on public.posts
  using ((select public.enforcement_gate('posts.update'))
     and ((owner_user_id = auth.uid())))
  with check ((owner_user_id = auth.uid()));

-- storage.attachments_insert
alter policy attachments_user_insert_auth on storage.objects
  with check ((select public.enforcement_gate('storage.attachments_insert'))
     and (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (lower((storage.foldername(name))[2]) = lower((auth.uid())::text)))));

-- storage.attachments_recipient
alter policy connected_attachment_recipient_select on storage.objects
  using ((select public.enforcement_gate('storage.attachments_recipient'))
     and (((bucket_id = 'attachments'::text) AND (EXISTS ( SELECT 1
   FROM connected_attachments ca
  WHERE ((ca.storage_bucket = objects.bucket_id) AND (ca.storage_path = objects.name) AND (ca.recipient_user_id = auth.uid()) AND (ca.deleted_at IS NULL)))))));

-- storage.attachments_update
alter policy attachments_user_update_auth on storage.objects
  using ((select public.enforcement_gate('storage.attachments_update'))
     and (((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text)))))
  with check (((bucket_id = 'attachments'::text) AND (name ~~ (('users/'::text || (auth.uid())::text) || '/%'::text))));

-- storage.attachments_via_post
alter policy attachments_select_via_visible_post on storage.objects
  using ((select public.enforcement_gate('storage.attachments_via_post'))
     and (((bucket_id = 'attachments'::text) AND ((storage.foldername(name))[1] = 'users'::text) AND (EXISTS ( SELECT 1
   FROM posts p
  WHERE ((lower((storage.foldername(objects.name))[2]) = lower((p.owner_user_id)::text)) AND ((select not public.enforcement_active()) or p.owner_entitled_until > now()) AND (EXISTS ( SELECT 1
           FROM jsonb_array_elements(p.attachments) a(value)
          WHERE (((a.value ->> 'bucket'::text) = objects.bucket_id) AND ((a.value ->> 'path'::text) = objects.name))))))))));

-- storage.avatars_insert
alter policy avatars_insert_owner_only on storage.objects
  with check ((select public.enforcement_gate('storage.avatars_insert'))
     and (((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))));

-- storage.avatars_update
alter policy avatars_update_owner_only on storage.objects
  using ((select public.enforcement_gate('storage.avatars_update'))
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
  if not public.enforcement_gate('rpc.add_post_comment') then
    raise exception 'not permitted';
  end if;
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
  if not public.enforcement_gate('rpc.reply_to_commenter') then
    raise exception 'not permitted';
  end if;
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
  if not public.enforcement_gate('rpc.respond_to_commenters') then
    raise exception 'not permitted';
  end if;
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
  if not public.enforcement_gate('rpc.get_unread_private_comment_groups') then
    raise exception 'not permitted';
  end if;
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
  select (select public.enforcement_gate('rpc.follow_requests_open')) and coalesce(
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
  select (select public.enforcement_gate('rpc.has_unread_private_comments')) and exists (
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
  -- U6b: the gate moves INTO the insert. A bare `select` observes but cannot
  -- refuse, and this function is SECURITY DEFINER so RLS does not cover it.
  insert into public.post_comment_views (post_id, viewer_user_id, last_viewed_at)
  select p_post_id, auth.uid(), now()
   where public.enforcement_gate('rpc.mark_post_comments_viewed')
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
  where (select public.enforcement_gate('rpc.get_account_directory_by_user_ids'))
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
      (select public.enforcement_gate('rpc.search_account_directory'))
      and auth.uid() is not null

      -- D-U6-1: a lapsed member becomes UNDISCOVERABLE. Subject-side, and it
      -- respects the kill switch, or a rollback would only half-roll-back.
      -- get_account_directory_by_user_ids deliberately has NO such filter (G10).
      and ((select not public.enforcement_active()) or ad.entitled_until > now())

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

-- ============================================== 9. the observer is retired
--
-- Dropped rather than kept as an alias. Nothing references it after the 23
-- policies and 9 RPCs above; leaving it would be a second way to reach the same
-- surface with a name that no longer describes it.
drop function public.shadow_observe(text);
