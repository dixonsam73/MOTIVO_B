#!/bin/zsh
# Load a prepared Études container copy into a device's Sync Test app
# container, file by file (devicectl's directory form fails; 2026-10-18).
#
# Usage: load_container_copy.sh <udid> <prepared-dir> [bundle-id]
#   <prepared-dir> holds Documents/, Library/Application Support/… and
#   Library/Preferences/<bundle-id>.plist exactly as they must land.
#
# Run against an install that has NOT been launched since it was installed,
# so the store is first opened by the build under test (the in-place upgrade)
# and cfprefsd holds no cached defaults for it. Prints one line per file and
# a count at the end; stops at the first failure.
set -u
UDID=${1:?udid}
SRC=${2:?prepared dir}
BUNDLE=${3:-com.samueldixon.motivo.synctest}
cd "$SRC" || exit 1
typeset -i n=0
find . -type f ! -name '.DS_Store' ! -name 'manifest-*.json' | sed 's|^\./||' | sort | while IFS= read -r rel; do
  xcrun devicectl device copy to --device "$UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "$SRC/$rel" --destination "$rel" >/dev/null 2>&1 \
    || { echo "FAILED: $rel"; exit 1; }
  n+=1
  echo "$n  $rel"
done
echo "loaded $(find . -type f ! -name '.DS_Store' ! -name 'manifest-*.json' | wc -l | tr -d ' ') file(s) into $BUNDLE on $UDID"
