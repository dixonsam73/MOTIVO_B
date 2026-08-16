#!/usr/bin/env bash
#
# U2 state inspector for fixture 1.
#
# Reads the resulting state directly rather than inferring it from the
# function's return value. A command result is not a pass; the state is.

set -euo pipefail
cd "$(dirname "$0")/../../.."
source supabase/tests/u2/lib.sh
source supabase/tests/u2/.ids

echo "---- A (departing) ----"
printf "  auth.users row              %s\n" "$(scalar "select count(*) c from auth.users where id='$A';")"
printf "  account_directory row       %s\n" "$(scalar "select count(*) c from account_directory where user_id='$A';")"
printf "  posts owned                 %s\n" "$(scalar "select count(*) c from posts where owner_user_id='$A';")"
printf "  follows involving           %s\n" "$(scalar "select count(*) c from follows where follower_user_id='$A' or followed_user_id='$A';")"
printf "  comments authored           %s\n" "$(scalar "select count(*) c from post_comments where author_user_id='$A';")"
printf "  post_shares as recipient    %s\n" "$(scalar "select count(*) c from post_shares where recipient_user_id='$A';")"
printf "  post_comment_views as viewer %s\n" "$(scalar "select count(*) c from post_comment_views where viewer_user_id='$A';")"
printf "  conn_att sent               %s\n" "$(scalar "select count(*) c from connected_attachments where sender_user_id='$A';")"
printf "  conn_att received           %s\n" "$(scalar "select count(*) c from connected_attachments where recipient_user_id='$A';")"
printf "  attachment objects          %s\n" "$(objcount attachments "users/$A/")"
printf "  avatar objects              %s\n" "$(objcount avatars "users/$A/")"

echo "---- B-9 two-recipient subcase (asset ${X:0:8}) ----"
printf "  rows for the shared asset   %s   (A->B: %s, A->C: %s)\n" \
  "$(scalar "select count(*) c from connected_attachments where asset_id='$X';")" \
  "$(scalar "select count(*) c from connected_attachments where asset_id='$X' and recipient_user_id='$B';")" \
  "$(scalar "select count(*) c from connected_attachments where asset_id='$X' and recipient_user_id='$C';")"
printf "  the ONE shared object       %s\n" "$(scalar "select count(*) c from storage.objects where bucket_id='attachments' and name='users/$A/connected/$X.pdf';")"

echo "---- protected: B and C must be untouched ----"
printf "  B auth.users / C auth.users %s / %s\n" \
  "$(scalar "select count(*) c from auth.users where id='$B';")" "$(scalar "select count(*) c from auth.users where id='$C';")"
printf "  B directory / C directory   %s / %s\n" \
  "$(scalar "select count(*) c from account_directory where user_id='$B';")" "$(scalar "select count(*) c from account_directory where user_id='$C';")"
printf "  B posts                     %s\n" "$(scalar "select count(*) c from posts where owner_user_id='$B';")"
printf "  B reply addressed to A      %s   <- B-19: must survive\n" "$(scalar "select count(*) c from post_comments where author_user_id='$B' and recipient_user_id='$A';")"
printf "  C comment on B post         %s\n" "$(scalar "select count(*) c from post_comments where author_user_id='$C';")"
printf "  third-party row B->C        %s   <- must survive\n" "$(scalar "select count(*) c from connected_attachments where sender_user_id='$B' and recipient_user_id='$C';")"
printf "  B->C object                 %s\n" "$(scalar "select count(*) c from storage.objects where bucket_id='attachments' and name='users/$B/connected/$Z.pdf';")"
printf "  B->A object (sender B)      %s   <- survives: A's sweep is users/A/ scoped\n" "$(scalar "select count(*) c from storage.objects where bucket_id='attachments' and name='users/$B/connected/$Y.pdf';")"
printf "  B follows B->C              %s\n" "$(scalar "select count(*) c from follows where follower_user_id='$B' and followed_user_id='$C';")"
printf "  B attachment objs / avatar  %s / %s\n" "$(objcount attachments "users/$B/")" "$(objcount avatars "users/$B/")"
