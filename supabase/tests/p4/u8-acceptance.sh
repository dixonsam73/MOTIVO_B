#!/usr/bin/env bash
#
# P4-U8 — COPY / DISCLOSURE ALIGNMENT.
#
# The negatives matter more than the positives here. Copy that OVERSTATES
# privacy is the exact defect C-32 and D-1 exist to prevent, and it cannot be
# caught by a build. These are F10's pattern: a style note made executable.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }
has() { if grep -qF "$2" "$3"; then ok "$1" "$4"; else bad "$1" "$4 — not found in $3"; fi; }
hasnt(){ if grep -qiE "$2" "$3"; then bad "$1" "$4 — FOUND in $3"; else ok "$1" "$4"; fi; }

echo; echo "P4-U8 — copy and disclosure alignment"; echo

A=MOTIVO/AboutEtudesView.swift
C=MOTIVO/ConnectedIntroductionView.swift
P=MOTIVO/ProfileView.swift

# ===== 1. THE CLAIMS THE COPY MUST NOT MAKE
echo "-- A  copy must not overstate privacy --"
hasnt U8-A1 'Thoughts are never shared|Thoughts can never|never shared' "$A" \
  "About does not claim Thoughts are NEVER shared (the toggle exists in Thought mode)"
hasnt U8-A2 'sharing remains entirely intentional' "$A" \
  "the opt-in-implying sentence is gone"
hasnt U8-A3 'Connected is private by default|private by default. If you choose to enable' "$A" \
  "Connected is not described as private by default"
for f in "$A" "$C" "$P"; do
  hasnt "U8-A4-$(basename $f .swift)" 'we never collect|no data leaves|nothing is uploaded' "$f" \
    "$(basename $f) makes no absolute never-collect claim"
done

# ===== 2. THE CLAIMS D-1 REQUIRES
echo; echo "-- B  D-1's three required statements are present --"
has U8-B1 "shared with your followers by default" "$A" "About states the sharing DEFAULT"
has U8-B2 "Default to Private Posts" "$A" "…and names WHERE to change it"
has U8-B3 "Thoughts start private" "$A" "…and that Thoughts start private"
has U8-B4 "shared with your followers by default" "$C" "Explore Connected states the default too"
has U8-B5 "When on, new sessions start with sharing off." "$P" "the setting itself now explains what it does"
has U8-B6 "Thoughts always start private" "$P" "…including the Thoughts case"

# ===== 3. ACCURATE CLAIMS THAT MUST SURVIVE
echo; echo "-- C  accurate claims are retained, not lost in the edit --"
has U8-C1 "Attachments are private by default" "$A" "attachments-private-by-default (verified: map[key] ?? true)"
has U8-C2 "Notes and attachments can remain personal even when a session is shared" "$A" \
  "private notes on a shared session (verified: force-cleared to NULL)"
has U8-C3 "Études is private by default" "$A" "Études PROPER is private by default — this one is accurate"

# ===== 4. NO BEHAVIOUR CHANGED
#
# U8 is a copy unit. The only Swift edits permitted are string literals and one
# new Text view; anything touching control flow, persistence or the network
# would make this something other than what it claims to be.
echo; echo "-- D  copy only --"
is U8-D1 "$(git diff --name-only 57ab5fa -- MOTIVO/ | grep -v -E 'AboutEtudesView|ConnectedIntroductionView|ProfileView|AddEditSessionView' | wc -l | tr -d ' ')" "0" \
  "only the three copy files plus AddEditSessionView changed under MOTIVO/"
# AddEditSessionView is in that list ONLY for a corrected comment. Assert that,
# rather than trusting the file list -- a comment-only claim is exactly the kind
# that rots.
is U8-D1b "$(git diff -U0 57ab5fa -- MOTIVO/AddEditSessionView.swift | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | sed -E 's/^[+-][[:space:]]*//' | grep -vE '^(//|$)' | wc -l | tr -d ' ')" "0" \
  "…and AddEditSessionView's diff is COMMENT-ONLY — no code line added or removed"
is U8-D2 "$(git diff 57ab5fa -- MOTIVO/ | grep -E '^[+-]' | grep -v -E '^(\+\+\+|---)' | grep -cE '(await|URLSession|NetworkManager|\.save\(|UserDefaults|isPublic *=|shouldPublish)')" "0" \
  "no added or removed line touches network, persistence or the sharing flag"
is U8-D3 "$(git diff --name-only 57ab5fa -- supabase/ | grep -v 'tests/p4/u8' | wc -l | tr -d ' ')" "0" \
  "no SQL, schema, migration or policy change"
is U8-D4 "$(git diff --name-only 57ab5fa -- MOTIVOTests/ | wc -l | tr -d ' ')" "0" \
  "no test was altered to accommodate the copy"

# ===== 5. THE DISCLOSURE ARTEFACT
# ===== THE THOUGHTS PRODUCT DECISION, MADE EXECUTABLE
#
# Settled 2026-09-05: a Thought is a diary entry, so Share INITIALISES OFF -- but
# the owner may deliberately publish one. Default-private, NOT structurally
# private. Both halves are pinned, because either could be "simplified" away.
echo; echo "-- F  Thoughts: default-private AND shareable --"
AE=MOTIVO/AddEditSessionView.swift
is U8-F1 "$(grep -c 'isPublic = isThoughtMode ? false :' "$AE")" "1" \
  "Share INITIALISES OFF for a Thought"
is U8-F2 "$(python3 -c "
import re,sys
t=open('$AE').read()
t=re.sub(r'^\s*//.*$','',t,flags=re.M)
i=t.find('Toggle(\"\", isOn: \$isPublic)')
seg=t[:i]
print('guarded' if re.search(r'if !isThoughtMode \{[^}]*$', seg) else 'offered')")" "offered" \
  "…and the toggle is still OFFERED in Thought mode (not structurally private)"
is U8-F3 "$(grep -c 'shouldPublish: isPublic' "$AE")" "1" \
  "…so a Thought the owner DOES share reaches the publish path unguarded"
# NOT a "must not contain" assertion: the house convention is to QUOTE the
# superseded sentence rather than delete it, so the old phrase legitimately
# survives inside the correction. Assert the correction instead.
has U8-F4 "Thoughts are DEFAULT-private, deliberately, not structurally" "$AE" \
  "the comment now states the product decision rather than describing the initialiser as the state"

echo; echo "-- E  the App Store disclosure content exists and is honest about its status --"
D=docs/app-store-privacy-disclosures.md
has U8-E1 "not legal advice" "$D" "the document does not present itself as legal advice"
has U8-E2 "nothing has been entered" "$D" "…and does not claim the ASC labels were applied"
has U8-E3 "Used for tracking (as Apple defines it): NO" "$D" "tracking is answered explicitly"
has U8-E4 "Solo, nothing leaves the device at all" "$D" "the controlling fact is stated first"
hasnt U8-E5 'Connected is private by default' "$D" "the disclosure does not misdescribe the default either"

echo; echo "  passed=$PASS failed=$FAIL"; echo
[ "$FAIL" -eq 0 ]
