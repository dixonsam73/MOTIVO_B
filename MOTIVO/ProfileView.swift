//
//  ProfileView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    // Single profile
    @FetchRequest(sortDescriptors: [], animation: .default)
    private var profiles: FetchedResults<Profile>

    // All instruments (we’ll filter by profile in code)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Instrument.name, ascending: true)],
        animation: .default
    )
    private var allInstruments: FetchedResults<Instrument>

    @State private var name: String = ""
    @State private var primaryInstrument: String = ""
    @State private var newInstrument: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Basic info
                Section("Your Details") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()

                    Picker("Primary instrument", selection: $primaryInstrument) {
                        ForEach(instrumentNames, id: \.self) { inst in
                            Text(inst).tag(inst)
                        }
                    }

                    if instrumentNames.isEmpty {
                        Text("Add at least one instrument below to choose a primary.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Instruments
                Section("Your Instruments") {
                    HStack {
                        TextField("Add instrument (e.g. Bass, Piano)", text: $newInstrument)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        Button("Add") { addInstrument() }
                            .disabled(newInstrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if profileInstruments.isEmpty {
                        Text("No instruments yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(profileInstruments, id: \.objectID) { instrument in
                            InstrumentRow(
                                name: instrument.name ?? "",
                                isPrimary: (instrument.name ?? "") == primaryInstrument,
                                setPrimary: { primaryInstrument = instrument.name ?? "" },
                                delete: { deleteInstrument(instrument) }
                            )
                        }
                        .onDelete(perform: deleteInstrumentsAt)
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
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { ensureProfileLoaded() }
        }
    }

    // MARK: - Derived data

    private var profileInstruments: [Instrument] {
        guard let p = profiles.first else { return [] }
        return allInstruments.filter { inst in
            inst.profile == p
        }
    }

    private var instrumentNames: [String] {
        var names: [String] = []
        for inst in profileInstruments {
            if let n = inst.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                names.append(n)
            }
        }
        return names
    }

    // MARK: - Lifecycle & actions

    private func ensureProfileLoaded() {
        if profiles.first == nil {
            let p = Profile(context: moc)
            p.id = UUID()
            p.name = ""
            p.primaryInstrument = ""
            try? moc.save()
        }

        if let p = profiles.first {
            name = p.name ?? ""
            primaryInstrument = (p.primaryInstrument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if primaryInstrument.isEmpty, let first = instrumentNames.first {
                primaryInstrument = first
            }
        }
    }

    private func save() {
        guard let p = profiles.first else { return }
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.primaryInstrument = primaryInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        try? moc.save()
        dismiss()
    }

    private func addInstrument() {
        let value = newInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return }

        // Avoid duplicates (case-insensitive)
        let lowerExisting = instrumentNames.map { $0.lowercased() }
        if lowerExisting.contains(value.lowercased()) {
            newInstrument = ""
            return
        }

        let inst = Instrument(context: moc)
        inst.id = UUID()
        inst.name = value
        inst.profile = profiles.first
        try? moc.save()

        if primaryInstrument.isEmpty {
            primaryInstrument = value
        }

        newInstrument = ""
    }

    private func deleteInstrument(_ inst: Instrument) {
        let removed = inst.name ?? ""
        moc.delete(inst)
        try? moc.save()

        if removed == primaryInstrument {
            primaryInstrument = instrumentNames.first ?? ""
        }
    }

    private func deleteInstrumentsAt(_ offsets: IndexSet) {
        let items = profileInstruments
        var removedPrimary = false

        for index in offsets {
            let inst = items[index]
            if (inst.name ?? "") == primaryInstrument {
                removedPrimary = true
            }
            moc.delete(inst)
        }
        try? moc.save()

        if removedPrimary {
            primaryInstrument = instrumentNames.first ?? ""
        }
    }
}

// MARK: - Small row

private struct InstrumentRow: View {
    let name: String
    let isPrimary: Bool
    let setPrimary: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isPrimary ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(.tint) // <-- was .accent

            Text(name)
                .lineLimit(1)

            Spacer()

            if isPrimary {
                Text("Primary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { setPrimary() }
        .contextMenu {
            Button("Set as Primary") { setPrimary() }
            Button("Delete", role: .destructive) { delete() }
        }
    }
}
