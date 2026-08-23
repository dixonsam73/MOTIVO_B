#!/usr/bin/env bash
#
# U4 end-to-end — the REAL appstore_notifications_v1, the REAL database.
# LOCAL DISPOSABLE STACK ONLY.
#
# WHAT THIS ADDS OVER THE OTHER TWO SUITES, and it is the part they cannot
# reach: wiring. modules.ts proves the verifier and the derivation;
# acceptance.sh proves the SQL. Only this proves that an HTTP request arriving
# at the deployed shape produces the right row, the right status code and the
# right absence of a write.
#
# THE ANCHOR IS REPLACED IN A COPY, NOT SWITCHED IN THE SOURCE. Our fixtures are
# signed by a throwaway test CA, so against the shipping constant they would --
# correctly -- all fail. The alternative would be an environment variable that
# relaxes the trust anchor, and a production-reachable switch on the one control
# that makes the endpoint safe is exactly what must not exist. So the harness
# writes a work-dir copy of apple_root_ca_g3.ts carrying the test root, and
# EVERY OTHER BYTE IS THE SHIPPING SOURCE.
#
# THE HAPPY PATH IS THEREFORE PROVEN AGAINST A FAITHFUL COPY, NOT AGAINST APPLE.
# B-28's remaining half -- a genuine Apple-signed payload -- discharges at U4i
# and nowhere earlier.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
# u2/lib.sh sets errexit for its own safety. A test suite must NOT abort on the
# first non-zero command: half these assertions PASS by a command failing, and
# an early exit would report "no failures" by never running them. Unset it here
# deliberately, keeping nounset and pipefail.
set +e

HERE="supabase/tests/u4"
WORK="$HERE/.work/e2e"
PORT="${U4_E2E_PORT:-9161}"
NAME="u4_e2e_$$"
: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"; export DOCKER_HOST

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-7s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-7s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^public.ecr.aws/supabase/edge-runtime:' | head -1)"
[ -n "$IMAGE" ] || { echo "u4: no edge-runtime image" >&2; exit 1; }
NET="$(docker network ls --format '{{.Name}}' | grep '^supabase_network_' | head -1)"
KONG="$(docker ps --format '{{.Names}}' | grep '^supabase_kong_' | head -1)"
[ -n "$NET" ] && [ -n "$KONG" ] || { echo "u4: local stack not running" >&2; exit 1; }

python3 "$HERE/../u4a/make-fixtures.py" >/dev/null || exit 1
FIX="$HERE/../u4a/.work/fixtures.json"

# THE DIRECTORY DEPTH IS PART OF THE COPY. index.ts imports ../_shared/..., so
# flattening it into one directory changes the module graph and the runtime
# fails to boot. Mirroring supabase/functions/<name>/ exactly means the file
# under test is byte-identical AND resolves identically.
rm -rf "$WORK"; mkdir -p "$WORK/fn" "$WORK/_shared"
cp supabase/functions/appstore_notifications_v1/index.ts "$WORK/fn/index.ts"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/fn/"
cp -R supabase/functions/_shared/appstore "$WORK/_shared/"
# The one deliberate substitution, isolated to a single file so a reader can see
# exactly what differs from production.
python3 - "$FIX" "$WORK/_shared/appstore/apple_root_ca_g3.ts" <<'PY'
import json,sys,re,pathlib
fx=json.load(open(sys.argv[1])); p=pathlib.Path(sys.argv[2]); t=p.read_text()
t=re.sub(r'export const APPLE_ROOT_CA_G3_B64 =.*?;',
         'export const APPLE_ROOT_CA_G3_B64 = "%s"; // U4 E2E: TEST CA, not Apple' % fx['test_root_der_b64'],
         t, flags=re.S)
p.write_text(t)
PY

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" --network "$NET" -p "$PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "SERVICE_ROLE_KEY=$SR" \
  -e "APPLE_ASSN_ALLOWED_ENVIRONMENTS=Sandbox" \
  "$IMAGE" start --main-service /probe/fn --port 9000 >/dev/null || exit 1

post() { curl -s -o /tmp/u4_body.$$ -w '%{http_code}' --max-time 200 -X POST \
         "http://127.0.0.1:$PORT/" -H 'Content-Type: application/json' -d "$1"; }
fixture() { python3 -c "import json,sys;print(json.dumps({'signedPayload':json.load(open('$FIX'))['$1']}))"; }
body() { cat /tmp/u4_body.$$ 2>/dev/null; }

echo "== U4 end-to-end (real function, real database) =="
for _ in $(seq 1 40); do sleep 3; [ "$(post "$(fixture good)")" != "000" ] && break; done

# fixture identity + binding
#
# THE BINDING TOKEN IS UNIQUE ACROSS ALL IDENTITIES, so an earlier suite in the
# same run may already hold it. The first version of this simply inserted and
# discarded the result: the insert failed silently, the notification was
# correctly reported UNMAPPED, and three assertions failed in a way that looked
# like a defect in the writer. AN EMPTY OR UNCREATED FIXTURE IS NOT A PASS AND
# MUST NOT BE A SILENT SKIP — so the conflicting row is cleared deliberately and
# the fixture asserts itself before anything depends on it.
A=$(mkuser u4e2e)
TOKEN=$(python3 -c "import json;print(json.load(open('$FIX'))['binding_token'])")
psq "delete from public.membership_binding where binding_token='$TOKEN';" >/dev/null
psq "insert into public.membership_binding (user_id, binding_token) values ('$A','$TOKEN');" >/dev/null
is E0  "$(psq "select count(*) from public.membership_binding where user_id='$A' and binding_token='$TOKEN';")" "1" "fixture binding exists"
psq "delete from public.membership_notification; delete from public.membership; delete from public.membership_notification_reject_stat;" >/dev/null

# ------------------------------------------------------------ Tier 1: no write
is E1  "$(curl -s -o /dev/null -w '%{http_code}' -X GET "http://127.0.0.1:$PORT/")" "405" "GET is refused"
is E2  "$(post '{"signedPayload":"not-a-jws"}')" "400" "structural reject -> 400"
is E3  "$(post 'this is not json')" "400" "non-JSON body -> 400"
is E4  "$(post '{"nope":1}')" "400" "missing signedPayload -> 400"
is E5  "$(post "$(python3 -c "import json;print(json.dumps({'signedPayload':'a.'+'B'*70000+'.c'}))")")" "400" "oversize body -> 400"
is E6  "$(psq "select count(*) from public.membership_notification;")" "0" "Tier 1 wrote NO audit row"
is E7  "$(psq "select count(*) from public.membership_notification_reject_stat;")" "0" "Tier 1 wrote NO counter"

# ------------------------------------------------- Tier 2: bounded counter only
is E8  "$(post "$(fixture tampered_payload)")" "503" "signature failure -> 5xx (G2 as amended)"
is E9  "$(post "$(fixture substituted_root)")" "503" "substituted root -> 5xx"
is E10 "$(post "$(fixture alg_none)")" "400" "alg:none is caught at Tier 1"
is E11 "$(psq "select count(*) from public.membership_notification;")" "0" "Tier 2 wrote NO audit row"
is E12 "$(psq "select reject_count from public.membership_notification_reject_stat where failure_category='signature';")" "2" "Tier 2 counter incremented exactly twice"
is E13 "$(psq "select count(*) from public.membership_notification_reject_stat;")" "1" "...in a single bounded row"

# ------------------------------------------------- Tier 3: verified but UNESTABLISHED
# The token resolves to a live binding and Apple's state is complete — and U4
# STILL writes nothing, because establishing ownership belongs to U5.
is E14 "$(post "$(fixture good)")" "200" "verified notification -> 200"
is E14b "$(body | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['outcome'])")" "ignored" "outcome ignored"
is E14c "$(body | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['failure_category'])")" "unestablished" "...categorised unestablished"
is E14d "$(body | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['needs_establishment'])")" "True" "...and flagged for U5"
is E14e "$(psq "select count(*) from public.membership;")" "0" "THE REAL FUNCTION CREATED NO MEMBERSHIP ROW"

# ---- U5 stand-in. U5 does not exist, so the authoritative row is inserted here
# directly, as a FIXTURE and not a code path. Everything below tests REFRESH.
psq "insert into public.membership (user_id, environment, original_transaction_id, product_id, renewal_date, renewal_info_signed_date, binding_method, bound_at) values ('$A','Sandbox','2000000999999999','com.sdsongs.etudes.connected.monthly', now() - interval '1 day', now() - interval '2 days', 'purchase', now());" >/dev/null
is E15  "$(psq "select count(*) from public.membership where user_id='$A';")" "1" "U5 stand-in row exists"
is E15b "$(post "$(fixture fallback_expires_date)")" "200" "notification against an ESTABLISHED row -> 200"
is E15c "$(body | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['outcome'])")" "applied" "outcome applied"
is E16  "$(psq "select (renewal_info_signed_date > now() - interval '1 day')::text from public.membership where user_id='$A';")" "true" "row refreshed"
# E17 REWRITTEN FOR U5b, 2026-08-23, AND IT WAS TESTING THE WRONG THING IN THE
# WRONG SUITE. It asserted Production entitlement at the end of a chain that is
# SANDBOX END TO END -- the notification must be Sandbox to pass
# APPLE_ASSN_ALLOWED_ENVIRONMENTS, and ingestion applies state to the row of the
# notification's OWN environment, so under D4 no Sandbox notification can ever
# produce entitlement. That is correct behaviour, not a test problem. e2e.sh is
# for wiring by its own description -- "the right row, the right status code, the
# right absence of a write" -- and entitlement derivation belongs to
# acceptance.sh.
#
# So it now asserts the ROW, and in doing so it became a STRONGER assertion than
# it was: this fixture carries a FUTURE expiresDate, so the row looks entitled on
# its face and must still confer nothing. That is D4 observed end to end through
# the real deployed function rather than argued in SQL.
is E17  "$(psq "select environment from public.membership where user_id='$A';")" "Sandbox" "state applied to the notification's OWN environment"
is E17c "$(psq "select (renewal_date > now())::text from public.membership where user_id='$A';")" "true" "...carrying Apple's future paid-through date"
is E17d "$(psq "select public.connected_member('$A');")" "f" "D4: a live-looking SANDBOX row confers NO Production entitlement"
is E17e "$(psq "select public.membership_state('$A');")" "sandbox_only" "...and reports sandbox_only, never expired"
is E17b "$(psq "select binding_method from public.membership where user_id='$A';")" "purchase" "binding_method untouched by ingestion"
is E18 "$(post "$(fixture fallback_expires_date)")" "200" "replay -> 200"
is E19 "$(body | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['outcome'])")" "duplicate" "replay outcome duplicate"
is E20 "$(psq "select delivery_count from public.membership_notification where notification_uuid='ef1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77';")" "2" "delivery_count 2"

is E21 "$(post "$(fixture good_unmapped)")" "200" "unmapped notification -> 200"
is E22 "$(body | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['failure_category'])")" "unmapped" "...categorised unmapped, not rejected"
is E23 "$(post "$(fixture test_notification)")" "200" "Apple TEST notification -> 200"
is E24 "$(psq "select failure_category from public.membership_notification where notification_type='TEST';")" "not_applicable" "TEST is not_applicable"
is E25 "$(post "$(fixture good_production_env)")" "200" "wrong-environment notification -> 200"
is E26 "$(psq "select outcome||'/'||failure_category from public.membership_notification where notification_uuid='af1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77';")" "rejected/unsupported" "...recorded as refused, not applied"

# B-25 end to end: incomplete writes nothing and schedules nothing.
BEFORE=$(psq "select renewal_info_signed_date from public.membership where user_id='$A';")
is E27 "$(post "$(fixture incomplete_no_renewal_info)")" "200" "incomplete notification -> 200"
is E28 "$(body | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['needs_reconciliation'])")" "True" "...requests reconciliation"
is E29 "$(psq "select renewal_info_signed_date from public.membership where user_id='$A';")" "$BEFORE" "...and wrote no state"
is E30 "$(psq "select coalesce(pending_cleanup_at::text,'null') from public.membership where user_id='$A';")" "null" "...and scheduled NO cleanup"

# A tampered inner JWS under a correctly signed envelope must not be applied.
is E31 "$(post "$(fixture tampered_nested_tx)")" "200" "tampered nested tx -> 200"
is E32 "$(psq "select outcome||'/'||coalesce(failure_category,'-') from public.membership_notification where notification_uuid='f0000000-77ac-4f1d-9f36-9a5b2c1d0e77';")" "rejected/unsupported" "...refused rather than applied"

rm -f /tmp/u4_body.$$
echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
