#!/usr/bin/env bash
#
# U5d end-to-end — the REAL membership_attest_v1, the REAL database, a
# programmable Apple stand-in. LOCAL DISPOSABLE STACK ONLY.
#
# WHAT THIS ADDS OVER THE OTHER SUITES. modules.ts proves the claim boundary and
# the taxonomy; acceptance.sh proves the SQL. Only this proves the WIRING — that
# an authenticated HTTP request produces the right row, the right status, the
# right absence of a write, and, for A30, THE RIGHT OUTBOUND CALL ORDER.
#
# A30 IS AN ORDERING ASSERTION, NOT AN OUTCOME ASSERTION. An implementation that
# establishes on the strength of the PUT's own 200 reaches an identical final row
# and is wrong. The stub records every request, and E5d-A30* assert the sequence
# PUT -> GET -> establish. A correct row in the wrong order FAILS here.
#
# THE ANCHOR IS REPLACED IN A COPY, NOT SWITCHED IN THE SOURCE — same discipline
# as U4's e2e, and for the same reason: a production-reachable switch on the one
# control that makes verification meaningful is exactly what must not exist.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e   # half these assertions PASS by a command failing

HERE="supabase/tests/u5"
WORK="$HERE/.work/e2e"
PORT="${U5_E2E_PORT:-9171}"
STUB_PORT="${U5_STUB_PORT:-9172}"
NAME="u5_e2e_$$"; STUB="u5_stub_$$"
: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"; export DOCKER_HOST

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-11s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-11s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^public.ecr.aws/supabase/edge-runtime:' | head -1)"
NET="$(docker network ls --format '{{.Name}}' | grep '^supabase_network_' | head -1)"
KONG="$(docker ps --format '{{.Names}}' | grep '^supabase_kong_' | head -1)"
[ -n "$IMAGE" ] && [ -n "$NET" ] && [ -n "$KONG" ] || { echo "u5: local stack not running" >&2; exit 1; }

python3 supabase/tests/u4a/make-fixtures.py >/dev/null || exit 1
FIX="supabase/tests/u4a/.work/fixtures.json"
TOK_OURS=$(python3 -c "import json;print(json.load(open('$FIX'))['binding_token'])")
TOK_OTHER="bbbbbbbb-0000-4000-8000-000000000009"

rm -rf "$WORK"; mkdir -p "$WORK/fn" "$WORK/_shared" "$WORK/stub"
cp supabase/functions/membership_attest_v1/index.ts "$WORK/fn/index.ts"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/fn/"
cp -R supabase/functions/_shared/appstore "$WORK/_shared/"
cp "$HERE/applestub.ts" "$WORK/stub/index.ts"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/stub/"
cp "$FIX" "$WORK/fixtures.json"
python3 - "$FIX" "$WORK/_shared/appstore/apple_root_ca_g3.ts" <<'PY'
import json,sys,re,pathlib
fx=json.load(open(sys.argv[1])); p=pathlib.Path(sys.argv[2]); t=p.read_text()
t=re.sub(r'export const APPLE_ROOT_CA_G3_B64 =.*?;',
         'export const APPLE_ROOT_CA_G3_B64 = "%s"; // U5 E2E: TEST CA, not Apple' % fx['test_root_der_b64'],
         t, flags=re.S)
p.write_text(t)
PY

cleanup() { docker rm -f "$NAME" "$STUB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$STUB" --network "$NET" -p "$STUB_PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  "$IMAGE" start --main-service /probe/stub --port 9000 >/dev/null || exit 1

docker run -d --name "$NAME" --network "$NET" -p "$PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "SERVICE_ROLE_KEY=$SR" -e "ANON_KEY=$AK" \
  -e "APPLE_ATTEST_ALLOWED_ENVIRONMENTS=Sandbox" \
  -e "APPLE_API_BASE_URL_SANDBOX=http://$STUB:9000" \
  -e "APPLE_IAP_KEY_ID=TESTKEYID" -e "APPLE_IAP_ISSUER_ID=test-issuer" \
  -e "APPLE_IAP_BUNDLE_ID=com.sdsongs.etudes" \
  -e "APPLE_IAP_P8_B64=$(python3 -c "import json;print(json.load(open('$FIX'))['p8_b64'])")" \
  "$IMAGE" start --main-service /probe/fn --port 9000 >/dev/null || exit 1

ready() { for _ in $(seq 1 40); do sleep 2; curl -s --max-time 20 "$1" >/dev/null 2>&1 && return 0; done; return 1; }
ready "http://127.0.0.1:$STUB_PORT/__calls" || { docker logs "$STUB" 2>&1 | tail -20; exit 1; }

STUBURL="http://127.0.0.1:$STUB_PORT"
ATT="http://127.0.0.1:$PORT/"
scenario() { curl -s -X POST "$STUBURL/__control" -H 'content-type: application/json' -d "$1" >/dev/null; }
calls()    { curl -s "$STUBURL/__calls" | python3 -c 'import json,sys;print(",".join(json.load(sys.stdin)["calls"]))'; }
attest()   { # $1 jwt, $2 fixture name
  local j; j=$(python3 -c "import json;print(json.load(open('$FIX'))['$2'])")
  curl -s -X POST "$ATT" -H "Authorization: Bearer $1" -H 'content-type: application/json' \
    -d "$(python3 -c "import json,sys;print(json.dumps({'jws':sys.argv[1]}))" "$j")"
}
code()     { local j; j=$(python3 -c "import json;print(json.load(open('$FIX'))['$2'])")
  curl -s -o /dev/null -w '%{http_code}' -X POST "$ATT" -H "Authorization: Bearer $1" \
    -H 'content-type: application/json' \
    -d "$(python3 -c "import json,sys;print(json.dumps({'jws':sys.argv[1]}))" "$j")"; }
field()    { python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1],""))' "$1"; }

echo
echo "U5d e2e — membership_attest_v1 against a programmable Apple"
echo

# ---- identities. The binding token is FORCED to the fixture value so the
# pre-minted JWSs represent "our token". A fixture manipulation, labelled.
A=$(mkuser u5da); TA=$(tokenfor u5da)
B=$(mkuser u5db); TB=$(tokenfor u5db)
psq "select set_config('request.jwt.claims','{\"sub\":\"$A\"}',false); select public.ensure_membership_binding();" >/dev/null
psq "update public.membership_binding set binding_token='$TOK_OURS' where user_id='$A';" >/dev/null
is E5d-0 "$(psq "select binding_token from public.membership_binding where user_id='$A';")" "$TOK_OURS" "fixture binding token in place"

# ================================================== auth boundary
is E5d-1 "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$ATT" -H 'content-type: application/json' -d '{"jws":"x"}')" "401" "no Authorization -> 401"
is E5d-2 "$(code "not-a-jwt" attest_ok)" "401" "invalid session -> 401"
is E5d-3 "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$ATT" -H "Authorization: Bearer $TA" -H 'content-type: application/json' -d '{}')" "400" "missing jws -> 400"
is E5d-4 "$(psq "select count(*) from public.membership where user_id in ('$A','$B');")" "0" "no membership row from any refused request"

# ================================================== claim boundary (B-31)
scenario '{"txBefore":"attest_ok","txAfter":"attest_ok","ri":"attest_ri"}'
is E5d-5 "$(code "$TA" attest_foreign_app)" "422" "another app's genuine JWS -> 422"
is E5d-6 "$(attest "$TA" attest_foreign_app | field category)" "foreign_app" "...categorised foreign_app"
is E5d-7 "$(attest "$TA" attest_foreign_app | field terminal)" "True" "...and terminal"
is E5d-8 "$(code "$TA" attest_foreign_product)" "422" "wrong product -> 422"
is E5d-9 "$(code "$TA" attest_env_production)" "422" "Production while only Sandbox attestable -> 422"
is E5d-10 "$(code "$TA" attest_family_shared)" "422" "FAMILY_SHARED -> 422"
is E5d-11 "$(calls)" "" "A REFUSED CLAIM NEVER REACHED APPLE"
is E5d-12 "$(psq "select count(*) from public.membership where user_id in ('$A','$B');")" "0" "...and wrote nothing"

# ================================================== new purchase
scenario '{"txBefore":"attest_ok","txAfter":"attest_ok","ri":"attest_ri"}'
R=$(attest "$TA" attest_ok)
is E5d-13 "$(printf '%s' "$R" | field outcome)" "established" "new purchase establishes"
is E5d-14 "$(psq "select binding_method from public.membership where user_id='$A';")" "purchase" "provenance derived as purchase"
is E5d-15 "$(psq "select environment from public.membership where user_id='$A';")" "Sandbox" "environment from the VERIFIED claims"
is E5d-16 "$(psq "select original_transaction_id from public.membership where user_id='$A';")" "2000000999999999" "otid from the verified claims"
is E5d-17 "$(calls)" "GET:2000000999999999" "live Apple read happened, and NO PUT was needed"
is E5d-18 "$(psq "select coalesce(pending_cleanup_at::text,'null')||'/'||coalesce(entitlement_ended_at::text,'null') from public.membership where user_id='$A';")" "null/null" "F11 preserved through the endpoint"
is E5d-19 "$(psq "select public.connected_member('$A');")" "f" "D4: a Sandbox row confers no Production entitlement"
is E5d-20 "$(psq "select public.membership_state('$A');")" "sandbox_only" "...and reports sandbox_only"

# ---- idempotent refresh: ownership provenance is IMMUTABLE
scenario '{"txBefore":"attest_ok","txAfter":"attest_ok","ri":"attest_ri"}'
R=$(attest "$TA" attest_ok)
is E5d-21 "$(printf '%s' "$R" | field outcome)" "already_established" "second attestation refreshes, never re-establishes"
is E5d-22 "$(psq "select binding_method from public.membership where user_id='$A';")" "purchase" "binding_method NOT re-provenanced"
is E5d-23 "$(psq "select count(*) from public.membership where user_id='$A';")" "1" "still one row"

# ================================================== A30 — LEGACY CLAIM
# Apple reports no token before the PUT and our token after it. THE ORDER IS THE
# ASSERTION: a correct row reached in the wrong order is a failure.
psq "delete from public.membership where user_id='$A';" >/dev/null
scenario '{"txBefore":"attest_no_token","txAfter":"attest_ok","ri":"attest_ri"}'
R=$(attest "$TA" attest_no_token)
is E5d-A30a "$(printf '%s' "$R" | field outcome)" "established" "legacy claim establishes"
is E5d-A30b "$(printf '%s' "$R" | field claimed)" "True" "...via the claim path"
is E5d-A30c "$(calls)" "GET:2000000999999999,PUT:2000000999999999,GET:2000000999999999,GET:2000000999999999" "EXACT OUTBOUND ORDER: read, PUT, re-read, re-read"
is E5d-A30d "$(psq "select binding_method from public.membership where user_id='$A';")" "legacy_claim" "provenance derived as legacy_claim"
# The PUT must be preceded by a read and FOLLOWED by at least one independent read.
PUTIDX=$(calls | tr ',' '\n' | grep -n '^PUT' | cut -d: -f1)
NCALLS=$(calls | tr ',' '\n' | wc -l | tr -d ' ')
is E5d-A30e "$( [ "$PUTIDX" -lt "$NCALLS" ] && echo yes || echo no)" "yes" "at least one Apple READ happened AFTER the PUT"
is E5d-A30f "$(calls | tr ',' '\n' | sed -n "$((PUTIDX+1))p" | cut -d: -f1)" "GET" "...and the very next call is a read, not a write"

# ================================================== propagation delay
psq "delete from public.membership where user_id='$A';" >/dev/null
scenario '{"txBefore":"attest_no_token","txAfter":"attest_no_token","ri":"attest_ri"}'
R=$(attest "$TA" attest_no_token)
is E5d-24 "$(printf '%s' "$R" | field outcome)" "pending" "propagation -> pending"
is E5d-25 "$(printf '%s' "$R" | field wrote)" "False" "...wrote nothing"
is E5d-26 "$(printf '%s' "$R" | field retry)" "True" "...and asks for a later attestation"
is E5d-27 "$(psq "select count(*) from public.membership where user_id='$A';")" "0" "NO membership row on propagation delay"
is E5d-28 "$(calls | tr ',' '\n' | grep -c '^PUT')" "1" "the PUT was issued exactly once"

# ---- and a later attestation completes it, once Apple surfaces the token
scenario '{"txBefore":"attest_ok","txAfter":"attest_ok","ri":"attest_ri"}'
R=$(attest "$TA" attest_no_token)
is E5d-29 "$(printf '%s' "$R" | field outcome)" "established" "a LATER attestation completes the claim"
is E5d-30 "$(calls | tr ',' '\n' | grep -c '^PUT')" "0" "...without a second PUT — Apple already had our token"

# ================================================== orphan rebind
psq "delete from public.membership where user_id='$A';" >/dev/null
scenario '{"txBefore":"attest_other_token","txAfter":"attest_ok","ri":"attest_ri"}'
R=$(attest "$TA" attest_no_token)
is E5d-31 "$(printf '%s' "$R" | field outcome)" "established" "orphan token permits rebind"
is E5d-32 "$(psq "select binding_method from public.membership where user_id='$A';")" "legacy_claim" "...recorded as legacy_claim"
is E5d-33 "$(calls | tr ',' '\n' | grep -c '^PUT')" "1" "...via one Set App Account Token"

# ================================================== LIVE-BINDING CONFLICT
# The same foreign token, but now it belongs to a LIVE binding. Nothing may be
# granted, nothing overwritten, and Apple must never be asked to overwrite it.
psq "delete from public.membership where user_id='$A';" >/dev/null
psq "select set_config('request.jwt.claims','{\"sub\":\"$B\"}',false); select public.ensure_membership_binding();" >/dev/null
psq "update public.membership_binding set binding_token='$TOK_OTHER' where user_id='$B';" >/dev/null
scenario '{"txBefore":"attest_other_token","txAfter":"attest_ok","ri":"attest_ri"}'
R=$(attest "$TA" attest_ok)
is E5d-34 "$(printf '%s' "$R" | field outcome)" "conflict" "a token on another LIVE binding -> conflict"
is E5d-35 "$(psq "select count(*) from public.membership where user_id='$A';")" "0" "...no membership row"
is E5d-36 "$(calls | tr ',' '\n' | grep -c '^PUT')" "0" "NO Set App Account Token — we never overwrite a live binding"
is E5d-37 "$(psq "select conflict_kind from public.membership_binding_conflict where user_id='$A';")" "live_binding_mismatch" "...recorded for operator disposition"

# ================================================== terminal Apple refusal
psq "delete from public.membership_binding_conflict where user_id='$A';" >/dev/null
psq "update public.membership_binding set binding_token='$TOK_OURS' where user_id='$A';" >/dev/null
scenario '{"txBefore":"attest_no_token","txAfter":"attest_ok","ri":"attest_ri","putHttp":400,"putErrorCode":4000185}'
R=$(attest "$TA" attest_no_token)
is E5d-38 "$(printf '%s' "$R" | field outcome)" "terminal_refusal" "Family Sharing refusal is TERMINAL"
is E5d-39 "$(printf '%s' "$R" | field reason)" "family_transaction_not_supported" "...named from Apple's own code"
is E5d-40 "$(psq "select count(*) from public.membership where user_id='$A';")" "0" "...and wrote nothing"
is E5d-41 "$(calls | tr ',' '\n' | grep -c '^GET')" "1" "...and did NOT re-read after a permanent refusal"

# ================================================== retryable Apple failures
scenario '{"txBefore":"attest_no_token","txAfter":"attest_ok","ri":"attest_ri","putHttp":500}'
is E5d-42 "$(code "$TA" attest_no_token)" "502" "5xx on the PUT -> 502"
is E5d-43 "$(psq "select count(*) from public.membership where user_id='$A';")" "0" "...wrote nothing"

scenario '{"txBefore":"attest_ok","txAfter":"attest_ok","ri":"attest_ri","statusHttp":500}'
is E5d-44 "$(code "$TA" attest_ok)" "502" "Apple status read 5xx -> 502"
is E5d-45 "$(attest "$TA" attest_ok | field wrote)" "False" "...and says explicitly that nothing was written"
is E5d-46 "$(psq "select count(*) from public.membership where user_id='$A';")" "0" "...no row"

scenario '{"txBefore":"attest_ok","txAfter":"attest_ok","ri":"attest_ri","empty":true}'
is E5d-47 "$(code "$TA" attest_ok)" "502" "Apple returning no matching subscription -> 502, never 'not entitled'"
is E5d-48 "$(psq "select count(*) from public.membership where user_id='$A';")" "0" "...no row"

# ================================================== structural (B-31)
SRC=supabase/functions/membership_attest_v1/index.ts

# THESE ASSERTIONS MUST TARGET CODE, NOT PROSE, and the first version of three of
# them did not. index.ts states "THIS FUNCTION NEVER CALLS verifyAppleJWS" in its
# own header, so a bare grep for that identifier finds the sentence claiming the
# property and reports a violation. The file explaining a rule defeated the check
# for the rule. Comments are stripped first — the same correction U5c-34 needed,
# which is why it is worth writing down twice.
codeonly() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/", "", t, flags=re.S)      # block comments
t=re.sub(r"^\s*//.*$", "", t, flags=re.M)       # whole-line comments
t=re.sub(r"//.*$", "", t, flags=re.M)            # trailing comments
print(len(re.findall(sys.argv[2], t)))' "$1" "$2"; }

is E5d-STRUCT1 "$(codeonly $SRC 'verifyAttestationJWS')" "2" "endpoint imports AND calls verifyAttestationJWS"
is E5d-STRUCT2 "$(codeonly $SRC 'verifyAppleJWS')" "0" "ENDPOINT NEVER CALLS THE BARE VERIFIER — B-31's structural half"
is E5d-STRUCT3 "$(grep -cE 'body\.(user_id|uid|environment|original_transaction_id)' $SRC)" "0" "no identity or Apple key is ever read from the body"
is E5d-STRUCT4 "$(grep -cE 'console\.(log|error)[^)]*clientJws' $SRC)" "0" "the client JWS is never logged"
is E5d-STRUCT5 "$(codeonly $SRC 'membership_establish_v1')" "1" "exactly one establishment call site"
is E5d-STRUCT6 "$(grep -cE 'insert into|INSERT INTO' $SRC)" "0" "the endpoint holds no SQL of its own"
is E5d-STRUCT7 "$(psq "select count(*) from information_schema.table_privileges where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated','service_role','PUBLIC');")" "0" "U5d widened no table privilege"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
