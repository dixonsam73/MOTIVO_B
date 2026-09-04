#!/usr/bin/env bash
#
# P4-U2a / C-60 — STRUCTURAL ACCEPTANCE.
#
# u1-baseline.sh is left UNCHANGED as the immutable pre-U2 record; it now
# reports exactly two failures, P4U1-5 and P4U1-6, and those two are precisely
# what docs/phase-4-u2a-prediction.md predicted. This file asserts the POST-U2a
# state, including the two properties the baseline cannot express: that BOTH
# modes reach deletion, and that neither shouldPublish literal moved.
#
# Comments are stripped before counting. The gate this unit changes now carries
# a 13-line comment naming .backendConnected and .backendPreview several times,
# so a raw text search would score the fix against its own explanation --
# U5c-34's shape, anticipated rather than repeated.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-10s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-10s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

code() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
t=re.sub(r"//.*$","",t,flags=re.M)
print(len(re.findall(sys.argv[2],t)))' "$1" "$2"; }


# ===================== SUITE PINNING (P4-U2b)
# This suite asserts what THIS UNIT changed. Later units legitimately supersede
# some of it -- U2b removed the C-60 gate entirely -- so the unit-specific
# assertions are evaluated against THIS UNIT'S OWN COMMIT rather than the
# working tree. That keeps every statement here true and the suite permanently
# green, instead of accumulating expected failures across four files, which is
# exactly where a real regression hides.
#
# Standing invariants that are NOT unit-specific stay LIVE below, because their
# whole value is that they can still fail.
PIN=9f1498e
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pin() { local out="$TMPD/$(echo "$1" | tr / _)"; git show "$PIN:$1" > "$out" 2>/dev/null || return 1; echo "$out"; }

AESV=$(pin MOTIVO/AddEditSessionView.swift)
PRDV=$(pin MOTIVO/PostRecordDetailsView.swift)
PS=$(pin MOTIVO/PublishService.swift)
BS=$(pin MOTIVO/BackendShim.swift)

echo
echo "P4-U2a / C-60 — structural acceptance (POST-U2a)"
echo

# ============ the fix: BOTH modes reach deletion, and the gate is one predicate
is U2a-1 "$(code $PS 'mode == \.backendPreview \|\| mode == \.backendConnected')" "2" \
  "both unshare gates name BOTH modes"
is U2a-2 "$(code $PS 'mode == \.backendPreview\) && hasBaseURL')" "0" \
  "no gate names backendPreview ALONE any more"
is U2a-3 "$(code $PS '\.backendConnected')" "2" \
  "backendConnected appears exactly twice — the two gates, nothing else"
# U2a-4 PINS THE CALL, NOT THE WORD. A bare 'deletePost' counts 6: two real
# calls and four NSLog string literals -- string literals are CODE and survive
# comment stripping. Written as a bare word first and caught on its first run,
# the same way C57-7 was.
is U2a-4 "$(code $PS 'publish\.deletePost')" "2" \
  "exactly two deletePost CALL sites"
is U2a-5 "$(code $PS '!shouldPublish, \(mode ==')" "2" \
  "deletion remains conditional on !shouldPublish at both sites"

# ============ EXPANSION, NOT REPLACEMENT — preview must still reach deletion
# Each gate is a disjunction containing backendPreview, so preview still passes.
is U2a-6 "$(code $PS '\.backendPreview')" "5" \
  "backendPreview still named 5x — 2 widened gates, 2 NSLog gates, 1 early-exit(:103)"

# U2a-6b/6c REMOVED BY P4-U2b. They pinned the four "Preview deletePost" log
# strings -- first that they were misnamed, then that they reported the real
# mode. U2b deleted the whole block those logs lived in, so there is nothing
# left to name correctly. `u2b-acceptance.sh` U2b-9 asserts the stronger fact:
# PublishService contains no bare deletePost at all. Removed rather than pinned
# to a third commit, because an assertion about a deleted construct is noise.

is U2a-7  "$(code $AESV 'shouldPublish:\s*true')"       "1" "AESV still hard-codes shouldPublish: true"
is U2a-8  "$(code $PRDV 'shouldPublish:\s*true')"       "1" "PRDV still hard-codes shouldPublish: true"
is U2a-9  "$(code $AESV 'shouldPublish:\s*isPublic')"   "0" "AESV still does NOT gate on isPublic"
is U2a-10 "$(code $PRDV 'shouldPublish:\s*visibility')" "0" "PRDV still does NOT gate on visibility"

# ============ U2c / U2s NOT implemented; deletion semantics NOT touched
is U2a-11 "$(code $BS 'loadIncludedAttachments')" "2" "BackendShim attachment path untouched"
# PINNED TO U2a's OWN COMMIT RANGE. These asserted "since the U1 baseline",
# which was only true while U2a was the tip -- U2a-2 legitimately touches three
# files, so as written they would have decayed into permanent noise. The claim
# worth keeping is historical and exact: U2a ITSELF changed one Swift file.
is U2a-12 "$(git diff --name-only f12330e..9f1498e -- 'MOTIVO/*.swift' | wc -l | tr -d ' ')" "1" \
  "U2a itself changed exactly ONE swift file"
is U2a-13 "$(git diff --name-only f12330e..9f1498e -- 'MOTIVO/PublishService.swift' | wc -l | tr -d ' ')" "1" \
  "and that file is PublishService.swift"
is U2a-14 "$(git diff --name-only f12330e..9f1498e -- supabase/migrations supabase/functions supabase/schema | wc -l | tr -d ' ')" "0" \
  "no migration, function or schema file changed (U2s not implemented)"

# ============ fail-closed deletion semantics unchanged in BackendShim
# The storage-object loop must still return before the row DELETE is issued.
is U2a-15 "$(python3 -c "
import re,sys
t=open('$BS').read()
t=re.sub(r'/\*.*?\*/','',t,flags=re.S); t=re.sub(r'//.*\$','',t,flags=re.M)
i=t.index('public func deletePost')
seg=t[i:i+4000]
obj=seg.index('deleteStorageObject')
row=seg.index('let deletePath')
print(1 if obj < row else 0)")" "1" \
  "storage-object deletion still precedes the post-row DELETE"

# ============ Phase 3 carry-forward — must survive every Phase 4 unit
PV=MOTIVO/ProfileView.swift   # LIVE: standing Phase 3 exit assertion
is U2a-16 "$(code $PV 'LocalFactoryReset\.perform')" "2" "LocalFactoryReset.perform still exactly 2 callers"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
