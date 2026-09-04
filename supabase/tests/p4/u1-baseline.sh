#!/usr/bin/env bash
#
# P4-U1 — PHASE 4 STRUCTURAL BASELINE.
#
# WHAT THIS IS. A re-runnable capture of the PRE-U2 client structure, written
# before any Phase 4 implementation change. It asserts the state as it is TODAY,
# not the state Phase 4 wants -- so a number of these assertions are SUPPOSED TO
# FAIL once U2 lands. Which ones, and what they become, is recorded in
# docs/phase-4-u1-baseline.md. That is the point: it makes the U2 change
# measurable rather than merely described.
#
# THEY TARGET CODE, NOT PROSE. Comments are stripped before counting. Both the
# publish path and LocalFactoryReset are heavily commented, and
# AccountDeletionTransaction.swift carries a doc comment naming
# `LocalFactoryReset.perform` that a naive grep counts as a third caller. The
# same shape as U5c-34 and C57-*, anticipated rather than repeated.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-10s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-10s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

# Strip // line comments and /* */ blocks, then count regex matches.
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
SSQ=MOTIVO/SessionSyncQueue.swift
PV=MOTIVO/ProfileView.swift
ADT=MOTIVO/AccountDeletionTransaction.swift

echo
echo "P4-U1 — Phase 4 structural baseline (PRE-U2)"
echo

# ===================== the mirror: publish is unconditional
# F-2. Both call sites hard-code the literal. These two flip at U2b.
is P4U1-1  "$(code $AESV 'shouldPublish:\s*true')"          "1" "AESV hard-codes shouldPublish: true"
is P4U1-2  "$(code $PRDV 'shouldPublish:\s*true')"          "1" "PRDV hard-codes shouldPublish: true"
is P4U1-3  "$(code $AESV 'shouldPublish:\s*isPublic')"      "0" "AESV does not yet gate on isPublic"
is P4U1-4  "$(code $PRDV 'shouldPublish:\s*visibility')"    "0" "PRDV does not yet gate on visibility"

# ===================== C-60: the delete is wired to the wrong mode
# F-3. Both gates name backendPreview and neither names backendConnected.
is P4U1-5  "$(code $PS 'mode == \.backendPreview\) && hasBaseURL')" "2" "unshare-delete gates on backendPreview"
is P4U1-6  "$(code $PS '\.backendConnected')"               "0" "PublishService never mentions backendConnected"
is P4U1-7  "$(code $SSQ 'mode == \.backendPreview \|\| mode == \.backendConnected')" "1" "flush IS mode-complete"

# ===================== F-4: no isPublic gate on the attachment path
is P4U1-8  "$(code $BS 'loadIncludedAttachments')"          "2" "loadIncludedAttachments: 1 decl + 1 call"
is P4U1-9  "$(code $BS 'payload\.isPublic')"                "2" "payload.isPublic used only to WRITE the column"
is P4U1-10 "$(code $BS 'AttachmentPrivacy\.isPrivate')"     "1" "sole attachment filter is per-attachment privacy"

# ===================== Phase 3 carry-forward — MUST NOT CHANGE IN PHASE 4
# CLAUDE.md makes this a Phase 3 EXIT assertion. A naive grep says 3; the third
# is a doc comment in AccountDeletionTransaction.swift.
LFR_PV=$(code $PV 'LocalFactoryReset\.perform')
LFR_OTHER=$(for f in $(git ls-files 'MOTIVO/*.swift'); do
              [ "$f" = "$PV" ] && continue
              code "$f" 'LocalFactoryReset\.perform'
            done | paste -sd+ - | bc)
is P4U1-11 "$LFR_PV"    "2" "LocalFactoryReset.perform callers in ProfileView"
is P4U1-12 "$LFR_OTHER" "0" "LocalFactoryReset.perform callers anywhere else"
is P4U1-13 "$(grep -c 'LocalFactoryReset\.perform' $ADT)" "1" "the third match IS the doc comment"

# ===================== server: no is_public predicate on the write path
POL=supabase/schema/policies.json
is P4U1-14 "$(python3 -c "
import json;p=json.load(open('$POL'))
print(sum(1 for r in p if r['tablename']=='posts'))")" "4" "posts carries 4 policies"
is P4U1-15 "$(python3 -c "
import json;p=json.load(open('$POL'))
r=[x for x in p if x['policyname']=='posts_insert_owner'][0]
print(1 if 'is_public' in (r['with_check'] or '') else 0)")" "0" "posts_insert_owner has NO is_public predicate"
is P4U1-16 "$(python3 -c "
import json;p=json.load(open('$POL'))
r=[x for x in p if x['policyname']=='posts_select_public_or_owner'][0]
print(1 if 'is_public = true' in (r['qual'] or '') else 0)")" "1" "SELECT policy DOES gate on is_public"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
