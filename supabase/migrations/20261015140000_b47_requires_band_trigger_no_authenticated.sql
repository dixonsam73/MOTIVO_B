-- B-47 follow-up. LOCAL FIDELITY ONLY: already true in production.
--
-- Production: no client role can execute tg_account_directory_requires_band
-- (supabase/schema/function_grants.json). B-41 revoked it from public, anon and
-- service_role, which was enough while the local stack's default ACL granted
-- functions through PUBLIC. From Supabase CLI 2.121.0 the local default ACL
-- grants anon, authenticated and service_role EXECUTE directly, so authenticated
-- kept it and verify-baseline.sh failed. Stating the revoke makes local
-- reproduce production whatever the default ACL. Nothing to apply there.

revoke all on function public.tg_account_directory_requires_band() from authenticated;
