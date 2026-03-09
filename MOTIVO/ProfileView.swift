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
// SCOPE: UI-only — ProfileView: align signed-in Sign out action styling with signed-out Sign in (soft surface button, same size/typography); no logic/auth changes.
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
     @State private var isWelcomeExpanded: Bool = false

     @AppStorage("appSettings_showWelcomeSection") private var showWelcomeSection: Bool = true

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
     @State private var showAppSettings: Bool = false
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
 
     var body: some View {
         modalsAndAlerts(
             NavigationStack {
                ZStack {
                    if auth.isSignedIn {
                        Form {
                     if showWelcomeSection {
                         welcomeSection
                     }
                     Group {
                         profileSection
                         privacySection
                         instrumentsSection
                     }
                     Group {
                         activitiesSection
                             tasksSection
                             appSettingsSection
                             accountSection
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
                     ToolbarItem(placement: .principal) {
                         Text("Profile").font(Theme.Text.pageTitle)
                     }
                     toolbarContent
                }
                .appBackground()
            }
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
        }
    }


// MARK: - Sections

     @ViewBuilder
     private var welcomeSection: some View {
         Section {
             VStack(spacing: 0) {
                 Button {
                     isWelcomeExpanded.toggle()
                 } label: {
                     HStack(spacing: Theme.Spacing.s) {
                         Text("Welcome!")
                             .font(Theme.Text.body)
                                 .foregroundStyle(Theme.Colors.accent)
                         Spacer()
                         Image(systemName: isWelcomeExpanded ? "chevron.up" : "chevron.down")
                             .font(.footnote.weight(.semibold))
                             .padding(6)
                             .background(.ultraThinMaterial, in: Circle())
                             .foregroundStyle(Theme.Colors.accent)
                     }
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityLabel(Text("Welcome to Études"))
                 .accessibilityHint(Text(isWelcomeExpanded ? "Hide welcome information" : "Show welcome information"))
                 .frame(minHeight: 24)

                 if isWelcomeExpanded {
                     Divider()
                         .padding(.vertical, 8)

                     VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                         Text("Welcome to Études")
                             .font(Theme.Text.body)
                             .fontWeight(.semibold)

                         VStack(alignment: .leading, spacing: Theme.Spacing.m) {

                             // Profile
                             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                 Text("Profile")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .foregroundStyle(Theme.Colors.accent)

                                 Text("Add your personal details and instruments here. Choose a primary instrument for quicker session setup. Activities work the same way — use presets or add your own, and set a primary for auto-selection. Accounts are private by default. Sessions are shared intentionally, and attachments remain personal unless you choose to include them. Adjust global privacy to control who sees what.")
                                     .font(Theme.Text.body)
                                     .foregroundStyle(Theme.Colors.secondaryText)
                             }

                             // Feed
                             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                 Text("Feed")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .foregroundStyle(Theme.Colors.accent)

                                 Text("Your activity history appears here. If you follow other musicians, you’ll also see the sessions they’ve chosen to share. Use the Feed Filter to switch between All (you + accounts you follow) or Mine (just you). Use search to find posts by title or content. Tap a session to open full details and view media. Comments are private conversations between you and the author. Replies are not visible to other commenters. There are no public follower counts, like counts, or rankings. The heart icon saves a session privately, and saved sessions can be filtered in the Feed Filter.")
                                     .font(Theme.Text.body)
                                     .foregroundStyle(Theme.Colors.secondaryText)
                             }

                             // Session Timer
                             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                 Text("Session Timer")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .foregroundStyle(Theme.Colors.accent)

                                 Text("Launched from the feed’s record button. Use it to log any of your activities — practice, rehearsal, performance, writing, or recording sessions. Attach photos, record audio or video, and trim recordings before saving. The notes/tasks pad sits beneath the timer — write notes, add tasks, or use task defaults that appear depending on the selected activity. Default task lists are configured in the Tasks Manager here on the Profile page.")
                                     .font(Theme.Text.body)
                                     .foregroundStyle(Theme.Colors.secondaryText)
                             }

                             // Stats
                             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                 Text("Stats")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .foregroundStyle(Theme.Colors.accent)

                                 Text("Tap the three bars in the Your Sessions header on the feed to see a detailed breakdown of your activity history.")
                                     .font(Theme.Text.body)
                                     .foregroundStyle(Theme.Colors.secondaryText)
                             }

                         
                         }
                         .frame(maxWidth: .infinity, alignment: .leading)
                     }
                     .frame(maxWidth: .infinity, alignment: .leading)
                     .transition(.opacity.combined(with: .move(edge: .top)))
                 }
             }
             .padding(.horizontal, 16)
             .padding(.vertical, 2)
             .padding(.top, Theme.Spacing.s)
             .cardSurface()
         }
         .padding(.top, Theme.Spacing.section)
             .listRowBackground(Color.clear)
     }

     @ViewBuilder
     private var profileSection: some View {
         Section(header: Text("Name").sectionHeader()) {
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
 
             TextField("Location (optional)", text: $locationText)
                 .textInputAutocapitalization(.words)
                 .disableAutocorrection(true)
                 .focused($isLocationFocused)
                 .onSubmit { isLocationFocused = false }

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

             if let msg = accountIDSyncMessage {
                 Text(msg)
                     .font(Theme.Text.meta)
                     .foregroundStyle(accountIDSyncIsError ? Color.red : Theme.Colors.secondaryText)
                     .padding(.top, 2)
             }
         }
         .listRowSeparator(.hidden)
     }
 
     @ViewBuilder
     private var privacySection: some View {
         Section(header: Text("Privacy & connection").sectionHeader()) {

             // 1) Posting defaults card (unchanged behaviour)
             VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                 // Title + control (same family grammar as other cards: title then control/value)
                 Text("Posting defaults")
                     .font(.subheadline.weight(.medium))
                     .foregroundStyle(Theme.Colors.secondaryText.opacity(0.95))

                 Toggle("Default to Private Posts", isOn: $defaultPrivacy)
                     .tint(Theme.Colors.accent)

                 Text("Makes new sessions default to private when on. You can still choose to publish a session when you save.")
                     .font(.caption)
                     .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
             }
             .padding(.vertical, Theme.Spacing.s)
             .cardSurface(padding: Theme.Spacing.m)
             .listRowSeparator(.hidden)

             // 2) Follow Requests card (separate, Instruments/Activities-style grammar)
             VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                 Text("Follow Requests")
                     .font(.subheadline.weight(.medium))
                     .foregroundStyle(Theme.Colors.secondaryText.opacity(0.95))

                 Menu {
                     // NOTE: this file’s enum is FollowRequestMode { autoApproveContacts=0, manual=1 }.
                     // We present spec-truthful labels without changing state shape or adding new keys.
                     Button {
                         followRequestModeRaw = FollowRequestMode.manual.rawValue
                     } label: {
                         let isCurrent = (FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual) == .manual
                         Label("Allow follow requests", systemImage: isCurrent ? "checkmark" : "")
                     }

                     Button {
                         followRequestModeRaw = FollowRequestMode.autoApproveContacts.rawValue
                     } label: {
                         let isCurrent = (FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual) == .autoApproveContacts
                         Label("Follow requests off", systemImage: isCurrent ? "checkmark" : "")
                     }
                 } label: {
                     HStack(spacing: 2) {
                         Text(
                             (FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual) == .autoApproveContacts
                             ? "Follow requests off"
                             : "Allow follow requests"
                         )
                         .font(Theme.Text.body)
                         .foregroundStyle(.primary)

                         Image(systemName: "chevron.up.chevron.down")
                             .font(.caption2)
                             .foregroundStyle(Theme.Colors.secondaryText)
                     }
                     .frame(maxWidth: .infinity, alignment: .leading)
                 }
                 .tint(.primary)

                 Text("Études never auto-approves follows.")
                     .font(.caption)
                     .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
             }
             .padding(.vertical, Theme.Spacing.s)
             .cardSurface(padding: Theme.Spacing.m)
             .listRowSeparator(.hidden)

             // 3) Lookup card (separate, hide Contacts option from UI)
             VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                 Text("Account visibility")
                     .font(.subheadline.weight(.medium))
                     .foregroundStyle(Theme.Colors.secondaryText.opacity(0.95))

                 Menu {
                     Button {
                         discoveryModeRawPerUser = DiscoveryMode.search.rawValue
                     } label: {
                         let isCurrent = (DiscoveryMode(rawValue: discoveryModeRawPerUser) ?? .none) == .search
                         Label("Searchable by name", systemImage: isCurrent ? "checkmark" : "")
                     }

                     Button {
                         discoveryModeRawPerUser = DiscoveryMode.none.rawValue
                     } label: {
                         let isCurrent = (DiscoveryMode(rawValue: discoveryModeRawPerUser) ?? .none) == .none
                         Label("Hidden from search", systemImage: isCurrent ? "checkmark" : "")
                     }

                     // NOTE: DiscoveryMode.contacts exists in this file but is intentionally hidden from UI here.
                 } label: {
                     HStack(spacing: 2) {
                         Text(
                             (DiscoveryMode(rawValue: discoveryModeRawPerUser) ?? .none) == .search
                             ? "Searchable by name"
                             : "Hidden from search"
                         )
                         .font(Theme.Text.body)
                         .foregroundStyle(.primary)

                         Image(systemName: "chevron.up.chevron.down")
                             .font(.caption2)
                             .foregroundStyle(Theme.Colors.secondaryText)
                     }
                     .frame(maxWidth: .infinity, alignment: .leading)
                 }
                 .tint(.primary)

                 Text("There’s no browsing of accounts or follow suggestions — you’re only found through search.")
                     .font(.caption)
                     .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
             }
             .padding(.vertical, Theme.Spacing.s)
             .cardSurface(padding: Theme.Spacing.m)
             .listRowSeparator(.hidden)

             // 4) Philosophy line OUTSIDE the cards (quiet footer)
             Text("Your account is private by default, and follows are always intentional.")
                 .font(.caption)
                 .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                 .padding(.top, Theme.Spacing.xs)
         }
     }

 
     @ViewBuilder
     private var instrumentsSection: some View {
         Section(header: Text("Instruments").sectionHeader()) {
             VStack(spacing: 0) {
                 Button { showInstrumentManager = true } label: {
                     manageRow(title: "Manage")
                         .foregroundStyle(Theme.Colors.secondaryText)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44, alignment: .center)
                 .font(Theme.Text.body)
 
                 Divider().padding(.leading, 16)
 
                 VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                     // Softer header-style label
                     Text("Primary Instrument")
                         .font(.subheadline.weight(.medium))
                         .foregroundStyle(Theme.Colors.secondaryText.opacity(0.95))
 
                     // Menu directly below, aligned on same rail
                     Menu {
                         ForEach(instrumentsArray, id: \.self) { name in
                             Button {
                                 primaryInstrumentName = name
                             } label: {
                                 let isCurrent = (primaryInstrumentName == name)
                                 Label(name, systemImage: isCurrent ? "checkmark" : "")
                             }
                         }
                     } label: {
                         HStack(spacing: 2) {
                             Text(primaryInstrumentName.isEmpty ? "Select" : primaryInstrumentName)
                                 .font(Theme.Text.body)
                                 .foregroundStyle(.primary)
                             Image(systemName: "chevron.up.chevron.down")
                                 .font(.caption2)
                                 .foregroundStyle(Theme.Colors.secondaryText)
                         }
                         .frame(maxWidth: .infinity, alignment: .leading)
                     }
                     .tint(Theme.Colors.accent)
                     .accessibilityLabel("Primary Instrument")
                 }
                 .padding(.top, Theme.Spacing.s)
                 .frame(minHeight: 44, alignment: .center)
             }
             .padding(.horizontal, 16)
             .padding(.vertical, 12)
             .padding(.top, Theme.Spacing.s)
             .cardSurface()
             .padding(.bottom, Theme.Spacing.m)
         }
         .padding(.top, Theme.Spacing.section)
     }
     @ViewBuilder
     private var activitiesSection: some View {
         Section(header: Text("Activities").sectionHeader()) {
             VStack(spacing: 0) {
                 Button { showActivityManager = true } label: {
                     manageRow(title: "Manage")
                         .foregroundStyle(Theme.Colors.secondaryText)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44)
                 .font(Theme.Text.body)
 
                 Divider().padding(.leading, 16)
 
                 VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                     // Softer header-style label
                     Text("Primary Activity")
                         .font(.subheadline.weight(.medium))
                         .foregroundStyle(Theme.Colors.secondaryText.opacity(0.95))
 
                     // Compute current label for the menu
                     let currentActivityLabel: String = {
                         if primaryActivityChoice.hasPrefix("core:") {
                             if let v = Int(primaryActivityChoice.split(separator: ":").last ?? "0"),
                                let type = SessionActivityType(rawValue: Int16(v)) {
                                 return type.label
                             }
                         } else if primaryActivityChoice.hasPrefix("custom:") {
                             return String(primaryActivityChoice.dropFirst("custom:".count))
                         }
                         // Fallback
                         return "Practice"
                     }()
 
                     // Menu directly below, aligned on same rail
                     Menu {
                         // Core activities
                         ForEach(SessionActivityType.allCases) { type in
                             let tag = "core:\(type.rawValue)"
                             Button {
                                 primaryActivityChoice = tag
                                 writePrimaryActivityRef(tag)
                             } label: {
                                 let isCurrent = (primaryActivityChoice == tag)
                                 Label(type.label, systemImage: isCurrent ? "checkmark" : "")
                             }
                         }
 
                         // Custom activities
                         ForEach(userActivities.compactMap { $0.displayName }, id: \.self) { name in
                             let tag = "custom:\(name)"
                             Button {
                                 primaryActivityChoice = tag
                                 writePrimaryActivityRef(tag)
                             } label: {
                                 let isCurrent = (primaryActivityChoice == tag)
                                 Label(name, systemImage: isCurrent ? "checkmark" : "")
                             }
                         }
                     } label: {
                         HStack(spacing: 2) {
                             Text(currentActivityLabel)
                                 .font(Theme.Text.body)
                                 .foregroundStyle(.primary)
                             Image(systemName: "chevron.up.chevron.down")
                                 .font(.caption2)
                                 .foregroundStyle(Theme.Colors.secondaryText)
                         }
                         .frame(maxWidth: .infinity, alignment: .leading)
                     }
                     .tint(Theme.Colors.accent)
                     .accessibilityLabel("Primary Activity")
                 }
                 .padding(.top, Theme.Spacing.s)
                 .frame(minHeight: 44)
             }
             .padding(.horizontal, 16)
             .padding(.vertical, 12)
             .padding(.top, Theme.Spacing.s)
             .cardSurface()
             .padding(.bottom, Theme.Spacing.m)
         }
     }
     
     @ViewBuilder
     private var appSettingsSection: some View {
         Section(header: Text("App Settings").sectionHeader()) {
             VStack(spacing: 0) {
                 Button { showAppSettings = true } label: {
                     manageRow(title: "Manage")
                         .foregroundStyle(Theme.Colors.secondaryText)
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44)
                 .font(Theme.Text.body)
             }
             .padding(.horizontal, 16)
             .padding(.vertical, 12)
             .padding(.top, Theme.Spacing.s)
             .cardSurface()
             .padding(.bottom, Theme.Spacing.m)
         }
     }
@ViewBuilder
     private var tasksSection: some View {
         Section(header: Text("Tasks").sectionHeader()) {
             VStack(spacing: 0) {
                 Button { showTasksManager = true } label: {
                     manageRow(title: "Manage")
                         .foregroundStyle(Theme.Colors.secondaryText)   // ⬅️ add this
                 }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
                 .frame(minHeight: 44)
                 .font(Theme.Text.body)
             }
             .padding(.horizontal, 16)
             .padding(.vertical, 12)
             .padding(.top, Theme.Spacing.s)
             .cardSurface()
             .padding(.bottom, Theme.Spacing.m)
         }
     }
 
   
     private var accountSection: some View {
         Group {
             if auth.isSignedIn {
                 // Sign out (primary) — its own container/card
                 Section {
                     VStack(alignment: .leading, spacing: 0) {
                         VStack(alignment: .leading, spacing: 4) {
                             Button {
                                 auth.signOut()
                             } label: {
                                 Text("Sign out")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .frame(maxWidth: .infinity)
                                     .frame(height: 52)
                             }
                             .buttonStyle(.plain)
                             .contentShape(Rectangle())
                         }
                     }
                     .padding(.horizontal, 16)
                     .padding(.vertical, 6)
                     .padding(.top, Theme.Spacing.s)
                     .cardSurface()
                 }

                 // Delete Account (destructive) — its own container/card, compact
                 Section {
                     Button {
                         deleteAccountConfirmText = ""
                         showDeleteAccountSheet = true
                     } label: {
                         Text("Delete account")
                             .font(Theme.Text.body.weight(.semibold))
                             .foregroundStyle(.red)
                             .frame(maxWidth: .infinity)
                             .padding(.vertical, 10)
                     }
                     .buttonStyle(.plain)
                     .contentShape(Rectangle())
                     .padding(.horizontal, 16)
                     .padding(.vertical, 2)
                     .padding(.top, Theme.Spacing.s)
                     .cardSurface()
                 }
                 .padding(.bottom, Theme.Spacing.m)
             } else {
                 Section {
                     SignInWithAppleButton(.signIn) { request in
                         auth.configure(request)
                     } onCompletion: { result in
                         auth.handle(result)
                     }
                     .signInWithAppleButtonStyle(.black)
                     .frame(height: 44)
                     .accessibilityLabel(Text("Sign in with Apple"))
                 }
             }
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
 
     private func manageRow(title: String) -> some View {
         HStack {
             Text(title)
             Spacer()
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
         let acctOrNil: String? = (acct.count >= 3) ? acct : nil
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
case .failure(let error):
    if isAccountIDCollision(error) {
        accountIDSyncMessage = "That account ID is already taken."
    } else {
        accountIDSyncMessage = "Couldn’t update your Account ID. Please try again."
    }
    accountIDSyncIsError = true
}
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
             Form {
                 Section {
                     Text("This permanently deletes your account and all backend data (posts, attachments, follows, comments, and your avatar). This can’t be undone.")
                         .font(Theme.Text.body)
                         .foregroundStyle(Theme.Colors.secondaryText)
                 }

                 Section(header: Text("Type DELETE to confirm").sectionHeader()) {
                     TextField("DELETE", text: $deleteAccountConfirmText)
                         .textInputAutocapitalization(.characters)
                         .autocorrectionDisabled()
                         .font(Theme.Text.body)
                 }

                 Section {
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
                         .frame(height: 52)
                     }
                     .disabled(deleteAccountInFlight || deleteAccountConfirmText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "DELETE")
                 }
             }
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
             .onChange(of: showActivityManager) { oldValue, newValue in
                 handleActivityManagerChange(oldValue, newValue)
             }
             .onChange(of: primaryActivityRef) { _ in
                 primaryActivityChoice = normalizedPrimaryActivityRef()
             }
             .onChange(of: name) { _, _ in
                 Task { @MainActor in scheduleDirectorySyncDebounced() }
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
                 // When instrument manager closes, sync instruments to account_directory (debounced).
                 if newValue == false {
                     scheduleDirectorySyncDebounced(nanoseconds: 200_000_000)
                 }
             }
             .sheet(isPresented: $showActivityManager) {
                 ActivityListView()
                     .environment(\.managedObjectContext, ctx)
             }
             .sheet(isPresented: $showTasksManager) {
                 TasksManagerView(activityRef: normalizedPrimaryActivityRef())
                     .environment(\.managedObjectContext, ctx)
             }
             .sheet(isPresented: $showAppSettings) {
                 AppSettingsView()
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
