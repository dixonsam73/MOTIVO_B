#!/usr/bin/env bash
#
# U2 fixture 2 — B-12, storage-list pagination past the 1000-entry boundary.
#
# delete_account_v1's listFolder() pages at LIST_PAGE = 1000 and breaks when a
# page comes back short. The 2026-08-11 production run swept five objects, so it
# exercised the loop's first iteration and nothing else.
#
# THE COUNT MUST EXCEED 1000 UNDER ONE PREFIX. Spreading objects across several
# prefixes would give a large total while every individual list call still
# returned one short page — which is precisely the case already proven and
# precisely what would make a green result meaningless. 1500 in a single folder
# is used here: comfortably past the boundary rather than 1001, so a
# one-off-by-one in the paging arithmetic is caught too.
#
# D is the departing account. E is a protected bystander whose objects must
# survive, so the run also shows the sweep is prefix-scoped rather than global.

set -euo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh

COUNT=${COUNT:-1500}

echo "== identities =="
D=$(mkuser d); E=$(mkuser e)
echo "  D=$D (departing)"; echo "  E=$E (protected bystander)"
printf 'D=%s\nE=%s\nCOUNT=%s\n' "$D" "$E" "$COUNT" > supabase/tests/u2/.ids-b12

sql "insert into account_directory (user_id, account_id, display_name, lookup_enabled, follow_requests_enabled)
     values ('$D','delta','Delta',true,true);" > /dev/null
sql "insert into account_directory (user_id, account_id, display_name, lookup_enabled, follow_requests_enabled)
     values ('$E','echo','Echo',true,true);" > /dev/null

echo "== uploading $COUNT objects under ONE prefix: users/$D/bulk/ =="
seq 1 "$COUNT" | xargs -P 16 -I{} curl -s -o /dev/null -X POST \
  "$API/storage/v1/object/attachments/users/$D/bulk/obj{}.pdf" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" \
  -H 'Content-Type: application/pdf' --data-binary 'b12'

echo "== protected bystander objects =="
putobj attachments "users/$E/connected/keep1.pdf" "keep" > /dev/null
putobj attachments "users/$E/bulk/keep2.pdf"      "keep" > /dev/null
putobj avatars     "users/$E/avatar.jpg"          "keep" > /dev/null

echo
echo "== fixture inventory =="
printf "  D objects under users/%s/bulk/  %s\n" "${D:0:8}" "$(objcount attachments "users/$D/bulk/")"
printf "  D objects under users/%s/       %s\n" "${D:0:8}" "$(objcount attachments "users/$D/")"
printf "  E objects (attachments/avatars) %s / %s\n" "$(objcount attachments "users/$E/")" "$(objcount avatars "users/$E/")"
printf "  storage.objects total           %s\n" "$(scalar 'select count(*) c from storage.objects;')"
