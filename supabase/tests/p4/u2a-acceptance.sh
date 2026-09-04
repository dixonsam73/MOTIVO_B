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

AESV=MOTIVO/AddEditSessionView.swift
PRDV=MOTIVO/PostRecordDetailsView.swift
PS=MOTIVO/PublishService.swift
BS=MOTIVO/BackendShim.swift

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

# The delete logs still say "Preview ... " and now fire in CONNECTED mode too.
# Deliberately NOT changed here: U2a's constraint is the smallest change that
# makes the path reachable, and U2b reopens this file. Pinned so that U2b has to
# address it consciously rather than inherit a log that misnames its own mode.
is U2a-6b "$(code $PS 'Preview deletePost')" "4" \
  "the 4 misnamed 'Preview deletePost' logs are still present — U2b owns them"

# ============ U2b IS NOT IMPLEMENTED — the call sites must be untouched
is U2a-7  "$(code $AESV 'shouldPublish:\s*true')"       "1" "AESV still hard-codes shouldPublish: true"
is U2a-8  "$(code $PRDV 'shouldPublish:\s*true')"       "1" "PRDV still hard-codes shouldPublish: true"
is U2a-9  "$(code $AESV 'shouldPublish:\s*isPublic')"   "0" "AESV still does NOT gate on isPublic"
is U2a-10 "$(code $PRDV 'shouldPublish:\s*visibility')" "0" "PRDV still does NOT gate on visibility"

# ============ U2c / U2s NOT implemented; deletion semantics NOT touched
is U2a-11 "$(code $BS 'loadIncludedAttachments')" "2" "BackendShim attachment path untouched"
is U2a-12 "$(git diff --name-only f12330e -- 'MOTIVO/*.swift' | wc -l | tr -d ' ')" "1" \
  "exactly ONE swift file changed since the U1 baseline"
is U2a-13 "$(git diff --name-only f12330e -- 'MOTIVO/PublishService.swift' | wc -l | tr -d ' ')" "1" \
  "and that file is PublishService.swift"
is U2a-14 "$(git diff --name-only f12330e -- supabase/migrations supabase/functions supabase/schema | wc -l | tr -d ' ')" "0" \
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
PV=MOTIVO/ProfileView.swift
is U2a-16 "$(code $PV 'LocalFactoryReset\.perform')" "2" "LocalFactoryReset.perform still exactly 2 callers"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
