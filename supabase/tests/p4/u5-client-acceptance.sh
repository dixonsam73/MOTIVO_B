#!/usr/bin/env bash
#
# P4-U5 CLIENT HALF (C-34) — STRUCTURAL ACCEPTANCE.
#
# The behavioural half is MOTIVOTests/AvatarVersionRegistryTests.swift (pure,
# network-free), which covers acceptance points 1, 2 and 6. This file carries
# what only source text can settle: WHICH render sites carry the version, which
# deliberately do NOT, and that the cache-key format was not disturbed.
#
# Comments are stripped before counting. That is not fastidiousness — U5d lost
# three assertions to a file whose own header explained the rule it was checking
# for, twice in two units.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-28s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-28s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

code() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
t=re.sub(r"//.*$","",t,flags=re.M)
print(len(re.findall(sys.argv[2],t)))' "$1" "$2"; }

echo
echo "P4-U5 client half (C-34) — structural acceptance"
echo

# ===== 3. THE CACHE-KEY FORMAT IS UNCHANGED, AND THAT IS LOAD-BEARING
#
# "avatars|<key>" is built in TEN places. THREE of them are owner-side
# invalidation helpers with byte-identical bodies — NetworkManager's,
# ProfileView's and AuthManager's. Folding the version INTO the key string
# would have left all three dropping an entry nothing reads any more: the
# owner changes their avatar, the helper clears "avatars|<key>", and the
# directory pipeline goes on serving "avatars|<key>|<version>".
#
# So the version DROPS the existing entry instead of renaming it. That is
# why these counts are an acceptance criterion and not trivia.
is U5c-1 "$(grep -rn --include='*.swift' '"avatars|\\(' MOTIVO | wc -l | tr -d ' ')" "10" \
  "the \"avatars|<key>\" format still appears in 10 places"
# NetworkManager builds it twice — the fetch path and the owner helper below it.
is U5c-key-NetworkManager "$(code MOTIVO/NetworkManager.swift 'avatars\|\\\(trimmed\)')" "2" \
  "NetworkManager's two key sites (fetch + owner helper) are unchanged in format"
for f in ProfileView AuthManager; do
  is "U5c-key-$f" "$(code MOTIVO/$f.swift 'avatars\|\\\(trimmed\)')" "1" \
    "$f's owner-side invalidation key is untouched"
done
is U5c-2 "$(code MOTIVO/NetworkManager.swift 'static func invalidateAvatarCaches\(avatarKey: String\) async')" "1" \
  "the pre-existing owner invalidation entry point survives unchanged"

# ===== 4. ALL FIVE DIRECTORY SITES CARRY THE VERSION, IN BOTH PLACES
#
# BOTH matters. Version in the fetch without version in .task(id:) means the
# refetch never fires — SwiftUI does not re-run an unchanged task identity.
# Version in .task(id:) without it in the fetch means the task re-runs and the
# pipeline serves the same stale cache entry. Either alone is a silent no-op.
#
# The two expressions differ, and the difference is the type: .task(id:) needs
# a String so it coalesces with ?? "", while the fetch parameter is String? and
# takes the optional straight through. Asserting one expression for both would
# have been an assertion about spelling, not about plumbing.
check_site() {                      # name, file, task-expr, fetch-expr
  is "U5c-task-$1"  "$(code "MOTIVO/$2.swift" "\.task\(id:.*$3")" "1" "$1 carries version in .task(id:)"
  is "U5c-fetch-$1" "$(code "MOTIVO/$2.swift" "version: $4\)")"     "1" "$1 passes version to the fetch"
}
check_site RemotePostRowTwin  ContentViewRemotePostRowTwin 'directoryAvatarVersion \?\? ""'        'directoryAvatarVersion'
check_site ProfilePeek        ProfilePeekView              'directoryAvatarVersion \?\? ""'        'directoryAvatarVersion'
check_site PeopleUserRow      PeopleUserRow                'overrideAvatarVersion \?\? ""'         'overrideAvatarVersion'
check_site Comments           CommentsView                 'directoryAccount\?\.avatarVersion \?\? ""' 'directoryAccount\?\.avatarVersion'
check_site SessionDetail      BackendSessionDetailView     'directoryAccount\?\.avatarVersion \?\? ""' 'directoryAccount\?\.avatarVersion'

# ===== THE PRE-CHECK THAT WOULD HAVE DEFEATED INVALIDATION IS GONE
#
# NOT NAMED IN THE PREDICTION — found during implementation. Three directory
# sites read the image cache BEFORE calling the pipeline and returned early on
# a hit. The pipeline is where invalidation lives, so a version bump would have
# been answered with the stale image and never reached the refetch: acceptance
# point 2 would have passed as a unit test and failed on device. The pipeline
# already returns a valid cached entry itself, so the pre-check bought nothing.
for f in ContentViewRemotePostRowTwin ProfilePeekView BackendSessionDetailView; do
  is "U5c-precheck-$f" "$(code MOTIVO/$f.swift 'RemoteAvatarImageCache\.get\(cacheKey\) != nil')" "0" \
    "$f does not pre-check the cache ahead of the pipeline"
done

# ===== 5. NO OWNER-SIDE SITE IS CHANGED
#
# These four read auth.backendAvatarKey. The owner already knows when their own
# avatar changed and invalidates explicitly; a server round-trip version would
# be strictly worse information. Untouched by file, then by behaviour.
is U5c-3 "$(git diff --name-only dfba1d8 -- MOTIVO/ProfileView.swift MOTIVO/PracticeTimerView.swift MOTIVO/AuthManager.swift | wc -l | tr -d ' ')" "0" \
  "ProfileView, PracticeTimerView and AuthManager are byte-untouched since dfba1d8"
for f in ProfileView ContentView PracticeTimerView ContentViewSessionRow; do
  is "U5c-owner-$f" "$(code MOTIVO/$f.swift 'fetchAvatarImageIfNeeded\(avatarKey: [A-Za-z]+\)')" "1" \
    "$f still fetches WITHOUT a version (owner-side)"
done

# ===== THE PIPELINE CONTRACT
is U5c-4 "$(code MOTIVO/NetworkManager.swift 'version: String\? = nil')" "1" \
  "version is OPTIONAL, so the four owner-side callers compile unchanged"
is U5c-5 "$(code MOTIVO/NetworkManager.swift 'shared\.shouldInvalidate\(key:')" "1" \
  "the pipeline consults the registry exactly once"
is U5c-6 "$(code MOTIVO/NetworkManager.swift 'RemoteAvatarImageCache\.invalidate\(cacheKey\)')" "2" \
  "image-cache invalidation: the new version path AND the pre-existing helper"
is U5c-7 "$(code MOTIVO/NetworkManager.swift 'RemoteAvatarSignedURLCache\.shared\.invalidate\(cacheKey\)')" "2" \
  "…and the same two for the signed-URL cache"
is U5c-8 "$(code MOTIVO/AccountDirectoryService.swift 'case avatarVersion = "avatar_version"')" "1" \
  "DirectoryAccount decodes avatar_version"
is U5c-9 "$(code MOTIVO/AccountDirectoryService.swift 'avatarVersion: existing')" "2" \
  "…and both explicit DirectoryAccount reconstructions carry it forward"

# ===== 7. NO SERVER BEHAVIOUR CHANGED IN THIS UNIT
is U5c-10 "$(git diff --name-only dfba1d8 -- supabase/schema supabase/migrations supabase/functions supabase/sql | wc -l | tr -d ' ')" "0" \
  "no SQL, schema or Edge Function change — G10 and B-15 untouched"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
