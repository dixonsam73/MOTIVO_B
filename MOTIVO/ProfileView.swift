////
//  ProfileView.swift
//  MOTIVO
//
//  [ROLLBACK ANCHOR] v7.8 Scope1 — pre-primary-activity (no primary activity selector; icons on manage rows; account at top)
//
//  v7.8 Stage 2 — Primary fallback notice + live sync
//  - Shows a one-time in-app notice if Primary (custom) was deleted/hidden and auto-reset to Practice.
//  - Live-syncs the Primary picker when returning from Activity Manager or when AppStorage changes.
//  - No schema/migrations.
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

    @State private var showInstrumentManager: Bool = false
    @State private var showActivityManager: Bool = false
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
                Section(header: Text("Profile")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    Toggle("Default to Private Posts", isOn: $defaultPrivacy)
                }

                // MARK: - Instruments (includes Primary Instrument picker)
                Section {
                    Picker("Primary Instrument", selection: $primaryInstrumentName) {
                        ForEach(instruments.map { $0.name ?? "" }.filter { !$0.isEmpty }, id: \.self) { n in
                            Text(n).tag(n)
                        }
                    }

                    Button {
                        showInstrumentManager = true
                    } label: {
                        Text("Manage Instruments")
                    }
                }

                // MARK: - Activities (includes Primary Activity picker; no separator line)
                Section {
                    Picker("Primary Activity", selection: $primaryActivityChoice) {
                        // Core activities first
                        ForEach(SessionActivityType.allCases) { type in
                            Text(type.label).tag("core:\(type.rawValue)")
                        }
                        // Then user customs directly (no "— Your Activities —" separator)
                        ForEach(userActivities.compactMap { $0.displayName }, id: \.self) { name in
                            Text(name).tag("custom:\(name)")
                        }
                    }
                    .onChange(of: primaryActivityChoice) { newValue in
                        writePrimaryActivityRef(newValue)
                    }

                    Button {
                        showActivityManager = true
                    } label: {
                        Text("Manage Activities")
                    }
                }

                // MARK: - Account (bottom)
                Section(header: Text("Account")) {
                    if auth.isSignedIn {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(auth.displayName ?? "Signed in")
                                .font(.headline)
                            Text("User ID: \(auth.currentUserID ?? "--")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                        .accessibilityLabel("Sign in with Apple")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onClose?()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        // Close-first strategy
                        onClose?()
                        // Then persist
                        isSaving = true
                        save()
                        isSaving = false
                    } label: {
                        Text("Save")
                    }
                    .disabled(profile == nil)
                }
            }
            // Initial hydration
            .onAppear {
                load()
                refreshUserActivities()
                // Sync local picker from stored ref (normalize if needed)
                primaryActivityChoice = normalizedPrimaryActivityRef()

                // Stage 2: show one-time notice if flagged by ActivityListView
                if primaryFallbackNoticeNeeded {
                    showPrimaryFallbackAlert = true
                    // Clear the flag immediately so it's truly one-time
                    primaryFallbackNoticeNeeded = false
                }
            }
            // When returning from Activity Manager, refresh customs and re-normalize picker
            .onChange(of: showActivityManager) { wasPresented, isPresented in
                if wasPresented == true && isPresented == false {
                    refreshUserActivities()
                    primaryActivityChoice = normalizedPrimaryActivityRef()
                }
            }
            // If the underlying AppStorage value changes (e.g., due to deletion in manager),
            // keep the picker selection in sync.
            .onChange(of: primaryActivityRef) { _, _ in
                primaryActivityChoice = normalizedPrimaryActivityRef()
            }
            // One-time alert
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
        }
    }

    // MARK: - Data

    private var instrumentsArray: [String] {
        instruments.map { $0.name ?? "" }.filter { !$0.isEmpty }
    }

    private func load() {
        // Ensure a single Profile record exists; fetch/create.
        let req: NSFetchRequest<Profile> = Profile.fetchRequest()
        req.fetchLimit = 1
        do {
            if let existing = try ctx.fetch(req).first {
                profile = existing
                // Backfill missing id if needed
                if profile?.value(forKey: "id") == nil {
                    profile?.setValue(UUID(), forKey: "id")
                    try? ctx.save()
                }
            } else {
                let p = Profile(context: ctx)
                // Ensure required fields are present
                p.setValue(UUID(), forKey: "id") // ensure id
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
        // Ensure id is set before any save
        if p.value(forKey: "id") == nil {
            p.setValue(UUID(), forKey: "id")
        }
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.primaryInstrument = primaryInstrumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        p.defaultPrivacy = defaultPrivacy
        do { try ctx.save() } catch {
            // Consider surfacing a user-facing alert if needed
        }
    }

    // MARK: - Primary Activity helpers

    private func refreshUserActivities() {
        do {
            userActivities = try PersistenceController.shared.fetchUserActivities(in: ctx)
        } catch {
            userActivities = []
        }
    }

    /// Returns a normalized, valid ref. Falls back to "core:0" if invalid or custom missing.
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
                // custom no longer exists → fallback to Practice
                return "core:0"
            }
        } else {
            return "core:0"
        }
    }

    /// Persists the user's selection and keeps local state in sync.
    private func writePrimaryActivityRef(_ newValue: String) {
        // Normalize against current customs
        let normalized = normalizeChoiceString(newValue)
        primaryActivityRef = normalized
        primaryActivityChoice = normalized
    }

    /// Normalizes picker choice strings to valid "core:<raw>" / "custom:<name>" respecting available customs.
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
