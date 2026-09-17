#!/usr/bin/env bash
# Local-only, rolled-back rehearsal. No persistent fixtures or schema changes.
set -euo pipefail
cd "$(dirname "$0")/../../.."
container=supabase_db_rlwtqxumfobakvdueugm
if ! docker ps --format '{{.Names}}' | rg -x "$container" >/dev/null; then
  echo 'Expected local test container unavailable; refusing.' >&2
  exit 1
fi
fingerprint="select md5(coalesce(string_agg(conname || pg_get_constraintdef(oid),'|' order by conname),'')) || ':' || (select allowed_mime_types::text from storage.buckets where id='attachments') || ':' || (select count(*) from public.connected_attachments) from pg_constraint where conrelid='public.connected_attachments'::regclass;"
before=$(docker exec "$container" psql -U postgres -d postgres -Atqc "$fingerprint")
{
  echo 'BEGIN;'
  cat supabase/migrations/20260917120000_connected_lists_mime.sql
  cat supabase/tests/lists/mime-checks.sql
  echo 'ROLLBACK;'
} | docker exec -i "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1
after=$(docker exec "$container" psql -U postgres -d postgres -Atqc "$fingerprint")
if [ "$before" != "$after" ]; then
  echo 'FAIL: local schema/bucket/reference count changed.' >&2
  exit 1
fi
echo 'PASS: local schema, MIME configuration and delivery count unchanged after rollback.'
