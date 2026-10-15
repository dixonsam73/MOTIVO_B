-- Adult-only gate: ROLLBACK of 2026-10-15-adult-gate-apply-production.sql.
-- PRODUCTION. Use only with Samuel's approval.
-- Run: supabase db query --linked -f supabase/sql/2026-10-15-adult-gate-rollback-production.sql
-- Restores account_privacy_upsert_v1 to its B-40 body (accepting band_13_17
-- and band_18_plus), and drops the refusal counter and its RPC.
-- REFUSES while the counter holds any count: those numbers are the children's
-- access assessment's evidence. Export them first (SELECT * FROM
-- public.connected_age_refusals ORDER BY month, reason), then delete the rows
-- deliberately, then run this.
-- Expect the final row: rolled back | t | t
-- Anything else, or an error, means it did not roll back. The exit code is 0
-- even on failure: read the response.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $guard$
BEGIN
  IF to_regclass('public.connected_age_refusals') IS NULL
     OR to_regprocedure('public.record_connected_age_refusal_v1(text)') IS NULL THEN
    RAISE EXCEPTION 'adult gate rollback: counter not present; nothing to roll back';
  END IF;
  IF position('is distinct from ''band_18_plus''' IN
       (SELECT prosrc FROM pg_proc WHERE oid = 'public.account_privacy_upsert_v1(text)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'adult gate rollback: upsert is not in the applied state';
  END IF;
  IF EXISTS (SELECT 1 FROM public.connected_age_refusals WHERE refusals > 0) THEN
    RAISE EXCEPTION 'adult gate rollback: the counter holds counts; export and delete them first';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.account_privacy_upsert_v1(p_age_band text)
 RETURNS TABLE(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean, o_follow_requests_enabled boolean, o_follow_requests_effective boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  if p_age_band not in ('band_13_17','band_18_plus') then raise exception 'invalid age band' using errcode='22023'; end if;

  insert into public.account_privacy as ap
      (user_id, age_band, lookup_enabled, lookup_set_under_band,
       follow_requests_enabled, follow_requests_set_under_band)
  values (v_uid, p_age_band,
          (p_age_band='band_18_plus'), p_age_band,
          (p_age_band='band_18_plus'), p_age_band)
  on conflict (user_id) do update
     set age_band = excluded.age_band,
         band_updated_at = case when ap.age_band = excluded.age_band then ap.band_updated_at else now() end;

  return query
    select ap.age_band, ap.lookup_enabled,
           (ap.lookup_enabled and not (ap.age_band='band_13_17' and ap.lookup_set_under_band='band_18_plus')),
           ap.follow_requests_enabled,
           (ap.follow_requests_enabled and ap.age_band <> 'band_13_17')
      from public.account_privacy ap where ap.user_id = v_uid;
end $function$;

DROP FUNCTION public.record_connected_age_refusal_v1(text);
DROP TABLE public.connected_age_refusals;

DO $post$
BEGIN
  IF to_regclass('public.connected_age_refusals') IS NOT NULL
     OR to_regprocedure('public.record_connected_age_refusal_v1(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'adult gate rollback: counter still present';
  END IF;
  IF position('not in (''band_13_17'',''band_18_plus'')' IN
       (SELECT prosrc FROM pg_proc WHERE oid = 'public.account_privacy_upsert_v1(text)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'adult gate rollback: upsert not restored';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.account_privacy_upsert_v1(text)', 'execute') THEN
    RAISE EXCEPTION 'adult gate rollback: authenticated lost execute on the upsert';
  END IF;
END $post$;
NOTIFY pgrst, 'reload schema';
COMMIT;
SELECT 'rolled back' AS adult_gate,
       to_regclass('public.connected_age_refusals') IS NULL AS counter_gone,
       position('not in (''band_13_17'',''band_18_plus'')' IN
         (SELECT prosrc FROM pg_proc WHERE oid = 'public.account_privacy_upsert_v1(text)'::regprocedure)) > 0
         AS upsert_restored;
