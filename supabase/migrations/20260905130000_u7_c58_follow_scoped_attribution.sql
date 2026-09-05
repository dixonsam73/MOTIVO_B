-- P4-U7 / C-58 — FOLLOW-SCOPED RETAINED ATTRIBUTION FOR A LAPSED VIEWER.
--
-- The production apply file, with its in-transaction guards and its returning
-- SELECT, is `supabase/sql/2026-09-05-u7-c58-follow-scoped-attribution.sql`.
-- This is the same function body for the local stack; read that file for the
-- reasoning, in particular WHY the disjunct keys on an APPROVED follow rather
-- than on any row the viewer can already see.

create or replace function public.get_account_directory_by_user_ids(user_ids uuid[])
 returns table(user_id uuid, account_id text, display_name text, location text,
               avatar_key text, instruments text[], avatar_version timestamp with time zone)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select
    ad.user_id,
    ad.account_id,
    ad.display_name,
    ad.location,
    ad.avatar_key,
    ad.instruments,
    ad.avatar_version
  from public.account_directory ad
  where auth.uid() is not null
    and ad.user_id = any(user_ids)
    and (
      (select public.enforcement_gate('rpc.get_account_directory_by_user_ids'))
      or exists (
        select 1
        from public.follows f
        where f.status = 'approved'
          and ( (f.follower_user_id = auth.uid() and f.followed_user_id = ad.user_id)
             or (f.followed_user_id = auth.uid() and f.follower_user_id = ad.user_id) )
      )
    );
$function$;
