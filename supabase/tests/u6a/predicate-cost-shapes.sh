#!/usr/bin/env bash
#
# U6a GATE, EXPERIMENT 4b — the per-row cost found in experiment 4 is a property
# of HOW the predicate is written, not of the predicate itself. Two shapes:
#
#   BARE      using ( is_member() and <row predicate> )
#   SUBQUERY  using ( (select is_member()) and <row predicate> )
#
# A scalar subquery with no outer reference becomes an InitPlan: evaluated ONCE
# per query and reused. A bare STABLE call is NOT hoisted -- STABLE promises
# stability within a statement, it does not make the planner cache the result --
# so it lands in the per-row Filter and runs once per scanned row.
#
# Measured at two fixture sizes so the ORDER is visible, not just a timing.
#
# The predicate text is substituted in BASH, against a __PRED__ placeholder.
# Earlier revisions tried `execute format(...)` at psql top level (not a psql
# statement -- it errored, the policy was never altered, and all four shapes
# silently measured the same unenforced policy) and then psql interpolation
# inside a dollar-quoted DO block (psql does not substitute there). Both failures
# looked like a RESULT rather than an error: four identical rows.
#
# LOCAL DISPOSABLE STACK ONLY. One transaction, always rolled back.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u4/lib.sh

SQL_TEMPLATE=$(cat <<'SQL'
begin;
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'u6a'||g||'@local.invalid', now(), now()
from generate_series(1,16) g;
select id as viewer from auth.users order by id limit 1 \gset
insert into public.posts (id, owner_user_id, is_public, created_at, attachments)
select gen_random_uuid(), (select id from auth.users order by id offset (g % 16) limit 1),
       true, now(), '[]'::jsonb from generate_series(1, :n) g;
insert into public.follows (follower_user_id, followed_user_id, status, created_at, updated_at)
select :'viewer', id, 'approved', now(), now() from auth.users where id <> :'viewer';
insert into public.membership
  (user_id, environment, original_transaction_id, product_id, apple_status,
   renewal_date, is_in_billing_retry, renewal_info_signed_date, binding_method, bound_at)
values (:'viewer','Production','u6a-otid','etudes.connected.monthly',1,
        now() + interval '30 days', false, now(), 'purchase', now());

create function public.u6a_is_member() returns boolean
  language sql stable security definer set search_path = ''
  as $fn$ select public.connected_member((select auth.uid())) $fn$;
grant execute on function public.u6a_is_member() to authenticated;

alter policy posts_select_public_or_owner on public.posts
  using (__PRED__ and ((owner_user_id = auth.uid())
     or (is_public = true and exists (
           select 1 from public.follows f
            where f.follower_user_id = auth.uid()
              and f.followed_user_id = posts.owner_user_id
              and f.status = 'approved'))));

set local role authenticated;
select set_config('request.jwt.claims',
       json_build_object('sub', :'viewer', 'role','authenticated')::text, true) \gset ig_
explain (analyze, timing off, costs off) select count(*) from public.posts;
reset role;
rollback;
SQL
)

run_one() { # run_one <n> <pred-sql>
  printf '%s' "${SQL_TEMPLATE//__PRED__/$2}" \
  | docker exec -i "$DB" psql -U postgres -d postgres -q -t -v ON_ERROR_STOP=1 -v n="$1" 2>&1
}

echo "======================================================================"
echo " U6a GATE 4b — bare call vs scalar subquery"
echo "======================================================================"
printf '%-8s %-10s %-12s %-18s %-9s %s\n' ROWS SHAPE "EXEC(ms)" "PREDICATE-SITE" "VISIBLE" ERR
for n in 500 5000; do
  for shape in bare subquery; do
    case "$shape" in
      bare)     pred="public.u6a_is_member()" ;;
      subquery) pred="(select public.u6a_is_member())" ;;
    esac
    out=$(run_one "$n" "$pred")
    ms=$(printf '%s' "$out"  | grep -o 'Execution Time: [0-9.]*' | awk '{print $3}')
    vis=$(printf '%s' "$out" | grep -o 'Seq Scan on posts (actual rows=[0-9]*' | grep -o '[0-9]*$')
    err=$(printf '%s' "$out" | grep -c 'ERROR')
    if   printf '%s' "$out" | grep -q 'One-Time Filter'; then site="One-Time Filter"
    elif printf '%s' "$out" | grep -q 'InitPlan';        then site="InitPlan"
    else site="per-row Filter"; fi
    printf '%-8s %-10s %-12s %-18s %-9s %s\n' "$n" "$shape" "${ms:-?}" "$site" "${vis:-?}" "$err"
    [ "$err" != "0" ] && printf '%s\n' "$out" | grep 'ERROR' | head -2
  done
done

echo
echo "=== RESIDUE CHECK ==="
psq "select 'auth.users='||(select count(*) from auth.users)||' posts='||(select count(*) from public.posts)||' membership='||(select count(*) from public.membership)||' u6a_fns='||(select count(*) from pg_proc where proname='u6a_is_member')"
psq "select case when qual like '%u6a_is_member%' then 'CONTAMINATED' else 'posts policy clean' end from pg_policies where tablename='posts' and cmd='SELECT'"
