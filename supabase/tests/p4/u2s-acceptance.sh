#!/usr/bin/env bash
#
# P4-U2s — SHARED-ONLY, ENFORCED BY THE SERVER.
#
# Asserts the DEPLOYED policy, from the committed production snapshot. The
# behavioural proof (A/B/C/D/E through PostgREST with genuine authenticated
# JWTs) is on the local stack, whose copy of this policy was byte-identical
# beforehand -- see docs/phase-4-u2s-acceptance.md.
#
# This is the LIVE guard that the pinned "U2s has not started" assertions in
# u2a2/u2b/u2c used to provide. It is strictly stronger: they asserted an
# absence, this asserts the presence of the exact clause.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

pol() { python3 -c "
import json,sys
p=json.load(open('supabase/schema/policies.json'))
r=[x for x in p if x['policyname']==sys.argv[1]]
print(r[0].get(sys.argv[2]) or '' if r else '<missing>')" "$1" "$2"; }

echo
echo "P4-U2s — server-side shared-only INSERT invariant"
echo

WC="$(pol posts_insert_owner with_check)"

# ============ the privacy conjunct is deployed
is U2s-1 "$(printf '%s' "$WC" | grep -c 'is_public = true')" "1" \
  "posts_insert_owner carries the is_public = true conjunct"
is U2s-2 "$(printf '%s' "$WC" | md5 -q)" "fb1873d10077148c59180ec7d45edbcb" \
  "…and the whole with_check is byte-exact to the rehearsed policy"

# ============ EVERY prior condition preserved -- nothing rewritten for tidiness
is U2s-3 "$(printf '%s' "$WC" | grep -c "enforcement_gate('posts.insert'::text)")" "1" \
  "the U6b gate conjunct is preserved verbatim"
is U2s-4 "$(printf '%s' "$WC" | grep -c 'owner_user_id = auth.uid()')" "1" \
  "the owner conjunct is preserved verbatim"

# ============ THE PRIVACY CLAUSE IS A PEER OF THE GATE, NOT NESTED INSIDE IT
# enforcement_gate returns TRUE whenever U6b enforcement is inactive, so a
# nested clause would evaporate with the kill switch. This is a privacy
# invariant, not membership enforcement.
# An earlier revision counted parentheses between the gate and the clause, which
# is fragile and got the answer wrong on correct input. The meaningful claim is
# simply that the privacy clause is the FINAL TOP-LEVEL CONJUNCT: it cannot be
# inside the gate's parenthesised SELECT, which closes earlier. U2s-2 pins the
# whole string anyway, and test E proves the behaviour with enforcement both ON
# and OFF -- that is the real evidence; this is the readable proxy.
is U2s-5 "$(printf '%s' "$WC" | grep -c 'AND (is_public = true))$')" "1" \
  "the privacy clause is the final TOP-LEVEL conjunct, outside the gate"

# ============ NO UPDATE RESTRICTION -- demotion must stay possible (C-61)
is U2s-6 "$(printf '%s' "$(pol posts_update_owner with_check)" | grep -c 'is_public')" "0" \
  "posts_update_owner has NO is_public restriction — unshare demotion preserved"
is U2s-7 "$(printf '%s' "$(pol posts_update_owner qual)" | grep -c 'is_public')" "0" \
  "…in its qual either"

# ============ read/delete untouched
is U2s-8 "$(pol posts_delete_owner qual)" "(owner_user_id = auth.uid())" \
  "posts_delete_owner unchanged"
is U2s-9 "$(printf '%s' "$(pol posts_select_public_or_owner qual)" | grep -c 'is_public = true')" "1" \
  "the SELECT policy still gates on is_public, as it always did"

# ============ scope: exactly one policy altered
is U2s-10 "$(python3 -c "
import json
p=json.load(open('supabase/schema/policies.json'))
print(sum(1 for x in p if x['tablename']=='posts'))")" "4" \
  "posts still carries exactly 4 policies"
# BOUNDED TO U2s'S OWN RANGE. Open-ended "since the U2s prediction" was true only
# while U2s was the tip; P4-U5 legitimately adds avatar_version, a trigger and two
# RPC signatures to the snapshot. The claim worth keeping is historical and exact:
# U2s ITSELF moved one snapshot file.
is U2s-11 "$(git diff --name-only 6f6a3c0..4febb8b -- supabase/schema | wc -l | tr -d ' ')" "1" \
  "U2s itself changed exactly one snapshot file"

# ============ standing invariant
is U2s-12 "$(python3 -c "
import re
t=open('MOTIVO/ProfileView.swift').read()
t=re.sub(r'/\*.*?\*/','',t,flags=re.S); t=re.sub(r'//.*$','',t,flags=re.M)
print(len(re.findall(r'LocalFactoryReset\.perform',t)))")" "2" \
  "LocalFactoryReset.perform still exactly 2 callers"

echo
echo "  passed=$PASS failed=$FAIL"
echo
[ "$FAIL" -eq 0 ]
