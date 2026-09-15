#!/usr/bin/env bash
#
# SCOPE 011 — VERIFIED APPLE SANDBOX MEMBERSHIP COUNTS AS CONNECTED ENTITLEMENT.
# DISPOSABLE LOCAL STACK ONLY. ROLLBACK ONLY.
#
#   SCOPE011_MIG=<path to the scope 011 migration> ./supabase/tests/p5/sandbox-entitlement.sh before
#   SCOPE011_MIG=<path to the scope 011 migration> ./supabase/tests/p5/sandbox-entitlement.sh after
#
# `before` runs against the stack as built (B-39 without scope 011). `after` creates
# the same fixtures, THEN applies the migration inside the same transaction, so the
# migration's recompute of the four cached columns is what case 7 tests.
#
# Every run is ONE transaction that is ROLLED BACK: fixtures (fresh ids), the
# enforcement flag and, in `after`, the migration. A structural fingerprint and row
# counts are compared before and after the run.
#
# TARGET. The database comes from the existing u2/u4 guards (localhost DB_URL from
# `supabase status`, exactly one supabase_db_* container publishing that port). This
# suite additionally refuses unless that container is THIS workdir's own project and
# never the retained developer stack.
#
# Exit: 0 prediction matched, 1 prediction deviated, 3 inconclusive.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e

MODE="${1:-}"
[ "$MODE" = before ] || [ "$MODE" = after ] || { echo "usage: $0 before|after"; exit 2; }
MIG="${SCOPE011_MIG:-supabase/migrations/20260915160000_scope011_verified_sandbox_entitlement.sql}"
[ "$MODE" = before ] || [ -f "$MIG" ] || { echo "migration not found: $MIG"; exit 3; }

RETAINED_DB="supabase_db_rlwtqxumfobakvdueugm"
PID=$(sed -nE 's/^project_id[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' supabase/config.toml)
[ -n "$PID" ] || { echo "no project_id in supabase/config.toml"; exit 3; }
[ "$DB" = "supabase_db_$PID" ] || { echo "refusing: resolved '$DB', not this workdir's project container supabase_db_$PID"; exit 3; }
[ "$DB" != "$RETAINED_DB" ] || { echo "refusing: resolved the RETAINED developer stack"; exit 3; }

FINGERPRINT="select md5(string_agg(p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'||pg_get_functiondef(p.oid)||coalesce(array_to_string(p.proacl,','),''),'|' order by p.proname, pg_get_function_identity_arguments(p.oid)))
  ||' users='||(select count(*) from auth.users)||' membership='||(select count(*) from public.membership)
  ||' posts='||(select count(*) from public.posts)||' shares='||(select count(*) from public.post_shares)
  ||' follows='||(select count(*) from public.follows)||' directory='||(select count(*) from public.account_directory)
  ||' privacy='||(select count(*) from public.account_privacy)||' shadow='||(select count(*) from public.shadow_enforcement_stat)
  ||' enforcing='||public.enforcement_active()
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public';"

echo; echo "Scope 011 — verified Sandbox entitlement ($MODE)"
echo "target: $DB (project $PID); migrations applied: $(psq "select max(version) from supabase_migrations.schema_migrations;")"
STATE_BEFORE=$(psq "$FINGERPRINT")
echo "state before: $STATE_BEFORE"

u() { uuidgen | tr 'A-Z' 'a-z'; }
TAG=$(u | cut -c1-8)
S_ACT=$(u); S_LAP=$(u); S_REV=$(u); S_GRC=$(u); S_RTY=$(u); P_ENT=$(u); P_EXP=$(u); MIX=$(u); S_DIR=$(u); POST=$(u)
as() { printf "set local role authenticated;\nselect set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true) is not null as claims;\n" "$1"; }

SQL_FILE=$(mktemp)
{
  echo "begin;"
  cat <<SQL
-- ------------------------------------------------------------------ fixtures
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 's11-' || id || '@local.invalid', now(), now()
  from unnest(array['$S_ACT','$S_LAP','$S_REV','$S_GRC','$S_RTY','$P_ENT','$P_EXP','$MIX','$S_DIR']) as id;

insert into public.membership (user_id, environment, original_transaction_id, product_id, apple_status, renewal_date,
                               is_in_billing_retry, grace_period_expires_date, renewal_info_signed_date, revocation_date,
                               binding_method, bound_at, entitlement_ended_at) values
 ('$S_ACT','Sandbox',   's11-$TAG-act','p',1, now()+interval '30 days', false, null,                    now(), null,                   'purchase', now(), null),
 ('$S_LAP','Sandbox',   's11-$TAG-lap','p',2, now()-interval '2 days',  false, null,                    now(), null,                   'purchase', now(), now()-interval '2 days'),
 ('$S_REV','Sandbox',   's11-$TAG-rev','p',5, now()+interval '20 days', false, null,                    now(), now()-interval '1 day', 'purchase', now(), now()-interval '1 day'),
 ('$S_GRC','Sandbox',   's11-$TAG-grc','p',4, now()-interval '1 day',   true,  now()+interval '10 days',now(), null,                   'purchase', now(), null),
 ('$S_RTY','Sandbox',   's11-$TAG-rty','p',3, now()-interval '9 days',  true,  now()-interval '1 day',  now(), null,                   'purchase', now(), now()-interval '1 day'),
 ('$P_ENT','Production','s11-$TAG-pent','p',1, now()+interval '30 days', false, null,                   now(), null,                   'purchase', now(), null),
 ('$P_EXP','Production','s11-$TAG-pexp','p',2, now()-interval '2 days',  false, null,                   now(), null,                   'purchase', now(), now()-interval '2 days'),
 ('$MIX',  'Production','s11-$TAG-mixp','p',5, now()+interval '20 days', false, null,                   now(), now()-interval '1 day', 'purchase', now(), now()-interval '1 day'),
 ('$MIX',  'Sandbox',   's11-$TAG-mixs','p',1, now()+interval '30 days', false, null,                   now(), null,                   'purchase', now(), null),
 ('$S_DIR','Sandbox',   's11-$TAG-dir','p',1, now()+interval '30 days', false, null,                    now(), null,                   'purchase', now(), null);

insert into public.account_privacy (user_id, age_band, lookup_enabled, lookup_set_under_band, follow_requests_enabled, follow_requests_set_under_band) values
 ('$S_ACT','band_18_plus',true,'band_18_plus',true,'band_18_plus'),
 ('$S_DIR','band_18_plus',true,'band_18_plus',true,'band_18_plus'),
 ('$P_ENT','band_18_plus',true,'band_18_plus',true,'band_18_plus');

-- The four cached columns for S_ACT, written BEFORE any migration in this transaction.
insert into public.account_directory (user_id, account_id, display_name) values ('$S_ACT', 's11a$TAG', 'S11 Active $TAG');
insert into public.posts (id, owner_user_id, is_public, created_at, attachments) values ('$POST', '$S_ACT', true, now(), '[]'::jsonb);
insert into public.post_shares (post_id, owner_user_id, recipient_user_id) values ('$POST', '$S_ACT', '$P_ENT');
insert into public.follows (follower_user_id, followed_user_id, status, created_at, updated_at) values ('$P_ENT', '$S_ACT', 'approved', now(), now());
SQL
  if [ "$MODE" = after ]; then echo "-- ------------------------------------------ scope 011 migration"; cat "$MIG"; echo; fi
  cat <<SQL
update public.membership_control set enforcement_enabled = true where id;
select 'SETUP|enforcing|' || public.enforcement_active();

-- 1 — active Sandbox: predicate AND the real gate as that identity
$(as "$S_ACT")
select 'SETUP|gate S_ACT|' || set_config('s11.gate_act', public.enforcement_gate('probe.scope011')::text, true);
reset role;
select 'CHECK|1|' || case when public.connected_member('$S_ACT') and current_setting('s11.gate_act') = 'true' then 'PASS' else 'FAIL' end
       || '|connected_member(S_ACT)=' || public.connected_member('$S_ACT') || ' gate=' || current_setting('s11.gate_act');

-- 2 — lapsed Sandbox
$(as "$S_LAP")
select 'SETUP|gate S_LAP|' || set_config('s11.gate_lap', public.enforcement_gate('probe.scope011')::text, true);
reset role;
select 'CHECK|2|' || case when not public.connected_member('$S_LAP') and current_setting('s11.gate_lap') = 'false' then 'PASS' else 'FAIL' end
       || '|connected_member(S_LAP)=' || public.connected_member('$S_LAP') || ' gate=' || current_setting('s11.gate_lap');

-- 3 — revoked Sandbox
select 'CHECK|3|' || case when not public.connected_member('$S_REV') then 'PASS' else 'FAIL' end || '|connected_member(S_REV)=' || public.connected_member('$S_REV');

-- 4 — Sandbox billing retry
select 'CHECK|4a|' || case when public.connected_member('$S_GRC') then 'PASS' else 'FAIL' end || '|within grace=' || public.connected_member('$S_GRC');
select 'CHECK|4b|' || case when not public.connected_member('$S_RTY') then 'PASS' else 'FAIL' end || '|past grace=' || public.connected_member('$S_RTY');

-- 5 — Production unchanged
select 'CHECK|5|' || case when public.connected_member('$P_ENT') and not public.connected_member('$P_EXP') then 'PASS' else 'FAIL' end
       || '|P_ENT=' || public.connected_member('$P_ENT') || ' P_EXP=' || public.connected_member('$P_EXP');

-- 6 — mixed: revoked Production + live Sandbox
select 'CHECK|6|' || case when public.connected_member('$MIX') then 'PASS' else 'FAIL' end || '|MIX=' || public.connected_member('$MIX');

-- 9 — membership_state keeps its value set
select 'CHECK|9|' || case when public.membership_state('$S_ACT') = 'sandbox_only' and public.membership_state('$P_ENT') = 'entitled'
                            and public.membership_state('$P_EXP') = 'expired' then 'PASS' else 'FAIL' end
       || '|S_ACT=' || public.membership_state('$S_ACT') || ' P_ENT=' || public.membership_state('$P_ENT') || ' P_EXP=' || public.membership_state('$P_EXP');

-- 10 — an active Sandbox identity's own directory INSERT under enforcement, then search by an entitled viewer
$(as "$S_DIR")
do \$s11\$ begin
  insert into public.account_directory (user_id, account_id, display_name) values ('$S_DIR', 's11d$TAG', 'S11probe$TAG');
  raise notice 'NOTE|10|directory insert by S_DIR accepted';
exception
  when insufficient_privilege then raise notice 'NOTE|10|directory insert by S_DIR refused: %', sqlerrm;
  when others then raise notice 'NOTE|10|SETUP-ERROR % %', sqlstate, sqlerrm;
end \$s11\$;
reset role;
$(as "$P_ENT")
select 'SETUP|search as P_ENT|' || set_config('s11.found', (select count(*) from public.search_account_directory('S11probe$TAG') where user_id = '$S_DIR')::text, true);
reset role;
select 'CHECK|10|' || case when exists (select 1 from public.account_directory where user_id = '$S_DIR')
                             and current_setting('s11.found') = '1' then 'PASS' else 'FAIL' end
       || '|row=' || exists (select 1 from public.account_directory where user_id = '$S_DIR') || ' found=' || current_setting('s11.found');

-- 8 — cleanup authority with a due schedule
update public.membership set entitlement_ended_at = now() - interval '61 days', pending_cleanup_at = now() - interval '1 minute'
 where user_id in ('$S_ACT', '$S_LAP');
select 'CHECK|8a|' || case when (public.membership_cleanup_authorised_v1('$S_ACT')->>'authorised')::boolean = false then 'PASS' else 'FAIL' end
       || '|S_ACT authorised=' || (public.membership_cleanup_authorised_v1('$S_ACT')->>'authorised');
select 'CHECK|8b|' || case when (public.membership_cleanup_authorised_v1('$S_LAP')->>'authorised')::boolean = true then 'PASS' else 'FAIL' end
       || '|S_LAP authorised=' || (public.membership_cleanup_authorised_v1('$S_LAP')->>'authorised');

-- 7 — all FOUR cached columns: future now (recompute), past after the membership lapses (propagation)
create temp table s11_cached on commit drop as
select coalesce((select owner_entitled_until > now() from public.posts where id = '$POST'), false)
   and coalesce((select owner_entitled_until > now() from public.post_shares where post_id = '$POST'), false)
   and coalesce((select followed_entitled_until > now() from public.follows where follower_user_id = '$P_ENT' and followed_user_id = '$S_ACT'), false)
   and coalesce((select entitled_until > now() from public.account_directory where user_id = '$S_ACT'), false) as future_all;
update public.membership set apple_status = 2, renewal_date = now() - interval '1 day' where user_id = '$S_ACT';
select 'CHECK|7|' || case when (select future_all from s11_cached)
         and coalesce((select owner_entitled_until <= now() from public.posts where id = '$POST'), false)
         and coalesce((select owner_entitled_until <= now() from public.post_shares where post_id = '$POST'), false)
         and coalesce((select followed_entitled_until <= now() from public.follows where follower_user_id = '$P_ENT' and followed_user_id = '$S_ACT'), false)
         and coalesce((select entitled_until <= now() from public.account_directory where user_id = '$S_ACT'), false)
       then 'PASS' else 'FAIL' end
       || '|recomputed future on all four=' || (select future_all from s11_cached);

rollback;
SQL
} > "$SQL_FILE"

OUT=$(docker exec -i "$DB" psql -U postgres -d postgres -At -q -v ON_ERROR_STOP=1 < "$SQL_FILE" 2>&1); PSQL_EXIT=$?
rm -f "$SQL_FILE"
echo "$OUT" | sed -E 's/^.*NOTICE:  //' | grep -E '^(SETUP|CHECK|NOTE|scope011)' | sed 's/^/  /'

STATE_AFTER=$(psq "$FINGERPRINT")
echo "state after:  $STATE_AFTER"

INCONCLUSIVE=0
if [ $PSQL_EXIT -ne 0 ]; then
  echo "INCONCLUSIVE: the transaction stopped on an error (psql exit $PSQL_EXIT):"
  echo "$OUT" | grep -iE 'error' | head -5 | sed 's/^/    /'
  INCONCLUSIVE=1
fi
echo "$OUT" | grep -q 'NOTE|10|SETUP-ERROR' && { echo "INCONCLUSIVE: case 10 setup error"; INCONCLUSIVE=1; }
[ "$STATE_BEFORE" = "$STATE_AFTER" ] || { echo "INCONCLUSIVE: definitions, grants or row counts changed"; INCONCLUSIVE=1; }

FAILED=""; PASSED=0; MISSING=""
for id in 1 2 3 4a 4b 5 6 7 8a 8b 9 10; do
  line=$(echo "$OUT" | grep -oE "CHECK\|$id\|[A-Z]+" | head -1)
  case "$line" in
    "CHECK|$id|PASS") PASSED=$((PASSED+1)); printf "  %-5s check %s\n" PASS "$id" ;;
    "CHECK|$id|FAIL") FAILED="$FAILED $id";  printf "  %-5s check %s\n" FAIL "$id" ;;
    *)                MISSING="$MISSING $id"; printf "  %-5s check %s\n" MISSING "$id" ;;
  esac
done
[ -z "$MISSING" ] || { echo "INCONCLUSIVE: missing checks:$MISSING"; INCONCLUSIVE=1; }

case "$MODE" in
  before) PREDICTED="1 4a 6 7 8a 10" ;;
  after)  PREDICTED="" ;;
esac
OBS=$(printf '%s\n' $FAILED | sort | tr '\n' ' ' | sed 's/ $//')
PRD=$(printf '%s\n' $PREDICTED | sort | tr '\n' ' ' | sed 's/ $//')
echo "summary: $PASSED passed, $(printf '%s\n' $FAILED | grep -c .) failed of 12 ($MODE); state unchanged: $([ "$STATE_BEFORE" = "$STATE_AFTER" ] && echo yes || echo no)"
[ $INCONCLUSIVE -eq 1 ] && exit 3
if [ "$OBS" = "$PRD" ]; then
  echo "PREDICTION MATCHED ($MODE): failures are exactly [$PRD]"; exit 0
else
  echo "PREDICTION DEVIATION ($MODE): predicted [$PRD], observed [$OBS]"; exit 1
fi
