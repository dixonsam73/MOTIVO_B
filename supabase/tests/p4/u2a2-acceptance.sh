#!/usr/bin/env bash
#
# P4-U2a-2 / C-61 — STRUCTURAL ACCEPTANCE.
#
# The durable-unshare-intent unit. Behavioural proof lives in
# MOTIVOTests/UnshareDurabilityTests.swift (local stack); this file asserts the
# properties source text can settle -- above all that U2b has NOT been started.
#
# Comments stripped before counting: the new code explains .unshare, demotion
# and NoSuchKey at length, and a raw search would score the change against its
# own explanation.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-11s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-11s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
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
PIN=145ddfd
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pin() { local out="$TMPD/$(echo "$1" | tr / _)"; git show "$PIN:$1" > "$out" 2>/dev/null || return 1; echo "$out"; }

# WAS LIVE. P4-U2c's amendment deliberately replaced the contract these assert:
# `op` is now DERIVED from `isPublic` and has no initialiser parameter, and the
# decoder normalises instead of plainly defaulting. U2a2-4/5 remain TRUE OF
# U2a-2 and are pinned to its commit. The LIVE guard has not been dropped -- it
# MOVED to u2c-acceptance U2c-15..20 plus the behavioural decoder test, which
# assert the current, stronger contract.
SSQ=$(pin MOTIVO/SessionSyncQueue.swift)
BS=MOTIVO/BackendShim.swift                  # LIVE: demote-then-delete must not regress
PS=$(pin MOTIVO/PublishService.swift)        # pinned: U2b removed the C-60 gate
AESV=$(pin MOTIVO/AddEditSessionView.swift)  # pinned: U2a2-16/18 assert "U2b not started"
PRDV=$(pin MOTIVO/PostRecordDetailsView.swift)
PV=MOTIVO/ProfileView.swift                  # LIVE: standing Phase 3 exit assertion

# P4-U2s LEGITIMATELY FALSIFIES THIS. It asserts "U2s has not started", which
# was true of this unit and is now false. Pinned to this unit's own commit per
# the policy in u2a-acceptance. The LIVE guard did not disappear -- u2s-acceptance
# asserts the STRONGER fact: the privacy conjunct IS deployed.
PINNED_POLICIES="$TMPD/policies.json"
git show 145ddfd:supabase/schema/policies.json > "$PINNED_POLICIES"

echo
echo "P4-U2a-2 / C-61 — structural acceptance"
echo

# ===================== the operation discriminator, backward-compatibly
is U2a2-1 "$(code $SSQ 'enum PostOp')"                          "1" "PostOp discriminator exists"
is U2a2-2 "$(code $SSQ 'case publish')"                         "1" "…with a publish case"
is U2a2-3 "$(code $SSQ 'case unshare')"                         "1" "…and an unshare case"
is U2a2-4 "$(code $SSQ 'op: PostOp = \.publish')"               "1" "memberwise init DEFAULTS to .publish"
is U2a2-5 "$(code $SSQ 'decodeIfPresent\(PostOp\.self, forKey: \.op\) \?\? \.publish')" "1" \
  "decoder defaults a MISSING op to .publish — legacy files keep their meaning"
is U2a2-6 "$(code $SSQ 'public init\(from decoder: Decoder\)')" "1" \
  "a hand-written decoder exists (the synthesised one would throw on legacy files)"

# ===================== last intent wins
is U2a2-7 "$(code $SSQ 'payload\.op != existing\.op')"          "1" "merge resolves a CHANGE OF INTENT explicitly"

# ===================== demote-then-delete, and idempotent object deletion
is U2a2-8  "$(code $BS 'func unsharePost')"                     "3" "unsharePost: protocol + simulated + HTTP"
is U2a2-9  "$(code $BS 'isAlreadyAbsent')"                      "3" "already-absent helper: 1 decl + 2 call sites"
is U2a2-10 "$(code $BS 'NoSuchKey')"                            "1" \
  "the rule matches the BODY's NoSuchKey — the HTTP status is 400, not 404"
is U2a2-11 "$(python3 -c "
import re
t=open('$BS').read()
t=re.sub(r'/\*.*?\*/','',t,flags=re.S); t=re.sub(r'//.*\$','',t,flags=re.M)
i=t.index('public func unsharePost(_ postID: UUID) async -> Result<Void, Error> {', t.index('class HTTPBackendPublishService'))
seg=t[i:i+3000]
print(1 if seg.index('is_public') < seg.index('deletePost(postID)') else 0)")" "1" \
  "DEMOTION PRECEDES DELETION in the HTTP unsharePost"

# ===================== the intent is persisted before the network is trusted
is U2a2-12 "$(code $PS 'op: \.unshare')"                        "2" "both publish entry points enqueue an .unshare"

# ===================== flush dispatches and dequeues only on convergence
is U2a2-13 "$(code $SSQ 'payload\.op == \.unshare')"            "1" "flushNow dispatches on the operation"
is U2a2-14 "$(code $SSQ 'unsharePost')"                         "1" "…to unsharePost"

# ===================== NO retry cap, NO backoff — deliberate
is U2a2-15 "$(code $SSQ 'attemptCount|maxAttempts|retryLimit|backoff')" "0" \
  "no retry cap and no backoff — abandoning an owed withdrawal is the wrong failure"

# ===================== U2b / U2c / U2s ARE NOT STARTED
is U2a2-16 "$(code $AESV 'shouldPublish:\s*true')"              "1" "AESV literal UNCHANGED — U2b not started"
is U2a2-17 "$(code $PRDV 'shouldPublish:\s*true')"              "1" "PRDV literal UNCHANGED — U2b not started"
is U2a2-18 "$(code $AESV 'shouldPublish:\s*isPublic')"          "0" "AESV still does not gate on isPublic"
is U2a2-19 "$(code $BS 'loadIncludedAttachments')"              "2" "attachment path untouched — U2c not started"
is U2a2-20 "$(git diff --name-only f12330e..145ddfd -- supabase/migrations supabase/functions supabase/schema | wc -l | tr -d ' ')" "0" \
  "no migration/function/schema change — U2s not started"
is U2a2-21 "$(python3 -c "
import json;p=json.load(open('$PINNED_POLICIES'))
r=[x for x in p if x['policyname']=='posts_insert_owner'][0]
print(1 if 'is_public' in (r['with_check'] or '') else 0)")" "0" \
  "posts_insert_owner still has NO is_public predicate"

# ===================== Phase 3 carry-forward
is U2a2-22 "$(code $PV 'LocalFactoryReset\.perform')"           "2" "LocalFactoryReset.perform still exactly 2 callers"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
