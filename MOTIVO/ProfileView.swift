// CHANGE-ID: 20260722_M10A_ProfileAccountSettingsFoundation
// SCOPE: M10A only — differentiate Études and Études Connected account rows; add Manage Membership placeholder in Connected; expose Erase All Études Data in both modes; preserve existing backend-delete + local factory-reset behavior for Connected and add direct local factory reset for Études mode; no other changes.
// SEARCH-TOKEN: 20260722_M10A_PROFILE_ACCOUNT_SETTINGS

// CHANGE-ID: 20260625_173400_Profile_ShowScoresToggle
// SCOPE: ProfileView settings only — add persisted Show Scores toggle using existing appSettings_showScores preference; no other UI, navigation, persistence, or timer logic changes.
// SEARCH-TOKEN: 20260625_173400_Profile_ShowScoresToggle

// CHANGE-ID: 20260517_221800_ProfileView_SubtleVisualPolish_Fix
// SCOPE: ProfileView visual polish only — quieter surfaces/dividers/rhythm; no behavior/navigation/persistence changes.
// SEARCH-TOKEN: 20260517_221800_ProfileView_SubtleVisualPolish_Fix

// CHANGE-ID: 20260515_122500_ThreadSuggestionsToggle
// SCOPE: ProfileView settings only — add persisted Show thread suggestions toggle; no other UI or logic changes.
// SEARCH-TOKEN: 20260515_122500_ThreadSuggestionsToggle

// CHANGE-ID: 20260428_191500_ProfileSignInGateSuppress
// SCOPE: ProfileView — close signed-out sign-in gate immediately after successful sign-in so setup root can render without signed-in ProfileView flash; no other UI/logic changes.
// SEARCH-TOKEN: 20260428_191500_ProfileSignInGateSuppress

// CHANGE-ID: 20260428_151500_ProfileAccountIDStaleStateGuard
// SCOPE: Account ID sync hardening - prevent stale accountIDText from being posted for a new backend user; trigger generation from current backend identity only.
// SEARCH-TOKEN: 20260428_151500_ProfileAccountIDStaleStateGuard

// CHANGE-ID: 20260317_125300_ProfileCard_InnerCardDividersIcons
// SCOPE: ProfileView — profile card only: add inner card surface, row dividers, and subtle conditional location/account ID icons while preserving all existing logic and behavior.
// SEARCH-TOKEN: 20260317_125300_ProfileCard_InnerCardDividersIcons

// CHANGE-ID: 20260317_110500_Profile_RemoveTopTitle_RenameProfileSection
// SCOPE: Visual-only — remove custom top Profile toolbar title and rename first section header from Name to Profile; no other UI or logic changes.
// SEARCH-TOKEN: 20260317_110500_Profile_RemoveTopTitle_RenameProfileSection

// CHANGE-ID: 20260317_102900_Profile_InlineAboutAndAccountActions
// SCOPE: UI-only — replace App Settings chevron with inline About Études / Sign out / Delete account rows; remove inline welcome card from Profile; no other UI or logic changes.
// CHANGE-ID: 20260317_092400_Profile_TimerControlsInline_RemoveAccountCards
// SCOPE: UI-only — move Show Metronome/Show Drone toggles into Session Setup card; remove Sign out/Delete account cards from Profile; no logic/theme/layout changes beyond relocation.
// SEARCH-TOKEN: 20260317_092400_Profile_TimerControlsInline_RemoveAccountCards

// CHANGE-ID: 20260309_094500_Profile_AvatarBootstrapFallback
// SCOPE: Owner avatar bootstrap fallback in ProfileView only — prefer local avatar, fall back to remote avatar via existing pipeline when backendAvatarKey exists; avoid adding weight to modalsAndAlerts.
// SEARCH-TOKEN: 20260309_094500_Profile_AvatarBootstrapFallback

// CHANGE-ID: 20260228_214500_Profile_KeyboardCursorDismiss_FormTap
// SCOPE: UI-only — clear Name/Location/Account ID FocusState when tapping other cards/scrolling in Form; no other UI/logic changes.
// SEARCH-TOKEN: 20260228_214500_Profile_KeyboardCursorDismiss_FormTap

// CHANGE-ID: 20260228_231800_Profile_NameFields_FocusDismiss_Fix2
// SCOPE: UI-only — dismiss keyboard for Name/Location/Account ID fields on Return and on tap elsewhere; no other UI/logic changes.
// SEARCH-TOKEN: 20260228_230200_Profile_NameFields_FocusDismiss

// CHANGE-ID: 20260227_122600_PV_AccountCards_SplitSections_CompactDeleteFix
// SCOPE: UI-only — ProfileView: split Sign out and Delete account into separate Sections; make Delete card compact; no logic/strings changes.
// SEARCH-TOKEN: 20260227_122600_PV_AccountCards_SplitSections_CompactDeleteFix

// CHANGE-ID: 20260227_150500_PV_DeleteOutsideSignOutCard
// SCOPE: UI-only — ProfileView: move Delete account into its own card below Sign out; no logic changes.
// SEARCH-TOKEN: 20260227_150500_PV_DeleteOutsideSignOutCard

// CHANGE-ID: 20260227_123000_Profile_DeleteAccount_401Fix
// SCOPE: Delete Account — fix 401 by using functions domain + session preflight; no other UI/logic changes.
// SEARCH-TOKEN: 20260227_124200_DeleteAccount_InvalidJWT_Fix

// CHANGE-ID: 20260225_153600_PV_SignOutButtonSoftSurface_AlignAuthActions_1f6c2d
// SCOPE: ProfileView onboarding routing only — after signed-out Apple sign-in gate succeeds, suppress signed-in Profile form rendering and close the gate; no UI/auth/profile logic changes.
// SEARCH-TOKEN: 20260225_153600_PV_SignOutButtonSoftSurface_AlignAuthActions_1f6c2d

// CHANGE-ID: 20260227_115200_Profile_DeleteAccount_Action
// SCOPE: ProfileView — add Delete Account action (signed-in) + confirmation sheet; invokes Edge Function delete_account_v1; no other UI/logic changes.
// SEARCH-TOKEN: 20260227_115200_Profile_DeleteAccount_Action

// CHANGE-ID: 20260221_142658_FollowInfraFix_9f2c
// SCOPE: Follow infra hardening — enforce requests-off (account_directory), fix decline/remove follower delete semantics, add follower revoke swipe.
// SEARCH-TOKEN: 20260221_142658_FollowInfraFix_9f2c

// CHANGE-ID: 20260221_094021_PV_AuthUI_Simplify_d930d3
// SCOPE: UI-only — ProfileView account section simplification (remove Account header + UUID display; single auth action card)
// SEARCH-TOKEN: 20260221_094021_PV_AuthUI_Simplify_d930d3

// CHANGE-ID: 20260211_141746_PPV_Instruments_Writeback_PV_a3d9c1
// SCOPE: Sync local instruments to account_directory on instrument manager dismiss + include instruments in directory upsert fingerprint
// SEARCH-TOKEN: 20260211_141746_PPV_Instruments_Writeback_PV_a3d9c1

// CHANGE-ID: 20260210_190200_Phase15_Step3B_ProfileAvatarWire
// SCOPE: Phase 15 Step 3B — ProfileView: wire avatar editor Save/Clear to backend avatar upload + account_directory.avatar_key patch; bust remote avatar caches; owner local cache preserved.
// SEARCH-TOKEN: 20260210_190200_Phase15_Step3B_ProfileAvatarWire

// CHANGE-ID: 20260205_073900_LiveDirectorySync_LocationOnChange
// SCOPE: Live directory identity sync — trigger account_directory upsert when Location changes (debounced); no UI/layout changes.
// CHANGE-ID: 20260120_142900_Phase12C_CommitOnlyAccountID_BlurGuard
// CHANGE-ID: 20260121_132406_P13A_AccountIDCollisionUX
// SCOPE: Phase 13A — surface account_id collision (HTTP 409 / 23505) inline under Account ID field; no backend/schema changes.
// SCOPE: Phase 12C hygiene — commit-only directory upsert for Account ID; never POST invalid account_id (send null until valid)
// CHANGE-ID: 20260120_124300_Phase12C_ProfileView_DirectoryOptIn
// SCOPE: Phase 12C — per-backend-user lookup opt-in + account ID field; upsert account_directory using backendUserID; no profile sync.
////
 //  ProfileView.swift
 //  MOTIVO
 //
 //  [ROLLBACK ANCHOR] v7.8 Scope1 — pre-primary-activity (no primary activity selector; icons on manage rows; account at top)
// CHANGE-ID: 20260117_172700_Phase11B_PrivacyRows_MatchInstrumentGrammar
// SCOPE: Phase 11B visual-only — match Privacy & connection row grammar to Instruments/Activities (value+chevron adjacent; remove iOS blue)
// CHANGE-ID: 20260119_203800_IdentityScopeSignOut_Profile
// SCOPE: Correctness/hygiene — clear Profile UI state on sign-out; repopulate on sign-in; no UI/logic changes beyond identity gating
 //
 //  v7.8 Stage 2 — Primary fallback notice + live sync (kept)
 //  v7.8 DesignLite — visual polish only (headers/background/spacing).
 //  v7.8 DesignLite — tweak: Manage buttons placed above primary pickers and aligned to section edge.
 //
// CHANGE-ID: 20260205_065749_LocParity_d2c43ded
// SCOPE: Identity data parity — include optional location in directory sync fingerprint + upsertSelfRow call (owner updates push to account_directory).
// SEARCH-TOKEN: 20260205_065749_LocParity_d2c43ded

// CHANGE-ID: 20260221_150200_FollowInfraHardening_RequestsToggle_UX_b5a1
// SCOPE: Follow infra hardening — immediate backend sync for follow request mode + request rejection UX wiring (no redesign).
// SEARCH-TOKEN: 20260221_150200_FollowInfraHardening_TOKEN_b5a1


import StoreKit
import UIKit
 import SwiftUI
import DeclaredAgeRange
 import CoreData
import Foundation
 import AuthenticationServices
 #if canImport(PhotosUI)
 import PhotosUI
 #endif
 
// MARK: - Privacy Settings (local-first)

// CHANGE-ID: 20260129_121332_14_3H_B2_ProfileUpsertGate
// SCOPE: Phase 14.3H (B2) — Gate account_directory upsert on Supabase bearer token to avoid 401 during sign-in transition; no UI changes.
// SEARCH-TOKEN: 20260129_121332_14_3H_B2_ProfileUpsertGate

// NOTE: profileVisibility_v1 is retained for legacy compatibility, but is not surfaced in UI.

fileprivate enum FollowRequestMode: Int, CaseIterable, Identifiable {
    case autoApproveContacts = 0
    case manual = 1
    case closed = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .autoApproveContacts: return "Approve follow requests" // legacy mapping
        case .manual:              return "Approve follow requests"
        case .closed:              return "Not accepting requests"
        }
    }
}

fileprivate enum DiscoveryMode: Int, CaseIterable, Identifiable {
    case none = 0
    case search = 1
    case contacts = 2 // stored for forward compatibility; hidden from UI until implemented
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none:     return "Lookup off"
        case .search:   return "Allow people to find me"
        case .contacts: return "Email invites"
        }
    }
}

// MARK: - C-70 owner-maintenance policy and local draft state

/// **C-70. The two decisions this unit turns on, as PURE VALUES.**
///
/// They live outside the `View` deliberately. Both were previously expressed as
/// `appModeManager.canShowConnectedAccountManagement`, which is `mode ==
/// .connected` and therefore folds in `isEntitled` — so a lapsed member holding
/// a real Connected account could neither publish owner maintenance nor even see
/// whether it had failed. That is C-35's shape, and the correction is the one
/// C-35 already made for account deletion in this same file: **gate on IDENTITY
/// and CONFIGURATION, never on `AppMode`.**
///
/// **Settled owner-maintenance policy exposed consistently — NOT a new membership
/// rule.** D-U6-3 has always intended the owner to be able to maintain their
/// existing directory row, and `account_directory_update_owner` carries no gate.
/// Creation stays gated and stays the SERVER's decision; automatic handle
/// generation stays Connected-only.
enum ProfileMaintenancePolicy {

    /// May this device attempt an owner directory write at all?
    /// Deliberately not a mode check and not a membership check.
    static func mayAttemptRemoteMaintenance(hasConnectedIdentity: Bool,
                                            isBackendConfigured: Bool,
                                            hasAccessToken: Bool,
                                            backendUserID: String?) -> Bool {
        guard hasConnectedIdentity, isBackendConfigured, hasAccessToken else { return false }
        guard let id = backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return false }
        return true
    }

    /// May the profile-maintenance surface — the sync message and the Account ID
    /// editor — be shown?
    ///
    /// **Narrower than general Connected account management on purpose.** It must
    /// not unlock the feed, access, or the rest of the Connected section.
    ///
    /// **It now gates the maintenance FEEDBACK surface rather than a field.** The
    /// Account ID field this was written for is gone with the handle; what
    /// remains behind this policy is the directory-sync message, and the reason
    /// it must not fold in `AppMode` is unchanged — a lapsed member maintaining
    /// an existing Connected profile has to be able to see whether the publish
    /// failed. Gate on IDENTITY and CONFIGURATION, never on `AppMode` (C-35).
    static func mayShowMaintenanceSurface(hasConnectedIdentity: Bool,
                                          isBackendConfigured: Bool) -> Bool {
        hasConnectedIdentity && isBackendConfigured
    }
}

/// **F2. Whether a refused directory write should be attempted once more.**
///
/// Pure, and outside the view, for the same reason `ProfileMaintenancePolicy` and
/// `ConnectedSetupDecision` are: a decision inside a `View` can only be tested by
/// rendering one, and nothing in this target renders.
///
/// **Consulted at BOTH events, because either can arrive first.** Keying only on
/// the arrival of an establishing completion misses the SUCCESS-BEFORE-FAILURE
/// order: the completion lands while nothing is outstanding, correctly writes
/// nothing, and the already-dispatched write's refusal then arrives with no
/// further completion to retrigger anything. So the failure side asks too.
///
/// **The completion is a HINT, never authority.** A true answer schedules one
/// ordinary directory write, which the server judges exactly as it judges every
/// other. Nothing here grants entitlement, and nothing here decides the message:
/// the WRITE sets and clears that, so a still-refused retry tells the member so
/// again, truthfully.
enum DirectoryReconciliationPolicy {

    /// True only when ALL SIX hold. Each is load-bearing:
    ///
    /// 1. a completion exists;
    /// 2. it ESTABLISHES membership — `pending` is propagation, not success, and
    ///    a reconciliation on it would write straight into the same refusal;
    /// 3. the owner matches;
    /// 4. the DIRECTORY GENERATION matches — this is what proves ownership, and
    ///    why an owner check alone is insufficient: an A→B→A cycle leaves the
    ///    owner equal to A again while the completion belongs to the previous A;
    /// 5. this completion has not already been consumed — the boundedness rule;
    ///
    /// and then EITHER a directory failure is outstanding (the repair path) OR
    /// this session has scoped evidence that the row is absent and none that it
    /// has been written (the initial-publication path).
    ///
    /// **CORRECTED FOR F3.** An earlier revision made an outstanding failure a
    /// precondition of all six, on the reasoning that "with none, there is
    /// nothing to reconcile". **That is exactly false for a fresh join**, which
    /// leaves no message to repair, and it is the defect F3 exists to fix. What
    /// the old rule was protecting — `alreadyEstablished` on every foreground
    /// costing nothing — is now carried by the absence evidence instead, which a
    /// member whose row already exists does not have.
    /// A write already evidenced by this screen, scoped so it cannot be mistaken
    /// for a different session's success.
    struct AppliedEvidence: Equatable {
        let owner: String
        let directoryGeneration: Int
    }

    static func shouldReconcile(completion: MembershipAttestationCoordinator.AttestationCompletion?,
                                hasOutstandingFailure: Bool,
                                rowAbsence: AuthManager.DirectoryRowAbsence?,
                                appliedEvidence: AppliedEvidence?,
                                currentOwner: String?,
                                currentDirectoryGeneration: Int,
                                lastConsumedSequence: Int?) -> Bool {
        guard let completion else { return false }
        guard completion.establishesMembership else { return false }
        guard let owner = currentOwner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !owner.isEmpty,
              owner == completion.owner else { return false }
        guard completion.directoryGeneration == currentDirectoryGeneration else { return false }
        guard completion.sequence != lastConsumedSequence else { return false }

        // The REPAIR path, unchanged: a refusal this screen showed.
        if hasOutstandingFailure { return true }

        // **F3 — INITIAL PUBLICATION WITH NO FOREGROUND ERROR.** A fresh join can
        // leave no message to repair at all.
        //
        // The SUPPORTED account is that with the join flow now kept on screen
        // (F1), the fields this screen syncs on were already assigned before the
        // identity arrived, so nothing changed and nothing was scheduled. **That
        // is read from source, not from captured device history** — no
        // request-level trace exists for the run that failed, and a silent
        // screen is also consistent with a superseded or not-permitted path.
        // What is measured is that the row was absent while Profile stayed open.
        //
        // Both scopes must describe THIS session. An absence from a previous
        // generation authorises nothing, and applied evidence from a previous
        // one does not suppress. Neither is a permission: the server judges the
        // resulting write exactly as it judges any other, and its band and
        // membership refusals are reported unchanged.
        let absenceIsCurrent = rowAbsence.map {
            $0.owner == owner && $0.directoryGeneration == currentDirectoryGeneration
        } ?? false
        let alreadyWritten = appliedEvidence.map {
            $0.owner == owner && $0.directoryGeneration == currentDirectoryGeneration
        } ?? false
        return absenceIsCurrent && !alreadyWritten
    }
}

/// **F3. The per-screen state the four triggers share, and the code the VIEW
/// ITSELF runs** — so a test can drive the production evaluation rather than a
/// reimplementation of it.
///
/// **It does NOT prove the observers are wired.** That is a separate, structural
/// assertion; a test driving this type would pass even if every `onChange` were
/// deleted, which is exactly why both exist.
@MainActor
final class DirectoryReconciliationEvaluator {
    private(set) var lastConsumedSequence: Int?
    private(set) var appliedEvidence: DirectoryReconciliationPolicy.AppliedEvidence?

    /// Ask, and CONSUME on a true answer — before the caller schedules anything,
    /// so a retry that is refused again cannot find the completion unspent.
    func evaluateAndConsume(completion: MembershipAttestationCoordinator.AttestationCompletion?,
                            hasOutstandingFailure: Bool,
                            rowAbsence: AuthManager.DirectoryRowAbsence?,
                            currentOwner: String?,
                            currentDirectoryGeneration: Int) -> Bool {
        guard DirectoryReconciliationPolicy.shouldReconcile(
                completion: completion,
                hasOutstandingFailure: hasOutstandingFailure,
                rowAbsence: rowAbsence,
                appliedEvidence: appliedEvidence,
                currentOwner: currentOwner,
                currentDirectoryGeneration: currentDirectoryGeneration,
                lastConsumedSequence: lastConsumedSequence)
        else { return false }
        lastConsumedSequence = completion?.sequence
        return true
    }

    /// Recorded ONLY from an accepted write's own result, never re-read from the
    /// coordinator afterwards: `result.generation` is the epoch the writer bound,
    /// and the acceptance guards have already passed by the time this is called.
    func noteApplied(owner: String?, generation: Int) {
        guard let owner = owner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !owner.isEmpty else { return }
        appliedEvidence = .init(owner: owner, directoryGeneration: generation)
    }
}

/// **C-70. The local-first gate — SYNCHRONOUS, and named for what it decides.**
///
/// `syncDirectoryFromCurrentState` calls exactly this before it captures the
/// owner and the snapshot. It commits locally and then reports whether remote
/// work is PERMITTED; it does not perform the publish and never claims to.
///
/// **It is deliberately synchronous.** An `async` version would introduce a new
/// suspension between the local commit and the capture of owner, generation and
/// snapshot — across which an identity change or a newer unsaved edit could slip,
/// so a value the member has already moved on from could be published. Adding a
/// seam must not weaken the thing the seam exists to protect.
///
/// **And it takes the real effects.** Passing a no-op to make a testable pipeline
/// appear used would be worse than no seam at all: the test would pass while
/// production ran a different order.
enum ProfileMaintenanceGate {
    enum Decision: Equatable {
        /// The local commit failed, so nothing may be published.
        case blockedByLocalFailure
        /// Committed locally; remote work is not permitted (Solo, no identity…).
        case localOnly
        /// Committed locally and remote work is permitted.
        case remotePermitted
    }

    static func decide(commitLocally: () -> Result<Void, Error>,
                       mayAttemptRemote: () -> Bool) -> Decision {
        guard case .success = commitLocally() else { return .blockedByLocalFailure }
        return mayAttemptRemote() ? .remotePermitted : .localOnly
    }
}

/// **C-70. May this view still touch local storage?**
///
/// Extracted because the interesting case is precisely the one a single boolean
/// hides: a reset whose global `isInProgress` flag has ALREADY been cleared by
/// its own `defer`, while this view is still the erased one. `.onDisappear` and
/// a late `onChange` both arrive in that window.
enum ProfileLocalStorageGate {
    static func isUsable(viewInvalidatedByReset: Bool, resetInProgress: Bool) -> Bool {
        !viewInvalidatedByReset && !resetInProgress
    }
}

/// **C-70. Pre-submit staleness.**
///
/// Captured when work is SCHEDULED and rechecked before any local or remote
/// effect. `DirectoryWriteCoordinator` owns a write only after submission, so
/// this window has no other guard. Cancellation is cooperative and cannot be
/// relied on alone.
struct ProfilePreSubmitToken: Equatable {
    let owner: String?
    let generation: Int

    func isStillCurrent(owner: String?, generation: Int) -> Bool {
        self.owner == owner && self.generation == generation
    }
}

/// **C-70. Whether the newest local name edit is safe to overwrite by hydration.**
///
/// MEASURED, not assumed — `docs/phase-6-c70-remaining-gaps-scope-2026-09-20.md`
/// §2.6. The draft lives in view state and only reaches the managed object inside
/// `save()`, so between a keystroke and the next save the stored value is stale —
/// and `load()` is reached by ANY save on the shared context, not just this
/// screen's. **Every edit reopens that window; it is not opened once.**
///
/// A failed save does NOT post `NSManagedObjectContextDidSave` (M1), and after a
/// save attempt the managed object already carries the text (M2) — but only until
/// the next keystroke, which is why this tracks the NEWEST draft rather than
/// "whether a save has ever run".
struct ProfileNameDraftState: Equatable {
    /// True when the newest edit has not yet been EVIDENCED as saved.
    private(set) var isDirty: Bool = false

    mutating func edited() { isDirty = true }

    /// Cleared on evidenced success ONLY — never optimistically on the attempt,
    /// so the in-flight window neither clears the flag nor permits hydration.
    mutating func evidencedSaved() { isDirty = false }

    /// **Factory reset is the explicit exception to draft retention.** The draft
    /// is dropped and must not be resurrected afterwards.
    mutating func invalidateForFactoryReset() { isDirty = false }

    /// Hydration may assign only when no newer unsaved edit exists.
    var mayHydrate: Bool { !isDirty }
}

 struct ProfileView: View {
     @Environment(\.managedObjectContext) private var ctx
     @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appModeManager: AppModeManager
    /// F2. Read for its COMPLETION HINT only. Never consulted for entitlement,
    /// mode or access — those resolve exactly where they always did.
    @EnvironmentObject private var attestation: MembershipAttestationCoordinator
    /// Already injected app-wide — `MembershipSelectionView`, presented from this
    /// screen, resolves the same object.
    @EnvironmentObject private var membershipStore: ConnectedMembershipStore
    /// F2/F3. The per-screen reconciliation state: the spent completion and the
    /// write this screen has evidenced. **Boundedness**: a still-refused retry
    /// cannot re-trigger itself, because the completion that authorised it is
    /// spent.
    ///
    /// **`@State`, so it RESETS ON REMOUNT — stated rather than glossed.** This
    /// scope therefore does NOT promise zero writes across arbitrary reopens of
    /// Profile while absence evidence is still standing: each fresh mount may
    /// publish once more. That is bounded by a deliberate user action, never by
    /// a timer, and it stops entirely once a write is evidenced within a mount.
    @State private var reconciliation = DirectoryReconciliationEvaluator()
    @Environment(\.colorScheme) private var colorScheme
 
     // Close-first strategy
     var onClose: (() -> Void)? = nil

     /// C-49: how the presenter returns the app to its home route after a
     /// SUCCESSFUL erase, and only then.
     ///
     /// Passed in rather than read from the environment deliberately. Each
     /// presenter already owns the router and knows what "home" means for its
     /// own presentation, and an `@EnvironmentObject` here would add a runtime
     /// dependency — one that traps only when the body evaluates, on a screen
     /// that leads to account deletion — in exchange for nothing this closure
     /// does not already give, compile-checked, at both call sites.
     var onEraseComplete: (() -> Void)? = nil
 
     @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
     private var instruments: FetchedResults<Instrument>
 
     @State private var name: String = ""
     @State private var primaryInstrumentName: String = ""
     @State private var defaultPrivacy: Bool = false

     @AppStorage("appSettings_showDroneStrip") private var showDroneStrip: Bool = true
     @AppStorage("appSettings_showMetronomeStrip") private var showMetronomeStrip: Bool = true
     @AppStorage("appSettings_showTasksPad") private var showTasksPad: Bool = true
    @AppStorage("appSettings_showScores") private var showScores: Bool = true
    @AppStorage("appSettings_showThreadSuggestions") private var showThreadSuggestions: Bool = true
    @AppStorage("appSettings_showTuner") private var showTuner: Bool = true
    @AppStorage("appSettings_tintMode") private var tintModeRaw: String = Theme.TintMode.auto.rawValue

@FocusState private var isNameFocused: Bool
@FocusState private var isLocationFocused: Bool
 
     @State private var showInstrumentManager: Bool = false

    private func clearNameFieldFocus() {
        isNameFocused = false
        isLocationFocused = false
    }

     @State private var showActivityManager: Bool = false
     @State private var showTasksManager: Bool = false
     @State private var profile: Profile?
 
 
     // Identity MVP additions
     @State private var avatarImage: UIImage? = nil
    @State private var avatarSyncErrorMessage: String? = nil
    @State private var showAvatarSyncErrorAlert: Bool = false
    @State private var avatarSyncInFlight: Bool = false
    @State private var avatarRefreshTask: Task<Void, Never>? = nil


    // CHANGE-ID: 20260227_114900_DeleteAccount_UIHook
    // SCOPE: ProfileView — add Delete Account UI + confirmation sheet (calls Edge Function delete_account_v1); no other UI/logic changes.
    // SEARCH-TOKEN: 20260227_114900_DeleteAccount_UIHook
    @State private var showDeleteAccountSheet: Bool = false
    // C-44: set ONLY by the explicit DELETE action, consumed by the sheet's
    // onDismiss before the workflow starts. See both sites for why.
    @State private var pendingDeletionConfirmed: Bool = false
    @State private var deleteAccountConfirmText: String = ""
    @State private var deleteAccountInFlight: Bool = false
    @State private var deleteAccountErrorMessage: String? = nil
    @State private var showDeleteAccountErrorAlert: Bool = false

     @State private var showPhotoPicker: Bool = false
     @State private var locationText: String = ""
 
     // Primary Activity (Stage 1 persisted in AppStorage; Stage 2 UX hardening)
     // Format: "core:<raw>" or "custom:<name>"
     @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"
     @State private var userActivities: [UserActivity] = []
     @State private var primaryActivityChoice: String = "core:0" // mirrors picker; same tag format
 
     // Stage 2: one-time notice flag (set in ActivityListView on fallback)
     @AppStorage("primaryActivityFallbackNoticeNeeded") private var primaryFallbackNoticeNeeded: Bool = false
     @State private var showPrimaryFallbackAlert: Bool = false
     @State private var showSupportMailFallback: Bool = false
 
     
    // Privacy & Discovery (local-first; future-sync to backend)
    // NOTE: profileVisibility_v1 is retained for legacy compatibility, but is not surfaced in UI.
    @AppStorage("profileVisibility_v1") private var profileVisibilityRaw: Int = 1
    @AppStorage("followRequestMode_v1") private var followRequestModeRaw: Int = FollowRequestMode.manual.rawValue
    @AppStorage("allowDiscovery_v1") private var allowDiscoveryLegacyRaw: Int = DiscoveryMode.none.rawValue
    @State private var discoveryModeRawPerUser: Int = DiscoveryMode.none.rawValue

    // Phase 13A — Account ID collision UX (shipping)
    @State private var directorySyncMessage: String? = nil
    @State private var directorySyncIsError: Bool = false

    @State private var directorySyncDebounceTask: Task<Void, Never>? = nil
    /// C-70. Not a bare fingerprint: see `DirectorySyncLatch` for the A→B→A
    /// revert this shape exists to stop losing.
    @State private var directorySyncLatch = DirectorySyncLatch()
    /// C-70. The newest local name edit, and whether it is safe to hydrate over.
    @Environment(\.scenePhase) private var scenePhase
    /// C-70. **View-lifetime invalidation, set BEFORE a factory reset starts.**
    ///
    /// `LocalFactoryReset.isInProgress` is not sufficient on its own: a local-only
    /// reset need not involve an identity transition, and `.onDisappear` runs
    /// AFTER `isInProgress` has returned to false — at which point
    /// `persistProfileEdits()` would re-create, through `ProfileStore.setLocation`
    /// and `ctx.save()`, the very text the reset just erased. Once this is set it
    /// is never cleared for the lifetime of this view.
    @State private var viewInvalidatedByReset = false
    @State private var nameDraft = ProfileNameDraftState()
    /// C-70. Local-save failure. DELIBERATELY SEPARATE from `directorySyncMessage`,
    /// which concerns the REMOTE write — conflating them would re-create exactly
    /// the false attribution C-70(a) removed.
    @State private var localSaveMessage: String? = nil
    private var followRequestMode: FollowRequestMode {
        get {
            let mode = FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual
            // Map legacy auto-approve to manual (Motivo never auto-approves follows).
            return mode == .autoApproveContacts ? .manual : mode
        }
        set { followRequestModeRaw = newValue.rawValue }
    }
    private var discoveryMode: DiscoveryMode {
        get { DiscoveryMode(rawValue: discoveryModeRawPerUser) ?? .none }
        set { discoveryModeRawPerUser = newValue.rawValue }
    }
     // New state for avatar editor sheet
     @State private var showAvatarEditor: Bool = false
     @State private var showAboutEtudes: Bool = false
     @State private var showConnectedIntroduction: Bool = false
     @State private var showMembershipSelection: Bool = false
     @State private var showConnectedSignInSheet: Bool = false

     /// U5f — WHY THE SIGN-IN SHEET NOW NEEDS AN INTENT.
     ///
     /// Sign in with Apple is presented from two places that want opposite things
     /// afterwards. A RETURNING member signing in is finished, and the stack
     /// unwinds. A member JOINING must be carried ON to the paywall, because
     /// under B-24 authentication is now a PREREQUISITE of purchase rather than
     /// something that follows it — the binding token has to exist before
     /// `product.purchase()` can carry it.
     ///
     /// One mechanism, not two: the same sheet, the same `AuthManager`, the same
     /// credential. Only what happens on completion differs.
     private enum ConnectedSignInIntent { case returning, join }
     @State private var connectedSignInIntent: ConnectedSignInIntent = .returning
     /// Apple's system age-range request. Études never asks the member their age;
     /// Apple presents its own sheet and returns a RANGE.
     @Environment(\.requestAgeRange) private var requestAgeRange
     @State private var ageRangeRefusedNotice: String?
     /// Mirrors the server's EFFECTIVE discoverability. Protective when unknown.
     @State private var discoverabilityOn: Bool = false
     @State private var discoverabilityBusy: Bool = false
     @State private var discoverabilityNotice: String?
     @State private var showTintModeSelection: Bool = false
    @State private var signedOutGateWasVisible: Bool = false
 

    private var connectedIntroduction: some View {
        ConnectedIntroductionView(
            onSignIn: {
                connectedSignInIntent = .returning
                showConnectedSignInSheet = true
            },
            onContinue: {
                // CP-3: Apple's declared age range is requested BEFORE
                // Sign in with Apple, so an ineligible or undisclosed
                // result turns the member away WITHOUT minting an
                // identity that would then need deleting. The band is
                // held in memory only until an identity exists.
                Task { @MainActor in
                    switch await requestDeclaredAgeRange() {
                    case .band(let band):
                        auth.pendingAgeBand = band
                        continueToConnectedJoin()
                    case .ineligible:
                        ageRangeRefusedNotice = "Études Connected is for ages 13 and over."
                    case .unavailable:
                        ageRangeRefusedNotice = "Études needs Apple to share your age range before Connected can be set up. You can change this in Settings, under your Apple Account."
                    }
                }
            }
        )
        .alert("Connected isn’t available",
               isPresented: Binding(get: { ageRangeRefusedNotice != nil },
                                    set: { if !$0 { ageRangeRefusedNotice = nil } })) {
            Button("OK", role: .cancel) { ageRangeRefusedNotice = nil }
        } message: {
            Text(ageRangeRefusedNotice ?? "")
        }
    }

    private var shouldSuppressSignedInProfileAfterGateSignIn: Bool {
        signedOutGateWasVisible && auth.currentUserID != nil && onClose != nil
    }

     var body: some View {
         modalsAndAlerts(
             NavigationStack {
                ZStack {
                    if shouldSuppressSignedInProfileAfterGateSignIn {
                        Color.clear
                    } else {
                        Form {
                     Group {
                         profileSection
                         sessionSetupSection
                         connectedPreferencesSection
                     }
                     Group {
                         if appModeManager.canShowConnectedAccountManagement {
                             appSettingsSection
                         } else {
                             connectedPromoSection
                         }
                     }
                     buildInfoFooter
                        }
                        .background(KeyboardDismissFormTapCatcher(onDismiss: {
                            clearNameFieldFocus()
                        }))
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                            clearNameFieldFocus()
                        })
                    }
                }
                .font(.callout)
                .navigationTitle("")
                .toolbar {
                     toolbarContent
                }
                .navigationDestination(isPresented: $showAboutEtudes) {
                    AboutEtudesView { connectedIntroduction }
                }
                .navigationDestination(isPresented: $showConnectedIntroduction) {
                    connectedIntroduction
                }
                .navigationDestination(isPresented: $showMembershipSelection) {
                    MembershipSelectionView(
                        onAuthenticationRequired: {
                            // DEFENSIVE ONLY since U5f. Authentication now happens
                            // before this screen is reachable, so this fires only
                            // if the identity disappeared underneath us.
                            connectedSignInIntent = .join
                            showMembershipSelection = false
                            showConnectedSignInSheet = true
                        },
                        onJoinComplete: {
                            // The purchase completed. Unwind to Profile and let
                            // AppMode activation resolve from local StoreKit
                            // exactly as it always has -- attestation informs the
                            // SERVER and never decides the client's UI.
                            showMembershipSelection = false
                            showConnectedIntroduction = false
                            showAboutEtudes = false
                        }
                    )
                }
                .navigationDestination(isPresented: $showTintModeSelection) {
                    TintModeSelectionView()
                }
                .sheet(isPresented: $showConnectedSignInSheet, onDismiss: {
                    if auth.currentUserID == nil {
                        signedOutGateWasVisible = false
                    }
                }) {
                    signedOutGateView
                }
                .appBackground()
            }
                .navigationBarBackButtonHidden(true)
         )
     }
 
     

#if canImport(UIKit)
private struct KeyboardDismissFormTapCatcher: UIViewRepresentable {
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = true
        // Installation onto the Form/List backing view happens in updateUIView once we're in the hierarchy.
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.installIfNeeded(from: uiView)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: (() -> Void)?
        private weak var installedOnView: UIView?
        private weak var gesture: UITapGestureRecognizer?

        init(onDismiss: (() -> Void)?) {
            self.onDismiss = onDismiss
        }

        func installIfNeeded(from host: UIView) {
            // Find the nearest scroll/table backing view (Form/List is typically a UITableView).
            let target = nearestScrollOrTable(from: host)
            guard let target else { return }

            if installedOnView === target { return }

            // Remove from old target if needed.
            if let old = installedOnView, let g = gesture {
                old.removeGestureRecognizer(g)
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self

            target.addGestureRecognizer(tap)
            installedOnView = target
            gesture = tap
        }

        @objc private func handleTap() {
            onDismiss?()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }

        // Allow taps everywhere except taps that begin inside a text input.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let v = touch.view else { return true }
            if isTextInputOrInsideTextInput(v) { return false }
            return true
        }

        private func isTextInputOrInsideTextInput(_ view: UIView) -> Bool {
            var current: UIView? = view
            while let v = current {
                if v is UITextField || v is UITextView { return true }
                current = v.superview
            }
            return false
        }

        private func nearestScrollOrTable(from view: UIView) -> UIView? {
            var current: UIView? = view
            while let v = current {
                if v is UITableView { return v }
                if v is UIScrollView { return v }
                current = v.superview
            }
            return nil
        }
    }
}
#endif

    // MARK: - Signed-out gate

    private var signedOutGateView: some View {
        GeometryReader { geo in
            VStack {
                Spacer().frame(height: geo.size.height * 0.30)

                SignInWithAppleButton(.signIn) { request in
                    auth.configure(request)
                } onCompletion: { result in
                    auth.handle(result)
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 52)
                .frame(maxWidth: 360)
                .background(Theme.Colors.surface(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                // Mask the built-in outline stroke so the button reads as a soft surface chip.
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.surface(colorScheme), lineWidth: 2)
                )
                .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.Spacing.l)
            .onAppear {
                signedOutGateWasVisible = true
            }
        }
    }

    


// MARK: - Sections

     private var profileSection: some View {
         Section(header: Text("Profile").sectionHeader()) {
             VStack(alignment: .leading, spacing: 2) {
                 VStack(spacing: 0) {
                     HStack(spacing: 12) {
                         Button { showAvatarEditor = true } label: { avatarChip }
                             .buttonStyle(.plain)
                             .disabled(false)
                             .task(id: avatarRefreshTrigger) {
                                 await MainActor.run {
                                     refreshAvatarDisplay()
                                 }
                             }

                         TextField("Name", text: nameEditingBinding)
                             .textInputAutocapitalization(.words)
                             .disableAutocorrection(true)
                             .focused($isNameFocused)
                             .onSubmit { isNameFocused = false }
                             // C-70. Blur is a commit point, not the only one:
                             // a member can pause while STILL FOCUSED, which is
                             // why the debounced path commits locally too.
                             .onChange(of: isNameFocused) { was, now in
                                 if was && !now { persistProfileEdits() }
                             }
                             .scaleEffect(isNameFocused ? 0.995 : 1)
                             .overlay(alignment: .bottomLeading) {
                                 Rectangle().frame(height: 1).opacity(isNameFocused ? 0.15 : 0)
                             }
                             .animation(.easeInOut(duration: 0.18), value: isNameFocused)
                     }
                     .padding(.vertical, Theme.Spacing.s)
                     .frame(minHeight: 44, alignment: .center)
                     .overlay(alignment: .bottom) {
                         quietDivider()
                     }

                     HStack(spacing: 10) {
                         if !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                             Image(systemName: "globe")
                                 .font(.system(size: 13, weight: .medium))
                                 .foregroundStyle(Theme.Colors.secondaryText)
                         }

                         TextField("Location (optional)", text: $locationText)
                             .textInputAutocapitalization(.words)
                             .disableAutocorrection(true)
                             .focused($isLocationFocused)
                             .onSubmit { isLocationFocused = false }
                             .onChange(of: isLocationFocused) { was, now in
                                 if was && !now { persistProfileEdits() }
                             }
                     }
                     .padding(.vertical, Theme.Spacing.s)
                     .frame(minHeight: 44, alignment: .center)
                     .overlay(alignment: .bottom) {
                         quietDivider()
                     }

                 }
                 .cardSurface(padding: profileInnerCardPadding)

                 // C-70. The LOCAL save failure, on its own surface. It is shown
                 // regardless of Connected state, because the local record is the
                 // account-free one and its failure concerns every member.
                 if let localMsg = localSaveMessage {
                     HStack(spacing: 8) {
                         Text(localMsg)
                             .font(Theme.Text.meta)
                             .foregroundStyle(Color.red)
                         // C-70. "Try again" must be ACTIONABLE. The retry goes
                         // through the SAME local-first path as every other
                         // commit point, so a success clears the message, marks
                         // the draft evidenced-saved and — only then — lets the
                         // remote publish proceed.
                         Button("Retry") {
                             submitDirectorySyncNow()
                         }
                         .font(Theme.Text.meta)
                         .foregroundStyle(Theme.Colors.accent)
                         .accessibilityLabel("Retry saving your profile")
                     }
                     .padding(.top, 2)
                 }

                 if mayShowMaintenanceSurface, let msg = directorySyncMessage {
                     Text(msg)
                         .font(Theme.Text.meta)
                         .foregroundStyle(directorySyncIsError ? Color.red : Theme.Colors.secondaryText)
                         .padding(.top, 2)
                 }
             }
         }
         .listRowSeparator(.hidden)
                .padding(.vertical, profileSectionSpacing / 2)
     }


private var sessionSetupSection: some View {
         Section(header: Text("Settings").sectionHeader()) {
             VStack(spacing: 0) {
                 Button { showInstrumentManager = true } label: {
                     navigationRow(title: "Instruments")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Button { showActivityManager = true } label: {
                     navigationRow(title: "Activities")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }


                 Button { showTintModeSelection = true } label: {
                     navigationRow(title: "Journal Tint", value: currentTintMode.displayName)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Button { showTasksManager = true } label: {
                     navigationRow(title: "Lists")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Toggle(isOn: $showMetronomeStrip) {
                     Text("Show Metronome")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Toggle(isOn: $showDroneStrip) {
                     Text("Show Drone")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Toggle(isOn: $showTasksPad) {
                     Text("Show Lists Pad")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Toggle(isOn: $showScores) {
                     Text("Show Scores")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Toggle(isOn: $showThreadSuggestions) {
                     Text("Show Thread Suggestions")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }


                 Toggle(isOn: $showTuner) {
                     Text("Show Tuner")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
             }
             .cardSurface(padding: profileInnerCardPadding)
             .listRowSeparator(.hidden)
                .padding(.vertical, profileSectionSpacing / 2)
         }
     }

     // H-1: these Connected preferences used to sit in the MIDDLE of Settings,
     // between Activities and Journal Tint. Same controls, same bindings, same
     // writers, same visibility rules — only the grouping changed.
     //
     // The header is "Connected", deliberately NOT "Privacy": these are
     // membership-scoped preferences, and "Privacy" would imply a scope they do
     // not have.
     //
     // It renders ONLY under `canShowConnectedAccountManagement`, which is the
     // gate that already wrapped both controls, so Solo shows no empty
     // "Connected" header. The discovery control keeps its own NESTED
     // `accountPrivacyState != nil` condition: without a server age band the
     // writer would refuse and the control could not work.
     @ViewBuilder
     private var connectedPreferencesSection: some View {
         if appModeManager.canShowConnectedAccountManagement {
             Section(header: Text("Connected").sectionHeader()) {
                 VStack(spacing: 0) {
                 VStack(alignment: .leading, spacing: 4) {
                     Toggle("Default to Private Posts", isOn: $defaultPrivacy)
                        .tint(Theme.Colors.accent)
                        .frame(minHeight: 44, alignment: .center)
                        .font(Theme.Text.body)

                     // D-1: the default is ON for sharing, and nothing said so.
                     // Describes what the toggle does, without overstating --
                     // Thoughts START private but remain shareable by choice.
                     Text("When on, new sessions start private. Thoughts are always private by default. You can change sharing for each session.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                 }
                 .padding(.vertical, Theme.Spacing.s)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 // CP-3: the discoverability preference, written through the ONLY
                 // client writer of it. Shown only once the server holds an age
                 // band -- without one the member is undiscoverable anyway and the
                 // writer would refuse, so offering a control here would be
                 // offering one that cannot work.
                 if auth.accountPrivacyState != nil {
                     VStack(alignment: .leading, spacing: 4) {
                         Toggle("Let other members find you", isOn: $discoverabilityOn)
                            .tint(Theme.Colors.accent)
                            .frame(minHeight: 44, alignment: .center)
                            .font(Theme.Text.body)
                            .disabled(discoverabilityBusy)
                            .onChange(of: discoverabilityOn) { oldValue, newValue in
                                guard oldValue != newValue else { return }
                                Task { @MainActor in await applyDiscoverability(newValue) }
                            }

                         // Neutral and factual: what each position does, and what
                         // does NOT change either way. No recommendation and no
                         // nudge in either direction.
                         Text("When this is on, other members can find you by searching your name or instrument. When it’s off, you won’t appear in search. People you already share with can still see your name on anything you’ve shared.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                     }
                     .padding(.vertical, Theme.Spacing.s)
                     .overlay(alignment: .bottom) {
                         quietDivider()
                     }
                 }
                 }
                 .cardSurface(padding: profileInnerCardPadding)
                 .listRowSeparator(.hidden)
                 .padding(.vertical, profileSectionSpacing / 2)
             }
         }
     }

     private var connectedPromoSection: some View {
         Section(header: Text("Account").sectionHeader()) {
             VStack(spacing: 0) {
                 Button { showConnectedIntroduction = true } label: {
                     navigationRow(title: "Explore Connected")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Button { showAboutEtudes = true } label: {
                     navigationRow(title: "About Études")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 // Guideline 1.2: published contact details. With no mail app,
                 // the address is copied and shown instead.
                 Button {
                     Task {
                         if !(await ModerationMail.open(ModerationMail.supportURL)) {
                             ModerationMail.copySupportAddress()
                             showSupportMailFallback = true
                         }
                     }
                 } label: {
                     navigationRow(title: "Contact Support")
                 }
                 .alert("Contact Support", isPresented: $showSupportMailFallback) {
                     Button("OK", role: .cancel) {}
                 } message: {
                     Text(ModerationMail.noMailMessage)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 legalLinkRows

                 eraseAllEtudesDataButton
             }
             .cardSurface(padding: profileInnerCardPadding)
             .listRowSeparator(.hidden)
                .padding(.vertical, profileSectionSpacing / 2)
         }
     }

     /// The renewal summary, and the near-expiry notice when it applies.
     @ViewBuilder
     private var membershipPeriodRows: some View {
         let summary = ConnectedRenewalPresentation.periodEndSummary(
             periodEnd: membershipStore.currentPeriodEndDate,
             isFreeTrial: membershipStore.isInFreeTrialPeriod)
         let notice = ConnectedRenewalPresentation.notice(
             periodEnd: membershipStore.currentPeriodEndDate,
             isFreeTrial: membershipStore.isInFreeTrialPeriod)

         if summary != nil || notice != .none {
             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                 if let summary {
                     Text(summary)
                         .font(Theme.Text.body)
                         .foregroundStyle(.primary)
                 }
                 switch notice {
                 case .none:
                     EmptyView()
                 case let .periodEnding(text):
                     Text(text)
                         .font(Theme.Text.meta)
                         .foregroundStyle(Theme.Colors.secondaryText)
                         .fixedSize(horizontal: false, vertical: true)
                 }
             }
             .frame(maxWidth: .infinity, alignment: .leading)
             .padding(.vertical, Theme.Spacing.s)
             .overlay(alignment: .bottom) { quietDivider() }
         }
     }

     @ViewBuilder
     private var appSettingsSection: some View {
         Section(header: Text("Account").sectionHeader()) {
             VStack(spacing: 0) {
                 // FOUNDING 500. The end date is always answerable, and in the
                 // last month it says plainly that payment follows. In-app rather
                 // than a notification: the app schedules none, and promising a
                 // delivery we cannot make would be worse than showing it where
                 // the member already manages their membership.
                 membershipPeriodRows

                 Button {
                     Task {
                         await openManageMembership()
                     }
                 } label: {
                     navigationRow(title: "Manage Membership")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 Button { showAboutEtudes = true } label: {
                     navigationRow(title: "About Études")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 // Guideline 1.2: published contact details. With no mail app,
                 // the address is copied and shown instead.
                 Button {
                     Task {
                         if !(await ModerationMail.open(ModerationMail.supportURL)) {
                             ModerationMail.copySupportAddress()
                             showSupportMailFallback = true
                         }
                     }
                 } label: {
                     navigationRow(title: "Contact Support")
                 }
                 .alert("Contact Support", isPresented: $showSupportMailFallback) {
                     Button("OK", role: .cancel) {}
                 } message: {
                     Text(ModerationMail.noMailMessage)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 legalLinkRows

                 Button {
                     auth.signOut()
                 } label: {
                     Text("Sign out")
                         .foregroundStyle(.primary)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .frame(minHeight: 44, alignment: .center)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     quietDivider()
                 }

                 eraseAllEtudesDataButton
             }
             .cardSurface(padding: profileInnerCardPadding)
             .listRowSeparator(.hidden)
                .padding(.vertical, profileSectionSpacing / 2)
         }
     }

     /// Privacy Policy and Terms of Use (Apple 5.1.1 / 3.1.2), opened in Safari.
     @ViewBuilder
     private var legalLinkRows: some View {
         ForEach([("Privacy Policy", LegalLinks.privacyPolicy),
                  ("Terms of Use", LegalLinks.termsOfUse)], id: \.0) { title, url in
             Link(destination: url) {
                 navigationRow(title: title)
             }
             .buttonStyle(.plain)
             .contentShape(Rectangle())
             .frame(minHeight: 44, alignment: .center)
             .font(Theme.Text.body)
             .overlay(alignment: .bottom) {
                 quietDivider()
             }
         }
     }

     /// Version, build number and commit, quietly at the foot of Profile.
     private var buildInfoFooter: some View {
         Section {
             Text(AppBuildInfo.label())
                 .font(Theme.Text.meta)
                 .foregroundStyle(Theme.Colors.secondaryText)
                 .textSelection(.enabled)
                 .frame(maxWidth: .infinity, alignment: .center)
         }
         .listRowBackground(Color.clear)
         .listRowSeparator(.hidden)
     }

     // C-35: every user-facing string below and the operation itself switch on the
     // SAME expression, `auth.hasConnectedIdentity`. That is deliberate and
     // structural — it makes it impossible to promise account deletion and perform
     // only a local wipe, or the reverse. Do not introduce a second predicate here,
     // and never gate any of it on entitlement or AppMode: a lapsed member holding
     // a backend account must get the Delete Account wording and behaviour.

     /// Destructive control title. Names account deletion explicitly whenever
     /// there is an account to delete.
     private var destructiveActionTitle: String {
         auth.hasConnectedIdentity ? "Delete Account & All Études Data" : "Erase All Études Data"
     }

     /// The word the user must type. Matches the verb in the title so the
     /// confirmation cannot read incongruously against the button.
     private var destructiveConfirmWord: String {
         auth.hasConnectedIdentity ? "DELETE" : "ERASE"
     }

     private var destructiveInFlightTitle: String {
         auth.hasConnectedIdentity ? "Deleting…" : "Erasing…"
     }

     private var eraseAllEtudesDataButton: some View {
         Button {
             deleteAccountConfirmText = ""
             showDeleteAccountSheet = true
         } label: {
             Text(destructiveActionTitle)
                 .foregroundStyle(.red)
                 .frame(maxWidth: .infinity, alignment: .leading)
                 .frame(minHeight: 44, alignment: .center)
         }
         .buttonStyle(.plain)
         .contentShape(Rectangle())
         .font(Theme.Text.body)
     }
     
     @MainActor
     private func openManageMembership() async {
         guard
             let scene = UIApplication.shared.connectedScenes
                 .compactMap({ $0 as? UIWindowScene })
                 .first
         else {
             return
         }

         do {
             try await AppStore.showManageSubscriptions(in: scene)
         } catch {
             #if DEBUG
             print("[Profile] Failed to present Manage Membership: \(error)")
             #endif
         }
     }

     // MARK: - Toolbar

     @ToolbarContentBuilder
     private var toolbarContent: some ToolbarContent {
         ToolbarItem(placement: .cancellationAction) {
             Button(action: { onClose?() }) {
                 Image(systemName: "chevron.backward")
                     .font(.body.weight(.semibold))
                     .foregroundStyle(.primary)
             }
             .accessibilityLabel("Close profile")
         }
     }
 
     // MARK: - Avatar
 
     @ViewBuilder
     private var avatarChip: some View {
         Group {
             if let img = avatarImage {
                 Image(uiImage: img)
                     .resizable()
                     .scaledToFill()
             } else {
                 ZStack {
                     Circle()
                         .fill(Color.gray.opacity(0.2))
                     Text(initials(from: name))
                         .font(.system(size: 16, weight: .bold))
                         .foregroundColor(Theme.Colors.secondaryText)
                         .minimumScaleFactor(0.5)
                         .lineLimit(1)
                 }
             }
         }
         .frame(width: 32, height: 32)
         .clipShape(Circle())
         .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))
     }
 
     private var avatarEditorSheet: some View {
         AvatarEditorView(
             image: ProfileStore.avatarOriginalImage(for: auth.currentUserID) ?? ProfileStore.avatarImage(for: auth.currentUserID),
             placeholderInitials: initials(from: name),
             onSave: { jpegData, cropped in
                 // Local cache for immediate UI (owner view).
                 ProfileStore.saveAvatarDerived(cropped, for: auth.currentUserID)
                 mirrorCurrentAvatarIntoLocalScope(cropped: cropped, currentUserID: auth.currentUserID)
                 avatarImage = ProfileStore.avatarImage(for: auth.currentUserID) ?? ProfileStore.avatarImage(for: nil)
                 showAvatarEditor = false

                 Task { _ = await persistAvatarToBackendIfPossible(jpegData: jpegData) }
             },
             onDelete: {
                 // Local clear immediately.
                 ProfileStore.deleteAvatar(for: auth.currentUserID)
                 ProfileStore.deleteAvatar(for: nil)
                 avatarRefreshTask?.cancel()
         avatarRefreshTask = nil
         avatarImage = nil
                 showAvatarEditor = false

                 Task {
                     let auth = _auth.wrappedValue
                     await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "ProfileView.connectedAvatarDelete")
                 }
             },
             onCancel: { showAvatarEditor = false },
             onReplaceOriginal: { image in
                 ProfileStore.saveAvatarOriginal(image, for: auth.currentUserID)
                 ProfileStore.saveAvatarOriginal(image, for: nil)
                 // Do not auto-update derived; keep current derived until user taps Save in the editor.
             }
         )
         .presentationDetents([.large])
     }
 
     // MARK: - Lifecycle / Data
 
     private func onAppearLoad() {
         // Milestone 7: Études Profile is local-first.
         // Signed-out users should see the local Profile rather than an empty authentication gate.
         load()
         refreshUserActivities()
         primaryActivityChoice = normalizedPrimaryActivityRef()
         if primaryFallbackNoticeNeeded {
             showPrimaryFallbackAlert = true
             primaryFallbackNoticeNeeded = false
         }
         refreshAvatarDisplay()
         self.locationText = ProfileStore.presentedLocation(for: auth.backendUserID) // C-36

         // CP-3: discovery is server-authoritative. AuthManager hydrates the
         // EFFECTIVE value from account_privacy; this no longer forces it on.
         discoveryModeRawPerUser = ProfileStore.discoveryModeRaw(for: auth.backendUserID)
         hydrateDiscoverabilityControl()

         // F3, EVENT 4 — a REMOUNT, where both earlier events have already
         // passed and this screen's state started empty.
         //
         // **LAST IN THIS FUNCTION, DELIBERATELY.** The snapshot a publish sends
         // is read from the live screen, so evaluating before `load()` and the
         // location rehydration above would publish the initial empty defaults
         // over the member's real profile.
         reconcileDirectoryIfAttestationAllows()
     }

     /// Writes the discoverability preference through the ONLY client writer of
     /// it. On failure the control is returned to the server's last known state,
     /// so the UI never claims a preference the server did not accept.
     @MainActor
     private func applyDiscoverability(_ enabled: Bool) async {
         discoverabilityBusy = true
         defer { discoverabilityBusy = false }
         switch await AccountPrivacyService.setLookupEnabled(enabled, auth: auth, reason: "profile") {
         case .success:
             let state = await auth.refreshAccountPrivacyState(reason: "discoverability")
             discoverabilityOn = state?.lookupEffective ?? enabled
         case .failure:
             discoverabilityOn = auth.accountPrivacyState?.lookupEffective ?? false
             discoverabilityNotice = "Couldn’t update that just now. Please try again."
         }
     }

     /// Hydrates the control from the server's EFFECTIVE value. Unknown reads as
     /// off, which is the protective direction.
     @MainActor
     private func hydrateDiscoverabilityControl() {
         discoverabilityOn = auth.accountPrivacyState?.lookupEffective ?? false
     }

     /// Asks Apple to share the member's age range and reduces it to a band.
     /// Any thrown error -- including `.notAvailable` and `.invalidRequest` --
     /// is `.unavailable`: never a band, and never eligibility.
     @MainActor
     private func requestDeclaredAgeRange() async -> DeclaredAgeRangeOutcome {
         do {
             let response = try await requestAgeRange(
                 ageGates: DeclaredAgeRangeService.minimumGate,
                 DeclaredAgeRangeService.adultGate
             )
             return DeclaredAgeRangeService.outcome(for: response)
         } catch {
             return .unavailable
         }
     }

     /// B-24 / D2: SIWA BEFORE PURCHASE for every new join. Forced rather than
     /// chosen -- the binding token must exist before StoreKit can carry it into
     /// the transaction, and a purchase made without one lands in the
     /// legacy-claim path instead of being bound at source. An already-
     /// authenticated member skips straight through.
     @MainActor
     private func continueToConnectedJoin() {
         if auth.hasConnectedIdentity {
             Task { @MainActor in
                 // The band must reach authenticated server state before any
                 // directory publication. For an identity that already exists
                 // this is a reconcile; for a new one it is the establishment.
                 _ = await auth.ensureAgeBandEstablished(reason: "join")
                 showMembershipSelection = true
             }
         } else {
             connectedSignInIntent = .join
             showConnectedSignInSheet = true
         }
     }

     private func clearUserPresentedStateForSignOut() {
         // Clear all user-presented state without mutating persisted device-level Profile.
         profile = nil
         name = ""
         primaryInstrumentName = ""
         defaultPrivacy = false
         avatarImage = nil
         locationText = ""
         discoveryModeRawPerUser = DiscoveryMode.none.rawValue

         userActivities = []
         // Keep AppStorage primaryActivityRef unchanged; normalize displayed choice only.
         primaryActivityChoice = normalizedPrimaryActivityRef()

         // Clear any in-flight UI surfaces.
         showPhotoPicker = false
         showAvatarEditor = false
     }
 
     private var avatarRefreshTrigger: String {
         let currentUserID = auth.currentUserID ?? "nil"
         let backendAvatarKey = auth.backendAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
         // P5-I / C-34 R2: the key never changes, so a replacement from another
         // device redraws through the revision instead.
         return "\(currentUserID)|\(backendAvatarKey)|\(auth.ownAvatarRevision)"
     }

     @MainActor
     private func refreshAvatarDisplay() {
         avatarRefreshTask?.cancel()
         avatarRefreshTask = nil

         let currentUserID = auth.currentUserID

         if ProfileStore.hasPendingLocalAvatarSync(), BackendEnvironment.shared.isConnected {
             if ProfileStore.hasPendingLocalAvatarUpload(), let localAvatar = ProfileStore.avatarImage(for: nil) {
                 copyLocalAvatarIntoConnectedScope(localAvatar, currentUserID: currentUserID)
                 avatarImage = localAvatar
             } else if ProfileStore.hasPendingLocalAvatarDeletion() {
                 if currentUserID != nil {
                     ProfileStore.deleteAvatar(for: currentUserID)
                 }
                 avatarImage = nil
             }

             Task { await syncPendingLocalAvatarToConnectedIfNeeded() }
             return
         }

         if let localAvatar = ProfileStore.avatarImage(for: currentUserID) {
             avatarImage = localAvatar
             return
         }

         let backendAvatarKey = auth.backendAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
         guard backendAvatarKey.isEmpty == false else {
             avatarImage = nil
             return
         }

         avatarImage = nil
         avatarRefreshTask = Task {
             let requestedUserID = currentUserID
             let requestedAvatarKey = backendAvatarKey
             let fetchedImage = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: requestedAvatarKey)
             guard Task.isCancelled == false else { return }

             await MainActor.run {
                 guard Task.isCancelled == false else { return }
                 guard auth.currentUserID == requestedUserID else { return }

                 let currentBackendAvatarKey = auth.backendAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                 guard currentBackendAvatarKey == requestedAvatarKey else { return }

                 if let localAvatar = ProfileStore.avatarImage(for: auth.currentUserID) {
                     avatarImage = localAvatar
                 } else {
                     if let fetchedImage {
                         seedLocalAvatarFromFetchedConnectedAvatar(fetchedImage, currentUserID: auth.currentUserID)
                     }
                     avatarImage = fetchedImage
                 }

                 avatarRefreshTask = nil
             }
         }
     }

     private func copyLocalAvatarIntoConnectedScope(_ localAvatar: UIImage, currentUserID: String?) {
         guard currentUserID != nil else { return }

         ProfileStore.saveAvatarDerived(localAvatar, for: currentUserID)

         if let localOriginal = ProfileStore.avatarOriginalImage(for: nil) {
             ProfileStore.saveAvatarOriginal(localOriginal, for: currentUserID)
         } else {
             ProfileStore.saveAvatarOriginal(localAvatar, for: currentUserID)
         }
     }

     private func mirrorCurrentAvatarIntoLocalScope(cropped: UIImage, currentUserID: String?) {
         ProfileStore.saveAvatarDerived(cropped, for: nil)

         if let currentOriginal = ProfileStore.avatarOriginalImage(for: currentUserID) {
             ProfileStore.saveAvatarOriginal(currentOriginal, for: nil)
         } else {
             ProfileStore.saveAvatarOriginal(cropped, for: nil)
         }
     }

     private func seedLocalAvatarFromFetchedConnectedAvatar(_ fetchedImage: UIImage, currentUserID: String?) {
         guard currentUserID != nil else { return }

         // A fetched Connected avatar is already backend-authoritative, so it should also become
         // the local Études avatar without creating a pending upload marker. P5-I: routed through
         // the one ProfileStore seeding function; first seeding keeps an existing connected copy.
         ProfileStore.seedAvatarFromConnected(fetchedImage, for: currentUserID, replacingExisting: false)
     }

     @MainActor
     private func syncPendingLocalAvatarToConnectedIfNeeded() async {
         let auth = _auth.wrappedValue
         await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "ProfileView.refreshAvatarDisplay")

         if let currentUserID = auth.currentUserID,
            let connectedAvatar = ProfileStore.avatarImage(for: currentUserID) {
             avatarImage = connectedAvatar
         } else {
             avatarImage = ProfileStore.avatarImage(for: nil)
         }
     }

     private func handleActivityManagerChange(_ wasPresented: Bool, _ isPresented: Bool) {
         if wasPresented == true && isPresented == false {
             refreshUserActivities()
             primaryActivityChoice = normalizedPrimaryActivityRef()
         }
     }

     private var currentTintMode: Theme.TintMode {
         Theme.TintMode(rawValue: tintModeRaw) ?? .auto
     }

     private var profileSectionSpacing: CGFloat { 10 }

     private var profileInnerCardPadding: CGFloat { Theme.Spacing.m - 6 }

     private var quietDividerOpacity: Double { 0.16 }

     @ViewBuilder
     private func quietDivider(leadingInset: CGFloat = 16) -> some View {
         Divider()
             .overlay(Color.primary.opacity(quietDividerOpacity))
             .padding(.leading, leadingInset)
             .padding(.vertical, -1)
     }
 
     private func navigationRow(title: String, value: String? = nil) -> some View {
         HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
             Text(title)
                 .foregroundStyle(.primary)

             Spacer(minLength: Theme.Spacing.l)

             if let value {
                 Text(value)
                     .font(Theme.Text.body)
                     .foregroundStyle(Theme.Colors.secondaryText.opacity(0.88))
                     .lineLimit(1)
                     .minimumScaleFactor(0.9)
                     .truncationMode(.tail)
             }

             Image(systemName: "chevron.right")
                 .font(.footnote.weight(.semibold))
                 .padding(6)
                 .background(
                    Theme.Colors.surface(colorScheme).opacity(0.82),
                    in: Circle()
                )
                 .foregroundStyle(Theme.Colors.secondaryText)
         }
     }
 
     // MARK: - Data
 
     private var instrumentsArray: [String] {
         instruments.map { $0.name ?? "" }.filter { !$0.isEmpty }
     }
 
     private func load() {
         // C-70. Do not re-hydrate an erased view; that is how erased text
         // reappears on screen after a reset.
         guard localStorageIsUsable else { return }
         let req: NSFetchRequest<Profile> = Profile.fetchRequest()
         req.fetchLimit = 1
         do {
             if let existing = try ctx.fetch(req).first {
                 profile = existing
                 if profile?.value(forKey: "id") == nil {
                     profile?.setValue(UUID(), forKey: "id")
                     try? ctx.save()
                 }
             } else {
                 let p = Profile(context: ctx)
                 p.setValue(UUID(), forKey: "id")
                 p.name = ""
                 p.primaryInstrument = instrumentsArray.first ?? ""
                 p.defaultPrivacy = false
                 try? ctx.save()
                 profile = p
             }
         } catch {
             // Minimal handling; non-fatal for UI
         }
 
         // C-70. HYDRATION MUST NOT OVERWRITE THE NEWEST UNSAVED EDIT.
         //
         // The guard is here, in `load()`, rather than in `onAppearLoad()`,
         // because two call sites reach `load()` DIRECTLY and would otherwise
         // bypass it: `NSManagedObjectContextDidSave` — which fires for ANY save
         // on the shared context, including saves made by other screens — and the
         // instrument manager closing.
         //
         // The draft lives in `@State` and only reaches the managed object inside
         // `save()`, so EVERY edit reopens this window; it is not opened once.
         if nameDraft.mayHydrate {
             name = profile?.name ?? ""
         }
         primaryInstrumentName = (profile?.primaryInstrument ?? "").isEmpty
             ? (instrumentsArray.first ?? "")
             : (profile?.primaryInstrument ?? "")
         defaultPrivacy = profile?.defaultPrivacy ?? false
     }
 
     @discardableResult
     private func save() -> Result<Void, Error> {
         // C-70. NO PROFILE IS A LOCAL FAILURE, NOT A SUCCESS.
         //
         // Returning `.success` here would report evidenced persistence for a
         // write that never happened, and — because the local commit gates the
         // remote publish — it would also UNBLOCK publishing a value the device
         // had not recorded. `load()` creates a Profile when none exists, so this
         // is the unexpected path; it fails closed rather than quietly.
         guard localStorageIsUsable else {
             return .failure(NSError(domain: "ProfileView", code: 2, userInfo: [
                 NSLocalizedDescriptionKey: "Local storage unavailable (reset)."
             ]))
         }
         guard let p = profile else {
             return .failure(NSError(domain: "ProfileView", code: 1, userInfo: [
                 NSLocalizedDescriptionKey: "No local profile to save into."
             ]))
         }
         if p.value(forKey: "id") == nil {
             p.setValue(UUID(), forKey: "id")
         }
         p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
         p.primaryInstrument = primaryInstrumentName.trimmingCharacters(in: .whitespacesAndNewlines)
         p.defaultPrivacy = defaultPrivacy
         // C-70. The empty catch is gone. A swallowed Core Data failure was the
         // whole of gap 2: the member saw an edit on screen that had not been
         // recorded, and nothing anywhere said so.
         //
         // THE CONTEXT IS NEVER ROLLED BACK OR RESET on failure. It is shared, so
         // a rollback would discard unrelated pending edits belonging to other
         // screens — and it would also discard THIS edit, which M5 shows the next
         // successful save commits without it being re-applied.
         do {
             try ctx.save()
             return .success(())
         } catch {
             return .failure(error)
         }
     }

     /// Commit local profile edits. Called from every commit point, and from
     /// `syncDirectoryFromCurrentState` BEFORE any remote precondition.
     @discardableResult
     private func persistProfileEdits() -> Result<Void, Error> {
         // C-70. An erased or erasing view writes NOTHING — not Core Data and not
         // `ProfileStore`. This is the `.onDisappear`-after-reset path, where
         // `isInProgress` is already false again.
         guard localStorageIsUsable else {
             return .failure(NSError(domain: "ProfileView", code: 2, userInfo: [
                 NSLocalizedDescriptionKey: "Local storage unavailable (reset)."
             ]))
         }
         let outcome = save()
         ProfileStore.setLocation(locationText, for: auth.backendUserID)
         switch outcome {
         case .success:
             // Evidenced success ONLY — never optimistic.
             nameDraft.evidencedSaved()
             localSaveMessage = nil
         case .failure:
             // Preserve the pending state and ask for a retry. NEVER presented as
             // saved, and never attributed to a field the failure does not name.
             localSaveMessage = "Not saved yet. Your changes are still here — try again."
         }
         return outcome
     }
 
     // MARK: - Primary Activity helpers
 
     private func refreshUserActivities() {
         do {
             userActivities = try PersistenceController.shared.fetchUserActivities(in: ctx)
         } catch {
             userActivities = []
         }
     }
 
     private func normalizedPrimaryActivityRef() -> String {
         let raw = primaryActivityRef.trimmingCharacters(in: .whitespacesAndNewlines)
         if raw.hasPrefix("core:") {
             if let v = Int(raw.split(separator: ":").last ?? "0"),
                SessionActivityType(rawValue: Int16(v)) != nil {
                 return "core:\(v)"
             } else {
                 return "core:0"
             }
         } else if raw.hasPrefix("custom:") {
             let name = String(raw.dropFirst("custom:".count))
             if userActivities.contains(where: { ($0.displayName ?? "") == name }) {
                 return "custom:\(name)"
             } else {
                 return "core:0"
             }
         } else {
             return "core:0"
         }
     }
 
     private func writePrimaryActivityRef(_ newValue: String) {
         let normalized = normalizeChoiceString(newValue)
         primaryActivityRef = normalized
         primaryActivityChoice = normalized
     }
 
     private func normalizeChoiceString(_ choice: String) -> String {
         if choice.hasPrefix("core:") {
             if let v = Int(choice.split(separator: ":").last ?? "0"),
                SessionActivityType(rawValue: Int16(v)) != nil {
                 return "core:\(v)"
             } else {
                 return "core:0"
             }
         } else if choice.hasPrefix("custom:") {
             let name = String(choice.dropFirst("custom:".count))
             if userActivities.contains(where: { ($0.displayName ?? "") == name }) {
                 return "custom:\(name)"
             } else {
                 return "core:0"
             }
         } else {
             return "core:0"
         }
     }
 
 
    // Phase 12C hygiene: avoid directory upserts on every keystroke.
    /// C-70. Submit immediately, capturing owner and generation **before** the
    /// `Task` is created.
    ///
    /// The direct Account-ID blur/submit callers and the local-save Retry all go
    /// through here. A bare `Task { await sync… }` captures nothing, so a task
    /// created just before an identity transition could run after it and compose
    /// the old identity's edit under the new one — the same pre-submit window the
    /// debounce path guards, reached by a different route.
    @MainActor
    private func submitDirectorySyncNow() {
        let token = ProfilePreSubmitToken(owner: auth.backendUserID,
                                          generation: DirectoryWriteCoordinator.shared.identityGeneration)
        Task { @MainActor in
            guard token.isStillCurrent(owner: auth.backendUserID,
                                       generation: DirectoryWriteCoordinator.shared.identityGeneration) else { return }
            await syncDirectoryFromCurrentState()
        }
    }

    @MainActor
    private func scheduleDirectorySyncDebounced(nanoseconds: UInt64 = 650_000_000) {
        directorySyncDebounceTask?.cancel()
        // C-70. CAPTURE THE OWNER AND GENERATION AT SCHEDULING TIME.
        //
        // Cancellation alone does not prove an old intent cannot reach a new
        // identity: cancellation is cooperative and a task can already be past
        // its sleep. The coordinator owns a write only AFTER submission, so this
        // pre-submit window needs its own evidence — captured here and rechecked
        // below, before ANY local or remote work.
        let token = ProfilePreSubmitToken(owner: auth.backendUserID,
                                          generation: DirectoryWriteCoordinator.shared.identityGeneration)
        directorySyncDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            guard token.isStillCurrent(owner: auth.backendUserID,
                                       generation: DirectoryWriteCoordinator.shared.identityGeneration) else { return }
            await syncDirectoryFromCurrentState()
        }
    }

    // Phase 12C — Owner-only directory upsert/disable. No profile sync; only minimal identity surface.
    /// Everything one directory publish needs, derived from the live screen
    /// state in one place so the SAME derivation can be taken again afterwards.
    private struct DirectorySyncSnapshot {
        let backendID: String
        let display: String
        let location: String?
        let instruments: [String]
        let fingerprint: String
    }

    @MainActor
    private func currentDirectorySnapshot(backendID: String) -> DirectorySyncSnapshot {
         let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
         // Connected discovery is always enabled. Relationship privacy is handled by explicit follow approval.
         let locTrim = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
         let locOrNil: String? = locTrim.isEmpty ? nil : locTrim
         let instrumentsClean = instrumentsArray
             .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
         let instrumentsSorted = instrumentsClean.sorted { a, b in
             a.localizedCaseInsensitiveCompare(b) == .orderedAscending
         }
         let instrumentsFP = instrumentsSorted.joined(separator: ",")
         // **CORRECTED. An earlier revision kept a literal "nil" segment here and
         // justified it as upgrade compatibility with existing latch values.
         // That premise was false and is withdrawn:** `directorySyncLatch` is
         // `@State`, so it is view-lifetime and starts empty on every mount —
         // there is no persisted fingerprint for a new shape to disagree with,
         // and nothing to be compatible across.
         //
         // The fingerprint describes PRESENT screen state, and the handle is no
         // longer part of it, so the segment is gone rather than kept as a
         // placeholder that would have to be explained again later.
         let fingerprint = "\(backendID)|\(display)|\(locOrNil ?? "nil")|connectedDiscovery:1|fr:1|i:\(instrumentsFP)"
         return DirectorySyncSnapshot(backendID: backendID,
                                      display: display,
                                      location: locOrNil,
                                      instruments: instrumentsSorted,
                                      fingerprint: fingerprint)
    }

     /// C-70. May this view still read or write local storage?
     ///
     /// False once a reset has been initiated from this screen, and false while
     /// one is running. **Deliberately not consulted before a reset actually
     /// starts** — a pre-reset failure must not suppress ordinary saving.
     private var localStorageIsUsable: Bool {
         ProfileLocalStorageGate.isUsable(viewInvalidatedByReset: viewInvalidatedByReset,
                                          resetInProgress: LocalFactoryReset.isInProgress)
     }

     /// C-70. The name field's binding, which marks the draft dirty **in the
     /// setter**.
     ///
     /// Two reasons it is not `.onChange(of: name)`. **Timing:** the setter runs
     /// at the edit, so an unrelated save landing in the same turn cannot hydrate
     /// over a draft that has not been flagged yet. **Correctness:** `.onChange`
     /// also fires for PROGRAMMATIC assignment, so marking there would let
     /// `load()` flag its own hydration as an unsaved edit — after which the flag
     /// could never legitimately clear.
     private var nameEditingBinding: Binding<String> {
         Binding(
             get: { name },
             set: { newValue in
                 guard newValue != name else { return }
                 nameDraft.edited()
                 name = newValue
             }
         )
     }

     /// C-70. Identity + configuration, never `AppMode`. See `ProfileMaintenancePolicy`.
     private var mayShowMaintenanceSurface: Bool {
         ProfileMaintenancePolicy.mayShowMaintenanceSurface(
             hasConnectedIdentity: auth.hasConnectedIdentity,
             isBackendConfigured: BackendConfig.isConfigured)
     }

     @MainActor
     private func syncDirectoryFromCurrentState() async {
        // Phase 14.3H (B2) — Never attempt account_directory upsert unless we have a valid Supabase bearer token.
        // Prevents unauthenticated upsert attempts during the sign-in transition (which can leave ProfileView in an empty limbo on first sign-in).
        let auth = _auth.wrappedValue

        // C-70. LOCAL FIRST, AND BEFORE EVERY REMOTE PRECONDITION.
        //
        // This runs ahead of the identity guards on purpose. A Solo member with
        // no Connected identity returns below, and if the local commit sat after
        // that return they would get NO debounce-driven local persistence at all
        // — the very members for whom the local record is the only record. Local
        // persistence must never be reachable only through a remote path's
        // preconditions.
        //
        // It also guards the remote submission: the device must not publish a
        // value it could not record. A pending edit survives in the shared
        // context but NOT a process kill, so this is a real safety gate and not
        // merely a consistency preference.
        // No new suspension here, deliberately: the owner, generation and
        // snapshot are captured below, and an await between the local commit and
        // that capture would let an identity change or a newer unsaved edit slip
        // in and be published.
        let decision = ProfileMaintenanceGate.decide(
            commitLocally: { persistProfileEdits() },
            mayAttemptRemote: {
                ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
                    hasConnectedIdentity: auth.hasConnectedIdentity,
                    isBackendConfigured: BackendConfig.isConfigured,
                    hasAccessToken: auth.hasSupabaseAccessToken,
                    backendUserID: auth.backendUserID)
            })
        guard decision == .remotePermitted else { return }

        // C-70/C-35. The gate above is IDENTITY AND CONFIGURATION, NEVER AppMode.
        //
        // It used to be `canShowConnectedAccountManagement` plus
        // `BackendEnvironment.shared.isConnected`. The first is `mode ==
        // .connected`; the second reads `backendMode_v1` from UserDefaults, which
        // `AppModeManager.applyBackendRuntimeMode` writes FROM that same mode.
        // Both fold in `isEntitled` without naming it, so a lapsed member holding
        // a real Connected account could not maintain their own directory row —
        // while `account_directory_update_owner` carries no gate and D-U6-3
        // always intended exactly that. This is the substitution C-35 already
        // made for `performDeleteAccount` in this same file.

         guard let backendID = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !backendID.isEmpty else { return }
         let snapshot = currentDirectorySnapshot(backendID: backendID)
         // Submitting a DIFFERENT value invalidates the token here, before the
         // request goes out -- so a revert to the previously-confirmed value
         // while this write is in flight is re-published rather than skipped.
         guard directorySyncLatch.shouldSubmit(snapshot.fingerprint) else { return }

         let result = await AccountDirectoryService.shared.upsertSelfRow(
             userID: backendID,
             displayName: snapshot.display,
             location: snapshot.location,
             instruments: snapshot.instruments,
             // C-70. Owner maintenance is the ONE path that must be able to
             // refresh while the app is in Solo. The GLOBAL `onAuthChallenge` is
             // unchanged and still forced, but it routes through
             // `ensureValidSession`, which is mode-gated and in Solo returns
             // `isSignedIn` having rotated nothing — so the retry would re-present
             // the token the server just refused. `boundRequest` resolves this
             // closure INSIDE its owner/generation guards, so a scoped handler
             // gains no latitude over identity.
             authChallenge: { await auth.ensureValidBackendSession(reason: "profile-maintenance", force: true) }
         )

         // C-70. EVERY UI EFFECT IS GUARDED HERE -- the message as much as the
         // latch. There are TWO kinds of staleness and neither subsumes the
         // other:
         //
         //   * the identity changed, or a newer write was SUBMITTED, which the
         //     coordinator's tokens see;
         //   * a newer edit is already ON SCREEN but has not been submitted yet,
         //     which is the ordinary case during the 650 ms debounce and which
         //     no server-side token can possibly see.
         //
         // An error posted for either is an error about a value the member has
         // already moved on from, and the pending attempt will report the real
         // one. THE LATCH is the effect that can outlive its own mistake: it is
         // a SKIP token, so the next identical attempt returns at the guard
         // above and never reaches the server at all.
         guard DirectoryWriteCoordinator.shared.mayApplyEffects(owner: backendID,
                                                                capturedGeneration: result.generation,
                                                                seq: result.seq) else { return }
         guard currentDirectorySnapshot(backendID: backendID).fingerprint == snapshot.fingerprint else { return }

         switch result.outcome {
         case .applied:
             directorySyncLatch.confirm(snapshot.fingerprint)
             directorySyncMessage = nil
             directorySyncIsError = false
             // F3. Recorded HERE and nowhere else: both freshness guards above
             // have already passed, so this row is evidenced for the identity
             // and epoch the WRITE bound. `result.generation`, never a fresh
             // read of the coordinator.
             reconciliation.noteApplied(owner: backendID, generation: result.generation)
         case .superseded, .supersededIdentity:
             // A newer intent, or a different identity, owns the screen. Report
             // nothing about a write whose result is not this member's business.
             break
         default:
             // C-70(a): the message names a field only when the SERVER attributed the
             // failure to that field. This row also carries display name, location and
             // instruments, and three of the five triggers never touch the Account ID.
             directorySyncMessage = DirectorySyncFailure.message(for: result.outcome)
             directorySyncIsError = (directorySyncMessage != nil)
             // F2, EVENT 2 — SUCCESS BEFORE FAILURE.
             //
             // The establishing completion may already have arrived while nothing
             // was outstanding, in which case it correctly wrote nothing and NO
             // further completion will land to retrigger anything. Asking here is
             // what closes that order; asking only on the completion misses it.
             reconcileDirectoryIfAttestationAllows()
         }
     }

     /// F2. Ask the policy, and — only on a true answer — consume the completion
     /// and schedule one ordinary write.
     ///
     /// **Consumption happens BEFORE scheduling**, so a write that is refused
     /// again cannot find the same completion still unspent and loop. The write
     /// itself goes through `syncDirectoryFromCurrentState` unchanged, so the
     /// identity binding, the generation epoch, the screen-fingerprint guard and
     /// every effect guard apply to it exactly as to a member's own edit.
     /// The two asynchronously-arriving inputs, as one observable value.
     private struct ReconciliationInputs: Equatable {
         let completion: MembershipAttestationCoordinator.AttestationCompletion?
         let absence: AuthManager.DirectoryRowAbsence?
     }

     private var reconciliationInputs: ReconciliationInputs {
         ReconciliationInputs(completion: attestation.lastCompletion,
                              absence: auth.directoryRowAbsence)
     }

     @MainActor
     private func reconcileDirectoryIfAttestationAllows() {
         guard reconciliation.evaluateAndConsume(
                 completion: attestation.lastCompletion,
                 hasOutstandingFailure: directorySyncMessage != nil,
                 rowAbsence: auth.directoryRowAbsence,
                 currentOwner: auth.backendUserID,
                 currentDirectoryGeneration: DirectoryWriteCoordinator.shared.identityGeneration)
         else { return }

         // The latch is a SKIP token keyed on the fingerprint, and the previous
         // attempt latched nothing because it failed -- but an identical earlier
         // SUCCESS could have. Invalidating makes this retry actually reach the
         // server rather than being skipped as unchanged.
         directorySyncLatch.invalidate()
         scheduleDirectorySyncDebounced()
     }

     // MARK: - Avatar (backend identity)

     @MainActor
     private func persistAvatarToBackendIfPossible(jpegData: Data) async -> Bool {
         guard appModeManager.canShowConnectedAccountManagement else { return false }
         guard BackendEnvironment.shared.isConnected else { return false }
         let auth = _auth.wrappedValue
         guard auth.hasSupabaseAccessToken else { return false }
         guard let backendID = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !backendID.isEmpty else { return false }

         avatarSyncInFlight = true
         defer { avatarSyncInFlight = false }

         // 1) Upload (overwrite) avatars/users/<uid>/avatar.jpg
         let upload = await NetworkManager.shared.uploadAvatarJPEG(data: jpegData, backendUserID: backendID)
         switch upload {
         case .failure:
             avatarSyncErrorMessage = "Couldn’t upload your avatar. Please try again."
             showAvatarSyncErrorAlert = true
             return false
         case .success(let avatarKey):
             // Bust remote caches for this key (image + signed URL), because content may have changed.
             await invalidateRemoteAvatarCaches(avatarKey: avatarKey)

             // 2) Patch account_directory.avatar_key
             let patch = await AccountDirectoryService.shared.updateSelfAvatarKey(userID: backendID, avatarKey: avatarKey)
             switch patch {
             case .success:
                 ProfileStore.clearPendingLocalAvatarSync()
                 return true
             case .failure:
                 avatarSyncErrorMessage = "Uploaded your avatar, but couldn’t update your profile. Please try again."
                 showAvatarSyncErrorAlert = true
                 return false
             }
         }
     }

     // C-33: `clearAvatarFromBackendIfPossible()` was removed here. It had no
     // callers — the live deletion path is the pending-marker route in
     // `AuthManager.syncPendingLocalAvatarToConnectedIfNeeded` — so this file
     // held a second, independent implementation of avatar deletion that
     // disguised which one actually ran. It carried the same discarded-result
     // defect, and repairing both would have preserved exactly the ambiguity
     // that made the defect hard to see. Deleted rather than fixed.

     private func invalidateRemoteAvatarCaches(avatarKey: String) async {
         let trimmed = avatarKey.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmed.isEmpty else { return }
         let cacheKey = "avatars|\(trimmed)"
         await RemoteAvatarSignedURLCache.shared.invalidate(cacheKey)
         #if canImport(UIKit)
         RemoteAvatarImageCache.invalidate(cacheKey)
         #endif
     }

// Phase 13A — account_id collision detection RELOCATED to DirectorySyncFailure (C-70(a)).


     // New helper method to compute initials from a string
     

     private var eraseAllEtudesDataExplanation: String {
         // C-35: gated on identity, never on entitlement — a lapsed member holding
         // a backend account must be told the truth about what will be deleted.
         //
         // The Connected text was also inaccurate before 2026-08-13: it promised
         // deletion of "comments" while B-3 retained them and B-1 preserved sent
         // attachments. Both rules were revised so the promise and the operation
         // now match; if that ever changes again, this string changes with it.
         if auth.hasConnectedIdentity {
             return """
             This permanently deletes your Études Connected account and the data associated with it — your profile, posts, comments, avatar, follows, and the attachments you have sent.

             This deletes only the Connected account you are signed in to. If you previously used another Connected account on this device, its shared posts are not deleted by this action.

             It also erases everything stored in Études on this device: your Journal, Scores, profile, attachments, instruments, activities and settings. Études will return to its first-launch state.

             Files you have already sent may remain on the devices of people you sent them to.

             Deleting your account does not cancel an App Store subscription.

             This can’t be undone.
             """
         }
         return "This permanently erases everything stored in Études on this device, including your Journal, Scores, profile, attachments, instruments, activities, and settings. Études will return to its first-launch state. This does not delete posts already shared with Études Connected. Any pending requests to remove shared posts will also be erased. To delete a Connected account and its posts, sign in to that account and use Delete Account. This can’t be undone."
     }

     private var deleteAccountSheet: some View {
         NavigationStack {
             ScrollView {
                 VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                     VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                         Text(eraseAllEtudesDataExplanation)
                             .font(Theme.Text.body)
                             .foregroundStyle(Theme.Colors.secondaryText)
                     }
                     .cardSurface()

                     // Non-destructive, and deliberately kept separate from the
                     // confirmation below. Deleting the account does not cancel App
                     // Store billing, so this offers the native sheet rather than
                     // only naming Settings. It is a convenience beside deletion,
                     // never a prerequisite for it: the delete action stays
                     // immediately available whatever the subscription state, which
                     // is why this is gated on identity like everything else here
                     // and not on entitlement.
                     if auth.hasConnectedIdentity {
                         Button {
                             Task { await openManageMembership() }
                         } label: {
                             HStack {
                                 Text("Manage Subscription")
                                 Spacer()
                                 Image(systemName: "arrow.up.forward.app")
                             }
                             .font(Theme.Text.body)
                             .frame(minHeight: 44)
                         }
                         .buttonStyle(.plain)
                         .contentShape(Rectangle())
                         .cardSurface()
                     }

                     VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                         Text("Type \(destructiveConfirmWord) to confirm").sectionHeader()

                         TextField(destructiveConfirmWord, text: $deleteAccountConfirmText)
                             .textInputAutocapitalization(.characters)
                             .autocorrectionDisabled()
                             .font(Theme.Text.body)
                             .padding(.vertical, 10)
                             .padding(.horizontal, 12)
                             .background(Theme.Colors.surface(colorScheme))
                             .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                             .overlay(
                                 RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                     .strokeBorder(Theme.Colors.stroke(colorScheme), lineWidth: 1)
                             )
                     }
                     .cardSurface()

                     Button(role: .destructive) {
                         // C-44 PRESENTATION BOUNDARY. Deletion is NOT started
                         // here. It starts from the sheet's onDismiss, once this
                         // sheet is fully gone, because the workflow presents
                         // Apple's authorization UI and ASAuthorizationController
                         // presents from the anchor window's root view
                         // controller — which cannot work while this sheet is
                         // still up. Only this explicit action sets the flag, so
                         // a swipe or Cancel dismissal can never start deletion.
                         pendingDeletionConfirmed = true
                         showDeleteAccountSheet = false
                     } label: {
                         HStack {
                             Spacer()
                             if deleteAccountInFlight {
                                 ProgressView()
                                     .padding(.trailing, 6)
                             }
                             Text(deleteAccountInFlight ? destructiveInFlightTitle : destructiveActionTitle)
                                 .font(Theme.Text.body.weight(.semibold))
                             Spacer()
                         }
                         .frame(maxWidth: .infinity)
                         .frame(height: 52)
                         .foregroundStyle(Color.white)
                         .background(
                             RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                 .fill(Color.red.opacity(0.48))
                         )
                     }
                     .buttonStyle(.plain)
                     .disabled(deleteAccountInFlight || deleteAccountConfirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != destructiveConfirmWord)
                     .opacity(deleteAccountInFlight || deleteAccountConfirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != destructiveConfirmWord ? 0.5 : 1.0)
                 }
                 .padding(.horizontal, Theme.Spacing.l)
                 .padding(.vertical, Theme.Spacing.section)
             }
             .appBackground()
             .tint(Theme.Colors.accent)
             .navigationTitle(destructiveActionTitle)
             .navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement: .cancellationAction) {
                     Button("Cancel") {
                         showDeleteAccountSheet = false
                     }
                 }
             }
         }
     }


     /// C-46. Called ONLY after a `LocalFactoryReset` has completed successfully,
     /// on either destructive branch. Never on a failed or cancelled deletion:
     /// dismissing Profile as generic cleanup would hide the error alert that
     /// tells the user their account was NOT deleted.
     ///
     /// Nothing in `LocalFactoryReset` clears `appRoute.isProfilePresented`, and
     /// it should not — the reset owns data, not navigation. This is the one
     /// place that knows the erase both finished and succeeded.
     ///
     /// C-49: dismissing the overlay is not enough. `MOTIVOApp.body` switches on
     /// `appRoute.route`, and the first-launch onboarding gate
     /// (`shouldRenderAppSetUpRoot`) exists only inside the `.timer` branch.
     /// Clearing `isProfilePresented` reveals whatever route was already
     /// underneath — `.content` when Profile was opened from the journal — where
     /// that gate is not in the view tree at all and is never evaluated. The
     /// result was an emptied journal after a successful erase, with onboarding
     /// appearing only after a force-quit, since a fresh launch defaults to
     /// `.timer`.
     ///
     /// Routing home here rather than in `LocalFactoryReset` is deliberate and
     /// keeps C-46's own rule intact: the reset owns data, not navigation. This
     /// is the one place that knows the erase both finished and succeeded, so it
     /// is the one place that may move the user — and, as C-46 established, it
     /// must never run on the failure path, where dismissing would hide the
     /// alert saying the account was NOT deleted.
     private func dismissProfileAfterSuccessfulErase() {
         onEraseComplete?()
         onClose?()
     }

     private func performDeleteAccount() async {
         // C-35: gated on IDENTITY, not on AppMode.
         //
         // This guard used to read `appModeManager.canShowConnectedAccountManagement`,
         // which is `mode == .connected` and therefore folds in `isEntitled`. A lapsed
         // member holding a full backend account fell through to the local-only branch,
         // so the only route to deleting their account was to re-subscribe first.
         //
         // Membership must never decide whether an existing account can be deleted.
         // If there is no Connected identity there is genuinely nothing remote to
         // delete, and the local reset is correct.
         guard auth.hasConnectedIdentity else {
             // C-44: wrapped so the whole destructive workflow is covered, not
             // just the reset phase. See AccountDeletionTransaction.
             await AccountDeletionTransaction.run(reason: "erase-all-etudes-data-local") {
                 deleteAccountInFlight = true
                 defer { deleteAccountInFlight = false }
                 // The sheet is already dismissed — onDismiss is what started us.
                 // C-70. FACTORY RESET IS THE EXPLICIT EXCEPTION TO DRAFT RETENTION.
                 // Set BEFORE the reset runs, and never cleared for this view's
                 // lifetime: `.onDisappear` fires after `isInProgress` is false
                 // again, and would otherwise re-create the erased text through
                 // `ProfileStore.setLocation` and `ctx.save()`.
                 viewInvalidatedByReset = true
                 directorySyncDebounceTask?.cancel()
                 directorySyncDebounceTask = nil
                 nameDraft.invalidateForFactoryReset()
                 localSaveMessage = nil
                 name = ""
                 locationText = ""
                await LocalFactoryReset.perform(reason: "erase-all-etudes-data-local", auth: auth)
                 dismissProfileAfterSuccessfulErase()
             }
             return
         }

         // Delete the backend account first, then perform the same local factory reset.
         //
         // C-35, SECOND MECHANISM — found by QA on 2026-08-13, after the first fix
         // had passed a structural audit.
         //
         // This guard read `BackendEnvironment.shared.isConnected`, which is
         // `currentBackendMode() == .backendConnected` — a runtime SERVICE-SELECTION
         // mode, chosen by AppModeManager.applyBackendRuntimeMode, which sets
         // .localSimulation for .solo and .backendConnected for .connected. AppMode
         // is resolved from `isEntitled`. So the moment a member lapsed, this guard
         // failed and the alert said "not currently available. Please try again" —
         // a retry that could never succeed.
         //
         // That is C-35's own defect a second time, reached by a different route:
         // an ENTITLEMENT DEPENDENCY LAUNDERED THROUGH A UserDefaults KEY. The
         // deletion path was audited for `isEntitled`, `AppMode` and
         // `canShowConnectedAccountManagement` and contained none of them by name,
         // which is precisely why a grep could not find this and running it could.
         //
         // BackendConfig.isConfigured is the right precondition: it reads the
         // bundled apiBaseURL and apiToken, is independent of AppMode, and is the
         // actual requirement of the request — deleteCurrentConnectedAccount builds
         // its own URLRequest against BackendConfig.apiBaseURL via URLSession and
         // never touches BackendEnvironment at all. The service re-checks the same
         // condition and throws .backendNotConfigured, so this is a friendly
         // pre-check rather than the authority.
         //
         // Do not reintroduce any BackendEnvironment or AppMode term here.
         guard BackendConfig.isConfigured else {
             deleteAccountErrorMessage = "Études Connected is unavailable. Please try again."
             showDeleteAccountErrorAlert = true
             return
         }

         // C-44: the entire destructive workflow runs inside one transaction —
         // Apple authorization, revocation, backend deletion, local reset. C-45's
         // credential-state observer reads this flag and defers, because a
         // SUCCESSFUL revocation makes Apple report `.revoked`, and signing out
         // on that signal mid-workflow would destroy the Supabase session that
         // delete_account_v1 still needs.
         await AccountDeletionTransaction.run(reason: "delete-account") {
         deleteAccountInFlight = true
         defer { deleteAccountInFlight = false }

         // C-44: revoke BEFORE deleting. The order is forced — delete_account_v1
         // removes the auth.users row that authenticates this call. The converse
         // was checked and is safe: revoking at Apple does not invalidate the
         // Supabase JWT, which is independent of Apple's grant.
         //
         // `attemptRevocation` cannot throw. That is the structural guarantee
         // that a revocation failure can never prevent deletion (TN3194: "you
         // must still fulfill the user's account deletion request"). Do not
         // "improve" this into a throwing call.
         // The outcome is logged inside the service, through a single funnel,
         // with os.Logger at privacy: .public — deliberately NOT `#if DEBUG`.
         // The first Device A run failed here and could not be diagnosed because
         // the only diagnostic was Debug-gated while the rig runs Release.
         let revocation = await AppleRevocationService.attemptRevocation(
             auth: auth,
             reason: "delete-account"
         )

         do {
             try await ConnectedAccountDeletionService.deleteCurrentConnectedAccount(
                 auth: auth,
                 reason: "delete-account"
             )
             // C-70. FACTORY RESET IS THE EXPLICIT EXCEPTION TO DRAFT RETENTION.
             // Set BEFORE the reset runs, and never cleared for this view's
             // lifetime: `.onDisappear` fires after `isInProgress` is false
             // again, and would otherwise re-create the erased text through
             // `ProfileStore.setLocation` and `ctx.save()`.
             viewInvalidatedByReset = true
             directorySyncDebounceTask?.cancel()
             directorySyncDebounceTask = nil
             nameDraft.invalidateForFactoryReset()
             localSaveMessage = nil
             name = ""
             locationText = ""
                await LocalFactoryReset.perform(reason: "erase-all-etudes-data-connected", auth: auth)
             dismissProfileAfterSuccessfulErase()

             // TN3194 step 2 — "Direct the user to manually revoke access for
             // your client" — shown only when revocation did not succeed, and
             // only after deletion has. Presented from the app root, not here:
             // ProfileView is a conditional overlay and may be gone by now.
             if !revocation.didRevoke {
                 AppleRevocationNotice.shared.isPending = true
             }
         } catch {
             // C-35: distinguish "your session expired" from "we couldn't reach the
             // server", because the recoveries differ and the old copy told the user
             // to sign out — which by this point has usually already happened.
             //
             // The discriminator is free rather than plumbed: a genuine refresh
             // failure WITHDRAWS the Connected identity, so `hasConnectedIdentity`
             // is false; transient and offline failures are guarded against that in
             // refreshSupabaseSession and leave it intact.
             //
             // 2026-09-07: that withdrawal is `clearConnectedIdentity`, no longer
             // `signOut()`. The discriminator is UNAFFECTED — both nil
             // `currentUserID` — but `signOut()` additionally destroyed the user's
             // attachment titles, which a refresh failure has no business doing.
             // Neither message may ever suggest re-subscribing —
             // re-AUTHENTICATION can be required, re-SUBSCRIPTION never.
             deleteAccountErrorMessage = auth.hasConnectedIdentity
                 ? "Couldn’t reach Études Connected. Check your connection and try again."
                 : "Your session has expired. Sign in with Apple again to delete your account — you don’t need to re-subscribe."
             showDeleteAccountErrorAlert = true
         }
         } // AccountDeletionTransaction.run
     }

private func initials(from string: String) -> String {
         let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
         if trimmed.isEmpty {
             return "Y"
         }
         let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
         if words.count == 1 {
             let first = words[0]
             if let firstLetter = first.first {
                 return String(firstLetter).uppercased()
             }
             return "Y"
         } else {
             let firstInitial = words.first?.first.map { String($0).uppercased() } ?? ""
             let lastInitial = words.last?.first.map { String($0).uppercased() } ?? ""
             return firstInitial + lastInitial
         }
     }
 
     private func modalsAndAlerts<V: View>(_ base: V) -> some View {
         var view = AnyView(base)
         view = AnyView(view
            .onAppear(perform: onAppearLoad)
            .onDisappear { persistProfileEdits() }
            // C-70. Backgrounding is a commit point. Without it an app killed
            // while Profile is on screen loses the edit entirely — the pending
            // change is NOT on disk (measured, M4 proxy).
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistProfileEdits() }
            }
            // C-24: sign-in completion is an event, not a change of identity. On a
            // reinstall the Keychain still holds the Apple user ID, so `currentUserID`
            // never changes and none of this would run if it were keyed on that.
            .onChange(of: auth.signInCompletionCount) { _, _ in
                guard auth.currentUserID != nil else { return }

                // Signed-out gate flow:
                // after a successful Sign in with Apple from the gate-presented ProfileView,
                // dismiss the gate and reveal PracticeTimerView directly.
                // F1. THE JOIN PURPOSE IS TESTED FIRST, and clearing the flag is
                // part of the fix rather than tidying.
                //
                // `signedOutGateView` has ONE render site and the sheet has THREE
                // openers, all of which set `connectedSignInIntent` — so the
                // intent is a complete discriminator, while
                // `signedOutGateWasVisible` is set unconditionally by a view that
                // cannot know why it is on screen. Testing the flag first
                // consumed the event and returned, so the `.join` branch below —
                // which exists precisely to keep a joining member in the flow they
                // just authenticated to continue — was unreachable, and `onClose`
                // (non-nil in BOTH presentations) dismissed Profile entirely.
                //
                // The flag must also be CLEARED, not merely bypassed:
                // `shouldSuppressSignedInProfileAfterGateSignIn` renders
                // `Color.clear` while it is set, so continuing into the join
                // without clearing it would leave a blank Profile underneath the
                // membership screen.
                if connectedSignInIntent == .join {
                    signedOutGateWasVisible = false
                    showConnectedSignInSheet = false
                    showMembershipSelection = true
                    return
                }

                if signedOutGateWasVisible {
                    showConnectedSignInSheet = false

                    if let onClose {
                        onClose()
                    } else {
                        // Nothing else will dismiss this ProfileView, and the
                        // suppression view clears only on sign-out, so it would
                        // otherwise be left on screen as a blank page.
                        signedOutGateWasVisible = false
                    }
                    return
                }

                // U5f's `.join` branch MOVED ABOVE the gate branch — see F1.
                // Its reasoning is unchanged and now reachable: authentication
                // used to be the LAST step of joining, so any success here
                // unwound the whole stack; under B-24 it is the FIRST step, and
                // unwinding a joining member drops them out of the flow they just
                // authenticated in order to continue.

                // Returning member: signing in IS the whole errand. Unwind, as
                // before. Entitlement resolves from local StoreKit and the server
                // learns of it through attestation, neither of which needs this
                // screen to stay open.
                if showConnectedSignInSheet || showMembershipSelection || showConnectedIntroduction {
                    showConnectedSignInSheet = false
                    showMembershipSelection = false
                    showConnectedIntroduction = false
                    showAboutEtudes = false
                }
            }
            .onChange(of: auth.currentUserID) { oldValue, newValue in

                // Identity scoping: clear on sign-out; repopulate on sign-in.
                // Hygiene: persist any in-memory edits for the *previous* signed-in identity
                // before we clear UI state (location is stored per-user in ProfileStore).
                if newValue == nil {
                    // Delete Account v2: during a factory reset, never persist per-user location back to ProfileStore.
                    //
                    // C-70. `localStorageIsUsable`, NOT `isInProgress` alone. A
                    // SwiftUI `onChange` can arrive after the reset's `defer` has
                    // cleared that flag, and while `save()` would then refuse via
                    // the view-lifetime flag, these two `ProfileStore` writes
                    // would still run and re-create the erased location. Same
                    // no-resurrection boundary, not extra scope.
                    if !localStorageIsUsable {
                        clearUserPresentedStateForSignOut()
                        return
                    }

                    if let oldBackendID = auth.backendUserID {
                        ProfileStore.setLocation(locationText, for: oldBackendID)
                    }

                    // Preserve the currently presented profile as the local Études profile after sign-out.
                    //
                    // C-70. The Result is no longer discarded. Identity scoping is
                    // DELIBERATELY UNCHANGED — the old-owner write above and the
                    // `nil`-owner write below both still happen exactly as before;
                    // only the silence is removed. Without this, a failure here
                    // reports nowhere, and the debounce that might otherwise have
                    // retried has just been cancelled by the identity transition.
                    switch save() {
                    case .success:
                        nameDraft.evidencedSaved()
                        localSaveMessage = nil
                    case .failure:
                        localSaveMessage = "Not saved yet. Your changes are still here — try again."
                    }
                    ProfileStore.setLocation(locationText, for: nil)
                    onAppearLoad()
                } else {
                    onAppearLoad()
                }
            }
            .onChange(of: auth.backendUserID) { _, newValue in
                // C-70. CANCEL THE PRE-SUBMIT DEBOUNCE.
                //
                // `DirectoryWriteCoordinator` owns a write only AFTER it is
                // submitted. A task scheduled under identity A that fires after a
                // switch to B has not been submitted yet, so no token can see it
                // — it would compose A's edit and send it as B.
                //
                // The local NAME draft is deliberately NOT discarded here: it is
                // device-local (`Profile` is fetched with no owner predicate) and
                // sign-out already preserves it as the local Études profile. Only
                // the remote submission and the per-owner handle/location drafts
                // belong to the identity.
                directorySyncDebounceTask?.cancel()
                directorySyncDebounceTask = nil
                directorySyncLatch.invalidate()
                // Phase 12C: user-scoped lookup state (per backend identity)
                if newValue == nil {
                    discoveryModeRawPerUser = DiscoveryMode.search.rawValue
                    locationText = ProfileStore.location(for: nil)
                } else {
                    discoveryModeRawPerUser = ProfileStore.discoveryModeRaw(for: auth.backendUserID)
                    locationText = ProfileStore.presentedLocation(for: auth.backendUserID) // C-36
                }
            }
            .onChange(of: primaryActivityRef) {
                primaryActivityChoice = normalizedPrimaryActivityRef()
            }
             .onChange(of: name) { _, _ in
                 // C-70. Dirty is marked in `nameEditingBinding`, NOT here — this
                 // also fires for PROGRAMMATIC assignment, so marking here would
                 // let hydration mark its own result dirty and never clear.
                 //
                 // NO OUTER `Task`: it was untracked, so it could run AFTER the
                 // identity handler cancelled the current debounce and schedule a
                 // fresh task carrying the old identity's edit. `onChange` is
                 // already on the main actor, so the call is direct and the
                 // cancellation in the identity handler is actually sufficient.
                 scheduleDirectorySyncDebounced()
             }
             .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: ctx)) { _ in
                 guard showInstrumentManager == false,
                       showActivityManager == false,
                       showTasksManager == false,
                       showDeleteAccountSheet == false,
                       showAvatarEditor == false,
                       showPhotoPicker == false else { return }
                 load()
             }
             .onChange(of: locationText) { _, _ in
                 // C-70. Same reasoning as `name` above: no untracked outer Task.
                 scheduleDirectorySyncDebounced()
             }
             // EVENTS 1 AND 3, in ONE observer over BOTH asynchronous inputs.
             //
             // 1 — failure before success: the completion that makes a refused
             //     write worth retrying.
             // 3 — completion before absence: row absence arrives on its own
             //     schedule, so a completion landing while it is still unknown
             //     is missed by events 1 and 2 alike.
             //
             // One `onChange` rather than two because either input changing asks
             // the same question, and because this body is already at the
             // type-checker's limit — two separate modifiers here failed to
             // compile in reasonable time.
             .onChange(of: reconciliationInputs) { _, _ in
                 reconcileDirectoryIfAttestationAllows()
             }
             .alert("Primary Activity reset", isPresented: $showPrimaryFallbackAlert) {
                 Button("OK", role: .cancel) {}
             } message: {
                 Text("Your Primary Activity was removed, so it’s been reset to Practice.")
             }
             .alert("Avatar update failed", isPresented: $showAvatarSyncErrorAlert) {
                 Button("OK", role: .cancel) {}
             } message: {
                 Text(avatarSyncErrorMessage ?? "Couldn’t update your avatar. Please try again.")
             }

             .alert("Erase failed", isPresented: $showDeleteAccountErrorAlert) {
                 Button("OK", role: .cancel) {}
             } message: {
                 Text(deleteAccountErrorMessage ?? "Couldn’t erase your Études data. Please try again.")
             }
             .sheet(isPresented: $showDeleteAccountSheet, onDismiss: {
                 // C-44: the destructive workflow starts HERE, not in the
                 // button, so Apple's authorization UI has a clean presentation
                 // context. No sleep and no timing guess — onDismiss fires only
                 // once the sheet is actually gone.
                 //
                 // The flag is CONSUMED before the async work begins, so an
                 // unrelated later dismissal of this sheet cannot replay
                 // deletion. Ordinary swipe-to-dismiss and Cancel never set it.
                 guard pendingDeletionConfirmed else { return }
                 pendingDeletionConfirmed = false
                 Task { await performDeleteAccount() }
             }) {
                 deleteAccountSheet
             }

             .sheet(isPresented: $showInstrumentManager) {
                 InstrumentListView()
                     .environment(\.managedObjectContext, ctx)
             }
             .onChange(of: showInstrumentManager) { _, newValue in
                 // When instrument manager closes, rehydrate local ProfileView state before any later save path can write stale values back.
                 if newValue == false {
                     load()
                     scheduleDirectorySyncDebounced(nanoseconds: 200_000_000)
                 }
             }
             .sheet(isPresented: $showActivityManager) {
                 ActivityListView()
                     .environment(\.managedObjectContext, ctx)
             }
             .onChange(of: showActivityManager) { _, newValue in
                 if newValue == false {
                     refreshUserActivities()
                     primaryActivityChoice = normalizedPrimaryActivityRef()
                 }
             }
             .sheet(isPresented: $showTasksManager) {
                 TasksManagerView(activityRef: normalizedPrimaryActivityRef())
                     .environment(\.managedObjectContext, ctx)
             }
         )
         #if canImport(PhotosUI)
         view = AnyView(view.sheet(isPresented: $showPhotoPicker) {
             PhotoPickerView { image in
                 if let image {
                     ProfileStore.saveAvatarOriginal(image, for: auth.currentUserID)
                     ProfileStore.saveAvatarOriginal(image, for: nil)
                     // Do not overwrite derived automatically; user confirms via editor.
                     // If no derived exists yet, you may choose to show the editor or leave as is.
                     if ProfileStore.avatarImage(for: auth.currentUserID) == nil {
                         // Keep displayed avatar nil until user saves from editor
                         avatarImage = nil
                     } else {
                         avatarImage = ProfileStore.avatarImage(for: auth.currentUserID)
                     }
                 }
             }
         })
         #endif
         view = AnyView(view.sheet(isPresented: $showAvatarEditor) { avatarEditorSheet })
         return view
     }
 }
 
 //  [ROLLBACK ANCHOR] v7.8 DesignLite — post
 
 #if canImport(PhotosUI)
 import PhotosUI
 struct PhotoPickerView: UIViewControllerRepresentable {
     var onPick: (UIImage?) -> Void
 
     func makeUIViewController(context: Context) -> PHPickerViewController {
         var config = PHPickerConfiguration(photoLibrary: .shared())
         config.filter = .images
         config.selectionLimit = 1
         let picker = PHPickerViewController(configuration: config)
         picker.delegate = context.coordinator
         return picker
     }
 
     func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
 
     func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
 
     final class Coordinator: NSObject, PHPickerViewControllerDelegate {
         let onPick: (UIImage?) -> Void
         init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
         func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
             guard let first = results.first else { picker.dismiss(animated: true); onPick(nil); return }
             if first.itemProvider.canLoadObject(ofClass: UIImage.self) {
                 first.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                     DispatchQueue.main.async {
                         picker.dismiss(animated: true)
                         self.onPick(obj as? UIImage)
                     }
                 }
             } else {
                 DispatchQueue.main.async { picker.dismiss(animated: true); self.onPick(nil) }
             }
         }
     }
 }
 #endif
