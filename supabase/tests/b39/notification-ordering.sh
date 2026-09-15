#!/usr/bin/env bash
#
# B-39 follow-up — notification → derivation → ingestion, and the ordering
# contract. LOCAL ONLY; see notification-ordering.ts for what it claims.
#
#   ./supabase/tests/b39/notification-ordering.sh
#
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e
export DB
exec deno run --allow-run=docker --allow-env=DB supabase/tests/b39/notification-ordering.ts
