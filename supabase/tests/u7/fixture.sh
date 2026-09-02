#!/usr/bin/env bash
#
# U7 cleanup fixture. LOCAL DISPOSABLE STACK ONLY.
#
# Forked from supabase/tests/u2/fixture.sh, which was built for
# delete_account_v1's blast radius and is already almost exactly U7's shape.
# Two things are added, and both are what make the EXPIRY matrix non-vacuous
# where the DELETION matrix did not need them:
#
#   - deleted_at variants, so reference counting has something to count;
#   - membership rows, so the subject is genuinely lapsed and due.
#
# NON-VACUOUS BY CONSTRUCTION. Every deletion rule has real work to do and every
# retention rule has a real row to spare. The inventory is asserted by the caller
# before the worker runs; an empty fixture is not a pass.
#
#   S  the lapsed SUBJECT, cleaned up
#   B  a live third party — recipient, author, and the control whose every
#      count must be unchanged
#   C  a SECOND recipient, which is the only way to build the shared-asset case
#   P  due Sandbox row AND a live PRODUCTION subscription — must never be cleaned
set -euo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u4/lib.sh

S=00000000-0000-0000-0000-0000000f0001
B=00000000-0000-0000-0000-0000000f0002
C=00000000-0000-0000-0000-0000000f0003
P=00000000-0000-0000-0000-0000000f0004

mkid() { psq "insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at)
  values ('$1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','$2@local.invalid',now(),now())
  on conflict do nothing;" >/dev/null; }
sq() { psq "$1" >/dev/null; }

for p in "$S s" "$B b" "$C c" "$P p"; do set -- $p; mkid "$1" "u7f-$2"
  sq "insert into public.membership_binding (user_id) values ('$1') on conflict do nothing;"; done

# ---- membership. S and P are due; B and C hold none at all.
mkmem() { sq "insert into public.membership
  (user_id, environment, original_transaction_id, product_id, apple_status,
   renewal_date, renewal_info_signed_date, binding_method, bound_at,
   entitlement_ended_at, pending_cleanup_at)
  values ('$1','$2','$3','etudes.connected.monthly',$4,$5,
     now() - interval '70 days','purchase', now() - interval '400 days', $6, $7);"; }
mkmem "$S" Sandbox    "otid-S-sandbox" 2 "now() - interval '90 days'" "now() - interval '90 days'" "now() - interval '30 days'"
mkmem "$P" Sandbox    "otid-P-sandbox" 2 "now() - interval '90 days'" "now() - interval '90 days'" "now() - interval '30 days'"
mkmem "$P" Production "otid-P-prod"    1 "now() + interval '20 days'" "null"                       "null"

# ---- directory, with avatar pointers
for t in "$S:sierra:Sierra" "$B:bravo:Bravo" "$C:charlie:Charlie" "$P:papa:Papa"; do
  u=${t%%:*}; rest=${t#*:}; a=${rest%%:*}; d=${rest##*:}
  sq "insert into account_directory (user_id, account_id, display_name, lookup_enabled, follow_requests_enabled)
      values ('$u','$a','$d',true,true);"
done

# ---- social graph. B->C is third-party and must survive S's cleanup.
for e in "$S:$B" "$B:$S" "$S:$C" "$C:$S" "$B:$C"; do
  sq "insert into follows (follower_user_id, followed_user_id, status) values ('${e%%:*}','${e##*:}','approved');"
done

# ---- posts
PS1=$(scalar "insert into posts (owner_user_id,is_public,title,attachments) values ('$S',true,'S post one','[]'::jsonb) returning id;")
PB1=$(scalar "insert into posts (owner_user_id,is_public,title,attachments) values ('$B',true,'B post one','[]'::jsonb) returning id;")
sq "update posts set attachments='[{\"bucket\":\"attachments\",\"path\":\"users/$S/$PS1/att1.pdf\"}]'::jsonb where id='$PS1';"

# ---- comments. THE DIVERGENCE FROM delete_account_v1 IS ASSERTED HERE.
#   S on B's surviving post          -> RETAINED (expiry keeps authored comments)
#   B on B's own post, addressed to S-> RETAINED (B-19, never recipient_user_id)
#   B on S's post                    -> cascades with the post (ratified)
sq "insert into post_comments (post_id,owner_user_id,author_user_id,recipient_user_id,body) values ('$PB1','$B','$S','$B','S comment on B post');"
sq "insert into post_comments (post_id,owner_user_id,author_user_id,recipient_user_id,body) values ('$PB1','$B','$B','$S','B reply addressed to S');"
sq "insert into post_comments (post_id,owner_user_id,author_user_id,recipient_user_id,body) values ('$PS1','$S','$B','$S','B comment on S post');"

sq "insert into post_shares (post_id,owner_user_id,recipient_user_id) values ('$PS1','$S','$B');"
sq "insert into post_shares (post_id,owner_user_id,recipient_user_id) values ('$PB1','$B','$S');"
sq "insert into post_comment_views (post_id,viewer_user_id) values ('$PB1','$S');"
sq "insert into post_comment_views (post_id,viewer_user_id) values ('$PB1','$B');"

# ---- connected attachments. The reference-count cases, all four shapes.
X=$(scalar "select gen_random_uuid();")   # S->B live,  S->C live      -> RETAIN
Y=$(scalar "select gen_random_uuid();")   # S->B live,  S->C DELETED   -> RETAIN (the mixed case)
Z=$(scalar "select gen_random_uuid();")   # S->B DELETED (only ref)    -> DOOM
W=$(scalar "select gen_random_uuid();")   # B->S: S's received row goes, B's object stays
putobj attachments "users/$S/connected/$X.pdf" "shared-x"  >/dev/null
putobj attachments "users/$S/connected/$Y.pdf" "shared-y"  >/dev/null
putobj attachments "users/$S/connected/$Z.pdf" "shared-z"  >/dev/null
putobj attachments "users/$B/connected/$W.pdf" "b-to-s"    >/dev/null
putobj attachments "users/$S/$PS1/att1.pdf"    "post-att"  >/dev/null
putobj avatars     "users/$S/avatar.jpg" "s-avatar" image/jpeg >/dev/null
putobj avatars     "users/$B/avatar.jpg" "b-avatar" image/jpeg >/dev/null
sq "update account_directory set avatar_key='users/$S/avatar.jpg' where user_id='$S';"
sq "update account_directory set avatar_key='users/$B/avatar.jpg' where user_id='$B';"

ca() { sq "insert into connected_attachments (asset_id,sender_user_id,recipient_user_id,storage_path,filename,byte_count,deleted_at)
   values ('$1','$2','$3','users/$2/connected/$1.pdf','f.pdf',12,$4);"; }
ca "$X" "$S" "$B" "null"
ca "$X" "$S" "$C" "null"
ca "$Y" "$S" "$B" "null"
ca "$Y" "$S" "$C" "now()"
ca "$Z" "$S" "$B" "now()"
ca "$W" "$B" "$S" "null"

printf 'S=%s\nB=%s\nC=%s\nP=%s\nPS1=%s\nPB1=%s\nX=%s\nY=%s\nZ=%s\nW=%s\n' \
  "$S" "$B" "$C" "$P" "$PS1" "$PB1" "$X" "$Y" "$Z" "$W" > supabase/tests/u7/.ids
echo "u7 fixture built"
