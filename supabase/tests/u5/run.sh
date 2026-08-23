#!/usr/bin/env bash
#
# U5 local suite. LOCAL DISPOSABLE STACK ONLY.
#
#   supabase db reset --local && ./supabase/tests/u5/run.sh
#
# Two suites, deliberately separate because they answer different questions:
#
#   modules     U5c — the attestation claim boundary and the Set App Account
#               Token taxonomy, inside the real edge runtime with fetch
#               injected. No database, no network.
#   acceptance  U5b — the SQL: environment separation, the establishment
#               writer, the two grants, and F11.
#   client-structural
#               U5e — properties of the CLIENT source that no unit test can
#               reach: the absences. Needs no database and no container.
#   e2e         U5d — wiring: the real endpoint, the real database, and a
#               programmable Apple whose CALL LOG is how A30's ordering is
#               proven. A correct row in the wrong order fails here.
#
# Everything verified here is "verified against a faithful local reproduction",
# never "verified in production", and the module battery runs against a faithful
# COPY of the shipping modules whose trust anchor is a test CA.

set -uo pipefail
cd "$(dirname "$0")/../../.."
: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"; export DOCKER_HOST

HERE=supabase/tests/u5
WORK="$HERE/.work/modules"
PORT="${U5_MODULES_PORT:-9161}"
NAME="u5_modules_$$"
RC=0

IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^public.ecr.aws/supabase/edge-runtime:' | head -1)"
[ -n "$IMAGE" ] || { echo "u5: no edge-runtime image; run 'supabase start'" >&2; exit 1; }

python3 supabase/tests/u4a/make-fixtures.py >/dev/null || exit 1

rm -rf "$WORK"; mkdir -p "$WORK/_shared"
cp "$HERE/modules.ts"                     "$WORK/index.ts"
cp supabase/tests/u4a/.work/fixtures.json "$WORK/fixtures.json"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/"
cp -R supabase/functions/_shared/appstore "$WORK/_shared/"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== U5c module battery =="
docker run -d --name "$NAME" -p "$PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  "$IMAGE" start --main-service /probe --port 9000 >/dev/null || exit 1

OUT=""
for _ in $(seq 1 40); do sleep 3; OUT="$(curl -s --max-time 240 "http://127.0.0.1:$PORT/" || true)"; [ -n "$OUT" ] && break; done
if [ -z "$OUT" ]; then docker logs "$NAME" 2>&1 | tail -30; exit 1; fi
printf '%s' "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for l in d["lines"]: print("  ", l)
print()
print("  %d passed, %d failed" % (d["pass"], d["fail"]))
sys.exit(1 if d["fail"] else 0)' || RC=1
cleanup

echo
"$HERE/client-structural.sh" || RC=1

echo
"$HERE/acceptance.sh" || RC=1

echo
"$HERE/e2e.sh" || RC=1

echo
[ "$RC" -eq 0 ] && echo "U5 LOCAL SUITE: ALL GREEN" || echo "U5 LOCAL SUITE: FAILURES ABOVE"
exit "$RC"
