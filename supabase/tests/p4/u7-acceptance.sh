#!/usr/bin/env bash
#
# P4-U7 / C-58 — FOLLOW-SCOPED RETAINED ATTRIBUTION. LOCAL STACK.
#
#   supabase db reset --local && ./supabase/tests/p4/u7-acceptance.sh
#
# WHAT THIS CLAIMS. Under LIVE enforcement a lapsed viewer can resolve the
# identity behind a follow relationship they already hold and are allowed to
# remove -- and NOTHING ELSE. The two negative cases are the point: a stranger
# and a merely-REQUESTED relationship both still resolve to nothing, which is
# what separates this from ungating the RPC (the rejected global fix).
#
# NOT IDEMPOTENT ACROSS RUNS WITHOUT A RESET -- it creates fixtures and toggles
# the enforcement flag. It restores the flag to false on the way out.

set -uo pipefail
cd "$(dirname "$0")/../../.."
DB=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1)
[ -n "$DB" ] || { echo "no local stack"; exit 1; }
psq()  { docker exec -i "$DB" psql -U postgres -d postgres -At -q -c "$1" 2>&1; }
psqf() { docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1; }

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo; echo "P4-U7 / C-58 — follow-scoped retained attribution"; echo

V_LAP=00000000-0000-0000-0000-0000000e0001   # lapsed viewer
A_FOL=00000000-0000-0000-0000-0000000e0002   # approved follow, viewer -> author
A_STR=00000000-0000-0000-0000-0000000e0003   # stranger
A_REQ=00000000-0000-0000-0000-0000000e0004   # REQUESTED only
A_REV=00000000-0000-0000-0000-0000000e0005   # approved, author -> viewer
V_ENT=00000000-0000-0000-0000-0000000e0006   # entitled viewer
A_LAP=00000000-0000-0000-0000-0000000e0007   # lapsed author

mk(){ psq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at) values ('$1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$2@local.invalid',now(),now()) on conflict do nothing;" >/dev/null; }
for p in "$V_LAP lap" "$A_FOL fol" "$A_STR str" "$A_REQ req" "$A_REV rev" "$V_ENT ent" "$A_LAP alap"; do
  set -- $p; mk "$1" "u7-$2"
done

psqf <<SQL >/dev/null
insert into public.membership (user_id,environment,original_transaction_id,product_id,apple_status,renewal_date,is_in_billing_retry,renewal_info_signed_date,binding_method,bound_at) values
 ('$V_LAP','Production','u7-lap','p',2, now()-interval '3 days', false, now(),'purchase',now()),
 ('$A_LAP','Production','u7-alap','p',2, now()-interval '3 days', false, now(),'purchase',now()),
 ('$V_ENT','Production','u7-ent','p',1, now()+interval '30 days', false, now(),'purchase',now())
on conflict do nothing;
insert into public.account_directory (user_id,account_id,display_name) values
 ('$A_FOL','u7fol','Followed Author'), ('$A_STR','u7str','A Stranger'),
 ('$A_REQ','u7req','Requested Only'),  ('$A_REV','u7rev','Reverse Follower'),
 ('$A_LAP','u7alap','Lapsed Author')
on conflict do nothing;
insert into public.follows (follower_user_id,followed_user_id,status,created_at,updated_at) values
 ('$V_LAP','$A_FOL','approved',now(),now()),
 ('$V_LAP','$A_REQ','requested',now(),now()),
 ('$A_REV','$V_LAP','approved',now(),now())
on conflict do nothing;
SQL

as(){ psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); $2" | tail -1; }
n(){ as "$1" "select count(*) from public.get_account_directory_by_user_ids(array['$2']::uuid[]);"; }

# ============================================== A. INERT until enforcement is on
echo "-- A  with enforcement OFF nothing about this unit is observable --"
is U7-A1 "$(psq "select enforcement_enabled from public.membership_control where id;")" "f" "precondition: enforcement ships off"
is U7-A2 "$(n "$V_LAP" "$A_STR")" "1" "gate open, so even a stranger resolves — the disjunct is not what is answering"

# ============================================== B. THE UNIT, under enforcement
psq "update public.membership_control set enforcement_enabled=true where id;" >/dev/null
echo; echo "-- B  BOUND: the lapsed viewer can read the relationships they hold --"
is U7-B0 "$(psq "select enforcement_enabled from public.membership_control where id;")" "t" "enforcement is bound for these cases"
is U7-B1 "$(psq "select public.connected_member('$V_LAP')::text;")" "false" "…and the viewer really is unentitled"
is U7-B2 "$(as "$V_LAP" "select count(*) from public.follows;")" "3" "the viewer still SEES their follow rows (D-U6-2, ungated)"
is U7-B3 "$(n "$V_LAP" "$A_FOL")" "1" "C-58: an APPROVED follow now RESOLVES (viewer -> author)"
is U7-B4 "$(n "$V_LAP" "$A_REV")" "1" "…and in the REVERSE direction too (author -> viewer)"

# ============================================== C. THE BOUNDARY — the discriminators
#
# Without these two, B3 would be satisfied by simply ungating the RPC, which is
# the GLOBAL FIX THE REGISTER REJECTS. They are what make this bounded.
echo; echo "-- C  BOUND: and NOTHING beyond those relationships --"
is U7-C1 "$(n "$V_LAP" "$A_STR")" "0" "DISCRIMINATOR: a STRANGER still resolves to nothing — no general resolver (B-5)"
is U7-C2 "$(n "$V_LAP" "$A_REQ")" "0" "DISCRIMINATOR: a merely-REQUESTED relationship does NOT resolve"
is U7-C3 "$(as "$V_LAP" "select count(*) from public.search_account_directory('Followed');")" "0" "search is untouched — a lapsed member stays undiscoverable (D-7/B-15)"
is U7-C4 "$(as "$V_LAP" "select count(*) from public.search_account_directory('Stranger');")" "0" "…for strangers too"

# ============================================== D. THE RETENTION HALF IS UNTOUCHED
echo; echo "-- D  BOUND: G10's retention half is exactly as before --"
is U7-D1 "$(n "$V_ENT" "$A_LAP")" "1" "an ENTITLED viewer still resolves a LAPSED author (G10)"
is U7-D2 "$(n "$V_ENT" "$A_STR")" "1" "…and an entitled viewer is unrestricted, as before"
psq "update public.membership_control set enforcement_enabled=false where id;" >/dev/null
is U7-D3 "$(n "$V_LAP" "$A_STR")" "1" "the kill switch restores the pre-U7 world completely"

# ============================================== E. STRUCTURE
echo; echo "-- E  structure --"
SRC="select regexp_replace(prosrc,'--[^\n]*','','g') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_account_directory_by_user_ids'"
is U7-E1 "$(psq "select ($SRC) like '%connected_member%' or ($SRC) like '%entitled_until%';")" "f" \
  "G10: still NO subject-side predicate (this is U6b-J3)"
is U7-E2 "$(psq "select ($SRC) like '%enforcement_gate%';")" "t" "the viewer gate is still the first disjunct"
is U7-E3 "$(psq "select ($SRC) like '%public.follows%' and ($SRC) like '%approved%';")" "t" "the follow scope is present and keyed on approved"
is U7-E4 "$(psq "select ($SRC) like '%requested%';")" "f" "…and NOT on requested — the boundary is in the source, not only in the test"
is U7-E5 "$(psq "select string_agg(has_function_privilege(r.rolname,p.oid,'EXECUTE')::text,'/' order by r.rolname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r where n.nspname='public' and p.proname='get_account_directory_by_user_ids';")" "false/true/false" \
  "grants unmoved: authenticated only (B-5)"
is U7-E6 "$(psq "select p.prosecdef::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_account_directory_by_user_ids';")" "true" "still SECURITY DEFINER"
is U7-E7 "$(psq "select count(*) from pg_policy where polrelid='public.follows'::regclass;")" "4" "no follows policy was added or removed"
is U7-E8 "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='search_account_directory' and prosrc like '%public.follows%';")" "0" \
  "the follow scope did NOT leak into the discovery RPC"

# ============================================== F. LOCAL/PRODUCTION FIDELITY
#
# U7 found that U5's server half never reached supabase/migrations/, so a local
# reset rebuilt a stack whose RPCs returned SIX columns while production returns
# seven. A rehearsal against that stack is a rehearsal of the wrong object.
echo; echo "-- F  local reproduction fidelity (B-23) --"
is U7-F1 "$(psq "select (pg_get_function_result(p.oid) like '%avatar_version timestamp with time zone%')::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_account_directory_by_user_ids';")" "true" \
  "the local RPC carries avatar_version, as production does"
is U7-F2 "$(psq "select (pg_get_function_result(p.oid) like '%avatar_version timestamp with time zone%')::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='search_account_directory';")" "true" \
  "…and so does the discovery RPC"
is U7-F3 "$(psq "select count(*) from information_schema.columns where table_schema='public' and table_name='account_directory' and column_name='avatar_version';")" "1" \
  "…and the column exists locally"
is U7-F4 "$(psq "select count(*) from pg_trigger where tgname='tg_directory_avatar_version';")" "1" "…and U5's trigger is present locally"

echo; echo "  passed=$PASS failed=$FAIL"; echo
[ "$FAIL" -eq 0 ]
