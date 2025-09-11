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
                Section(header: Text("Profile")) {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Toggle("Default public posts", isOn: $defaultPrivacy)
                }

                Section(header: Text("Primary Instrument")) {
                    if instruments.isEmpty {
                        HStack {
                            Text("No instruments added yet").foregroundStyle(.secondary)
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
                    Button("Close") { onClose?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        // 1) Close immediately
                        onClose?()
                        // 2) Save next tick
                        DispatchQueue.main.async { save() }
                    }
                }
            }
            .onAppear { loadOrCreateProfile() }
            .sheet(isPresented: $showInstrumentManager) { InstrumentListView() }
        }
    }

    private var instrumentsArray: [String] {
        instruments
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func loadOrCreateProfile() {
        let fr: NSFetchRequest<Profile> = Profile.fetchRequest()
        fr.fetchLimit = 1
        if let existing = (try? ctx.fetch(fr))?.first {
            profile = existing
        } else {
            let p = Profile(context: ctx)
            p.id = UUID()
            p.name = ""
            p.primaryInstrument = ""
            p.defaultPrivacy = false
            try? ctx.save()
            profile = p
        }

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
        do { try ctx.save() } catch { /* minimal handling */ }
    }
}
