#!/usr/bin/env bash
#
# U6a GATE, EXPERIMENT 3 — can a SHADOW predicate record its decision?
#
# G4 asks for "per denied request, WHICH CLAUSE would have decided it". That is
# not something RLS naturally gives you:
#
#   * a SELECT policy FILTERS, it does not deny -- there is no denial event;
#   * a policy qual is an expression, and expressions do not write;
#   * membership_state() can name the clause, but nothing calls it per request.
#
# Experiment 4b found the hook: written as `(select f())` the predicate becomes
# an InitPlan, evaluated EXACTLY ONCE per query per table. That is the natural
# granularity for a shadow record. This experiment measures whether a predicate
# that WRITES can live there, and what it costs.
#
# Three things are measured, not argued:
#   M1  can a function INSERT a log row while being called from a SELECT policy?
#   M2  does making it VOLATILE (required to write) destroy the InitPlan, i.e.
#       collapse it back to once-per-row?
#   M3  how many log rows does one query actually produce?
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

create table public.u6a_shadow_log(
  id bigserial primary key, at timestamptz not null default now(),
  user_id uuid, surface text, decided text, would_deny boolean);

-- THE SHADOW PREDICATE. Returns TRUE unconditionally -- it denies nothing, by
-- construction, which is what makes a shadow window a shadow window. It records
-- what enforcement WOULD have decided, and the clause membership_state() names.
create function public.u6a_shadow(p_surface text) returns boolean
  language plpgsql volatile security definer set search_path = ''
  as $fn$
  declare u uuid; st text; ent boolean;
  begin
    u := (select auth.uid());
    st := public.membership_state(u);
    ent := public.connected_member(u);
    insert into public.u6a_shadow_log(user_id, surface, decided, would_deny)
    values (u, p_surface, st, not coalesce(ent,false));
    return true;   -- ALWAYS. Shadow denies nothing.
  end $fn$;
grant execute on function public.u6a_shadow(text) to authenticated;

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

\echo 'SHADOWROWS:'
select count(*) as log_rows from public.u6a_shadow_log;
select distinct decided, would_deny from public.u6a_shadow_log;
rollback;
SQL
)

run_one() {
  printf '%s' "${SQL_TEMPLATE//__PRED__/$2}" \
  | docker exec -i "$DB" psql -U postgres -d postgres -q -t -v ON_ERROR_STOP=1 -v n="$1" 2>&1
}

echo "======================================================================"
echo " U6a GATE 3 — can the shadow predicate record, and at what granularity?"
echo "======================================================================"
printf '%-8s %-12s %-12s %-18s %s\n' ROWS SHAPE "EXEC(ms)" SITE "LOG ROWS PER QUERY"
for n in 500 5000; do
  for shape in bare subquery; do
    case "$shape" in
      bare)     pred="public.u6a_shadow('posts.select')" ;;
      subquery) pred="(select public.u6a_shadow('posts.select'))" ;;
    esac
    out=$(run_one "$n" "$pred")
    ms=$(printf '%s' "$out" | grep -o 'Execution Time: [0-9.]*' | awk '{print $3}')
    logn=$(printf '%s' "$out" | sed -n '/SHADOWROWS:/,$p' | grep -oE '^ *[0-9]+' | head -1 | tr -d ' ')
    if   printf '%s' "$out" | grep -q 'One-Time Filter'; then site="One-Time Filter"
    elif printf '%s' "$out" | grep -q 'InitPlan';        then site="InitPlan"
    else site="per-row Filter"; fi
    err=$(printf '%s' "$out" | grep 'ERROR' | head -1)
    printf '%-8s %-12s %-12s %-18s %s %s\n' "$n" "$shape" "${ms:-?}" "$site" "${logn:-?}" "$err"
  done
done

echo
echo "-- what clause did membership_state() name? --"
printf '%s' "$(run_one 500 "(select public.u6a_shadow('posts.select'))")" | sed -n '/SHADOWROWS:/,$p' | head -8

echo
echo "-- is PostgREST's per-REQUEST hook available? (the other candidate) --"
psq "select coalesce(nullif(current_setting('pgrst.db_pre_request', true),''),'<unset>') as db_pre_request"
psq "select rolname||' -> '||coalesce(array_to_string(rolconfig,' | '),'<no role config>') from pg_roles where rolname in ('authenticator','authenticated')"

echo
echo "=== RESIDUE CHECK ==="
psq "select 'posts='||(select count(*) from public.posts)||' users='||(select count(*) from auth.users)||' shadow_log_tables='||(select count(*) from pg_tables where tablename='u6a_shadow_log')||' shadow_fns='||(select count(*) from pg_proc where proname='u6a_shadow')"
psq "select case when qual like '%u6a_shadow%' then 'CONTAMINATED' else 'posts policy clean' end from pg_policies where tablename='posts' and cmd='SELECT'"
