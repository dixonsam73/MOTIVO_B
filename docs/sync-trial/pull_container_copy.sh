#!/bin/zsh
# Copy a device's Études app container to the Mac, file by file (devicectl's
# directory form fails; 2026-10-18), for `compare_containers.py`.
#
# Usage: pull_container_copy.sh <udid> <dest-dir> [bundle-id] [subdirectory…]
#   Default subdirectories: Documents, "Library/Application Support",
#   Library/Preferences. The destination must not exist yet.
#
# Uses the JSON listing, so names with spaces are safe. Prints one line per
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
typeset -i n=0
for sub in "${SUBDIRS[@]}"; do
  xcrun devicectl device info files --device "$UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --subdirectory "$sub" --json-output "$LISTING.part" >/dev/null 2>&1 || { echo "listing failed for $sub (missing on device?)"; continue; }
  python3 -I - "$LISTING.part" "$sub" <<'EOF' | while IFS= read -r rel; do
import json, sys
data = json.load(open(sys.argv[1]))
sub = sys.argv[2].rstrip("/")
for item in data.get("result", {}).get("files", []):
    rel = item.get("relativePath")
    if not rel or item.get("resources", {}).get("isDirectory"):
        continue
    print(f"{sub}/{rel}")
EOF
    mkdir -p "$DEST/$(dirname "$rel")"
    xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
      --source "$rel" --destination "$DEST/$rel" >/dev/null 2>&1 || { echo "FAILED: $rel"; exit 1; }
    n+=1
    echo "$n  $rel"
  done
  cat "$LISTING.part" >> "$LISTING"; rm -f "$LISTING.part"
done
echo "pulled $(find "$DEST" -type f ! -name 'device-listing.json' | wc -l | tr -d ' ') file(s) from $BUNDLE on $UDID into $DEST"
