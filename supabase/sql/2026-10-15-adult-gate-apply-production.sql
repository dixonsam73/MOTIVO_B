-- Adult-only gate: refusal counter + upsert restricted to band_18_plus.
-- PRODUCTION APPLY. Requires one Codex review round and Samuel's approval.
-- NOT APPLIED. Prepared and rehearsed locally 2026-10-15.
-- Run: supabase db query --linked -f supabase/sql/2026-10-15-adult-gate-apply-production.sql
-- The body between BEGIN and COMMIT is the migration
-- supabase/migrations/20261015120000_adult_gate_refusal_counter.sql verbatim
-- (the rehearsal script checks this). Guards run inside the transaction.
-- Expect the final row: applied | 0 | t | f | t
--   (counter rows, anon can record, anon can read, upsert restricted).
-- Anything else, or an error, means it did not apply. The exit code is 0 even
-- on failure: read the response.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
-- Adult-only gate for Connected (RELEASE.md section B, decided 2026-10-15).
--
-- 1. An anonymous count of Connected joins refused by the age gate, per month
--    and reason. A number only: no user id, no device id, no timestamp finer
--    than the month. It is evidence for the children's access assessment, and
--    it is an INDICATOR, NOT AN AUDITED FIGURE: it counts attempts, not people
--    (one person retrying counts each time), and anyone holding the public
--    anon key can call the RPC, so it can be inflated. Monthly buckets make a
--    spike visible. Refusals happen before Sign in with Apple, so the caller
--    is anonymous by design.
--    Readable only by the service role (dashboard / SQL editor): RLS is on with
--    no policies and the client roles hold no table privileges.
--
-- 2. account_privacy_upsert_v1 accepts only band_18_plus. The client gate only
--    ever writes that; this stops an older beta build establishing a 13-17
--    row. Existing rows are untouched. The rest of the 13-17 server pathway
--    (B-40, the band columns, tg_directory_requires_band) stays, by decision
--    (Samuel, 2026-10-15, choice 3). The body is otherwise identical to B-40's.
--
-- The reasons are ConnectedAgeGate.RefusalReason's raw values.

do $adult_gate_pre$
begin
  if to_regclass('public.connected_age_refusals') is not null
     or to_regprocedure('public.record_connected_age_refusal_v1(text)') is not null then
    raise exception 'adult gate: counter already exists';
  end if;
  if to_regprocedure('public.account_privacy_upsert_v1(text)') is null then
    raise exception 'adult gate: account_privacy_upsert_v1(text) missing';
  end if;
end $adult_gate_pre$;

create table public.connected_age_refusals (
    month     date   not null,
    reason    text   not null,
    refusals  bigint not null default 0,
    constraint connected_age_refusals_pkey primary key (month, reason),
    constraint connected_age_refusals_reason
        check (reason = any (array['under_18'::text, 'unconfirmed_adult'::text, 'declined'::text,
                                   'unavailable'::text, 'ios_update_needed'::text])),
    constraint connected_age_refusals_month_is_first_day
        check (month = date_trunc('month', month)::date),
    constraint connected_age_refusals_non_negative check (refusals >= 0)
);

alter table public.connected_age_refusals enable row level security;
revoke all on table public.connected_age_refusals from public, anon, authenticated;

create function public.record_connected_age_refusal_v1(p_reason text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if p_reason is null or p_reason not in
     ('under_18','unconfirmed_adult','declined','unavailable','ios_update_needed') then
    raise exception 'invalid refusal reason' using errcode = '22023';
  end if;
  insert into public.connected_age_refusals as r (month, reason, refusals)
  values (date_trunc('month', now() at time zone 'utc')::date, p_reason, 1)
  on conflict (month, reason) do update set refusals = r.refusals + 1;
end $function$;

revoke all on function public.record_connected_age_refusal_v1(text) from public, anon, authenticated;
grant execute on function public.record_connected_age_refusal_v1(text) to anon, authenticated;

CREATE OR REPLACE FUNCTION public.account_privacy_upsert_v1(p_age_band text)
 RETURNS TABLE(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean, o_follow_requests_enabled boolean, o_follow_requests_effective boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'authentication required' using errcode='28000'; end if;
  if p_age_band is distinct from 'band_18_plus' then raise exception 'invalid age band' using errcode='22023'; end if;

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

do $adult_gate_post$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.connected_age_refusals'::regclass) then
    raise exception 'adult gate: RLS not enabled on the counter';
  end if;
  if exists (select 1 from pg_policies where schemaname='public' and tablename='connected_age_refusals') then
    raise exception 'adult gate: the counter must have no policies';
  end if;
  if has_table_privilege('anon', 'public.connected_age_refusals', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.connected_age_refusals', 'select,insert,update,delete') then
    raise exception 'adult gate: client roles hold table privileges on the counter';
  end if;
  if not has_function_privilege('anon', 'public.record_connected_age_refusal_v1(text)', 'execute') then
    raise exception 'adult gate: anon cannot record a refusal';
  end if;
  if position('is distinct from ''band_18_plus''' in
       (select prosrc from pg_proc where oid = 'public.account_privacy_upsert_v1(text)'::regprocedure)) = 0 then
    raise exception 'adult gate: upsert not restricted to band_18_plus';
  end if;
  if not has_function_privilege('authenticated', 'public.account_privacy_upsert_v1(text)', 'execute') then
    raise exception 'adult gate: authenticated lost execute on the upsert';
  end if;
end $adult_gate_post$;

-- PostgREST picks up the new RPC at commit.
notify pgrst, 'reload schema';
COMMIT;
SELECT 'applied' AS adult_gate,
       (SELECT count(*) FROM public.connected_age_refusals) AS counter_rows,
       has_function_privilege('anon', 'public.record_connected_age_refusal_v1(text)', 'execute') AS anon_can_record,
       has_table_privilege('anon', 'public.connected_age_refusals', 'select') AS anon_can_read,
       position('is distinct from ''band_18_plus''' IN
         (SELECT prosrc FROM pg_proc WHERE oid = 'public.account_privacy_upsert_v1(text)'::regprocedure)) > 0
         AS upsert_adult_only;
