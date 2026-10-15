-- Adult-only gate, follow-up. LOCAL FIDELITY ONLY: already true in production.
--
-- After the 2026-10-15 production apply, capture-schema.sh showed production's
-- default privileges granting service_role ALL on connected_age_refusals and
-- EXECUTE on record_connected_age_refusal_v1 directly. The local stack's
-- defaults don't (its service_role reached the function only through PUBLIC,
-- which the migration revokes), so verify-baseline.sh failed on these grants.
-- Stating them makes local reproduce production. Nothing to apply there.
-- anon and authenticated keep execute only, and no table access.

grant all on table public.connected_age_refusals to service_role;
grant execute on function public.record_connected_age_refusal_v1(text) to service_role;
