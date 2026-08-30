#!/usr/bin/env bash
#
# U6a acceptance — SHADOW ENFORCEMENT. LOCAL DISPOSABLE STACK ONLY.
#
#   supabase db reset --local && ./supabase/tests/u6a/acceptance.sh
#
# G4's acceptance criteria, as executable assertions. Every one reads resulting
# state; a command exit status is never a pass.
#
# WHAT THIS SUITE CLAIMS, PRECISELY. U6a attaches an observer to 23 policies and
# 9 SECURITY DEFINER RPCs and CHANGES NO REQUEST'S OUTCOME. The load-bearing
# assertion is G4-S2: the same query returns the SAME ROWS with the observer
# attached and with the pre-U6a policy restored, for four identity classes. Every
# other structural assertion here is a guard around that one.
#
# WHAT IT DOES NOT CLAIM. Nothing about identities that generate no traffic --
# that is G11, unrun, and U6b's entry condition. Nothing about production.
# G4-B2 (zero grandfather-only decisions) is U6b's gate, NOT a pass condition
# here: a window that observes grandfather-only decisions is a SUCCESSFUL G4 and
# a BLOCKED U6b.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh          # localhost guard + dynamic credentials
source supabase/tests/u4/lib.sh          # psq/psqf + container resolution

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

echo
echo "U6a acceptance — shadow enforcement: attached, bounded, and INERT"
echo

# ============================================================ G4-S1  inertness
echo "-- G4-S1  the observer is inert on every path --"
is G4-S1a "$(psq "select public.shadow_observe('probe.s1')::text;")" "true" "returns true for an unauthenticated caller"
psq "select set_config('request.jwt.claims','{\"sub\":\"00000000-0000-0000-0000-0000000000ff\"}',false);" >/dev/null
is G4-S1b "$(psq "select set_config('request.jwt.claims','{\"sub\":\"00000000-0000-0000-0000-0000000000ff\"}',true); select public.shadow_observe('probe.s1b')::text;" | tail -1)" "true" "returns true for an identity with no membership row"
# The structural half: EVERY return in the body returns true.
#
# The first revision asserted "exactly ONE return statement" against raw prosrc.
# It failed at 3 -- two real returns plus the phrase "the ONLY return value this
# can have" INSIDE A COMMENT. Two defects in one line: it counted comment text,
# and "one return" was never the requirement. U5c-34 and three U5d assertions had
# the identical shape, and the U5d record states the rule this broke: a
# source-text assertion must target CODE, and a well-commented file is exactly
# the one most likely to defeat it. Comments are stripped, and the property
# asserted is the real one -- no return can yield anything but true.
is G4-S1c "$(psq "select (select count(*) from regexp_matches(regexp_replace((select prosrc from pg_proc where proname='shadow_observe'), '--[^\n]*', '', 'g'), 'return[[:space:]]+true', 'gi'))::text = (select count(*) from regexp_matches(regexp_replace((select prosrc from pg_proc where proname='shadow_observe'), '--[^\n]*', '', 'g'), 'return', 'gi'))::text;")" "t" "EVERY return in the observer returns true"
is G4-S1d "$(psq "select count(*) from regexp_matches(regexp_replace((select prosrc from pg_proc where proname='shadow_observe'), '--[^\n]*', '', 'g'), 'return[[:space:]]+true', 'gi');")" "2" "...and there are two such returns (null-uid early exit, and the tail)"

# ==================================================== G4-S5  privilege posture
echo
echo "-- G4-S5  no client role can reach the shadow aggregate --"
for R in anon authenticated service_role; do
  is "G4-S5-$R" "$(psq "select count(*) from information_schema.role_table_grants where table_name='shadow_enforcement_stat' and grantee='$R';")" "0" "$R holds no privilege on shadow_enforcement_stat"
done

# ================================================== G4-S4  the oracle is closed
echo
echo "-- G4-S4  no uuid-addressable membership oracle exists --"
is G4-S4a "$(psq "select has_function_privilege('authenticated','public.connected_member(uuid)','EXECUTE')::text;")" "false" "connected_member(uuid) NOT executable by authenticated"
is G4-S4b "$(psq "select has_function_privilege('anon','public.connected_member(uuid)','EXECUTE')::text;")" "false" "...nor by anon"
is G4-S4c "$(psq "select has_function_privilege('service_role','public.connected_member(uuid)','EXECUTE')::text;")" "false" "...nor by service_role"
is G4-S4d "$(psq "select has_function_privilege('authenticated','public.membership_state(uuid)','EXECUTE')::text;")" "false" "membership_state(uuid) NOT executable by authenticated"
is G4-S4e "$(psq "select pronargs from pg_proc where proname='connected_member_self';")" "0" "the granted predicate takes NO argument -- nothing to aim"
is G4-S4f "$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) ~* 'connected_member\(|membership_state\(|connected_member_self\(';")" "0" "no policy calls an entitlement predicate DIRECTLY"

# =============================================== G4-S3  never a bare call
echo
echo "-- G4-S3  every policy reference is the InitPlan form, one per policy --"
ATT=$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%';")
is G4-S3-count "$ATT" "23" "policies with the observer attached"
# Postgres renders the scalar subquery as `( SELECT public.shadow_observe(...`.
# A BARE call renders without that prefix, which is a 71x cliff at 5000 rows and
# is functionally identical -- so review cannot catch it and this must.
# NOT a `while read` loop, deliberately. psq is `docker exec -i`, which READS
# STDIN -- inside a while-read loop it consumes the loop's own input and the loop
# dies silently after the first iteration. And this host runs bash 3.2, which has
# no associative arrays. Both bit this suite once; the fix is to materialise the
# list FIRST and iterate over a completed string.
S3LIST=$(psq "select policyname||'|'||replace(coalesce(qual,'')||' '||coalesce(with_check,''), E'\n',' ') from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%' order by policyname;")
OLDIFS=$IFS; IFS=$'\n'
for line in $S3LIST; do
  IFS=$OLDIFS
  [ -z "$line" ] && { IFS=$'\n'; continue; }
  pn="${line%%|*}"; body="${line#*|}"
  # Postgres renders a scalar subquery as `( SELECT shadow_observe(...) AS
  # shadow_observe)` -- WITHOUT the schema prefix and WITH an alias. The first
  # revision matched '( SELECT public.shadow_observe' (never matches, so every
  # policy read as bare) and counted the bare name (so the alias double-counted).
  # Count CALL SITES -- the name followed by '(' -- and wrapped call sites.
  n_calls=$(printf '%s' "$body" | grep -oE '(public\.)?shadow_observe\(' | wc -l | tr -d ' ')
  n_sel=$(printf '%s' "$body" | grep -oE '\( SELECT (public\.)?shadow_observe\(' | wc -l | tr -d ' ')
  is "G4-S3-$pn" "$n_sel" "$n_calls" "$pn: every reference wrapped in a scalar subquery"
  IFS=$'\n'
done
IFS=$OLDIFS

# ================================================= G4-S6  deletion cannot break
echo
echo "-- G4-S6  C-35 cannot regress: enforcement can never block deletion --"
is G4-S6a "$(psq "select rolbypassrls::text from pg_roles where rolname='service_role';")" "true" "service_role still bypasses RLS"
is G4-S6b "$(psq "select count(*) from pg_policies where policyname in ('account_directory_select_owner','account_directory_update_owner') and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%';")" "0" "self-profile policies UNOBSERVED (C-35, D-U6-3)"
is G4-S6c "$(psq "select count(*) from pg_policies where cmd='DELETE' and schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%';")" "0" "ALL six DELETE policies unobserved (D-U6-2)"
is G4-S6d "$(psq "select count(*) from pg_policies where cmd='DELETE' and schemaname in ('public','storage');")" "6" "...and there are exactly six of them"

# ==================================================== G4-S7  bounded aggregate
echo
echo "-- G4-S7  the store is a bounded aggregate, never an append-only log --"
psqf <<'SQL' >/dev/null
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000a001','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','u6a-s7@local.invalid', now(), now())
on conflict do nothing;
SQL
psq "select set_config('request.jwt.claims','{\"sub\":\"00000000-0000-0000-0000-00000000a001\"}',true); select public.shadow_observe('probe.s7') from generate_series(1,25);" >/dev/null
is G4-S7a "$(psq "select count(*) from public.shadow_enforcement_stat where surface='probe.s7';")" "1" "25 identical decisions produce ONE row"
is G4-S7b "$(psq "select observations::text from public.shadow_enforcement_stat where surface='probe.s7';")" "25" "...with the counter at 25"
is G4-S7c "$(psq "select count(*) from public.shadow_enforcement_stat where bucket_hour <> date_trunc('hour', bucket_hour);")" "0" "every bucket is hour-aligned"

# ================================================ G4-B1/B3/B4  the observations
echo
echo "-- G4-B1/B3/B4  clause vocabulary, separability, attributability --"
is G4-B1 "$(psq "select count(*) from public.shadow_enforcement_stat where decided_clause not in ('entitled','expired','sandbox_only','grandfathered','unknown');")" "0" "every observation names one of the five clauses"
is G4-B3 "$(psq "select count(*) from pg_constraint where conname='shadow_stat_clause_check';")" "1" "sandbox_only is SEPARABLE by constraint, so it can be excluded from the denial report"
is G4-B4 "$(psq "select count(*) from public.shadow_enforcement_stat where user_id is null;")" "0" "every observation is attributable to an identity"

# ========================================================= G4-S2  THE BIG ONE
echo
echo "-- G4-S2  ATTACHED vs DETACHED: identical rows, 4 identity classes x 4 surfaces --"
echo "   (the assertion that makes 'shadow' mean something)"

# Four identity classes, built explicitly. An empty fixture is not a pass, so
# each is created and read back before anything depends on it.
mkid() { psq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at) values ('$1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$2@local.invalid',now(),now()) on conflict do nothing; select count(*) from auth.users where id='$1';"; }
ENT=00000000-0000-0000-0000-00000000b001   # entitled Production member
LAP=00000000-0000-0000-0000-00000000b002   # lapsed Production member
SBX=00000000-0000-0000-0000-00000000b003   # Sandbox-only
NON=00000000-0000-0000-0000-00000000b004   # no membership row at all
for pair in "$ENT ent" "$LAP lap" "$SBX sbx" "$NON non"; do set -- $pair; mkid "$1" "u6a-$2" >/dev/null; done
is G4-S2-fix "$(psq "select count(*) from auth.users where id in ('$ENT','$LAP','$SBX','$NON');")" "4" "four identity classes exist before use"

psqf <<SQL >/dev/null
insert into public.membership (user_id,environment,original_transaction_id,product_id,apple_status,renewal_date,is_in_billing_retry,renewal_info_signed_date,binding_method,bound_at)
values ('$ENT','Production','u6a-ent','etudes.connected.monthly',1, now()+interval '30 days', false, now(), 'purchase', now()),
       ('$LAP','Production','u6a-lap','etudes.connected.monthly',2, now()-interval '2 days',  false, now(), 'purchase', now()),
       ('$SBX','Sandbox',   'u6a-sbx','etudes.connected.monthly',1, now()+interval '30 days', false, now(), 'purchase', now())
on conflict do nothing;
-- content owned by a fifth party, visible through an approved follow
insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at)
values ('00000000-0000-0000-0000-00000000b0ff','00000000-0000-0000-0000-000000000000','authenticated','authenticated','u6a-owner@local.invalid',now(),now())
on conflict do nothing;
insert into public.posts (id,owner_user_id,is_public,created_at,attachments)
select gen_random_uuid(),'00000000-0000-0000-0000-00000000b0ff',true,now(),'[]'::jsonb from generate_series(1,10);
insert into public.follows (follower_user_id,followed_user_id,status,created_at,updated_at)
select v, '00000000-0000-0000-0000-00000000b0ff','approved',now(),now()
from unnest(array['$ENT'::uuid,'$LAP'::uuid,'$SBX'::uuid,'$NON'::uuid]) v;
insert into public.post_comments (id,post_id,owner_user_id,author_user_id,recipient_user_id,body,created_at)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-00000000b0ff', '00000000-0000-0000-0000-00000000b0ff', v, 'c', now()
from (select id from public.posts limit 3) p, unnest(array['$ENT'::uuid,'$LAP'::uuid,'$SBX'::uuid,'$NON'::uuid]) v;
SQL
is G4-S2-fix2 "$(psq "select count(*) from public.posts;")" "10" "10 posts by a followed owner exist"

# Count rows a given identity sees on a given surface, as `authenticated`.
seen() { psq "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); select count(*) from $2;" | tail -1; }

# bash 3.2 has no associative arrays, so the attached counts go to files.
ATT_DIR=$(mktemp -d); trap 'rm -rf "$ATT_DIR"' EXIT
tbl_of() { case "$1" in posts) echo public.posts;; comments) echo public.post_comments;;
                        follows) echo public.follows;; shares) echo public.post_shares;; esac; }
for pair in "$ENT ent" "$LAP lap" "$SBX sbx" "$NON non"; do
  set -- $pair
  for s in posts comments follows shares; do
    seen "$1" "$(tbl_of $s)" > "$ATT_DIR/$2-$s"
  done
done

# Capture the CURRENT (U6a) policy definitions first, generated from the catalog
# exactly as the rollback baseline was. The first revision re-attached by
# re-running the migration, whose `create table` fails on a second run -- and the
# failure was swallowed by `|| true`, so THE SUITE LEFT THE OBSERVER DETACHED and
# would have poisoned every later suite run in the same reset. A teardown whose
# failure is invisible is worse than no teardown.
#
# CAPTURE BOTH POLICIES AND FUNCTIONS. The rollback baseline restores 33 policies
# AND 9 functions; a re-attach that covers only policies leaves the nine RPCs
# detached, which is exactly what the first revision did -- the suite passed, and
# inventory-complete.sh then failed with "observed functions = 0". A teardown
# must be the inverse of the setup, over the SAME set of objects.
REATTACH="$ATT_DIR/reattach.sql"
psq "select format(E'alter policy %I on %I.%I%s%s;', policyname, schemaname, tablename,
       coalesce(' using ('||qual||')',''), coalesce(' with check ('||with_check||')',''))
     from pg_policies where schemaname in ('public','storage')
       and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%'
     order by policyname;" > "$REATTACH"
psq "select pg_get_functiondef(p.oid)||';'
     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.prokind='f' and p.proname <> 'shadow_observe'
       and pg_get_functiondef(p.oid) like '%shadow_observe%'
     order by p.proname;" >> "$REATTACH"
is G4-S2-cap "$(grep -c '^alter policy' "$REATTACH")" "23" "23 attached policy definitions captured before detaching"
is G4-S2-cap2 "$(grep -c '^CREATE OR REPLACE FUNCTION' "$REATTACH")" "9" "...and the 9 observed function definitions too"

# DETACH: restore the pre-U6a definitions from the captured rollback baseline.
docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 \
  < supabase/sql/2026-08-30-u6a-rollback-baseline.sql >/dev/null 2>&1
DET=$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%';")
is G4-S2-det "$DET" "0" "observer fully DETACHED before the comparison"

for pair in "$ENT ent" "$LAP lap" "$SBX sbx" "$NON non"; do
  set -- $pair
  for s in posts comments follows shares; do
    is "G4-S2-$2-$s" "$(seen "$1" "$(tbl_of $s)")" "$(cat "$ATT_DIR/$2-$s")" "$2/$s identical attached vs detached"
  done
done

# RE-ATTACH from the captured definitions, and ASSERT it worked. A teardown that
# is not asserted is a teardown that silently did not happen.
docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 < "$REATTACH" >/dev/null 2>&1
is G4-S2-re "$(psq "select count(*) from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'')||coalesce(with_check,'')) like '%shadow_observe%';")" "23" "23 policies RE-ATTACHED"
is G4-S2-re2 "$(psq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' and p.proname<>'shadow_observe' and pg_get_functiondef(p.oid) like '%shadow_observe%';")" "9" "...and 9 functions -- the suite leaves the instance as it found it"

# ================================== G4-S8  the window actually records from RLS
echo
echo "-- G4-S8  the observer fires from POLICY evaluation, not only when called --"
echo "   (attached-and-silent and attached-and-working look identical otherwise)"
# FOUR rows, not one: the aggregate is keyed by user_id, and G4-S2 drove the
# same surface as four different identity classes. Asserting 4 is the stronger
# statement -- it proves each identity was observed SEPARATELY, which is what
# makes sandbox_only separable from a real lapse (G4-B3, and D4's whole reason
# for adding the fifth state).
is G4-S8a "$(psq "select count(*) from public.shadow_enforcement_stat where surface='posts.select';")" "4" "posts.select observed once per identity class, separately"
is G4-S8a2 "$(psq "select count(distinct user_id) from public.shadow_enforcement_stat where surface='posts.select';")" "4" "...four distinct identities, none conflated"
is G4-S8b "$(psq "select count(*) from public.shadow_enforcement_stat where surface not like 'probe.%' and observations > 0;")" "$(psq "select count(*) from public.shadow_enforcement_stat where surface not like 'probe.%';")" "every policy-driven row carries a positive counter"
is G4-S8c "$(psq "select count(distinct decided_clause) >= 1 from public.shadow_enforcement_stat where surface not like 'probe.%';")" "t" "...and each names a clause"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] || exit 1
