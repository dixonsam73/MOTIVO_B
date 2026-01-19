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
 import SwiftUI
 import CoreData
 import AuthenticationServices
 #if canImport(PhotosUI)
 import PhotosUI
 #endif
 
// MARK: - Privacy Settings (local-first)

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
 
     @State private var showInstrumentManager: Bool = false
     @State private var showActivityManager: Bool = false
     @State private var showTasksManager: Bool = false
     @State private var showAppSettings: Bool = false
     @State private var profile: Profile?
 
 
     // Identity MVP additions
     @State private var avatarImage: UIImage? = nil
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
    @AppStorage("allowDiscovery_v1") private var allowDiscoveryRaw: Int = DiscoveryMode.none.rawValue

    private var followRequestMode: FollowRequestMode {
        get {
            let mode = FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual
            // Map legacy auto-approve to manual (Motivo never auto-approves follows).
            return mode == .autoApproveContacts ? .manual : mode
        }
        set { followRequestModeRaw = newValue.rawValue }
    }
    private var discoveryMode: DiscoveryMode {
        get { DiscoveryMode(rawValue: allowDiscoveryRaw) ?? .none }
        set { allowDiscoveryRaw = newValue.rawValue }
    }
     // New state for avatar editor sheet
     @State private var showAvatarEditor: Bool = false
 
     var body: some View {
         modalsAndAlerts(
             NavigationStack {
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
                 .accessibilityLabel(Text("Welcome to Motivo"))
                 .accessibilityHint(Text(isWelcomeExpanded ? "Hide welcome information" : "Show welcome information"))
                 .frame(minHeight: 24)

                 if isWelcomeExpanded {
                     Divider()
                         .padding(.vertical, 8)

                     VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                         Text("Welcome to Motivo")
                             .font(Theme.Text.body)
                             .fontWeight(.semibold)

                         VStack(alignment: .leading, spacing: Theme.Spacing.m) {

                             // Profile
                             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                 Text("Profile")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .foregroundStyle(Theme.Colors.accent)

                                 Text("Add your personal details and instruments here. Choose a primary instrument for quicker session setup. Activities work the same way — use presets or add your own, and set a primary for auto-selection. Adjust global privacy to control who sees what.")
                                     .font(Theme.Text.body)
                                     .foregroundStyle(Theme.Colors.secondaryText)
                             }

                             // Feed
                             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                 Text("Feed")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .foregroundStyle(Theme.Colors.accent)

                                 Text("Your activity history appears here (and posts from users you follow). Use the Feed Filter to switch between All (you + the accounts you follow) or Mine (just you). Use search to find posts by title or content (e.g. Bach, scales, SLAP). Tap a post to open full session details, view media, and like or comment.")
                                     .font(Theme.Text.body)
                                     .foregroundStyle(Theme.Colors.secondaryText)
                             }

                             // Practice Timer
                             VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                 Text("Practice Timer")
                                     .font(Theme.Text.body.weight(.semibold))
                                     .foregroundStyle(Theme.Colors.accent)

                                 Text("Launched from the feed's record button. Use it to log your practice, rehearsal, performance, or recording sessions. Attach photos, record audio or video, and trim those recordings before saving. The notes/tasks pad sits beneath the timer — write notes, add tasks, or use task defaults that automatically appear depending on the selected activity. Default task lists are configured in the Tasks Manager here on the Profile page (e.g., a setlist for a rehearsal, warm-ups and scales for a practice session).")
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

                             // Closing
                             Text("Happy noting!")
                                 .font(Theme.Text.body.weight(.semibold))
                                 .foregroundStyle(Theme.Colors.accent)
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
 
                 TextField("Name", text: $name)
                     .textInputAutocapitalization(.words)
                     .disableAutocorrection(true)
                     .focused($isNameFocused)
                     .scaleEffect(isNameFocused ? 0.995 : 1)
                     .overlay(alignment: .bottomLeading) {
                         Rectangle().frame(height: 1).opacity(isNameFocused ? 0.15 : 0)
                     }
                     .animation(.easeInOut(duration: 0.18), value: isNameFocused)
             }
 
             TextField("Location (optional)", text: $locationText)
                 .textInputAutocapitalization(.words)
                 .disableAutocorrection(true)
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

                 Text("Motivo never auto-approves follows.")
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
                         allowDiscoveryRaw = DiscoveryMode.search.rawValue
                     } label: {
                         let isCurrent = (DiscoveryMode(rawValue: allowDiscoveryRaw) ?? .none) == .search
                         Label("Searchable by name", systemImage: isCurrent ? "checkmark" : "")
                     }

                     Button {
                         allowDiscoveryRaw = DiscoveryMode.none.rawValue
                     } label: {
                         let isCurrent = (DiscoveryMode(rawValue: allowDiscoveryRaw) ?? .none) == .none
                         Label("Hidden from search", systemImage: isCurrent ? "checkmark" : "")
                     }

                     // NOTE: DiscoveryMode.contacts exists in this file but is intentionally hidden from UI here.
                 } label: {
                     HStack(spacing: 2) {
                         Text(
                             (DiscoveryMode(rawValue: allowDiscoveryRaw) ?? .none) == .search
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
             Text("Your profile is private by default, and follows are always intentional.")
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
 
     @ViewBuilder
     private var accountSection: some View {
         Section(header: Text("Account").sectionHeader()) {
             VStack(alignment: .leading, spacing: 0) {
                 VStack(alignment: .leading, spacing: 4) {
                     if auth.isSignedIn {
                         Text(auth.displayName ?? "Signed in")
                             .font(Theme.Text.body)
                             .frame(minHeight: 44, alignment: .center)
                         Text("User ID: \(auth.currentUserID ?? "--")")
                             .font(.footnote)
                             .foregroundStyle(.secondary)
                             .lineLimit(3)
                             .truncationMode(.tail)
                             .padding(.bottom, 8)
                         Divider().padding(.leading, 16)
                         HStack {
                             Spacer()
                             Button(role: .destructive) { auth.signOut() } label: {
                                 Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                             }
                             .font(Theme.Text.body)
                             .frame(minHeight: 44)
                         }
                     } else {
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
             .padding(.horizontal, 16)
             .padding(.vertical, 12)
             .padding(.top, Theme.Spacing.s)
             .cardSurface()
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
             onSave: { cropped in
                 ProfileStore.saveAvatarDerived(cropped, for: auth.currentUserID)
                 avatarImage = ProfileStore.avatarImage(for: auth.currentUserID)
                 showAvatarEditor = false
             },
             onDelete: {
                 ProfileStore.deleteAvatar(for: auth.currentUserID)
                 avatarImage = nil
                 showAvatarEditor = false
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
         self.avatarImage = ProfileStore.avatarImage(for: auth.currentUserID)
         self.locationText = ProfileStore.location(for: auth.currentUserID)
     }

     private func clearUserPresentedStateForSignOut() {
         // Clear all user-presented state without mutating persisted device-level Profile.
         profile = nil
         name = ""
         primaryInstrumentName = ""
         defaultPrivacy = false
         avatarImage = nil
         locationText = ""

         userActivities = []
         // Keep AppStorage primaryActivityRef unchanged; normalize displayed choice only.
         primaryActivityChoice = normalizedPrimaryActivityRef()

         // Clear any in-flight UI surfaces.
         showPhotoPicker = false
         showAvatarEditor = false
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
         ProfileStore.setLocation(locationText, for: auth.currentUserID)
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
 
     // New helper method to compute initials from a string
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
                    if let oldID = oldValue {
                        ProfileStore.setLocation(locationText, for: oldID)
                    }
                    // Device-level Profile: keep existing behaviour by saving pending edits
                    // before clearing the view's presented state.
                    save()
                    clearUserPresentedStateForSignOut()
                } else {
                    onAppearLoad()
                }
            }
             .onChange(of: showActivityManager) { oldValue, newValue in
                 handleActivityManagerChange(oldValue, newValue)
             }
             .onChange(of: primaryActivityRef) { _ in
                 primaryActivityChoice = normalizedPrimaryActivityRef()
             }
             .alert("Primary Activity reset", isPresented: $showPrimaryFallbackAlert) {
                 Button("OK", role: .cancel) {}
             } message: {
                 Text("Your Primary Activity was removed, so it’s been reset to Practice.")
             }
             .sheet(isPresented: $showInstrumentManager) {
                 InstrumentListView()
                     .environment(\.managedObjectContext, ctx)
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
