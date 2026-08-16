#!/usr/bin/env bash
# U2 shared helpers. LOCAL ONLY — every URL here is 127.0.0.1.
#
# The keys below are the Supabase CLI's well-known LOCAL demo keys, printed by
# `supabase status` on every machine. They are not secrets and they authenticate
# to nothing outside this host. No production credential appears in this repo.
set -euo pipefail
export API=${API:-http://127.0.0.1:54321}
export SR="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
export AK="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

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
