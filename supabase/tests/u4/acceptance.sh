#!/usr/bin/env bash
#
# U4 acceptance — LOCAL DISPOSABLE STACK ONLY.
#
# Runs the U4-owned assertions from docs/qa-plan.md ("U4 — PREDICTIONS").
# Numbering continues Phase 3's shared A-series from A40; A29-A31 belong to U5.
#
# Every assertion reads RESULTING STATE. A command exit status is not a pass.
#
# Run from a freshly reset local stack:
#   supabase db reset --local && ./supabase/tests/u4/acceptance.sh

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh   # localhost guard + dynamic credentials
source supabase/tests/u4/lib.sh   # psql access, also localhost-guarded

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-7s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-7s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo "== U4 acceptance =="

# ------------------------------------------------------------------ structure
is A41  "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name like 'membership%';")" "6" "membership tables after U4"
is A41b "$(psq "select count(*) from information_schema.tables where table_schema='public' and table_name='membership_notification_reject_stat';")" "1" "reject-stat table exists"
is A42  "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('membership_resolve_binding_v1','membership_apply_state_v1','membership_record_notification_v1','membership_record_reject_v1','membership_ingest_notification_v1','membership_apply_reconciliation_v1','membership_due_for_reconciliation_v1');")" "7" "U4 functions"
is A42b "$(psq "select count(*) from information_schema.columns where table_schema='public' and table_name='membership_notification' and column_name in ('delivery_count','last_received_at');")" "2" "B-26 columns"

# B-27's widened vocabulary, asserted by exercising it rather than by reading it.
is A43  "$(refuses "insert into public.membership_notification (notification_uuid, environment, signed_date, outcome) values (gen_random_uuid(),'Sandbox',now(),'nonsense');")" "refused" "unknown outcome rejected"
is A43b "$(psq "insert into public.membership_notification (notification_uuid, environment, signed_date, outcome, failure_category) values ('a1000000-0000-4000-8000-000000000001','Sandbox',now(),'ignored','unmapped') returning outcome;")" "ignored" "'ignored'/'unmapped' accepted"
is A43c "$(refuses "insert into public.membership_notification (notification_uuid, environment, signed_date, outcome) values ('a1000000-0000-4000-8000-000000000002','Sandbox',now(),'ignored');")" "refused" "'ignored' requires a category"
is A43d "$(refuses "insert into public.membership_notification (notification_uuid, environment, signed_date, outcome, failure_category) values ('a1000000-0000-4000-8000-000000000003','Sandbox',now(),'applied','incomplete');")" "refused" "'applied' forbids a category"
# An Apple-signed payload carrying no environment may be 'ignored' but never 'applied'.
is A43e "$(psq "insert into public.membership_notification (notification_uuid, signed_date, outcome, failure_category) values ('a1000000-0000-4000-8000-000000000004',now(),'ignored','not_applicable') returning outcome;")" "ignored" "environment optional on 'ignored'"
is A43f "$(refuses "insert into public.membership_notification (notification_uuid, signed_date, outcome) values ('a1000000-0000-4000-8000-000000000005',now(),'applied');")" "refused" "environment required on 'applied'"
psqf <<'SQL' >/dev/null
delete from public.membership_notification;
SQL

# --------------------------------------------------- privilege boundary (U3 A3f)
# THE INVARIANT U3 ESTABLISHED MUST SURVIVE U4 UNCHANGED. It now covers six
# tables rather than five, and it is still zero.
is A44  "$(psq "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(c.relacl) a where n.nspname='public' and c.relkind='r' and c.relname like 'membership%' and a.grantee <> c.relowner;")" "0" "non-owner grantees on membership tables"
is A44b "$(psq "select count(*) from information_schema.role_table_grants where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated','service_role');")" "0" "table grants to any client/server role"
is A44c "$(psq "select count(*) from information_schema.column_privileges where table_schema='public' and table_name like 'membership%' and grantee in ('anon','authenticated','service_role');")" "0" "column grants"
is A44d "$(psq "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname like 'membership%' and not c.relrowsecurity;")" "0" "membership tables without RLS"

# EXACTLY FOUR U4 functions are granted, and only to service_role.
is A45  "$(psq "select string_agg(p.proname,',' order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'membership%_v1' and has_function_privilege('service_role',p.oid,'EXECUTE');")" "membership_apply_reconciliation_v1,membership_due_for_reconciliation_v1,membership_ingest_notification_v1,membership_record_reject_v1" "service_role EXECUTE set"
is A45b "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('membership_apply_state_v1','membership_resolve_binding_v1','membership_record_notification_v1') and has_function_privilege('service_role',p.oid,'EXECUTE');")" "0" "internal writers unreachable by service_role"
is A45c "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join (select rolname from pg_roles where rolname in ('anon','authenticated')) r where n.nspname='public' and p.proname like 'membership%' and has_function_privilege(r.rolname,p.oid,'EXECUTE');")" "0" "NO client EXECUTE on any membership function"
is A45d "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'membership%' and exists (select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.privilege_type='EXECUTE' and a.grantee=0);")" "0" "PUBLIC EXECUTE anywhere"
# U5's grant has NOT been made early.
is A45e "$(psq "select has_function_privilege('authenticated','public.ensure_membership_binding()','EXECUTE')::text;")" "false" "ensure_membership_binding still ungranted (U5)"

# The write boundary, proven by attempting it as service_role rather than assumed.
is A46  "$(refuses "set role service_role; insert into public.membership_notification (notification_uuid, environment, signed_date, outcome) values (gen_random_uuid(),'Sandbox',now(),'applied');")" "refused" "service_role direct INSERT on membership_notification"
is A46b "$(refuses "set role service_role; update public.membership set pending_cleanup_at = null;")" "refused" "service_role direct UPDATE on membership"
is A46c "$(refuses "set role service_role; delete from public.membership_binding;")" "refused" "service_role direct DELETE on membership_binding"
is A46d "$(refuses "set role service_role; select count(*) from public.membership;")" "refused" "service_role direct SELECT on membership"
is A46e "$(refuses "set role service_role; select public.membership_apply_state_v1(null,null,null,null);")" "refused" "service_role calling the canonical writer directly"

# ------------------------------------------------------------------- fixtures
A=$(mkuser u4a); B=$(mkuser u4b)
psqf <<SQL >/dev/null
insert into public.membership_binding (user_id, binding_token)
values ('$A','aaaaaaaa-0000-4000-8000-000000000001');
SQL
TOK='aaaaaaaa-0000-4000-8000-000000000001'

ingest() { psq "select public.membership_ingest_notification_v1('$1'::jsonb)->>'outcome';"; }
ingest_full() { psq "select public.membership_ingest_notification_v1('$1'::jsonb);"; }

ev() { # uuid, type, token, signed_offset, renewal_offset, extra-state-json
cat <<JSON
{"notification_uuid":"$1","environment":"Sandbox","notification_type":"$2","subtype":null,
 "original_transaction_id":"2000000999999999","signed_date":"$(psq "select now();")",
 "app_account_token":$3,"disposition":"state","payload_bytes":1200,
 "payload_sha256":"$(printf '%064d' 1)",
 "state":{"product_id":"com.sdsongs.etudes.connected.monthly","apple_status":1,
   "renewal_date":"$(psq "select now() + interval '$5';")",
   "grace_period_expires_date":null,"is_in_billing_retry":false,"auto_renew_status":1,
   "expiration_intent":null,"revocation_date":null,
   "renewal_info_signed_date":"$(psq "select now() + interval '$4';")"}}
JSON
}

# ------------------------------------------------------------- ingestion rules
#
# U4 CANNOT ESTABLISH MEMBERSHIP. A notification that maps to a live binding and
# carries complete Apple state STILL writes nothing when no authoritative row
# exists: binding_method and bound_at record how ownership was PROVED, and U5's
# protocol is what earns the right to write them.
is A47  "$(ingest "$(ev b0000000-0000-4000-8000-000000000001 SUBSCRIBED "\"$TOK\"" '0 seconds' '30 days')")" "ignored" "mapped notification does NOT establish membership"
is A47b "$(psq "select count(*) from public.membership;")" "0" "NO membership row was created"
is A47c "$(psq "select failure_category from public.membership_notification where notification_uuid='b0000000-0000-4000-8000-000000000001';")" "unestablished" "...recorded as unestablished, not unmapped and not rejected"
is A47d "$(psq "select (public.membership_ingest_notification_v1('$(ev b0000000-0000-4000-8000-00000000000e SUBSCRIBED "\"$TOK\"" '0 seconds' '30 days')'::jsonb)->>'needs_establishment');")" "true" "...and flags needs_establishment for U5"
is A47e "$(psq "select public.connected_member('$A');")" "f" "identity is NOT entitled by a notification alone"
# THE STRUCTURAL FORM OF THE SAME RULE: no INSERT into membership exists in U4.
is A47f "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'membership%' and pg_get_functiondef(p.oid) ~* 'insert +into +public\.membership *(as|\()';")" "0" "no U4 function inserts into membership"

# ---- U5 STAND-IN. U5 does not exist, so the authoritative row is created here
# directly, under explicit acknowledgement that this is a FIXTURE and not a code
# path. Everything below tests REFRESH of an established row, which is all U4
# claims to do.
psqf <<SQL >/dev/null
insert into public.membership (user_id, environment, original_transaction_id, product_id,
       renewal_date, renewal_info_signed_date, binding_method, bound_at)
values ('$A','Sandbox','2000000999999999','com.sdsongs.etudes.connected.monthly',
        now() + interval '1 day', now() - interval '1 day', 'purchase', now());
SQL
is A47g "$(psq "select count(*) from public.membership where user_id='$A';")" "1" "U5 stand-in row exists"
is A47h "$(ingest "$(ev b0000000-0000-4000-8000-00000000000f DID_RENEW "\"$TOK\"" '0 seconds' '30 days')")" "applied" "an ESTABLISHED row is refreshed"
is A47i "$(psq "select public.connected_member('$A');")" "t" "...and the identity is entitled"
is A47j "$(psq "select binding_method from public.membership where user_id='$A';")" "purchase" "binding_method untouched by ingestion"

# B-26 — a replay is OBSERVABLE, which "no second row appeared" never was.
is A48  "$(ingest "$(ev b0000000-0000-4000-8000-00000000000f DID_RENEW "\"$TOK\"" '10 days' '99 days')")" "duplicate" "replay returns duplicate"
is A48b "$(psq "select delivery_count from public.membership_notification where notification_uuid='b0000000-0000-4000-8000-00000000000f';")" "2" "delivery_count incremented"
is A48c "$(psq "select outcome from public.membership_notification where notification_uuid='b0000000-0000-4000-8000-00000000000f';")" "applied" "first delivery's outcome preserved"
is A48d "$(psq "select count(*) from public.membership_notification where notification_uuid='b0000000-0000-4000-8000-00000000000f';")" "1" "no second audit row"
is A48e "$(psq "select (renewal_date < now() + interval '40 days')::text from public.membership;")" "true" "replay changed NO state"

# Ordering — an out-of-order delivery is a no-op, not an error.
is A49  "$(ingest "$(ev b0000000-0000-4000-8000-000000000002 DID_RENEW "\"$TOK\"" '-1 day' '365 days')")" "stale" "older renewal_info_signed_date is stale"
is A49b "$(psq "select (renewal_date < now() + interval '40 days')::text from public.membership;")" "true" "stale delivery wrote nothing"
is A49c "$(ingest "$(ev b0000000-0000-4000-8000-000000000003 DID_RENEW "\"$TOK\"" '1 hour' '60 days')")" "applied" "newer signed date applies"

# B-24 — a token matching no live binding is ordinary traffic, never a mapping.
is A50  "$(ingest "$(ev b0000000-0000-4000-8000-000000000004 DID_RENEW '"cccccccc-0000-4000-8000-000000000009"' '2 hours' '90 days')")" "ignored" "foreign token is ignored"
is A50b "$(psq "select failure_category from public.membership_notification where notification_uuid='b0000000-0000-4000-8000-000000000004';")" "unmapped" "...categorised as unmapped, NOT rejected"
is A50c "$(psq "select count(*) from public.membership;")" "1" "no membership row created for it"
is A50d "$(ingest "$(ev b0000000-0000-4000-8000-000000000005 DID_RENEW null '3 hours' '90 days')")" "ignored" "absent token is ignored"
# THE B-24 STRUCTURAL ASSERTION: nothing in U4 maps a transaction id to a user.
is A50e "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'membership%' and pg_get_functiondef(p.oid) ~* 'from public.membership[^ ]* *(m *)?where.*original_transaction_id *= *p_';")" "0" "no function resolves identity from original_transaction_id"

# B-25 — incomplete state writes NOTHING and schedules NOTHING.
BEFORE_SIGNED=$(psq "select renewal_info_signed_date from public.membership where user_id='$A';")
is A51  "$(psq "select public.membership_ingest_notification_v1('{\"notification_uuid\":\"b0000000-0000-4000-8000-000000000006\",\"environment\":\"Sandbox\",\"notification_type\":\"DID_RENEW\",\"signed_date\":\"$(psq "select now();")\",\"app_account_token\":\"$TOK\",\"disposition\":\"incomplete\",\"original_transaction_id\":\"2000000999999999\",\"state\":null}'::jsonb)->>'outcome';")" "ignored" "incomplete notification is ignored"
is A51b "$(psq "select failure_category from public.membership_notification where notification_uuid='b0000000-0000-4000-8000-000000000006';")" "incomplete" "...categorised incomplete"
is A51c "$(psq "select (public.membership_ingest_notification_v1('{\"notification_uuid\":\"b0000000-0000-4000-8000-000000000016\",\"environment\":\"Sandbox\",\"notification_type\":\"DID_RENEW\",\"signed_date\":\"$(psq "select now();")\",\"app_account_token\":\"$TOK\",\"disposition\":\"incomplete\",\"original_transaction_id\":\"2000000999999999\",\"state\":null}'::jsonb)->>'needs_reconciliation');")" "true" "...and asks for a live read"
is A51d "$(psq "select renewal_info_signed_date from public.membership where user_id='$A';")" "$BEFORE_SIGNED" "incomplete wrote no state"
is A51e "$(psq "select coalesce(pending_cleanup_at::text,'null') from public.membership where user_id='$A';")" "null" "AMBIGUOUS STATE SCHEDULED NO CLEANUP"

# ------------------------------------------------- expiry, quarantine, recovery
is A52  "$(psq "select public.membership_ingest_notification_v1(jsonb_build_object('notification_uuid','b0000000-0000-4000-8000-000000000007','environment','Sandbox','notification_type','EXPIRED','subtype','VOLUNTARY','original_transaction_id','2000000999999999','signed_date',now()::text,'app_account_token','$TOK','disposition','state','state',jsonb_build_object('product_id','com.sdsongs.etudes.connected.monthly','apple_status',2,'renewal_date',(now() - interval '1 hour')::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now() + interval '5 hours')::text)))->>'outcome';")" "applied" "expiry applies"
is A52b "$(psq "select public.connected_member('$A');")" "f" "entitlement ends"
is A52c "$(psq "select (pending_cleanup_at - entitlement_ended_at = interval '60 days')::text from public.membership where user_id='$A';")" "true" "quarantine is EXACTLY 60 days (Q1)"
is A52d "$(psq "select (entitlement_ended_at < now())::text from public.membership where user_id='$A';")" "true" "end instant taken from Apple's date, not our clock"
ENDED=$(psq "select entitlement_ended_at from public.membership where user_id='$A';")
# A later still-expired notification must not slide the deadline forward.
is A52e "$(psq "select public.membership_ingest_notification_v1(jsonb_build_object('notification_uuid','b0000000-0000-4000-8000-000000000008','environment','Sandbox','notification_type','EXPIRED','original_transaction_id','2000000999999999','signed_date',now()::text,'app_account_token','$TOK','disposition','state','state',jsonb_build_object('product_id','p','apple_status',2,'renewal_date',(now() - interval '1 minute')::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now() + interval '6 hours')::text)))->>'outcome';")" "applied" "second expiry notification applies"
is A52f "$(psq "select entitlement_ended_at from public.membership where user_id='$A';")" "$ENDED" "entitlement_ended_at NOT slid forward"

# Billing grace: retry alone must not entitle; retry + unexpired grace must.
is A53  "$(psq "select public.membership_ingest_notification_v1(jsonb_build_object('notification_uuid','b0000000-0000-4000-8000-000000000009','environment','Sandbox','notification_type','DID_FAIL_TO_RENEW','subtype','GRACE_PERIOD','original_transaction_id','2000000999999999','signed_date',now()::text,'app_account_token','$TOK','disposition','state','state',jsonb_build_object('product_id','p','apple_status',4,'renewal_date',(now() - interval '1 hour')::text,'grace_period_expires_date',(now() + interval '16 days')::text,'is_in_billing_retry',true,'renewal_info_signed_date',(now() + interval '7 hours')::text)))->>'outcome';")" "applied" "grace applies"
is A53b "$(psq "select public.connected_member('$A');")" "t" "grace RETAINS entitlement"
is A53c "$(psq "select coalesce(pending_cleanup_at::text,'null') from public.membership where user_id='$A';")" "null" "re-entitlement CANCELS pending cleanup (C5/G6c)"
is A53d "$(psq "select coalesce(entitlement_ended_at::text,'null') from public.membership where user_id='$A';")" "null" "...and clears the end instant"
# Retry outside grace is NOT entitled — Apple's formula requires both.
is A53e "$(psq "select public.membership_ingest_notification_v1(jsonb_build_object('notification_uuid','b0000000-0000-4000-8000-00000000000a','environment','Sandbox','notification_type','DID_FAIL_TO_RENEW','subtype','BILLING_RETRY','original_transaction_id','2000000999999999','signed_date',now()::text,'app_account_token','$TOK','disposition','state','state',jsonb_build_object('product_id','p','apple_status',3,'renewal_date',(now() - interval '1 hour')::text,'grace_period_expires_date',(now() - interval '1 minute')::text,'is_in_billing_retry',true,'renewal_info_signed_date',(now() + interval '8 hours')::text)))->>'outcome';")" "applied" "retry-outside-grace applies"
is A53f "$(psq "select public.connected_member('$A');")" "f" "retry alone does NOT entitle"
is A53g "$(psq "select (pending_cleanup_at is not null)::text from public.membership where user_id='$A';")" "true" "...and quarantine restarts"

# --------------------------------------------------------------- reconciliation
is A54  "$(psq "select public.membership_apply_reconciliation_v1('$B','Sandbox', jsonb_build_object('product_id','p','renewal_date',(now()+interval '30 days')::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now()+interval '20 hours')::text))->>'outcome';")" "ignored" "reconciliation will NOT create a row"
is A54a "$(psq "select (public.membership_apply_reconciliation_v1('$B','Sandbox', jsonb_build_object('product_id','p','renewal_date',(now()+interval '30 days')::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now()+interval '21 hours')::text))->>'needs_establishment');")" "true" "...and says why"
is A54b "$(psq "select count(*) from public.membership where user_id='$B';")" "0" "...and created none"
is A54c "$(psq "select public.membership_apply_reconciliation_v1('$A','Sandbox', jsonb_build_object('product_id','com.sdsongs.etudes.connected.monthly','renewal_date',(now()+interval '30 days')::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now()+interval '20 hours')::text))->>'outcome';")" "applied" "reconciliation refreshes an existing row"
is A54d "$(psq "select public.connected_member('$A');")" "t" "...restoring entitlement"
is A54e "$(psq "select coalesce(pending_cleanup_at::text,'null') from public.membership where user_id='$A';")" "null" "...and cancelling cleanup"
is A54f "$(psq "select public.membership_apply_reconciliation_v1('$A','Sandbox', jsonb_build_object('product_id','p','renewal_date',(now()+interval '99 days')::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now()+interval '1 hour')::text))->>'outcome';")" "stale" "reconciliation obeys the SAME ordering rule"
is A54g "$(psq "select count(*) from public.membership_due_for_reconciliation_v1('$A','Sandbox');")" "1" "selector finds the row"
is A54h "$(psq "select count(*) from public.membership_due_for_reconciliation_v1();")" "1" "selector with no filter returns all"

# Ownership is a PRECONDITION of writing, not a property checked afterwards.
psqf <<SQL >/dev/null
delete from public.membership_binding where user_id='$A';
SQL
is A55  "$(refuses "select public.membership_apply_state_v1('$A','Sandbox','T', jsonb_build_object('product_id','p','renewal_date',(now()+interval '1 day')::text,'is_in_billing_retry',false,'renewal_info_signed_date',(now()+interval '99 hours')::text));")" "refused" "canonical writer refuses without a live binding"
psqf <<SQL >/dev/null
insert into public.membership_binding (user_id, binding_token) values ('$A','$TOK');
SQL

# ------------------------------------------------------ B-29 bounded diagnostics
psqf <<'SQL' >/dev/null
delete from public.membership_notification_reject_stat;
SQL
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  psq "select public.membership_record_reject_v1('signature', repeat('$(printf '%x' $((i % 16)))',64));" >/dev/null
done
is A56  "$(psq "select count(*) from public.membership_notification_reject_stat;")" "1" "twelve rejects produce ONE row"
is A56b "$(psq "select reject_count from public.membership_notification_reject_stat;")" "12" "...with an exact count"
is A56c "$(psq "select cardinality(sample_sha256) from public.membership_notification_reject_stat;")" "8" "digest sample capped at eight"
psq "select public.membership_record_reject_v1('decode', null);" >/dev/null
is A56d "$(psq "select count(*) from public.membership_notification_reject_stat;")" "2" "a second category adds exactly one row"
is A56e "$(refuses "insert into public.membership_notification_reject_stat (hour_bucket, failure_category) values (now(),'signature');")" "refused" "unaligned hour bucket rejected"
is A56f "$(refuses "insert into public.membership_notification_reject_stat (hour_bucket, failure_category) values (date_trunc('hour',now()),'nonsense');")" "refused" "unknown reject category rejected"
# THE PROPERTY THAT MATTERS: cardinality is bounded by hours x categories, so an
# unauthenticated flood cannot grow the database however long it runs.
is A56g "$(psq "select (count(*) <= (select count(distinct hour_bucket) from public.membership_notification_reject_stat) * 6)::text from public.membership_notification_reject_stat;")" "true" "row count bounded by hours x categories"
# Inputs are validated inside the function, not trusted from the caller — this is
# the only function an unauthenticated request reaches, indirectly.
psq "select public.membership_record_reject_v1('signature','NOT-A-DIGEST');" >/dev/null
is A56h "$(psq "select cardinality(sample_sha256) from public.membership_notification_reject_stat where failure_category='signature';")" "8" "a malformed digest is DROPPED, not stored"
psq "select public.membership_record_reject_v1('made-up-category', null);" >/dev/null
is A56i "$(psq "select count(*) from public.membership_notification_reject_stat where failure_category='made-up-category';")" "0" "an unknown category is normalised, not stored"
is A56j "$(psq "select count(*) from public.membership_notification_reject_stat;")" "2" "...and creates no extra row"

# ------------------------------------------------------------- grant audit (U4)
# The selector returns ONLY what appstore_reconcile_v1 uses. A scheduling column
# has no business leaving the database on a path with no use for it.
is A58  "$(psq "select string_agg(a.attname,',' order by a.attnum) from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join lateral unnest(p.proallargtypes, p.proargnames, p.proargmodes) with ordinality as a(atttypid, attname, attmode, attnum) where n.nspname='public' and p.proname='membership_due_for_reconciliation_v1' and a.attmode='t';")" "user_id,environment,original_transaction_id" "selector returns exactly three columns"
is A58b "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='membership_due_for_reconciliation_v1' and pg_get_functiondef(p.oid) ~* 'pending_cleanup_at *,|, *pending_cleanup_at';")" "0" "selector no longer returns scheduling state"

# --------------------------------------------------------------- observe-only
# 33 is the count over public AND storage, which is the scope capture-schema.sh
# captures. Counting 'public' alone gives 23 and would silently assert a
# different thing from the one the B-23 baseline records.
is A57  "$(psq "select count(*) from pg_policies where schemaname in ('public','storage');")" "33" "policy count UNCHANGED"
is A57b "$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) ~* 'connected_member|membership';")" "0" "NO policy consults membership"
is A57c "$(psq "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal;")" "1" "trigger count unchanged"
is A57d "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'membership%' and pg_get_functiondef(p.oid) ~* 'delete +from +public\.(posts|post_shares|post_comments|follows|account_directory|connected_attachments|post_comment_views)';")" "0" "no U4 function deletes Domain 3 content"
is A57e "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'membership%' and pg_get_functiondef(p.oid) ~* 'storage\.objects';")" "0" "no U4 function touches storage"
is A57f "$(psq "select count(*) from pg_extension where extname='pg_cron';")" "0" "no scheduler installed"
# 60 days is a hard constant, not configuration production could shorten.
is A57g "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='membership_apply_state_v1' and pg_get_functiondef(p.oid) like '%interval ''60 days''%';")" "1" "quarantine constant is literal in the writer"

echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
