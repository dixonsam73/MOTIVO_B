-- B-41 / R1 — RESTORE THE MIGRATION HISTORY TO PRODUCTION PARITY. SCHEMA ONLY.
--
-- The B-23 gate reported 19 problems on a fresh local rebuild (2026-09-14). Every
-- one is a statement production already has and supabase/migrations/ lacked. This
-- file adds NOTHING new: each statement is copied from the record of what ran,
-- and the target is the committed supabase/schema/ snapshot. Historical
-- migrations are deliberately NOT edited. Production is NOT touched by this file.
--
-- Plan and prediction: docs/phase-5-b41-b42-restoration-plan.md,
-- docs/phase-5-b41-r1-prediction.md.

-- ====================================================== 1. P4-U2s posts policy
--
-- Source: supabase/sql/2026-09-04-u2s-posts-insert-privacy.sql, applied to
-- production 2026-09-04 and never added as a migration. Copied verbatim.
alter policy posts_insert_owner on public.posts
  with check (
    (select public.enforcement_gate('posts.insert'::text))
    and (owner_user_id = auth.uid())
    and (is_public = true)
  );

-- ======================================== 2. CP-1 privacy functions and trigger
--
-- Source: docs/phase-5-d-cp1-migration-prediction.md §4, the planned statements
-- the committed CP-1 migration omitted. A new function inherits PUBLIC EXECUTE
-- by default, so without these the local rebuild let anon and service_role call
-- the four RPCs and every role hold EXECUTE on the trigger function.
revoke all on function public.account_privacy_upsert_v1(text)               from public, anon, service_role;
revoke all on function public.account_privacy_set_lookup_v1(boolean)        from public, anon, service_role;
revoke all on function public.account_privacy_set_follow_requests_v1(boolean) from public, anon, service_role;
revoke all on function public.account_privacy_self_v1()                     from public, anon, service_role;
revoke all on function public.tg_account_directory_requires_band()          from public, anon, service_role;

grant execute on function public.account_privacy_upsert_v1(text)               to authenticated;
grant execute on function public.account_privacy_set_lookup_v1(boolean)        to authenticated;
grant execute on function public.account_privacy_set_follow_requests_v1(boolean) to authenticated;
grant execute on function public.account_privacy_self_v1()                     to authenticated;

-- ============================================ 3. P4-U5 avatar-version trigger
--
-- Source: docs/phase-4-u5-acceptance.md — the trigger function "picked up
-- Supabase's default public EXECUTE", was found by snapshot recapture, and
-- "Four REVOKEs later" matched tg_set_entitled_until in production. Those
-- revokes were never added to a migration.
revoke all on function public.tg_stamp_avatar_version() from public, anon, authenticated, service_role;
