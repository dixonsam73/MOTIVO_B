#!/usr/bin/env bash
#
# U7b HALF B — THE BORN-LAPSED QUARANTINE FLOOR. LOCAL ONLY.
#
#   supabase db reset --local && ./supabase/tests/u7/acceptance-bornlapsed.sh
#
# SCORED SEPARATELY FROM HALF A, WITH ITS OWN TALLY AND ITS OWN EXIT CODE. This
# suite exercises membership_apply_state_v1 ONLY. It never calls
# membership_due_for_cleanup_v1 or membership_cleanup_complete_v1, and its
# identities are disjoint from Half A's — so neither half can satisfy an
# assertion belonging to the other.
#
# WHAT THIS CLAIMS. (1) A first schedule is never written already-past. (2) The
# guard FIRES on the born-lapsed shape and CANNOT fire on an ordinary lapse —
# asserted in both directions, because a guard that never fires and a guard that
# always fires are both defects and only one is visible. (3) Nothing else about
# the canonical writer moved: anti-sliding, cancellation, staleness, F11 and
# UPDATE-ONLY all still hold.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-8s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-8s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo; echo "U7b HALF B — born-lapsed quarantine floor"; echo

ORD=00000000-0000-0000-0000-0000000e0001   # ordinary lapse — floor must NOT fire
BORN=00000000-0000-0000-0000-0000000e0002  # born-lapsed    — floor MUST fire
SLID=00000000-0000-0000-0000-0000000e0003  # existing schedule — never pushed out
CANC=00000000-0000-0000-0000-0000000e0004  # entitled again — cancellation
ESTB=00000000-0000-0000-0000-0000000e0005  # F11: establishment schedules nothing

mkid() { psq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at)
  values ('$1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$2@local.invalid',now(),now())
  on conflict do nothing;" >/dev/null; }
for p in "$ORD ord" "$BORN born" "$SLID slid" "$CANC canc" "$ESTB estb"; do
  set -- $p; mkid "$1" "u7b-$2"
  psq "insert into public.membership_binding (user_id) values ('$1') on conflict do nothing;" >/dev/null
done

# A row with NO schedule, exactly as membership_establish_v1 leaves one (F11).
seed() {
  psq "insert into public.membership
    (user_id, environment, original_transaction_id, product_id, apple_status,
     renewal_date, renewal_info_signed_date, binding_method, bound_at,
     entitlement_ended_at, pending_cleanup_at)
   values ('$1','Sandbox','otid-$1','etudes.connected.monthly',1,
     $2, now() - interval '400 days', 'purchase', now() - interval '400 days',
     null, null);" >/dev/null; }

# $1 uid  $2 renewal_date literal  $3 signed_date literal
apply() {
  psq "select public.membership_apply_state_v1('$1','Sandbox','otid-$1',
    jsonb_build_object(
      'product_id','etudes.connected.monthly',
      'apple_status', 2,
      'renewal_date', $2,
      'is_in_billing_retry', false,
      'renewal_info_signed_date', $3), null);"; }

is B-1a "$(psq "select count(*) from auth.users where id::text like '00000000-0000-0000-0000-0000000e%';")" "5" "five identities exist"

# ------------------------------------------------------------ B-2 ordinary lapse
seed "$ORD" "now() - interval '400 days'"
R=$(apply "$ORD" "to_jsonb((now() - interval '1 hour')::text)" "to_jsonb(now()::text)")
is B-2  "$(printf '%s' "$R" | grep -c '"outcome": "applied"')" "1" "ordinary lapse applies"
ORD_END=$(psq "select entitlement_ended_at::text from public.membership where user_id='$ORD';")
is B-2b "$(psq "select (pending_cleanup_at between now() + interval '59 days' and now() + interval '61 days') from public.membership where user_id='$ORD';")" "t" "schedule is ~now + 60d"
is B-6  "$(psq "select pending_cleanup_at = entitlement_ended_at + interval '60 days' from public.membership where user_id='$ORD';")" "t" "B-6 N24 the floor CANNOT fire on an ordinary lapse — schedule is EXACTLY ended+60d"

# ---------------------------------------------------------------- B-3 born-lapsed
seed "$BORN" "now() - interval '400 days'"
R=$(apply "$BORN" "to_jsonb((now() - interval '240 days')::text)" "to_jsonb(now()::text)")
is B-3a "$(printf '%s' "$R" | grep -c '"outcome": "applied"')" "1" "born-lapsed transition applies"
is B-3  "$(psq "select pending_cleanup_at > now() from public.membership where user_id='$BORN';")" "t" "B-3 N22 the schedule is NOT already past"
is B-3b "$(psq "select pending_cleanup_at >= now() + interval '59 days' from public.membership where user_id='$BORN';")" "t" "and is a genuine 60-day quarantine"
is B-4  "$(psq "select entitlement_ended_at < now() - interval '239 days' from public.membership where user_id='$BORN';")" "t" "B-4 entitlement_ended_at is STILL Apple's truth, ~240 days past"
is B-5  "$(psq "select (pending_cleanup_at - (entitlement_ended_at + interval '60 days')) > interval '100 days' from public.membership where user_id='$BORN';")" "t" "B-5 N24 the guard DEMONSTRABLY FIRED — schedule differs from ended+60d by >100d"

# ------------------------------------------------------------- B-7 anti-sliding
seed "$SLID" "now() - interval '400 days'"
apply "$SLID" "to_jsonb((now() - interval '1 hour')::text)" "to_jsonb((now() - interval '10 minutes')::text)" >/dev/null
FIRST_SCHED=$(psq "select pending_cleanup_at::text from public.membership where user_id='$SLID';")
FIRST_END=$(psq "select entitlement_ended_at::text from public.membership where user_id='$SLID';")
apply "$SLID" "to_jsonb(now()::text)" "to_jsonb(now()::text)" >/dev/null
is B-7  "$(psq "select pending_cleanup_at::text from public.membership where user_id='$SLID';")" "$FIRST_SCHED" "B-7 N23 an EXISTING schedule is never pushed out"
is B-8  "$(psq "select entitlement_ended_at::text from public.membership where user_id='$SLID';")" "$FIRST_END" "B-8 entitlement_ended_at never slides forward"

# ------------------------------------------------------------ B-9 cancellation
seed "$CANC" "now() - interval '400 days'"
apply "$CANC" "to_jsonb((now() - interval '1 hour')::text)" "to_jsonb((now() - interval '10 minutes')::text)" >/dev/null
is B-9a "$(psq "select pending_cleanup_at is not null from public.membership where user_id='$CANC';")" "t" "lapsed first, so the cancellation is non-vacuous"
apply "$CANC" "to_jsonb((now() + interval '30 days')::text)" "to_jsonb(now()::text)" >/dev/null
is B-9  "$(psq "select pending_cleanup_at is null and entitlement_ended_at is null from public.membership where user_id='$CANC';")" "t" "B-9 QA-C5 entitled again CANCELS the schedule"

# ------------------------------------------------------- B-10 F11, B-11 stale
psq "select public.membership_establish_v1('$ESTB','Sandbox','otid-$ESTB',
   (select binding_token from public.membership_binding where user_id='$ESTB'),
   (select binding_token from public.membership_binding where user_id='$ESTB'),
   jsonb_build_object('product_id','etudes.connected.monthly','apple_status',2,
     'renewal_date', to_jsonb((now() - interval '240 days')::text),
     'is_in_billing_retry', false,
     'renewal_info_signed_date', to_jsonb(now()::text)));" >/dev/null
is B-10a "$(psq "select count(*) from public.membership where user_id='$ESTB';")" "1" "establishment created a row (non-vacuous)"
is B-10  "$(psq "select entitlement_ended_at is null and pending_cleanup_at is null from public.membership where user_id='$ESTB';")" "t" "B-10 F11 establishment STILL schedules nothing, even born-lapsed"

R=$(apply "$ORD" "to_jsonb((now() - interval '1 hour')::text)" "to_jsonb((now() - interval '10 days')::text)")
is B-11 "$(printf '%s' "$R" | grep -c '"outcome": "stale"')" "1" "B-11 an older signed_date is still a no-op"
is B-11b "$(psq "select entitlement_ended_at::text from public.membership where user_id='$ORD';")" "$ORD_END" "and the row is unchanged"

# ------------------------------------------------- B-12/B-13 structural
is B-12 "$(psq "select count(*) from pg_proc where proname='membership_apply_state_v1' and pg_get_functiondef(oid) ~* 'insert[[:space:]]+into[[:space:]]+public\.membership';")" "0" "B-12 the writer is STILL UPDATE-ONLY"
is B-13 "$(psq "select pg_get_functiondef(oid) ~ 'QUARANTINE IS NEVER RETROACTIVELY SPENT' from pg_proc where proname='membership_apply_state_v1';")" "t" "the floor is present in the deployed definition"
is B-13b "$(psq "select (length(pg_get_functiondef(oid)) - length(replace(pg_get_functiondef(oid),'v_cleanup :=','')))/length('v_cleanup :=') from pg_proc where proname='membership_apply_state_v1';")" "3" "B-13 exactly THREE v_cleanup assignments: cancel, compute, floor"

echo; echo "  HALF B: $PASS passed, $FAIL failed"; echo
[ "$FAIL" -eq 0 ]
