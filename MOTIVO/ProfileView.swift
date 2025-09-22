////
//  ProfileView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
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
    @State private var profile: Profile?
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Auth / Account section
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

                // MARK: - Profile section
                Section(header: Text("Profile")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    Picker("Primary Instrument", selection: $primaryInstrumentName) {
                        ForEach(instruments.map { $0.name ?? "" }.filter { !$0.isEmpty }, id: \.self) { n in
                            Text(n).tag(n)
                        }
                    }

                    Toggle("Default to Private Posts", isOn: $defaultPrivacy)
                }

                // MARK: - Instruments
                Section {
                    Button {
                        showInstrumentManager = true
                    } label: {
                        Label("Manage Instruments", systemImage: "guitars")
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
            .onAppear(perform: load)
            .sheet(isPresented: $showInstrumentManager) {
                InstrumentListView()
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
                p.setValue(UUID(), forKey: "id") // <- make id non-nil up front
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
            // You could surface a user-facing alert here if desired
        }
    }
}
