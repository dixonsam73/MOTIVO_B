#!/usr/bin/env bash
#
# U6a GATE, EXPERIMENT 1b — GIVEN that EXECUTE is checked in a policy qual
# (experiment 1), what shape may U6's predicate actually take?
#
# The naive fix to experiment 1 is "grant EXECUTE on connected_member(uuid) to
# authenticated". That works (experiment 1, test E) and it is DANGEROUS, because
# the function TAKES A USER ID. Granting it makes it callable through PostgREST
# as an RPC by any authenticated client, for ANY uuid -- turning the entitlement
# predicate into a membership oracle over the whole user base.
#
# So three candidate shapes are measured here, not argued:
#   S1  inline the SQL into the policy qual, no function call at all
#   S2  a ZERO-ARGUMENT SECURITY DEFINER wrapper over auth.uid(), granted
#   S3  the granted uuid-taking function, probed as an oracle (the risk)
#
# LOCAL DISPOSABLE STACK ONLY -- inherits u4/lib.sh's guards.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u4/lib.sh

echo "=============================================================="
echo " U6a GATE 1b — what shape may the enforcement predicate take?"
echo "=============================================================="

psq "drop schema if exists u6a_shape cascade" >/dev/null
psqf <<'SQL' >/dev/null
create schema u6a_shape;
create table u6a_shape.probe(id int primary key, tag text);
insert into u6a_shape.probe values (1,'row-one'),(2,'row-two');
alter table u6a_shape.probe enable row level security;
grant usage on schema u6a_shape to authenticated;
grant select on u6a_shape.probe to authenticated;
SQL

JWT='{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}'

echo
echo "-- S1: INLINE subquery on public.membership, no function call --"
echo "   authenticated holds ZERO privilege on public.membership (U3 revoked it)."
psq "create policy s1 on u6a_shape.probe for select to authenticated using (exists (select 1 from public.membership m where m.user_id = auth.uid()))" >/dev/null
R1=$(psq "set role authenticated; set request.jwt.claims to '$JWT'; select count(*) from u6a_shape.probe")
echo "   result: $R1"
case "$R1" in
  *"permission denied for table membership"*) echo "   >>> S1 IS NOT VIABLE — the qual is privilege-checked as the INVOKER" ;;
  0|2) echo "   >>> S1 evaluated without error — inlining reads membership as the invoker" ;;
  *) echo "   >>> S1 UNEXPECTED: $R1" ;;
esac
psq "drop policy s1 on u6a_shape.probe" >/dev/null

echo
echo "-- S2: ZERO-ARGUMENT SECURITY DEFINER wrapper over auth.uid(), granted --"
psqf <<'SQL' >/dev/null
create function u6a_shape.is_member() returns boolean
  language sql stable security definer set search_path = ''
  as $$ select public.connected_member((select auth.uid())) $$;
revoke execute on function u6a_shape.is_member() from public, anon, service_role;
grant  execute on function u6a_shape.is_member() to authenticated;
SQL
psq "create policy s2 on u6a_shape.probe for select to authenticated using (u6a_shape.is_member())" >/dev/null
R2=$(psq "set role authenticated; set request.jwt.claims to '$JWT'; select count(*) from u6a_shape.probe")
echo "   result: $R2"
case "$R2" in
  *"permission denied"*) echo "   >>> S2 IS NOT VIABLE: $R2" ;;
  0) echo "   >>> S2 VIABLE — evaluated cleanly, denied (no membership row for this uid). CORRECT." ;;
  2) echo "   >>> S2 evaluated cleanly and ALLOWED — check the fixture, expected denial" ;;
  *) echo "   >>> S2 UNEXPECTED: $R2" ;;
esac

echo
echo "   ...and does the wrapper's SECURITY DEFINER reach the ungranted inner fn?"
INNER=$(psq "set role authenticated; set request.jwt.claims to '$JWT'; select u6a_shape.is_member()")
echo "   direct call to the wrapper: $INNER   (expect f, not an error)"
psq "drop policy s2 on u6a_shape.probe" >/dev/null

echo
echo "-- S2-oracle: can the zero-arg wrapper be abused to probe ANOTHER user? --"
echo "   It takes no argument and reads auth.uid(), so there is nothing to aim."
SIG=$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='u6a_shape' and p.proname='is_member' and p.pronargs=0")
echo "   zero-argument overloads of is_member: $SIG   (1 = no argument exists to supply)"

echo
echo "-- S3: THE RISK — grant the uuid-taking predicate, then use it as an oracle --"
psq "grant execute on function public.connected_member(uuid) to authenticated" >/dev/null
ORACLE=$(psq "set role authenticated; set request.jwt.claims to '$JWT'; select public.connected_member('11111111-2222-3333-4444-555555555555'::uuid)")
echo "   authenticated asked about a DIFFERENT user id: '$ORACLE'"
case "$ORACLE" in
  *ERROR*) echo "   >>> refused — not an oracle" ;;
  *)       echo "   >>> ANSWERED. Granting connected_member(uuid) to authenticated makes it" ;
           echo "       a membership oracle over any uuid, callable as a PostgREST RPC." ;;
esac
psq "revoke execute on function public.connected_member(uuid) from public, anon, authenticated, service_role" >/dev/null
BACK=$(psq "select has_function_privilege('authenticated','public.connected_member(uuid)','EXECUTE')")
echo "   production posture restored, authenticated EXECUTE = $BACK   (expect f)"

psq "drop schema if exists u6a_shape cascade" >/dev/null
echo
echo "cleanup: u6a_shape remaining = $(psq "select count(*) from information_schema.schemata where schema_name='u6a_shape'")"
