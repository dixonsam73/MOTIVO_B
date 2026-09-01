#!/usr/bin/env bash
#
# U6a acceptance — SUPERSEDED BY U6b, 2026-09-01.
#
# This suite tested `public.shadow_observe(text)`, which U6b DROPS: a function
# that denies requests must not be called `shadow_observe` (C-25 / F6). Its
# subject no longer exists.
#
# IT WAS NOT EDITED UNTIL IT PASSED, AND IT IS NOT A STUB THAT ALWAYS PASSES --
# that is the "check that cannot fire" defect this repository names. The
# assertions with unique value were CARRIED into supabase/tests/u6b/acceptance.sh
# as group K, unchanged in substance; the rest were superseded there by name:
#
#   G4-S1  inertness on every path      -> U6b group D (behavioural, and honest:
#                                          inert only while unbound)
#   G4-S2  attached vs detached rows    -> U6b-D5 and U6b-I3
#   G4-S3  no bare observer calls       -> U6b-J1
#   G4-S4  uuid predicates ungranted    -> U6b-J2
#   G4-S5/S6/S7/S8, B1/B3/B4            -> U6b group K
#
# What U6a PROVED is preserved in supabase/sql/README-u6a-deployment.md, which is
# the record. This file remains as an executable guard on the supersession
# itself, and it CAN fail.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-11s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-11s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo; echo "U6a acceptance — SUPERSEDED. Guarding that the supersession is real."; echo
is SUP-1 "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='shadow_observe';")" "0" "shadow_observe is gone, so this suite's subject is genuinely absent"
is SUP-2 "$([ -x supabase/tests/u6b/acceptance.sh ] && echo yes || echo no)" "yes" "the successor suite exists and is executable"
is SUP-3 "$(grep -c 'U6b-K' supabase/tests/u6b/acceptance.sh)" "12" "all twelve carried assertions are present in the successor"
echo; echo "  $PASS passed, $FAIL failed"; echo
[ "$FAIL" -eq 0 ]
