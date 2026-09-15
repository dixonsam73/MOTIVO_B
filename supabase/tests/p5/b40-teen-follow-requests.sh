#!/usr/bin/env bash
#
# B-40 / A4 — A 13-17 MEMBER'S INBOUND FOLLOW REQUESTS ARE CLOSED SERVER-SIDE. LOCAL STACK.
#
#   ./supabase/tests/p5/b40-teen-follow-requests.sh before   # schema as found
#   ./supabase/tests/p5/b40-teen-follow-requests.sh after    # B-40 migration applied INSIDE the transaction
#
# ROLLBACK ONLY. Fixtures (fresh ids) and, in `after`, the migration run in ONE
# transaction that is rolled back: no reset, no persistent apply, no retained fixture.
# Enforcement is not touched. Function definitions, grants and row counts are
# fingerprinted before and after to show the stack is left as found.
#
# The setter, self read, upsert and follows inserts run as `authenticated` with the
# actor's JWT claims (RLS applies; `authenticated` does not bypass it). The two
# internal helpers are observed from the privileged connection. An expected refusal
# must be an RLS rejection; any other error is reported as SETUP-ERROR (inconclusive).
#
# Exit: 0 all six pass, 1 a check failed, 3 inconclusive (setup error / missing check /
# state changed).

set -uo pipefail
cd "$(dirname "$0")/../../.."
MODE="${1:-}"
[ "$MODE" = before ] || [ "$MODE" = after ] || { echo "usage: $0 before|after"; exit 2; }
MIG=supabase/migrations/20260915150000_b40_teen_follow_requests_closed.sql

DB=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1)
[ "$DB" = "supabase_db_rlwtqxumfobakvdueugm" ] || { echo "not the existing local stack ('$DB'); refusing"; exit 3; }
psq() { docker exec -i "$DB" psql -U postgres -d postgres -At -q -v ON_ERROR_STOP=1 "$@"; }

FINGERPRINT="select md5(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || pg_get_functiondef(p.oid) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname))
               || ' users=' || (select count(*) from auth.users)
               || ' privacy=' || (select count(*) from public.account_privacy)
               || ' follows=' || (select count(*) from public.follows)
               || ' shadow=' || (select count(*) from public.shadow_enforcement_stat)
               || ' enforcing=' || public.enforcement_active()
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('account_privacy_requests_open','account_privacy_self_v1','account_privacy_upsert_v1','account_privacy_set_follow_requests_v1','account_privacy_set_lookup_v1','account_privacy_discoverable','follow_requests_open');"

echo; echo "B-40 — teen inbound follow requests ($MODE)"
echo "target: container $DB, database $(psq -c 'select current_database()')"
STATE_BEFORE=$(psq -c "$FINGERPRINT")
echo "state before: $STATE_BEFORE"
case "$STATE_BEFORE" in *"enforcing=true"*) echo "enforcement is active locally; requester entitlement fixtures would be needed — not arranged by this script; stopping"; exit 3;; esac

T=$(uuidgen | tr 'A-Z' 'a-z'); A=$(uuidgen | tr 'A-Z' 'a-z'); R=$(uuidgen | tr 'A-Z' 'a-z')
as() { printf "set local role authenticated;\nselect set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', true) is not null as claims;\n" "$1"; }

{
  echo "begin;"
  if [ "$MODE" = after ]; then cat "$MIG"; echo; fi
  cat <<SQL
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('$T','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b40-t-$T@local.invalid',now(),now()),
 ('$A','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b40-a-$A@local.invalid',now(),now()),
 ('$R','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b40-r-$R@local.invalid',now(),now());

-- SETUP through the real client paths. Teen T reaches the A4 state via the writer.
$(as "$T")
select 'SETUP|T upsert|' || o_age_band from public.account_privacy_upsert_v1('band_13_17');
select 'SETUP|T setter|' || public.account_privacy_set_follow_requests_v1(true);
reset role;
$(as "$A")
select 'SETUP|A upsert|' || o_age_band || ' enabled=' || o_follow_requests_enabled from public.account_privacy_upsert_v1('band_18_plus');
reset role;
select 'SETUP|T row|' || age_band || ' enabled=' || follow_requests_enabled || ' set_under=' || follow_requests_set_under_band
  from public.account_privacy where user_id = '$T';

-- CHECK 1 — helper (privileged observation).
select 'CHECK|1|' || case when public.account_privacy_requests_open('$T') = false then 'PASS' else 'FAIL' end
       || '|account_privacy_requests_open(T)=' || public.account_privacy_requests_open('$T');

-- CHECK 2 — self read as T.
$(as "$T")
select 'CHECK|2|' || case when o_follow_requests_effective = false then 'PASS' else 'FAIL' end
       || '|self_v1 as T effective=' || o_follow_requests_effective from public.account_privacy_self_v1();

-- CHECK 3 — upsert return as T.
select 'CHECK|3|' || case when o_follow_requests_effective = false then 'PASS' else 'FAIL' end
       || '|upsert_v1(band_13_17) as T effective=' || o_follow_requests_effective from public.account_privacy_upsert_v1('band_13_17');
reset role;

-- CHECK 4 — R's follow request toward T must be refused BY RLS.
$(as "$R")
do \$b40\$ begin
  insert into public.follows (follower_user_id, followed_user_id, status) values ('$R', '$T', 'requested');
  raise notice 'CHECK|4|FAIL|follows insert R->T accepted';
exception
  when insufficient_privilege then
    if sqlerrm like 'new row violates row-level security policy%' then
      raise notice 'CHECK|4|PASS|refused by RLS: %', sqlerrm;
    else
      raise notice 'CHECK|4|SETUP-ERROR|42501 but not an RLS rejection: %', sqlerrm;
    end if;
  when others then
    raise notice 'CHECK|4|SETUP-ERROR|% %', sqlstate, sqlerrm;
end \$b40\$;
reset role;

-- CHECK 5 — adult control: open for A, and R's request toward A is accepted.
select 'CHECK|5a|' || case when public.account_privacy_requests_open('$A') = true then 'PASS' else 'FAIL' end
       || '|account_privacy_requests_open(A)=' || public.account_privacy_requests_open('$A');
$(as "$A")
select 'CHECK|5b|' || case when o_follow_requests_effective = true then 'PASS' else 'FAIL' end
       || '|self_v1 as A effective=' || o_follow_requests_effective from public.account_privacy_self_v1();
reset role;
$(as "$R")
do \$b40\$ begin
  insert into public.follows (follower_user_id, followed_user_id, status) values ('$R', '$A', 'requested');
  raise notice 'NOTE|5c|follows insert R->A accepted';
exception when others then
  raise notice 'NOTE|5c|follows insert R->A refused: % %', sqlstate, sqlerrm;
end \$b40\$;
reset role;
select 'CHECK|5c|' || case when exists (select 1 from public.follows where follower_user_id = '$R' and followed_user_id = '$A' and status = 'requested') then 'PASS' else 'FAIL' end
       || '|R->A requested row present';

-- CHECK 6 — discovery unchanged: a teen's own opt-in stays effective.
$(as "$T")
select 'SETUP|T set_lookup|' || public.account_privacy_set_lookup_v1(true);
reset role;
select 'CHECK|6|' || case when public.account_privacy_discoverable('$T') = true then 'PASS' else 'FAIL' end
       || '|account_privacy_discoverable(T)=' || public.account_privacy_discoverable('$T');

rollback;
SQL
} > /tmp/b40-$$.sql

OUT=$(docker exec -i "$DB" psql -U postgres -d postgres -At -q -v ON_ERROR_STOP=1 < /tmp/b40-$$.sql 2>&1); PSQL_EXIT=$?
rm -f /tmp/b40-$$.sql
echo "$OUT" | sed -E 's/^.*NOTICE:  //' | grep -E '^(SETUP|CHECK|NOTE)\|' | sed 's/^/  /'

STATE_AFTER=$(psq -c "$FINGERPRINT")
echo "state after:  $STATE_AFTER"

INCONCLUSIVE=0; FAILED=0; PASSED=0
if [ $PSQL_EXIT -ne 0 ]; then
  echo "INCONCLUSIVE: the transaction stopped on an error (psql exit $PSQL_EXIT):"; echo "$OUT" | grep -iE 'error' | head -5 | sed 's/^/    /'; INCONCLUSIVE=1
fi
echo "$OUT" | grep -q 'CHECK|[0-9a-z]*|SETUP-ERROR' && { echo "INCONCLUSIVE: a refusal was not an RLS rejection"; INCONCLUSIVE=1; }
[ "$STATE_BEFORE" = "$STATE_AFTER" ] || { echo "INCONCLUSIVE: definitions, grants or row counts changed"; INCONCLUSIVE=1; }

check() { # id, component ids...
  local id=$1; shift; local all=PASS
  for c in "$@"; do
    local line; line=$(echo "$OUT" | grep -oE "CHECK\|$c\|[A-Z-]+" | head -1)
    case "$line" in "CHECK|$c|PASS") ;; "CHECK|$c|FAIL") all=FAIL ;; *) all=MISSING ;; esac
    [ "$all" = MISSING ] && break
  done
  case $all in PASS) PASSED=$((PASSED+1));; FAIL) FAILED=$((FAILED+1));; *) INCONCLUSIVE=1;; esac
  printf "  %-8s check %s\n" "$all" "$id"
}
echo "results:"
check 1 1; check 2 2; check 3 3; check 4 4; check 5 5a 5b 5c; check 6 6
echo "summary: $PASSED passed, $FAILED failed of 6 ($MODE); state unchanged: $([ "$STATE_BEFORE" = "$STATE_AFTER" ] && echo yes || echo no)"
[ $INCONCLUSIVE -eq 1 ] && exit 3
[ $FAILED -eq 0 ] && exit 0 || exit 1
