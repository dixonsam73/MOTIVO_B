-- B-40 / audit A4 — A 13-17 MEMBER'S INBOUND FOLLOW REQUESTS ARE CLOSED, SERVER-SIDE.
--
-- THE DECISION (P5-G / Q2, docs/phase-5-g-decision-register.md §A2): a 13-17 member
-- CANNOT enable inbound follow requests, and no follow-request control is to be added.
-- Reason of record: Études has no moderation, no reporting surface and no guardian
-- channel, so inbound contact from a stranger to a minor has no mitigating control.
-- The young member may still initiate relationships themselves.
--
-- THE DEFECT. `account_privacy_set_follow_requests_v1` is executable by
-- `authenticated` (retained by decision, no client caller) and stamps
-- `follow_requests_set_under_band` with the row's CURRENT band. The effective rule
-- below only closed a teen row whose preference had been set under `band_18_plus`, so
-- a teen calling the writer directly produced an OPEN row, and another member's
-- `follows` insert then passed `follows_insert_requester`.
--
-- THE CHANGE. One expression, in the helper and its two inline mirrors, so the three
-- read paths cannot disagree:
--     effective follow requests := follow_requests_enabled AND age_band <> 'band_13_17'
-- Adults are unchanged by construction (`age_band` is NOT NULL, two values): for
-- `band_18_plus` both the old and new expressions reduce to `follow_requests_enabled`.
-- It is read-time, so it also closes any row already written.
--
-- DELIBERATELY UNCHANGED: signatures, return types, security definer, search_path and
-- grants (CREATE OR REPLACE keeps them); the writer and its grant; discovery
-- (`account_privacy_discoverable`, where a teen's own opt-in stays effective);
-- `follow_requests_open` and the follows policy, which call the helper.
--
-- Bodies transcribed from pg_get_functiondef on the local stack (identical to
-- 20260906120000_cp1_cp2_account_privacy.sql) with only that expression changed.

CREATE OR REPLACE FUNCTION public.account_privacy_requests_open(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((
    select p.follow_requests_enabled
       and p.age_band <> 'band_13_17'
      from public.account_privacy p
     where p.user_id = target_user_id), false);
$function$;

CREATE OR REPLACE FUNCTION public.account_privacy_self_v1()
 RETURNS TABLE(o_age_band text, o_lookup_enabled boolean, o_lookup_effective boolean, o_follow_requests_enabled boolean, o_follow_requests_effective boolean, o_band_updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select ap.age_band, ap.lookup_enabled,
         (ap.lookup_enabled and not (ap.age_band='band_13_17' and ap.lookup_set_under_band='band_18_plus')),
         ap.follow_requests_enabled,
         (ap.follow_requests_enabled and ap.age_band <> 'band_13_17'),
         ap.band_updated_at
    from public.account_privacy ap
   where ap.user_id = auth.uid();
$function$;

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
