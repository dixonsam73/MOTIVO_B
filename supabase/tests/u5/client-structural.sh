#!/usr/bin/env bash
#
# U5e client structural assertions.
#
# WHY A SHELL SCRIPT AND WHY IT LIVES HERE. These assert properties of the CLIENT
# SOURCE that no unit test can reach — "this identifier appears nowhere", "this
# file never writes to that store". The unit tests in MOTIVOTests cover the pure
# behaviour; these cover the absences. They sit beside the other U5 suites so all
# of U5's evidence is in one place.
#
# THEY TARGET CODE, NOT PROSE. Both service files explain at length that the JWS
# is never logged or persisted, so a raw text search finds the sentence claiming
# the property and reports a violation. That mistake was made twice on the server
# side (U5c-34, then E5d-STRUCT1/2/5) before the pattern was recognised; comments
# are stripped first here from the outset.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-9s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-9s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

# Strip // line comments and /* */ blocks, then count regex matches.
code() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
t=re.sub(r"//.*$","",t,flags=re.M)
print(len(re.findall(sys.argv[2],t)))' "$1" "$2"; }

ATT=MOTIVO/MembershipAttestationService.swift
BIND=MOTIVO/MembershipBindingService.swift
AUTH=MOTIVO/AuthManager.swift

echo
echo "U5e — client structural assertions"
echo

# ============================ the JWS is a bearer artefact
# Under F3b's P2 it stays valid for the LIFE OF THE TRANSACTION, so a leak is
# permanent rather than expiring in minutes. These are the absences that matter.
is C5e-1 "$(code $ATT 'print\(')"            "0" "attestation service never print()s"
is C5e-2 "$(code $ATT 'NSLog\(')"            "0" "...never NSLog()s"
is C5e-3 "$(code $ATT 'Logger|os_log')"      "0" "...never opens a Logger"
is C5e-4 "$(code $ATT 'UserDefaults')"       "0" "...never touches UserDefaults"
is C5e-5 "$(code $ATT 'Keychain\.set')"      "0" "...never writes the Keychain"
is C5e-6 "$(code $ATT 'FileManager|\.write\(')" "0" "...never writes a file"
is C5e-7 "$(code $ATT 'static var|@Published|private var')" "0" "...holds NO mutable state, so nothing can cache the JWS"

# The body is built in exactly one place and carries exactly one key.
is C5e-8  "$(code $ATT 'JSONSerialization\.data')" "1" "exactly one request body is constructed"
is C5e-9  "$(code $ATT '\[\"jws\": jws\]')"        "1" "...and it is [\"jws\": jws]"
is C5e-10 "$(code $ATT 'user_id|originalTransactionId|original_transaction_id|environment\"')" "0" "no identity or Apple key is sent"

# ============================ the client never invents a token
# A client-minted token would be a value the server never issued, and binding a
# real Apple subscription to one puts a fabricated identifier at the centre of
# the ownership protocol.
is C5e-11 "$(code $BIND 'UUID\(\)')" "0" "binding service NEVER mints a UUID"
is C5e-12 "$(code $BIND 'ensure_membership_binding')" "1" "...it asks the server, once"

# ============================ no mode dependency (the U5 invariant)
# Nothing in either service may depend on Connected already being active, or the
# invariant "(locally entitled AND hasConnectedIdentity)" is not what runs.
for F in "$ATT" "$BIND"; do
  N=$(basename "$F" .swift)
  is "C5e-13-$N" "$(code $F 'canViewFeed|appModeManager|AppMode|isConnected')" "0" "$N has no app-mode dependency"
done
is C5e-14 "$(code $ATT 'ensureValidBackendSession')" "1" "attestation uses the MODE-INDEPENDENT session helper"
is C5e-15 "$(code $ATT 'ensureValidSession\(')" "0" "...and never the Connected-gated one"
is C5e-16 "$(code $ATT 'ensureValidSessionForConnectedAccountCleanup')" "0" "...nor the cleanup-named one (C-25)"

# ============================ F6, asserted on the helper itself
is C5e-17 "$(python3 -c '
import re,sys
t=open("'$AUTH'").read()
m=re.search(r"func ensureValidBackendSession.*?\n    \}", t, flags=re.S)
print(len(re.findall(r"isConnected", m.group(0))) if m else -1)')" "0" "ensureValidBackendSession has NO isConnected guard"
is C5e-18 "$(python3 -c '
import re
t=open("'$AUTH'").read()
m=re.search(r"func ensureValidSession\(reason.*?\n    \}", t, flags=re.S)
print(len(re.findall(r"isConnected", m.group(0))) if m else -1)')" "1" "ensureValidSession KEEPS its guard — existing callers unchanged"
is C5e-19 "$(python3 -c '
import re
t=open("'$AUTH'").read()
m=re.search(r"func ensureValidSessionForConnectedAccountCleanup.*?\n    \}", t, flags=re.S)
print(len(re.findall(r"ensureValidBackendSession", m.group(0))) if m else -1)')" "1" "the cleanup helper is a thin alias, so behaviour is provably identical"

# ============================ standing Phase 3 exit assertion
# LocalFactoryReset.perform must keep exactly two callers. U5e touches client
# code, so it is re-checked rather than assumed.
is C5e-20 "$(python3 -c '
import re,glob
n=0
for f in glob.glob("MOTIVO/*.swift"):
    t=open(f).read()
    t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
    t=re.sub(r"^\s*///.*$","",t,flags=re.M)
    t=re.sub(r"^\s*//.*$","",t,flags=re.M)
    n+=len(re.findall(r"LocalFactoryReset\.perform",t))
print(n)')" "2" "LocalFactoryReset.perform still has exactly two callers"

# ============================ Solo stays account-free
is C5e-21 "$(code $ATT 'hasConnectedIdentity')" "1" "attestation requires an existing identity, never creates one"
is C5e-22 "$(code $BIND 'hasConnectedIdentity')" "1" "binding requires an existing identity, never creates one"
is C5e-23 "$(code $ATT 'signIn|SignInWithApple|ASAuthorization')" "0" "neither service can initiate authentication"

# ============================ U5f — the trigger invariant
#
# THE MOST LOAD-BEARING ASSERTIONS IN THIS FILE. If attestation is ever gated on
# Connected already being active, the member the whole mechanism exists to
# rescue -- the dormant pre-cutover subscriber sitting in Solo BECAUSE the server
# does not know them yet -- can never reach it. G11 fails silently and forever.
COORD=MOTIVO/MembershipAttestationCoordinator.swift
is C5f-1 "$(code $COORD 'canViewFeed|AppMode|BackendEnvironment|\.connected')" "0" "the coordinator has NO app-mode dependency"
is C5f-2 "$(code $COORD 'isLocallyEntitled')" "4" "entitlement is a PARAMETER, never read from a store"
is C5f-3 "$(code $COORD 'hasConnectedIdentity')" "1" "identity is required"
is C5f-4 "$(code $COORD 'BackendConfig.isConfigured')" "1" "configuration is required"
is C5f-5 "$(code $COORD 'membership_|membershipRow|hasMembership')" "0" "NEVER gated on a server membership row existing"

# The coordination must not become persistent client authority over membership.
is C5f-6 "$(code $COORD 'UserDefaults|Keychain|FileManager')" "0" "duplicate suppression is IN MEMORY ONLY"
is C5f-7 "$(code $COORD 'jws|JWS')" "0" "the coordinator never touches the JWS at all"

# Every trigger routes through the coordinator, so the invariant is enforced once.
is C5f-8 "$(code MOTIVO/MOTIVOApp.swift 'attestation.attestIfNeeded')" "4" "four app-level triggers: launch, foreground, entitlement, identity"
is C5f-9 "$(code MOTIVO/MembershipSelectionView.swift 'attestation.attestIfNeeded')" "2" "two user-initiated triggers: purchase and restore"
is C5f-10 "$(code MOTIVO/MOTIVOApp.swift 'MembershipAttestationService\.')" "0" "no trigger bypasses the coordinator"
is C5f-11 "$(code MOTIVO/MembershipSelectionView.swift 'MembershipAttestationService\.attest')" "0" "...including the purchase path"

# The triggers must sit OUTSIDE the Connected-liveness block, which returns early
# on canViewFeed. Asserted by proximity: no attestIfNeeded call may appear after
# a canViewFeed guard within the same Task.
is C5f-12 "$(python3 -c '
import re
t=open("MOTIVO/MOTIVOApp.swift").read()
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
bad=0
for m in re.finditer(r"guard appModeManager\.canViewFeed else \{ return \}(.*?)\n                    \}", t, flags=re.S):
    if "attestIfNeeded" in m.group(1): bad+=1
print(bad)')" "0" "NO attestation trigger sits behind a canViewFeed guard"

# ============================ U5f — SIWA before purchase
is C5f-13 "$(code MOTIVO/MembershipSelectionView.swift 'appAccountToken: bindingToken')" "1" "the purchase carries the SERVER-ISSUED token"
is C5f-14 "$(code MOTIVO/MembershipSelectionView.swift 'bindingToken *= *UUID\(')" "0" "...and the binding token is NEVER minted on device"
is C5f-14b "$(code MOTIVO/MembershipSelectionView.swift 'MembershipBindingService.ensureBindingToken')" "1" "...it comes from the server, through one call site"
is C5f-15 "$(code MOTIVO/ConnectedMembershipStore.swift '\.appAccountToken\(')" "1" "StoreKit receives it as a PurchaseOption"
is C5f-16 "$(code MOTIVO/ProfileView.swift 'connectedSignInIntent')" "5" "the sign-in sheet carries a join/returning intent"
is C5f-17 "$(code MOTIVO/ProfileView.swift 'connectedSignInIntent = .join')" "2" "Continue routes through SIWA when identity is absent"

# Only .verified transactions may attest — D8, asserted at the source.
is C5f-18 "$(code MOTIVO/MembershipAttestationService.swift 'case .verified')" "1" "only .verified entitlements are collected"
is C5f-19 "$(code MOTIVO/ConnectedMembershipStore.swift 'MembershipStoreError\.entitlementMissingAfterVerifiedPurchase')" "0" "F10: NOTHING constructs the old failure any more"
is C5f-19b "$(code MOTIVO/ConnectedMembershipStore.swift 'entitlementMissingAfterVerifiedPurchase')" "2" "...only its declaration and its description remain"

# ============================ Solo is still account-free
is C5f-20 "$(code MOTIVO/ProfileView.swift 'connectedPromoSection')" "2" "Connected remains behind an explicit entry point"
is C5f-21 "$(code $COORD 'signIn|ASAuthorization')" "0" "attestation can never initiate authentication"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
