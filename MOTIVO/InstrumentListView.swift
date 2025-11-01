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
                Section(header: Text("Add Instrument").sectionHeader()) {
                    HStack {
                        TextField("e.g. Bass, Piano", text: $newInstrument)
                            .font(Theme.Text.body)
                            .textInputAutocapitalization(.words)
                        Button(action: { add() }) { Text("Add").font(Theme.Text.body) }
                            .disabled(newInstrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section(header: Text("Your Instruments").sectionHeader()) {
                    ForEach(instrumentsForProfile(), id: \.objectID) { inst in
                        Text(inst.name ?? "").font(Theme.Text.body)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Instruments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Instruments").font(Theme.Text.pageTitle).foregroundStyle(.primary)
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Button(action: { dismiss() }) {
                        Text("Close")
                            .font(Theme.Text.body)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .contentShape(Capsule())
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44, alignment: .center)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .padding(.top, 6)
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
