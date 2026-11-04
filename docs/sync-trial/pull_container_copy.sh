#!/bin/zsh
# Copy a device's Études app container to the Mac, file by file (devicectl's
# directory form fails; 2026-10-18), for `compare_containers.py`.
#
# Usage: pull_container_copy.sh <udid> <dest-dir> [bundle-id] [subdirectory…]
#   Default subdirectories: Documents, "Library/Application Support",
#   Library/Preferences. The destination must not exist yet.
#
# One recursive JSON listing of the container root is taken and filtered by
# prefix: the --subdirectory form returns nothing for Documents (seen
# 2026-11-04), and the JSON keeps names with spaces safe. Prints one line per
# file and the count; stops at the first failure.
set -u
UDID=${1:?udid}
DEST=${2:?dest dir}
BUNDLE=${3:-com.samueldixon.motivo.synctest}
shift 3 2>/dev/null || shift $#
typeset -a SUBDIRS
if (( $# > 0 )); then SUBDIRS=("$@"); else SUBDIRS=(Documents "Library/Application Support" Library/Preferences); fi
[[ -e "$DEST" ]] && { echo "destination exists: $DEST"; exit 1; }
mkdir -p "$DEST"
LISTING="$DEST/device-listing.json"
xcrun devicectl device info files --device "$UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --json-output "$LISTING" >/dev/null 2>&1 || { echo "listing failed"; exit 1; }
typeset -i n=0
python3 -I -c '
import json, sys
data = json.load(open(sys.argv[1]))
subs = [s.rstrip("/") + "/" for s in sys.argv[2:]]
for item in data.get("result", {}).get("files", []):
    rel = item.get("relativePath")
    if not rel or item.get("resources", {}).get("isDirectory"):
        continue
    if any(rel.startswith(s) for s in subs):
        print(rel)
' "$LISTING" "${SUBDIRS[@]}" | while IFS= read -r rel; do
  mkdir -p "$DEST/$(dirname "$rel")"
  xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "$rel" --destination "$DEST/$rel" >/dev/null 2>&1 || { echo "FAILED: $rel"; exit 1; }
  n+=1
  echo "$n  $rel"
done
echo "pulled $(find "$DEST" -type f ! -name 'device-listing.json' | wc -l | tr -d ' ') file(s) from $BUNDLE on $UDID into $DEST"
