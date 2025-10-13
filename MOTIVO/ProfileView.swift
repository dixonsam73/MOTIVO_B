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

    // Primary Activity (Stage 1 persisted in AppStorage; Stage 2 UX hardening)
    // Format: "core:<raw>" or "custom:<name>"
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"
    @State private var userActivities: [UserActivity] = []
    @State private var primaryActivityChoice: String = "core:0" // mirrors picker; same tag format

    // Stage 2: one-time notice flag (set in ActivityListView on fallback)
    @AppStorage("primaryActivityFallbackNoticeNeeded") private var primaryFallbackNoticeNeeded: Bool = false
    @State private var showPrimaryFallbackAlert: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Profile
                Section {
                    Text("Name").sectionHeader()
                    VStack(spacing: Theme.Spacing.s) {
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
                }
                .listRowSeparator(.hidden)

                Section {
                    Toggle("Default to Private Posts", isOn: $defaultPrivacy)
                }
                .listRowSeparator(.hidden)

                // MARK: - Instruments (Manage above Primary)
                Section {
                    // Removed header Text("Instruments").sectionHeader()

                    // Manage button aligned with section edge
                    Button {
                        showInstrumentManager = true
                    } label: {
                        HStack {
                            Text("Manage Instruments")
                            Spacer()
                            Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
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
                .listRowSeparator(.hidden)

                // MARK: - Activities (Manage above Primary; no separator line)
                Section {
                    // Removed header Text("Activities").sectionHeader()

                    Button {
                        showActivityManager = true
                    } label: {
                        HStack {
                            Text("Manage Activities")
                            Spacer()
                            Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isButton)

                    VStack(spacing: Theme.Spacing.s) {
                        Picker("Primary Activity", selection: $primaryActivityChoice) {
                            // Core activities first
                            ForEach(SessionActivityType.allCases) { type in
                                Text(type.label).tag("core:\(type.rawValue)")
                            }
                            // Then user customs directly
                            ForEach(userActivities.compactMap { $0.displayName }, id: \.self) { name in
                                Text(name).tag("custom:\(name)")
                            }
                        }
                        .onChange(of: primaryActivityChoice) { _, newValue in
                            writePrimaryActivityRef(newValue)
                        }
                    }
                }
                .listRowSeparator(.hidden)

                Section {
                    Button {
                        showTasksManager = true
                    } label: {
                        HStack {
                            Text("Manage Tasks")
                            Spacer()
                            Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isButton)
                }
                .listRowSeparator(.hidden)

                // MARK: - Account (bottom)
                Section {
                    Text("Account").sectionHeader()
                    if auth.isSignedIn {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(auth.displayName ?? "Signed in")
                                .font(.headline)
                            Text("User ID: \(auth.currentUserID ?? "--")")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                            Button(role: .destructive) {
                                auth.signOut()
                            } label: {
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
                .listRowSeparator(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onClose?()
                        isSaving = true
                        save()
                        isSaving = false
                    } label: { Text("Save") }
                    .disabled(profile == nil)
                }
            }
            .appBackground()
            .onAppear {
                load()
                refreshUserActivities()
                primaryActivityChoice = normalizedPrimaryActivityRef()
                if primaryFallbackNoticeNeeded {
                    showPrimaryFallbackAlert = true
                    primaryFallbackNoticeNeeded = false
                }
            }
            .onChange(of: showActivityManager) { wasPresented, isPresented in
                if wasPresented == true && isPresented == false {
                    refreshUserActivities()
                    primaryActivityChoice = normalizedPrimaryActivityRef()
                }
            }
            .onChange(of: primaryActivityRef) { _, _ in
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
}

//  [ROLLBACK ANCHOR] v7.8 DesignLite — post



