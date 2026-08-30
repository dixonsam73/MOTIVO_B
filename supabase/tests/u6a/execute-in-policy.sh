#!/usr/bin/env bash
#
# U6a GATE, EXPERIMENT 1 — does a function referenced in an RLS policy
# expression require EXECUTE privilege from the INVOKING role?
#
# WHY THIS EXISTS. The U3 migration asserts, in a comment and nowhere else:
#
#   "connected_member() needs no grant at all: at U6 it is evaluated inside RLS
#    policy expressions, which run as part of the query rather than as a direct
#    call -- so it decides what clients may see while remaining unreachable BY
#    them."
#
# connected_member() has EXECUTE revoked from public, anon, authenticated AND
# service_role. If that comment is wrong, then every policy U6 writes fails with
# "permission denied for function connected_member" for role `authenticated` --
# which is not a subtle mis-scoping, it is a total Connected outage for every
# member, entitled or not, the moment U6b binds.
#
# The claim has never been executed. It is cheap to settle and catastrophic to
# discover in production, so it is settled here first.
#
# LOCAL DISPOSABLE STACK ONLY -- inherits u4/lib.sh's localhost + container
# guards. There is no flag to turn them off.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u4/lib.sh

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
# Asserts on OBSERVED STATE, never on an exit status.
want() { # want <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1 -> $3"; else bad "$1 -> expected '$2', got '$3'"; fi
}

echo "=============================================================="
echo " U6a GATE 1 — EXECUTE privilege inside an RLS policy qual"
echo " container: $DB"
echo "=============================================================="

# ---------------------------------------------------------------- teardown
psq "drop schema if exists u6a_gate cascade" >/dev/null

# ---------------------------------------------------------------- fixture
psqf <<'SQL' >/dev/null
create schema u6a_gate;
create table u6a_gate.probe(id int primary key, tag text);
insert into u6a_gate.probe values (1,'row-one'),(2,'row-two');
alter table u6a_gate.probe enable row level security;
grant usage on schema u6a_gate to authenticated;
grant select on u6a_gate.probe to authenticated;

-- A non-SECURITY-DEFINER twin, so the result can be attributed to EXECUTE
-- privilege rather than to SECURITY DEFINER doing something special.
create function u6a_gate.plain_true(uuid) returns boolean
  language sql stable as $$ select true $$;
revoke execute on function u6a_gate.plain_true(uuid)
  from public, anon, authenticated, service_role;

-- A SECURITY DEFINER twin that always returns TRUE. connected_member() is both
-- SECURITY DEFINER and (on an empty fixture) FALSE, so on its own it cannot
-- separate "EXECUTE was checked" from "the predicate was false".
create function u6a_gate.secdef_true(uuid) returns boolean
  language sql stable security definer set search_path = '' as $$ select true $$;
revoke execute on function u6a_gate.secdef_true(uuid)
  from public, anon, authenticated, service_role;
SQL

FIXROWS=$(psq "select count(*) from u6a_gate.probe")
want "fixture: 2 rows exist before anything is asserted" "2" "$FIXROWS"

# --------------------------------------------------------------- CONTROLS
echo
echo "-- CONTROLS: prove the harness can tell allow from deny --"

# The known-true state: a DIRECT call must be refused. If this ever passes,
# the function is granted and the whole experiment is meaningless.
DIRECT=$(psq "set role authenticated; select public.connected_member('00000000-0000-0000-0000-000000000001'::uuid)")
case "$DIRECT" in
  *"permission denied for function connected_member"*) want "C1 direct call as authenticated is REFUSED" "refused" "refused" ;;
  *ERROR*) bad "C1 direct call refused, but NOT on privilege: $DIRECT" ;;
  *) bad "C1 direct call as authenticated was ACCEPTED (returned '$DIRECT') — function is granted, experiment void" ;;
esac

# A policy that calls NOTHING must let rows through, or a later empty result
# would be uninterpretable.
psq "create policy p_none on u6a_gate.probe for select to authenticated using (true)" >/dev/null
C2=$(psq "set role authenticated; select count(*) from u6a_gate.probe")
want "C2 function-free policy returns rows (harness works)" "2" "$C2"
psq "drop policy p_none on u6a_gate.probe" >/dev/null

# ------------------------------------------------------------------- TESTS
#
# NO `or true` ANYWHERE IN A QUAL, and the reason is the first defect this
# experiment produced. The first revision wrote the qual as
#   using (public.connected_member(...) or true)
# so that a merely-FALSE predicate could not be mistaken for a privilege error.
# Postgres folds `or true` to a constant and NEVER EVALUATES THE FUNCTION, so
# that revision returned 2 rows and "proved" EXECUTE was not checked. It proved
# nothing. The defensive clause destroyed the only thing being measured.
#
# Three outcomes are already distinguishable without it:
#   ERROR permission denied -> EXECUTE is checked in a policy qual
#   0 rows                  -> not checked; predicate evaluated FALSE
#   2 rows                  -> not checked; predicate evaluated TRUE

verdict() { # verdict <label> <raw>
  case "$2" in
    *"permission denied for function"*) echo "  $1 -> ERROR permission denied  ** EXECUTE IS CHECKED **" ;;
    0) echo "  $1 -> 0 rows  (evaluated, predicate false; EXECUTE not checked)" ;;
    2) echo "  $1 -> 2 rows  (evaluated, predicate true;  EXECUTE not checked)" ;;
    *) echo "  $1 -> UNEXPECTED: $2" ;;
  esac
}

echo
echo "-- TEST A: the real connected_member(), UNGRANTED, alone in a qual --"
psq "create policy p_cm on u6a_gate.probe for select to authenticated using (public.connected_member('00000000-0000-0000-0000-000000000001'::uuid))" >/dev/null
TA=$(psq "set role authenticated; select count(*) from u6a_gate.probe")
verdict "A connected_member (SECURITY DEFINER, ungranted)" "$TA"
psq "drop policy p_cm on u6a_gate.probe" >/dev/null

echo
echo "-- TEST B: SECURITY DEFINER twin returning TRUE, ungranted --"
echo "   (isolates 'is it SECURITY DEFINER' from 'does the predicate hold')"
psq "create policy p_sd on u6a_gate.probe for select to authenticated using (u6a_gate.secdef_true('00000000-0000-0000-0000-000000000001'::uuid))" >/dev/null
TB=$(psq "set role authenticated; select count(*) from u6a_gate.probe")
verdict "B secdef_true (SECURITY DEFINER, ungranted)" "$TB"
psq "drop policy p_sd on u6a_gate.probe" >/dev/null

echo
echo "-- TEST C: plain (non-SECURITY-DEFINER) twin returning TRUE, ungranted --"
psq "create policy p_plain on u6a_gate.probe for select to authenticated using (u6a_gate.plain_true('00000000-0000-0000-0000-000000000001'::uuid))" >/dev/null
TC=$(psq "set role authenticated; select count(*) from u6a_gate.probe")
verdict "C plain_true (invoker rights, ungranted)" "$TC"
psq "drop policy p_plain on u6a_gate.probe" >/dev/null

echo
echo "-- TEST D: THE DISCRIMINATOR — grant EXECUTE, change nothing else --"
psq "grant execute on function u6a_gate.plain_true(uuid) to authenticated" >/dev/null
psq "grant execute on function u6a_gate.secdef_true(uuid) to authenticated" >/dev/null
psq "create policy p_plain2 on u6a_gate.probe for select to authenticated using (u6a_gate.plain_true('00000000-0000-0000-0000-000000000001'::uuid))" >/dev/null
TD=$(psq "set role authenticated; select count(*) from u6a_gate.probe")
verdict "D plain_true (invoker rights, NOW GRANTED)" "$TD"
psq "drop policy p_plain2 on u6a_gate.probe" >/dev/null

echo
echo "-- TEST E: does the grant rescue connected_member() too? --"
psq "grant execute on function public.connected_member(uuid) to authenticated" >/dev/null
psq "create policy p_cm2 on u6a_gate.probe for select to authenticated using (public.connected_member('00000000-0000-0000-0000-000000000001'::uuid))" >/dev/null
TE=$(psq "set role authenticated; select count(*) from u6a_gate.probe")
verdict "E connected_member (NOW GRANTED)" "$TE"
psq "drop policy p_cm2 on u6a_gate.probe" >/dev/null
# RESTORE the production posture immediately. This grant exists for one
# assertion and must not outlive it.
psq "revoke execute on function public.connected_member(uuid) from public, anon, authenticated, service_role" >/dev/null
RESTORED=$(psq "select has_function_privilege('authenticated','public.connected_member(uuid)','EXECUTE')")
want "E-restore: connected_member EXECUTE revoked again for authenticated" "f" "$RESTORED"

echo
echo "=============================================================="
echo " summary of the CONTROLS only: PASS=$PASS FAIL=$FAIL"
echo " (the TEST verdicts above are observations, not pass/fail)"
echo "=============================================================="

psq "drop schema if exists u6a_gate cascade" >/dev/null
LEFT=$(psq "select count(*) from information_schema.schemata where schema_name='u6a_gate'")
echo "cleanup: u6a_gate schemas remaining = $LEFT"
