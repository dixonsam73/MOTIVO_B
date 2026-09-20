-- B-37 — LITERAL SEARCH TOKENS AND A PER-ACCOUNT SEARCH BUDGET
--
-- Two defects and one control, in one migration because they live in one
-- predicate:
--
--   1. LITERAL TOKENS. Caller tokens reached three separate LIKE expressions
--      unescaped, so `%%` or `__` browsed the whole directory in one query
--      through the ordinary authenticated client. MEASURED on a local stack:
--      4 of 4 other rows, HTTP 200.
--
--   2. THE EMPTY-TOKEN BROWSE, which escaping alone does NOT close.
--      `btrim(q)` trims SPACES ONLY, so a query of two TABS passes
--      `char_length(btrim(q)) >= 2`, splits into empty tokens, and leaves the
--      tokens CTE empty -- at which point `not exists (... where not (...))` is
--      vacuously TRUE FOR EVERY ROW. MEASURED: two tabs, two newlines and
--      tab-space-tab each returned the entire directory. The explicit
--      "at least one token" guard below is what closes it.
--
--   3. A PER-ACCOUNT BUDGET, counted inside this function, so that systematic
--      enumeration is slow and attributable while an ordinary search is
--      instant. It raises the cost of bulk collection; it does not prevent it,
--      and nothing here should be described as preventing it.
--
-- THE FUNCTION BECOMES VOLATILE, AND THAT IS LOAD-BEARING RATHER THAN
-- STYLISTIC. PostgREST executes a STABLE function's RPC in a READ-ONLY
-- transaction: a nested INSERT fails with SQLSTATE 25006, "cannot execute
-- INSERT in a read-only transaction". MEASURED directly. Two consequences:
--   * no counter write could ever land while the function stayed STABLE; and
--   * `enforcement_gate`'s telemetry INSERT has been failing on this path all
--     along and being swallowed by its own `exception when others then null`.
--     After this migration that write SUCCEEDS, so `shadow_enforcement_stat`
--     begins recording `rpc.search_account_directory` where it previously
--     recorded nothing. That is a consequence of the volatility change, not a
--     separate feature, and it is deliberately not suppressed.
--   * GET: PostgREST serves an RPC over GET for STABLE functions, and it does
--     so for this one today, returning real rows. A VOLATILE function under
--     GET still runs read-only, so the budget INSERT raises and the request
--     FAILS CLOSED with no rows.
--
-- WHAT IS DELIBERATELY NOT CHANGED. Ordinary broad matching stays: `a e` is a
-- literal two-token search and short tokens legitimately match much of a small
-- community. There is NO per-token minimum -- the promised fix is literal
-- special characters, not the elimination of broad ordinary matching. The
-- two-character whole-query floor stays (production carries a two-character
-- display name -- B-15). `location` is still returned. `LIMIT 20` and the
-- ordering are unchanged. `get_account_directory_by_user_ids` is untouched and
-- must keep ignoring the discovery opt-out (G10 / C-58).

begin;

-- ---------------------------------------------------------------- the counter
--
-- One row per member, bounded by auth.users and removed by FK cascade, so
-- retention needs no worker. A per-request log was rejected: it would be
-- unbounded, need cleanup, and create a durable record of every search a member
-- performs -- a privacy cost paid to solve a privacy problem.
--
-- ANCHORED FIXED WINDOWS, not rolling windows. Known residual: a caller timing
-- requests across a boundary can obtain up to double the burst allowance in a
-- short span. Accepted for a budget whose purpose is to make sweeps slow.

create table if not exists public.directory_search_budget (
    user_id            uuid        not null references auth.users(id) on delete cascade,
    burst_started_at   timestamptz not null,
    burst_count        integer     not null,
    window_started_at  timestamptz not null,
    window_count       integer     not null,
    updated_at         timestamptz not null default now(),
    -- Named rather than generated, because the upsert below targets the
    -- CONSTRAINT and not the column: `on conflict (user_id)` is AMBIGUOUS
    -- against this function's RETURNS TABLE output variable of the same name,
    -- and fails at runtime with 42702 on every call. Observed, not foreseen --
    -- it only appeared when the real RPC was exercised.
    constraint directory_search_budget_pkey primary key (user_id)
);

comment on table public.directory_search_budget is
  'B-37 per-account directory search budget. Private: no client role holds any '
  'privilege, and RLS is on with no policy. Written only by '
  'search_account_directory() as SECURITY DEFINER. Never grant this to a client '
  'role -- a member who can read or write it can reset their own allowance.';

-- U3's rule: a new table's privileges must be deterministic rather than
-- inherited from whatever pg_default_acl applies to the creating role.
revoke all on public.directory_search_budget from public;
revoke all on public.directory_search_budget from anon;
revoke all on public.directory_search_budget from authenticated;
revoke all on public.directory_search_budget from service_role;

alter table public.directory_search_budget enable row level security;

-- ------------------------------------------------------------- the predicate

create or replace function public.search_account_directory(q text)
returns table (
    user_id        uuid,
    account_id     text,
    display_name   text,
    location       text,
    avatar_key     text,
    instruments    text[],
    avatar_version timestamptz
)
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
    -- B-37 allowances. PROVISIONAL INITIAL VALUES, argued from client cadence
    -- and not from measured production behaviour: search is one deliberate
    -- button tap (no type-ahead, no debounce), and a human refinement cycle is
    -- one search every 5-15 seconds. They are NOT recorded on
    -- membership_control or any other membership authority object -- search
    -- budgeting and membership/age authority stay separate, so revising these
    -- is a function replacement and never a write to an authority surface.
    c_burst_window constant interval := interval '60 seconds';
    c_burst_limit  constant integer  := 10;
    c_long_window  constant interval := interval '60 minutes';
    c_long_limit   constant integer  := 120;

    v_now     timestamptz := now();   -- one server-time basis for the whole call
    v_uid     uuid;
    v_prefer  text;
    v_bstart  timestamptz;
    v_bcount  integer;
    v_lstart  timestamptz;
    v_lcount  integer;
    v_retry   integer := 0;
    v_tokens  text[];
begin
    v_uid := (select auth.uid());

    -- Existing controls first, so an unauthenticated or unentitled caller is
    -- refused by them and never creates a budget row.
    if v_uid is null then
        return;
    end if;

    if not (select public.enforcement_gate('rpc.search_account_directory')) then
        return;
    end if;

    -- A rolled-back transaction would discard the budget debit while still
    -- returning rows, so this function refuses ANY request carrying a `Prefer`
    -- header. That is blunter than matching `tx=rollback`, and it is blunt
    -- DELIBERATELY, because the narrow version was MEASURED TO BE DEFEATED:
    --
    --   * `request.headers ->> 'prefer'` exposes only ONE value when a caller
    --     sends duplicate Prefer headers, and which one survives depends on
    --     their ORDER;
    --   * so `Prefer: tx=rollback` + `Prefer: count=exact` presents
    --     `count=exact` to SQL while PostgREST still honours the rollback.
    --     Under `db-tx-end = commit-allow-override` that returned directory
    --     rows with NO durable debit -- a working bypass of the budget.
    --
    -- Refusing on the mere PRESENCE of the header closes that, because at least
    -- one value is always visible. The shipping client sends no Prefer header
    -- on this call at all (NetworkManager adds only apikey, Authorization and
    -- Content-Type, and AccountDirectoryService.search passes no extra
    -- headers), so CURRENT APP REQUESTS ARE UNCHANGED. That is not the same as
    -- "nothing legitimate is refused": a direct caller using an ordinary
    -- preference such as `count=exact` on this RPC IS refused, deliberately.
    -- Anyone wanting to allow one should read the measurement above first.
    --
    -- THIS STILL DOES NOT DEFEND AGAINST A SERVER CONFIGURED TO ROLL BACK BY
    -- DEFAULT, because then no header is sent and nothing distinguishes the
    -- request. Verifying production commit mode is a separate deployment
    -- prerequisite and is not discharged here.
    v_prefer := nullif(current_setting('request.headers', true), '')::jsonb ->> 'prefer';
    if v_prefer is not null then
        raise exception 'search_transaction_preference_unsupported'
            using hint = 'A transaction preference could discard the search budget debit.';
    end if;

    -- The whole-query floor, unchanged. B-15: 2 is the smallest product-valid
    -- value, because production carries a two-character display name.
    if char_length(btrim(q)) < 2 then
        return;
    end if;

    -- Tokens, escaped ONCE into an array so all three LIKE branches below
    -- consume a neutralised value and none can be missed. THE ESCAPE CHARACTER
    -- IS ESCAPED FIRST: doing % and _ before \ would double-escape a caller's
    -- literal backslash. E'\\' is a single backslash and E'\\\\' is two, so the
    -- pairs read as ('\' -> '\\'), ('%' -> '\%'), ('_' -> '\_').
    --
    -- An array rather than a temporary table: a temp table per request would
    -- add catalog churn to every search for no benefit.
    select array_agg(distinct
               replace(replace(replace(lower(t), E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_'))
      into v_tokens
      from regexp_split_to_table(btrim(q), '\s+') as t
     where t <> '';

    -- EXPLICIT, AND NOT CEREMONY. With no tokens the "every token must match"
    -- test below is vacuously true for EVERY row, which is how two tabs
    -- returned the entire directory. btrim trims SPACES ONLY, so that query
    -- clears the floor above.
    if v_tokens is null or array_length(v_tokens, 1) is null then
        return;
    end if;

    -- ------------------------------------------------------------ the budget
    --
    -- Atomic by row lock. The upsert writes only updated_at, so the counts it
    -- returns are the PRE-state, and the row stays locked for the rest of the
    -- transaction -- concurrent calls for one identity serialise and a lost
    -- update is not representable. A REFUSAL BELOW RAISES, so the whole
    -- transaction including this write is rolled back and a refused request
    -- consumes no allowance and leaves no trace.
    insert into public.directory_search_budget as b
           (user_id, burst_started_at, burst_count, window_started_at, window_count)
    values (v_uid, v_now, 0, v_now, 0)
    on conflict on constraint directory_search_budget_pkey do update set updated_at = v_now
    returning b.burst_started_at, b.burst_count, b.window_started_at, b.window_count
    into v_bstart, v_bcount, v_lstart, v_lcount;

    if v_bstart <= v_now - c_burst_window then
        v_bstart := v_now; v_bcount := 0;
    end if;
    if v_lstart <= v_now - c_long_window then
        v_lstart := v_now; v_lcount := 0;
    end if;

    if v_bcount >= c_burst_limit or v_lcount >= c_long_limit then
        -- Derived from the actual end of each blocking window, never invented,
        -- and the MAXIMUM when both block.
        if v_bcount >= c_burst_limit then
            v_retry := greatest(v_retry,
                ceil(extract(epoch from (v_bstart + c_burst_window - v_now)))::integer);
        end if;
        if v_lcount >= c_long_limit then
            v_retry := greatest(v_retry,
                ceil(extract(epoch from (v_lstart + c_long_window - v_now)))::integer);
        end if;

        -- PT429 -> HTTP 429 (MEASURED). Deliberately NOT 401: the client
        -- refreshes the session and retries on 401 only, and a throttle must
        -- never be mistaken for an authentication challenge.
        raise sqlstate 'PT429'
            using message = 'search_rate_limited',
                  detail  = json_build_object('retry_after_seconds', greatest(v_retry, 1))::text;
    end if;

    update public.directory_search_budget
       set burst_started_at  = v_bstart,
           burst_count       = v_bcount + 1,
           window_started_at = v_lstart,
           window_count      = v_lcount + 1,
           updated_at        = v_now
     where directory_search_budget.user_id = v_uid;

    -- ------------------------------------------------------------ the search
    return query
    select
        ad.user_id,
        ad.account_id,
        ad.display_name,
        ad.location,
        ad.avatar_key,
        ad.instruments,
        ad.avatar_version
    from public.account_directory ad
    where
        -- D-U6-1: a lapsed member becomes UNDISCOVERABLE. Subject-side, and it
        -- respects the kill switch, or a rollback would only half-roll-back.
        -- get_account_directory_by_user_ids deliberately has NO such filter (G10).
        ((select not public.enforcement_active()) or ad.entitled_until > now())

        -- CP-2 / P5-E: EFFECTIVE discovery. UNCONDITIONAL, and deliberately NOT
        -- wrapped in enforcement_active() the way D-U6-1 above is. The kill
        -- switch may relax ENTITLEMENT gating; it must never relax CHILD-SAFETY
        -- privacy. Absence of a privacy row resolves FALSE.
        and public.account_privacy_discoverable(ad.user_id)

        -- Self-exclusion, not a security control. B-15: it yields NULL for an
        -- anonymous caller, which is why the v_uid null check above is the real
        -- protection and must stay.
        and ad.user_id <> v_uid

        -- Every search token must match somewhere, as LITERAL text.
        and not exists (
            select 1
            from unnest(v_tokens) as token
            where not (
                (ad.account_id is not null
                    and lower(ad.account_id) like token || '%' escape '\')

                or

                (lower(ad.display_name) like '%' || token || '%' escape '\')

                or

                exists (
                    select 1
                    from unnest(coalesce(ad.instruments, '{}')) as instrument
                    where lower(instrument) like '%' || token || '%' escape '\'
                )
            )
        )

    order by
        ad.account_id nulls last,
        ad.user_id

    limit 20;
end;
$function$;

-- The grant is unchanged and is restated so the privilege surface is explicit
-- rather than inherited: authenticated only, never anon or service_role.
revoke all on function public.search_account_directory(text) from public;
revoke all on function public.search_account_directory(text) from anon;
revoke all on function public.search_account_directory(text) from service_role;
grant execute on function public.search_account_directory(text) to authenticated;

commit;
