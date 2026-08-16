#!/usr/bin/env bash
#
# U2 shared helpers. LOCAL DISPOSABLE STACK ONLY.
#
# CREDENTIALS ARE LOADED DYNAMICALLY FROM THE RUNNING LOCAL STACK and are never
# written down here. Earlier revisions inlined the Supabase CLI's well-known
# local demo JWTs. Those authenticate to nothing beyond 127.0.0.1 and were not
# production secrets — but they are JWT-shaped, so a remote secret scanner has
# no way to tell them apart from something that matters. Removing them costs
# nothing and removes the ambiguity.
#
# There is deliberately NO hard-coded fallback. If the local stack is not
# running, this fails loudly rather than quietly reaching for a stale constant.

set -euo pipefail

# ---------------------------------------------------------------- credentials

_u2_die() { echo "u2: $*" >&2; exit 1; }

command -v supabase >/dev/null 2>&1 || _u2_die "supabase CLI not found on PATH"
command -v jq        >/dev/null 2>&1 || _u2_die "jq not found on PATH"

_U2_STATUS="$(supabase status -o json 2>/dev/null || true)"
[ -n "$_U2_STATUS" ] || _u2_die \
  "could not read 'supabase status -o json'. Is the local stack running?
   Try:  export DOCKER_HOST=\"unix://\$HOME/.colima/default/docker.sock\" && supabase start"

export API=$(printf '%s' "$_U2_STATUS" | jq -r '.API_URL // empty')
export AK=$(printf  '%s' "$_U2_STATUS" | jq -r '.ANON_KEY // empty')
export SR=$(printf  '%s' "$_U2_STATUS" | jq -r '.SERVICE_ROLE_KEY // empty')

[ -n "$API" ] || _u2_die "API_URL missing from supabase status output"
[ -n "$AK"  ] || _u2_die "ANON_KEY missing from supabase status output"
[ -n "$SR"  ] || _u2_die "SERVICE_ROLE_KEY missing from supabase status output"

# HARD LOCALHOST GUARD. Everything below is destructive by design, so the
# tooling must be structurally incapable of pointing at a hosted project even
# if configuration drifts or someone exports API by hand. There is no flag to
# turn this off, deliberately.
case "$API" in
  http://127.0.0.1:*|http://localhost:*|http://[::1]:*) ;;
  *) _u2_die "refusing to run: API_URL '$API' is not localhost. U2 tooling is local-only." ;;
esac

# `supabase db query --local` is used throughout rather than --linked, for the
# same reason. Never change these to --linked.

# ------------------------------------------------------------------- helpers

# A non-SELECT prints a plain command tag ("INSERT 0 1"), a SELECT prints JSON,
# and a failure prints a JSON _tag:"Error". Fail loudly on the last of those
# rather than letting a broken fixture look like a passing test.
sql() {
  local out
  out=$(supabase db query --local "$1" 2>/dev/null)
  case "$out" in
    *'"_tag":"Error"'*) echo "SQL FAILED: $out" >&2; return 1 ;;
  esac
  printf '%s' "$out"
}
scalar()   { sql "$1" | jq -r '.rows[0] | to_entries[0].value'; }
mkuser()   { curl -s -X POST "$API/auth/v1/admin/users" -H "apikey: $SR" -H "Authorization: Bearer $SR" \
             -H 'Content-Type: application/json' \
             -d "{\"email\":\"$1@u2.local\",\"password\":\"u2-local-pw-1234\",\"email_confirm\":true}" | jq -r '.id'; }
tokenfor() { curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $AK" \
             -H 'Content-Type: application/json' \
             -d "{\"email\":\"$1@u2.local\",\"password\":\"u2-local-pw-1234\"}" | jq -r '.access_token'; }
# $1 bucket, $2 path, $3 body, $4 content-type.
# The content type is a real parameter because the buckets enforce
# allowed_mime_types exactly as production does — avatars accepts image/jpeg
# only, and an application/pdf upload there is correctly rejected.
putobj() {
  local ct=${4:-application/pdf} code
  code=$(printf '%s' "${3:-x}" | curl -s -o /dev/null -w '%{http_code}' -X POST \
    "$API/storage/v1/object/$1/$2" -H "apikey: $SR" -H "Authorization: Bearer $SR" \
    -H "Content-Type: $ct" --data-binary @-)
  if [ "$code" != "200" ]; then
    echo "UPLOAD FAILED ($code): $1/$2 as $ct" >&2
    return 1
  fi
  printf '%s' "$code"
}
delacct()  { curl -s -X POST "$API/functions/v1/delete_account_v1" -H "Authorization: Bearer $1"; }
objcount() { scalar "select count(*) c from storage.objects where bucket_id='$1' and name like '$2%';"; }
