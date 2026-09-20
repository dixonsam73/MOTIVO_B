#!/usr/bin/env bash
#
# B-37 ACCEPTANCE — LITERAL SEARCH TOKENS AND THE PER-ACCOUNT SEARCH BUDGET.
# LOCAL DISPOSABLE STACK ONLY.
#
#   supabase db reset --local && ./supabase/tests/b37/acceptance.sh
#
# WHAT THIS CLAIMS.
#   B  wildcard characters are matched as LITERAL text in all three branches,
#      and every branch still matches ordinary text including a literal % or _;
#   C  multi-token searching is UNCHANGED (no per-token floor), and a query that
#      yields no tokens returns nothing instead of browsing;
#   D  the budget admits ordinary use, refuses excess with a derived duration,
#      charges nothing for a refusal, and resets on its anchor;
#   E  it is atomic under contention, across BOTH limits, and per identity;
#   F  it cannot be bypassed by transaction preference, HTTP method, direct
#      table access, a re-issued token, or any other granted route;
#   G  discovery, entitlement, self-exclusion and by-ID attribution are intact.
#
# WHAT IT DOES NOT CLAIM: that bulk collection is prevented, that enumeration is
# impossible, or anything about production. Every number here is local.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh

# lib.sh's sql() cannot report a CLI-level failure: `out=$(cmd)` under `set -e`
# aborts before its own error branch is reachable, so a broken fixture exits 1
# in silence. Three faults hid behind that while this suite was written.
sql() {
  local out rc=0
  out=$(supabase db query --local "$1" 2>/dev/null) || rc=$?
  if [ $rc -ne 0 ]; then echo "SQL FAILED (exit $rc): $1" >&2; return 1; fi
  case "$out" in *'"_tag":"Error"'*) echo "SQL FAILED: $out" >&2; return 1 ;; esac
  printf '%s' "$out"
}
scalar() { local o rc=0; o=$(sql "$1") || rc=$?; [ $rc -eq 0 ] || return $rc
           printf '%s' "$o" | jq -r '.rows[0] | to_entries[0].value'; }

# `supabase db query --local` is SINGLE-STATEMENT at CLI 2.113.0 ("cannot insert
# multiple commands into a prepared statement"), so DDL and multi-statement
# fixtures go through psql in the local db container.
# Bind to THIS project's container by its ref, not to whatever `docker ps`
# happens to list first -- another local Supabase project would otherwise be a
# silent target for destructive fixtures.
PROJECT_REF=$(cat supabase/.temp/project-ref 2>/dev/null)
[ -n "$PROJECT_REF" ] || { echo "no supabase/.temp/project-ref; refusing to guess a container" >&2; exit 1; }
DBC="supabase_db_${PROJECT_REF}"
docker inspect "$DBC" >/dev/null 2>&1 || { echo "container $DBC is not running" >&2; exit 1; }
psqlq() { docker exec -i "$DBC" psql -v ON_ERROR_STOP=1 -q -U postgres -d postgres; }
psqlv() { docker exec "$DBC" psql -tA -U postgres -d postgres -c "$1"; }
# A probe that is EXPECTED to fail must not abort the suite (`set -e` is on from
# lib.sh), and its error text is the result being scored.
psqltry() { docker exec "$DBC" psql -tA -U postgres -d postgres -c "$1" 2>&1 || true; }
reload() { psqlv "notify pgrst, 'reload schema';" >/dev/null; sleep 2; }

# Everything this suite mutates outside its own fixtures must be undone even if
# an assertion aborts it, not only on the happy path: the db-tx-end override,
# the enforcement flag, and the induced counter fault.
#
# The tx setting is RESET rather than restored to a saved value, and that is
# only sound because it is asserted ABSENT before anything touches it -- on a
# freshly reset local stack it is. If that assertion ever fails, stop: this
# suite would be discarding a setting somebody else put there.
PRIOR_TXCFG=$(docker exec "$DBC" psql -tA -U postgres -d postgres -c \
  "select coalesce(array_to_string(s.setconfig,','),'') from pg_db_role_setting s join pg_roles r on r.oid=s.setrole where r.rolname='authenticator';" 2>/dev/null | tr -d ' ')
case "$PRIOR_TXCFG" in
  *tx_end*) echo "REFUSING TO RUN: authenticator already carries a pgrst.db_tx_end setting ($PRIOR_TXCFG)." >&2
            echo "This suite would discard it. Reset the local stack first." >&2; exit 1 ;;
esac

restore_local_state() {
  docker exec "$DBC" psql -tA -U postgres -d postgres >/dev/null 2>&1 <<'SQLR' || true
alter role authenticator reset pgrst.db_tx_end;
update public.membership_control set enforcement_enabled = false;
drop trigger if exists __b37_fault_trg on public.directory_search_budget;
drop function if exists public.__b37_fault();
notify pgrst, 'reload config';
SQLR
}
trap restore_local_state EXIT

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

ensureuser() {
  local id; id=$(mkuser "$1")
  if [ -z "$id" ] || [ "$id" = "null" ]; then id=$(scalar "select id from auth.users where email='$1@u2.local';"); fi
  [ -n "$id" ] && [ "$id" != "null" ] || { echo "ensureuser $1 FAILED" >&2; exit 1; }
  printf '%s' "$id"
}

echo; echo "B-37 acceptance — literal search tokens and the per-account budget"; echo

# ------------------------------------------------------------------ fixtures
#
# B-40's tg_account_directory_requires_band refuses a directory row unless an
# account_privacy band row exists, so privacy rows come FIRST. account_id must
# be 3-24 chars of ^[a-z0-9_]+$ (account_id_format), so the two-character
# DISPLAY-name case (B-15) carries a NULL account_id -- which also exercises the
# `account_id is not null` branch.
S=$(ensureuser b37-searcher); ST=$(tokenfor b37-searcher)
O=$(ensureuser b37-other);    OT=$(tokenfor b37-other)
U1=$(ensureuser b37-alpha); U2=$(ensureuser b37-bravo);  U3=$(ensureuser b37-ng)
U4=$(ensureuser b37-pct);   U5=$(ensureuser b37-jsmith); U6=$(ensureuser b37-hidden)

for u in "$S" "$O" "$U1" "$U2" "$U3" "$U4" "$U5" "$U6"; do
  sql "insert into public.account_privacy (user_id, age_band, lookup_enabled, lookup_set_under_band,
         follow_requests_enabled, follow_requests_set_under_band)
       values ('$u','band_18_plus',true,'band_18_plus',true,'band_18_plus')
       on conflict (user_id) do update set lookup_enabled = true;" >/dev/null
done
# The discovery opt-out subject.
sql "update public.account_privacy set lookup_enabled = false where user_id = '$U6';" >/dev/null

sql "insert into public.account_directory
       (user_id, account_id, display_name, lookup_enabled, location, instruments, entitled_until)
     values ('$S','searcher','Searcher Self',true,'Herts','{\"piano\"}', now()+interval '30 days'),
            ('$O','otherone','Other One',true,'Herts','{\"piano\"}', now()+interval '30 days'),
            ('$U1','alpha','Alice Alpha',true,'Herts','{\"violin\"}', now()+interval '30 days'),
            ('$U2','bravo','Bob Bravo',true,'Herts','{\"cello\"}', now()+interval '30 days'),
            ('$U3',null,'Ng',true,'Herts','{\"viola\"}', now()+interval '30 days'),
            ('$U4','a_b','Percent 50% Player',true,'Herts','{\"bass_guitar\"}', now()+interval '30 days'),
            ('$U5','jsmith','J Smith',true,'Herts','{\"flute\"}', now()+interval '30 days'),
            ('$U6','hidden','Hidden Person',true,'Herts','{\"oboe\"}', now()+interval '30 days')
     on conflict (user_id) do update set display_name = excluded.display_name;" >/dev/null

# 7 discoverable subjects besides the searcher (Hidden is opted out), so 7 rows
# is "everyone the searcher may see" and any test returning 7 has browsed.
VISIBLE=6   # alpha, bravo, ng, pct, jsmith, otherone

srch_as() {  # $1 token, $2 query-json -> writes body to /tmp/b37body, echoes status
  curl -s -o /tmp/b37body -w '%{http_code}' -X POST "$API/rest/v1/rpc/search_account_directory" \
    -H "apikey: $AK" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    -d "{\"q\":$2}"
}
srch() { srch_as "$ST" "$2"; }
rows() { jq 'if type=="array" then length else -1 end' </tmp/b37body 2>/dev/null; }
names() { jq -r 'if type=="array" then (map(.display_name)|sort|join(",")) else "ERR" end' </tmp/b37body 2>/dev/null; }
clearbudget() { psqlv "delete from public.directory_search_budget;" >/dev/null; }

# A query returning n rows, scored with the budget cleared first so group B and C
# can never be perturbed by group D's allowance.
q() { clearbudget; srch x "$2" >/dev/null; }

# ============================================================ B — literal text
echo "B — wildcard characters are LITERAL in all three branches"
q x '"%%"';   is B1 "$(rows)" "0" "q='%%' rows"
q x '"__"';   is B2 "$(rows)" "0" "q='__' rows"
q x '"%a"';   is B3 "$(rows)" "0" "q='%a' rows"
# A GENUINE discriminator: as a wildcard `al_` matches "alp" in alpha; as
# literal text "al_" appears in no fixture. (An earlier revision asserted 0 for
# 'a_', which was wrong -- 'a_' is a literal prefix of the account_id 'a_b', so
# 1 row was the correct answer and the test was the defect.)
q x '"al_"';  is B4 "$(rows)" "0" "q='al_' matches nothing literally (would wildcard-match 'alpha')"
q x '"%_%"';  is B5 "$(rows)" "0" "q='%_%' rows"
q x '"\\\\"'; is B6 "$(rows)" "0" "q='\\\\' (two backslashes) rows"
q x '"\\%"';  is B7 "$(rows)" "0" "q='\\%' rows"
# positive controls: two-character literal-bearing queries, one per branch
q x '"a_"';   is B8 "$(names)" "Percent 50% Player" "a literal underscore still matches where it genuinely occurs"
q x '"a_b"';  is B9  "$(names)" "Percent 50% Player" "account_id prefix branch, literal _"
q x '"0%"';   is B10 "$(names)" "Percent 50% Player" "display_name branch, literal %"
q x '"bas_"'; is B11 "$(rows)" "0" "'bas_' matches nothing literally (would wildcard-match 'bass')"
q x '"ss_g"'; is B12 "$(names)" "Percent 50% Player" "instrument branch, literal _ (bass_guitar)"
q x '"al"';   is B13 "$(names)" "Alice Alpha" "ordinary account_id prefix"
q x '"OB B"'; is B14 "$(names)" "Bob Bravo" "case-insensitive display_name"
q x '"ng"';   is B15 "$(names)" "Ng" "B-15: the two-character display name is still searchable"
q x '"cello"';is B16 "$(names)" "Bob Bravo" "ordinary instrument substring"
echo

# ================================================= C — tokens and empty tokens
echo "C — multi-token searching unchanged; no-token queries return nothing"
q x '"J Smith"'; is C1 "$(names)" "J Smith" "initial-plus-surname still matches (D4 declined)"
q x '"a e"';     C2R=$(rows)
                 if [ "$C2R" -gt 1 ] && [ "$C2R" -lt 7 ]; then ok C2 "'a e' still matches broadly ($C2R rows), by decision"
                 else bad C2 "'a e' expected an ordinary broad match, got $C2R"; fi
q x '"\t\t"';    is C3 "$(rows)" "0" "two TABS (clears the floor, yields no tokens)"
q x '"\n\n"';    is C4 "$(rows)" "0" "two NEWLINES"
q x '"\t \t"';   is C5 "$(rows)" "0" "tab-space-tab"
q x '"  "';      is C6 "$(rows)" "0" "two spaces (fails the floor)"
q x '""';        is C7 "$(rows)" "0" "empty string"
q x '"a"';       is C8 "$(rows)" "0" "single character fails the whole-query floor"
q x '"  al  "';  is C9 "$(names)" "Alice Alpha" "surrounding whitespace is trimmed"
q x '"al   al"'; is C10 "$(names)" "Alice Alpha" "repeated token (distinct) still matches"
echo

# =========================================================== D — budget policy
echo "D — the budget admits ordinary use and refuses excess with a derived duration"
clearbudget
for i in $(seq 1 10); do srch x '"al"' >/dev/null; done
is D1 "$(psqlv "select burst_count from public.directory_search_budget where user_id='$S';")" "10" "10 ordinary searches all admitted"
C=$(srch x '"al"')
is D2 "$C" "429" "the 11th is refused with HTTP 429"
is D3 "$(jq -r '.code' </tmp/b37body)" "PT429" "refusal carries a discriminable code"
is D4 "$(jq -r '.message' </tmp/b37body)" "search_rate_limited" "refusal message"
RA=$(jq -r '.details' </tmp/b37body | jq -r '.retry_after_seconds')
if [ "$RA" -ge 1 ] && [ "$RA" -le 60 ]; then ok D5 "retry_after_seconds derived from the burst window ($RA)"
else bad D5 "retry_after_seconds out of range: $RA"; fi
is D6 "$(psqlv "select burst_count from public.directory_search_budget where user_id='$S';")" "10" "a REFUSED request consumes no allowance"
is D7 "$(rows)" "-1" "a refusal returns no rows at all"
# the anchor resets
psqlv "update public.directory_search_budget set burst_started_at = now() - interval '61 seconds' where user_id='$S';" >/dev/null
is D8 "$(srch x '"al"')" "200" "the member recovers once the burst anchor ages out"
is D9 "$(psqlv "select burst_count from public.directory_search_budget where user_id='$S';")" "1" "the burst count restarts at 1"
# the long window blocks independently, and its duration is the one reported
psqlv "update public.directory_search_budget set window_count = 120, window_started_at = now() - interval '10 minutes', burst_count = 0, burst_started_at = now() where user_id='$S';" >/dev/null
is D10 "$(srch x '"al"')" "429" "the sustained limit refuses even with burst headroom"
RA2=$(jq -r '.details' </tmp/b37body | jq -r '.retry_after_seconds')
if [ "$RA2" -gt 60 ] && [ "$RA2" -le 3000 ]; then ok D11 "the reported duration is the LONG window's ($RA2 s), not the burst's"
else bad D11 "expected a long-window duration, got $RA2"; fi
# both blocking -> the maximum
psqlv "update public.directory_search_budget set burst_count = 10, burst_started_at = now() where user_id='$S';" >/dev/null
srch x '"al"' >/dev/null
RA3=$(jq -r '.details' </tmp/b37body | jq -r '.retry_after_seconds')
if [ "$RA3" -gt 60 ]; then ok D12 "with both windows blocking, the MAXIMUM is reported ($RA3 s)"
else bad D12 "expected the maximum of both windows, got $RA3"; fi
# a second identity is unaffected
is D13 "$(srch_as "$OT" '"al"')" "200" "a second identity is unaffected by the first's exhaustion"
# the signature cannot carry a caller-supplied identity
is D14 "$(psqlv "select pg_get_function_identity_arguments(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='search_account_directory';")" "q text" "the function takes only q -- no caller-supplied identity"
echo

# ========================================================== E — concurrency
echo "E — atomic under contention, across both limits"
# Every concurrent request is captured to its OWN status/body file. An earlier
# revision kept only the final counter value and shared one body path, so it
# could not tell an excess REFUSAL from an excess ERROR, and a 500 would have
# scored as a pass.
CDIR=$(mktemp -d); trap 'rm -rf "$CDIR"; restore_local_state' EXIT
burst_fire() {   # $1 = how many parallel requests, writes $CDIR/<i>.status
  rm -f "$CDIR"/*.status "$CDIR"/*.body 2>/dev/null
  local i
  for i in $(seq 1 "$1"); do
    ( curl -s -o "$CDIR/$i.body" -w '%{http_code}' -X POST "$API/rest/v1/rpc/search_account_directory" \
        -H "apikey: $AK" -H "Authorization: Bearer $ST" -H 'Content-Type: application/json' \
        -d '{"q":"al"}' > "$CDIR/$i.status" ) &
  done
  wait
}
count_status() { grep -lx "$1" "$CDIR"/*.status 2>/dev/null | wc -l | tr -d ' '; }
# curl -w writes no trailing newline, so `cat` would fuse every status into one
# unparseable string and this check would "fail" on healthy output.
other_status() { for f in "$CDIR"/*.status; do printf '%s\n' "$(cat "$f")"; done \
                 | grep -vx -e 200 -e 429 | sort -u | tr '\n' ' '; }

clearbudget; burst_fire 20
is E1  "$(count_status 200)" "10" "20 parallel requests: exactly the allowance is ACCEPTED"
is E1b "$(count_status 429)" "10" "and every excess request is REFUSED, not errored"
is E1c "$(other_status)" "" "no other status was surfaced to any caller"
is E1d "$(psqlv "select burst_count from public.directory_search_budget where user_id='$S';")" "10" "the counter agrees with the accepted count (no lost updates)"
is E1e "$(psqlv "select count(*) from public.directory_search_budget where user_id='$S';")" "1" "exactly one counter row exists"

# Crossing the SUSTAINED limit under contention: 118 of 120 used, 10 fired.
psqlv "delete from public.directory_search_budget;" >/dev/null
psqlv "insert into public.directory_search_budget (user_id,burst_started_at,burst_count,window_started_at,window_count) values ('$S', now(), 0, now(), 118);" >/dev/null
burst_fire 10
is E2  "$(count_status 200)" "2"  "sustained limit: exactly the 2 remaining are ACCEPTED"
is E2b "$(count_status 429)" "8"  "and the other 8 are REFUSED"
is E2c "$(other_status)" "" "no other status was surfaced"
is E2d "$(psqlv "select window_count from public.directory_search_budget where user_id='$S';")" "120" "the sustained counter lands exactly on the limit"

# A reset boundary under contention: the burst anchor has aged out, so all six
# must be accepted and the new window must hold EXACTLY six.
psqlv "update public.directory_search_budget set burst_started_at = now() - interval '61 seconds', burst_count = 10, window_count = 0, window_started_at = now() where user_id='$S';" >/dev/null
burst_fire 6
is E3  "$(count_status 200)" "6" "at a reset boundary all six concurrent calls are accepted"
is E3b "$(count_status 429)" "0" "and none is refused"
is E3c "$(psqlv "select burst_count from public.directory_search_budget where user_id='$S';")" "6" "the new window holds exactly six"

# Long-window reset recovery.
psqlv "update public.directory_search_budget set window_count = 120, window_started_at = now() - interval '61 minutes', burst_count = 0, burst_started_at = now() where user_id='$S';" >/dev/null
is E4  "$(srch x '"al"')" "200" "the member recovers once the SUSTAINED anchor ages out"
is E4b "$(psqlv "select window_count from public.directory_search_budget where user_id='$S';")" "1" "and the sustained count restarts at 1"

is E5 "$(psqlv "select count(*) from pg_stat_activity where wait_event_type='Lock' and query ilike '%directory_search_budget%';")" "0" "no session is left waiting on the counter lock"

# A FAULT IN THE COUNTER ITSELF MUST FAIL CLOSED, and must not leak directory
# data on the way out.
clearbudget
psqlq <<'SQLX'
create or replace function public.__b37_fault() returns trigger language plpgsql as $$
begin raise exception 'b37 induced counter fault'; end $$;
create trigger __b37_fault_trg before insert or update on public.directory_search_budget
  for each row execute function public.__b37_fault();
SQLX
FC=$(srch x '"al"')
FR=$(rows)
if [ "$FC" != "200" ]; then ok E6 "a counter fault FAILS CLOSED (HTTP $FC)"; else bad E6 "a counter fault returned HTTP 200"; fi
is E6b "$FR" "-1" "and returns no directory rows"
is E6c "$(jq -r '.code // "none"' </tmp/b37body)" "P0001" "surfacing as an ordinary error, not a throttle"
psqlq <<'SQLX'
drop trigger if exists __b37_fault_trg on public.directory_search_budget;
drop function if exists public.__b37_fault();
SQLX
is E6d "$(srch x '"al"')" "200" "and ordinary search resumes once the fault is removed"
echo

# ============================================================== F — bypass
echo "F — the budget cannot be bypassed"
clearbudget
# F1: transaction preference, under BOTH the default and a permissive setting,
# scoring the response AND the durable debit independently.
for hdr in 'Prefer: tx=rollback' 'Prefer: count=exact, tx=rollback' 'Prefer: tx=rollback, count=exact' 'Prefer: TX=ROLLBACK' 'Prefer: tx = rollback' 'Prefer: tx=rollback;q=1'; do
  B=$(psqlv "select coalesce(sum(burst_count),0) from public.directory_search_budget;")
  C=$(curl -s -o /tmp/b37body -w '%{http_code}' -X POST "$API/rest/v1/rpc/search_account_directory" \
      -H "apikey: $AK" -H "Authorization: Bearer $ST" -H 'Content-Type: application/json' -H "$hdr" -d '{"q":"al"}')
  A=$(psqlv "select coalesce(sum(burst_count),0) from public.directory_search_budget;")
  R=$(rows)
  if [ "$R" -le 0 ]; then ok "F1" "default cfg [$hdr] no rows (HTTP $C, debit $B->$A)"
  elif [ "$A" -gt "$B" ]; then ok "F1" "default cfg [$hdr] rows=$R WITH a durable debit ($B->$A)"
  else bad "F1" "default cfg [$hdr] returned $R rows and the debit did NOT persist ($B->$A)"; fi
done
# duplicate headers, BOTH orders
for pair in "count=exact|tx=rollback" "tx=rollback|count=exact"; do
  h1=${pair%%|*}; h2=${pair##*|}
  B=$(psqlv "select coalesce(sum(burst_count),0) from public.directory_search_budget;")
  C=$(curl -s -o /tmp/b37body -w '%{http_code}' -X POST "$API/rest/v1/rpc/search_account_directory" \
      -H "apikey: $AK" -H "Authorization: Bearer $ST" -H 'Content-Type: application/json' \
      -H "Prefer: $h1" -H "Prefer: $h2" -d '{"q":"al"}')
  A=$(psqlv "select coalesce(sum(burst_count),0) from public.directory_search_budget;")
  R=$(rows)
  if [ "$R" -le 0 ]; then ok "F1d" "default cfg duplicate [$h1 | $h2] no rows (HTTP $C, debit $B->$A)"
  elif [ "$A" -gt "$B" ]; then ok "F1d" "default cfg duplicate [$h1 | $h2] rows=$R WITH a durable debit ($B->$A)"
  else bad "F1d" "default cfg duplicate [$h1 | $h2] returned $R rows, debit did NOT persist ($B->$A)"; fi
done
# now under commit-allow-override, where the preference is actually honoured
psqlv "alter role authenticator set pgrst.db_tx_end = 'commit-allow-override';" >/dev/null
psqlv "notify pgrst, 'reload config';" >/dev/null; sleep 3
for pair in "tx=rollback|" "count=exact|tx=rollback" "tx=rollback|count=exact"; do
  h1=${pair%%|*}; h2=${pair##*|}
  clearbudget
  if [ -n "$h2" ]; then
    C=$(curl -s -o /tmp/b37body -w '%{http_code}' -X POST "$API/rest/v1/rpc/search_account_directory" \
        -H "apikey: $AK" -H "Authorization: Bearer $ST" -H 'Content-Type: application/json' \
        -H "Prefer: $h1" -H "Prefer: $h2" -d '{"q":"al"}')
  else
    C=$(curl -s -o /tmp/b37body -w '%{http_code}' -X POST "$API/rest/v1/rpc/search_account_directory" \
        -H "apikey: $AK" -H "Authorization: Bearer $ST" -H 'Content-Type: application/json' \
        -H "Prefer: $h1" -d '{"q":"al"}')
  fi
  A=$(psqlv "select coalesce(sum(burst_count),0) from public.directory_search_budget;")
  R=$(rows)
  # The requirement: no response may carry directory rows without a durable debit.
  if [ "$R" -le 0 ]; then ok "F1o" "override cfg [$h1${h2:+ | $h2}] no rows (HTTP $C, durable debit $A)"
  elif [ "$A" -ge 1 ]; then ok "F1o" "override cfg [$h1${h2:+ | $h2}] rows=$R WITH a durable debit ($A)"
  else bad "F1o" "override cfg [$h1${h2:+ | $h2}] returned $R rows and the debit did NOT persist"; fi
done
psqlv "alter role authenticator reset pgrst.db_tx_end;" >/dev/null
psqlv "notify pgrst, 'reload config';" >/dev/null; sleep 3
is F1r "$(psqlv "select count(*) from pg_db_role_setting s join pg_roles r on r.oid=s.setrole where r.rolname='authenticator' and array_to_string(s.setconfig,',') like '%tx_end%';")" "0" "the local db-tx-end override is restored"

# F2: the GET route
clearbudget
G=$(curl -s -o /tmp/b37get -w '%{http_code}' -X GET "$API/rest/v1/rpc/search_account_directory?q=al" -H "apikey: $AK" -H "Authorization: Bearer $ST")
GR=$(jq 'if type=="array" then length else -1 end' </tmp/b37get 2>/dev/null)
if [ "$GR" -le 0 ]; then ok F2 "the GET route returns no directory rows (HTTP $G)"; else bad F2 "GET returned $GR rows"; fi
is F2b "$(psqlv "select coalesce(sum(burst_count),0) from public.directory_search_budget;")" "0" "and it is not an unmetered data route"

# F3: direct table access as a client role
for op in "select count(*) from public.directory_search_budget" \
          "insert into public.directory_search_budget (user_id,burst_started_at,burst_count,window_started_at,window_count) values ('$S',now(),0,now(),0)" \
          "update public.directory_search_budget set burst_count = 0" \
          "delete from public.directory_search_budget"; do
  R=$(psqltry "begin; set local role authenticated; $op; rollback;" | tr '\n' ' ' | head -c 200)
  case "$R" in *"permission denied"*) ok F3 "authenticated cannot: ${op:0:38}…" ;;
                                   *) bad F3 "authenticated COULD: ${op:0:38}… -> $R" ;; esac
done
# CLIENT roles only. The owner (postgres) necessarily holds the table's seven
# privileges -- that is how the SECURITY DEFINER function reaches it at all --
# and counting those would assert something no correct implementation can satisfy.
is F3b "$(psqlv "select count(*) from information_schema.role_table_grants where table_name='directory_search_budget' and grantee in ('anon','authenticated','service_role','PUBLIC');")" "0" "no CLIENT role holds any privilege on the counter table"
is F3c "$(psqlv "select relrowsecurity::text from pg_class where oid='public.directory_search_budget'::regclass;")" "true" "RLS is enabled on the counter table"
is F3d "$(psqlv "select count(*) from pg_policies where tablename='directory_search_budget';")" "0" "and it carries no policy"

# F4: no other executable route
is F4 "$(psqlv "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%search_account_directory%';")" "1" "exactly one search function exists"
is F4b "$(psqlv "select has_function_privilege('anon','public.search_account_directory(text)','execute')::text;")" "false" "anon cannot execute it"
is F4c "$(psqlv "select has_function_privilege('service_role','public.search_account_directory(text)','execute')::text;")" "false" "service_role cannot execute it"
is F4d "$(psqlv "select has_function_privilege('authenticated','public.search_account_directory(text)','execute')::text;")" "true" "authenticated can"

# F5: anon over HTTP
A=$(curl -s -o /tmp/b37anon -w '%{http_code}' -X POST "$API/rest/v1/rpc/search_account_directory" \
    -H "apikey: $AK" -H "Content-Type: application/json" -d '{"q":"al"}')
if [ "$A" != "200" ]; then ok F5 "an anonymous caller is refused (HTTP $A)"
else bad F5 "anon got HTTP 200: $(head -c 120 /tmp/b37anon)"; fi

# F6: a re-issued token for the same identity does not reset the allowance
clearbudget
for i in $(seq 1 10); do srch x '"al"' >/dev/null; done
ST2=$(tokenfor b37-searcher)
is F6 "$(srch_as "$ST2" '"al"')" "429" "a freshly issued token for the same identity is still refused"
echo

# ====================================================== G — preserved behaviour
echo "G — discovery, entitlement, self-exclusion and attribution are intact"
clearbudget
q x '"hidden"'; is G1 "$(rows)" "0" "a member with discovery OFF is not returned"
q x '"Hidden Person"'; is G1b "$(rows)" "0" "nor by their exact display name"

# BEHAVIOURAL entitlement, not a string search of the definition. Enforcement is
# switched on for this group only, with membership rows giving the caller a live
# entitlement, so the gate admits the caller and D-U6-1 can actually be observed
# deciding the SUBJECT. Restored immediately afterwards.
memb() {  # $1 user, $2 renewal offset
  psqlv "insert into public.membership (user_id, environment, original_transaction_id, product_id,
           apple_status, renewal_date, is_in_billing_retry, renewal_info_signed_date,
           binding_method, bound_at)
         values ('$1','Production','otid-$1','etudes.connected.monthly',1, now() + interval '$2',
                 false, now(), 'purchase', now())
         on conflict (user_id, environment) do update set renewal_date = excluded.renewal_date;" >/dev/null 2>&1
}
memb "$S"  "30 days"     # the caller is entitled
memb "$U1" "30 days"     # Alice is entitled
memb "$U2" "-1 days"     # Bob has lapsed
psqlv "update public.membership_control set enforcement_enabled = true;" >/dev/null
clearbudget
q x '"al"';    is G2  "$(names)" "Alice Alpha" "under live enforcement an ENTITLED subject is discoverable"
q x '"bravo"'; is G2b "$(rows)" "0" "and a LAPSED subject is not (D-U6-1, observed)"
G2CALLER=$(srch_as "$OT" '"al"')
G2CR=$(rows)
if [ "$G2CR" -le 0 ]; then ok G2c "an UNENTITLED caller gets nothing under live enforcement (HTTP $G2CALLER)"
else bad G2c "an unentitled caller received $G2CR rows"; fi
q x '"hidden"'; is G2d "$(rows)" "0" "the discovery opt-out still holds under live enforcement"
psqlv "update public.membership_control set enforcement_enabled = false;" >/dev/null
psqlv "delete from public.membership;" >/dev/null
is G2e "$(psqlv "select enforcement_enabled::text from public.membership_control;")" "false" "enforcement is restored to off"

clearbudget
q x '"searcher"'; is G3 "$(rows)" "0" "the caller never returns themselves"
DEF=$(psqlv "select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='search_account_directory';")
case "$DEF" in *"v_uid is null"*) ok G3b "the anon guard survives (self-exclusion is NOT a security control)" ;;
                               *) bad G3b "the anon guard is gone" ;; esac
case "$DEF" in *"limit 20"*) ok G5 "LIMIT 20 is unchanged" ;; *) bad G5 "LIMIT 20 is gone" ;; esac
case "$DEF" in *"order by"*"ad.account_id nulls last"*) ok G5b "the ordering is unchanged" ;;
                                                     *) bad G5b "the ordering changed" ;; esac

# by-ID attribution is untouched and still ignores the discovery opt-out.
BY=$(curl -s -X POST "$API/rest/v1/rpc/get_account_directory_by_user_ids" -H "apikey: $AK" \
     -H "Authorization: Bearer $ST" -H 'Content-Type: application/json' -d "{\"user_ids\":[\"$U6\"]}")
is G4 "$(echo "$BY" | jq -r 'if type=="array" then (map(.display_name)|join(",")) else "ERR" end')" "Hidden Person" \
      "G10/C-58: by-ID attribution still resolves an opted-out member"
# Byte comparison against the committed production capture, not a count of one.
psqlv "select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_account_directory_by_user_ids';" > /tmp/b37_byid_local
python3 - <<'PYX' > /tmp/b37_byid_base
import json
for f in json.load(open('supabase/schema/functions.json')):
    if f.get('proname') == 'get_account_directory_by_user_ids':
        print(f['definition'].rstrip())
PYX
# psql -tA appends ONE trailing newline the JSON capture does not carry. Only
# that is normalised: an earlier revision stripped trailing whitespace from
# EVERY line while claiming byte identity, which would have hidden a real
# whitespace change inside the body.
if diff -q <(printf '%s' "$(cat /tmp/b37_byid_base)") \
           <(printf '%s' "$(cat /tmp/b37_byid_local)") >/dev/null; then
  ok G4b "the by-ID function is byte-identical to the committed capture"
else bad G4b "the by-ID function DIFFERS from the committed capture"; fi
echo

printf "  %s\n" "-----------------------------------------------"
printf "  PASS %d   FAIL %d\n\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
