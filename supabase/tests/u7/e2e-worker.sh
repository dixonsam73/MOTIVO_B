#!/usr/bin/env bash
#
# U7c end-to-end — the REAL membership_cleanup_v1, the REAL database, real
# storage objects, a programmable Apple. LOCAL DISPOSABLE STACK ONLY.
#
#   supabase db reset --local && ./supabase/tests/u7/e2e-worker.sh
#
# THE ANCHOR IS REPLACED IN A COPY, NOT SWITCHED IN THE SOURCE — same discipline
# as U4's and U5's e2e, and for the same reason: a production-reachable switch on
# the one control that makes verification meaningful is exactly what must not
# exist.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e

HERE="supabase/tests/u7"
WORK="$HERE/.work/e2e"
PORT="${U7_E2E_PORT:-9181}"; STUB_PORT="${U7_STUB_PORT:-9182}"
NAME="u7_e2e_$$"; STUB="u7_stub_$$"
: "${DOCKER_HOST:=unix://$HOME/.colima/default/docker.sock}"; export DOCKER_HOST

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^public.ecr.aws/supabase/edge-runtime:' | head -1)"
NET="$(docker network ls --format '{{.Name}}' | grep '^supabase_network_' | head -1)"
KONG="$(docker ps --format '{{.Names}}' | grep '^supabase_kong_' | head -1)"
[ -n "$IMAGE" ] && [ -n "$NET" ] && [ -n "$KONG" ] || { echo "u7: local stack not running" >&2; exit 1; }

python3 supabase/tests/u4a/make-fixtures.py >/dev/null || exit 1
FIX="supabase/tests/u4a/.work/fixtures.json"

rm -rf "$WORK"; mkdir -p "$WORK/fn" "$WORK/_shared" "$WORK/stub"
cp supabase/functions/membership_cleanup_v1/index.ts "$WORK/fn/index.ts"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/fn/"
cp -R supabase/functions/_shared/appstore "$WORK/_shared/"
cp "$HERE/applestub.ts" "$WORK/stub/index.ts"
cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/stub/"
cp "$FIX" "$WORK/fixtures.json"
python3 - "$FIX" "$WORK/_shared/appstore/apple_root_ca_g3.ts" <<'PY'
import json,sys,re,pathlib
fx=json.load(open(sys.argv[1])); p=pathlib.Path(sys.argv[2]); t=p.read_text()
t=re.sub(r'export const APPLE_ROOT_CA_G3_B64 =.*?;',
         'export const APPLE_ROOT_CA_G3_B64 = "%s"; // U7 E2E: TEST CA, not Apple' % fx['test_root_der_b64'],
         t, flags=re.S)
p.write_text(t)
PY

cleanup() { docker rm -f "$NAME" "$STUB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$STUB" --network "$NET" -p "$STUB_PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  "$IMAGE" start --main-service /probe/stub --port 9000 >/dev/null || exit 1
docker run -d --name "$NAME" --network "$NET" -p "$PORT:9000" -v "$PWD/$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "SERVICE_ROLE_KEY=$SR" -e "ANON_KEY=$AK" \
  -e "APPLE_API_BASE_URL_SANDBOX=http://$STUB:9000" \
  -e "APPLE_API_BASE_URL_PRODUCTION=http://$STUB:9000" \
  -e "APPLE_IAP_KEY_ID=TESTKEYID" -e "APPLE_IAP_ISSUER_ID=test-issuer" \
  -e "APPLE_IAP_BUNDLE_ID=com.sdsongs.etudes" \
  -e "APPLE_IAP_P8_B64=$(python3 -c "import json;print(json.load(open('$FIX'))['p8_b64'])")" \
  "$IMAGE" start --main-service /probe/fn --port 9000 >/dev/null || exit 1

for _ in $(seq 1 40); do sleep 2; curl -s --max-time 5 "http://127.0.0.1:$STUB_PORT/__calls" >/dev/null 2>&1 && break; done
plan()  { curl -s -X POST "http://127.0.0.1:$STUB_PORT/__control" -H 'content-type: application/json' -d "$1" >/dev/null; }
calls() { curl -s "http://127.0.0.1:$STUB_PORT/__calls"; }
run()   { curl -s --max-time 180 -X POST "http://127.0.0.1:$PORT/" -H "Authorization: Bearer $SR" -H 'content-type: application/json' -d "$1"; }

echo; echo "U7c end-to-end — the real worker, real storage, programmable Apple"; echo

reset_fixture() { supabase db reset --local >/dev/null 2>&1; ./supabase/tests/u7/fixture.sh >/dev/null; source supabase/tests/u7/.ids; }
objs()   { psq "select count(*) from storage.objects where bucket_id='$1' and name like '$2%';"; }
objgone(){ psq "select count(*) from storage.objects where bucket_id='attachments' and name='$1';"; }

reset_fixture

# ---- non-vacuity: every rule below has real work or a real row to spare
is U7-fix1 "$(psq "select count(*) from posts where owner_user_id='$S';")" "1" "S owns a post"
is U7-fix2 "$(psq "select count(*) from connected_attachments where sender_user_id='$S';")" "5" "S sent 5 rows across 3 assets"
is U7-fix3 "$(objs attachments "users/$S/")" "4" "S has 4 storage objects"
is U7-fix4 "$(psq "select count(*) from post_comments where author_user_id='$S';")" "1" "S authored a comment elsewhere"
is U7-fix5 "$(psq "select public.connected_member('$P');")" "t" "P is genuinely Production-entitled"

# ========================================================== C — DRY RUN
plan '{"*":{"ri":"attest_ri_lapsed","status":2}}'
D=$(run '{"mode":"dry_run"}')
is C-1  "$(printf '%s' "$D" | grep -c "\"user_id\":\"$S\"")" "1" "preview returns the eligible subject"
is C-2  "$(psq "select count(*) from public.membership where cleanup_claimed_at is not null;")" "0" "C-2 dry run acquired NO lease, anywhere"
is C-4a "$(psq "select count(*) from posts where owner_user_id='$S';")" "1" "dry run deleted no post"
is C-4b "$(psq "select count(*) from follows where follower_user_id='$S' or followed_user_id='$S';")" "4" "dry run deleted no follow"
is C-4c "$(objs attachments "users/$S/")" "4" "dry run deleted no object"
is C-5  "$(psq "select count(*) from public.membership where user_id='$S' and pending_cleanup_at is not null;")" "1" "dry run wrote no membership state"
is C-6  "$(psq "select provolatile from pg_proc where proname='membership_cleanup_eligible_v1';")" "s" "C-6 eligibility fn is STABLE — structurally cannot claim"
is C-7  "$(printf '%s' "$D" | grep -c 'would_delete_objects')" "1" "dry run reports the blast radius"
is C-8  "$(calls | grep -c '"otid"')" "0" "C-8 dry run made ZERO Apple requests"
is C-3  "$(printf '%s' "$(run '{"mode":"dry_run"}')" | grep -c "\"user_id\":\"$S\"")" "1" "C-3 a second preview STILL finds it — the P4->P5 trap does not exist"
is C-9  "$(psq "select count(*) from public.membership_cleanup_eligible_v1(25);")" "$(psq "select count(*) from public.membership_cleanup_eligible_v1(25);")" "preview is repeatable on quiesced state"

# ================================================== D — AUTHORITY: failures
for CASE in "http:D-1:{\"http\":503}" "garbage:D-3:{\"garbage\":true}" "empty:D-3b:{\"empty\":true}"; do
  LBL=$(echo "$CASE" | cut -d: -f2); PLAN=$(echo "$CASE" | cut -d: -f3-)
  reset_fixture; plan "{\"*\":$PLAN}"
  R=$(run "{\"mode\":\"execute\",\"user_id\":\"$S\"}")
  is "$LBL"   "$(printf '%s' "$R" | grep -c '"decision":"abort"')" "1" "Apple unreadable -> abort"
  is "$LBL-n" "$(psq "select count(*) from posts where owner_user_id='$S';")" "1" "...and NOTHING deleted"
  is "$LBL-c" "$(psq "select count(*) from public.membership where user_id='$S' and cleanup_completed_at is not null;")" "0" "...no completion marker (F-8)"
done

# ---------------- D-4: Apple says ENTITLED -> self-eliminates (QA C5)
reset_fixture; plan '{"*":{"ri":"attest_ri","status":1}}'
R=$(run "{\"mode\":\"execute\",\"user_id\":\"$S\"}")
is D-4  "$(printf '%s' "$R" | grep -c '"decision":"refused"')" "1" "D-4 QA-C5 entitled at the fresh read -> REFUSED"
is D-4b "$(psq "select count(*) from posts where owner_user_id='$S';")" "1" "...nothing deleted"
is D-4c "$(psq "select coalesce(pending_cleanup_at::text,'CLEARED') from public.membership where user_id='$S';")" "CLEARED" "...and the schedule was CANCELLED by reconciliation"

# ---------------- D-6: due Sandbox + LIVE Production -> never cleaned
reset_fixture
plan '{"otid-P-sandbox":{"ri":"attest_ri_lapsed","status":2},"otid-P-prod":{"ri":"attest_ri","status":1}}'
R=$(run "{\"mode\":\"execute\",\"user_id\":\"$P\"}")
is D-6  "$(printf '%s' "$R" | grep -c '"decision":"refused"')" "1" "D-6 lapsed Sandbox + LIVE Production -> REFUSED"
is D-6b "$(printf '%s' "$R" | grep -c 'connected_member() is true')" "1" "...on the identity-level Production predicate"
is D-7  "$(calls | python3 -c "import json,sys;print(len({c['otid'] for c in json.load(sys.stdin)['calls']}))")" "2" "D-7 BOTH environments were refreshed before authority"

# ---------------- D-8: one environment fails -> whole identity aborts
reset_fixture
plan '{"otid-P-sandbox":{"ri":"attest_ri_lapsed","status":2},"otid-P-prod":{"http":503}}'
R=$(run "{\"mode\":\"execute\",\"user_id\":\"$P\"}")
is D-8 "$(printf '%s' "$R" | grep -c '"decision":"abort"')" "1" "D-8 one environment unreadable -> the WHOLE identity aborts"

# ============================================ D-5 / E — the retention matrix
reset_fixture; plan '{"*":{"ri":"attest_ri_lapsed","status":2}}'
R=$(run "{\"mode\":\"execute\",\"user_id\":\"$S\"}")
is D-5  "$(printf '%s' "$R" | grep -c '"decision":"cleaned"')" "1" "D-5 not entitled + connected_member false -> CLEANED"

is E-1  "$(psq "select count(*) from posts where owner_user_id='$S';")" "0" "own posts removed"
is E-2  "$(objgone "users/$S/$PS1/att1.pdf")" "0" "own post-attachment object removed"
is E-3  "$(psq "select count(*) from connected_attachments where recipient_user_id='$S';")" "0" "received references removed"
is E-4  "$(psq "select count(*) from post_shares where recipient_user_id='$S';")" "0" "received shares removed"
is E-5  "$(psq "select count(*) from post_comment_views where viewer_user_id='$S';")" "0" "own comment-views removed"
is E-6  "$(psq "select count(*) from follows where follower_user_id='$S' or followed_user_id='$S';")" "0" "follows removed BOTH directions"
is E-7  "$(objgone "users/$S/connected/$Z.pdf")" "0" "E-7 fully-soft-deleted asset: object removed"
is E-7b "$(psq "select count(*) from connected_attachments where asset_id='$Z';")" "0" "...and its row removed"
is E-8  "$(objgone "users/$S/connected/$X.pdf")" "1" "E-8 LIVE recipient reference: object RETAINED"
is E-8b "$(psq "select count(*) from connected_attachments where asset_id='$X';")" "2" "...and BOTH rows retained"
is E-9  "$(objgone "users/$S/connected/$Y.pdf")" "1" "E-9 one live + one soft-deleted: object RETAINED"
is E-9b "$(psq "select count(*) from connected_attachments where asset_id='$Y';")" "2" "...and its rows retained"
is E-10 "$(psq "select count(*) from post_comments where author_user_id='$S' and owner_user_id='$B';")" "1" "E-10 comment on ANOTHER member's surviving post RETAINED"
is E-11 "$(psq "select count(*) from post_comments where author_user_id='$B' and recipient_user_id='$S';")" "1" "E-11 B-19 comment merely ADDRESSED to S retained"
is E-12 "$(psq "select display_name from account_directory where user_id='$S';")" "Sierra" "E-12 directory row RETAINED, display_name intact"
is E-13 "$(psq "select coalesce(avatar_key,'NULL') from account_directory where user_id='$S';")" "NULL" "avatar_key cleared"
is E-13b "$(objs avatars "users/$S/")" "0" "...and the avatar object removed"
is E-14 "$(psq "select count(*) from auth.users where id='$S';")" "1" "E-14 auth.users RETAINED"
is E-15 "$(psq "select count(*) from public.membership where user_id='$S';")" "1" "E-15 membership RETAINED (QA A24)"
is E-15b "$(psq "select count(*) from public.membership_binding where user_id='$S';")" "1" "...and membership_binding RETAINED"
is E-17 "$(objs attachments "users/$S/")" "2" "E-17 NO unconditional prefix sweep: 2 retained objects survive inside S's own prefix"

# ---- E-16 third-party blast radius
is E-16a "$(psq "select count(*) from posts where owner_user_id='$B';")" "1" "B's post untouched"
is E-16b "$(psq "select count(*) from follows where follower_user_id='$B' and followed_user_id='$C';")" "1" "B->C follow untouched"
is E-16c "$(objs attachments "users/$B/")" "1" "B's object untouched"
is E-16d "$(objs avatars "users/$B/")" "1" "B's avatar untouched"
is E-16e "$(psq "select count(*) from post_comment_views where viewer_user_id='$B';")" "1" "B's comment-view untouched"
is E-16f "$(psq "select coalesce(avatar_key,'NULL') from account_directory where user_id='$B';")" "users/$B/avatar.jpg" "B's avatar pointer untouched"
is E-16g "$(psq "select count(*) from auth.users;")" "4" "no identity removed"

# ---- completion + idempotency
is F-3a "$(psq "select count(*) from public.membership where user_id='$S' and cleanup_completed_at is not null;")" "1" "completion marker set"
is F-3b "$(psq "select coalesce(pending_cleanup_at::text,'CLEARED') from public.membership where user_id='$S';")" "CLEARED" "schedule cleared"
R2=$(run "{\"mode\":\"execute\",\"user_id\":\"$S\"}")
is F-3  "$(printf '%s' "$R2" | grep -c "\"user_id\":\"$S\"")" "0" "F-3 second execute finds nothing — no double cleanup"
is F-3c "$(objs attachments "users/$S/")" "2" "...and the retained objects are still there"

# ---- F-6 / F-7 lease
reset_fixture
psq "update public.membership set cleanup_claimed_at = now() where user_id='$S';" >/dev/null
is F-7 "$(psq "select count(*) from public.membership_cleanup_eligible_v1(25) where user_id='$S';")" "0" "F-7 a held lease excludes the identity"
psq "update public.membership set cleanup_claimed_at = now() - interval '2 hours' where user_id='$S';" >/dev/null
is F-6 "$(psq "select count(*) from public.membership_cleanup_eligible_v1(25) where user_id='$S';")" "1" "F-6 an EXPIRED lease recovers a crashed run"

# ================================================================ G — structural
W=supabase/functions/membership_cleanup_v1/index.ts
# SOURCE-TEXT ASSERTIONS MUST TARGET CODE, NOT PROSE. G-1 first FAILED against a
# correct file because the header says "There is no auth.admin.deleteUser call in
# this file" — the comment explaining the rule defeated the check for the rule.
# U5c/U5d hit this twice; a well-commented file is exactly the one most likely to
# defeat a naive grep. Comments are stripped before every check below.
code() { grep -vE '^[[:space:]]*(//|\*|/\*)' "$W"; }
is G-1 "$(code | grep -c 'deleteUser')" "0" "G-1 the worker CANNOT delete an auth user"
is G-2 "$(code | grep -c 'from("post_comments")')" "0" "G-2 B-19: the worker never deletes post_comments at all"
is G-3 "$(code | grep -c 'from("account_directory").delete')" "0" "G-3 never deletes the directory row"
is G-4 "$(code | grep -cE 'from\("membership(_binding)?"\)\.delete')" "0" "G-4 never deletes membership or binding"
is G-4b "$(code | grep -c 'retainedPaths.has')" "1" "G-4b the sweep SUBTRACTS retained paths — not a blanket prefix remove"
is G-4c "$(code | grep -c 'removeVerified')" "3" "G-4c every object removal goes through the re-listing verifier"
is G-4d "$(code | grep -c 'membership_cleanup_authorised_v1')" "1" "G-4d authority comes from the gate, not composed locally"
is G-5 "$(psq "select count(*) from pg_extension where extname='pg_cron';")" "0" "G-5 still no scheduler"

echo; echo "  U7c e2e: $PASS passed, $FAIL failed"; echo
[ "$FAIL" -eq 0 ]
