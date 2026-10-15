#!/usr/bin/env bash
# Adult-only gate: local rehearsal of the refusal counter and the adult-only
# upsert. LOCAL STACK ONLY. Starts from the pre-change state, applies the
# production apply file, proves the behaviour through PostgREST with the anon
# key and a real user JWT (psql bypasses RLS, so it can't prove access), then
# rolls back with the production rollback file and proves the local state is
# restored. Cleanup runs on every exit, including failure.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/default/docker.sock}"
container=supabase_db_rlwtqxumfobakvdueugm
docker ps --format '{{.Names}}' | grep -qx "$container" || { echo 'Local DB container unavailable; refusing.' >&2; exit 1; }
psql_() { docker exec -i "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
status=$(supabase status -o json 2>/dev/null)
API=$(printf '%s' "$status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["API_URL"])')
AK=$(printf '%s' "$status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ANON_KEY"])')
SR=$(printf '%s' "$status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')
case "$API" in http://127.0.0.1:*) ;; *) echo "Refusing non-local API $API" >&2; exit 1;; esac

MIG=supabase/migrations/20261015120000_adult_gate_refusal_counter.sql
APPLY=supabase/sql/2026-10-15-adult-gate-apply-production.sql
ROLLBACK=supabase/sql/2026-10-15-adult-gate-rollback-production.sql
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

fp="select coalesce(to_regclass('public.connected_age_refusals')::text,'absent')||':'||md5((select prosrc from pg_proc where oid='public.account_privacy_upsert_v1(text)'::regprocedure))||':'||(select count(*) from public.account_privacy);"
before=$(psql_ -Atqc "$fp")
echo "before: $before"
case "$before" in absent:*) ;; *) fail 'local DB is not in the pre-change state (run supabase db reset --local after moving the migration aside, or roll back)';; esac

uid=""; applied=0
cleanup() {
  if [ -n "$uid" ]; then
    psql_ -q -c "delete from public.account_privacy where user_id='$uid'; delete from auth.users where id='$uid';" >/dev/null 2>&1 || true
  fi
  if [ "$applied" = 1 ]; then
    psql_ -q -c "delete from public.connected_age_refusals;" >/dev/null 2>&1 || true
    psql_ -q -f - < "$ROLLBACK" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# 1. The apply file's body is the migration, verbatim.
body=$(awk '/^SET LOCAL statement_timeout/{on=1;next} /^COMMIT;$/{on=0} on' "$APPLY")
[ "$body" = "$(cat "$MIG")" ] || fail 'apply file body differs from the migration'
pass 'apply file body equals the migration'

# 2. Guards, rolled back: the migration's post-guards pass, and a second run is refused.
{ echo 'BEGIN;'; cat "$MIG"; echo 'ROLLBACK;'; } | psql_ -q >/dev/null || fail 'migration did not apply cleanly in a rolled-back transaction'
pass 'migration applies; its post-guards hold'
second=$( { echo 'BEGIN;'; cat "$MIG" "$MIG"; echo 'ROLLBACK;'; } | psql_ -q 2>&1 || true)
printf '%s' "$second" | grep -q 'adult gate: counter already exists' || fail "second run not refused: $second"
pass 'a second run is refused'

# 3. Rollback refuses before apply.
norb=$(psql_ -q -f - < "$ROLLBACK" 2>&1 || true)
printf '%s' "$norb" | grep -q 'counter not present' || fail "rollback before apply not refused: $norb"
pass 'rollback refuses when nothing is applied'

# 4. Apply exactly as production would, and read the final row.
applied=1
out=$(psql_ -At -f - < "$APPLY")
last=$(printf '%s\n' "$out" | tail -1)
[ "$last" = 'applied|0|t|f|t' ] || fail "unexpected final row: $last"
pass "apply final row: $last"

# 5. Through PostgREST.
code() { curl -s -o /tmp/adult-gate-resp.$$ -w '%{http_code}' "$@"; }
rpc() { code -X POST "$API/rest/v1/rpc/$1" -H "apikey: $AK" -H "Authorization: Bearer $2" -H 'content-type: application/json' -d "$3"; }
# The apply NOTIFYs a schema reload; wait for it (an invalid reason is a 400 once the RPC is known).
for _ in $(seq 1 20); do
  [ "$(rpc record_connected_age_refusal_v1 "$AK" '{"p_reason":"x"}')" = 400 ] && break; sleep 0.5
done

for r in under_18 unconfirmed_adult declined unavailable ios_update_needed under_18; do
  c=$(rpc record_connected_age_refusal_v1 "$AK" "{\"p_reason\":\"$r\"}")
  [ "$c" = 204 ] || [ "$c" = 200 ] || fail "anon record $r -> HTTP $c $(cat /tmp/adult-gate-resp.$$)"
done
pass 'anon can record every reason'
c=$(rpc record_connected_age_refusal_v1 "$AK" '{"p_reason":"band_13_17"}')
[ "$c" = 400 ] || fail "invalid reason -> HTTP $c (want 400)"
c=$(rpc record_connected_age_refusal_v1 "$AK" '{"p_reason":null}')
[ "$c" = 400 ] || fail "null reason -> HTTP $c (want 400)"
pass 'an invalid or null reason is refused (400)'

counts=$(psql_ -Atqc "select string_agg(reason||'='||refusals, ',' order by reason) from public.connected_age_refusals where month=date_trunc('month', now() at time zone 'utc')::date;")
[ "$counts" = 'declined=1,ios_update_needed=1,unavailable=1,unconfirmed_adult=1,under_18=2' ] || fail "counts: $counts"
cols=$(psql_ -Atqc "select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema='public' and table_name='connected_age_refusals';")
[ "$cols" = 'month,reason,refusals' ] || fail "columns: $cols"
pass "counts per reason this month: $counts; columns are month,reason,refusals only"

c=$(code "$API/rest/v1/connected_age_refusals?select=*" -H "apikey: $AK" -H "Authorization: Bearer $AK")
[ "$c" = 401 ] || [ "$c" = 403 ] || fail "anon read -> HTTP $c $(cat /tmp/adult-gate-resp.$$)"
c=$(code -X POST "$API/rest/v1/connected_age_refusals" -H "apikey: $AK" -H "Authorization: Bearer $AK" -H 'content-type: application/json' \
  -d "{\"month\":\"2026-10-01\",\"reason\":\"declined\",\"refusals\":999}")
[ "$c" = 401 ] || [ "$c" = 403 ] || fail "anon insert -> HTTP $c"
pass 'anon can neither read nor write the counter table'

email="adultgate-$(uuidgen | tr 'A-Z' 'a-z' | cut -c1-8)@local.invalid"; pw="ag-$(uuidgen)"
uid=$(curl -s -X POST "$API/auth/v1/admin/users" -H "apikey: $SR" -H "Authorization: Bearer $SR" -H 'content-type: application/json' \
  -d "{\"email\":\"$email\",\"password\":\"$pw\",\"email_confirm\":true}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
tok=$(curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $AK" -H 'content-type: application/json' \
  -d "{\"email\":\"$email\",\"password\":\"$pw\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
c=$(code "$API/rest/v1/connected_age_refusals?select=*" -H "apikey: $AK" -H "Authorization: Bearer $tok")
[ "$c" = 401 ] || [ "$c" = 403 ] || fail "authenticated read -> HTTP $c $(cat /tmp/adult-gate-resp.$$)"
c=$(rpc record_connected_age_refusal_v1 "$tok" '{"p_reason":"declined"}')
[ "$c" = 204 ] || [ "$c" = 200 ] || fail "authenticated record -> HTTP $c"
pass 'a signed-in member can record but not read'

c=$(rpc account_privacy_upsert_v1 "$tok" '{"p_age_band":"band_13_17"}')
[ "$c" = 400 ] || fail "upsert band_13_17 -> HTTP $c (want 400) $(cat /tmp/adult-gate-resp.$$)"
[ "$(psql_ -Atqc "select count(*) from public.account_privacy where user_id='$uid';")" = 0 ] || fail 'a refused band wrote a row'
c=$(rpc account_privacy_upsert_v1 "$tok" '{"p_age_band":"band_18_plus"}')
[ "$c" = 200 ] || fail "upsert band_18_plus -> HTTP $c $(cat /tmp/adult-gate-resp.$$)"
grep -q '"o_age_band":"band_18_plus"' /tmp/adult-gate-resp.$$ || fail "upsert response: $(cat /tmp/adult-gate-resp.$$)"
c=$(rpc account_privacy_upsert_v1 "$tok" '{"p_age_band":"band_13_17"}')
[ "$c" = 400 ] || fail 'an adult row could be moved to band_13_17'
[ "$(psql_ -Atqc "select age_band from public.account_privacy where user_id='$uid';")" = band_18_plus ] || fail 'adult row changed'
pass 'upsert refuses band_13_17 (no row, and an adult row cannot be moved); band_18_plus works'
rm -f /tmp/adult-gate-resp.$$

# 6. Rollback refuses while counts exist, then restores once they are cleared.
held=$(psql_ -q -f - < "$ROLLBACK" 2>&1 || true)
printf '%s' "$held" | grep -q 'the counter holds counts' || fail "rollback with counts not refused: $held"
pass 'rollback refuses while the counter holds counts'
psql_ -q -c "delete from public.account_privacy where user_id='$uid'; delete from auth.users where id='$uid';"
uid=""
psql_ -q -c "delete from public.connected_age_refusals;"
rb=$(psql_ -At -f - < "$ROLLBACK" | tail -1)
[ "$rb" = 'rolled back|t|t' ] || fail "unexpected rollback row: $rb"
applied=0
after=$(psql_ -Atqc "$fp")
echo "after:  $after"
[ "$before" = "$after" ] || fail 'local state not restored (counter, upsert body or account_privacy count)'
pass 'rollback final row as expected; local state restored exactly'
echo 'ALL PASS'
