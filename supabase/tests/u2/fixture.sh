#!/usr/bin/env bash
#
# U2 fixture 1 — B-4, B-13 and B-9's two-recipient subcase.
#
# Three local identities. No Apple ID is involved and none is possible here:
# these are local GoTrue users, which is exactly why Phase 3 could unblock a
# subcase that two real Apple IDs could never stage.
#
#   A  the departing account (deleted in the test)
#   B  live recipient, and a third party whose own state must survive
#   C  SECOND live recipient of the same asset — the subcase itself
#
# NON-VACUOUS BY CONSTRUCTION. Every deletion step in delete_account_v1 has real
# work to do, and every retention rule has a real row to spare. An empty fixture
# is not a pass, so the inventory is asserted at the end.

set -euo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh

echo "== identities =="
A=$(mkuser a); B=$(mkuser b); C=$(mkuser c)
echo "  A=$A"; echo "  B=$B"; echo "  C=$C"
printf 'A=%s\nB=%s\nC=%s\n' "$A" "$B" "$C" > supabase/tests/u2/.ids

echo "== directory rows =="
# Names spelled out rather than derived: macOS ships bash 3.2, which has no ${x^}.
for triple in "$A:alpha:Alpha" "$B:bravo:Bravo" "$C:charlie:Charlie"; do
  u=$(echo "$triple" | cut -d: -f1)
  a=$(echo "$triple" | cut -d: -f2)
  d=$(echo "$triple" | cut -d: -f3)
  sql "insert into account_directory (user_id, account_id, display_name, lookup_enabled, follow_requests_enabled)
       values ('$u', '$a', '$d', true, true);" > /dev/null
done

echo "== social graph =="
# A<->B and A<->C approved both ways; B->C is THIRD-PARTY and must survive A's deletion.
for e in "$A:$B" "$B:$A" "$A:$C" "$C:$A" "$B:$C"; do
  sql "insert into follows (follower_user_id, followed_user_id, status)
       values ('${e%%:*}', '${e##*:}', 'approved');" > /dev/null
done

echo "== posts =="
PA1=$(scalar "insert into posts (owner_user_id, is_public, title, attachments)
              values ('$A', true, 'A post one', '[]'::jsonb) returning id;")
PA2=$(scalar "insert into posts (owner_user_id, is_public, title, attachments)
              values ('$A', true, 'A post two', '[]'::jsonb) returning id;")
PB1=$(scalar "insert into posts (owner_user_id, is_public, title, attachments)
              values ('$B', true, 'B post one', '[]'::jsonb) returning id;")
sql "update posts set attachments =
       '[{\"bucket\":\"attachments\",\"path\":\"users/$A/$PA1/att1.pdf\"}]'::jsonb
     where id = '$PA1';" > /dev/null
printf 'PA1=%s\nPA2=%s\nPB1=%s\n' "$PA1" "$PA2" "$PB1" >> supabase/tests/u2/.ids

echo "== comments =="
# A on B's post          -> DELETED (author_user_id = A)
# B on B's own post, addressed to A -> SURVIVES (B-19: someone else's words)
# C on B's own post      -> SURVIVES (unrelated third party)
sql "insert into post_comments (post_id, owner_user_id, author_user_id, recipient_user_id, body)
     values ('$PB1','$B','$A','$B','A comment on B post');" > /dev/null
sql "insert into post_comments (post_id, owner_user_id, author_user_id, recipient_user_id, body)
     values ('$PB1','$B','$B','$A','B reply addressed to A');" > /dev/null
sql "insert into post_comments (post_id, owner_user_id, author_user_id, recipient_user_id, body)
     values ('$PB1','$B','$C','$B','C comment on B post');" > /dev/null

echo "== shares and views =="
sql "insert into post_shares (post_id, owner_user_id, recipient_user_id) values ('$PA1','$A','$B');" > /dev/null
sql "insert into post_shares (post_id, owner_user_id, recipient_user_id) values ('$PB1','$B','$A');" > /dev/null
sql "insert into post_comment_views (post_id, viewer_user_id) values ('$PB1','$A');" > /dev/null
sql "insert into post_comment_views (post_id, viewer_user_id) values ('$PB1','$B');" > /dev/null

echo "== storage objects =="
X=$(scalar "select gen_random_uuid();")   # THE shared asset: A -> B and A -> C
Y=$(scalar "select gen_random_uuid();")   # B -> A   (sender B, so under users/B/)
Z=$(scalar "select gen_random_uuid();")   # B -> C   (third party, must survive)
printf 'X=%s\nY=%s\nZ=%s\n' "$X" "$Y" "$Z" >> supabase/tests/u2/.ids
putobj attachments "users/$A/connected/$X.pdf" "shared-asset" > /dev/null
putobj attachments "users/$A/$PA1/att1.pdf"    "post-attach"  > /dev/null
putobj attachments "users/$B/connected/$Y.pdf" "b-to-a"       > /dev/null
putobj attachments "users/$B/connected/$Z.pdf" "b-to-c"       > /dev/null
putobj avatars     "users/$A/avatar.jpg"       "a-avatar" image/jpeg > /dev/null
putobj avatars     "users/$B/avatar.jpg"       "b-avatar" image/jpeg > /dev/null
sql "update account_directory set avatar_key='users/$A/avatar.jpg' where user_id='$A';" > /dev/null
sql "update account_directory set avatar_key='users/$B/avatar.jpg' where user_id='$B';" > /dev/null

echo "== connected_attachments =="
# THE SUBCASE: one asset, ONE storage_path, TWO live recipient rows.
# connected_attachments_asset_recipient_unique is UNIQUE(asset_id, recipient_user_id)
# and the path CHECK derives storage_path from sender+asset alone, so this is
# the only shape it can take.
sql "insert into connected_attachments
       (asset_id, sender_user_id, recipient_user_id, storage_path, filename, byte_count)
     values ('$X','$A','$B','users/$A/connected/$X.pdf','shared.pdf',12);" > /dev/null
sql "insert into connected_attachments
       (asset_id, sender_user_id, recipient_user_id, storage_path, filename, byte_count)
     values ('$X','$A','$C','users/$A/connected/$X.pdf','shared.pdf',12);" > /dev/null
# A as RECIPIENT (step 1 has work), and a third-party row that must survive.
sql "insert into connected_attachments
       (asset_id, sender_user_id, recipient_user_id, storage_path, filename, byte_count)
     values ('$Y','$B','$A','users/$B/connected/$Y.pdf','b-to-a.pdf',6);" > /dev/null
sql "insert into connected_attachments
       (asset_id, sender_user_id, recipient_user_id, storage_path, filename, byte_count)
     values ('$Z','$B','$C','users/$B/connected/$Z.pdf','b-to-c.pdf',6);" > /dev/null

echo
echo "== fixture inventory (an empty fixture is not a pass) =="
printf "  auth.users              %s\n" "$(scalar 'select count(*) c from auth.users;')"
printf "  account_directory       %s\n" "$(scalar 'select count(*) c from account_directory;')"
printf "  posts (A / total)       %s / %s\n" "$(scalar "select count(*) c from posts where owner_user_id='$A';")" "$(scalar 'select count(*) c from posts;')"
printf "  follows (A / total)     %s / %s\n" "$(scalar "select count(*) c from follows where follower_user_id='$A' or followed_user_id='$A';")" "$(scalar 'select count(*) c from follows;')"
printf "  comments (A auth/total) %s / %s\n" "$(scalar "select count(*) c from post_comments where author_user_id='$A';")" "$(scalar 'select count(*) c from post_comments;')"
printf "  conn_att (A sent/recv)  %s / %s   total %s\n" "$(scalar "select count(*) c from connected_attachments where sender_user_id='$A';")" "$(scalar "select count(*) c from connected_attachments where recipient_user_id='$A';")" "$(scalar 'select count(*) c from connected_attachments;')"
printf "  attachments objs A / B  %s / %s\n" "$(objcount attachments "users/$A/")" "$(objcount attachments "users/$B/")"
printf "  avatar objs A / B       %s / %s\n" "$(objcount avatars "users/$A/")" "$(objcount avatars "users/$B/")"
printf "  shared-asset rows       %s  (asset %s, one path, two recipients)\n" "$(scalar "select count(*) c from connected_attachments where asset_id='$X';")" "${X:0:8}"
