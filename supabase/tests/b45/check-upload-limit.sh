#!/usr/bin/env bash
# B-45 local rehearsal. Local stack only. Restores the bucket and removes its
# test objects on every exit, including failure, then proves the fingerprint is
# unchanged.
# Limitation: the local stack's default project-wide cap is also 50 MiB, so the
# oversized upload shows a refusal but not WHICH limit refused it. What this
# proves is the SQL guards and that exactly 50 MiB is accepted.
set -euo pipefail
cd "$(dirname "$0")/../../.."
container=supabase_db_rlwtqxumfobakvdueugm
docker ps --format '{{.Names}}' | grep -qx "$container" || { echo 'Local DB container unavailable; refusing.' >&2; exit 1; }
psql_() { docker exec -i "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
status=$(supabase status -o json 2>/dev/null)
api=$(printf '%s' "$status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["API_URL"])')
key=$(printf '%s' "$status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["SERVICE_ROLE_KEY"])')
case "$api" in http://127.0.0.1:*) ;; *) echo "Refusing non-local API $api" >&2; exit 1;; esac

fp="select file_size_limit||':'||allowed_mime_types::text||':'||public||':'||(select count(*) from storage.objects where bucket_id='attachments') from storage.buckets where id='attachments';"
before=$(psql_ -Atqc "$fp")
echo "before: $before"
case "$before" in 157286400:*) ;; *) echo 'Refusing: local bucket is not in the pre-B-45 state.' >&2; exit 1;; esac

tmp=$(mktemp -d)
changed=0
cleanup() {
  for n in at over; do
    curl -s -o /dev/null -X DELETE "$api/storage/v1/object/attachments/b45-rehearsal/$n.pdf" \
      -H "Authorization: Bearer $key" -H "apikey: $key" || true
  done
  if [ "$changed" = 1 ]; then
    psql_ -q -c "UPDATE storage.buckets SET file_size_limit=157286400 WHERE id='attachments' AND file_size_limit=52428800;" || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# 1. SQL guards, rolled back: apply, re-apply refused, rollback body restores.
{
  echo 'BEGIN;'
  cat supabase/migrations/20260924120000_b45_attachments_upload_limit.sql
  cat <<'SQL'
DO $t$ BEGIN IF (SELECT file_size_limit FROM storage.buckets WHERE id='attachments') <> 52428800 THEN RAISE EXCEPTION 'FAIL: not applied'; END IF; RAISE NOTICE 'PASS: migration applied'; END $t$;
SQL
  sed -n '/^DO \$guard\$/,/^UPDATE/p' supabase/sql/2026-09-24-b45-upload-limit-rollback-production.sql
  echo "DO \$t\$ BEGIN IF (SELECT file_size_limit FROM storage.buckets WHERE id='attachments') <> 157286400 THEN RAISE EXCEPTION 'FAIL: rollback did not restore'; END IF; RAISE NOTICE 'PASS: rollback body restores 157286400'; END \$t\$;"
  echo 'ROLLBACK;'
} | psql_ -q

# 1b. The real migration, run twice in one rolled-back transaction, must refuse the second run.
second=$( { echo 'BEGIN;'; cat supabase/migrations/20260924120000_b45_attachments_upload_limit.sql supabase/migrations/20260924120000_b45_attachments_upload_limit.sql; echo 'ROLLBACK;'; } | psql_ -q 2>&1 || true)
printf '%s' "$second" | grep -q 'B-45: unexpected attachments bucket configuration' || { echo "FAIL: second run not refused: $second" >&2; exit 1; }
echo 'PASS: the migration pre-guard refuses a second run'

# 2. Real HTTP boundary, with the change committed locally.
changed=1
psql_ -q -f - < supabase/sql/2026-09-24-b45-upload-limit-apply-production.sql
head -c 52428800 /dev/zero > "$tmp/at"
head -c 52428801 /dev/zero > "$tmp/over"
up() { curl -s -o "$tmp/resp" -w '%{http_code}' -X POST "$api/storage/v1/object/attachments/b45-rehearsal/$1.pdf" \
  -H "Authorization: Bearer $key" -H "apikey: $key" -H 'Content-Type: application/pdf' --data-binary @"$tmp/$1"; }
at=$(up at); over=$(up over)
echo "exactly 50 MiB -> HTTP $at; 50 MiB + 1 byte -> HTTP $over (bucket or local project-wide cap) ($(head -c 200 "$tmp/resp"))"
for n in at over; do
  curl -s -o /dev/null -X DELETE "$api/storage/v1/object/attachments/b45-rehearsal/$n.pdf" -H "Authorization: Bearer $key" -H "apikey: $key" || true
done
psql_ -q -f - < supabase/sql/2026-09-24-b45-upload-limit-rollback-production.sql
changed=0

after=$(psql_ -Atqc "$fp")
echo "after:  $after"
[ "$at" = 200 ] || { echo 'FAIL: a 50 MiB file was refused' >&2; exit 1; }
[ "$over" != 200 ] || { echo 'FAIL: a file over 50 MiB was accepted' >&2; exit 1; }
[ "$before" = "$after" ] || { echo 'FAIL: local bucket or object count changed' >&2; exit 1; }
echo 'PASS: guards hold, 50 MiB accepted, 50 MiB + 1 refused (limit not isolated), local state restored.'
