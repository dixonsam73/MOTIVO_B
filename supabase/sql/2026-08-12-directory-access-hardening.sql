-- 2026-08-12 — directory access hardening
--
-- Covers B-5, and the latent anon exposure on search_account_directory found
-- while verifying it. Reviewed as a diff before being applied, per
-- supabase/README.md; migration tooling arrives in Phase 3.
--
-- Apply as one round trip so the transaction is real:
--     supabase db query --linked -f supabase/sql/2026-08-12-directory-access-hardening.sql
-- then immediately:
--     ./supabase/capture-schema.sh && git diff --stat supabase/schema
--
--
-- BEFORE-STATE, observed 2026-08-12 over the wire with the shipped anon key
-- and no bearer token. Recorded here because a passing check after a fix
-- proves nothing unless the defect was seen first (B-4's lesson):
--
--   V1  POST /rest/v1/rpc/get_account_directory_by_user_ids
--       -> HTTP 200, one full directory row (user_id, account_id,
--          display_name, instruments populated).            B-5, observed.
--
--   V2  POST /rest/v1/rpc/search_account_directory {"q":"cva"}
--       -> HTTP 200, zero rows — while that same token matches exactly one
--          row once the auth.uid() self-exclusion is lifted.
--
-- V2 is the point: search is not protected from anon, it merely fails closed
-- by accident. `ad.user_id <> auth.uid()` is self-exclusion; against a NULL
-- uid every comparison yields NULL and every row is filtered. That is a side
-- effect of a predicate written for a different purpose.
--
--
-- NOT IN SCOPE, deliberately:
--
--   lookup_enabled.  Neither function consults it and neither should. Discovery
--   is always on and relationship privacy is explicit follow approval (settled;
--   client side landed at ff2d4ff). The 8 of 15 rows currently holding
--   lookup_enabled = false are residue from the pre-July model — every one was
--   last signed in on or before 2026-06-06 — not preferences anybody expressed.
--   Gating resolution on it would blank names and avatars for existing
--   followers; gating search on it would hide accounts that never opted out.
--   See B-2, premise corrected.
--
--   B-15, the 2-character substring floor. Phase 4.
--   B-11, server-side paid-membership enforcement. Phase 3.


begin;

-- 1. Bodies.
--
--    An explicit auth.uid() test, so the boundary is stated in the function
--    rather than resting on a grant alone. CREATE OR REPLACE preserves the
--    existing ACL; it does not reset it. Step 2 is what changes the grants.
--
--    WARNING for whoever edits search_account_directory next:
--    `ad.user_id <> auth.uid()` is self-exclusion, NOT a security control.
--    Do not "tidy" it to IS DISTINCT FROM. Doing so would return every row to
--    an unauthenticated caller the moment a grant to anon ever came back — and
--    Supabase's default privileges on `public` re-grant anon, authenticated
--    and service_role on any NEWLY CREATED object, so a future drop-and-
--    recreate of this function would restore exactly that grant silently.
--    The auth.uid() IS NOT NULL test below is what makes that survivable.

create or replace function public.get_account_directory_by_user_ids(user_ids uuid[])
returns table(user_id uuid, account_id text, display_name text,
              location text, avatar_key text, instruments text[])
language sql stable security definer set search_path to 'public'
as $function$
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

create or replace function public.search_account_directory(q text)
returns table(user_id uuid, account_id text, display_name text,
              location text, avatar_key text, instruments text[])
language sql stable security definer set search_path to 'public'
as $function$

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


-- 2. Grants. Applied after the replaces so they land regardless of ordering.
--
--    PUBLIC must be revoked as well as anon: anon inherits PUBLIC, so revoking
--    anon alone would leave both functions world-executable.
--
--    service_role is revoked too. There is no service-role caller today —
--    delete_account_v1 reads and writes the account_directory TABLE directly
--    (functions/delete_account_v1/index.ts:265, :350) and never these RPCs —
--    and that is the intended Phase 3 pattern: server-side code queries the
--    table with service_role, it does not go through these RPCs. Leaving the
--    grant in place while the bodies return zero rows to a service-role caller
--    (auth.uid() is NULL there) would be a silent-empty-result trap; plain
--    LANGUAGE sql cannot RAISE, so the honest fix is to remove the grant.
--
--    The callable surface is therefore explicitly authenticated-only, plus the
--    owner: target ACL {postgres=X/postgres, authenticated=X/postgres}.
--
--    Note this is deliberately TIGHTER than public.follow_requests_open, which
--    carries {postgres, authenticated, service_role} and no PUBLIC entry. That
--    function is called from the follows_insert_requester RLS policy and is
--    left exactly as deployed (B-18, register correction only) — its
--    SECURITY DEFINER is load-bearing, and dropping it would make follow-request
--    gating fail OPEN, because the policy's subselect would then hit
--    account_directory_select_owner, find no row for another user, and
--    coalesce to true.

revoke execute on function public.get_account_directory_by_user_ids(uuid[])
  from public, anon, service_role;

revoke execute on function public.search_account_directory(text)
  from public, anon, service_role;

commit;
