#!/usr/bin/env bash
#
# B-23 fidelity gate — Phase 3 U1.
#
# Captures the ten structural queries from the LOCAL instance and diffs them
# against the committed supabase/schema/ snapshot, which is observed production
# truth and the authority in this comparison.
#
# ALL TEN MUST DIFF EMPTY. That is the whole gate. Anything less is not a
# faithful baseline, and no verification run against it counts.
#
# This script must never be made to pass by normalising away a genuine
# structural difference. If a difference is deterministic and semantically
# irrelevant, report it and get the criterion changed deliberately — do not
# redefine "empty diff" here.
#
# Requires: a running local stack (`supabase start`), and therefore a container
# runtime. Does not touch production.

set -euo pipefail

cd "$(dirname "$0")/.."

FILES=(functions policies rls_enabled triggers constraints columns
       function_grants table_grants column_grants storage_buckets)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Capturing local structural snapshot..."
./supabase/capture-schema.sh --local "$TMP" > /dev/null

echo
echo "B-23 fidelity gate — local baseline vs supabase/schema/"
echo

pass=0
fail=0
for f in "${FILES[@]}"; do
  if diff -q "supabase/schema/$f.json" "$TMP/$f.json" > /dev/null 2>&1; then
    printf "  %-18s EMPTY\n" "$f"
    pass=$((pass + 1))
  else
    printf "  %-18s DIFFERS\n" "$f"
    fail=$((fail + 1))
  fi
done

echo
echo "  $pass of ${#FILES[@]} empty"

if [ "$fail" -ne 0 ]; then
  echo
  echo "GATE NOT MET. Differences:"
  for f in "${FILES[@]}"; do
    if ! diff -q "supabase/schema/$f.json" "$TMP/$f.json" > /dev/null 2>&1; then
      echo
      echo "--- $f ---"
      diff "supabase/schema/$f.json" "$TMP/$f.json" || true
    fi
  done
  exit 1
fi

echo
echo "GATE MET. The local baseline reproduces production structurally."
echo "This is NOT production verification — see supabase/README.md."
