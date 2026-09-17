#!/usr/bin/env bash
# Local-only, rolled back. Fixtures use fresh UUIDs and cannot reach production.
set -euo pipefail
cd "$(dirname "$0")/../../.."
container=supabase_db_rlwtqxumfobakvdueugm
docker ps --format '{{.Names}}' | rg -x "$container" >/dev/null || { echo 'Expected local stack unavailable'; exit 1; }
fingerprint="select (select count(*) from auth.users)||':'||(select count(*) from public.connected_attachments)||':'||(select count(*) from public.follows)||':'||(select count(*) from public.membership)||':'||(select count(*) from public.account_privacy)||':'||(select count(*) from storage.objects)||':'||public.enforcement_active()||':'||(select allowed_mime_types::text from storage.buckets where id='attachments')||':'||md5(string_agg(pg_get_functiondef(p.oid),'|' order by p.proname)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public';"
before=$(docker exec "$container" psql -U postgres -d postgres -Atqc "$fingerprint")
{
 echo 'BEGIN;'
 # Bring only these two stale local predicates to the verified deployed definitions,
 # within the same rollback. Neither is deployed/reapplied to production.
 cat supabase/migrations/20260915150000_b40_teen_follow_requests_closed.sql
 cat supabase/migrations/20260915160000_scope011_verified_sandbox_entitlement.sql
 cat supabase/migrations/20260917120000_connected_lists_mime.sql
 cat supabase/tests/lists/list-delivery-checks.sql
 echo 'ROLLBACK;'
} | docker exec -i "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1
after=$(docker exec "$container" psql -U postgres -d postgres -Atqc "$fingerprint")
[ "$before" = "$after" ] || { echo 'FAIL: local baseline changed'; exit 1; }
echo 'PASS: local identities, deliveries, follows, memberships, privacy, objects, enforcement and function definitions restored.'
