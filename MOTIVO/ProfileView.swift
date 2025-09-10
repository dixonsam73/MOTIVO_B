//
//  ProfileView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    // Instruments for the current profile (string-key sort descriptor per convention)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var instruments: FetchedResults<Instrument>

    // Local form state
    @State private var name: String = ""
    @State private var primaryInstrumentName: String = ""
    @State private var defaultPrivacy: Bool = false

    // Routing
    @State private var showInstrumentManager: Bool = false

    // Cached profile reference
    @State private var profile: Profile?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Toggle("Default public posts", isOn: $defaultPrivacy)
                        .accessibilityHint("When enabled, new sessions default to Public")
                }

                Section(header: Text("Primary Instrument")) {
                    if instruments.isEmpty {
                        HStack {
                            Text("No instruments added yet")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Manage…") { showInstrumentManager = true }
                        }
                    } else {
                        Picker("Primary", selection: $primaryInstrumentName) {
                            ForEach(instrumentsArray, id: \.self) { ins in
                                Text(ins).tag(ins)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("Manage instruments…") { showInstrumentManager = true }
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear { loadOrCreateProfile() }
            .sheet(isPresented: $showInstrumentManager) {
                InstrumentListView()
            }
        }
    }

    // MARK: - Derived
    private var instrumentsArray: [String] {
        instruments
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Data flow
    private func loadOrCreateProfile() {
        // Fetch (or create) singleton Profile
        let fr: NSFetchRequest<Profile> = Profile.fetchRequest()
        fr.fetchLimit = 1
        if let existing = (try? ctx.fetch(fr))?.first {
            profile = existing
        } else {
            let p = Profile(context: ctx)
            p.id = UUID()
            p.name = ""
            p.primaryInstrument = ""
            p.defaultPrivacy = false  // private by default
            try? ctx.save()
            profile = p
        }

        // Bind to form
        name = profile?.name ?? ""
        primaryInstrumentName = (profile?.primaryInstrument ?? "").isEmpty
            ? (instrumentsArray.first ?? "")
            : (profile?.primaryInstrument ?? "")
        defaultPrivacy = profile?.defaultPrivacy ?? false
    }

    private func save() {
        guard let p = profile else { return }
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.primaryInstrument = primaryInstrumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        p.defaultPrivacy = defaultPrivacy
        do {
            try ctx.save()
            dismiss()
        } catch {
            // Minimal error handling per your guardrails
        }
    }
}
