#!/usr/bin/env bash
#
# B-23 fidelity gate — Phase 3 U1.
#
# Captures the ten structural surfaces from the LOCAL instance and compares them
# against the committed supabase/schema/ snapshot, which is observed production
# truth and the authority in this comparison.
#
# The criterion is enforced by check-baseline.py, and it is deliberately not
# "eyeball the diff":
#
#   - every surface reproducible byte-identically MUST be byte-identical;
#   - a catalog-serialization difference is tolerated ONLY if it is declared in
#     baseline-exceptions.json with evidence that it is PostgreSQL
#     normalization/history rather than a semantic difference;
#   - each declared exception is still DETECTED and verified to be exactly the
#     approved difference, on both the production and the local side;
#   - a new difference, a changed difference, or a declared exception that no
#     longer appears all FAIL the gate.
#
# Never make this pass by normalising a difference away. If one is genuinely
# irreproducible, evidence it and add it to the allowlist deliberately.
#
# Requires: a running local stack (`supabase start`), and therefore a container
# runtime. Does not touch production.

set -euo pipefail

cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Capturing local structural snapshot..."
./supabase/capture-schema.sh --local "$TMP" > /dev/null

echo
exec python3 ./supabase/check-baseline.py "$TMP"
