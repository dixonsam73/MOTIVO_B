#!/usr/bin/env bash
#
# U7c AUTHORISATION BOUNDARY — the destructive worker must not be publicly
# callable. LOCAL DISPOSABLE STACK ONLY.
#
#   supabase db reset --local && ./supabase/tests/u7/auth-probe.sh
#
# WHY THIS EXISTS AS ITS OWN SUITE. config.toml sets verify_jwt = false, so the
# PLATFORM performs no authentication at all: every request reaches the function
# body, whatever it carries. That is correct for this function and it means the
# function's OWN check is the entire authorisation boundary. A boundary that is
# the only one had better be measured rather than reviewed.
#
# THE THING BEING DISPROVED is that "an Authorization header is present" is
# enough. The anon key is a syntactically valid JWT that any client holds, and a
# real user JWT is obtainable by anyone who can sign in. Both must be REFUSED --
# which is precisely why platform JWT verification alone is not sufficient
# authorisation for a destructive endpoint: it would admit AUTH-7.
#
# U7e, 2026-09-03: THE ACCEPTED CREDENTIAL IS NOW CLEANUP_INVOKE_KEY ALONE.
# The service role key is NO LONGER accepted from outside -- AUTH-8 inverted from
# 200 to 401, and that inversion is the point of the change rather than a side
# effect. SERVICE_ROLE_KEY remains the function's INTERNAL database credential.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e

HERE="supabase/tests/u7"; WORK="$HERE/.work/auth"
PORT="${U7_AUTH_PORT:-9185}"; NAME="u7_auth_$$"; NAME2="u7_auth_nosecret_$$"
: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"; export DOCKER_HOST

# A stand-in for the production invocation key. Length and shape deliberately
# unlike a JWT, so nothing can pass by resembling one.
CK="u7e-test-invoke-key-0123456789abcdef"

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^public.ecr.aws/supabase/edge-runtime:' | head -1)"
NET="$(docker network ls --format '{{.Name}}' | grep '^supabase_network_' | head -1)"
KONG="$(docker ps --format '{{.Names}}' | grep '^supabase_kong_' | head -1)"
[ -n "$IMAGE" ] && [ -n "$NET" ] && [ -n "$KONG" ] || { echo "u7: local stack not running" >&2; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK/fn" "$WORK/_shared"
cp supabase/functions/membership_cleanup_v1/index.ts "$WORK/fn/index.ts"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/fn/"
cp -R supabase/functions/_shared/appstore "$WORK/_shared/"

cleanup() { docker rm -f "$NAME" "$NAME2" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" --network "$NET" -p "$PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "SERVICE_ROLE_KEY=$SR" -e "ANON_KEY=$AK" \
  -e "CLEANUP_INVOKE_KEY=$CK" \
  "$IMAGE" start --main-service /probe/fn --port 9000 >/dev/null || exit 1
for _ in $(seq 1 40); do sleep 2; curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$PORT/" && break; done

code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "http://127.0.0.1:$PORT/" \
           ${1:+-H "Authorization: $1"} -H 'content-type: application/json' -d '{"mode":"dry_run"}'; }

echo; echo "U7c authorisation boundary — verify_jwt=false, so this check is the ONLY gate"; echo

is AUTH-1  "$(code "")"                         "401" "AUTH-1 NO Authorization header -> 401"
is AUTH-2  "$(code "Bearer ")"                   "401" "AUTH-2 EMPTY bearer -> 401"
is AUTH-3  "$(code "Bearer $AK")"                "401" "AUTH-3 the ANON key -> 401 (a valid JWT is NOT authorisation)"
is AUTH-4  "$(code "Bearer not-a-token")"        "401" "AUTH-4 a junk bearer -> 401"
is AUTH-5  "$(code "Bearer ${CK}x")"             "401" "AUTH-5 the cleanup key +1 char -> 401"
is AUTH-6  "$(code "Bearer ${CK:0:${#CK}-1}")"   "401" "AUTH-6 the cleanup key -1 char -> 401"
is AUTH-7  "$(code "Bearer wrong-secret-entirely")" "401" "AUTH-7 a wholly wrong secret -> 401"

# THE INVERSION. Until U7e this returned 200. The service role key is authority
# over the entire project; the scheduler needs one capability, so the endpoint no
# longer accepts the broad credential merely because it is broad.
is AUTH-8  "$(code "Bearer $SR")"                "401" "AUTH-8 the SERVICE ROLE key -> 401 (NO LONGER ACCEPTED)"

# A genuine end-user JWT, signed by the local GoTrue secret -- the case
# verify_jwt=true would have admitted, since every authenticated Apple user can
# obtain one.
UJWT=$(python3 - <<PYEOF
import hmac,hashlib,base64,json,time
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
h=b64(json.dumps({"alg":"HS256","typ":"JWT"},separators=(',',':')).encode())
p=b64(json.dumps({"sub":"00000000-0000-0000-0000-0000000000aa","role":"authenticated",
   "aud":"authenticated","exp":int(time.time())+3600},separators=(',',':')).encode())
s=b64(hmac.new(b"super-secret-jwt-token-with-at-least-32-characters-long",
   f"{h}.{p}".encode(),hashlib.sha256).digest())
print(f"{h}.{p}.{s}")
PYEOF
)
is AUTH-9  "$(code "Bearer $UJWT")"              "401" "AUTH-9 a REAL signed user JWT -> 401"
is AUTH-10 "$(code "Bearer $CK")"                "200" "AUTH-10 the CLEANUP INVOKE key -> 200 (not vacuously refusing)"
is AUTH-11 "$(code "$CK")"                       "200" "AUTH-11 scheme prefix optional -- same as appstore_reconcile_v1"
is AUTH-12 "$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X GET "http://127.0.0.1:$PORT/" -H "Authorization: Bearer $CK")" "405" "AUTH-12 GET is refused regardless"

# ---- FAIL CLOSED WHEN THE INVOCATION KEY IS ABSENT FROM THE ENVIRONMENT.
# Measured, never reasoned: an unset CLEANUP_INVOKE_KEY must refuse EVERY caller,
# including one presenting an empty credential, rather than comparing two empty
# strings and admitting anyone. This container is given SERVICE_ROLE_KEY (so the
# database client is fine) and NO invocation key at all.
docker run -d --name "$NAME2" --network "$NET" -p "$((PORT+1)):9000" -v "$PWD/$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "SERVICE_ROLE_KEY=$SR" -e "ANON_KEY=$AK" \
  "$IMAGE" start --main-service /probe/fn --port 9000 >/dev/null 2>&1
for _ in $(seq 1 30); do sleep 2; curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$((PORT+1))/" && break; done
ncode() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "http://127.0.0.1:$((PORT+1))/" \
            ${1:+-H "Authorization: $1"} -H 'content-type: application/json' -d '{"mode":"execute"}'; }
is AUTH-13 "$(ncode "Bearer $CK")"  "401" "AUTH-13 key UNSET, correct key presented -> 401 (fail closed)"
is AUTH-14 "$(ncode "Bearer ")"     "401" "AUTH-14 key UNSET, EMPTY credential -> 401 (two empties never match)"
is AUTH-15 "$(ncode "")"            "401" "AUTH-15 key UNSET, no header -> 401"
is AUTH-16 "$(ncode "Bearer $SR")"  "401" "AUTH-16 key UNSET, service role presented -> 401"

echo; echo "  U7e auth boundary: $PASS passed, $FAIL failed"; echo
[ "$FAIL" -eq 0 ]
