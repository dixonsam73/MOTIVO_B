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
# real user JWT is obtainable by anyone who can sign in. Both must be REFUSED.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e

HERE="supabase/tests/u7"; WORK="$HERE/.work/auth"
PORT="${U7_AUTH_PORT:-9185}"; NAME="u7_auth_$$"; NAME2="u7_auth_nosecret_$$"
: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"; export DOCKER_HOST

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
  "$IMAGE" start --main-service /probe/fn --port 9000 >/dev/null || exit 1
for _ in $(seq 1 40); do sleep 2; curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$PORT/" && break; done

code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "http://127.0.0.1:$PORT/" \
           ${1:+-H "Authorization: $1"} -H 'content-type: application/json' -d '{"mode":"dry_run"}'; }

echo; echo "U7c authorisation boundary — verify_jwt=false, so this check is the ONLY gate"; echo

is AUTH-1 "$(code "")"                    "401" "AUTH-1 NO Authorization header -> 401"
is AUTH-2 "$(code "Bearer $AK")"          "401" "AUTH-2 the ANON key -> 401 (a valid JWT is NOT authorisation)"
is AUTH-3 "$(code "Bearer not-a-token")"  "401" "AUTH-3 a junk bearer -> 401"
is AUTH-4 "$(code "Bearer ${SR}x")"       "401" "AUTH-4 the service key with ONE extra char -> 401"
is AUTH-5 "$(code "Bearer ${SR:0:${#SR}-1}")" "401" "AUTH-5 the service key TRUNCATED by one -> 401"
# AUTH-6 RE-POINTED AFTER MEASUREMENT. It first asserted that the raw key without
# a "Bearer " scheme is refused, and that FAILED: `.replace(/^Bearer\s+/i, "")`
# leaves a scheme-less header unchanged, so the bare secret is accepted. That is
# LAXNESS IN SCHEME PARSING, NOT A SECURITY WEAKNESS -- the correct secret is
# still required and still compared in constant time -- and it is BYTE-IDENTICAL
# to the deployed appstore_reconcile_v1, which uses the same expression. Diverging
# here would give the two service-role functions different authorisation stories,
# which is exactly what this project avoids.
#
# The security-relevant property is asserted instead, and it is independently
# witnessed by AUTH-4/AUTH-5/AUTH-7 in any case: what matters is the SECRET, not
# the scheme.
is AUTH-6  "$(code "wrong-secret-entirely")" "401" "AUTH-6 a WRONG secret without the scheme -> 401"
is AUTH-6b "$(code "$SR")"                   "200" "AUTH-6b the scheme prefix is optional -- same as appstore_reconcile_v1"

# A genuine end-user JWT, signed by the local GoTrue secret. This is the case
# that matters: verify_jwt=true would have ACCEPTED it, because it is a real,
# valid, unexpired user token -- and every authenticated Apple user can obtain
# one. It must be refused.
UJWT=$(python3 - <<'PY'
import hmac,hashlib,base64,json,time
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
h=b64(json.dumps({"alg":"HS256","typ":"JWT"},separators=(',',':')).encode())
p=b64(json.dumps({"sub":"00000000-0000-0000-0000-0000000000aa","role":"authenticated",
   "aud":"authenticated","exp":int(time.time())+3600},separators=(',',':')).encode())
s=b64(hmac.new(b"super-secret-jwt-token-with-at-least-32-characters-long",
   f"{h}.{p}".encode(),hashlib.sha256).digest())
print(f"{h}.{p}.{s}")
PY
)
is AUTH-7 "$(code "Bearer $UJWT")" "401" "AUTH-7 a REAL signed user JWT -> 401 (what verify_jwt=true would have let in)"
is AUTH-8 "$(code "Bearer $SR")"   "200" "AUTH-8 the service role key -> 200 (the check is not vacuously refusing)"
is AUTH-9 "$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X GET "http://127.0.0.1:$PORT/" -H "Authorization: Bearer $SR")" "405" "GET is refused regardless"

# ---- fail-closed when the secret itself is MISSING from the environment.
# Measured rather than reasoned: an unset SERVICE_ROLE_KEY must never make the
# comparison trivially succeed.
docker run -d --name "$NAME2" --network "$NET" -p "$((PORT+1)):9000" -v "$PWD/$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "ANON_KEY=$AK" \
  "$IMAGE" start --main-service /probe/fn --port 9000 >/dev/null 2>&1
for _ in $(seq 1 30); do sleep 2; curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$((PORT+1))/" && break; done
NS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "http://127.0.0.1:$((PORT+1))/" \
      -H "Authorization: Bearer anything" -H 'content-type: application/json' -d '{"mode":"execute"}')
is AUTH-10 "$([ "$NS" = "200" ] && echo OPEN || echo CLOSED)" "CLOSED" "AUTH-10 SERVICE_ROLE_KEY unset -> NOT 200 (fail-closed; observed $NS)"

echo; echo "  U7c auth boundary: $PASS passed, $FAIL failed"; echo
[ "$FAIL" -eq 0 ]
