#!/usr/bin/env bash
#
# U4a route gate. LOCAL AND DISPOSABLE ONLY.
#
# Runs the verification battery INSIDE the real Supabase Edge Runtime image,
# because that is the whole point: there is no `deno` on this machine, and a
# result from some other JavaScript runtime would answer a different question.
# The container is throwaway, is never given credentials, and nothing here can
# reach production.
#
# THE PROBE IS DELIBERATELY NOT A FUNCTION UNDER supabase/functions/. Adding one
# there would make it deployable, and `supabase functions deploy` is not scoped
# to the function you name — it has been observed to re-version delete_account_v1
# as a side effect. A test that could ship is not a test worth having.
#
#   ./supabase/tests/u4a/run.sh

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="$HERE/.work"
PORT="${U4A_PORT:-9141}"
NAME="u4a_gate_$$"

die() { echo "u4a: $*" >&2; exit 1; }

command -v docker  >/dev/null 2>&1 || die "docker not found on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH"
command -v openssl >/dev/null 2>&1 || die "openssl not found on PATH"

: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"
export DOCKER_HOST

IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^public.ecr.aws/supabase/edge-runtime:' | head -1)"
[ -n "$IMAGE" ] || die "no supabase/edge-runtime image locally. Run 'supabase start' first."

echo "== U4a route gate =="
echo "  image  $IMAGE"

python3 "$HERE/make-fixtures.py" || die "fixture generation failed"

# Assemble a self-contained main service. Copying rather than mounting the repo
# keeps the container's view minimal and makes the import paths trivial.
rm -rf "$WORK/probe"
mkdir -p "$WORK/probe"
cp "$HERE/probe.ts"                        "$WORK/probe/index.ts"
cp "$WORK/fixtures.json"                   "$WORK/probe/fixtures.json"
cp "$REPO/supabase/functions/deno.json"    "$WORK/probe/deno.json"
cp "$REPO/supabase/functions/deno.lock"    "$WORK/probe/deno.lock"
mkdir -p "$WORK/probe/_shared"
cp -R "$REPO/supabase/functions/_shared/appstore" "$WORK/probe/_shared/"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$NAME" -p "$PORT:9000" -v "$WORK/probe:/probe:ro" \
  "$IMAGE" start --main-service /probe --port 9000 >/dev/null || die "could not start the runtime"

OUT=""
for _ in $(seq 1 40); do
  sleep 3
  OUT="$(curl -s --max-time 240 "http://127.0.0.1:$PORT/" || true)"
  [ -n "$OUT" ] && break
done

if [ -z "$OUT" ]; then
  echo "--- container log ---"; docker logs "$NAME" 2>&1 | tail -30
  die "no response from the probe"
fi

printf '%s' "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print()
print("  runtime:", (d.get("runtime") or {}).get("userAgent"))
for k in ("apple_root_subject","apple_wwdr_subject"):
    if d.get(k): print(f"  {k}: {d[k]}")
print("  mean verification: %s ms" % d.get("verify_ms_avg"))
print()
for l in d.get("lines",[]): print("   ", l)
print()
print("  %d passed, %d failed" % (d.get("pass",0), d.get("fail",0)))
sys.exit(1 if d.get("fail",0) else 0)
'
