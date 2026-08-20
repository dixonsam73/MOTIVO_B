#!/usr/bin/env bash
#
# U4 full local suite. LOCAL DISPOSABLE STACK ONLY.
#
#   ./supabase/tests/u4/run.sh
#
# Three suites, deliberately separate because they answer different questions
# and a failure in one must not be read as covering another:
#
#   modules     the verifier, the derivation rules and Apple API failure
#               handling — inside the real edge runtime, with fetch injected.
#               Q6's failure modes exist ONLY here; they cannot be induced
#               against Apple.
#   acceptance  the SQL: privilege boundary, ordering, dedupe, quarantine
#               arithmetic, and the B-24/B-25 refusals.
#   e2e         wiring: a real HTTP request to the real function producing the
#               right row, the right status and the right ABSENCE of a write.
#
# Everything verified here is "verified against a faithful local reproduction",
# never "verified in production" — and the happy path is verified against a
# faithful COPY of the function whose trust anchor is a test CA. B-28's real-Apple
# half discharges at U4i and nowhere earlier.

set -uo pipefail
cd "$(dirname "$0")/../../.."
: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"; export DOCKER_HOST

HERE=supabase/tests/u4
WORK="$HERE/.work/modules"
PORT="${U4_MODULES_PORT:-9151}"
NAME="u4_modules_$$"
RC=0

IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^public.ecr.aws/supabase/edge-runtime:' | head -1)"
[ -n "$IMAGE" ] || { echo "u4: no edge-runtime image; run 'supabase start'" >&2; exit 1; }

python3 supabase/tests/u4a/make-fixtures.py >/dev/null || exit 1

rm -rf "$WORK"; mkdir -p "$WORK/_shared"
cp "$HERE/modules.ts"                    "$WORK/index.ts"
cp supabase/tests/u4a/.work/fixtures.json "$WORK/fixtures.json"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/"
cp -R supabase/functions/_shared/appstore "$WORK/_shared/"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== U4 module battery =="
docker run -d --name "$NAME" -p "$PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  "$IMAGE" start --main-service /probe --port 9000 >/dev/null || exit 1

OUT=""
for _ in $(seq 1 40); do sleep 3; OUT="$(curl -s --max-time 240 "http://127.0.0.1:$PORT/" || true)"; [ -n "$OUT" ] && break; done
if [ -z "$OUT" ]; then docker logs "$NAME" 2>&1 | tail -20; exit 1; fi
printf '%s' "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for l in d["lines"]: print("  ", l)
print()
print("  %d passed, %d failed" % (d["pass"], d["fail"]))
sys.exit(1 if d["fail"] else 0)' || RC=1
cleanup

echo
"$HERE/acceptance.sh" || RC=1
echo
"$HERE/e2e.sh" || RC=1

echo
[ "$RC" -eq 0 ] && echo "U4 LOCAL SUITE: ALL GREEN" || echo "U4 LOCAL SUITE: FAILURES ABOVE"
exit "$RC"
