//
//  InstrumentListView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct InstrumentListView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    // Use string keys to avoid key-path inference issues
    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    )
    private var instruments: FetchedResults<Instrument>

    @FetchRequest(entity: Profile.entity(), sortDescriptors: [])
    private var profiles: FetchedResults<Profile>

    @State private var newInstrument: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Instrument") {
                    HStack {
                        TextField("e.g. Bass, Piano", text: $newInstrument)
                            .textInputAutocapitalization(.words)
                        Button("Add") { add() }
                            .disabled(newInstrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Your Instruments") {
                    ForEach(instrumentsForProfile(), id: \.objectID) { inst in
                        Text(inst.name ?? "")
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Instruments")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func instrumentsForProfile() -> [Instrument] {
        guard let p = profiles.first else { return [] }
        return instruments.filter { $0.profile == p }
    }

    private func add() {
        let name = newInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard let profile = fetchOrCreateProfile() else { return }

        // Avoid duplicates (case-insensitive)
        let existing = instrumentsForProfile().compactMap { $0.name?.lowercased() }
        if existing.contains(name.lowercased()) { newInstrument = ""; return }

        let inst = Instrument(context: moc)
        inst.id = UUID()
        inst.name = name
        inst.profile = profile

        // Mirror into owner-scoped UserInstrument so Profile/ProfilePeek can display chips
        if let name = inst.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                _ = try PersistenceController.shared.fetchOrCreateUserInstrument(
                    named: name,
                    mapTo: inst,
                    visibleOnProfile: true,
                    in: moc
                )
            } catch {
                // Non-fatal: the profile list still updates; peek chips may lag
                print("UserInstrument mirror failed: \(error)")
            }
        }

        try? moc.save()
        newInstrument = ""
    }

    private func delete(at offsets: IndexSet) {
        let list = instrumentsForProfile()
        for index in offsets {
            let inst = list[index]
            // Capture name before delete to resolve the corresponding UserInstrument
            let name = (inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            moc.delete(inst)
            // Attempt to delete the mirrored UserInstrument for the current owner by normalized name
            if !name.isEmpty {
                let norm = PersistenceController.normalized(name)
                let fr: NSFetchRequest<UserInstrument> = UserInstrument.fetchRequest()
                var predicates: [NSPredicate] = []
                if let owner = PersistenceController.shared.ownerIDForCustoms { predicates.append(NSPredicate(format: "ownerUserID == %@", owner)) }
                predicates.append(NSPredicate(format: "normalizedName == %@", norm))
                fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                if let matches = try? moc.fetch(fr) {
                    for ui in matches { moc.delete(ui) }
                }
            }
        }
        try? moc.save()
    }

    private func fetchOrCreateProfile() -> Profile? {
        if let p = profiles.first { return p }
        let p = Profile(context: moc)
        p.id = UUID()
        p.name = ""
        p.primaryInstrument = ""
        try? moc.save()
        return p
    }
}

