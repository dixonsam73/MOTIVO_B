////
 //  ProfileView.swift
 //  MOTIVO
 //
 //  [ROLLBACK ANCHOR] v7.8 Scope1 — pre-primary-activity (no primary activity selector; icons on manage rows; account at top)
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

fileprivate enum ProfileVisibility: Int, CaseIterable, Identifiable {
    case publicProfile = 0
    case followersOnly = 1
    case privateProfile = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .publicProfile:  return "Public"
        case .followersOnly:  return "Followers only"
        case .privateProfile: return "Private"
        }
    }
}

fileprivate enum FollowRequestMode: Int, CaseIterable, Identifiable {
    case autoApproveContacts = 0
    case manual = 1
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .autoApproveContacts: return "Auto-approve"
        case .manual:              return "Manual"
        }
    }
}

fileprivate enum DiscoveryMode: Int, CaseIterable, Identifiable {
    case none = 0
    case search = 1
    case contacts = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none:     return "Off"
        case .search:   return "Search"
        case .contacts: return "Contacts"
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
 
     @FocusState private var isNameFocused: Bool
 
     @State private var showInstrumentManager: Bool = false
     @State private var showActivityManager: Bool = false
     @State private var showTasksManager: Bool = false
     @State private var profile: Profile?
     @State private var isSaving = false
 
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
    @AppStorage("profileVisibility_v1") private var profileVisibilityRaw: Int = ProfileVisibility.followersOnly.rawValue
    @AppStorage("followRequestMode_v1") private var followRequestModeRaw: Int = FollowRequestMode.manual.rawValue
    @AppStorage("allowDiscovery_v1") private var allowDiscoveryRaw: Int = DiscoveryMode.none.rawValue

    private var profileVisibility: ProfileVisibility {
        get { ProfileVisibility(rawValue: profileVisibilityRaw) ?? .followersOnly }
        set { profileVisibilityRaw = newValue.rawValue }
    }
    private var followRequestMode: FollowRequestMode {
        get { FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual }
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
                     Group {
                         profileSection
                         privacySection
                         instrumentsSection
                     }
                     Group {
                         activitiesSection
                         tasksSection
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
 
     @ViewBuilder
     private var profileSection: some View {
         Section {
             Text("Name").sectionHeader()
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
        Section {
            Toggle("Default to Private Posts", isOn: $defaultPrivacy)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {

                // Profile Visibility
                Menu {
                    ForEach(ProfileVisibility.allCases) { option in
                        Button {
                            profileVisibilityRaw = option.rawValue
                        } label: {
                            let isCurrent = (ProfileVisibility(rawValue: profileVisibilityRaw) ?? .followersOnly) == option
                            Label(option.label, systemImage: isCurrent ? "checkmark" : "")
                        }
                    }
                } label: {
                    SettingRow(
                        title: "Profile Visibility",
                        value: (ProfileVisibility(rawValue: profileVisibilityRaw) ?? .followersOnly).label
                    )
                    .tint(.primary)
                }
                .accessibilityLabel("Profile Visibility")
                .accessibilityValue((ProfileVisibility(rawValue: profileVisibilityRaw) ?? .followersOnly).label)

                // Follow Requests
                Menu {
                    ForEach(FollowRequestMode.allCases) { option in
                        Button {
                            followRequestModeRaw = option.rawValue
                        } label: {
                            let isCurrent = (FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual) == option
                            Label(option.label, systemImage: isCurrent ? "checkmark" : "")
                        }
                    }
                } label: {
                    SettingRow(
                        title: "Follow Requests",
                        value: (FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual).label
                    )
                    .tint(.primary)
                }
                .accessibilityLabel("Follow Requests")
                .accessibilityValue((FollowRequestMode(rawValue: followRequestModeRaw) ?? .manual).label)

                // Find Friends (formerly "Discovery")
                Menu {
                    ForEach(DiscoveryMode.allCases) { option in
                        Button {
                            allowDiscoveryRaw = option.rawValue
                        } label: {
                            let isCurrent = (DiscoveryMode(rawValue: allowDiscoveryRaw) ?? .none) == option
                            Label(option.label, systemImage: isCurrent ? "checkmark" : "")
                        }
                    }
                } label: {
                    SettingRow(
                        title: "Find Friends",
                        value: (DiscoveryMode(rawValue: allowDiscoveryRaw) ?? .none).label
                    )
                    .tint(.primary)
                }
                .accessibilityLabel("Find Friends")
                .accessibilityValue((DiscoveryMode(rawValue: allowDiscoveryRaw) ?? .none).label)

            }
            .padding(.vertical, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
            .cardSurface(padding: Theme.Spacing.m)
            .listRowSeparator(.hidden)

            Text("Motivo is private by default. Control profile visibility, follow approvals, and how others can find you.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                .padding(.top, Theme.Spacing.s)
        }
    }
 
     @ViewBuilder
     private var instrumentsSection: some View {
         Section {
             Text("Instruments").sectionHeader()
             Button { showInstrumentManager = true } label: { manageRow(title: "Manage Instruments") }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
 
             VStack(spacing: Theme.Spacing.s) {
                 Picker("Primary Instrument", selection: $primaryInstrumentName) {
                     ForEach(instruments.map { $0.name ?? "" }.filter { !$0.isEmpty }, id: \.self) { n in
                         Text(n).tag(n)
                     }
                 }
             }
         }
         .cardSurface()
         .padding(.top, Theme.Spacing.section)
         .listRowSeparator(.hidden)
     }
 
     @ViewBuilder
     private var activitiesSection: some View {
         Section {
             Text("Activities").sectionHeader()
             Button { showActivityManager = true } label: { manageRow(title: "Manage Activities") }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
 
             VStack(spacing: Theme.Spacing.s) {
                 Picker("Primary Activity", selection: $primaryActivityChoice) {
                     ForEach(SessionActivityType.allCases) { type in
                         Text(type.label).tag("core:\(type.rawValue)")
                     }
                     ForEach(userActivities.compactMap { $0.displayName }, id: \.self) { name in
                         Text(name).tag("custom:\(name)")
                     }
                 }
                 .onChange(of: primaryActivityChoice) { _, newValue in
                     writePrimaryActivityRef(newValue)
                 }
             }
         }
         .cardSurface()
         .padding(.top, Theme.Spacing.section)
         .listRowSeparator(.hidden)
     }
 
     @ViewBuilder
     private var tasksSection: some View {
         Section {
             Text("Tasks").sectionHeader()
             Button { showTasksManager = true } label: { manageRow(title: "Manage Tasks") }
                 .buttonStyle(.plain)
                 .contentShape(Rectangle())
                 .accessibilityAddTraits(.isButton)
         }
         .cardSurface()
         .padding(.top, Theme.Spacing.section)
         .listRowSeparator(.hidden)
     }
 
     @ViewBuilder
     private var accountSection: some View {
         Section {
             Text("Account").sectionHeader()
             if auth.isSignedIn {
                 VStack(alignment: .leading, spacing: 6) {
                     Text(auth.displayName ?? "Signed in")
                         .font(Theme.Text.body)
                     Text("User ID: \(auth.currentUserID ?? "--")")
                         .font(Theme.Text.meta)
                         .foregroundStyle(Theme.Colors.secondaryText)
                     Button(role: .destructive) { auth.signOut() } label: {
                         Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                     }
                     .padding(.top, 6)
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
         .cardSurface()
         .padding(.top, Theme.Spacing.section)
         .listRowSeparator(.hidden)
     }
 
     @ToolbarContentBuilder
     private var toolbarContent: some ToolbarContent {
         ToolbarItem(placement: .cancellationAction) {
             Button(action: { onClose?() }) {
                 Text("Close")
                     .font(Theme.Text.body)
                     .foregroundStyle(.primary)
                     .padding(.horizontal, 12)
                     .padding(.vertical, 8)
                     .background(
                         Capsule()
                             .stroke(Theme.Colors.secondaryText.opacity(0.12), lineWidth: 1)
                     )
                     .contentShape(Capsule())
                     .frame(minWidth: 44, minHeight: 44)
             }
         }
         ToolbarItem(placement: .confirmationAction) { saveButton }
     }
 
     private var saveButton: some View {
         Button {
             onClose?()
             isSaving = true
             save()
             ProfileStore.setLocation(locationText, for: auth.currentUserID)
             isSaving = false
         } label: {
             Text("Save")
                 .font(Theme.Text.body)
                 .foregroundStyle(.primary)
                 .padding(.horizontal, 12)
                 .padding(.vertical, 8)
                 .background(
                     Capsule()
                         .stroke(Theme.Colors.secondaryText.opacity(0.12), lineWidth: 1)
                 )
                 .contentShape(Capsule())
                 .frame(minWidth: 44, minHeight: 44)
         }
         .disabled(profile == nil)
     }
 
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
 
     private func onAppearLoad() {
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
                 TasksManagerView()
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




















