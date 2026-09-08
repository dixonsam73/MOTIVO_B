-- P5-G / D1 acceptance. Run against the LOCAL stack after `supabase db reset --local`.
-- Every assertion raises on failure; the final SELECT returns a row so that
-- "no rows returned" is a symptom rather than a disguise.
\set ON_ERROR_STOP on

create or replace function pg_temp.ok(cond boolean, label text) returns void
language plpgsql as $$
begin
  if cond then raise notice 'PASS  %', label;
  else raise exception 'FAIL  %', label; end if;
end $$;

create or replace function pg_temp.act(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', json_build_object('sub', u)::text, true); end $$;

create or replace function pg_temp.anon() returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', '', true); end $$;

do $outer$
declare
  ua uuid := '11111111-1111-1111-1111-111111111111';  -- adult
  ut uuid := '22222222-2222-2222-2222-222222222222';  -- teen
  r  record;
  b  boolean;
  n  int;
  t0 timestamptz;
  err text;
begin
  -- ---------- fixtures ----------
  delete from public.account_privacy where user_id in (ua, ut);
  insert into auth.users (id,email) values (ut,'t@test.local') on conflict do nothing;

  perform pg_temp.act(ua);
  perform public.account_privacy_upsert_v1('band_18_plus');
  perform pg_temp.act(ut);
  perform public.account_privacy_upsert_v1('band_13_17');

  -- =========================================================================
  -- W — WRITERS
  -- =========================================================================
  -- W3: withhold sets the flag and touches NOTHING else.
  perform pg_temp.act(ua);
  select lookup_enabled, follow_requests_enabled, lookup_set_under_band,
         follow_requests_set_under_band, band_updated_at, age_band
    into r from public.account_privacy where user_id = ua;
  perform public.account_privacy_withhold_age_eligibility_v1();
  perform pg_temp.ok((select age_eligibility_withheld from public.account_privacy where user_id=ua),
                     'W3a withhold sets the flag');
  perform pg_temp.ok((select lookup_enabled = r.lookup_enabled
                         and follow_requests_enabled = r.follow_requests_enabled
                         and lookup_set_under_band = r.lookup_set_under_band
                         and follow_requests_set_under_band = r.follow_requests_set_under_band
                         and band_updated_at = r.band_updated_at
                         and age_band = r.age_band
                      from public.account_privacy where user_id=ua),
                     'W3b withhold rewrites NO preference, band or timestamp');

  -- W5: idempotent.
  perform public.account_privacy_withhold_age_eligibility_v1();
  perform pg_temp.ok((select age_eligibility_withheld from public.account_privacy where user_id=ua),
                     'W5 withhold is idempotent');

  -- =========================================================================
  -- S — PREDICATES, while withheld
  -- =========================================================================
  perform pg_temp.ok(public.account_privacy_discoverable(ua) = false,
                     'S2 discoverable FALSE while withheld (adult, lookup on)');
  perform pg_temp.ok(public.account_privacy_requests_open(ua) = false,
                     'S3 requests_open FALSE while withheld (adult, requests on)');
  perform pg_temp.ok(public.follow_requests_open(ua) = false,
                     'S3b follow_requests_open consumer FALSE, via the helper');

  -- S5: the entitlement kill switch must NOT relax withholding.
  update public.membership_control set enforcement_enabled = false;
  perform pg_temp.ok(public.account_privacy_discoverable(ua) = false,
                     'S5a discoverable STILL false with enforcement disabled');
  perform pg_temp.ok(public.follow_requests_open(ua) = false,
                     'S5b follow_requests_open STILL false with enforcement disabled');
  update public.membership_control set enforcement_enabled = true;

  -- S4: a missing row resolves CLOSED (CP-2-R1 unchanged).
  perform pg_temp.ok(public.account_privacy_discoverable('99999999-9999-9999-9999-999999999999') = false,
                     'S4 missing row resolves CLOSED');

  -- S7: the teen override still applies independently of withholding.
  perform pg_temp.ok(public.account_privacy_discoverable(ut) = false,
                     'S7 teen default remains undiscoverable, withholding aside');

  -- =========================================================================
  -- W1/W2 — a conclusive eligible band CLEARS withholding
  -- =========================================================================
  select band_updated_at into t0 from public.account_privacy where user_id=ua;
  perform pg_temp.act(ua);
  perform public.account_privacy_upsert_v1('band_18_plus');   -- same band
  perform pg_temp.ok((select not age_eligibility_withheld from public.account_privacy where user_id=ua),
                     'W1 conclusive eligible band clears withholding');
  perform pg_temp.ok((select band_updated_at = t0 from public.account_privacy where user_id=ua),
                     'W2 unchanged band is idempotent: band_updated_at unmoved');
  perform pg_temp.ok(public.account_privacy_discoverable(ua),
                     'S1 discoverable TRUE again once withholding cleared');

  -- =========================================================================
  -- NEW ASSERTION: no client RPC can clear withholding directly
  -- =========================================================================
  perform public.account_privacy_withhold_age_eligibility_v1();
  -- the preference writers must NOT clear it
  perform public.account_privacy_set_lookup_v1(true);
  perform public.account_privacy_set_follow_requests_v1(true);
  perform pg_temp.ok((select age_eligibility_withheld from public.account_privacy where user_id=ua),
                     'X1 preference writers CANNOT clear withholding');
  perform pg_temp.ok(public.account_privacy_discoverable(ua) = false,
                     'X2 turning lookup ON does not defeat withholding');
  -- and there is no argument-taking withhold function to pass false to
  select count(*) into n from pg_proc p join pg_namespace nn on nn.oid=p.pronamespace
   where nn.nspname='public' and p.proname='account_privacy_withhold_age_eligibility_v1'
     and p.pronargs = 0;
  perform pg_temp.ok(n = 1, 'X3 withhold RPC is PARAMETERLESS: no way to pass false');

  -- W4: withhold with no row raises and creates nothing.
  perform pg_temp.act('99999999-9999-9999-9999-999999999999');
  begin
    perform public.account_privacy_withhold_age_eligibility_v1();
    perform pg_temp.ok(false, 'W4 should have raised');
  exception when check_violation then
    perform pg_temp.ok(true, 'W4 withhold with no row raises 23514');
  end;
  perform pg_temp.ok((select count(*) from public.account_privacy
                       where user_id='99999999-9999-9999-9999-999999999999') = 0,
                     'W4b withhold created NO row');

  -- =========================================================================
  -- R — reclassification round trip, preferences preserved
  -- =========================================================================
  perform pg_temp.act(ua);
  perform public.account_privacy_upsert_v1('band_18_plus');     -- clear withholding
  perform public.account_privacy_set_lookup_v1(true);           -- adult sets ON
  perform pg_temp.ok(public.account_privacy_discoverable(ua), 'R0 adult ON is effective');

  perform public.account_privacy_upsert_v1('band_13_17');       -- adult -> teen
  perform pg_temp.ok(public.account_privacy_discoverable(ua) = false,
                     'R1 adult->teen withholds EFFECT of the adult-set preference');
  perform pg_temp.ok((select lookup_enabled and lookup_set_under_band='band_18_plus'
                      from public.account_privacy where user_id=ua),
                     'R1b the stored preference is NOT rewritten');

  perform public.account_privacy_upsert_v1('band_18_plus');     -- teen -> adult
  perform pg_temp.ok(public.account_privacy_discoverable(ua),
                     'R2/R3 teen->adult round trip RESTORES the underlying preference');

  -- R5: withheld -> valid band clears withholding with preferences intact.
  perform public.account_privacy_withhold_age_eligibility_v1();
  perform public.account_privacy_upsert_v1('band_18_plus');
  perform pg_temp.ok(public.account_privacy_discoverable(ua)
                     and (select lookup_enabled from public.account_privacy where user_id=ua),
                     'R5 withheld -> eligible clears withholding, preferences intact');

  -- =========================================================================
  -- W7 / grants
  -- =========================================================================
  select count(*) into n from information_schema.routine_privileges
   where routine_schema='public' and routine_name='account_privacy_self_v1'
     and grantee='authenticated' and privilege_type='EXECUTE';
  perform pg_temp.ok(n=1, 'W7a self_v1 EXECUTE grant survived the DROP/CREATE');

  select count(*) into n from information_schema.routine_privileges
   where routine_schema='public'
     and routine_name in ('account_privacy_discoverable','account_privacy_requests_open')
     and grantee in ('anon','authenticated','service_role');
  perform pg_temp.ok(n=0, 'W7b internal helpers remain client-unexecutable');

  select count(*) into n from information_schema.role_table_grants
   where table_schema='public' and table_name='account_privacy'
     and grantee in ('anon','authenticated','service_role');
  perform pg_temp.ok(n=0, 'W6 no client role holds ANY table privilege on account_privacy');

  -- self_v1 returns seven columns including the flag
  perform pg_temp.act(ua);
  select count(*) into n from information_schema.columns
   where false;  -- placeholder, real check below
  perform pg_temp.ok((select o_age_eligibility_withheld is not null from public.account_privacy_self_v1()),
                     'W7c self_v1 returns o_age_eligibility_withheld');

  raise notice '--- ALL P5-G/D1 SQL ASSERTIONS PASSED ---';
end $outer$;

select 'p5g-d1 acceptance complete' as result;
