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
DB=supabase_db_rlwtqxumfobakvdueugm
psq()  { docker exec -i "$DB" psql -U postgres -d postgres -At -q -c "$1" 2>&1; }
psqf() { docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 2>&1; }
# does a statement fail? prints "ok" if it errored (i.e. constraint held)
refuses() { local out; out=$(psq "$1"); case "$out" in *ERROR*) echo "refused";; *) echo "ACCEPTED";; esac; }

echo "== U3 acceptance =="

# ---------------------------------------------------------------- structure
is A1  "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name like 'membership%';")" "5" "new tables"
is A1b "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('connected_member','membership_state','ensure_membership_binding');")" "3" "new helpers"

# ------------------------------------------------------- client reachability
is A3  "$(psq "select count(*) from information_schema.role_table_grants where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated');")" "0" "table grants to clients"
is A3b "$(psq "select count(*) from information_schema.column_privileges where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated');")" "0" "column grants to clients"
is A4  "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select oid,rolname from pg_roles where rolname in ('anon','authenticated')) r where n.nspname='public' and p.proname in ('connected_member','membership_state','ensure_membership_binding') and has_function_privilege(r.rolname,p.oid,'EXECUTE');")" "0" "client EXECUTE (effective)"
is A4b "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('connected_member','membership_state','ensure_membership_binding') and exists (select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.privilege_type='EXECUTE' and a.grantee=0);")" "0" "PUBLIC EXECUTE"
# relkind='r' matters: pg_class also holds the 10 indexes on these tables, and
# an index has relrowsecurity=false by nature. Without it this counted indexes.
is A4c "$(psq "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname like 'membership%' and not c.relrowsecurity;")" "0" "tables without RLS"

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
is A15c "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ilike '%membership%' and p.proname not in ('connected_member','membership_state','ensure_membership_binding');")" "0" "pre-existing functions referencing membership"
is A16 "$(psq "select count(*) from public.membership where pending_cleanup_at is not null;")" "0" "cleanup scheduled"
is A16b "$(psq "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','storage') and not t.tgisinternal;")" "5" "trigger count unchanged"
is A14 "$(psq "select count(*) from public.membership_cutover;")" "0" "local cutover snapshot empty"
is A14b "$(psq "select coalesce((select cutover_at::text from public.membership_control),'null');")" "null" "cutover_at unset locally"

echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
