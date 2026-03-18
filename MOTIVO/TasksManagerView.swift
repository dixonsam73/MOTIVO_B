// CHANGE-ID: 20260318_143900_TasksManager_TasksPadCopy
// SCOPE: Add "Tasks Pad" section header and update toggle label to "Pre-fill tasks in Session Timer". No other UI or logic changes.
// SEARCH-TOKEN: 20260318_143900_TasksManager_TasksPadCopy

import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif

struct TasksManagerView: View {
    let activityRef: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.editMode) private var editMode

    @State private var selectedActivityRef: String = "core:0"
    @State private var items: [String] = []
    @State private var newItemText: String = ""
    @State private var autofillEnabled: Bool = true
    @State private var userActivities: [UserActivity] = []

    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    )
    private var instruments: FetchedResults<Instrument>

    @FetchRequest(entity: Profile.entity(), sortDescriptors: [])
    private var profiles: FetchedResults<Profile>

    @State private var selectedInstrumentID: UUID? = nil

    init(activityRef: String) {
        self.activityRef = activityRef
        _selectedActivityRef = State(initialValue: activityRef)
    }

    private var ownerScope: String {
        if let id = PersistenceController.shared.currentUserID,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        return "device"
    }

    private func normalizedActivityRef(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("core:") || trimmed.hasPrefix("custom:") {
            return trimmed
        }
        return "core:0"
    }

    private var currentNormalizedActivityRef: String {
        normalizedActivityRef(selectedActivityRef)
    }

    private var tasksKey: String { "practiceTasks_v1::" + ownerScope + "::" + currentNormalizedActivityRef + currentInstrumentKeySuffix }
    private var toggleKey: String { "practiceTasks_autofill_enabled::" + ownerScope + "::" + currentNormalizedActivityRef + currentInstrumentKeySuffix }

    private var legacyTasksKey: String { "practiceTasks_v1::" + ownerScope }
    private var legacyToggleKey: String { "practiceTasks_autofill_enabled::" + ownerScope }

    private var allActivityRefs: [String] {
        var result: [String] = []

        for t in SessionActivityType.allCases {
            result.append("core:\(t.rawValue)")
        }

        let customs: [String] = userActivities.compactMap { ua in
            let n = (ua.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "custom:\(n)"
        }

        for c in customs where !result.contains(c) {
            result.append(c)
        }

        let normalized = currentNormalizedActivityRef
        if !result.contains(normalized) {
            result.insert(normalized, at: 0)
        }

        return result
    }

    private func activityDisplayName(for ref: String) -> String {
        if ref.hasPrefix("core:"),
           let rawPart = ref.split(separator: ":").last,
           let rawValue = Int16(rawPart),
           let t = SessionActivityType(rawValue: rawValue) {
            return t.label
        } else if ref.hasPrefix("custom:") {
            return String(ref.dropFirst("custom:".count))
        }
        return SessionActivityType.practice.label
    }

    private var isSignedIn: Bool {
        PersistenceController.shared.currentUserID != nil
    }

    private var instrumentsForProfile: [Instrument] {
        guard isSignedIn else { return [] }
        guard let p = profiles.first else { return [] }
        return instruments.filter { $0.profile == p }
    }

    private var shouldShowInstrumentSelector: Bool {
        instrumentsForProfile.count > 1
    }

    private var currentInstrumentKeySuffix: String {
        guard shouldShowInstrumentSelector,
              let id = selectedInstrumentID else { return "" }
        return "::inst:" + id.uuidString
    }

    private func instrumentDisplayName(for id: UUID?) -> String {
        guard let id else { return "" }
        return instrumentsForProfile.first(where: { $0.id == id })?.name ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {

                Section(header: Text("Activity").sectionHeader()) {
                    HStack {
                        Menu {
                            ForEach(allActivityRefs, id: \.self) { ref in
                                Button {
                                    selectedActivityRef = ref
                                } label: {
                                    Label(
                                        activityDisplayName(for: ref),
                                        systemImage: ref == selectedActivityRef ? "checkmark" : "circle"
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(activityDisplayName(for: selectedActivityRef))
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Theme.Colors.accent)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                    }
                }

                if shouldShowInstrumentSelector {
                    Section(header: Text("Instrument").sectionHeader()) {
                        HStack {
                            Menu {
                                ForEach(instrumentsForProfile, id: \.objectID) { inst in
                                    Button {
                                        selectedInstrumentID = inst.id
                                    } label: {
                                        Label(
                                            inst.name ?? "",
                                            systemImage: (inst.id == selectedInstrumentID) ? "checkmark" : "circle"
                                        )
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(instrumentDisplayName(for: selectedInstrumentID))
                                        .font(Theme.Text.body)
                                        .foregroundStyle(Theme.Colors.accent)

                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                            }
                        }
                    }
                }

                // ✅ UPDATED SECTION
                Section(header: Text("Tasks Pad").sectionHeader()) {
                    Toggle("Pre-fill tasks in Session Timer", isOn: $autofillEnabled)
                        .font(Theme.Text.body)
                        .tint(Theme.Colors.accent)
                        .onChange(of: autofillEnabled) { _ in
                            saveToggle()
                        }
                }

                Section(header: Text("Add Task").sectionHeader()) {
                    HStack {
                        TextField("Add task", text: $newItemText)
                            .font(Theme.Text.body)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)

                        if !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: addItem) {
                                Text("Add")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                }

                Section(header: Text("Your Tasks").sectionHeader()) {
                    ForEach(items.indices, id: \.self) { index in
                        Text(items[index])
                            .font(Theme.Text.body)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Tasks Manager")
                        .font(Theme.Text.pageTitle)
                }
            }
            .onAppear {
                selectedActivityRef = normalizedActivityRef(activityRef)
                loadUserActivities()
                if shouldShowInstrumentSelector, selectedInstrumentID == nil {
                    selectedInstrumentID = instrumentsForProfile.first?.id
                }
                loadAll()
            }
            .onChange(of: selectedActivityRef) { _ in loadAll() }
            .onChange(of: selectedInstrumentID) { _ in loadAll() }
            .appBackground()
        }
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newItemText = ""
        saveItems()
    }

    private func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }

    private func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        saveItems()
    }

    private func loadAll() {
        let defaults = UserDefaults.standard

        if let arr = defaults.array(forKey: tasksKey) as? [String] {
            items = arr
        } else if let legacyArr = defaults.array(forKey: legacyTasksKey) as? [String] {
            items = legacyArr
        } else {
            items = []
        }

        if defaults.object(forKey: toggleKey) != nil {
            autofillEnabled = defaults.bool(forKey: toggleKey)
        } else if defaults.object(forKey: legacyToggleKey) != nil {
            autofillEnabled = defaults.bool(forKey: legacyToggleKey)
        } else {
            autofillEnabled = true
        }
    }

    private func saveItems() {
        UserDefaults.standard.set(items, forKey: tasksKey)
    }

    private func saveToggle() {
        UserDefaults.standard.set(autofillEnabled, forKey: toggleKey)
    }

    private func loadUserActivities() {
        let req: NSFetchRequest<UserActivity> = UserActivity.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
        userActivities = (try? viewContext.fetch(req)) ?? []
    }
}
