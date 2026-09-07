#!/usr/bin/env bash
#
# SESSION MANAGEMENT FIX — STRUCTURAL ACCEPTANCE. 2026-09-07.
#
# The behavioural half is MOTIVOTests/SessionRefreshPolicyTests.swift (pure,
# network-free), which covers the four-way disposition and the expiry gate.
# This file carries what only source text can settle: that NO non-user-initiated
# path reaches the destructive `signOut()`, and that the refresh/hydration cycle
# has had its edge cut rather than merely slowed.
#
# Comments are stripped before counting. That is not fastidiousness — U5d lost
# three assertions to a file whose own header explained the rule it was checking
# for, and THIS file's subject is a function whose doc comment names `signOut()`
# four times.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-12s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-12s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

code() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"^\s*///.*$","",t,flags=re.M)
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
t=re.sub(r"//.*$","",t,flags=re.M)
print(len(re.findall(sys.argv[2],t)))' "$1" "$2"; }

A=MOTIVO/AuthManager.swift
P=MOTIVO/SessionRefreshPolicy.swift

echo
echo "Session management fix — structural acceptance"
echo

# ===== 1. THE CONTENT-LOSS DEFECT
#
# `signOut()` removes the per-user attachment TITLE mappings — content the
# user typed. AuthManager's own `clearConnectedIdentity` doc comment states
# the rule, ~100 lines below where the code broke it: "PREFER THIS OVER
# signOut() FOR ANY NON-USER-INITIATED WITHDRAWAL." A superseded refresh
# token is squarely a non-user-initiated withdrawal.
#
# So the count that matters is CALLS, in code, inside AuthManager. It must be
# zero: every remaining occurrence is the definition or a doc comment.
is S-1 "$(code $A 'self\.signOut\(\)')" "0" "self.signOut() calls in AuthManager"

# The definition survives, because a USER-INITIATED sign-out is still correct.
is S-2 "$(code $A 'func signOut\(\)')" "1" "signOut() definition retained"

# Its only legitimate callers: the Profile sign-out button, and the factory
# reset, where everything is going anyway. If this number moves, a new
# destructive caller has appeared.
is S-3 "$(grep -rn --include='*.swift' 'auth\.signOut()' MOTIVO | wc -l | tr -d ' ')" "2" \
       "user-initiated signOut() call sites"

# The withdrawal primitive actually used by the session paths. Five sites:
# missing token, unconfigured backend (x2), the four-way switch's two
# withdrawing cases, and the Supabase-missing fallback.
is S-4 "$(code $A 'self\.clearConnectedIdentity\(reason:')" "6" \
       "clearConnectedIdentity call sites in AuthManager"
is S-4b "$(code $A 'func clearConnectedIdentity\(reason:')" "1" "its definition"

# ===== 2. THE FOUR-WAY DISPOSITION
#
# FOUR, not three and not a boolean. The boolean is what forced the false
# choice between "carry on" and "destroy everything"; a three-way that drops
# `ignore` would withdraw the Connected identity on every foreground in
# flight mode, which is strictly worse than the defect being fixed.
for c in ignore recoverWithNewerSession withdrawIdentity terminal; do
  is "S-5:$c" "$(code $P "case $c\\b")" "1" "RefreshFailureDisposition.$c declared"
  is "S-6:$c" "$(code $A "case \\.$c:")" "1" "handled in refreshSupabaseSession"
done

# The offline predicate exists ONCE, having been moved rather than copied —
# two copies would let the transport rule drift between them.
is S-7 "$(grep -rn --include='*.swift' 'func isOfflineOrTransientNetworkError' MOTIVO | wc -l | tr -d ' ')" "1" \
       "isOfflineOrTransientNetworkError definitions"

# ===== 3. THE EXPIRY GATE
is S-8 "$(code $A 'SessionRefreshPolicy\.shouldRefresh')" "1" "expiry gate wired into the refresh"

# ===== 3b. THE GATE MUST NOT EAT THE 401 RECOVERY PATH
#
# A token can be REJECTED WHILE UNEXPIRED -- server-side revocation, a signing-key
# rotation, clock skew. The auth challenge fires precisely then, so it must force
# a rotation; otherwise the gate hands the retry the very token that was refused
# and the 401 recovery path is silently dead. This assertion exists because the
# defect was introduced by the gate itself and caught on review, not by a test.
is S-8b "$(code $A 'reason: "network-auth-challenge", force: true')" "1" \
        "auth challenge forces a rotation"
is S-8c "$(code $A 'if !force,\s*\n\s*!SessionRefreshPolicy\.shouldRefresh')" "1" \
        "the expiry gate is skippable only under force"
is S-8d "$(code $A 'if !force, let existing = sessionRefreshInFlight')" "1" \
        "a forced refresh is not answered by a coalesced in-flight one"

# ===== 4. THE CYCLE'S EDGE IS CUT
#
# The gate alone does NOT break the loop — it removes ROTATION from it. A
# re-entrant pass still returns success, and the scheduler used to cancel the
# running hydration and start another, which spins. The in-flight guard is
# what makes re-entry a no-op, and it is structural: it does not depend on
# which session helper the privacy preflight happens to call, so re-pointing
# that preflight cannot silently restore the loop.
# Eight sites: the declaration, the guard, two assignments (the already-hydrated
# branch and the full one), the two withdrawal primitives that reset it, and the
# release helper's own test and assignment.
is S-9  "$(code $A 'directoryHydrationInFlightUserID')" "8" "in-flight guard sites"
is S-9b "$(code $A 'defer \{ self\.releaseDirectoryHydrationClaim\(bid\) \}')" "2" \
        "released on every task exit path"
# A cancelled task still runs its defer, and cancellation is cooperative, so the
# release must be conditional or a late-exiting task frees a NEWER identity's
# claim -- which would look exactly like the guard not existing.
is S-9c "$(code $A 'if directoryHydrationInFlightUserID == userID')" "1" \
        "the claim is released only by its owner"
is S-10 "$(code $A 'guard directoryHydrationInFlightUserID != bid else')" "1" "re-entrancy guard present"

# ===== 5. THE POLICY IS PURE
#
# It decides; it does not reach. Keychain, network and Supabase must not
# appear in it, or the four-way disposition stops being testable and this
# subsystem returns to the zero coverage it had when the loop was diagnosed.
for forbidden in Keychain NetworkManager 'import Supabase' SupabaseClient UserDefaults; do
  is "S-11:$forbidden" "$(code $P "$forbidden")" "0" "SessionRefreshPolicy free of $forbidden"
done

echo
echo "  PASS $PASS   FAIL $FAIL"
echo
[ "$FAIL" -eq 0 ]
