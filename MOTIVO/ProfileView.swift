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

 import SwiftUI
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
        case .search:   return "Allow handle lookup"
        case .contacts: return "Email invites"
        }
    }
}

 // MARK: - Setting Row (label + value, single-line, calm)
 fileprivate struct SettingRow: View {
     let title: String
     let value: String
     var body: some View {
         HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
             Text(title)
                 .font(.callout)
                 .foregroundStyle(Theme.Colors.secondaryText.opacity(0.8))
                 .lineLimit(1)
                 .truncationMode(.tail)
 
             Spacer(minLength: Theme.Spacing.l)
 
             Text(value)
                 .font(Theme.Text.body)
                 .foregroundStyle(.primary)
                 .lineLimit(1)
                 .minimumScaleFactor(0.9)
                 .truncationMode(.tail)
         }
         .contentShape(Rectangle())
     }
 }
 
 struct ProfileView: View {
     @Environment(\.managedObjectContext) private var ctx
     @EnvironmentObject private var auth: AuthManager
    @Environment(\.colorScheme) private var colorScheme
 
     // Close-first strategy
     var onClose: (() -> Void)? = nil
 
     @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
     private var instruments: FetchedResults<Instrument>
 
     @State private var name: String = ""
     @State private var primaryInstrumentName: String = ""
     @State private var defaultPrivacy: Bool = false

     @AppStorage("appSettings_showDroneStrip") private var showDroneStrip: Bool = true
     @AppStorage("appSettings_showMetronomeStrip") private var showMetronomeStrip: Bool = true
     @AppStorage("appSettings_showTasksPad") private var showTasksPad: Bool = true
    @AppStorage("appSettings_showTuner") private var showTuner: Bool = true
    @AppStorage("appSettings_tintMode") private var tintModeRaw: String = Theme.TintMode.auto.rawValue

@FocusState private var isNameFocused: Bool
@FocusState private var isLocationFocused: Bool
@FocusState private var isAccountIDFocused: Bool
 
     @State private var showInstrumentManager: Bool = false

    private func clearNameFieldFocus() {
        isNameFocused = false
        isLocationFocused = false
        isAccountIDFocused = false
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
 
     
    // Privacy & Discovery (local-first; future-sync to backend)
    // NOTE: profileVisibility_v1 is retained for legacy compatibility, but is not surfaced in UI.
    @AppStorage("profileVisibility_v1") private var profileVisibilityRaw: Int = 1
    @AppStorage("followRequestMode_v1") private var followRequestModeRaw: Int = FollowRequestMode.manual.rawValue
    @AppStorage("allowDiscovery_v1") private var allowDiscoveryLegacyRaw: Int = DiscoveryMode.none.rawValue
    @State private var discoveryModeRawPerUser: Int = DiscoveryMode.none.rawValue
    @State private var accountIDText: String = ""

    // Phase 13A — Account ID collision UX (shipping)
    @State private var accountIDSyncMessage: String? = nil
    @State private var accountIDSyncIsError: Bool = false

    @State private var directorySyncDebounceTask: Task<Void, Never>? = nil
    @State private var lastDirectorySyncFingerprint: String? = nil
    @State private var lastAccountIDSubmitAt: Date? = nil
    @State private var accountIDAutoGenerationInFlight: Bool = false
    @State private var accountIDAutoGenerationAttemptedBackendID: String? = nil
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
     @State private var showTintModeSelection: Bool = false
    @State private var signedOutGateWasVisible: Bool = false
    @State private var signedOutGateCloseRequested: Bool = false

    private var shouldSuppressSignedInProfileAfterGateSignIn: Bool {
        signedOutGateWasVisible && auth.currentUserID != nil && onClose != nil
    }

     var body: some View {
         modalsAndAlerts(
             NavigationStack {
                ZStack {
                    if shouldSuppressSignedInProfileAfterGateSignIn {
                        Color.clear
                            .onAppear(perform: closeSignedOutGateAfterSuccessfulSignInIfNeeded)
                    } else if auth.isSignedIn {
                        Form {
                     Group {
                         profileSection
                         privacySection
                         sessionSetupSection
                     }
                     Group {
                             appSettingsSection
                     }
                        }
                        .background(KeyboardDismissFormTapCatcher(onDismiss: {
                            clearNameFieldFocus()
                        }))
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                            clearNameFieldFocus()
                        })
                    } else {
                        signedOutGateView
                    }
                }
                .font(.callout)
                .navigationTitle("")
                .toolbar {
                     toolbarContent
                }
                .navigationDestination(isPresented: $showAboutEtudes) {
                    AboutEtudesView()
                }
                .navigationDestination(isPresented: $showTintModeSelection) {
                    TintModeSelectionView()
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
                signedOutGateCloseRequested = false
            }
        }
    }

    private func closeSignedOutGateAfterSuccessfulSignInIfNeeded() {
        guard signedOutGateWasVisible else { return }
        guard signedOutGateCloseRequested == false else { return }
        guard auth.currentUserID != nil else { return }
        signedOutGateCloseRequested = true
        onClose?()
    }


// MARK: - Sections

     private var profileSection: some View {
         Section(header: Text("Profile").sectionHeader()) {
             VStack(alignment: .leading, spacing: 4) {
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

                         TextField("Name", text: $name)
                             .textInputAutocapitalization(.words)
                             .disableAutocorrection(true)
                             .focused($isNameFocused)
                             .onSubmit { isNameFocused = false }
                             .scaleEffect(isNameFocused ? 0.995 : 1)
                             .overlay(alignment: .bottomLeading) {
                                 Rectangle().frame(height: 1).opacity(isNameFocused ? 0.15 : 0)
                             }
                             .animation(.easeInOut(duration: 0.18), value: isNameFocused)
                     }
                     .padding(.vertical, Theme.Spacing.s)
                     .frame(minHeight: 44, alignment: .center)
                     .overlay(alignment: .bottom) {
                         Divider()
                             .padding(.leading, 16)
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
                     }
                     .padding(.vertical, Theme.Spacing.s)
                     .frame(minHeight: 44, alignment: .center)
                     .overlay(alignment: .bottom) {
                         Divider()
                             .padding(.leading, 16)
                     }

                     HStack(spacing: 10) {
                         if !accountIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                             Text("@")
                                 .font(Theme.Text.meta)
                                 .foregroundStyle(Theme.Colors.secondaryText)
                         }

                         TextField("Account ID : How people find you.", text: $accountIDText)
                             .textInputAutocapitalization(.never)
                             .autocorrectionDisabled(true)
                             .keyboardType(.asciiCapable)
                             .onChange(of: accountIDText) { _, newValue in
                                 let normalized = normalizeAccountID(newValue)
                                 if normalized != newValue { accountIDText = normalized }
                                 // Clear any prior sync feedback as the user edits.
                                 accountIDSyncMessage = nil
                                 accountIDSyncIsError = false
                                 ProfileStore.setAccountID(accountIDText, for: auth.backendUserID)
                             }
                             .focused($isAccountIDFocused)
                             .onChange(of: isAccountIDFocused) { oldValue, newValue in
                                 // Commit-only: on blur, sync once with the latest sanitized state.
                                 // Guard: Return/Done often triggers both onSubmit and a blur; avoid double-posting.
                                 if oldValue == true && newValue == false {
                                     if let t = lastAccountIDSubmitAt, Date().timeIntervalSince(t) < 0.35 {
                                         return
                                     }
                                     Task { await syncDirectoryFromCurrentState() }
                                 }
                             }
                             .onSubmit {
                                 // Commit-only: on Return/Done, sync once.
                                 lastAccountIDSubmitAt = Date()
                                 Task { await syncDirectoryFromCurrentState() }
                                 isAccountIDFocused = false
                             }
                             .font(Theme.Text.meta)
                             .foregroundStyle(Color.primary)
                     }
                     .padding(.vertical, Theme.Spacing.s)
                     .frame(minHeight: 44, alignment: .center)
                 }
                 .cardSurface(padding: Theme.Spacing.m)

                 if let msg = accountIDSyncMessage {
                     Text(msg)
                         .font(Theme.Text.meta)
                         .foregroundStyle(accountIDSyncIsError ? Color.red : Theme.Colors.secondaryText)
                         .padding(.top, 2)
                 }
             }
         }
         .listRowSeparator(.hidden)
     }


@ViewBuilder
    private var privacySection: some View {
        Section(header: Text("Privacy & connection").sectionHeader()) {
            VStack(spacing: 0) {
                Toggle("Default to Private Posts", isOn: $defaultPrivacy)
                    .tint(Theme.Colors.accent)
                    .padding(.vertical, Theme.Spacing.s)
                    .frame(minHeight: 44, alignment: .center)
                    .font(Theme.Text.body)
                    .overlay(alignment: .bottom) {
                        Divider()
                            .padding(.leading, 16)
                    }

                Toggle(
                    "Allow follow requests",
                    isOn: Binding(
                        get: {
                            (FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual) == .manual
                        },
                        set: { isOn in
                            followRequestModeRaw = isOn
                                ? FollowRequestMode.manual.rawValue
                                : FollowRequestMode.autoApproveContacts.rawValue
                        }
                    )
                )
                .tint(Theme.Colors.accent)
                .padding(.vertical, Theme.Spacing.s)
                .frame(minHeight: 44, alignment: .center)
                .font(Theme.Text.body)
                .overlay(alignment: .bottom) {
                    Divider()
                        .padding(.leading, 16)
                }

                Toggle(
                    "Searchable by name",
                    isOn: Binding(
                        get: {
                            (DiscoveryMode(rawValue: discoveryModeRawPerUser) ?? .none) == .search
                        },
                        set: { isOn in
                            discoveryModeRawPerUser = isOn
                                ? DiscoveryMode.search.rawValue
                                : DiscoveryMode.none.rawValue
                        }
                    )
                )
                .tint(Theme.Colors.accent)
                .padding(.vertical, Theme.Spacing.s)
                .frame(minHeight: 44, alignment: .center)
                .font(Theme.Text.body)
            }
            .cardSurface(padding: Theme.Spacing.m)
            .listRowSeparator(.hidden)
        }
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
                     Divider()
                         .padding(.leading, 16)
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
                     Divider()
                         .padding(.leading, 16)
                 }

                 Button { showTintModeSelection = true } label: {
                     navigationRow(title: "Tint Mode", value: currentTintMode.displayName)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     Divider()
                         .padding(.leading, 16)
                 }

                 Button { showTasksManager = true } label: {
                     navigationRow(title: "Tasks")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     Divider()
                         .padding(.leading, 16)
                 }

                 Toggle(isOn: $showMetronomeStrip) {
                     Text("Show Metronome")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     Divider()
                         .padding(.leading, 16)
                 }

                 Toggle(isOn: $showDroneStrip) {
                     Text("Show Drone")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     Divider()
                         .padding(.leading, 16)
                 }

                 Toggle(isOn: $showTasksPad) {
                     Text("Show Tasks Pad")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     Divider()
                         .padding(.leading, 16)
                 }

                 Toggle(isOn: $showTuner) {
                     Text("Show Tuner")
                 }
                 .tint(Theme.Colors.accent)
                 .padding(.vertical, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
             }
             .cardSurface(padding: Theme.Spacing.m)
             .listRowSeparator(.hidden)
         }
     }

     @ViewBuilder
     private var appSettingsSection: some View {
         Section(header: Text("Account").sectionHeader()) {
             VStack(spacing: 0) {
                 Button { showAboutEtudes = true } label: {
                     navigationRow(title: "About Études")
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
                 .overlay(alignment: .bottom) {
                     Divider()
                         .padding(.leading, 16)
                 }

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
                     Divider()
                         .padding(.leading, 16)
                 }

                 Button {
                     deleteAccountConfirmText = ""
                     showDeleteAccountSheet = true
                 } label: {
                     Text("Delete account")
                         .foregroundStyle(.red)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .frame(minHeight: 44, alignment: .center)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .font(Theme.Text.body)
             }
             .cardSurface(padding: Theme.Spacing.m)
             .listRowSeparator(.hidden)
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
                 avatarImage = ProfileStore.avatarImage(for: auth.currentUserID)
                 showAvatarEditor = false

                 Task { await persistAvatarToBackendIfPossible(jpegData: jpegData) }
             },
             onDelete: {
                 // Local clear immediately.
                 ProfileStore.deleteAvatar(for: auth.currentUserID)
                 avatarRefreshTask?.cancel()
         avatarRefreshTask = nil
         avatarImage = nil
                 showAvatarEditor = false

                 Task { await clearAvatarFromBackendIfPossible() }
             },
             onCancel: { showAvatarEditor = false },
             onReplaceOriginal: { image in
                 ProfileStore.saveAvatarOriginal(image, for: auth.currentUserID)
                 // Do not auto-update derived; keep current derived until user taps Save in the editor.
             }
         )
         .presentationDetents([.large])
     }
 
     // MARK: - Lifecycle / Data
 
     private func onAppearLoad() {
         // Identity scoping hygiene: when signed out, Profile must render empty (no user data).
         guard auth.currentUserID != nil else {
             clearUserPresentedStateForSignOut()
             return
         }

         load()
         refreshUserActivities()
         primaryActivityChoice = normalizedPrimaryActivityRef()
         if primaryFallbackNoticeNeeded {
             showPrimaryFallbackAlert = true
             primaryFallbackNoticeNeeded = false
         }
         refreshAvatarDisplay()
         self.locationText = ProfileStore.location(for: auth.backendUserID)

         // Phase 12C: per-backend-user lookup state (per-user; legacy allowDiscovery_v1 adopted as initial default)
         discoveryModeRawPerUser = ProfileStore.discoveryModeRaw(for: auth.backendUserID)
         accountIDText = ProfileStore.accountID(for: auth.backendUserID)
     }

     private func clearUserPresentedStateForSignOut() {
         // Clear all user-presented state without mutating persisted device-level Profile.
         profile = nil
         name = ""
         primaryInstrumentName = ""
         defaultPrivacy = false
         avatarImage = nil
         locationText = ""
         accountIDText = ""
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
         return "\(currentUserID)|\(backendAvatarKey)"
     }

     @MainActor
     private func refreshAvatarDisplay() {
         avatarRefreshTask?.cancel()
         avatarRefreshTask = nil

         let currentUserID = auth.currentUserID
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
                     avatarImage = fetchedImage
                 }

                 avatarRefreshTask = nil
             }
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
 
     private func navigationRow(title: String, value: String? = nil) -> some View {
         HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
             Text(title)
                 .foregroundStyle(.primary)

             Spacer(minLength: Theme.Spacing.l)

             if let value {
                 Text(value)
                     .font(Theme.Text.body)
                     .foregroundStyle(.primary)
                     .lineLimit(1)
                     .minimumScaleFactor(0.9)
                     .truncationMode(.tail)
             }

             Image(systemName: "chevron.right")
                 .font(.footnote.weight(.semibold))
                 .padding(6)
                 .background(.ultraThinMaterial, in: Circle())
                 .foregroundStyle(Theme.Colors.secondaryText)
         }
     }
 
     // MARK: - Data
 
     private var instrumentsArray: [String] {
         instruments.map { $0.name ?? "" }.filter { !$0.isEmpty }
     }
 
     private func load() {
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
 
         name = profile?.name ?? ""
         primaryInstrumentName = (profile?.primaryInstrument ?? "").isEmpty
             ? (instrumentsArray.first ?? "")
             : (profile?.primaryInstrument ?? "")
         defaultPrivacy = profile?.defaultPrivacy ?? false
     }
 
     private func save() {
         guard let p = profile else { return }
         if p.value(forKey: "id") == nil {
             p.setValue(UUID(), forKey: "id")
         }
         p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
         p.primaryInstrument = primaryInstrumentName.trimmingCharacters(in: .whitespacesAndNewlines)
         p.defaultPrivacy = defaultPrivacy
         do { try ctx.save() } catch { }
     }

     private func persistProfileEdits() {
         // Do not persist user-presented state when signed out.
         guard auth.currentUserID != nil else { return }
         save()
         ProfileStore.setLocation(locationText, for: auth.backendUserID)
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
 
     // Phase 12C — Handle normalization (client-side). Server enforces strict rules; this keeps UI deterministic.
     private func normalizeAccountID(_ raw: String) -> String {
         var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
         if s.hasPrefix("@") { s = String(s.dropFirst()) }
         // Allowed: a–z, 0–9, underscore
         s = String(s.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" })
         // Max length 24
         if s.count > 24 { s = String(s.prefix(24)) }
         return s
     }

 
    // Phase 12C hygiene: avoid directory upserts on every keystroke.
    @MainActor
    private func scheduleDirectorySyncDebounced(nanoseconds: UInt64 = 650_000_000) {
        directorySyncDebounceTask?.cancel()
        directorySyncDebounceTask = Task {
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await syncDirectoryFromCurrentState()
        }
    }

    // Phase 12C — Owner-only directory upsert/disable. No profile sync; only minimal identity surface.
     @MainActor
     private func syncDirectoryFromCurrentState() async {
        // Phase 14.3H (B2) — Never attempt account_directory upsert unless we have a valid Supabase bearer token.
        // Prevents unauthenticated upsert attempts during the sign-in transition (which can leave ProfileView in an empty limbo on first sign-in).
        let auth = _auth.wrappedValue
        guard BackendEnvironment.shared.isConnected else { return }
        guard auth.hasSupabaseAccessToken else { return }

         guard let backendID = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !backendID.isEmpty else { return }
         let display = name.trimmingCharacters(in: .whitespacesAndNewlines)
         // If user hasn’t opted in, ensure lookup is disabled (row may still exist).
         let enabled = (DiscoveryMode(rawValue: discoveryModeRawPerUser) ?? .none) == .search
         let frm = (FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual)
         let followRequestsEnabled = !(frm == .autoApproveContacts || frm == .closed)
         let acct = accountIDText.trimmingCharacters(in: .whitespacesAndNewlines)
         let storedAccountID = ProfileStore.accountID(for: backendID).trimmingCharacters(in: .whitespacesAndNewlines)
         // Account ID is user-scoped. During sign-out/delete/recreate transitions, accountIDText can briefly
         // contain the previous user's handle. Only send an explicit account_id when it matches the value stored
         // for the current backend user; otherwise omit it so auto-generation can safely derive from this user's name.
         let acctOrNil: String? = (acct.count >= 3 && !storedAccountID.isEmpty && acct == storedAccountID) ? acct : nil
         let locTrim = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
         let locOrNil: String? = locTrim.isEmpty ? nil : locTrim
         let instrumentsClean = instrumentsArray
             .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
         let instrumentsSorted = instrumentsClean.sorted { a, b in
             a.localizedCaseInsensitiveCompare(b) == .orderedAscending
         }

         let instrumentsFP = instrumentsSorted.joined(separator: ",")
         let fingerprint = "\(backendID)|\(display)|\(locOrNil ?? "nil")|\(acctOrNil ?? "nil")|\(enabled ? "1" : "0")|fr:\(followRequestsEnabled ? "1" : "0")|i:\(instrumentsFP)"
         if fingerprint == lastDirectorySyncFingerprint { return }
         let result = await AccountDirectoryService.shared.upsertSelfRow(
             userID: backendID,
             displayName: display,
             accountID: acctOrNil,
             lookupEnabled: enabled,
             followRequestsEnabled: followRequestsEnabled,
             location: locOrNil,
             instruments: instrumentsSorted
         )
         switch result {
case .success:
    lastDirectorySyncFingerprint = fingerprint
    accountIDSyncMessage = nil
    accountIDSyncIsError = false
    await attemptAccountIDAutoGenerationIfNeeded(
        backendID: backendID,
        displayName: display,
        lookupEnabled: enabled,
        followRequestsEnabled: followRequestsEnabled,
        location: locOrNil,
        instruments: instrumentsSorted
    )
case .failure(let error):
    if isAccountIDCollision(error) {
        accountIDSyncMessage = "That account ID is already taken."
    } else {
        accountIDSyncMessage = "Couldn’t update your Account ID. Please try again."
    }
    accountIDSyncIsError = true
}
     }

    @MainActor
    private func attemptAccountIDAutoGenerationIfNeeded(
        backendID: String,
        displayName: String,
        lookupEnabled: Bool,
        followRequestsEnabled: Bool,
        location: String?,
        instruments: [String]
    ) async {
        guard BackendEnvironment.shared.isConnected else { return }
        let auth = _auth.wrappedValue
        guard auth.hasSupabaseAccessToken else { return }

        let trimmedBackendID = backendID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBackendID.isEmpty else { return }
        guard auth.backendUserID?.caseInsensitiveCompare(trimmedBackendID) == .orderedSame else { return }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else { return }

        let storedAccountID = ProfileStore.accountID(for: trimmedBackendID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard storedAccountID.isEmpty else { return }

        guard accountIDAutoGenerationInFlight == false else { return }
        guard accountIDAutoGenerationAttemptedBackendID?.caseInsensitiveCompare(trimmedBackendID) != .orderedSame else { return }

        accountIDAutoGenerationInFlight = true
        accountIDAutoGenerationAttemptedBackendID = trimmedBackendID
        defer { accountIDAutoGenerationInFlight = false }

        let generated = await AccountDirectoryService.shared.autoGenerateAccountIDIfMissing(
            userID: trimmedBackendID,
            displayName: trimmedDisplayName,
            localAccountID: storedAccountID,
            lookupEnabled: lookupEnabled,
            followRequestsEnabled: followRequestsEnabled,
            location: location,
            instruments: instruments
        )

        guard let generated, !generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ProfileStore.setAccountID(generated, for: trimmedBackendID)
        accountIDText = generated
        lastDirectorySyncFingerprint = nil
    }




     

     // MARK: - Avatar (backend identity)

     @MainActor
     private func persistAvatarToBackendIfPossible(jpegData: Data) async {
         guard BackendEnvironment.shared.isConnected else { return }
         let auth = _auth.wrappedValue
         guard auth.hasSupabaseAccessToken else { return }
         guard let backendID = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !backendID.isEmpty else { return }

         avatarSyncInFlight = true
         defer { avatarSyncInFlight = false }

         // 1) Upload (overwrite) avatars/users/<uid>/avatar.jpg
         let upload = await NetworkManager.shared.uploadAvatarJPEG(data: jpegData, backendUserID: backendID)
         switch upload {
         case .failure:
             avatarSyncErrorMessage = "Couldn’t upload your avatar. Please try again."
             showAvatarSyncErrorAlert = true
             return
         case .success(let avatarKey):
             // Bust remote caches for this key (image + signed URL), because content may have changed.
             await invalidateRemoteAvatarCaches(avatarKey: avatarKey)

             // 2) Patch account_directory.avatar_key
             let patch = await AccountDirectoryService.shared.updateSelfAvatarKey(userID: backendID, avatarKey: avatarKey)
             switch patch {
             case .success:
                 return
             case .failure:
                 avatarSyncErrorMessage = "Uploaded your avatar, but couldn’t update your profile. Please try again."
                 showAvatarSyncErrorAlert = true
                 return
             }
         }
     }

     @MainActor
     private func clearAvatarFromBackendIfPossible() async {
         guard BackendEnvironment.shared.isConnected else { return }
         let auth = _auth.wrappedValue
         guard auth.hasSupabaseAccessToken else { return }
         guard let backendID = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !backendID.isEmpty else { return }

         avatarSyncInFlight = true
         defer { avatarSyncInFlight = false }

         // Best-effort delete (do not block UI on failure).
         _ = await NetworkManager.shared.deleteAvatarObject(backendUserID: backendID)

         // Clear avatar_key in account_directory.
         let patch = await AccountDirectoryService.shared.updateSelfAvatarKey(userID: backendID, avatarKey: nil)
         switch patch {
         case .success:
             // Bust caches for the canonical key as well, in case any surfaces still reference it.
             await invalidateRemoteAvatarCaches(avatarKey: "users/\(backendID)/avatar.jpg")
             return
         case .failure:
             avatarSyncErrorMessage = "Couldn’t clear your avatar right now. Please try again."
             showAvatarSyncErrorAlert = true
             return
         }
     }

     private func invalidateRemoteAvatarCaches(avatarKey: String) async {
         let trimmed = avatarKey.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmed.isEmpty else { return }
         let cacheKey = "avatars|\(trimmed)"
         await RemoteAvatarSignedURLCache.shared.invalidate(cacheKey)
         #if canImport(UIKit)
         RemoteAvatarImageCache.invalidate(cacheKey)
         #endif
     }

// Phase 13A — Detect account_id collision (unique constraint) from NetworkManager error.
     private func isAccountIDCollision(_ error: Error) -> Bool {
        // NetworkError is nested in NetworkManager.
        if let net = error as? NetworkManager.NetworkError {
            switch net {
            case .httpError(let status, let body):
                guard status == 409, let body, !body.isEmpty else { return false }
                // Supabase/Postgres unique violation on account_directory.account_id.
                if body.contains("\"code\":\"23505\"") { return true }
                if body.contains("account_directory_account_id_key") { return true }
                return false
            default:
                return false
            }
        }
        return false
    }




     // New helper method to compute initials from a string
     

     private var deleteAccountSheet: some View {
         NavigationStack {
             ScrollView {
                 VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                     VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                         Text("This permanently deletes your account and all backend data (posts, attachments, follows, comments, and your avatar). This can’t be undone.")
                             .font(Theme.Text.body)
                             .foregroundStyle(Theme.Colors.secondaryText)
                     }
                     .cardSurface()

                     VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                         Text("Type DELETE to confirm").sectionHeader()

                         TextField("DELETE", text: $deleteAccountConfirmText)
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
                         Task { await performDeleteAccount() }
                     } label: {
                         HStack {
                             Spacer()
                             if deleteAccountInFlight {
                                 ProgressView()
                                     .padding(.trailing, 6)
                             }
                             Text(deleteAccountInFlight ? "Deleting…" : "Delete account")
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
                     .disabled(deleteAccountInFlight || deleteAccountConfirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE")
                     .opacity(deleteAccountInFlight || deleteAccountConfirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE" ? 0.5 : 1.0)
                 }
                 .padding(.horizontal, Theme.Spacing.l)
                 .padding(.vertical, Theme.Spacing.section)
             }
             .appBackground()
             .tint(Theme.Colors.accent)
             .navigationTitle("Delete account")
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


     private func performDeleteAccount() async {
         // Guard: must be connected and have a stored Supabase access token.
         guard BackendEnvironment.shared.isConnected else {
             deleteAccountErrorMessage = "Delete Account is only available in Connected mode."
             showDeleteAccountErrorAlert = true
             return
         }

         // Preflight: ensure we have a fresh, valid Supabase session/token before invoking the function.
let sessionOK = await auth.ensureValidSession(reason: "delete-account")
guard sessionOK else {
    deleteAccountErrorMessage = "Session is not valid. Please sign out, sign in, then try again."
    showDeleteAccountErrorAlert = true
    return
}

let tokenKey = "supabaseAccessToken_v1"
         guard let accessTokenRaw = Keychain.get(tokenKey), accessTokenRaw.isEmpty == false else {
             deleteAccountErrorMessage = "Missing Supabase session token. Please sign out and sign back in, then try again."
             showDeleteAccountErrorAlert = true
             return
         }

         // Defensive: Keychain values can carry stray whitespace; JWT must be header.payload.signature (2 dots).
         let accessToken = accessTokenRaw.trimmingCharacters(in: .whitespacesAndNewlines)
         let dotCount = accessToken.filter { $0 == "." }.count
         guard dotCount == 2 else {
             deleteAccountErrorMessage = "Invalid Supabase session token format (dotCount=\(dotCount)). Please sign out and sign back in, then try again."
             showDeleteAccountErrorAlert = true
             return
         }

         guard let baseURL = BackendConfig.apiBaseURL, let anonKey = BackendConfig.apiToken else {
             deleteAccountErrorMessage = "Backend is not configured."
             showDeleteAccountErrorAlert = true
             return
         }

         deleteAccountInFlight = true
         defer { deleteAccountInFlight = false }

         // Prefer the dedicated functions domain to avoid gateway/header quirks:
// https://<project-ref>.functions.supabase.co/<function>
let functionURL: URL = {
    if let host = baseURL.host,
       host.hasSuffix(".supabase.co") {
        let projectRef = host.replacingOccurrences(of: ".supabase.co", with: "")
        if let url = URL(string: "https://\(projectRef).functions.supabase.co/delete_account_v1") {
            return url
        }
    }
    // Fallback to the REST-style endpoint if we cannot derive the project ref.
    return baseURL
        .appendingPathComponent("functions")
        .appendingPathComponent("v1")
        .appendingPathComponent("delete_account_v1")
}()

         var request = URLRequest(url: functionURL)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue(anonKey, forHTTPHeaderField: "apikey")
         request.setValue(anonKey, forHTTPHeaderField: "x-api-key")
         request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

         do {
             let (data, response) = try await URLSession.shared.data(for: request)
             let status = (response as? HTTPURLResponse)?.statusCode ?? -1

             if status != 200 {
                 let body = String(data: data, encoding: .utf8) ?? ""
                 deleteAccountErrorMessage = "Server returned \(status). \(body)"
                 showDeleteAccountErrorAlert = true
                 return
             }

             // Expect: { "success": true }
             if let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                let dict = obj as? [String: Any],
                let ok = dict["success"] as? Bool,
                ok == true {
                 showDeleteAccountSheet = false
                 await LocalFactoryReset.perform(reason: "delete-account-success", auth: auth)
                 return
             }

             let body = String(data: data, encoding: .utf8) ?? ""
             deleteAccountErrorMessage = "Unexpected response: \(body)"
             showDeleteAccountErrorAlert = true
         } catch {
             deleteAccountErrorMessage = String(describing: error)
             showDeleteAccountErrorAlert = true
         }
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
            .onDisappear(perform: persistProfileEdits)
            .onChange(of: auth.currentUserID) { oldValue, newValue in
                if oldValue == nil, newValue != nil, signedOutGateWasVisible {
                    closeSignedOutGateAfterSuccessfulSignInIfNeeded()
                    return
                }

                // Identity scoping: clear on sign-out; repopulate on sign-in.
                // Hygiene: persist any in-memory edits for the *previous* signed-in identity
                // before we clear UI state (location is stored per-user in ProfileStore).
                if newValue == nil {
                // Delete Account v2: during a factory reset, never persist per-user location back to ProfileStore.
                if LocalFactoryReset.isInProgress {
                    clearUserPresentedStateForSignOut()
                    return
                }

                    if let oldBackendID = auth.backendUserID {
                        ProfileStore.setLocation(locationText, for: oldBackendID)
                    }
                    // Device-level Profile: keep existing behaviour by saving pending edits
                    // before clearing the view's presented state.
                    save()
                    clearUserPresentedStateForSignOut()
                } else {
                    onAppearLoad()
                }
            }
            .onChange(of: auth.backendUserID) { _, newValue in
                // Phase 12C: user-scoped lookup state (per backend identity)
                if newValue == nil {
                    accountIDText = ""
                    discoveryModeRawPerUser = DiscoveryMode.none.rawValue
                } else {
                    discoveryModeRawPerUser = ProfileStore.discoveryModeRaw(for: auth.backendUserID)
                    accountIDText = ProfileStore.accountID(for: auth.backendUserID)
                    locationText = ProfileStore.location(for: auth.backendUserID)
                }
            }
             .onChange(of: primaryActivityRef) { _ in
                 primaryActivityChoice = normalizedPrimaryActivityRef()
             }
             .onChange(of: name) { _, _ in
                 Task { @MainActor in scheduleDirectorySyncDebounced() }
             }
             .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: ctx)) { _ in
                 guard auth.currentUserID != nil else { return }
                 guard showInstrumentManager == false,
                       showActivityManager == false,
                       showTasksManager == false,
                       showDeleteAccountSheet == false,
                       showAvatarEditor == false,
                       showPhotoPicker == false else { return }
                 load()
             }
             .onChange(of: locationText) { _, _ in
                 Task { @MainActor in scheduleDirectorySyncDebounced() }
             }
             .onChange(of: discoveryModeRawPerUser) { _, newValue in
                 ProfileStore.setDiscoveryModeRaw(newValue, for: auth.backendUserID)
                 Task { await syncDirectoryFromCurrentState() }
             }
             .onChange(of: followRequestModeRaw) { _, _ in
                 // Hardening: push follow-request preference immediately to backend (no restart dependency).
                 Task { await syncDirectoryFromCurrentState() }
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

             .alert("Delete account failed", isPresented: $showDeleteAccountErrorAlert) {
                 Button("OK", role: .cancel) {}
             } message: {
                 Text(deleteAccountErrorMessage ?? "Couldn’t delete your account. Please try again.")
             }
             .sheet(isPresented: $showDeleteAccountSheet) {
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
