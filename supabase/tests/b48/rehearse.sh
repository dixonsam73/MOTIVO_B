#!/usr/bin/env bash
#
# B-48 + avatar names per upload — rehearsal on the LOCAL stack only.
#
#   ./supabase/tests/b48/rehearse.sh
#
# PART 1 (only on a stack that does not hold the migration yet): the SQL
# guards, every case inside a transaction that is rolled back.
# PART 2: the applied state through the real HTTP boundary, with real sessions
# for separate members (PostgREST and storage-api under RLS, not --local SQL,
# which bypasses RLS and could prove nothing about a policy).
#
# Part 1 ends by applying the production script for real on the local stack,
# which is the state `supabase db reset --local` also produces now that the
# migration is in supabase/migrations/. Part 2 removes every user, row and
# object it created on every exit path.
#
# What this cannot show: the hosted storage backend, or production's own rows.
set -uo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh
set +e

MIG=supabase/migrations/20261112120000_b48_avatar_names_and_own_folder_reference.sql
APPLY=supabase/sql/2026-11-12-b48-avatar-names-apply-production.sql
ROLLBACK=supabase/sql/2026-11-12-b48-avatar-names-rollback-production.sql
PREFLIGHT=supabase/sql/2026-11-12-b48-avatar-names-preflight-production.sql

PASS=0; FAIL=0
is() {  # label got want description
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS $1  $4";
  else FAIL=$((FAIL+1)); echo "FAIL $1  $4  (got '$2', want '$3')"; fi
}
has_text() { case "$2" in *"$3"*) is "$1" yes yes "$4";; *) is "$1" "$(printf '%s' "$2" | tail -c 300)" "$3" "$4";; esac; }
txn() { docker exec -i "$DB" psql -U postgres -d postgres -At -q 2>&1; }   # no ON_ERROR_STOP: the ROLLBACK must run
sq() { psq "$1" >/dev/null; }

OLD_INSERT="(( SELECT enforcement_gate('storage.avatars_insert'::text) AS enforcement_gate) AND ((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text))))"
OLD_DELETE="((bucket_id = 'avatars'::text) AND (name = (('users/'::text || (auth.uid())::text) || '/avatar.jpg'::text)))"
state() { psq "select coalesce(qual,'')||'|'||coalesce(with_check,'') from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'avatars_%' order by policyname;
               select count(*) from pg_constraint where conname='account_directory_avatar_key_own_folder';"; }
applied() { [ "$(psq "select count(*) from pg_constraint where conname='account_directory_avatar_key_own_folder' and convalidated;")" = "1" ]; }

# The apply script's body IS the migration, byte for byte.
body=$(sed -n '/^SET LOCAL statement_timeout/,/^COMMIT;/p' "$APPLY" | sed '1d;$d')
is V-1 "$(printf '%s\n' "$body" | diff -q - "$MIG" >/dev/null 2>&1 && echo same || echo different)" same "the production apply body is the migration verbatim"

# ============================================================ PART 1: guards
if applied; then
  echo "PART 1 SKIPPED: this stack already holds the migration. Rehearse the guards on a stack in the previous state."
else
  before=$(state)
  X=$(uuidgen | tr 'A-F' 'a-f'); Y=$(uuidgen | tr 'A-F' 'a-f')
  mkrow() {  # SQL that makes two users and X's directory row with the given avatar_key literal
    cat <<SQL
insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at) values
  ('$X','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b48-x@local.invalid',now(),now()),
  ('$Y','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b48-y@local.invalid',now(),now());
insert into public.account_privacy (user_id, age_band, lookup_enabled, lookup_set_under_band, follow_requests_enabled, follow_requests_set_under_band)
  values ('$X','band_18_plus',true,'band_18_plus',true,'band_18_plus');
insert into public.account_directory (user_id, account_id, display_name, lookup_enabled, follow_requests_enabled, avatar_key)
  values ('$X','b48x','B48 X',true,true,$1);
SQL
  }

  # 1a. Applies on the previous state, with a conforming old-name reference and a NULL one present.
  out=$( { echo 'BEGIN;'; mkrow "'users/$X/avatar.jpg'"; cat "$MIG"
           echo "select 'constraint:'||convalidated from pg_constraint where conname='account_directory_avatar_key_own_folder';"
           echo "select 'ref:'||avatar_key from public.account_directory where user_id='$X';"; echo 'ROLLBACK;'; } | txn)
  has_text G-1 "$out" "constraint:true" "the migration applies and validates with an existing old-name reference"
  has_text G-2 "$out" "ref:users/$X/avatar.jpg" "and that reference is untouched"

  # 1b. A second run is refused.
  out=$( { echo 'BEGIN;'; cat "$MIG" "$MIG"; echo 'ROLLBACK;'; } | txn)
  has_text G-3 "$out" "is not in the expected state; nothing was changed" "a second run is refused by the pre-guard"

  # 1c. ANY existing reference outside its owner's folder: refused, named, not altered.
  n=4
  for bad in "'users/$Y/avatar.jpg'" "'users/$Y/avatar-0123456789abcdef0123456789abcdef.jpg'" "'anything'" "''" \
             "'users/$X/other.jpg'" "'users/$(printf '%s' "$X" | tr 'a-f' 'A-F')/avatar.jpg'" "'users/$X/avatar-0123456789ABCDEF0123456789abcdef.jpg'" \
             "'users/$X/avatar-0123456789abcdef0123456789abcdef.jpg/../../$Y/avatar.jpg'"; do
    out=$( { echo 'BEGIN;'; mkrow "$bad"; cat "$MIG"; echo 'ROLLBACK;'; } | txn)
    has_text "G-$n" "$out" "1 existing avatar reference(s) are not in their owner's folder. Nothing was changed and no reference was altered. user_id: $X" "refused and reported: avatar_key = $bad"
    n=$((n+1))
  done
  is G-12 "$(psq "select count(*) from pg_constraint where conname='account_directory_avatar_key_own_folder';")" 0 "after every refusal the constraint does not exist"

  # 1d. The rollback restores the two policies and KEEPS the constraint.
  rb=$(sed -n '/^do \$b48_rollback_guard\$/,/^COMMIT;/p' "$ROLLBACK" | sed '$d')
  out=$( { echo 'BEGIN;'; cat "$MIG"; printf '%s\n' "$rb"
           echo "select 'ins:'||with_check from pg_policies where policyname='avatars_insert_owner_only';"
           echo "select 'del:'||qual from pg_policies where policyname='avatars_delete_owner_only';"
           echo "select 'constraint:'||convalidated from pg_constraint where conname='account_directory_avatar_key_own_folder';"; echo 'ROLLBACK;'; } | txn)
  has_text G-13 "$out" "ins:$OLD_INSERT" "rollback restores the INSERT policy exactly"
  has_text G-14 "$out" "del:$OLD_DELETE" "rollback restores the DELETE policy exactly"
  has_text G-15 "$out" "constraint:true" "rollback keeps the ownership constraint, validated"
  # ...and refuses while a per-upload image, or a reference to one, exists.
  out=$( { echo 'BEGIN;'; cat "$MIG"
           echo "insert into storage.objects (bucket_id, name) values ('avatars','users/$X/avatar-0123456789abcdef0123456789abcdef.jpg');"
           printf '%s\n' "$rb"; echo 'ROLLBACK;'; } | txn)
  has_text G-16 "$out" "1 per-upload image(s) and 0 reference(s)" "rollback refuses while a per-upload image exists"
  out=$( { echo 'BEGIN;'; mkrow "null"; cat "$MIG"
           echo "update public.account_directory set avatar_key='users/$X/avatar-0123456789abcdef0123456789abcdef.jpg' where user_id='$X';"
           printf '%s\n' "$rb"; echo 'ROLLBACK;'; } | txn)
  has_text G-17 "$out" "0 per-upload image(s) and 1 reference(s)" "rollback refuses while a reference to a per-upload image exists"
  # ...and refuses on a stack that is not in the B-48 state.
  out=$( { echo 'BEGIN;'; printf '%s\n' "$rb"; echo 'ROLLBACK;'; } | txn)
  has_text G-18 "$out" "are not in the B-48 state" "rollback refuses when the policies are not the B-48 ones"

  is G-19 "$(state)" "$before" "every guard case left the stack exactly as it was"

  # The preflight on the previous state, then the real apply.
  pre=$(docker exec -i "$DB" psql -U postgres -d postgres -At -q -v ON_ERROR_STOP=1 < "$PREFLIGHT" 2>&1)
  echo "preflight row: $pre"
  has_text G-20 "$pre" "|0||t|t|t|f|" "preflight: nothing nonconforming, three policies as expected, no constraint yet"
  out=$(docker exec -i "$DB" psql -U postgres -d postgres -At -q -v ON_ERROR_STOP=1 < "$APPLY" 2>&1)
  echo "apply final row: $out"
  has_text G-21 "$out" "applied|" "the production apply script reports: applied"
fi
applied || { echo "FAIL: the stack does not hold the migration; Part 2 not run"; exit 1; }

# ============================================================ PART 2: the HTTP boundary
# Production enforces membership; the local stack may not. Switched ON for
# this part so the gate on INSERT has something to refuse, and put back on exit.
ENF_WAS=$(psq "select enforcement_enabled from public.membership_control;")
RUN=$(openssl rand -hex 4)
TMP=$(mktemp -d)
UIDS=()
cleanup() {
  sq "update public.membership_control set enforcement_enabled = '$ENF_WAS'::boolean;"
  for u in "${UIDS[@]:-}"; do
    [ -n "$u" ] || continue
    for n in $(psq "select name from storage.objects where bucket_id='avatars' and name like 'users/$u/%';"); do
      curl -s -o /dev/null -X DELETE "$API/storage/v1/object/avatars/$n" -H "apikey: $SR" -H "Authorization: Bearer $SR"
    done
    sq "delete from public.follows where follower_user_id='$u' or followed_user_id='$u';
        delete from public.membership where user_id='$u'; delete from public.membership_binding where user_id='$u';
        delete from public.shadow_enforcement_stat where user_id='$u';
        delete from public.account_directory where user_id='$u'; delete from public.account_privacy where user_id='$u';"
    curl -s -o /dev/null -X DELETE "$API/auth/v1/admin/users/$u" -H "apikey: $SR" -H "Authorization: Bearer $SR"
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

member() {  # $1 label, $2 entitled 0/1 -> sets the uid in $REPLY
  local u; u=$(mkuser "b48-$1-$RUN")
  case "$u" in ????????-????-????-????-????????????) ;; *) echo "could not create user $1: $u" >&2; exit 2;; esac
  UIDS+=("$u")
  sq "insert into public.account_privacy (user_id, age_band, lookup_enabled, lookup_set_under_band, follow_requests_enabled, follow_requests_set_under_band)
      values ('$u','band_18_plus',true,'band_18_plus',true,'band_18_plus');
      insert into public.account_directory (user_id, account_id, display_name, lookup_enabled, follow_requests_enabled)
      values ('$u','b48$1$RUN','B48 $1',true,true);"
  if [ "$2" = 1 ]; then
    sq "insert into public.membership_binding (user_id) values ('$u') on conflict do nothing;
        insert into public.membership (user_id, environment, original_transaction_id, product_id, apple_status,
          renewal_date, renewal_info_signed_date, binding_method, bound_at)
        values ('$u','Sandbox','b48-$RUN-$1','etudes.connected.monthly',1, now() + interval '20 days', now(), 'purchase', now());"
  fi
  REPLY=$u
}
member a 1; A=$REPLY; member b 1; B=$REPLY; member f 1; F=$REPLY; member u 0; U=$REPLY
sq "insert into public.follows (follower_user_id, followed_user_id, status) values ('$F','$A','approved');"
sq "update public.membership_control set enforcement_enabled = true;"
is E-0 "$(psq "select enforcement_enabled from public.membership_control;")" t "membership enforcement is ON for this part, as in production (was: $ENF_WAS)"
TA=$(tokenfor "b48-a-$RUN"); TB=$(tokenfor "b48-b-$RUN"); TF=$(tokenfor "b48-f-$RUN"); TU=$(tokenfor "b48-u-$RUN")
for t in "$TA" "$TB" "$TF" "$TU"; do [ "${#t}" -gt 100 ] || { echo "no session token" >&2; exit 2; }; done

hex() { openssl rand -hex 16; }
have() { psq "select count(*) from storage.objects where bucket_id='avatars' and name='$1';"; }
up()   { printf 'jpeg-%s' "$RANDOM" | curl -s -o "$TMP/resp" -w '%{http_code}' -X POST "$API/storage/v1/object/avatars/$2" \
           -H "apikey: $AK" -H "Authorization: Bearer $1" -H 'Content-Type: image/jpeg' ${3:+-H "x-upsert: true"} --data-binary @-; }
put()  { printf 'jpeg-%s' "$RANDOM" | curl -s -o "$TMP/resp" -w '%{http_code}' -X PUT "$API/storage/v1/object/avatars/$2" \
           -H "apikey: $AK" -H "Authorization: Bearer $1" -H 'Content-Type: image/jpeg' --data-binary @-; }
del()  { curl -s -o "$TMP/resp" -w '%{http_code}' -X DELETE "$API/storage/v1/object/avatars/$2" -H "apikey: $AK" -H "Authorization: Bearer $1"; }
get()  { curl -s -o "$TMP/resp" -w '%{http_code}' "$API/storage/v1/object/authenticated/avatars/$2" -H "apikey: $AK" -H "Authorization: Bearer $1"; }
sign() { curl -s -o "$TMP/resp" -w '%{http_code}' -X POST "$API/storage/v1/object/sign/avatars/$2" -H "apikey: $AK" -H "Authorization: Bearer $1" \
           -H 'Content-Type: application/json' -d '{"expiresIn":60}'; }
digest() { psq "select coalesce(metadata->>'eTag','')||':'||coalesce(metadata->>'size','') from storage.objects where bucket_id='avatars' and name='$1';"; }
ok() { [ "$1" = 200 ] && echo ok || echo "refused"; }

OLD_A="users/$A/avatar.jpg"; NEW_A="users/$A/avatar-$(hex).jpg"; NEW_A2="users/$A/avatar-$(hex).jpg"
OLD_B="users/$B/avatar.jpg"; NEW_B="users/$B/avatar-$(hex).jpg"

# ---- INSERT
is I-1 "$(ok "$(up "$TA" "$OLD_A")")" ok "owner stores the old fixed name (an old build)"
is I-2 "$(ok "$(up "$TA" "$NEW_A")")" ok "owner stores a per-upload name"
is I-3 "$(ok "$(up "$TA" "$NEW_A2")")" ok "owner stores a second per-upload name beside it"
d0=$(digest "$NEW_A")
c=$(up "$TA" "$NEW_A"); echo "      (same name again -> HTTP $c $(head -c 160 "$TMP/resp"))"
is I-4 "$(ok "$c")" refused "the same per-upload name cannot be stored twice"
c=$(up "$TA" "$NEW_A" upsert); echo "      (same name, x-upsert -> HTTP $c $(head -c 160 "$TMP/resp"))"
is I-5 "$(ok "$c")" refused "nor overwritten by an upsert"
is I-6 "$(ok "$(put "$TA" "$NEW_A")")" refused "nor by an update"
is I-7 "$(digest "$NEW_A")" "$d0" "and its stored content is unchanged after all three"
is I-8 "$(ok "$(up "$TA" "$OLD_A" upsert)")" ok "the old fixed name can still be overwritten (old builds upsert)"
n=9
for name in "users/$B/avatar-$(hex).jpg" "users/$B/avatar.jpg" \
            "users/$A/avatar-XYZ.jpg" "users/$A/avatar-$(hex | tr 'a-f' 'A-F' | sed 's/^./A/').jpg" "users/$A/avatar-$(hex | cut -c1-31).jpg" "users/$A/avatar-$(hex)0.jpg" \
            "users/$A/avatar-$(hex).png" "users/$A/avatar-$(hex).jpg.jpg" "users/$A/x/avatar-$(hex).jpg" "users/$A/other.jpg" \
            "users/$A/avatar-$(hex).jpg/avatar.jpg" "avatar-$(hex).jpg" "users/$(printf '%s' "$A" | tr 'a-f' 'A-F')/avatar-$(hex).jpg"; do
  c=$(up "$TA" "$name")
  is "I-$n" "$(ok "$c"):$(have "$name")" "refused:0" "A cannot store $(printf '%s' "$name" | sed "s/$A/<A>/;s/$B/<B>/")"
  n=$((n+1))
done
NEW_U="users/$U/avatar-$(hex).jpg"
is I-22 "$(ok "$(up "$TU" "$NEW_U")"):$(have "$NEW_U")" "refused:0" "a member without an entitlement cannot store a per-upload name (the gate is unchanged)"
is I-23 "$(ok "$(up "$TU" "users/$U/avatar.jpg")"):$(have "users/$U/avatar.jpg")" "refused:0" "nor the old name"
c=$(printf 'x' | curl -s -o /dev/null -w '%{http_code}' -X POST "$API/storage/v1/object/avatars/users/$A/avatar-$(hex).jpg" -H "apikey: $AK" -H "Authorization: Bearer $AK" -H 'Content-Type: image/jpeg' --data-binary @-)
is I-24 "$(ok "$c")" refused "an anonymous caller cannot store anything"

# ---- SELECT (unchanged policy, new names)
is S-1 "$(ok "$(get "$TA" "$NEW_A")")" ok "owner reads the per-upload image"
is S-2 "$(ok "$(sign "$TA" "$NEW_A")")" ok "owner signs a URL for it (what the app does)"
is S-3 "$(ok "$(get "$TF" "$NEW_A")")" ok "an approved follower reads it"
is S-4 "$(ok "$(sign "$TF" "$NEW_A")")" ok "and signs a URL for it"
is S-5 "$(ok "$(get "$TB" "$NEW_A")")" refused "a member who does not follow cannot read it"
is S-6 "$(ok "$(get "$TU" "$NEW_A")")" refused "nor an unentitled non-follower"

# ---- DELETE
is D-1 "$(ok "$(up "$TB" "$NEW_B")"):$(ok "$(up "$TB" "$OLD_B")")" "ok:ok" "B stores both forms"
c=$(del "$TA" "$NEW_B"); echo "      (A deletes B's per-upload image -> HTTP $c $(head -c 160 "$TMP/resp"))"
is D-2 "$(have "$NEW_B")" 1 "A cannot delete B's per-upload image"
c=$(del "$TA" "$OLD_B")
is D-3 "$(have "$OLD_B")" 1 "A cannot delete B's old-name image"
c=$(del "$TF" "$NEW_A")
is D-4 "$(have "$NEW_A")" 1 "an approved follower can read but cannot delete"
c=$(del "$TA" "$NEW_A"); echo "      (owner deletes own per-upload image -> HTTP $c $(head -c 160 "$TMP/resp"))"
is D-5 "$c:$(have "$NEW_A")" "200:0" "the owner deletes exactly the named per-upload image"
is D-6 "$(have "$NEW_A2"):$(have "$OLD_A")" "1:1" "and nothing else in the folder went with it"
c=$(del "$TA" "$NEW_A"); body=$(head -c 300 "$TMP/resp")
echo "      (owner deletes a name that is already gone -> HTTP $c $body)"
printf '%s\n%s\n' "$c" "$body" > "$TMP/missing"
case "$c:$body" in 404:*|*not_found*|*"not found"*|*'"404"'*) m=absent;; *) m=other;; esac
is D-7 "$m" absent "a delete of a name already gone answers in a form the app reads as 'gone' (AuthManager.avatarObjectIsAbsent)"
is D-8 "$(del "$TA" "$OLD_A"):$(have "$OLD_A")" "200:0" "the owner deletes the old-name image"
# An unentitled member can still delete their own (membership never gates removal).
curl -s -o /dev/null -X POST "$API/storage/v1/object/avatars/$NEW_U" -H "apikey: $SR" -H "Authorization: Bearer $SR" -H 'Content-Type: image/jpeg' --data-binary 'x'
is D-9 "$(have "$NEW_U")" 1 "(fixture) a per-upload image exists for the unentitled member"
is D-10 "$(del "$TU" "$NEW_U"):$(have "$NEW_U")" "200:0" "an unentitled member can delete their own per-upload image"

# ---- THE REFERENCE (B-48), as the owner through PostgREST
patch() {  # token uid json [extra filter] -> code ; body in $TMP/resp
  curl -s -o "$TMP/resp" -w '%{http_code}' -X PATCH "$API/rest/v1/account_directory?user_id=eq.$2${4:+&$4}&select=user_id,avatar_key,avatar_version" \
    -H "apikey: $AK" -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -H 'Prefer: return=representation' -d "$3"
}
ref() { psq "select coalesce(avatar_key,'NULL') from public.account_directory where user_id='$1';"; }
is R-1 "$(patch "$TA" "$A" "{\"avatar_key\":\"$NEW_A2\"}"):$(ref "$A")" "200:$NEW_A2" "owner points the reference at their own per-upload image"
V=$(jq -r '.[0].avatar_version' "$TMP/resp")
is R-2 "$(patch "$TA" "$A" "{\"avatar_key\":\"users/$A/avatar.jpg\"}"):$(ref "$A")" "200:users/$A/avatar.jpg" "or at their own old name"
n=3
for bad in "$NEW_B" "$OLD_B" "anything" "" "users/$A/other.jpg" "users/$A/avatar-$(hex).jpg/../../$B/avatar.jpg" "users/$(printf '%s' "$A" | tr 'a-f' 'A-F')/avatar.jpg"; do
  c=$(patch "$TA" "$A" "{\"avatar_key\":\"$bad\"}")
  is "R-$n" "$( [ "$c" = 200 ] && echo ok || echo refused ):$(ref "$A")" "refused:users/$A/avatar.jpg" "owner cannot set avatar_key to '$(printf '%s' "$bad" | sed "s/$A/<A>/;s/$B/<B>/")' ($(jq -r '.code // empty' "$TMP/resp" 2>/dev/null))"
  n=$((n+1))
done
is R-10 "$(refuses "update public.account_directory set avatar_key='$OLD_B' where user_id='$A';")" refused "nor can any other role, the service role included (a table constraint)"
is R-11 "$(patch "$TA" "$A" '{"avatar_key":null}'):$(ref "$A")" "200:NULL" "owner clears the reference"
# The conditional write the app makes: accepted on the version it read, refused on an older one.
V2=$(jq -r '.[0].avatar_version' "$TMP/resp"); VZ=$(printf '%s' "$V2" | sed 's/+00:00$/Z/')
c=$(patch "$TA" "$A" "{\"avatar_key\":\"$NEW_A2\"}" "avatar_version=eq.$(printf '%s' "$V" | sed 's/+00:00$/Z/')")
is R-12 "$c:$(jq 'length' "$TMP/resp"):$(ref "$A")" "200:0:NULL" "a write conditional on an OLDER version matches no row and changes nothing"
c=$(patch "$TA" "$A" "{\"avatar_key\":\"$NEW_A2\"}" "avatar_version=eq.$VZ")
is R-13 "$c:$(jq 'length' "$TMP/resp"):$(ref "$A")" "200:1:$NEW_A2" "a write conditional on the CURRENT version is made"
is R-14 "$(patch "$TB" "$A" "{\"avatar_key\":null}"):$(jq 'length' "$TMP/resp"):$(ref "$A")" "200:0:$NEW_A2" "another member cannot write A's reference at all"

echo
echo "delete of a missing object answered: $(tr '\n' ' ' < "$TMP/missing")"
cleanup; trap - EXIT
is Z-1 "$(psq "select enforcement_enabled from public.membership_control;"):$(psq "select count(*) from storage.objects where bucket_id='avatars' and name like '%avatar-%';"):$(psq "select count(*) from auth.users where email like 'b48-%';")" "$ENF_WAS:0:0" "enforcement is as it was, and no test object or user is left"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
