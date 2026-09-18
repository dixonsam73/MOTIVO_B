#!/usr/bin/env bash
#
# P6 single-object delete — focused end-to-end on the LOCAL stack.
#
#   EVID=<new or empty evidence dir> ./supabase/tests/p6-single-delete/e2e.sh
#
# NO DATABASE RESET, deliberately (unlike u7/e2e-worker.sh). Every scenario builds
# its own fixture on FRESH random synthetic uids and tears exactly that down again;
# the one test-owned trigger is dropped on every exit path. The run ends by
# comparing structure, captured counts and the storage byte digest with the
# baseline it took first. The functions run from COPIES in $WORK, served by a
# disposable edge-runtime container; the source tree is not modified.
#
# What this can show: the functions now delete through the single-object route,
# fail and stop at the right stage, and leave nothing listed (and, on this local
# FILE backend, no bytes) for what they deleted. What it cannot show: hosted S3
# behaviour, removal of historical orphans, or storage-api's own version clean-up.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e
die() { echo "p6sd: $*" >&2; exit 2; }
: "${EVID:?EVID must be set}"
# EVIDENCE: a new or empty directory only; this run never deletes it.
if [ -e "$EVID" ] && [ -n "$(ls -A "$EVID" 2>/dev/null)" ]; then die "EVID exists and is not empty: $EVID"; fi
mkdir -p "$EVID" || die "cannot create EVID"

# LOCAL WIRING, UNIQUELY. u4/lib.sh has already chosen the ONE supabase_db_*
# container publishing the DB port from `supabase status` (localhost-guarded);
# every other container is derived from ITS project suffix and must exist exactly.
SUFFIX="${DB#supabase_db_}"
[ -n "$SUFFIX" ] && [ "$SUFFIX" != "$DB" ] || die "cannot derive the project suffix from $DB"
ST="supabase_storage_$SUFFIX"; KONG="supabase_kong_$SUFFIX"; NET="supabase_network_$SUFFIX"; EDGE="supabase_edge_runtime_$SUFFIX"
for c in "$ST" "$KONG" "$EDGE"; do
  [ "$(docker ps --filter "name=^${c}$" --format '{{.Names}}' | wc -l | tr -d ' ')" = "1" ] || die "expected exactly one running $c"
done
[ "$(docker network ls --filter "name=^${NET}$" --format '{{.Name}}' | wc -l | tr -d ' ')" = "1" ] || die "expected exactly one network $NET"
docker inspect "$ST" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q "@$DB:5432/" || die "$ST does not point at $DB"
IMAGE="$(docker inspect "$EDGE" --format '{{.Config.Image}}')"; [ -n "$IMAGE" ] || die "no edge-runtime image"

# PRECONDITIONS: nothing this run owns may already exist.
[ "$(psq "select count(*) from pg_namespace where nspname='p6sd';")" = "0" ] || die "schema p6sd already exists — refusing to run (it would be dropped)"
[ "$(psq "select count(*) from pg_trigger where tgname='p6sd_refuse';")" = "0" ] || die "trigger p6sd_refuse already exists — refusing to run"
[ -z "$(docker ps -a --format '{{.Names}}' | grep '^p6sd_')" ] || die "p6sd_* containers already exist — refusing to run"

# WORK: a directory THIS RUN creates; it is the only thing ever removed recursively.
# Under $HOME because Colima shares only the home directory with its VM.
mkdir -p "$HOME/.cache" || die "cannot create ~/.cache"
WORK="$(mktemp -d "$HOME/.cache/p6sd-run.XXXXXX")" || die "mktemp failed"
case "$WORK" in "$HOME"/.cache/p6sd-run.*) ;; *) die "unexpected WORK path $WORK";; esac
CK="p6sd-test-invoke-key-0123456789abcdef"
PORT_C=9191; PORT_D=9192; PORT_S=9193
NC="p6sd_cleanup_$$"; ND="p6sd_delete_$$"; NS="p6sd_stub_$$"

PASS=0; FAIL=0
ok()  { printf "  PASS  %-8s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  FAIL  %-8s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

# ---------------------------------------------------------------- baseline
baseline() {  # $1 = label
  ./supabase/capture-schema.sh --local "$EVID/$1-struct" > "$EVID/$1-capture.log" 2>&1 || die "baseline $1: capture failed"
  [ "$(ls "$EVID/$1-struct"/*.json 2>/dev/null | wc -l | tr -d ' ')" = "10" ] || die "baseline $1: expected 10 structural files"
  psq "select 'buckets', string_agg(id||':'||public::text||':'||coalesce(file_size_limit::text,''), ',' order by id) from storage.buckets;
       select 'objects', bucket_id, count(*) from storage.objects group by bucket_id order by bucket_id;
       select 'auth.users', count(*) from auth.users;
       select 'objects triggers', string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid='storage.objects'::regclass and not tgisinternal;
       select 'p6sd schema', count(*) from pg_namespace where nspname='p6sd';" > "$EVID/$1-data.txt"
  docker exec "$ST" sh -c 'cd /mnt && find . -type f | sort | xargs -r sha256sum' | sha256sum > "$EVID/$1-bytes.txt"
  docker exec "$ST" sh -c 'cd /mnt && find . -type f | wc -l' >> "$EVID/$1-bytes.txt"
  grep -q '^auth.users|' "$EVID/$1-data.txt" || die "baseline $1: data capture failed"
}
baseline before

# ---------------------------------------------------------------- copies + containers
mkdir -p "$WORK/cleanup" "$WORK/delete" "$WORK/_shared" "$WORK/stub"
cp supabase/functions/membership_cleanup_v1/index.ts "$WORK/cleanup/index.ts"
cp supabase/functions/delete_account_v1/index.ts "$WORK/delete/index.ts"
for d in cleanup delete stub; do cp supabase/functions/deno.json supabase/functions/deno.lock "$WORK/$d/"; done
cp -R supabase/functions/_shared/appstore supabase/functions/_shared/storage "$WORK/_shared/"
cp supabase/tests/u7/applestub.ts "$WORK/stub/index.ts"
FIX="supabase/tests/u4a/.work/fixtures.json"; cp "$FIX" "$WORK/fixtures.json"
python3 - "$FIX" "$WORK/_shared/appstore/apple_root_ca_g3.ts" <<'PY'
import json,sys,re,pathlib
fx=json.load(open(sys.argv[1])); p=pathlib.Path(sys.argv[2]); t=p.read_text()
t=re.sub(r'export const APPLE_ROOT_CA_G3_B64 =.*?;', 'export const APPLE_ROOT_CA_G3_B64 = "%s"; // P6SD E2E: TEST CA, not Apple' % fx['test_root_der_b64'], t, flags=re.S)
p.write_text(t)
PY

ALL_UIDS_FILE="$EVID/created-uids.txt"; : > "$ALL_UIDS_FILE"
P6SD_CREATED=0
teardown_all() {
  # Only artifacts THIS run created: the trigger/schema (absent at start, asserted),
  # this run's uids, its containers, and its own mktemp directory.
  [ "$P6SD_CREATED" = "1" ] && psq "drop trigger if exists p6sd_refuse on storage.objects; drop schema if exists p6sd cascade;" >/dev/null
  # Every synthetic uid this run created, whatever state it was left in.
  [ -s "$ALL_UIDS_FILE" ] && destroy $(sort -u "$ALL_UIDS_FILE")
  docker logs "$NC" > "$EVID/logs-cleanup.txt" 2>&1; docker logs "$ND" > "$EVID/logs-delete.txt" 2>&1
  docker rm -f "$NC" "$ND" "$NS" >/dev/null 2>&1
  case "$WORK" in "$HOME"/.cache/p6sd-run.*) rm -rf -- "$WORK" ;; esac
}
trap teardown_all EXIT

docker run -d --name "$NS" --network "$NET" -p "$PORT_S:9000" -v "$WORK:/probe:ro" "$IMAGE" start --main-service /probe/stub --port 9000 >/dev/null || exit 2
docker run -d --name "$NC" --network "$NET" -p "$PORT_C:9000" -v "$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "SERVICE_ROLE_KEY=$SR" -e "CLEANUP_INVOKE_KEY=$CK" \
  -e "APPLE_API_BASE_URL_SANDBOX=http://$NS:9000" -e "APPLE_API_BASE_URL_PRODUCTION=http://$NS:9000" \
  -e "APPLE_IAP_KEY_ID=TESTKEYID" -e "APPLE_IAP_ISSUER_ID=test-issuer" -e "APPLE_IAP_BUNDLE_ID=com.sdsongs.etudes" \
  -e "APPLE_IAP_P8_B64=$(python3 -c "import json;print(json.load(open('$FIX'))['p8_b64'])")" \
  "$IMAGE" start --main-service /probe/cleanup --port 9000 >/dev/null || exit 2
docker run -d --name "$ND" --network "$NET" -p "$PORT_D:9000" -v "$WORK:/probe:ro" \
  -e "SUPABASE_URL=http://$KONG:8000" -e "SUPABASE_ANON_KEY=$AK" -e "SERVICE_ROLE_KEY=$SR" \
  "$IMAGE" start --main-service /probe/delete --port 9000 >/dev/null || exit 2
for _ in $(seq 1 40); do sleep 2; curl -s --max-time 3 "http://127.0.0.1:$PORT_S/__calls" >/dev/null 2>&1 && break; done
sleep 4
plan()  { curl -s -X POST "http://127.0.0.1:$PORT_S/__control" -H 'content-type: application/json' -d "$1" >/dev/null; }
runC()  { curl -s --max-time 170 -X POST "http://127.0.0.1:$PORT_C/" -H "Authorization: Bearer $CK" -H 'content-type: application/json' -d "$1"; }
runD()  { curl -s --max-time 170 -X POST "http://127.0.0.1:$PORT_D/" -H "Authorization: Bearer $1"; }

# ---------------------------------------------------------------- fixture helpers
newid() { python3 -c 'import uuid;print(uuid.uuid4())'; }
sq()    { psq "$1" >/dev/null; }
objs()  { psq "select count(*) from storage.objects where bucket_id='$1' and name like '$2%';"; }
has()   { psq "select count(*) from storage.objects where bucket_id='$1' and name='$2';"; }
bytes() { docker exec "$ST" sh -c "[ -e '/mnt/stub/stub/$1/$2' ] && echo present || echo gone"; }

refuse_delete_of() {  # bucket name — a test-owned trigger refusing ONE object's delete
  P6SD_CREATED=1
  psq "create schema if not exists p6sd;
       create or replace function p6sd.refuse() returns trigger language plpgsql as \$f\$
       begin raise exception 'p6sd refused delete of %', old.name; end \$f\$;
       drop trigger if exists p6sd_refuse on storage.objects;
       create trigger p6sd_refuse before delete on storage.objects for each row
         when (old.bucket_id = '$1' and old.name = '$2') execute function p6sd.refuse();" >/dev/null
}
allow_deletes() { [ "$P6SD_CREATED" = "1" ] && psq "drop trigger if exists p6sd_refuse on storage.objects;" >/dev/null; return 0; }

# A HANGING STORAGE LIST, for real: hold storage.objects under an ACCESS EXCLUSIVE
# lock so storage-api's list query waits. Local, exclusive stack only; released
# when the holder's sleep ends. Every function-side list is bounded at 15 s.
hold_objects_lock() {  # $1 seconds; runs in the background, prints nothing
  docker exec -i "$DB" psql -U postgres -d postgres -q -c "begin; lock table storage.objects in access exclusive mode; select pg_sleep($1); commit;" >/dev/null 2>&1 &
  HOLD_PID=$!
  sleep 1
}

# A subject S with a post + attachment, a DOOMED connected asset (only ref soft-
# deleted), a RETAINED one (live recipient), a received ref from B, follows,
# directory row with avatar; and B with its own object and avatar (the control).
build() {  # $1=S $2=B $3=with_membership(0/1)
  local S=$1 B=$2
  printf '%s\n%s\n' "$S" "$B" >> "$ALL_UIDS_FILE"
  for u in "$S" "$B"; do
    psq "select 1 from auth.users where id='$u';" | grep -q 1 || sq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at)
      values ('$u','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p6sd-$u@local.invalid',now(),now());"
    # CP-1: a directory row needs an established band first.
    sq "insert into public.account_privacy (user_id, age_band, lookup_enabled, lookup_set_under_band, follow_requests_enabled, follow_requests_set_under_band)
        values ('$u','band_18_plus',true,'band_18_plus',true,'band_18_plus') on conflict do nothing;"
    sq "insert into account_directory (user_id, account_id, display_name, lookup_enabled, follow_requests_enabled)
        values ('$u','p6'||substr(replace('$u','-',''),1,16),'P6 $u',true,true) on conflict do nothing;"
  done
  if [ "$3" = "1" ]; then
    sq "insert into public.membership_binding (user_id) values ('$S') on conflict do nothing;"
    sq "insert into public.membership (user_id, environment, original_transaction_id, product_id, apple_status,
          renewal_date, renewal_info_signed_date, binding_method, bound_at, entitlement_ended_at, pending_cleanup_at)
        values ('$S','Sandbox','p6sd-otid-$S','etudes.connected.monthly',2, now() - interval '90 days',
          now() - interval '70 days','purchase', now() - interval '400 days', now() - interval '90 days', now() - interval '30 days');"
  fi
  sq "insert into follows (follower_user_id, followed_user_id, status) values ('$S','$B','approved'),('$B','$S','approved');"
  PS=$(scalar "insert into posts (owner_user_id,is_public,title,attachments) values ('$S',true,'p6sd post','[]'::jsonb) returning id;")
  sq "update posts set attachments='[{\"bucket\":\"attachments\",\"path\":\"users/$S/$PS/att1.pdf\"}]'::jsonb where id='$PS';"
  DOOM=$(newid); KEEP=$(newid); RECV=$(newid)
  putobj attachments "users/$S/$PS/att1.pdf" "post-att" >/dev/null
  putobj attachments "users/$S/connected/$DOOM.pdf" "doomed" >/dev/null
  putobj attachments "users/$S/connected/$KEEP.pdf" "kept" >/dev/null
  putobj attachments "users/$B/connected/$RECV.pdf" "b-to-s" >/dev/null
  putobj avatars "users/$S/avatar.jpg" "s-avatar" image/jpeg >/dev/null
  putobj avatars "users/$B/avatar.jpg" "b-avatar" image/jpeg >/dev/null
  sq "update account_directory set avatar_key='users/$S/avatar.jpg' where user_id='$S';"
  sq "update account_directory set avatar_key='users/$B/avatar.jpg' where user_id='$B';"
  ca() { sq "insert into connected_attachments (asset_id,sender_user_id,recipient_user_id,storage_path,filename,byte_count,deleted_at)
             values ('$1','$2','$3','users/$2/connected/$1.pdf','f.pdf',12,$4);"; }
  ca "$DOOM" "$S" "$B" "now()"
  ca "$KEEP" "$S" "$B" "null"
  ca "$RECV" "$B" "$S" "null"
}

destroy() {  # explicit teardown of exactly these uids
  allow_deletes
  for u in "$@"; do
    for b in attachments avatars; do
      for n in $(psq "select name from storage.objects where bucket_id='$b' and name like 'users/$u/%';"); do
        curl -s -o /dev/null -X DELETE "$API/storage/v1/object/$b/$n" -H "apikey: $SR" -H "Authorization: Bearer $SR"
      done
    done
    sq "delete from connected_attachments where sender_user_id='$u' or recipient_user_id='$u';
        delete from post_comment_views where viewer_user_id='$u';
        delete from post_shares where recipient_user_id='$u' or owner_user_id='$u';
        delete from post_comments where author_user_id='$u' or owner_user_id='$u' or recipient_user_id='$u';
        delete from posts where owner_user_id='$u';
        delete from follows where follower_user_id='$u' or followed_user_id='$u';
        delete from account_directory where user_id='$u';
        delete from public.account_privacy where user_id='$u';
        delete from public.membership where user_id='$u';
        delete from public.membership_binding where user_id='$u';
        delete from auth.users where id='$u';"
  done
}

# A GoTrue user with a real session, for delete_account_v1 (verify_jwt=false; the
# function validates the token itself). Synthetic address, local only.
gotrue_user() {  # prints "<uid> <access_token>"
  local email="p6sd-$(newid | cut -c1-8)@local.invalid" pw="p6sd-$(newid)"
  local uid; uid=$(curl -s -X POST "$API/auth/v1/admin/users" -H "apikey: $SR" -H "Authorization: Bearer $SR" \
    -H 'content-type: application/json' -d "{\"email\":\"$email\",\"password\":\"$pw\",\"email_confirm\":true}" | jq -r '.id')
  printf '%s\n' "$uid" >> "$ALL_UIDS_FILE"
  local tok; tok=$(curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $AK" -H 'content-type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$pw\"}" | jq -r '.access_token')
  echo "$uid $tok"
}

echo; echo "P6 single-object delete — focused e2e (local, no reset)"; echo

# ================================================================ STRUCTURAL
code() { grep -vE '^[[:space:]]*(//|\*|/\*)' "$1"; }
for f in supabase/functions/delete_account_v1/index.ts supabase/functions/membership_cleanup_v1/index.ts; do
  is S-1 "$(code "$f" | grep -cE '\.remove\(')" "0" "$(basename "$(dirname "$f")"): no .remove( call in executable code"
done
is S-2 "$(code supabase/functions/delete_account_v1/index.ts | grep -c 'await deleteAll(')" "2" "delete_account_v1 deletes through deleteAll at its 2 sites"
is S-3 "$(code supabase/functions/membership_cleanup_v1/index.ts | grep -c 'await deleteAll(')" "1" "cleanup deletes through deleteAll in removeVerified"
is S-4 "$(code supabase/functions/membership_cleanup_v1/index.ts | grep -c 'await removeVerified(')" "2" "...called for attachments and avatars"
is S-5 "$(code supabase/functions/delete_account_v1/index.ts | grep -cE 'const (ATTACHMENTS_BUCKET = "attachments"|AVATARS_BUCKET = "avatars");')" "2" "bucket constants pinned (a wrong bucket would read as NoSuchKey)"

# ================================================================ REAL NOT-FOUND via the helper
NF=$(deno eval "import { deleteOne } from './supabase/functions/_shared/storage/delete_one.ts';
  console.log(await deleteOne({ url: '$API', key: Deno.env.get('SR'), deadline: Date.now()+30000 }, 'attachments', 'users/$(newid)/stale/captured.pdf', 't'));" 2>&1 | tail -1)
is N-1 "$NF" "absent" "a stale captured path against real local storage -> absent (pinned NoSuchKey branch)"

# ================================================================ CLEANUP happy path
S=$(newid); B=$(newid); build "$S" "$B" 1
plan '{"*":{"ri":"attest_ri_lapsed","status":2}}'
R=$(runC "{\"mode\":\"execute\",\"user_id\":\"$S\"}"); echo "$R" > "$EVID/c1.json"
is C1-1 "$(printf '%s' "$R" | grep -c '"decision":"cleaned"')" "1" "cleanup: cleaned"
is C1-2 "$(has attachments "users/$S/$PS/att1.pdf")" "0" "post attachment row gone"
is C1-3 "$(bytes attachments "users/$S/$PS/att1.pdf")" "gone" "...and its bytes gone (local FILE backend only)"
is C1-4 "$(has attachments "users/$S/connected/$DOOM.pdf")" "0" "doomed connected asset gone"
is C1-5 "$(has attachments "users/$S/connected/$KEEP.pdf")" "1" "RETAINED asset with a live recipient survives"
is C1-6 "$(has avatars "users/$S/avatar.jpg")" "0" "avatar gone"
is C1-7 "$(psq "select coalesce(avatar_key,'NULL') from account_directory where user_id='$S';")" "NULL" "avatar_key cleared"
is C1-8 "$(objs attachments "users/$B/")" "1" "B's object untouched"
is C1-9 "$(has avatars "users/$B/avatar.jpg")" "1" "B's avatar untouched"
is C1-10 "$(psq "select count(*) from public.membership where user_id='$S' and cleanup_completed_at is not null;")" "1" "completion recorded"
destroy "$S" "$B"

# ================================================================ CLEANUP: attachment failure
S=$(newid); B=$(newid); build "$S" "$B" 1
refuse_delete_of attachments "users/$S/$PS/att1.pdf"
plan '{"*":{"ri":"attest_ri_lapsed","status":2}}'
R=$(runC "{\"mode\":\"execute\",\"user_id\":\"$S\"}"); echo "$R" > "$EVID/c2.json"
is C2-1 "$(printf '%s' "$R" | grep -c '"decision":"abort"')" "1" "attachment delete refused -> abort"
is C2-2 "$(printf '%s' "$R" | grep -o '"step":"[^"]*"' | head -1)" '"step":"attachments.delete"' "...at the attachment delete step"
is C2-3 "$(psq "select count(*) from posts where owner_user_id='$S';")" "1" "no later stage ran: posts intact"
is C2-4 "$(psq "select count(*) from connected_attachments where recipient_user_id='$S';")" "1" "received refs intact"
is C2-5 "$(psq "select count(*) from follows where follower_user_id='$S' or followed_user_id='$S';")" "2" "follows intact"
is C2-6 "$(psq "select coalesce(avatar_key,'NULL') from account_directory where user_id='$S';")" "users/$S/avatar.jpg" "avatar pointer intact"
is C2-7 "$(psq "select count(*) from public.membership where user_id='$S' and cleanup_completed_at is not null;")" "0" "no completion"
is C2-8 "$(has attachments "users/$S/$PS/att1.pdf")" "1" "the refused object is still listed"
allow_deletes; psq "update public.membership set cleanup_claimed_at = null where user_id='$S';" >/dev/null
R=$(runC "{\"mode\":\"execute\",\"user_id\":\"$S\"}")
is C2-9 "$(printf '%s' "$R" | grep -c '"decision":"cleaned"')" "1" "re-run after the fault is removed completes"
destroy "$S" "$B"

# ================================================================ CLEANUP: avatar failure
S=$(newid); B=$(newid); build "$S" "$B" 1
refuse_delete_of avatars "users/$S/avatar.jpg"
plan '{"*":{"ri":"attest_ri_lapsed","status":2}}'
R=$(runC "{\"mode\":\"execute\",\"user_id\":\"$S\"}"); echo "$R" > "$EVID/c3.json"
is C3-1 "$(printf '%s' "$R" | grep -o '"step":"[^"]*"' | head -1)" '"step":"avatars.delete"' "avatar delete refused -> abort at the avatar step"
is C3-2 "$(psq "select count(*) from posts where owner_user_id='$S';")" "0" "EARLIER stages already ran: posts gone"
is C3-3 "$(psq "select count(*) from follows where follower_user_id='$S' or followed_user_id='$S';")" "0" "...follows gone"
is C3-4 "$(psq "select coalesce(avatar_key,'NULL') from account_directory where user_id='$S';")" "users/$S/avatar.jpg" "avatar_key NOT cleared"
is C3-5 "$(psq "select count(*) from public.membership where user_id='$S' and cleanup_completed_at is not null;")" "0" "completion NOT recorded"
allow_deletes; psq "update public.membership set cleanup_claimed_at = null where user_id='$S';" >/dev/null
R=$(runC "{\"mode\":\"execute\",\"user_id\":\"$S\"}")
is C3-6 "$(printf '%s' "$R" | grep -c '"decision":"cleaned"')" "1" "re-run completes"
destroy "$S" "$B"

# ================================================================ ACCOUNT DELETION happy path
read -r S TOK <<<"$(gotrue_user)"; B=$(newid); build "$S" "$B" 0
R=$(runD "$TOK"); echo "$R" > "$EVID/d1.json"
is D1-1 "$(printf '%s' "$R" | grep -c '"success":true')" "1" "delete_account: success"
is D1-2 "$(objs attachments "users/$S/")" "0" "every attachment row gone (incl. the retained-by-cleanup asset: deletion removes all)"
is D1-3 "$(bytes attachments "users/$S/$PS/att1.pdf")" "gone" "...bytes gone (local FILE backend only)"
is D1-4 "$(has avatars "users/$S/avatar.jpg")" "0" "avatar gone"
is D1-5 "$(psq "select count(*) from auth.users where id='$S';")" "0" "auth user removed last"
is D1-6 "$(objs attachments "users/$B/")" "1" "B's object untouched"
destroy "$S" "$B"

# ================================================================ ACCOUNT DELETION: attachment failure
read -r S TOK <<<"$(gotrue_user)"; B=$(newid); build "$S" "$B" 0
refuse_delete_of attachments "users/$S/$PS/att1.pdf"
R=$(runD "$TOK"); echo "$R" > "$EVID/d2.json"
is D2-1 "$(printf '%s' "$R" | grep -o '"step":"[^"]*"')" '"step":"storage.delete.delete"' "attachment delete refused -> fails at the storage step"
is D2-2 "$(psq "select count(*) from connected_attachments where recipient_user_id='$S';")" "0" "step 1 had ALREADY run: received refs gone"
is D2-3 "$(psq "select count(*) from connected_attachments where sender_user_id='$S';")" "2" "3b did NOT run: sent rows intact"
is D2-4 "$(has avatars "users/$S/avatar.jpg")" "1" "avatar intact"
is D2-5 "$(psq "select count(*) from account_directory where user_id='$S';")" "1" "directory row intact"
is D2-6 "$(psq "select count(*) from auth.users where id='$S';")" "1" "auth user intact"
allow_deletes
R=$(runD "$TOK")
is D2-7 "$(printf '%s' "$R" | grep -c '"success":true')" "1" "re-run completes"
destroy "$S" "$B"

# ================================================================ ACCOUNT DELETION: avatar failure
read -r S TOK <<<"$(gotrue_user)"; B=$(newid); build "$S" "$B" 0
refuse_delete_of avatars "users/$S/avatar.jpg"
R=$(runD "$TOK"); echo "$R" > "$EVID/d3.json"
is D3-1 "$(printf '%s' "$R" | grep -o '"step":"[^"]*"')" '"step":"storage.delete.avatar.delete"' "avatar delete refused -> fails at the avatar step"
is D3-2 "$(psq "select count(*) from connected_attachments where sender_user_id='$S';")" "0" "3b had ALREADY run: sent rows gone"
is D3-3 "$(psq "select coalesce(avatar_key,'NULL') from account_directory where user_id='$S';")" "users/$S/avatar.jpg" "avatar pointer + directory row kept"
is D3-4 "$(psq "select count(*) from posts where owner_user_id='$S';")" "1" "step 5 did NOT run: posts intact"
is D3-5 "$(psq "select count(*) from auth.users where id='$S';")" "1" "auth user NOT removed"
allow_deletes
R=$(runD "$TOK")
is D3-6 "$(printf '%s' "$R" | grep -c '"success":true')" "1" "re-run completes"
destroy "$S" "$B"

# ================================================================ CLEANUP: a HANGING list
S=$(newid); B=$(newid); build "$S" "$B" 1
plan '{"*":{"ri":"attest_ri_lapsed","status":2}}'
hold_objects_lock 25
T0=$(date +%s); R=$(runC "{\"mode\":\"execute\",\"user_id\":\"$S\"}"); T1=$(date +%s); echo "$R" > "$EVID/c4.json"
wait "$HOLD_PID"
is C4-1 "$(printf '%s' "$R" | grep -c '"decision":"abort"')" "1" "a hanging storage list -> abort"
is C4-2 "$(printf '%s' "$R" | grep -oE '"step":"[^"]*\.timeout"' | head -1 | grep -c 'storage.list')" "1" "...with a labelled list timeout step"
is C4-3 "$([ $((T1-T0)) -lt 60 ] && echo bounded || echo "$((T1-T0))s")" "bounded" "the invocation returned within the list budget, not the lock"
is C4-4 "$(psq "select count(*) from posts where owner_user_id='$S';")" "1" "no subsequent stage: posts intact"
is C4-5 "$(objs attachments "users/$S/")" "3" "no subsequent stage: no object deleted"
is C4-6 "$(psq "select count(*) from public.membership where user_id='$S' and cleanup_completed_at is not null;")" "0" "no completion"
destroy "$S" "$B"

# ================================================================ ACCOUNT DELETION: a HANGING list
read -r S TOK <<<"$(gotrue_user)"; B=$(newid); build "$S" "$B" 0
hold_objects_lock 25
T0=$(date +%s); R=$(runD "$TOK"); T1=$(date +%s); echo "$R" > "$EVID/d4.json"
wait "$HOLD_PID"
is D4-1 "$(printf '%s' "$R" | grep -oE '"step":"[^"]*"')" '"step":"storage.list:users/'"$S"'.timeout"' "a hanging list -> fails at the labelled list timeout"
is D4-2 "$([ $((T1-T0)) -lt 60 ] && echo bounded || echo "$((T1-T0))s")" "bounded" "returned within the list budget"
is D4-3 "$(psq "select count(*) from connected_attachments where recipient_user_id='$S';")" "0" "step 1 had already run (received refs gone)"
is D4-4 "$(psq "select count(*) from connected_attachments where sender_user_id='$S';")" "2" "no subsequent stage: sent rows intact"
is D4-5 "$(objs attachments "users/$S/")" "3" "no subsequent stage: no object deleted"
is D4-6 "$(psq "select count(*) from auth.users where id='$S';")" "1" "auth user intact"
destroy "$S" "$B"

# ================================================================ LOGS carry no key
teardown_all; trap - EXIT
is L-1 "$(cat "$EVID/logs-cleanup.txt" "$EVID/logs-delete.txt" | grep -cF "$SR")" "0" "no service key in function logs"
is L-2 "$(cat "$EVID/logs-cleanup.txt" "$EVID/logs-delete.txt" | grep -cF "$AK")" "0" "no anon key in function logs"

# ================================================================ RESTORE CHECK
baseline after
for f in "$EVID"/before-struct/*.json; do n=$(basename "$f"); cmp -s "$f" "$EVID/after-struct/$n" || bad R-1 "structure changed: $n"; done
is R-2 "$(diff -q "$EVID/before-data.txt" "$EVID/after-data.txt" >/dev/null && echo same || echo DIFFERENT)" "same" "captured counts/config match baseline"
is R-3 "$(diff -q "$EVID/before-bytes.txt" "$EVID/after-bytes.txt" >/dev/null && echo same || echo DIFFERENT)" "same" "storage byte listing digest matches baseline"

echo; echo "P6SD: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
