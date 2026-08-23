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
is A1  "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name in ('membership','membership_binding','membership_notification','membership_cutover','membership_control');")" "5" "U3's five tables"
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
# AMENDED FOR U5b, 2026-08-23 -- see A4. connected_member() carries EXECUTE for
# nobody, still, and that half is unchanged: at U6 it is evaluated inside policy
# expressions rather than called, so it decides what clients may see while
# remaining unreachable BY them.
is A3h "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select rolname from pg_roles where rolname in ('anon','authenticated','service_role')) r where n.nspname='public' and p.proname='connected_member' and has_function_privilege(r.rolname,p.oid,'EXECUTE');")" "0" "EXECUTE on connected_member: nobody"

# ------------------------------------------------------------------ fixtures
A=$(mkuser u3a); B=$(mkuser u3b)
psqf <<SQL >/dev/null
insert into public.membership_cutover (user_id) values ('$A');
SQL

# ------------------------------------------------------- helper derivations
is A5  "$(psq "select public.connected_member('$B');")" "f" "unknown identity"
is A6  "$(psq "select public.connected_member('$A');")" "t" "grandfathered identity"
is A10 "$(psq "select public.connected_member(null);")" "f" "NULL input"
is A10b "$(psq "select public.connected_member('00000000-0000-0000-0000-000000000000');")" "f" "unknown uuid"
is A28 "$(psq "select public.membership_state('$A');")" "grandfathered" "state(grandfathered)"
is A28b "$(psq "select public.membership_state('$B');")" "unknown" "state(unknown)"

# A7 — real state overrides grandfathering (expired row on a snapshot identity)
psqf <<SQL >/dev/null
insert into public.membership (user_id, environment, original_transaction_id, product_id,
       renewal_date, renewal_info_signed_date, binding_method, bound_at)
values ('$A','Production','TXN-EXPIRED','com.sdsongs.etudes.connected.monthly',
        now() - interval '1 day', now(), 'legacy_claim', now());
SQL
is A7  "$(psq "select public.connected_member('$A');")" "f" "expired row beats grandfather"
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

# A11 — grandfather switch
psqf <<SQL >/dev/null
delete from public.membership where user_id='$A';
update public.membership_control set grandfather_enabled = false where id;
SQL
is A11 "$(psq "select public.connected_member('$A');")" "f" "grandfather disabled"
psqf <<SQL >/dev/null
update public.membership_control set grandfather_enabled = true where id;
SQL
is A11b "$(psq "select public.connected_member('$A');")" "t" "grandfather re-enabled"

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
is A26b "$(psq "select public.membership_state('$A');")" "grandfathered" "state with binding but no membership"

# A13 — cascade
psqf <<SQL >/dev/null
insert into public.membership (user_id,environment,original_transaction_id,product_id,renewal_info_signed_date,binding_method,bound_at)
values ('$A','Production','TXN-CASC','p',now(),'purchase',now());
delete from auth.users where id='$A';
SQL
is A13 "$(psq "select (select count(*) from public.membership where user_id='$A') + (select count(*) from public.membership_binding where user_id='$A') + (select count(*) from public.membership_cutover where user_id='$A');")" "0" "auth.users cascade removes all three"

# ---------------------------------------------------------------- inertness
is A15 "$(psq "select count(*) from pg_policies where qual ilike '%connected_member%' or with_check ilike '%connected_member%';")" "0" "policies calling connected_member"
is A15b "$(psq "select count(*) from pg_policies where schemaname in ('public','storage');")" "33" "existing policy count"
# WIDENED 2026-08-20, and the intent is unchanged. This asserts that no
# PRE-EXISTING product function was modified to consult membership -- the real
# hazard being something like search_account_directory quietly acquiring an
# entitlement check. It used to name U3's three helpers as the exemption, which
# made U4's own seven functions look like a violation of a U3 property. Excluding
# the whole Phase 3 namespace says what was meant and still catches the hazard.
is A15c "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ilike '%membership%' and p.proname not in ('connected_member','ensure_membership_binding') and p.proname not like 'membership%';")" "0" "pre-existing functions referencing membership"
is A16 "$(psq "select count(*) from public.membership where pending_cleanup_at is not null;")" "0" "cleanup scheduled"
is A16b "$(psq "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage') and not t.tgisinternal;")" "5" "trigger count unchanged"
is A14 "$(psq "select count(*) from public.membership_cutover;")" "0" "local cutover snapshot empty"
is A14b "$(psq "select coalesce((select cutover_at::text from public.membership_control),'null');")" "null" "cutover_at unset locally"

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
for TBL in membership membership_binding membership_notification membership_cutover membership_control; do
  for KEY in "$AK" "$AUTHJWT"; do probe GET "$API/rest/v1/$TBL?select=*" "$KEY" ""; done
done
for FN in connected_member membership_state; do
  for KEY in "$AK" "$AUTHJWT"; do probe POST "$API/rest/v1/rpc/$FN" "$KEY" "{\"target_user_id\":\"$E\"}"; done
done
is A22  "$SEEN"   "14" "runtime probes attempted (5 tables + 2 RPCs, x2 roles)"
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

# A27 -- a dormant snapshot identity acquires a binding lazily, and acquiring
# one must NOT fabricate membership. Both halves of the state rule are checked:
# grandfathered when the identity is in the snapshot, unknown when it is not.
S=$(mkuser u3s)
psqf <<SQL >/dev/null
insert into public.membership_cutover (user_id) values ('$S');
SQL
is A27  "$(psq "select count(*) from public.membership_binding where user_id='$S';")" "0" "snapshot identity starts unbound"
TS=$(as_identity "$S")
is A27b "$(psq "select count(*) from public.membership_binding where user_id='$S';")" "1" "binding created on demand"
is A27c "$(psq "select count(*) from public.membership where user_id='$S';")" "0" "no membership row fabricated"
is A27d "$(psq "select public.membership_state('$S');")" "grandfathered" "bound snapshot identity"
is A27e "$(psq "select public.membership_state('$E');")" "unknown" "bound NON-snapshot identity"

# Fixtures removed so the cutover section below starts from the same state it
# did before this block existed -- cascade takes the bindings and the snapshot
# row with them.
psqf <<SQL >/dev/null
delete from auth.users where id in ('$E','$F','$G','$S');
SQL
is A27f "$(psq "select count(*) from public.membership_binding;")" "0" "binding fixtures cleaned up"
is A27g "$(psq "select count(*) from public.membership_cutover;")" "0" "snapshot empty again before cutover section"

# ============================= cutover boundary =============================
# The corrected mechanism (supabase/sql/2026-08-16-u3-cutover-population.sql)
# exercised end to end against LOCAL identities. Production is not touched.

# A32 — cutover_verified_at exists, is nullable, and starts unset.
is A32 "$(psq "select count(*) from information_schema.columns where table_schema='public' and table_name='membership_control' and column_name='cutover_verified_at' and is_nullable='YES';")" "1" "cutover_verified_at nullable column"
is A32b "$(psq "select coalesce((select cutover_verified_at::text from public.membership_control),'null');")" "null" "verified_at unset before cutover"

# A33 — verification cannot precede the boundary it verifies.
is A33 "$(refuses "update public.membership_control set cutover_verified_at = now(), cutover_identity_count = 0 where id and cutover_at is null;")" "refused" "verified_at without cutover_at"
# The count is tied to VERIFICATION, not to the boundary -- setting one
# without the other is refused in both directions.
is A33b "$(refuses "update public.membership_control set cutover_identity_count = 0 where id;")" "refused" "count without verified_at"

# Local identities: C created BEFORE the boundary, D created AFTER it.
C=$(mkuser u3c)
psqf <<SQL >/dev/null
begin;
update public.membership_control set cutover_at = now(), updated_at = now() where id and cutover_at is null;
insert into public.membership_cutover (user_id)
select u.id from auth.users u
 where u.created_at < (select cutover_at from public.membership_control where id)
 on conflict (user_id) do nothing;
commit;
SQL
D=$(mkuser u3d)

# A34 — the predicate is total and disjoint: C in, D out.
is A34 "$(psq "select count(*) from public.membership_cutover where user_id='$C';")" "1" "pre-boundary identity captured"
is A34b "$(psq "select count(*) from public.membership_cutover where user_id='$D';")" "0" "POST-boundary identity excluded"
is A34c "$(psq "select public.connected_member('$D');")" "f" "post-cutover identity not entitled"

# A35 — re-running the population is idempotent and CANNOT admit D.
BEFORE=$(psq "select count(*) from public.membership_cutover;")
psqf <<SQL >/dev/null
insert into public.membership_cutover (user_id)
select u.id from auth.users u
 where u.created_at < (select cutover_at from public.membership_control where id)
 on conflict (user_id) do nothing;
SQL
is A35 "$(psq "select count(*) from public.membership_cutover;")" "$BEFORE" "re-run population changes nothing"
is A35b "$(psq "select count(*) from public.membership_cutover where user_id='$D';")" "0" "re-run still excludes post-cutover"

# A36 — convergence completeness check reports zero on a converged snapshot.
is A36 "$(psq "select count(*) from auth.users u where u.created_at < (select cutover_at from public.membership_control where id) and not exists (select 1 from public.membership_cutover c where c.user_id=u.id);")" "0" "missing qualifying identities"

# A37 — PERMANENT INVARIANT: no post-cutover or NULL-dated row in the snapshot.
is A37 "$(psq "select count(*) from public.membership_cutover c join auth.users u on u.id=c.user_id where u.created_at is null or u.created_at >= (select cutover_at from public.membership_control where id);")" "0" "post-cutover rows in snapshot"

# A38 — the NULL hazard is real and the guard detects it.
# auth.users.created_at is nullable with no default; a NULL satisfies NEITHER
# side of the boundary, so it must be caught BEFORE a boundary is declared.
psqf <<SQL >/dev/null
update auth.users set created_at = null where id='$D';
SQL
is A38 "$(psq "select count(*) from auth.users where created_at is null;")" "1" "NULL created_at guard detects it"
is A38b "$(psq "select count(*) from auth.users u where u.created_at < (select cutover_at from public.membership_control where id) and u.id='$D';")" "0" "NULL is excluded by '<'"
is A38c "$(psq "select count(*) from auth.users u where u.created_at >= (select cutover_at from public.membership_control where id) and u.id='$D';")" "0" "NULL is ALSO excluded by '>=' -- unclassifiable"
psqf <<SQL >/dev/null
update auth.users set created_at = now() where id='$D';
SQL

# A39 — finalisation sets verified_at and the counts agree.
psqf <<SQL >/dev/null
update public.membership_control
   set cutover_identity_count = (select count(*) from public.membership_cutover),
       cutover_verified_at = now(), updated_at = now()
 where id and cutover_at is not null and cutover_verified_at is null;
SQL
is A39 "$(psq "select (cutover_verified_at is not null)::text from public.membership_control where id;")" "true" "verified_at set after convergence"
is A39b "$(psq "select (cutover_identity_count = (select count(*) from public.membership_cutover))::text from public.membership_control where id;")" "true" "recorded count = materialised"
is A39c "$(psq "select (cutover_identity_count = (select count(*) from auth.users u where u.created_at < (select cutover_at from public.membership_control where id)))::text from public.membership_control where id;")" "true" "recorded count = by-predicate"

# A40 — finalisation is itself re-run protected.
V=$(psq "select cutover_verified_at from public.membership_control where id;")
psqf <<SQL >/dev/null
update public.membership_control set cutover_verified_at = now()
 where id and cutover_at is not null and cutover_verified_at is null;
SQL
is A40 "$(psq "select cutover_verified_at from public.membership_control where id;")" "$V" "finalisation guard prevents overwrite"

echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
