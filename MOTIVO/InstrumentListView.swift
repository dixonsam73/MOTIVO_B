//
//  InstrumentListView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

// CHANGE-ID: 20260228_223800_InstrumentList_KeyboardDismiss
// SCOPE: Dismiss Add Instrument keyboard after Add tapped (no other UI/logic changes)

// CHANGE-ID: 20260119_203800_IdentityScopeSignOut_Instruments
// SCOPE: Correctness/hygiene — Instruments Manager renders empty when signed out; no other UI/logic changes

// CHANGE-ID: 20260316_191540_InstrumentPrimaryPersistedReload
// SCOPE: Keep row-tap primary selector in InstrumentListView, persist to Profile.primaryInstrument, and rehydrate tick state from persisted Profile after save; no other UI/logic changes.

import SwiftUI
import CoreData

struct InstrumentListView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    )
    private var instruments: FetchedResults<Instrument>

    @FetchRequest(entity: Profile.entity(), sortDescriptors: [])
    private var profiles: FetchedResults<Profile>

    @State private var profile: Profile?
    @State private var primaryInstrumentName: String = ""
    @State private var newInstrument: String = ""
    @FocusState private var isAddInstrumentFocused: Bool

    private var isSignedIn: Bool {
        PersistenceController.shared.currentUserID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Add Instrument").sectionHeader()) {
                    HStack {
                        TextField("e.g. Bass, Piano", text: $newInstrument)
                            .font(Theme.Text.body)
                            .disabled(!isSignedIn)
                            .textInputAutocapitalization(.words)
                            .focused($isAddInstrumentFocused)

                        Button(action: { add() }) {
                            Text("Add")
                                .font(Theme.Text.body)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSignedIn || newInstrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section(header: Text("Your Instruments").sectionHeader()) {
                    Text("Tap to set the default instrument.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))

                    ForEach(instrumentsForProfile(), id: \.objectID) { inst in
                        Button {
                            setPrimaryInstrument(inst)
                        } label: {
                            HStack {
                                Text(inst.name ?? "")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if isCurrentPrimary(inst) {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Instruments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Instruments")
                        .font(Theme.Text.pageTitle)
                        .foregroundStyle(.primary)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close instruments")
                }
            }
            .appBackground()
            .onAppear {
                loadPrimarySelection()
            }
        }
    }

    private func instrumentsForProfile() -> [Instrument] {
        guard isSignedIn else { return [] }
        guard let p = profile ?? loadProfileOnly() else { return [] }
        return instruments.filter { $0.profile == p }
    }

    private func isCurrentPrimary(_ instrument: Instrument) -> Bool {
        let name = (instrument.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name == primaryInstrumentName
    }

    private func setPrimaryInstrument(_ instrument: Instrument) {
        guard isSignedIn else { return }
        let name = (instrument.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard name != primaryInstrumentName else { return }

        if profile == nil {
            loadPrimarySelection()
        }
        guard let p = profile else { return }

        p.primaryInstrument = name

        do {
            try moc.save()
            loadPrimarySelection()
        } catch {
            moc.rollback()
            loadPrimarySelection()
            print("Instrument primary save failed: \(error)")
        }
    }

    private func add() {
        guard isSignedIn else { return }
        let name = newInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard let ownerProfile = fetchOrCreateProfile() else { return }

        let existing = instrumentsForProfile().compactMap { $0.name?.lowercased() }
        if existing.contains(name.lowercased()) {
            newInstrument = ""
            isAddInstrumentFocused = false
            return
        }

        let inst = Instrument(context: moc)
        inst.id = UUID()
        inst.name = name
        inst.profile = ownerProfile

        if let instrumentName = inst.name, !instrumentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                _ = try PersistenceController.shared.fetchOrCreateUserInstrument(
                    named: instrumentName,
                    mapTo: inst,
                    visibleOnProfile: true,
                    in: moc
                )
            } catch {
                print("UserInstrument mirror failed: \(error)")
            }
        }

        do {
            try moc.save()
        } catch {
            moc.rollback()
            print("Instrument add failed: \(error)")
            return
        }

        newInstrument = ""
        isAddInstrumentFocused = false
        loadPrimarySelection()
    }

    private func delete(at offsets: IndexSet) {
        guard isSignedIn else { return }
        let list = instrumentsForProfile()
        for index in offsets {
            let inst = list[index]
            let name = (inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            moc.delete(inst)

            if !name.isEmpty {
                let norm = PersistenceController.normalized(name)
                let fr: NSFetchRequest<UserInstrument> = UserInstrument.fetchRequest()
                var predicates: [NSPredicate] = []
                if let owner = PersistenceController.shared.ownerIDForCustoms {
                    predicates.append(NSPredicate(format: "ownerUserID == %@", owner))
                }
                predicates.append(NSPredicate(format: "normalizedName == %@", norm))
                fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                if let matches = try? moc.fetch(fr) {
                    for ui in matches { moc.delete(ui) }
                }
            }
        }

        do {
            try moc.save()
        } catch {
            moc.rollback()
            print("Instrument delete failed: \(error)")
            return
        }

        loadPrimarySelection()
    }

    private func loadProfileOnly() -> Profile? {
        guard isSignedIn else { return nil }
        let req: NSFetchRequest<Profile> = Profile.fetchRequest()
        req.fetchLimit = 1
        do {
            if let existing = try moc.fetch(req).first {
                if existing.value(forKey: "id") == nil {
                    existing.setValue(UUID(), forKey: "id")
                    try? moc.save()
                }
                profile = existing
                return existing
            } else {
                let p = Profile(context: moc)
                p.setValue(UUID(), forKey: "id")
                p.name = ""
                p.primaryInstrument = instrumentsForProfileNames().first ?? ""
                p.defaultPrivacy = false
                try? moc.save()
                profile = p
                return p
            }
        } catch {
            print("Profile load failed: \(error)")
            return nil
        }
    }

    private func loadPrimarySelection() {
        guard isSignedIn else {
            profile = nil
            primaryInstrumentName = ""
            return
        }

        let loadedProfile = loadProfileOnly()
        let persisted = (loadedProfile?.primaryInstrument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        primaryInstrumentName = persisted.isEmpty
            ? (instrumentsForProfileNames().first ?? "")
            : persisted
    }

    private func instrumentsForProfileNames() -> [String] {
        guard let p = profile ?? profiles.first else { return [] }
        return instruments
            .filter { $0.profile == p }
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func fetchOrCreateProfile() -> Profile? {
        guard isSignedIn else { return nil }
        if let existing = profile {
            return existing
        }
        return loadProfileOnly()
    }
}
