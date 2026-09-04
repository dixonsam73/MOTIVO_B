#!/usr/bin/env bash
#
# P4-U2b — SHARED-ONLY UPLOADS. STRUCTURAL ACCEPTANCE.
#
# Behavioural proof: MOTIVOTests/SharedOnlyUploadTests.swift (local stack).
# This file carries what source text can settle -- above all the STRUCTURAL HALF
# of the attachment claim, which the behavioural suite deliberately does not
# assert: the attachment upload has exactly one entry point, and it is reachable
# only from the .publish branch.
#
# Comments stripped before counting.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

code() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
t=re.sub(r"//.*$","",t,flags=re.M)
print(len(re.findall(sys.argv[2],t)))' "$1" "$2"; }

# ===================== SUITE PINNING (see u2a-acceptance for the policy)
# U2b's own commit. P4-U2c's amendment removed the `op:` parameter that U2b-13
# counts, so that assertion is pinned to where it is true. The live guard on the
# current contract is u2c-acceptance U2c-15..20.
PIN=c92065e
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pin() { local out="$TMPD/$(echo "$1" | tr / _)"; git show "$PIN:$1" > "$out" 2>/dev/null || return 1; echo "$out"; }

AESV=MOTIVO/AddEditSessionView.swift         # LIVE: the U2b call-site flips
PRDV=MOTIVO/PostRecordDetailsView.swift      # LIVE: the U2b call-site flips
PS=$(pin MOTIVO/PublishService.swift)        # pinned: U2c removed the op: argument
BS=MOTIVO/BackendShim.swift                  # LIVE: the upload choke point
SSQ=MOTIVO/SessionSyncQueue.swift            # LIVE: one uploadPost invocation
PV=MOTIVO/ProfileView.swift                  # LIVE: standing Phase 3 exit assertion

# P4-U2s LEGITIMATELY FALSIFIES THIS. It asserts "U2s has not started", which
# was true of this unit and is now false. Pinned to this unit's own commit per
# the policy in u2a-acceptance. The LIVE guard did not disappear -- u2s-acceptance
# asserts the STRONGER fact: the privacy conjunct IS deployed.
PINNED_POLICIES="$TMPD/policies.json"
git show c92065e:supabase/schema/policies.json > "$PINNED_POLICIES"

echo
echo "P4-U2b — shared-only uploads, structural acceptance"
echo

# ===================== the two call-site flips, and ONLY those two
is U2b-1 "$(code $AESV 'shouldPublish:\s*isPublic')"   "1" "AESV now gates existence on isPublic"
is U2b-2 "$(code $PRDV 'shouldPublish:\s*visibility')" "1" "PRDV now gates existence on visibility"
is U2b-3 "$(code $AESV 'shouldPublish:\s*true')"       "0" "no hard-coded true left in AESV"
is U2b-4 "$(code $PRDV 'shouldPublish:\s*true')"       "0" "no hard-coded true left in PRDV"
# Bounded to U2b's OWN range. Open-ended "since U2a-2" was true only while U2b
# was the tip; the U2c amendment legitimately touches a fourth file.
is U2b-5 "$(git diff --name-only 145ddfd..c92065e -- 'MOTIVO/*.swift' | wc -l | tr -d ' ')" "3" \
  "U2b itself changed exactly three swift files"

# ===================== THE STRUCTURAL HALF OF THE ATTACHMENT CLAIM
# The behavioural suite proves the gate (no row, no .publish item). These two
# prove that no OTHER route to Storage exists, which is what makes "Share OFF
# uploads nothing" a complete statement rather than an observation.
is U2b-6 "$(code $BS 'loadIncludedAttachments')" "2" \
  "loadIncludedAttachments: exactly 1 declaration + 1 call site"
is U2b-7 "$(python3 -c "
import re
t=open('$BS').read()
t=re.sub(r'/\*.*?\*/','',t,flags=re.S); t=re.sub(r'//.*\$','',t,flags=re.M)
i=t.index('func uploadPost', t.index('class HTTPBackendPublishService'))
j=t.index('func ', i+10)
while 'loadIncludedAttachments' not in t[i:j] and j < len(t)-10:
    j=t.index('func ', j+10)
print(1 if 'loadIncludedAttachments' in t[i:j] else 0)")" "1" \
  "…and that call site is INSIDE uploadPost"
is U2b-8 "$(code $SSQ 'uploadPost')" "1" "uploadPost is invoked from exactly one place in the queue"

# ===================== the redundant immediate delete is GONE (§1)
is U2b-9  "$(code $PS 'deletePost')"        "0" "no bare deletePost left in PublishService"
is U2b-10 "$(code $PS '\.backendConnected')" "0" "…and no mode gate either — the queue owns it"
is U2b-11 "$(code $SSQ 'unsharePost')"       "1" "the ONE unshare primitive lives in the queue path"
# 3, not 2: the two unshare-capable entry points plus the backendPreview
# early-exit flush in publishIfNeeded. Written as 2 first and corrected against
# the measurement.
is U2b-12 "$(code $PS 'flushNow')"           "3" "all three flush sites intact (immediacy preserved)"
is U2b-13 "$(code $PS 'op: \.unshare')"      "2" "…and both still persist the intent first (durability preserved)"

# ===================== U2c and U2s ARE NOT STARTED
is U2b-14 "$(git diff --name-only f12330e..c92065e -- supabase/migrations supabase/functions supabase/schema | wc -l | tr -d ' ')" "0" \
  "no migration/function/schema change — U2s not started"
is U2b-15 "$(python3 -c "
import json;p=json.load(open('$PINNED_POLICIES'))
r=[x for x in p if x['policyname']=='posts_insert_owner'][0]
print(1 if 'is_public' in (r['with_check'] or '') else 0)")" "0" \
  "posts_insert_owner has NO is_public guard — U2b claims no old-client durability"

# ===================== standing invariants
is U2b-16 "$(code $PV 'LocalFactoryReset\.perform')" "2" "LocalFactoryReset.perform still exactly 2 callers"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
