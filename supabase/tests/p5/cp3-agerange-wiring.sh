#!/usr/bin/env bash
#
# CP-3 — THE AGE-RANGE WIRING REGRESSION. 2026-09-08.
#
# WHY THIS IS STRUCTURAL AND NOT A UNIT TEST.
#
# The defect was NOT in the coordinator's logic. `recoverIfNeeded` takes its
# range provider as a PARAMETER, and five unit tests pass a stub — all of them
# passed while the shipped path could not establish a band on device. The defect
# lived in WHERE THE ENVIRONMENT ACTION IS READ: `@Environment(\.requestAgeRange)`
# was declared on `struct MOTIVOApp: App`, which has no presentation context.
#
# A stubbed provider cannot distinguish that, by construction — it replaces the
# very thing that was broken. C-44 recorded the general lesson: "a probe
# validates a mechanism, not the presentation context it ships in."
#
# So the regression asserts the WIRING: which scope reads the action, which
# types may call it, and that nothing else was smuggled in to work around it.
# Same idiom as C5f-12, which parses MOTIVOApp.swift for a call-site property.
#
# Comments are stripped before counting — this fix's own files explain the rule
# they are checked for, which is exactly how U5d lost three assertions.

set -uo pipefail
cd "$(dirname "$0")/../../.."

PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m  %-8s %s\n" "$1" "$2"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m  %-8s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
is()  { if [ "$2" = "$3" ]; then ok "$1" "$4 = $3"; else bad "$1" "$4: expected '$3', got '$2'"; fi; }

code() { python3 -c '
import re,sys
t=open(sys.argv[1]).read()
t=re.sub(r"/\*.*?\*/","",t,flags=re.S)
t=re.sub(r"^\s*///.*$","",t,flags=re.M)
t=re.sub(r"^\s*//.*$","",t,flags=re.M)
t=re.sub(r"//.*$","",t,flags=re.M)
print(len(re.findall(sys.argv[2],t)))' "$1" "$2"; }

APP=MOTIVO/MOTIVOApp.swift
TRG=MOTIVO/AgeBandRecoveryTrigger.swift
CRD=MOTIVO/AgeBandRecoveryCoordinator.swift
PRF=MOTIVO/ProfileView.swift

echo
echo "CP-3 age-range wiring regression"
echo

# ===== 1. THE DEFECT ITSELF: the App must not own a presentation-requiring action
is W-1 "$(code $APP 'Environment\(\\\.requestAgeRange\)')" "0" \
       "MOTIVOApp declares NO requestAgeRange environment"
is W-1b "$(code $APP 'requestAgeRange')" "0" "MOTIVOApp does not reference it at all"
is W-1c "$(code $APP 'DeclaredAgeRange')" "0" "…and no longer imports the framework"

# The App also must not still own a bridge that closes over one.
is W-1d "$(code $APP 'recoverAgeBandIfNeeded')" "0" "the App-scope bridge is gone"

# ===== 2. IT IS READ FROM A VIEW, AND THE TRIGGER IS ONE
is W-2  "$(code $TRG 'struct AgeBandRecoveryTrigger: ViewModifier')" "1" "the trigger IS a ViewModifier"
is W-2b "$(code $TRG 'Environment\(\\\.requestAgeRange\)')" "1" "…and it reads the action itself"

# ===== 3. ONLY VIEW-SCOPED TYPES MAY CALL IT
#
# Exactly two call sites, both in Views: ProfileView's Continue (proven working
# on device) and the trigger. If a third appears, or one appears anywhere else,
# this fails.
is W-3  "$(grep -rl --include='*.swift' 'requestAgeRange(' MOTIVO | sort | tr '\n' ' ')" \
        "MOTIVO/AgeBandRecoveryTrigger.swift MOTIVO/ProfileView.swift " \
        "requestAgeRange is CALLED only from these files"
is W-3b "$(code $PRF 'Environment\(\\\.requestAgeRange\)')" "1" "ProfileView keeps its own View-scoped action"

# ===== 4. THE COORDINATOR STILL TAKES THE PROVIDER AS A PARAMETER
#
# The injection design is what keeps the coordinator testable; the fix must not
# have "solved" the defect by moving the environment read INTO the coordinator,
# which would make it untestable and re-create an App-scope-shaped problem.
is W-4  "$(code $CRD 'requestRange: \(\) async -> DeclaredAgeRangeOutcome')" "1" \
        "coordinator still receives the provider"
is W-4b "$(code $CRD 'Environment')" "0" "coordinator reads NO environment"
is W-4c "$(code $CRD 'import SwiftUI')" "0" "…and is not a View-layer type"

# ===== 5. NO SECOND AGE-RANGE MECHANISM WAS ADDED
#
# Both call sites must map through the one pure mapper. A bespoke derivation at
# either site would be a second mechanism wearing the fix's clothes.
is W-5  "$(code $TRG 'DeclaredAgeRangeService\.outcome\(for:')" "1" "trigger uses the shared mapper"
is W-5b "$(code $PRF 'DeclaredAgeRangeService\.outcome\(for:')" "1" "ProfileView uses the same mapper"
is W-5c "$(code $TRG 'lowerBound|upperBound')" "0" "trigger does NO bounds arithmetic of its own"

# ===== 6. NOTHING IS PERSISTED TO SOLVE THIS
for forbidden in UserDefaults Keychain ProfileStore 'CoreData' 'NSFetchRequest'; do
  is "W-6:$forbidden" "$(code $TRG "$forbidden")" "0" "trigger persists nothing via $forbidden"
done
is W-6b "$(code $TRG 'pendingAgeBand')" "0" "trigger does not touch pendingAgeBand — the coordinator owns it"

# ===== 7. NO NEW UI FOR RECOVERY
for ui in 'Text\(' 'Button\(' '\.sheet\(' '\.alert\(' 'NavigationStack'; do
  is "W-7:$ui" "$(code $TRG "$ui")" "0" "trigger introduces no $ui"
done

# ===== 8. FAIL-CLOSED AND POLICY ARE UNCHANGED, STILL IN THE COORDINATOR
is W-8  "$(code $TRG 'return \.unavailable')" "2" "trigger fails closed (catch + no-framework)"
is W-8b "$(code $CRD 'case \.success:\s*\n\s*return')" "1" "existing-band short-circuit intact"
is W-8c "$(code $CRD 'guard !inFlight else \{ return false \}')" "1" "single-flight intact"
is W-8d "$(code $CRD 'cooldown')" "4" "cooldown intact"
is W-8e "$(code $CRD 'guard let band = Self\.bandToEstablish')" "1" \
        "only a derived band may be written — fail-closed"

# ===== 9. THE TRIGGERS ARE STILL LAUNCH + FOREGROUND, AND STILL THE COORDINATOR'S
is W-9  "$(code $TRG 'onAppear')" "1" "launch trigger present"
is W-9b "$(code $TRG 'onChange\(of: scenePhase\)')" "1" "foreground trigger present"
is W-9c "$(code $TRG 'coordinator\.recoverIfNeeded')" "1" "recovery still belongs to the coordinator"
is W-9d "$(code $TRG 'LocalFactoryReset\.isInProgress')" "1" "factory-reset guard preserved on foreground"
is W-9e "$(code $APP 'ageBandRecovery\(coordinator:')" "1" "the trigger is attached to the root view"

echo
echo "  PASS $PASS   FAIL $FAIL"
echo
[ "$FAIL" -eq 0 ]
