#!/usr/bin/env bash
#
# U5b acceptance — LOCAL DISPOSABLE STACK ONLY.
#
#   supabase db reset --local && ./supabase/tests/u5/acceptance.sh
#
# Covers D4's environment separation, the establishment writer, the two grants
# and the F11 rule. Every assertion reads resulting state; a command exit status
# is never a pass.
#
# WHAT THIS SUITE DELIBERATELY DOES NOT CLAIM.
#
# **A30 IS NOT DISCHARGED HERE, AND MUST NOT BE RECORDED AS IF IT WERE.** A30 is
# "the legacy claim calls Set App Account Token and RE-READS Apple before writing
# membership". Both halves are HTTPS round trips that belong to U5c/U5d, and
# neither exists yet. What is asserted below is the SQL-side PRECONDITION only:
# that establishment REFUSES on a token Apple has not confirmed as ours, so the
# claim path cannot be short-circuited in the database. That is a prerequisite
# for A30, not A30.
#
# A29 and A31 ARE exercised in full at this level, because both are decisions the
# database makes on its own: a token belonging to another live binding is refused
# and recorded, and an orphan is distinguished from a mismatch.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh          # localhost guard + dynamic credentials
source supabase/tests/u4/lib.sh          # psq/psqf/refuses + container resolution

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-7s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-7s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo
echo "U5b acceptance — establishment, environment separation, grants"
echo

A=$(mkuser u5a); B=$(mkuser u5b); C=$(mkuser u5c); D=$(mkuser u5d)
for U in "$A" "$B" "$C" "$D"; do
  psq "select set_config('request.jwt.claims','{\"sub\":\"$U\"}',false); select public.ensure_membership_binding();" >/dev/null
done
TOKA=$(psq "select binding_token from public.membership_binding where user_id='$A';")
TOKB=$(psq "select binding_token from public.membership_binding where user_id='$B';")
TOKC=$(psq "select binding_token from public.membership_binding where user_id='$C';")

st() {  # $1 renewal_date expr, $2 signed offset
  echo "jsonb_build_object('product_id','com.sdsongs.etudes.connected.monthly','apple_status',1,'renewal_date',($1)::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now() $2)::text)"
}
establish() {  # user, env, otid, apple_token, jws_token, state_expr
  psq "select public.membership_establish_v1('$1','$2','$3',$4,$5,$6);"
}

# ============================================ D4 — environment separation
echo "-- D4: Production entitlement only, and no grandfather fall-through"

# The critical case: a SANDBOX-only identity that IS in the cutover snapshot.
# Under the naive WHERE-clause fix this returns TRUE via the grandfather clause,
# which is the exact inversion of invariant 8.
psqf <<SQL >/dev/null
insert into public.membership_cutover (user_id) values ('$A');
insert into public.membership (user_id, environment, original_transaction_id, product_id,
       renewal_date, renewal_info_signed_date, binding_method, bound_at)
values ('$A','Sandbox','TXN-SBX-LIVE','com.sdsongs.etudes.connected.monthly',
        now() + interval '30 days', now(), 'purchase', now());
SQL
is A60  "$(psq "select public.connected_member('$A');")" "f" "live SANDBOX row in snapshot does NOT entitle"
is A60b "$(psq "select public.membership_state('$A');")" "sandbox_only" "state(sandbox_only)"

# Same identity, but with every derivation input NULL — U3's coalesce lesson in
# its purest form under the new shape. bool_or must still be FALSE, not NULL.
psqf <<SQL >/dev/null
update public.membership set renewal_date=null, grace_period_expires_date=null,
       is_in_billing_retry=true where user_id='$A' and environment='Sandbox';
SQL
is A60c "$(psq "select public.connected_member('$A');")" "f" "Sandbox row, all inputs NULL, still no fall-through"
psqf <<SQL >/dev/null
update public.membership set renewal_date = now() + interval '30 days' where user_id='$A';
SQL

# Production behaviour is unchanged.
psqf <<SQL >/dev/null
insert into public.membership_cutover (user_id) values ('$B');
insert into public.membership (user_id, environment, original_transaction_id, product_id,
       renewal_date, renewal_info_signed_date, binding_method, bound_at)
values ('$B','Production','TXN-PRD-LIVE','com.sdsongs.etudes.connected.monthly',
        now() + interval '30 days', now(), 'purchase', now());
SQL
is A60d "$(psq "select public.connected_member('$B');")" "t" "live PRODUCTION row entitles"
is A60e "$(psq "select public.membership_state('$B');")" "entitled" "state(entitled)"

# Sandbox live + Production lapsed on ONE identity: the Sandbox row must not
# rescue the lapsed Production one.
psqf <<SQL >/dev/null
insert into public.membership (user_id, environment, original_transaction_id, product_id,
       renewal_date, renewal_info_signed_date, binding_method, bound_at)
values ('$B','Sandbox','TXN-SBX-B','com.sdsongs.etudes.connected.monthly',
        now() + interval '30 days', now(), 'purchase', now());
update public.membership set renewal_date = now() - interval '1 day'
 where user_id='$B' and environment='Production';
SQL
is A60f "$(psq "select public.connected_member('$B');")" "f" "live Sandbox does NOT rescue lapsed Production"
is A60g "$(psq "select public.membership_state('$B');")" "expired" "state(expired), not sandbox_only"

# No rows at all -> grandfather clause, unchanged.
psqf <<SQL >/dev/null
insert into public.membership_cutover (user_id) values ('$C');
SQL
is A60h "$(psq "select public.connected_member('$C');")" "t" "no rows + snapshot still grandfathers"
is A60i "$(psq "select public.membership_state('$C');")" "grandfathered" "state(grandfathered)"
is A60j "$(psq "select public.membership_state('$D');")" "unknown" "state(unknown)"
is A60k "$(psq "select public.connected_member(null);")" "f" "NULL input fails closed"

# ================================================ ACL survived REPLACE
echo
echo "-- CREATE OR REPLACE must not resurrect privileges"
for R in anon authenticated service_role; do
  is "A61-$R" "$(psq "select has_function_privilege('$R','public.connected_member(uuid)','execute');")" "f" "connected_member not executable by $R"
done
is A61b "$(psq "select has_function_privilege('service_role','public.membership_state(uuid)','execute');")" "t" "membership_state still granted to service_role"
is A61c "$(psq "select has_function_privilege('authenticated','public.membership_state(uuid)','execute');")" "f" "membership_state still denied to authenticated"

# ==================================================== the two U5b grants
echo
echo "-- the entire U5b privilege delta is two grants"
is A62  "$(psq "select has_function_privilege('authenticated','public.ensure_membership_binding()','execute');")" "t" "ensure_membership_binding GRANTED to authenticated"
is A62b "$(psq "select has_function_privilege('anon','public.ensure_membership_binding()','execute');")" "f" "...and NOT to anon"
is A62c "$(psq "select has_function_privilege('service_role','public.membership_establish_v1(uuid,text,text,uuid,uuid,jsonb)','execute');")" "t" "establish granted to service_role"
for R in anon authenticated; do
  is "A62d-$R" "$(psq "select has_function_privilege('$R','public.membership_establish_v1(uuid,text,text,uuid,uuid,jsonb)','execute');")" "f" "establish NOT executable by $R"
done
is A62e "$(psq "select count(*) from information_schema.table_privileges where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated','service_role','PUBLIC');")" "0" "zero table privileges on any membership table"

# =============================================== establishment behaviour
echo
echo "-- membership_establish_v1"

# A63 — happy path. Apple reports OUR token and the JWS carried it: provenance
# is 'purchase', DERIVED from which artefact carried the token, never supplied.
R=$(establish "$D" Production TXN-EST-1 "'$(psq "select binding_token from public.membership_binding where user_id='$D';")'::uuid" "'$(psq "select binding_token from public.membership_binding where user_id='$D';")'::uuid" "$(st "now() + interval '30 days'" "- interval '1 hour'")")
is A63  "$(echo "$R" | jq -r '.outcome')" "established" "establishes on a confirmed own token"
is A63b "$(psq "select binding_method from public.membership where user_id='$D' and environment='Production';")" "purchase" "provenance derived as purchase"

# F11 — established row carries NO schedule, on every insert path.
is A63c "$(psq "select coalesce(pending_cleanup_at::text,'null') from public.membership where user_id='$D';")" "null" "F11: pending_cleanup_at NULL on establishment"
is A63d "$(psq "select coalesce(entitlement_ended_at::text,'null') from public.membership where user_id='$D';")" "null" "F11: entitlement_ended_at NULL on establishment"

# A63e — the BORN-LAPSED case. Apple says not entitled at first contact; the row
# is still created, and STILL carries no schedule. Without this rule U5 becomes
# the unit that can schedule destruction on first contact, with a deadline
# already in the past.
E2=$(mkuser u5e)
psq "select set_config('request.jwt.claims','{\"sub\":\"$E2\"}',false); select public.ensure_membership_binding();" >/dev/null
TOKE=$(psq "select binding_token from public.membership_binding where user_id='$E2';")
R=$(establish "$E2" Production TXN-EST-LAPSED "'$TOKE'::uuid" "'$TOKE'::uuid" "$(st "now() - interval '400 days'" "- interval '1 hour'")")
is A63f "$(echo "$R" | jq -r '.outcome')" "established" "born-lapsed subscription still establishes"
is A63g "$(echo "$R" | jq -r '.entitled')" "false" "...and is correctly derived not-entitled"
is A63h "$(psq "select coalesce(pending_cleanup_at::text,'null')||'/'||coalesce(entitlement_ended_at::text,'null') from public.membership where user_id='$E2';")" "null/null" "F11 holds for a born-lapsed establishment"

# A63i — legacy provenance: Apple reports our token but the JWS did not carry it.
F2=$(mkuser u5f)
psq "select set_config('request.jwt.claims','{\"sub\":\"$F2\"}',false); select public.ensure_membership_binding();" >/dev/null
TOKF=$(psq "select binding_token from public.membership_binding where user_id='$F2';")
R=$(establish "$F2" Production TXN-EST-LEGACY "'$TOKF'::uuid" "null" "$(st "now() + interval '30 days'" "- interval '1 hour'")")
is A63i "$(psq "select binding_method from public.membership where user_id='$F2';")" "legacy_claim" "provenance derived as legacy_claim"

# A63j — ownership is established ONCE. A second call must not re-provenance.
R=$(establish "$F2" Production TXN-EST-LEGACY "'$TOKF'::uuid" "'$TOKF'::uuid" "$(st "now() + interval '60 days'" "+ interval '1 hour'")")
is A63j "$(echo "$R" | jq -r '.outcome')" "already_established" "second call does not re-establish"
is A63k "$(psq "select binding_method from public.membership where user_id='$F2';")" "legacy_claim" "binding_method NOT re-provenanced"
is A63l "$(echo "$R" | jq -r '.refresh.outcome')" "applied" "refresh delegated to the CANONICAL writer"
is A63m "$(psq "select count(*) from public.membership where user_id='$F2';")" "1" "still exactly one row"

# ============================== A29 / A31 / the A30 SQL-side precondition
echo
echo "-- A29, A31, and the A30 PRECONDITION (not A30 itself)"

# A29 — a token belonging to ANOTHER live binding. Grant nothing, change nothing.
R=$(establish "$C" Production TXN-FOREIGN "'$TOKA'::uuid" "'$TOKA'::uuid" "$(st "now() + interval '30 days'" "- interval '1 hour'")")
is A29  "$(echo "$R" | jq -r '.outcome')" "conflict" "foreign live token is REFUSED"
is A29b "$(psq "select count(*) from public.membership where user_id='$C';")" "0" "...and created no membership row"
is A29c "$(psq "select conflict_kind from public.membership_binding_conflict where user_id='$C';")" "live_binding_mismatch" "...and recorded the conflict"
is A29d "$(psq "select observed_count from public.membership_binding_conflict where user_id='$C';")" "1" "conflict counted once"

# A29e — bounded: a repeat increments rather than adding a row.
establish "$C" Production TXN-FOREIGN "'$TOKA'::uuid" "'$TOKA'::uuid" "$(st "now() + interval '30 days'" "- interval '1 hour'")" >/dev/null
is A29e "$(psq "select observed_count from public.membership_binding_conflict where user_id='$C';")" "2" "repeat increments the counter"
is A29f "$(psq "select count(*) from public.membership_binding_conflict where user_id='$C';")" "1" "...and adds no second row"

# A31 — an ORPHAN token is distinguished from a mismatch, and neither is
# silently bound. Orphan rebind is permitted BY DESIGN but requires the Apple
# round trip, so U5b refuses and says why.
R=$(establish "$C" Production TXN-ORPHAN "'11111111-2222-4333-8444-555555555555'::uuid" "null" "$(st "now() + interval '30 days'" "- interval '1 hour'")")
is A31  "$(echo "$R" | jq -r '.outcome')" "requires_claim" "orphan token is NOT silently bound"
is A31b "$(echo "$R" | jq -r '.reason' | grep -c orphan)" "1" "...and is reported as an orphan, not a mismatch"
is A31c "$(psq "select count(*) from public.membership where user_id='$C';")" "0" "...and created no row"

# A30-PRE — Apple reports NO token. Establishment must refuse: binding it is a
# legacy claim, which needs Set App Account Token and an independent re-read.
# THIS IS THE PRECONDITION FOR A30, NOT A30.
R=$(establish "$C" Production TXN-NOTOKEN "null" "null" "$(st "now() + interval '30 days'" "- interval '1 hour'")")
is A30pre  "$(echo "$R" | jq -r '.outcome')" "requires_claim" "no Apple token -> refuses to establish"
is A30preb "$(echo "$R" | jq -r '.established')" "false" "...and says it established nothing"
is A30prec "$(psq "select count(*) from public.membership where user_id='$C';")" "0" "...and wrote no membership row"

# A64 — the same subscription claimed by a second identity. The uniqueness
# constraint must surface as a recorded conflict, never a 5xx and never a
# second entitled identity.
R=$(establish "$C" Production TXN-EST-1 "'$TOKC'::uuid" "'$TOKC'::uuid" "$(st "now() + interval '30 days'" "- interval '1 hour'")")
is A64  "$(echo "$R" | jq -r '.outcome')" "conflict" "second identity cannot claim an established subscription"
is A64b "$(psq "select count(*) from public.membership where original_transaction_id='TXN-EST-1';")" "1" "still exactly one row for that subscription"
is A64c "$(psq "select conflict_kind from public.membership_binding_conflict where user_id='$C' and original_transaction_id='TXN-EST-1';")" "transaction_owned_by_other_identity" "recorded with the right kind"

# A65 — ownership is a precondition of writing, restated at this entry point.
G2=$(mkuser u5g)
is A65 "$(psq "select public.membership_establish_v1('$G2','Production','TXN-NOBIND','$TOKA'::uuid,null,$(st "now() + interval '30 days'" "- interval '1 hour'"));" | grep -c 'no binding')" "1" "no binding row -> refused"

# ==================================================== structural invariants
echo
echo "-- structural"
is A67  "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and pg_get_functiondef(p.oid) ~* 'insert into public\.membership *\(';")" "1" "exactly ONE function inserts into public.membership"
is A67b "$(psq "select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and pg_get_functiondef(p.oid) ~* 'insert into public\.membership *\(';")" "membership_establish_v1" "...and it is the establishment writer"
#
# REWRITTEN AT U6a, 2026-08-30, for the same reason as U4's A57b: the old form
# stayed green under U6a while the claim it made became false. See A57b.
is A67c "$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) ~* 'connected_member|membership|shadow_observe';")" "23" "the 23 enumerated policies consult shadow telemetry"
is A67c2 "$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) ~* 'connected_member\\(|membership_state\\(|connected_member_self\\(';")" "0" "...and U5b's writers are still consulted by NO policy -- enforcement is not bound"
is A67c3 "$(psq "select public.shadow_observe('probe.a67c')::text;")" "true" "...and the observer is inert: it returns true, always"
is A67d "$(psq "select count(*) from public.membership where pending_cleanup_at is not null;")" "0" "U5b scheduled no cleanup anywhere"
is A67e "$(psq "select relrowsecurity::text from pg_class where relname='membership_binding_conflict';")" "true" "RLS enabled on the conflict table"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
