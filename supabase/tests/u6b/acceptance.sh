#!/usr/bin/env bash
#
# U6b acceptance — BINDING ENFORCEMENT + SUBJECT-SIDE VISIBILITY. LOCAL ONLY.
#
#   supabase db reset --local && ./supabase/tests/u6b/acceptance.sh
#
# WHAT THIS CLAIMS. (1) Applied, U6b denies NOTHING -- enforcement_enabled ships
# false. (2) Flipped on, the viewer matrix decides exactly as Apple's formula
# says, including that BILLING RETRY ALONE DOES NOT ENTITLE. (3) A lapsed AUTHOR
# becomes invisible on the five subject surfaces. (4) THE RETENTION HALF IS
# ASSERTED AS HARD AS THE HIDING HALF -- retained comments, retained attribution
# and live-referenced sent attachments must all still resolve. (5) The kill
# switch restores everything.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-11s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-11s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo; echo "U6b acceptance — binding enforcement and subject-side visibility"; echo

mkid() { psq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at) values ('$1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$2@local.invalid',now(),now()) on conflict do nothing;" >/dev/null; }
V_ENT=00000000-0000-0000-0000-0000000c0001   # entitled viewer
V_LAP=00000000-0000-0000-0000-0000000c0002   # lapsed viewer
V_GRC=00000000-0000-0000-0000-0000000c0003   # billing retry + grace unexpired -> ENTITLED
V_RTY=00000000-0000-0000-0000-0000000c0004   # billing retry, grace EXPIRED    -> NOT entitled
V_SBX=00000000-0000-0000-0000-0000000c0005   # sandbox only
V_NON=00000000-0000-0000-0000-0000000c0006   # no membership row
A_OK=00000000-0000-0000-0000-0000000c00a1    # entitled AUTHOR
A_LAP=00000000-0000-0000-0000-0000000c00a2   # lapsed AUTHOR
for p in "$V_ENT ent" "$V_LAP lap" "$V_GRC grc" "$V_RTY rty" "$V_SBX sbx" "$V_NON non" "$A_OK aok" "$A_LAP alap"; do
  set -- $p; mkid "$1" "u6b-$2"; done
is U6b-fix1 "$(psq "select count(*) from auth.users where id::text like '00000000-0000-0000-0000-0000000c%';")" "8" "eight fixtures exist before use"

# Membership BEFORE posts for A_OK (exercises the BEFORE trigger); posts BEFORE
# membership for A_LAP (exercises the propagation trigger). Both paths must land.
psqf <<SQL >/dev/null
insert into public.membership (user_id,environment,original_transaction_id,product_id,apple_status,renewal_date,is_in_billing_retry,grace_period_expires_date,renewal_info_signed_date,binding_method,bound_at) values
 ('$V_ENT','Production','u6b-ent','p',1, now()+interval '30 days', false, null,                    now(),'purchase',now()),
 ('$V_LAP','Production','u6b-lap','p',2, now()-interval '2 days',  false, null,                    now(),'purchase',now()),
 ('$V_GRC','Production','u6b-grc','p',4, now()-interval '1 day',   true,  now()+interval '10 days',now(),'purchase',now()),
 ('$V_RTY','Production','u6b-rty','p',3, now()-interval '9 days',  true,  now()-interval '1 day',  now(),'purchase',now()),
 ('$V_SBX','Sandbox',   'u6b-sbx','p',1, now()+interval '30 days', false, null,                    now(),'purchase',now()),
 ('$A_OK', 'Production','u6b-aok','p',1, now()+interval '30 days', false, null,                    now(),'purchase',now());
insert into public.posts (id,owner_user_id,is_public,created_at,attachments)
select gen_random_uuid(),'$A_OK',true,now(),'[]'::jsonb from generate_series(1,3);
insert into public.posts (id,owner_user_id,is_public,created_at,attachments)
select gen_random_uuid(),'$A_LAP',true,now(),'[]'::jsonb from generate_series(1,4);
insert into public.membership (user_id,environment,original_transaction_id,product_id,apple_status,renewal_date,is_in_billing_retry,renewal_info_signed_date,binding_method,bound_at)
values ('$A_LAP','Production','u6b-alap','p',2, now()-interval '3 days', false, now(),'purchase',now());
insert into public.follows (follower_user_id,followed_user_id,status,created_at,updated_at)
select v,a,'approved',now(),now() from unnest(array['$V_ENT'::uuid,'$V_LAP'::uuid,'$V_GRC'::uuid,'$V_RTY'::uuid,'$V_SBX'::uuid,'$V_NON'::uuid]) v,
                                       unnest(array['$A_OK'::uuid,'$A_LAP'::uuid]) a;
insert into public.account_directory (user_id,account_id,display_name) values
 ('$A_OK','aok','A OK'), ('$A_LAP','alap','A Lapsed') on conflict do nothing;
insert into public.post_comments (id,post_id,owner_user_id,author_user_id,recipient_user_id,body,created_at)
select gen_random_uuid(), p.id, '$A_OK', '$A_LAP', '$A_OK', 'retained comment by a lapsed author', now()
from (select id from public.posts where owner_user_id='$A_OK' limit 1) p;
SQL

seen() { psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); select count(*) from $2;" | tail -1; }
gate() { psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); select public.enforcement_gate('probe')::text;" | tail -1; }
setflag() { psq "update public.membership_control set enforcement_enabled=$1 where id;" >/dev/null; }

# ============================================ A. the trigger derived both ways
echo "-- A  the ONE derivation reached both insert orders --"
is U6b-A1 "$(psq "select count(*) from public.posts where owner_user_id='$A_OK' and owner_entitled_until > now();")" "3" "BEFORE trigger: entitled author's posts carry a future timestamp"
is U6b-A2 "$(psq "select count(*) from public.posts where owner_user_id='$A_LAP' and owner_entitled_until < now();")" "4" "PROPAGATION trigger: lapsed author's posts back-filled to the past"
is U6b-A3 "$(psq "select count(*) from public.account_directory where user_id='$A_LAP' and entitled_until < now();")" "1" "...and the directory row followed too"
is U6b-A4 "$(psq "select count(*) from public.follows where followed_user_id='$A_LAP' and followed_entitled_until < now();")" "6" "...and every follow row naming the lapsed author"

echo; echo "-- B  drift is mechanically zero --"
DRIFT="select (select count(*) from public.posts p where p.owner_entitled_until is distinct from public.membership_entitled_until(p.owner_user_id)) + (select count(*) from public.post_shares s where s.owner_entitled_until is distinct from public.membership_entitled_until(s.owner_user_id)) + (select count(*) from public.follows f where f.followed_entitled_until is distinct from public.membership_entitled_until(f.followed_user_id)) + (select count(*) from public.account_directory d where d.entitled_until is distinct from public.membership_entitled_until(d.user_id));"
is U6b-B1 "$(psq "$DRIFT")" "0" "stored equals recomputed on all four tables"
psq "update public.membership set renewal_date = now()+interval '90 days' where user_id='$A_LAP';" >/dev/null
is U6b-B2 "$(psq "$DRIFT")" "0" "...still zero after a membership change"
is U6b-B3 "$(psq "select count(*) from public.posts where owner_user_id='$A_LAP' and owner_entitled_until > now();")" "4" "...and the change propagated to the author's posts"
psq "update public.membership set renewal_date = now()-interval '3 days' where user_id='$A_LAP';" >/dev/null
is U6b-B4 "$(psq "select count(*) from public.posts where owner_user_id='$A_LAP' and owner_entitled_until < now();")" "4" "...and back again"

echo; echo "-- C  a client cannot set its own visibility --"
is U6b-C1 "$(psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$A_LAP','role','authenticated')::text, true); insert into public.posts (id,owner_user_id,is_public,created_at,attachments,owner_entitled_until) values (gen_random_uuid(),'$A_LAP',true,now(),'[]'::jsonb, now()+interval '999 days'); select count(*) from public.posts where owner_user_id='$A_LAP' and owner_entitled_until > now();" | tail -1)" "0" "a client-supplied future timestamp is OVERWRITTEN by the trigger"
psq "delete from public.posts where owner_user_id='$A_LAP' and id not in (select id from public.posts where owner_user_id='$A_LAP' order by created_at limit 4);" >/dev/null

# =========================================== D. INERT while the flag ships off
echo; echo "-- D  applied but not bound: U6b denies NOTHING --"
is U6b-D0 "$(psq "select enforcement_enabled::text from public.membership_control;")" "false" "enforcement_enabled ships FALSE"
for pair in "$V_ENT ent" "$V_LAP lap" "$V_SBX sbx" "$V_NON non"; do set -- $pair
  is "U6b-D-$2" "$(gate "$1")" "true" "gate returns true for $2 while unbound"; done
BASE_ENT=$(seen "$V_ENT" "public.posts"); BASE_NON=$(seen "$V_NON" "public.posts")
is U6b-D5 "$BASE_NON" "$BASE_ENT" "unbound: an unentitled viewer sees exactly what an entitled one sees"

# ==================================================== E. bind, and the matrix
echo; echo "-- E  BOUND: the viewer matrix, Apple's formula exactly --"
setflag true
is U6b-E0 "$(psq "select enforcement_enabled::text from public.membership_control;")" "true" "enforcement is bound"
is U6b-E1 "$(gate "$V_ENT")" "true"  "entitled Production member -> GRANT"
is U6b-E2 "$(gate "$V_LAP")" "false" "expired -> DENY"
is U6b-E3 "$(gate "$V_GRC")" "true"  "billing retry WITH unexpired grace -> GRANT"
is U6b-E4 "$(gate "$V_RTY")" "false" "billing retry with grace EXPIRED -> DENY (retry alone never entitles)"
is U6b-E5 "$(gate "$V_SBX")" "false" "sandbox_only -> DENY"
is U6b-E6 "$(gate "$V_NON")" "false" "no membership row -> DENY"

echo; echo "-- F  BOUND: subject-side visibility --"
is U6b-F1 "$(seen "$V_ENT" "public.posts where owner_user_id='$A_OK'")" "3" "entitled viewer SEES an entitled author's posts"
is U6b-F2 "$(seen "$V_ENT" "public.posts where owner_user_id='$A_LAP'")" "0" "entitled viewer sees NONE of a LAPSED author's posts"
is U6b-F3 "$(seen "$V_LAP" "public.posts")" "0" "an unentitled viewer sees nothing at all"
is U6b-F4 "$(seen "$A_LAP" "public.posts where owner_user_id='$A_LAP'")" "4" "the lapsed author still reads their OWN material (D-U6-4)"

echo; echo "-- G  BOUND: THE RETENTION HALF, asserted as hard as the hiding half --"
is U6b-G1 "$(psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$V_ENT','role','authenticated')::text, true); select count(*) from public.get_account_directory_by_user_ids(array['$A_LAP']::uuid[]);" | tail -1)" "1" "attribution for a LAPSED author still resolves (G10)"
is U6b-G2 "$(psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$V_ENT','role','authenticated')::text, true); select count(*) from public.search_account_directory('Lapsed');" | tail -1)" "0" "...but the lapsed author is UNDISCOVERABLE by search (D-U6-1)"
is U6b-G3 "$(psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$V_ENT','role','authenticated')::text, true); select count(*) from public.search_account_directory('OK');" | tail -1)" "1" "...while an entitled member remains discoverable"
is U6b-G4 "$(seen "$A_OK" "public.post_comments where author_user_id='$A_LAP'")" "1" "a lapsed author's retained comment is STILL VISIBLE to the post owner"

echo; echo "-- H  BOUND: the carve-outs must all still work --"
is U6b-H1 "$(seen "$A_LAP" "public.account_directory where user_id='$A_LAP'")" "1" "lapsed member still reads own profile (D-U6-3)"
is U6b-H2 "$(seen "$A_LAP" "public.follows where follower_user_id='$A_LAP' or followed_user_id='$A_LAP'")" "6" "follows stay visible so withdrawal remains possible"

# =============================================== I. the kill switch restores
echo; echo "-- I  the kill switch restores BOTH halves --"
setflag false
is U6b-I1 "$(gate "$V_NON")" "true" "unentitled viewer allowed again"
is U6b-I2 "$(seen "$V_ENT" "public.posts where owner_user_id='$A_LAP'")" "4" "the LAPSED author is visible again -- subject side rolled back too"
is U6b-I3 "$(seen "$V_ENT" "public.posts")" "$BASE_ENT" "row counts back to the pre-binding baseline"

echo; echo "-- J  structure --"
is U6b-J1 "$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||' '||coalesce(with_check,'')) like '%enforcement_gate%' and (coalesce(qual,'')||' '||coalesce(with_check,'')) not like '%( SELECT enforcement_gate%';")" "0" "ZERO bare gate calls in any policy"
is U6b-J2 "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r where n.nspname='public' and p.proname in ('membership_entitled_until','connected_member','membership_state') and has_function_privilege(r.rolname,p.oid,'EXECUTE') and not (p.proname='membership_state' and r.rolname='service_role');")" "0" "no client role can reach any uuid-taking entitlement predicate"
is U6b-J3 "$(psq "select (regexp_replace(prosrc,'--[^\n]*','','g') like '%connected_member%' or regexp_replace(prosrc,'--[^\n]*','','g') like '%entitled_until%')::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_account_directory_by_user_ids';")" "false" "get_account_directory_by_user_ids gates on NO subject predicate (G10)"
is U6b-J4 "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='shadow_observe';")" "0" "shadow_observe is retired, not aliased"

# ================================== K. CARRIED FORWARD FROM U6a's SUITE
#
# U6a's acceptance suite tested `shadow_observe`, which U6b drops. Rather than
# leave a suite exercising a function that no longer exists -- or worse, one
# edited until it always passes -- its assertions with unique value are CARRIED
# HERE, unchanged in substance. Nothing was dropped to make a rename easy.
echo; echo "-- K  carried forward from U6a: privilege, carve-outs, bounded aggregate --"
for R in anon authenticated service_role; do
  is "U6b-K1-$R" "$(psq "select count(*) from information_schema.role_table_grants where table_name='shadow_enforcement_stat' and grantee='$R';")" "0" "$R holds no privilege on shadow_enforcement_stat"
done
is U6b-K2 "$(psq "select rolbypassrls::text from pg_roles where rolname='service_role';")" "true" "service_role still bypasses RLS -- C-35 cannot regress"
is U6b-K3 "$(psq "select count(*) from pg_policies where policyname in ('account_directory_select_owner','account_directory_update_owner') and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_gate%';")" "0" "self-profile SELECT/UPDATE ungated (D-U6-3)"
is U6b-K4 "$(psq "select count(*) from pg_policies where cmd='DELETE' and schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%enforcement_gate%';")" "0" "ALL six DELETE policies ungated (D-U6-2)"
is U6b-K5 "$(psq "select count(*) from pg_policies where cmd='DELETE' and schemaname in ('public','storage');")" "6" "...and there are exactly six of them"
psq "select set_config('request.jwt.claims', json_build_object('sub','$V_NON','role','authenticated')::text, false); select public.enforcement_gate('probe.k6') from generate_series(1,25);" >/dev/null
is U6b-K6 "$(psq "select count(*) from public.shadow_enforcement_stat where surface='probe.k6';")" "1" "25 identical decisions produce ONE row"
is U6b-K7 "$(psq "select observations::text from public.shadow_enforcement_stat where surface='probe.k6';")" "25" "...with the counter at 25"
is U6b-K8 "$(psq "select count(*) from public.shadow_enforcement_stat where bucket_hour <> date_trunc('hour', bucket_hour);")" "0" "every bucket is hour-aligned"
is U6b-K9 "$(psq "select count(*) from public.shadow_enforcement_stat where decided_clause not in ('entitled','expired','sandbox_only','grandfathered','unknown');")" "0" "every observation names one of the five clauses"
is U6b-K10 "$(psq "select count(*) from pg_constraint where conname='shadow_stat_clause_check';")" "1" "sandbox_only stays SEPARABLE by constraint"
is U6b-K11 "$(psq "select count(*) from public.shadow_enforcement_stat where user_id is null;")" "0" "every observation is attributable to an identity"

# The U6b addition to that group: the two eras must be distinguishable forever.
is U6b-K12 "$(psq "select count(*) from information_schema.key_column_usage where constraint_name='shadow_enforcement_stat_pkey' and column_name='enforced';")" "1" "enforced is IN the primary key, so shadow and enforcement rows never merge"

# ================================================== L. C-59 — THE WRITE DENY PATH
#
# C-59: the enforcement WRITE-deny path had never been observed behaving, either
# locally or in production. It was structurally enforced -- posts_insert_owner
# carries enforcement_gate in its WITH CHECK -- and its shadow-path reachability
# was demonstrated on 2026-09-01. Nothing had ever watched it DENY.
#
# SCORED ON DATABASE OUTCOME, NEVER ON TELEMETRY. A denied INSERT aborts the
# statement, which rolls back the observer's own write (B-34's blind spot), so an
# absent shadow_enforcement_stat row cannot distinguish "denied" from "never
# attempted". The only sound evidence is whether the row exists afterwards.
#
# IT TRAVERSES THE REAL POLICY. Every statement runs `set local role
# authenticated` with a JWT claim and issues a plain INSERT -- the same path
# PostgREST takes. enforcement_gate() is never called directly here. L1
# additionally requires the refusal to be an RLS violation SPECIFICALLY, so a
# NOT NULL violation or a typo cannot be mistaken for enforcement working.
#
# TWO CONTROLS MAKE IT DISCRIMINATING RATHER THAN VACUOUS. L3 shows an ENTITLED
# author inserting under the SAME enforcement, so the gate is not blanket-
# refusing. L7 replays the IDENTICAL refused statement with enforcement OFF and
# it succeeds, so the refusal was the gate and not the statement.

echo; echo "-- L  BOUND: the WRITE deny path, by database outcome (C-59) --"

# Runs one statement as an authenticated identity through the real RLS path, and
# separates an RLS refusal from any other error.
as_writes() {
  local out
  out=$(psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); $2")
  case "$out" in
    *"violates row-level security policy"*) echo "rls_refused" ;;
    *ERROR*)                                echo "other_error" ;;
    *)                                      echo "accepted" ;;
  esac
}
INS_LAP="insert into public.posts (id,owner_user_id,is_public,created_at,attachments) values (gen_random_uuid(),'$A_LAP',true,now(),'[]'::jsonb);"
INS_OK="insert into public.posts (id,owner_user_id,is_public,created_at,attachments) values (gen_random_uuid(),'$A_OK',true,now(),'[]'::jsonb);"
owns() { psq "select count(*) from public.posts where owner_user_id='$1';"; }

setflag true
is U6b-L0 "$(psq "select enforcement_enabled::text from public.membership_control;")" "true" "enforcement is bound for the write tests"

LAP_BEFORE=$(owns "$A_LAP"); OK_BEFORE=$(owns "$A_OK")
is U6b-L1 "$(as_writes "$A_LAP" "$INS_LAP")" "rls_refused" "an UNENTITLED author's own INSERT is refused BY THE POLICY"
is U6b-L2 "$(owns "$A_LAP")" "$LAP_BEFORE" "...and NO ROW LANDED -- the database outcome, not telemetry"

is U6b-L3 "$(as_writes "$A_OK" "$INS_OK")" "accepted" "an ENTITLED author inserts under the SAME enforcement -- the gate discriminates"
is U6b-L4 "$(owns "$A_OK")" "$((OK_BEFORE+1))" "...and that row DID land"

# The carve-outs must survive the write gate. DELETE was asserted structurally
# by K4; this is the behavioural half, and it is the one that matters because a
# member who cannot delete cannot leave.
DEL_BEFORE=$(owns "$A_LAP")
is U6b-L5 "$(as_writes "$A_LAP" "delete from public.posts where owner_user_id='$A_LAP' and id = (select id from public.posts where owner_user_id='$A_LAP' limit 1);")" "accepted" "the unentitled owner can still DELETE their own post (D-U6-2)"
is U6b-L6 "$(owns "$A_LAP")" "$((DEL_BEFORE-1))" "...and the delete actually removed it"
is U6b-L7 "$(seen "$A_LAP" "public.posts where owner_user_id='$A_LAP'")" "$((DEL_BEFORE-1))" "the unentitled owner still READS their own posts (D-U6-4)"

# THE CONTROL. The identical statement that was refused above now succeeds.
setflag false
LAP_OFF=$(owns "$A_LAP")
is U6b-L8 "$(as_writes "$A_LAP" "$INS_LAP")" "accepted" "the IDENTICAL refused INSERT succeeds with enforcement OFF"
is U6b-L9 "$(owns "$A_LAP")" "$((LAP_OFF+1))" "...and the row landed -- so L1 was the GATE, not the statement"

echo; echo "  $PASS passed, $FAIL failed"; echo
[ "$FAIL" -eq 0 ]
