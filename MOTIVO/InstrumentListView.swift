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
        try? moc.save()
        newInstrument = ""
    }

    private func delete(at offsets: IndexSet) {
        let list = instrumentsForProfile()
        for index in offsets {
            moc.delete(list[index])
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

