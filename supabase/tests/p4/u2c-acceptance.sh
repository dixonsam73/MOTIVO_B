#!/usr/bin/env bash
#
# P4-U2c — THE ATTACHMENT-UPLOAD PRIVACY INVARIANT.
#
#   No attachment-upload path is reachable for a payload whose effective
#   publication state is private/unshared.
#
# THIS UNIT ADDS NO PRODUCTION CODE, DELIBERATELY. The architecture already
# guarantees the property, and these assertions pin the guarantee. A runtime
# `guard payload.isPublic else { return }` in uploadPost would be redundant by
# construction AND weaker: it would silently swallow a divergence that these
# assertions fail loudly on.
#
# SCOPE. This is about POST attachments. Three other Storage writers are
# legitimately outside it and are asserted as such rather than ignored:
# direct-send attachments (connected_attachments, Domain 3 by design), avatars
# (the public identity row), and the DEBUG-only viewer.
#
# Comments are stripped before counting -- the code under assertion explains
# .publish/.unshare, demotion and upload at length, and a raw search would score
# the invariant against its own prose.

set -uo pipefail
cd "$(dirname "$0")/../../.."

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

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

# Name of the function enclosing the Nth match of a pattern, comments stripped.
enclosing() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
t=re.sub(r"//.*$","",t,flags=re.M)
lines=t.split("\n")
want=sys.argv[2]; nth=int(sys.argv[3]); seen=0
for i,l in enumerate(lines):
    if re.search(want,l):
        seen+=1
        if seen==nth:
            for j in range(i,-1,-1):
                m=re.match(r"\s*(?:@\w+\s+)?(?:public |private |internal |fileprivate )?func (\w+)",lines[j])
                if m: print(m.group(1)); sys.exit()
            print("<none>"); sys.exit()
print("<not-found>")' "$1" "$2" "$3"; }

BS=MOTIVO/BackendShim.swift
SSQ=MOTIVO/SessionSyncQueue.swift
AESV=MOTIVO/AddEditSessionView.swift
PRDV=MOTIVO/PostRecordDetailsView.swift
PV=MOTIVO/ProfileView.swift
DVV=MOTIVO/DebugViewerView.swift

# P4-U2s LEGITIMATELY FALSIFIES THIS. It asserts "U2s has not started", which
# was true of this unit and is now false. Pinned to this unit's own commit per
# the policy in u2a-acceptance. The LIVE guard did not disappear -- u2s-acceptance
# asserts the STRONGER fact: the privacy conjunct IS deployed.
PINNED_POLICIES="$TMPD/policies.json"
git show 85d1884:supabase/schema/policies.json > "$PINNED_POLICIES"

echo
echo "P4-U2c — attachment-upload privacy invariant"
echo

# ============ 1. THE UPLOAD DOOR IS INSIDE uploadPost, AND THERE IS ONLY ONE
is U2c-1 "$(code $BS 'uploadStorageObject')" "2" \
  "uploadStorageObject: 1 declaration + 1 call site"
is U2c-2 "$(enclosing $BS 'uploadStorageObject\(from:' 1)" "uploadPost" \
  "…and the call site's enclosing function is uploadPost"
is U2c-3 "$(code $BS 'loadIncludedAttachments')" "2" \
  "loadIncludedAttachments: 1 declaration + 1 call site"
is U2c-4 "$(enclosing $BS 'loadIncludedAttachments\(for:' 1)" "uploadPost" \
  "…and its call site's enclosing function is uploadPost too"

# ============ 2. uploadPost HAS ONE CALLER, AND IT IS GUARDED
# Excludes the protocol requirement, both implementations, and the simulated
# stub's diagnostics string -- what is counted is an actual invocation.
is U2c-5 "$(code $SSQ 'publish\.uploadPost')" "1" \
  "the queue invokes uploadPost exactly once"
is U2c-6 "$(( $(code $AESV 'publish\.uploadPost') + $(code $PRDV 'publish\.uploadPost') + $(code MOTIVO/PublishService.swift 'publish\.uploadPost') ))" "0" \
  "…and no view or PublishService invokes it at all"
is U2c-7 "$(python3 -c "
import re
t=open('$SSQ').read()
t=re.sub(r'/\*.*?\*/','',t,flags=re.S); t=re.sub(r'//.*$','',t,flags=re.M)
i=t.index('publish.uploadPost')
before=t[:i]
g=before.rindex('payload.op == .unshare')
c=before.rindex('continue')
print(1 if g < c < i else 0)")" "1" \
  "…and an .unshare guard-and-continue sits between them"

# ============ 3. THE .unshare PATH TOUCHES NO UPLOAD PRIMITIVE
is U2c-8 "$(python3 -c "
import re
t=open('$BS').read()
t=re.sub(r'/\*.*?\*/','',t,flags=re.S); t=re.sub(r'//.*$','',t,flags=re.M)
i=t.index('public func unsharePost', t.index('class HTTPBackendPublishService'))
seg=t[i:i+2500]
print(sum(1 for k in ['uploadStorageObject','loadIncludedAttachments','uploadPost'] if k in seg))")" "0" \
  "unsharePost contains NO upload primitive"

# ============ 4. EXISTENCE AND VISIBILITY CANNOT DIVERGE AT THE CALL SITES
# This is what closes `.publish` + isPublic:false, which the op boundary alone
# does not. The SAME identifier is passed to both parameters.
# The lowercase-initial filter excludes `isPublic: Bool` -- the @State TYPE
# ANNOTATION, which is the first textual match in both files and which an
# earlier revision of this assertion compared by mistake.
sym() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"//.*$","",t,flags=re.M)
args=set(re.findall(r"isPublic:\s*([a-z]\w*)",t))
sp=set(re.findall(r"shouldPublish:\s*([a-z]\w*)",t))
print(1 if sp and sp <= args and "true" not in sp else 0)' "$1"; }
is U2c-9  "$(sym $AESV)" "1" \
  "AESV passes the SAME identifier to isPublic: and shouldPublish:"
is U2c-10 "$(sym $PRDV)" "1" \
  "PRDV likewise"

# ============ 5. NO OTHER RELEASE-COMPILED POST-ATTACHMENT UPLOAD
# ConnectedAttachmentSharing and the avatar writers are DIFFERENT surfaces and
# are named here so the invariant is not overclaimed.
is U2c-11 "$(code $DVV 'storage/v1/object/attachments/')" "1" \
  "the only other attachments writer in code is DebugViewerView's"
is U2c-12 "$(python3 -c "
t=open('$DVV').read().split('\n'); d=0
for i,l in enumerate(t):
    s=l.strip()
    if s.startswith('#if DEBUG'): d+=1
    elif s.startswith('#if'): d+=1
    elif s.startswith('#endif') and d>0: d-=1
    if 'storage/v1/object/attachments/' in l and 'uploadPath' in l:
        print(1 if d>0 else 0); break
else: print('nomatch')")" "1" \
  "…and it is inside #if DEBUG, so it is not compiled into Release"

# ============ 5b. P4-U2c AMENDMENT — THE FORBIDDEN STATE IS UNREPRESENTABLE
# U2c-1..12 prove the upload door has one entrance behind an .unshare guard, and
# U2c-9/10 prove the two shipping call sites do not construct `.publish` +
# isPublic:false. NEITHER proves the combination cannot REACH the door. These do:
# `op` is derived from `isPublic`, so the contradiction has no initialiser to
# come through, and the decoder normalises the on-disk case.
is U2c-15 "$(code $SSQ 'op: PostOp = \.publish')" "0" \
  "the memberwise init no longer takes an op: parameter"
is U2c-16 "$(code $SSQ 'self\.op = isPublic \? \.publish : \.unshare')" "1" \
  "…op is DERIVED from isPublic instead"
is U2c-17 "$(code $SSQ 'public let op: PostOp')" "1" \
  "…and op is a let, so it cannot be reassigned afterwards"
is U2c-18 "$(code $SSQ 'op = \(isPublic == false\) \? \.unshare : \(declared \?\? \.publish\)')" "1" \
  "the decoder normalises a contradictory file to the SAFE reading"
is U2c-19 "$(( $(code $SSQ 'op: \.') + $(code MOTIVO/PublishService.swift 'op: \.') + $(code $AESV 'op: \.') + $(code $PRDV 'op: \.') ))" "0" \
  "NO production site passes op: at all"
is U2c-20 "$(code $SSQ 'mergedIsPublic')" "2" \
  "the merge computes visibility once and lets op follow — it cannot recombine them"

# ============ 6. STANDING INVARIANTS
is U2c-13 "$(code $PV 'LocalFactoryReset\.perform')" "2" \
  "LocalFactoryReset.perform still exactly 2 callers"
is U2c-14 "$(python3 -c "
import json;p=json.load(open('$PINNED_POLICIES'))
r=[x for x in p if x['policyname']=='posts_insert_owner'][0]
print(1 if 'is_public' in (r['with_check'] or '') else 0)")" "0" \
  "posts_insert_owner still has NO is_public guard — U2s not started"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
