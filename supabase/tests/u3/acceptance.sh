#!/usr/bin/env bash
#
# U3 acceptance — LOCAL DISPOSABLE STACK ONLY.
#
# Runs the U3-owned assertions from docs/qa-plan.md ("U3 — PREDICTIONS").
# A24 is the STRUCTURAL half only; A29-A31 belong to U5 and are not run here.
#
# Every assertion reads resulting state. A command exit status is not a pass.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh          # localhost guard + dynamic credentials

PASS=0; FAIL=0
ok()   { printf "  \033[32mPASS\033[0m  %-6s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31mFAIL\033[0m  %-6s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()   { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

# raw psql for statements supabase db query cannot take (multi-statement, DO blocks)
#
# THE TARGET IS RESOLVED FROM THE RUNNING LOCAL STACK, NEVER HARD-CODED. It used
# to name one project's container literally, which tied the suite to a single
# machine's project ref and, worse, would have kept pointing at a stale
# container if the ref ever changed. The resolution below derives the container
# from `supabase status`'s own DB_URL, so the suite talks to whatever local
# stack is actually running -- or refuses to run at all.
#
# THE LOCALHOST BOUNDARY IS PRESERVED AND WIDENED. lib.sh already refuses a
# non-localhost API_URL; this adds the same guard on DB_URL, and then requires
# the resolved container to be a supabase_db_* one publishing that exact port.
# Every route into the database is therefore localhost-checked, which matters
# because everything below is destructive by design.
_u3_die() { echo "u3: $*" >&2; exit 1; }

DB_URL=$(supabase status -o json 2>/dev/null | jq -r '.DB_URL // empty')
[ -n "$DB_URL" ] || _u3_die "could not read DB_URL from 'supabase status -o json'"

DB_HOST=$(printf '%s' "$DB_URL" | sed -E 's#^.*@([^:/]+):([0-9]+)/.*$#\1#')
DB_PORT=$(printf '%s' "$DB_URL" | sed -E 's#^.*@([^:/]+):([0-9]+)/.*$#\2#')
case "$DB_HOST" in
  127.0.0.1|localhost|::1) ;;
  *) _u3_die "refusing to run: DB_URL host '$DB_HOST' is not localhost" ;;
esac
[ -n "$DB_PORT" ] || _u3_die "could not parse a port from DB_URL"

DB=$(docker ps --filter "publish=$DB_PORT" --format '{{.Names}}' | grep '^supabase_db_' || true)
[ -n "$DB" ] || _u3_die "no supabase_db_* container publishes port $DB_PORT"
[ "$(printf '%s\n' "$DB" | wc -l | tr -d ' ')" = "1" ] || _u3_die \
  "ambiguous: more than one supabase_db_* container publishes port $DB_PORT:
$DB"

psq()  { docker exec -i "$DB" psql -U postgres -d postgres -At -q -c "$1" 2>&1; }
psqf() { docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 2>&1; }
# does a statement fail? prints "ok" if it errored (i.e. constraint held)
refuses() { local out; out=$(psq "$1"); case "$out" in *ERROR*) echo "refused";; *) echo "ACCEPTED";; esac; }

echo "== U3 acceptance =="

# ---------------------------------------------------------------- structure
# TIGHTENED 2026-08-20, and it is strictly stronger rather than relaxed. This
# used to count tables matching 'membership%' and expect 5, which made a correct
# U4 -- adding membership_notification_reject_stat -- fail a U3 assertion about
# U3's own objects. Naming the five says what was always meant, and would still
# catch one of them going missing.
# RE-POINTED BY U6b-4: membership_cutover is DROPPED (B-36). Four tables, and
# the fifth is asserted ABSENT below rather than quietly dropped from the list.
is A1  "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name in ('membership','membership_binding','membership_notification','membership_control');")" "4" "U3's four surviving tables"
is A1c "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name='membership_cutover';")" "0" "membership_cutover is GONE (U6b-4)"
is A1b "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('connected_member','membership_state','ensure_membership_binding');")" "3" "new helpers"

# ------------------------------------------------------- client reachability
is A3  "$(psq "select count(*) from information_schema.role_table_grants where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated');")" "0" "table grants to clients"
is A3b "$(psq "select count(*) from information_schema.column_privileges where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated');")" "0" "column grants to clients"
# AMENDED FOR U5b, 2026-08-23. U3 asserted ZERO client-reachable membership
# objects and that was true AT U3 -- its own cell said "including
# ensure_membership_binding(), which U5 grants, not U3". U5b makes that grant, so
# the assertion is re-pointed rather than deleted, and it is now STRICTER than
# the original: not "zero", but "exactly one, and precisely which one".
is A4  "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select oid,rolname from pg_roles where rolname in ('anon','authenticated')) r where n.nspname='public' and p.proname in ('connected_member','membership_state') and has_function_privilege(r.rolname,p.oid,'EXECUTE');")" "0" "client EXECUTE on the two authority helpers"
is A4u5 "$(psq "select string_agg(r.rolname,',' order by r.rolname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r where n.nspname='public' and p.proname='ensure_membership_binding' and has_function_privilege(r.rolname,p.oid,'EXECUTE');")" "authenticated" "ensure_membership_binding reachable by authenticated ALONE (U5b)"
is A4b "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('connected_member','membership_state','ensure_membership_binding') and exists (select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.privilege_type='EXECUTE' and a.grantee=0);")" "0" "PUBLIC EXECUTE"
# relkind='r' matters: pg_class also holds the 10 indexes on these tables, and
# an index has relrowsecurity=false by nature. Without it this counted indexes.
is A4c "$(psq "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname like 'membership%' and not c.relrowsecurity;")" "0" "tables without RLS"

# ------------------------------------------------------ privilege determinism
# U3's final privilege state must be a property of the migration, not of
# whichever pg_default_acl entry applies to the creating role. A3c/A3d assert
# the service_role half that ambient defaults would otherwise supply; A3e closes
# the PUBLIC blind spot the structural capture cannot see (it filters grantee to
# three named roles); A3f is the whole model in one query -- no grantee other
# than the owner appears in relacl for any of the five tables, under any default.
is A3c "$(psq "select count(*) from information_schema.role_table_grants where table_schema='public' and table_name like 'membership%' and grantee='service_role';")" "0" "table grants to service_role"
is A3d "$(psq "select count(*) from information_schema.column_privileges where table_schema='public' and table_name like 'membership%' and grantee='service_role';")" "0" "column grants to service_role"
is A3e "$(psq "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(c.relacl) a where n.nspname='public' and c.relkind='r' and c.relname like 'membership%' and a.grantee=0;")" "0" "PUBLIC table privileges"
is A3f "$(psq "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(c.relacl) a where n.nspname='public' and c.relkind='r' and c.relname like 'membership%' and a.grantee <> c.relowner;")" "0" "non-owner grantees on membership tables"
# The one deliberate exception to "no non-owner privileges anywhere", stated as
# an assertion so the model is positively confirmed and not merely negatively.
is A3g "$(psq "select has_function_privilege('service_role','public.membership_state(uuid)','EXECUTE')::text;")" "true" "service_role EXECUTE on membership_state"
# AMENDED FOR U5b, 2026-08-23 -- see A4. AND THE REASON RE-STATED 2026-09-01 BY
# B-33, because the one written here was false: a function referenced from a
# policy qual DOES have EXECUTE checked against the invoking role, so "evaluated
# rather than called" never made it reachable-by-policy-yet-unreachable-by-role.
# The ASSERTION is unchanged and still right -- connected_member(uuid) carries
# EXECUTE for nobody -- and U6a is what makes that survivable: policies consult
# the zero-argument connected_member_self() wrapper, which is granted to
# `authenticated` and reaches this form internally. Keeping this form ungranted
# is what stops it becoming a membership oracle over every user.
is A3h "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r where n.nspname='public' and p.proname='connected_member' and has_function_privilege(r.rolname,p.oid,'EXECUTE');")" "0" "EXECUTE on connected_member: nobody"

# ------------------------------------------------------------------ fixtures
A=$(mkuser u3a); B=$(mkuser u3b)
# U6b-4: there is no snapshot to insert into. $A is simply a pre-cutover-aged
# identity with no membership row, which is now the ONLY thing that shape means.

# ------------------------------------------------------- helper derivations
is A5  "$(psq "select public.connected_member('$B');")" "f" "unknown identity"
is A6  "$(psq "select public.connected_member('$A');")" "f" "an identity with no membership row is NOT entitled -- grandfathering RETIRED (B-36/U6b-4)"
is A10 "$(psq "select public.connected_member(null);")" "f" "NULL input"
is A10b "$(psq "select public.connected_member('00000000-0000-0000-0000-000000000000');")" "f" "unknown uuid"
is A28 "$(psq "select public.membership_state('$A');")" "unknown" "state(unknown) -- 'grandfathered' is no longer producible"
is A28b "$(psq "select public.membership_state('$B');")" "unknown" "state(unknown)"

# A7 — an expired Production row derives NOT ENTITLED. Before U6b-4 this also
# proved real state OVERRIDES grandfathering; there is no longer a second clause
# for it to override, so the assertion survives with a narrower meaning.
psqf <<SQL >/dev/null
insert into public.membership (user_id, environment, original_transaction_id, product_id,
       renewal_date, renewal_info_signed_date, binding_method, bound_at)
values ('$A','Production','TXN-EXPIRED','com.sdsongs.etudes.connected.monthly',
        now() - interval '1 day', now(), 'legacy_claim', now());
SQL
is A7  "$(psq "select public.connected_member('$A');")" "f" "expired Production row -> not entitled"
is A28c "$(psq "select public.membership_state('$A');")" "expired" "state(expired)"

# A8 — entitled
psqf <<SQL >/dev/null
update public.membership set renewal_date = now() + interval '30 days' where user_id='$A';
SQL
is A8  "$(psq "select public.connected_member('$A');")" "t" "entitled row"
is A28d "$(psq "select public.membership_state('$A');")" "entitled" "state(entitled)"

# A9 — Billing Grace: retry alone must NOT entitle
psqf <<SQL >/dev/null
update public.membership set renewal_date = now() - interval '1 day',
       is_in_billing_retry = true, grace_period_expires_date = null where user_id='$A';
SQL
is A9a "$(psq "select public.connected_member('$A');")" "f" "retry, grace NULL"
psqf <<SQL >/dev/null
update public.membership set grace_period_expires_date = now() - interval '1 hour' where user_id='$A';
SQL
is A9b "$(psq "select public.connected_member('$A');")" "f" "retry, grace past"
# Added after A9a failed: the NULL-propagation shape in its purest form -- every
# derivation input NULL on a row that EXISTS. Must be false, never grandfathered.
psqf <<SQL >/dev/null
update public.membership set renewal_date = null, grace_period_expires_date = null,
       is_in_billing_retry = true where user_id='$A';
SQL
is A9d "$(psq "select public.connected_member('$A');")" "f" "all derivation inputs NULL"
is A9e "$(psq "select public.membership_state('$A');")" "expired" "state with NULL inputs"
psqf <<SQL >/dev/null
update public.membership set grace_period_expires_date = now() + interval '10 days' where user_id='$A';
SQL
is A9c "$(psq "select public.connected_member('$A');")" "t" "retry + future grace"

# A11 — RETIRED BY U6b-4 AND REPLACED IN PLACE, not deleted. It tested that the
# grandfather switch could turn the compatibility clause off and back on. Both
# the switch and the clause are gone, so the assertion now pins their ABSENCE --
# which is the property that must never silently regress.
psqf <<SQL >/dev/null
delete from public.membership where user_id='$A';
SQL
is A11 "$(psq "select count(*) from information_schema.columns where table_schema='public' and table_name='membership_control' and column_name in ('grandfather_enabled','grandfather_expires_at');")" "0" "the grandfather switch is GONE -- restoring it is a migration, never a flag"
is A11b "$(psq "select (pg_get_functiondef(p.oid) like '%cutover%' or pg_get_functiondef(p.oid) like '%grandfather%')::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='connected_member';")" "false" "connected_member references NO retired object"

# ---------------------------------------------------------------- constraints
is A12 "$(refuses "insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,binding_method,bound_at) values ('$A','Production','DUP','p',now(),'purchase',now()), ('$B','Production','DUP','p',now(),'purchase',now());")" "refused" "duplicate (env,txn)"
is A25 "$(refuses "insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,bound_at) values ('$B','Production','NOBIND','p',now(),now());")" "refused" "membership without binding_method"
is A25b "$(refuses "insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,binding_method) values ('$B','Production','NOBIND2','p',now(),'purchase');")" "refused" "membership without bound_at"
is A25c "$(refuses "insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,binding_method,bound_at) values ('$B','Production','BADM','p',now(),'guessed',now());")" "refused" "invalid binding_method"
is Axc "$(refuses "insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,binding_method,bound_at) values ('$B','Xcode','XC','p',now(),'purchase',now());")" "refused" "environment 'Xcode'"
is A23 "$(refuses "insert into public.membership_binding (user_id,binding_token) values ('$A','11111111-1111-1111-1111-111111111111'),('$B','11111111-1111-1111-1111-111111111111');")" "refused" "duplicate binding_token"

# notification table
is An1 "$(psq "insert into public.membership_notification (outcome,failure_category,payload_bytes,payload_sha256,request_id) values ('rejected','decode',412,repeat('a',64),'req-1') returning 'ok';")" "ok" "rejected row with NO uuid"
is An2 "$(refuses "insert into public.membership_notification (outcome) values ('applied');")" "refused" "accepted row missing uuid/env/date"
U=$(psq "select gen_random_uuid();")
is An3 "$(refuses "insert into public.membership_notification (notification_uuid,environment,signed_date,outcome) values ('$U','Sandbox',now(),'applied'),('$U','Sandbox',now(),'applied');")" "refused" "duplicate notification_uuid"

# --------------------------------------------------- binding lifecycle (A24)
psqf <<SQL >/dev/null
delete from public.membership_binding;
insert into public.membership_binding (user_id) values ('$A');
insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,binding_method,bound_at)
values ('$A','Production','TXN-LIFE','p',now(),'legacy_claim',now());
delete from public.membership where user_id='$A';
SQL
is A24 "$(psq "select count(*) from public.membership_binding where user_id='$A';")" "1" "binding survives membership delete"
is A24b "$(psq "select count(*) from pg_constraint where conrelid='public.membership_binding'::regclass and confrelid='public.membership'::regclass;")" "0" "no FK membership->binding"

# A26 — legacy path needs no fake membership row
is A26 "$(psq "select count(*) from public.membership where user_id='$A';")" "0" "binding exists with zero membership rows"
is A26b "$(psq "select public.membership_state('$A');")" "unknown" "state with binding but no membership"

# A13 — cascade
psqf <<SQL >/dev/null
insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,binding_method,bound_at)
values ('$A','Production','TXN-CASC','p',now(),'purchase',now());
delete from auth.users where id='$A';
SQL
is A13 "$(psq "select (select count(*) from public.membership where user_id='$A') + (select count(*) from public.membership_binding where user_id='$A');")" "0" "auth.users cascade removes both surviving tables"

# ---------------------------------------------------------------- inertness
is A15 "$(psq "select count(*) from pg_policies where qual ilike '%connected_member%' or with_check ilike '%connected_member%';")" "0" "policies calling connected_member"
is A15b "$(psq "select count(*) from pg_policies where schemaname in ('public','storage');")" "33" "existing policy count"
# WIDENED 2026-08-20, and the intent is unchanged. This asserts that no
# PRE-EXISTING product function was modified to consult membership -- the real
# hazard being something like search_account_directory quietly acquiring an
# entitlement check. It used to name U3's three helpers as the exemption, which
# made U4's own seven functions look like a violation of a U3 property. Excluding
# the whole Phase 3 namespace says what was meant and still catches the hazard.
#
# RE-POINTED AGAIN AT U6b, 2026-09-01. U6b RENAMES the observer to
# enforcement_gate -- a function that DENIES must not be called shadow_observe
# (C-25/F6) -- and adds three more dependents outside the namespace:
# enforcement_active, tg_set_entitled_until and tg_membership_propagate_entitled_until.
# ALL SIX ARE NAMED BY HAND. No namespace, no pattern: any other function
# acquiring a membership dependency still fails this.
#
# RE-POINTED AT U6a, 2026-08-30, AND IT CAUGHT WHAT A57b WAS SUPPOSED TO CATCH.
# U6a's shadow_observe() called membership_state(), so it acquired exactly the
# dependency this assertion exists to detect -- and it FAILED here, unpredicted,
# while A57b and A67c stayed green. That function was named as a SINGLE EXPLICIT
# EXCEPTION, never a namespace or pattern: any OTHER function acquiring a
# membership dependency still fails this, which is the whole point of the row.
is A15c "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ilike '%membership%' and p.proname not in ('connected_member','ensure_membership_binding','enforcement_gate','enforcement_active','tg_set_entitled_until','tg_membership_propagate_entitled_until') and p.proname not like 'membership%';")" "0" "no function outside the membership namespace depends on membership, except six named by hand"
is A16 "$(psq "select count(*) from public.membership where pending_cleanup_at is not null;")" "0" "cleanup scheduled"
# RE-POINTED FOR U6b, 2026-09-01: 5 -> 10. U6b adds five triggers -- four
# BEFORE INSERT OR UPDATE row triggers maintaining the denormalised visibility
# timestamp, and one AFTER trigger on `membership` propagating it. The assertion
# is not weakened: it still pins an exact count, so a sixth would fail it.
is A16b "$(psq "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage') and not t.tgisinternal;")" "10" "trigger count: U3's 5 plus U6b's 5"
# A14 — RETIRED BY U6b-4: there is no snapshot table to be empty. A14b survives
# unchanged: cutover_at is RETAINED as the historical record of a declared
# boundary, and is still unset on a fresh local instance.
is A14 "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name='membership_cutover';")" "0" "no snapshot table exists to hold a snapshot"
is A14b "$(psq "select coalesce((select cutover_at::text from public.membership_control),'null');")" "null" "cutover_at RETAINED as a column and unset locally"

# ================= binding runtime + runtime client denial ==================
#
# A19-A22 and A27 were predicted as U3-owned and had NO assertion in the first
# 63. They were neither run nor declared deferred, which is the ownerless shape
# this project holds itself to -- so they are executed here rather than quietly
# reassigned to U5.
#
# THEY ARE RUNNABLE AT U3, and the reason is worth stating because it was the
# original excuse for skipping them. ensure_membership_binding() is ungranted
# until U5, but that grant governs who may CALL it through PostgREST; the
# function's own identity handling is exercised by setting the same JWT claim
# PostgREST itself would set. A22 then tests the ungranted state from the
# outside, over real HTTP, which is the half a catalog query cannot prove.

# Calls the function as a given identity, exactly as PostgREST would present it.
# Each psq is a FRESH session, so a claim set here cannot leak into any other
# assertion -- which is why the claim and the call must share one statement.
as_identity() { psq "select set_config('request.jwt.claims','{\"sub\":\"$1\"}',false); select public.ensure_membership_binding();" | tail -1; }

E=$(mkuser u3e); F=$(mkuser u3f)

# A19 -- repeated calls by one identity are idempotent.
T1=$(as_identity "$E"); T2=$(as_identity "$E")
is A19  "$T2" "$T1" "repeated call returns the same token"
is A19b "$(psq "select count(*) from public.membership_binding where user_id='$E';")" "1" "exactly one binding row"

# A20 -- GENUINE CONCURRENCY, not a sequential proxy. Eight sessions are armed
# and then released together by pg_sleep_until on a shared instant, so they
# contend inside the upsert rather than politely queueing. This is the assertion
# the `on conflict do update` form exists for: `do nothing` would let a loser
# skip without taking a lock and then read no row at all.
G=$(mkuser u3g)
T0=$(psq "select (now() + interval '4 seconds')::text;")
CDIR=$(mktemp -d)
for i in 1 2 3 4 5 6 7 8; do
  ( psq "select set_config('request.jwt.claims','{\"sub\":\"$G\"}',false); select pg_sleep_until('$T0'::timestamptz); select public.ensure_membership_binding();" | tail -1 > "$CDIR/$i" ) &
done
wait || true
is A20  "$(cat "$CDIR"/* | wc -l | tr -d ' ')" "8" "all 8 concurrent sessions returned"
is A20b "$(cat "$CDIR"/* | sort -u | wc -l | tr -d ' ')" "1" "one distinct token across the burst"
is A20c "$(psq "select count(*) from public.membership_binding where user_id='$G';")" "1" "one binding row after the burst"
is A20d "$(cat "$CDIR"/* | sort -u)" "$(psq "select binding_token from public.membership_binding where user_id='$G';")" "returned token = stored token"
rm -rf "$CDIR"

# A21 -- one identity cannot obtain another's token.
TE=$(psq "select binding_token from public.membership_binding where user_id='$E';")
TF=$(as_identity "$F")
is A21  "$(psq "select pronargs from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='ensure_membership_binding';")" "0" "function takes no argument"
is A21b "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='ensure_membership_binding';")" "1" "no overload accepting a user_id"
is A21c "$(if [ "$TF" != "$TE" ]; then echo differs; else echo SAME; fi)" "differs" "second identity gets its own token"
is A21d "$(psq "select (binding_token='$TF')::text from public.membership_binding where user_id='$F';")" "true" "returned token belongs to the caller"
is A21e "$(psq "select count(*) from public.membership_binding where user_id='$F' and binding_token='$TE';")" "0" "caller never receives another's token"
is A21f "$(psq "select public.ensure_membership_binding();" | grep -c 'authentication required')" "1" "unauthenticated call refused (28000)"

# A22 -- RUNTIME denial over HTTP, for both client roles.
#
# CATALOG GRANTS ARE NOT THE RUNTIME TEST. A3/A3b prove the privilege is absent;
# this proves the request actually fails at the edge PostgREST serves. The two
# CONTROLS below are what stop it passing vacuously: a denial proves nothing if
# the credential was simply invalid, so each credential is first shown to work
# against a surface it is entitled to reach.
AUTHJWT=$(tokenfor u3e)
is A22ctl1 "$(curl -s -o /dev/null -w '%{http_code}' "$API/rest/v1/" -H "apikey: $AK")" "200" "CONTROL: anon key reaches PostgREST"
is A22ctl2 "$(curl -s -o /dev/null -w '%{http_code}' "$API/rest/v1/posts?select=id&limit=1" -H "apikey: $AK" -H "Authorization: Bearer $AUTHJWT")" "200" "CONTROL: authenticated JWT reads an entitled table"

TWOXX=0; ARRAYS=0; SEEN=0
probe() { # $1 method, $2 url, $3 bearer, $4 body
  local body code
  if [ "$1" = "GET" ]; then
    body=$(curl -s -w '\n%{http_code}' "$2" -H "apikey: $AK" -H "Authorization: Bearer $3")
  else
    body=$(curl -s -w '\n%{http_code}' -X POST "$2" -H "apikey: $AK" -H "Authorization: Bearer $3" \
           -H 'Content-Type: application/json' -d "$4")
  fi
  code=$(printf '%s' "$body" | tail -1)
  SEEN=$((SEEN+1))
  case "$code" in 2??) TWOXX=$((TWOXX+1));; esac
  case "$(printf '%s' "$body" | head -1)" in '['*) ARRAYS=$((ARRAYS+1));; esac
}
for TBL in membership membership_binding membership_notification membership_control; do
  for KEY in "$AK" "$AUTHJWT"; do probe GET "$API/rest/v1/$TBL?select=*" "$KEY" ""; done
done
for FN in connected_member membership_state; do
  for KEY in "$AK" "$AUTHJWT"; do probe POST "$API/rest/v1/rpc/$FN" "$KEY" "{\"target_user_id\":\"$E\"}"; done
done
is A22  "$SEEN"   "12" "runtime probes attempted (4 tables + 2 RPCs, x2 roles)"
is A22b "$TWOXX"  "0"  "successful (2xx) client responses"
is A22c "$ARRAYS" "0"  "responses returning a JSON row array"

# ensure_membership_binding IS SCORED SEPARATELY FROM U5b ONWARDS, and it must
# be: folding it into the aggregate above would let "one 2xx somewhere" pass for
# either role. Anon must still be refused; authenticated must now SUCCEED, which
# is the half no catalog query can prove -- the grant working through PostgREST
# over real HTTP.
ANON_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/rest/v1/rpc/ensure_membership_binding" -H "apikey: $AK" -H "Authorization: Bearer $AK" -H 'Content-Type: application/json' -d '{}')
AUTH_BODY=$(curl -s -X POST "$API/rest/v1/rpc/ensure_membership_binding" -H "apikey: $AK" -H "Authorization: Bearer $AUTHJWT" -H 'Content-Type: application/json' -d '{}')
# Computed BEFORE the assertion, not inside $( ): a `case` pattern's own closing
# paren terminates a command substitution, which silently turned this assertion
# into a literal string on its first run.
ANON_VERDICT=refused
case "$ANON_CODE" in 2??) ANON_VERDICT=2xx;; esac
is A22d "$ANON_VERDICT" "refused" "anon STILL refused over HTTP (U5b)"
is A22e "$(printf '%s' "$AUTH_BODY" | tr -d '\"' | grep -cE '^[0-9a-f]{8}-')" "1" "authenticated receives a uuid token over HTTP (U5b)"
is A22f "$(psq "select (binding_token::text = '$(printf '%s' "$AUTH_BODY" | tr -d '\"')')::text from public.membership_binding where user_id='$E';")" "true" "...and it is the CALLER'S OWN stored token"

# A27 -- a dormant identity acquires a binding lazily, and acquiring one must
# NOT fabricate membership. RE-POINTED BY U6b-4: there is no snapshot, so both
# halves of the old state rule now collapse to 'unknown'. The load-bearing half
# -- that a binding never fabricates membership -- is UNCHANGED and is the
# reason this block survives at all.
S=$(mkuser u3s)
is A27  "$(psq "select count(*) from public.membership_binding where user_id='$S';")" "0" "dormant identity starts unbound"
TS=$(as_identity "$S")
is A27b "$(psq "select count(*) from public.membership_binding where user_id='$S';")" "1" "binding created on demand"
is A27c "$(psq "select count(*) from public.membership where user_id='$S';")" "0" "no membership row fabricated"
is A27d "$(psq "select public.membership_state('$S');")" "unknown" "a binding alone NEVER produces entitlement"
is A27e "$(psq "select public.membership_state('$E');")" "unknown" "...and neither does one on any other identity"

# Fixtures removed -- cascade takes the bindings with them.
psqf <<SQL >/dev/null
delete from auth.users where id in ('$E','$F','$G','$S');
SQL
is A27f "$(psq "select count(*) from public.membership_binding;")" "0" "binding fixtures cleaned up"
is A27g "$(psq "select count(*) from public.membership;")" "0" "no membership row was ever fabricated by any of it"

# ================= cutover boundary — RETIRED BY U6b-4 =====================
#
# A32 to A40 tested the U3 cutover population mechanism: the boundary column
# guards, the population statement, its re-run idempotence, the convergence
# check and the finalisation guard. **THE MECHANISM THEY TESTED NO LONGER
# EXISTS.** `membership_cutover` is dropped and `grandfather_enabled` /
# `grandfather_expires_at` are dropped (B-36, U6b-4).
#
# THEY ARE RETIRED IN PLACE RATHER THAN DELETED, and the group that replaces
# them asserts the RETIREMENT rather than nothing -- the U6a-to-U6b group K
# precedent: never leave a suite exercising an object that no longer exists, and
# never edit one until it always passes. A deleted section proves nothing; this
# one fails loudly if any part of the retired mechanism comes back.
#
# WHAT WAS LOST AND IS NOT RECOVERABLE HERE, stated rather than glossed: the
# population statement's correctness -- that '<' captures pre-boundary and
# excludes NULL-dated identities -- was verified in production at U3's P6/P8 and
# is recorded in CLAUDE.md. It is history now, not a live property, because
# nothing populates a snapshot any more.
#
# cutover_at, cutover_identity_count and cutover_verified_at are RETAINED as the
# historical record of a boundary that was declared and verified. No function
# reads them; A41 pins that.

is A32 "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name='membership_cutover';")" "0" "the snapshot table is gone"
is A33 "$(psq "select count(*) from information_schema.columns where table_schema='public' and table_name='membership_control' and column_name in ('grandfather_enabled','grandfather_expires_at');")" "0" "both grandfather controls are gone"
is A34 "$(psq "select count(*) from information_schema.columns where table_schema='public' and table_name='membership_control' and column_name in ('cutover_at','cutover_identity_count','cutover_verified_at');")" "3" "the cutover RECORD is retained -- history is not erased"
is A35 "$(psq "select (u6b_bound_at is not null)::text from public.membership_control;")" "false" "u6b_bound_at is retained as a column and unset locally"
is A36 "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and (pg_get_functiondef(p.oid) like '%membership_cutover%' or pg_get_functiondef(p.oid) like '%grandfather%');")" "0" "NO function references any retired object"
is A37 "$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%cutover%';")" "0" "no policy references the snapshot"
is A38 "$(psq "select public.membership_state('$(mkuser u3ret)');")" "unknown" "a brand-new identity is 'unknown', never 'grandfathered'"

# A39 — THE CONSTRAINT THAT MUST NOT BE NARROWED. Historical telemetry rows
# carry decided_clause = 'grandfathered' and stay valid forever. Removing the
# live branch must never remove the historical vocabulary: the aggregate is
# keyed on decided_clause, so the before and after of the retirement sit in the
# same table as evidence, and narrowing this check would break existing rows.
is A39 "$(psq "select (pg_get_constraintdef(oid) like '%grandfathered%')::text from pg_constraint where conname='shadow_stat_clause_check';")" "true" "historical 'grandfathered' telemetry REMAINS VALID"
is A39b "$(psq "insert into public.shadow_enforcement_stat (user_id,surface,decided_clause,would_deny,enforced,bucket_hour,observations,last_seen) values ('$(mkuser u3hist)','probe.retired','grandfathered',false,false,date_trunc('hour',now()),1,now()) returning 'ok';")" "ok" "...and such a row can still be WRITTEN, not merely tolerated"

# A40 — the entitlement predicate is now two-armed and reaches no retired object.
is A40 "$(psq "select (pg_get_functiondef(p.oid) like '%coalesce%')::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='connected_member';")" "true" "connected_member still coalesces -- the Sandbox-only NULL case is unchanged"
is A41 "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and pg_get_functiondef(p.oid) like '%cutover_at%';")" "0" "no function reads the retained cutover record"

echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
