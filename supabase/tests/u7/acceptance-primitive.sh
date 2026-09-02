#!/usr/bin/env bash
#
# U7b HALF A — THE CLEANUP PRIMITIVE. LOCAL ONLY.
#
#   supabase db reset --local && ./supabase/tests/u7/acceptance-primitive.sh
#
# SCORED SEPARATELY FROM HALF B, WITH ITS OWN TALLY AND ITS OWN EXIT CODE, so a
# green primitive can never carry a red writer correction or the reverse. This
# suite NEVER calls membership_apply_state_v1 and never exercises the born-lapsed
# floor; every schedule below is written by direct INSERT, which is what keeps
# the two halves' evidence disjoint.
#
# WHAT THIS CLAIMS. (1) Selection is bounded exactly as predicted, including that
# an identity with no membership row is unreachable. (2) The selector returns the
# WHOLE identity, which is the rule a per-row implementation breaks. (3) The lease
# is durable, expires, and recovers a crashed run. (4) Completion is idempotent
# and touches no Apple state. (5) The privilege surface is two EXECUTE grants.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-8s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-8s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo; echo "U7b HALF A — cleanup primitive"; echo

# --------------------------------------------------------------- fixtures
# Six identities. Named for the state they are in, not for their order.
DUE=00000000-0000-0000-0000-0000000d0001   # one Sandbox row, due
FUT=00000000-0000-0000-0000-0000000d0002   # scheduled, not yet due
NOS=00000000-0000-0000-0000-0000000d0003   # lapsed, NO schedule
NON=00000000-0000-0000-0000-0000000d0004   # no membership row at all
DUA=00000000-0000-0000-0000-0000000d0005   # due Sandbox + LIVE Production
TWO=00000000-0000-0000-0000-0000000d0006   # both environments due
CTL=00000000-0000-0000-0000-0000000d0007   # control: due, never touched

mkid() { psq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at)
  values ('$1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$2@local.invalid',now(),now())
  on conflict do nothing;" >/dev/null; }
mkbind() { psq "insert into public.membership_binding (user_id) values ('$1') on conflict do nothing;" >/dev/null; }

# $1 uid  $2 env  $3 renewal_date  $4 entitlement_ended_at  $5 pending_cleanup_at
mkmem() {
  psq "insert into public.membership
    (user_id, environment, original_transaction_id, product_id, apple_status,
     renewal_date, renewal_info_signed_date, binding_method, bound_at,
     entitlement_ended_at, pending_cleanup_at)
   values ('$1','$2','otid-$1-$2','etudes.connected.monthly',1,
     $3, now() - interval '1 day', 'purchase', now() - interval '1 day',
     $4, $5);" >/dev/null; }

for p in "$DUE due" "$FUT fut" "$NOS nos" "$NON non" "$DUA dua" "$TWO two" "$CTL ctl"; do
  set -- $p; mkid "$1" "u7a-$2"; mkbind "$1"; done

mkmem "$DUE" Sandbox    "now() - interval '90 days'" "now() - interval '90 days'" "now() - interval '30 days'"
mkmem "$FUT" Sandbox    "now() - interval '10 days'" "now() - interval '10 days'" "now() + interval '50 days'"
mkmem "$NOS" Sandbox    "now() - interval '90 days'" "now() - interval '90 days'" "null"
mkmem "$DUA" Sandbox    "now() - interval '90 days'" "now() - interval '90 days'" "now() - interval '30 days'"
mkmem "$DUA" Production "now() + interval '20 days'" "null"                       "null"
mkmem "$TWO" Sandbox    "now() - interval '90 days'" "now() - interval '90 days'" "now() - interval '30 days'"
mkmem "$TWO" Production "now() - interval '95 days'" "now() - interval '95 days'" "now() - interval '35 days'"
mkmem "$CTL" Sandbox    "now() - interval '90 days'" "now() - interval '90 days'" "now() - interval '10 days'"

# NON-VACUITY. An empty fixture is not a pass.
is A-1a "$(psq "select count(*) from auth.users where id::text like '00000000-0000-0000-0000-0000000d%';")" "7" "seven identities exist"
is A-1b "$(psq "select count(*) from public.membership where user_id::text like '00000000-0000-0000-0000-0000000d%';")" "8" "eight membership rows exist (1+1+1+2+2+1)"
is A-1c "$(psq "select count(*) from public.membership where user_id='$NON';")" "0" "NON deliberately has no membership row"

sel() { psq "select user_id::text||'/'||environment from public.membership_due_for_cleanup_v1($1) order by 1;"; }
claimcnt() { psq "select count(*) from public.membership where user_id='$1' and cleanup_claimed_at is not null;"; }
unclaim() { psq "update public.membership set cleanup_claimed_at = null;" >/dev/null; }

# ------------------------------------------------------- selection boundaries
ROWS=$(sel 50)
is A-2  "$(printf '%s\n' "$ROWS" | grep -c "^$DUE/Sandbox$")" "1" "due row IS selected"
is A-3  "$(printf '%s\n' "$ROWS" | grep -c "^$FUT/")"         "0" "N6 future schedule NOT selected"
is A-4  "$(printf '%s\n' "$ROWS" | grep -c "^$NOS/")"         "0" "N7 no schedule NOT selected"
is A-5  "$(printf '%s\n' "$ROWS" | grep -c "^$NON/")"         "0" "N8 no membership row NOT selected"
is A-6  "$(printf '%s\n' "$ROWS" | grep -c "^$DUA/")"         "2" "N5 candidate identity yields BOTH environments"
is A-6b "$(printf '%s\n' "$ROWS" | grep -c "^$DUA/Production$")" "1" "the LIVE Production row is returned as context"
is A-7  "$(psq "select coalesce(pending_cleanup_at::text,'null') from public.membership where user_id='$DUA' and environment='Production';")" "null" "selector did not schedule the live row"

unclaim
is A-8  "$(sel 1 | cut -d/ -f1 | sort -u | wc -l | tr -d ' ')" "1" "N: p_limit bounds IDENTITIES"
unclaim
is A-8b "$(sel 1 | wc -l | tr -d ' ')" "2" "and returns ALL rows of that one identity"
unclaim
is A-9  "$(sel 1 | head -1 | cut -d/ -f1)" "$TWO" "oldest pending_cleanup_at first"
unclaim
is A-9b "$(psq "select 1 from public.membership_due_for_cleanup_v1(0);" 2>&1 | grep -c ERROR)" "1" "p_limit < 1 is refused"

# --------------------------------------------------------------------- lease
unclaim
FIRST=$(sel 50)
is A-10 "$(printf '%s\n' "$FIRST" | grep -c "^$DUE/")" "1" "first call returns the candidate"
is A-10b "$(claimcnt "$DUE")" "1" "and claims it"
is A-11 "$(sel 50 | grep -c "^$DUE/")" "0" "A-11 immediate second call returns NOTHING — the claim holds"
is A-12 "$(psq "select coalesce(cleanup_claimed_at::text,'null') from public.membership where user_id='$DUA' and environment='Production';")" "null" "the LIVE row is returned but never claimed"
is A-12b "$(claimcnt "$DUA")" "1" "exactly the due row of that identity is claimed"

psq "update public.membership set cleanup_claimed_at = now() - interval '2 hours' where user_id='$DUE';" >/dev/null
is A-13 "$(sel 50 | grep -c "^$DUE/")" "1" "N: an EXPIRED claim makes the identity a candidate again"
is A-14 "$(psq "select pg_get_functiondef(oid) ~ 'interval ''1 hour''' from pg_proc where proname='membership_due_for_cleanup_v1';")" "t" "lease interval is one hour"
is A-15 "$(psq "select public.connected_member('$DUA');")" "t" "a claim does not alter entitlement (DUA still Production-entitled)"
is A-15b "$(psq "select public.membership_state('$DUE');")" "sandbox_only" "a claim does not alter membership_state"

# ---------------------------------------------------------------- completion
BEFORE_CTL=$(psq "select md5(string_agg(m::text,'|' order by m.environment)) from public.membership m where m.user_id='$CTL';")
APPLE_BEFORE=$(psq "select renewal_date::text||'|'||coalesce(entitlement_ended_at::text,'-')||'|'||binding_method||'|'||original_transaction_id from public.membership where user_id='$TWO' and environment='Sandbox';")

R1=$(psq "select public.membership_cleanup_complete_v1('$TWO');")
is A-16  "$(printf '%s' "$R1" | grep -c '"outcome": "completed"')" "1" "completion reports completed"
is A-16b "$(psq "select count(*) from public.membership where user_id='$TWO' and pending_cleanup_at is not null;")" "0" "pending_cleanup_at cleared"
is A-16c "$(psq "select count(*) from public.membership where user_id='$TWO' and cleanup_claimed_at is not null;")" "0" "lease cleared"
is A-16d "$(psq "select count(*) from public.membership where user_id='$TWO' and cleanup_completed_at is not null;")" "2" "cleanup_completed_at set"
is A-17  "$(printf '%s' "$R1" | grep -c '"rows": 2')" "1" "A-17 BOTH environments' schedules cleared"

STAMP=$(psq "select max(cleanup_completed_at)::text from public.membership where user_id='$TWO';")
R2=$(psq "select public.membership_cleanup_complete_v1('$TWO');")
is A-18  "$(printf '%s' "$R2" | grep -c '"outcome": "noop"')" "1" "N19/QA-C8 second call is a NO-OP"
is A-18b "$(printf '%s' "$R2" | grep -c '"rows": 0')" "1" "and touches zero rows"
is A-18c "$(psq "select max(cleanup_completed_at)::text from public.membership where user_id='$TWO';")" "$STAMP" "cleanup_completed_at NOT overwritten by the repeat"
is A-19  "$(sel 50 | grep -c "^$TWO/")" "0" "a completed identity is no longer selected"
is A-20  "$(psq "select renewal_date::text||'|'||coalesce(entitlement_ended_at::text,'-')||'|'||binding_method||'|'||original_transaction_id from public.membership where user_id='$TWO' and environment='Sandbox';")" "$APPLE_BEFORE" "A-20 completion touched NO Apple state"
is A-21  "$(psq "select md5(string_agg(m::text,'|' order by m.environment)) from public.membership m where m.user_id='$CTL';")" "$BEFORE_CTL" "A-21 control identity byte-identical"
is A-22  "$(psq "select public.membership_cleanup_complete_v1(null);" 2>&1 | grep -c '22004\|no user_id')" "1" "null argument raises"

# ------------------------------------------------------------------ privilege
priv() { psq "select has_function_privilege('$1','public.$2','execute');"; }
for r in anon authenticated; do
  is "A-23/$r" "$(priv $r 'membership_due_for_cleanup_v1(integer)')" "f" "$r cannot execute the selector"
  is "A-24/$r" "$(priv $r 'membership_cleanup_complete_v1(uuid)')"   "f" "$r cannot execute completion"
done
is A-23s "$(priv service_role 'membership_due_for_cleanup_v1(integer)')" "t" "service_role CAN execute the selector"
is A-24s "$(priv service_role 'membership_cleanup_complete_v1(uuid)')"   "t" "service_role CAN execute completion"
is A-23p "$(psq "select coalesce(bool_or(g.grantee='PUBLIC'),false) from information_schema.routine_privileges g join pg_proc p on p.proname=g.routine_name where g.routine_name in ('membership_due_for_cleanup_v1','membership_cleanup_complete_v1');")" "f" "PUBLIC holds nothing"
is A-25 "$(psq "select count(*) from information_schema.table_privileges where grantee='service_role' and table_name in ('membership','membership_binding','membership_control','membership_notification','membership_binding_conflict','membership_notification_reject_stat');")" "0" "A-25 service_role holds ZERO table privilege on all six"

# ------------------------------------- structural: U7b deletes and creates nothing
is A-26 "$(psq "select count(*) from pg_proc where proname in ('membership_due_for_cleanup_v1','membership_cleanup_complete_v1') and pg_get_functiondef(oid) ~* 'delete[[:space:]]+from';")" "0" "A-26 NO delete statement in either new function"
is A-27 "$(psq "select count(*) from pg_proc where proname in ('membership_due_for_cleanup_v1','membership_cleanup_complete_v1') and pg_get_functiondef(oid) ~* 'insert[[:space:]]+into[[:space:]]+public\.membership';")" "0" "A-27 neither function originates a membership row"

echo; echo "  HALF A: $PASS passed, $FAIL failed"; echo
[ "$FAIL" -eq 0 ]
