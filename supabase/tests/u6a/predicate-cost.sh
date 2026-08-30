#!/usr/bin/env bash
#
# U6a GATE, EXPERIMENT 4 — what does the entitlement predicate COST when it is
# evaluated inside an RLS policy on a feed-shaped query?
#
# The question that matters is not milliseconds, it is ORDER: is the predicate
# evaluated ONCE PER QUERY or ONCE PER ROW? connected_member() is SECURITY
# DEFINER and runs two correlated subqueries over membership + membership_cutover,
# so once-per-row on a growing feed is a different design from once-per-query.
#
# EVERYTHING RUNS INSIDE ONE TRANSACTION THAT ROLLS BACK. The U5d record already
# caught a cross-suite leak from assertions that counted rows GLOBALLY after a
# suite left fixtures behind; this experiment refuses to be that suite.
#
# LOCAL DISPOSABLE STACK ONLY -- inherits u4/lib.sh's guards.

set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u4/lib.sh

N="${1:-500}"

echo "=============================================================="
echo " U6a GATE 4 — cost of the entitlement predicate under RLS"
echo " fixture: $N posts   (production held 99 at the last capture)"
echo "=============================================================="

docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 -v n="$N" <<'SQL'
begin;

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'u6a'||g||'@local.invalid', now(), now()
from generate_series(1,16) g;

-- Capture the viewer id into a psql variable BEFORE any `set role`. The first
-- revision kept it in a temp table and read it back after switching role, which
-- failed with "permission denied for table me" -- authenticated has no
-- privilege on a postgres-owned temp table. The fixture must be resolved by the
-- owner and then passed in as a literal.
select id as viewer from auth.users order by id limit 1 \gset

insert into public.posts (id, owner_user_id, is_public, created_at, attachments)
select gen_random_uuid(),
       (select id from auth.users order by id offset (g % 16) limit 1),
       true, now(), '[]'::jsonb
from generate_series(1, :n) g;

insert into public.follows (follower_user_id, followed_user_id, status, created_at, updated_at)
select :'viewer', id, 'approved', now(), now()
from auth.users where id <> :'viewer';

\echo ''
\echo '--- BASELINE: the shipping posts SELECT policy, no entitlement clause ---'
set local role authenticated;
select set_config('request.jwt.claims',
       json_build_object('sub', :'viewer', 'role','authenticated')::text, true) \gset ignore_
explain (analyze, timing off, summary on, costs off)
  select count(*) from public.posts;
reset role;

-- --------------------------------------------- add the entitlement predicate
-- S2 shape from experiment 1b: a ZERO-ARGUMENT SECURITY DEFINER wrapper over
-- auth.uid(), granted to authenticated. Experiment 1 proved the ungranted
-- uuid-taking form cannot be referenced from a qual at all.
create function public.u6a_is_member() returns boolean
  language sql stable security definer set search_path = ''
  as $$ select public.connected_member((select auth.uid())) $$;
grant execute on function public.u6a_is_member() to authenticated;

alter policy posts_select_public_or_owner on public.posts
  using (
    public.u6a_is_member()
    and ((owner_user_id = auth.uid())
      or (is_public = true and exists (
            select 1 from public.follows f
             where f.follower_user_id = auth.uid()
               and f.followed_user_id = posts.owner_user_id
               and f.status = 'approved')))
  );

\echo ''
\echo '--- ENFORCED, viewer NOT a member (expect 0 rows) ---'
set local role authenticated;
select set_config('request.jwt.claims',
       json_build_object('sub', :'viewer', 'role','authenticated')::text, true) \gset ignore2_
explain (analyze, timing off, summary on, costs off)
  select count(*) from public.posts;
reset role;

-- make the viewer an entitled PRODUCTION member
insert into public.membership
  (user_id, environment, original_transaction_id, product_id, apple_status,
   renewal_date, is_in_billing_retry, renewal_info_signed_date,
   binding_method, bound_at)
values (:'viewer', 'Production', 'u6a-cost-otid', 'etudes.connected.monthly',
        1, now() + interval '30 days', false, now(), 'purchase', now());

\echo ''
\echo '--- ENFORCED, viewer IS an entitled member (expect rows) ---'
set local role authenticated;
select set_config('request.jwt.claims',
       json_build_object('sub', :'viewer', 'role','authenticated')::text, true) \gset ignore3_
explain (analyze, timing off, summary on, costs off)
  select count(*) from public.posts;
reset role;

\echo ''
\echo '--- ORDER CHECK: is the predicate a One-Time Filter (per query) or per row? ---'

rollback;
SQL

echo
echo "=== RESIDUE CHECK — the transaction must have left nothing ==="
psq "select 'auth.users='||(select count(*) from auth.users)
        ||' posts='||(select count(*) from public.posts)
        ||' follows='||(select count(*) from public.follows)
        ||' membership='||(select count(*) from public.membership)
        ||' u6a_is_member_fns='||(select count(*) from pg_proc where proname='u6a_is_member')"
echo "=== posts SELECT policy qual restored to the shipping definition? ==="
psq "select case when qual like '%u6a_is_member%' then 'CONTAMINATED' else 'clean (no entitlement clause)' end from pg_policies where tablename='posts' and cmd='SELECT'"
