#!/usr/bin/env bash
#
# Capture the structural snapshot.
#
# DEFAULT BEHAVIOUR IS UNCHANGED: with no arguments this refreshes
# supabase/schema/ from the LINKED PRODUCTION project, exactly as before.
#
#   ./supabase/capture-schema.sh                    # linked  -> supabase/schema
#   ./supabase/capture-schema.sh --local <outdir>   # local   -> <outdir>
#
# Run the default form immediately after any applied SQL change to production,
# and commit the resulting diff. The diff is the record of what changed in
# production.
#
# The --local form was added by Phase 3 U1 (B-23) so the same ten queries can be
# run against the local instance and compared. THE COMPARISON DIRECTION MATTERS:
# supabase/schema/ is observed production truth and is the authority; the local
# capture is the thing being measured against it. Never write a local capture
# into supabase/schema/ — the script refuses to.
#
# Structure only. Every query below reads the system catalogs or
# information_schema. None of them read a user table, and none may be changed
# to do so. See README.md.
#
# Requires: supabase CLI, logged in and linked (for --linked). --local
# additionally requires a running local stack, and therefore a container
# runtime.

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="--linked"
OUT="supabase/schema"

if [ "${1:-}" = "--local" ]; then
  TARGET="--local"
  OUT="${2:-}"
  if [ -z "$OUT" ]; then
    echo "error: --local requires an output directory" >&2
    exit 2
  fi
  # Refuse to overwrite the production snapshot with a local capture. That
  # would destroy the only record of observed production truth and make the
  # fidelity gate compare a file against itself.
  case "$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)/$(basename "$OUT")" in
    */supabase/schema)
      echo "error: refusing to write a --local capture into supabase/schema" >&2
      exit 2
      ;;
  esac
elif [ -n "${1:-}" ] && [ "${1:-}" != "--linked" ]; then
  echo "usage: $0 [--linked | --local <outdir>]" >&2
  exit 2
fi

mkdir -p "$OUT"

q() {
  # $1 = output basename, $2 = SQL
  #
  # Keep only .rows, with sorted keys. The CLI wraps results in a per-invocation
  # random `boundary` token plus a warning string; leaving those in would make
  # every refresh produce a diff on every file, which would render the snapshot
  # diff worthless as a record of what actually changed.
  supabase db query "$TARGET" "$2" | jq -S '.rows' > "$OUT/$1.json"
  printf "  %-18s %8s bytes\n" "$1" "$(wc -c < "$OUT/$1.json" | tr -d ' ')"
}

echo "Capturing structural snapshot ($TARGET -> $OUT)..."

q functions "select p.proname, pg_get_functiondef(p.oid) as definition, p.prosecdef as security_definer from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by 1;"

q policies "select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check from pg_policies where schemaname in ('public','storage') order by schemaname, tablename, policyname;"

q rls_enabled "select c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' order by 1;"

q triggers "select t.tgname, c.relname as on_table, pg_get_triggerdef(t.oid) as definition, t.tgenabled from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage') and not t.tgisinternal order by 2,1;"

q constraints "select conrelid::regclass::text as table_name, conname, pg_get_constraintdef(oid) as definition, contype from pg_constraint where connamespace='public'::regnamespace order by 1,2;"

q columns "select table_name, column_name, ordinal_position, data_type, is_nullable, column_default from information_schema.columns where table_schema='public' order by table_name, ordinal_position;"

q function_grants "select p.proname, r.rolname as grantee, has_function_privilege(r.rolname, p.oid, 'EXECUTE') as can_execute from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r where n.nspname='public' order by 1,2;"

# Table and column privileges.
#
# Added 2026-08-13 with B-14, which exposed a blind spot: the snapshot recorded
# FUNCTION grants but no table or column privileges at all, so a whole class of
# backend authority was invisible to the diff. B-14's fix lives entirely here —
# it removes UPDATE on follows.follower_user_id from `authenticated` — and
# without these two queries the only durable record of it would have been a
# commit message, which is precisely what B-17 exists to prevent.
#
# column_privileges expands table-level grants down to each column, so it shows
# the effective per-column privilege regardless of how it was granted. That is
# what makes a column-scoped REVOKE/GRANT visible as a diff.

q table_grants "select table_name, grantee, privilege_type from information_schema.role_table_grants where table_schema='public' and grantee in ('anon','authenticated','service_role') order by 1,2,3;"

q column_grants "select table_name, column_name, grantee, privilege_type from information_schema.column_privileges where table_schema='public' and grantee in ('anon','authenticated','service_role') order by 1,2,3,4;"

q storage_buckets "select id, name, public, file_size_limit, allowed_mime_types from storage.buckets order by 1;"

echo
if [ "$TARGET" = "--linked" ]; then
  echo "Done. Review the diff before committing:"
  echo "  git diff --stat supabase/schema"
else
  echo "Done. Compare against observed production truth:"
  echo "  diff -rq supabase/schema $OUT"
fi
