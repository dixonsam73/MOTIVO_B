#!/usr/bin/env bash
#
# U4 shared psql access. LOCAL DISPOSABLE STACK ONLY.
#
# Every route into the database is localhost-checked, because everything the U4
# suites do is destructive by design. u2/lib.sh already guards API_URL; this adds
# the same guard on DB_URL and then requires the resolved container to be a
# supabase_db_* one publishing that exact port. There is no flag to turn it off.

set -uo pipefail

_u4_die() { echo "u4: $*" >&2; exit 1; }

DB_URL=$(supabase status -o json 2>/dev/null | jq -r '.DB_URL // empty')
[ -n "$DB_URL" ] || _u4_die "could not read DB_URL from 'supabase status -o json'"

DB_HOST=$(printf '%s' "$DB_URL" | sed -E 's#^.*@([^:/]+):([0-9]+)/.*$#\1#')
DB_PORT=$(printf '%s' "$DB_URL" | sed -E 's#^.*@([^:/]+):([0-9]+)/.*$#\2#')
case "$DB_HOST" in
  127.0.0.1|localhost|::1) ;;
  *) _u4_die "refusing to run: DB_URL host '$DB_HOST' is not localhost" ;;
esac
[ -n "$DB_PORT" ] || _u4_die "could not parse a port from DB_URL"

DB=$(docker ps --filter "publish=$DB_PORT" --format '{{.Names}}' | grep '^supabase_db_' || true)
[ -n "$DB" ] || _u4_die "no supabase_db_* container publishes port $DB_PORT"
[ "$(printf '%s\n' "$DB" | wc -l | tr -d ' ')" = "1" ] || _u4_die "ambiguous supabase_db_* container"

export DB

psq()  { docker exec -i "$DB" psql -U postgres -d postgres -At -q -c "$1" 2>&1; }
psqf() { docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 2>&1; }
# Prints "refused" when a statement errors — used to assert that a privilege
# boundary or a constraint actually holds, rather than assuming it.
refuses() { local out; out=$(psq "$1"); case "$out" in *ERROR*) echo "refused";; *) echo "ACCEPTED";; esac; }
