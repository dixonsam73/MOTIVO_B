// CHANGE-ID: 20260321_134500_TasksManager_ImportSavedSets_DefaultSelector
// SCOPE: Add task import (paste/scan), saved task sets, and default-set selector within existing TasksManager system. No Core Data/backend changes.
// SEARCH-TOKEN: 20260321_134500_TasksManager_ImportSavedSets_DefaultSelector

import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers
#if canImport(Vision)
import Vision
#endif

private struct ImportedTaskDraftLineDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draftLines: [TasksManagerView.EditableImportedTaskLine]
    @Binding var draggedLineID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedLineID,
              draggedLineID != targetID,
              let from = draftLines.firstIndex(where: { $0.id == draggedLineID }),
              let to = draftLines.firstIndex(where: { $0.id == targetID })
        else { return }

        if draftLines[to].id != draggedLineID {
            withAnimation(.easeInOut(duration: 0.18)) {
                draftLines.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedLineID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

#if canImport(VisionKit)
import VisionKit
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
    @State private var selectedTaskSetID: UUID? = nil
    @State private var savedTaskSets: [SavedTaskSet] = []
    @State private var draftTaskSetName: String = ""
    @State private var showTaskImportLauncher: Bool = false
    @State private var showTaskImportPasteSheet: Bool = false
    @State private var showTaskImportScanSheet: Bool = false
    @State private var showSaveCurrentTaskSetPrompt: Bool = false
    @State private var showDefaultTaskSetSheet: Bool = false
    @State private var pastedImportText: String = ""
    @State private var importDraftItems: [String] = []
    @State private var importDraftTaskSetName: String = ""
    @State private var importDraftLines: [EditableImportedTaskLine] = []
    @State private var draggedImportLineID: UUID? = nil
    @State private var suppressImportedRawTextObserver: Bool = false
    @FocusState private var focusedImportLineID: UUID?

    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    )
    private var instruments: FetchedResults<Instrument>

    @FetchRequest(entity: Profile.entity(), sortDescriptors: [])
    private var profiles: FetchedResults<Profile>

    @State private var selectedInstrumentID: UUID? = nil

    private struct SavedTaskSet: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var items: [String]
    }

    fileprivate struct EditableImportedTaskLine: Identifiable, Equatable {
        let id: UUID = UUID()
        var text: String
    }

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
    private var taskSetsKey: String { tasksKey + "::saved_sets_v1" }
    private var globalTaskSetsKey: String { "practiceTasks_saved_sets_v2::" + ownerScope }
    private var defaultTaskSetIDKey: String { tasksKey + "::default_set_id_v1" }

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

    private var hasSavedTaskSets: Bool {
        !savedTaskSets.isEmpty
    }

    private var selectedTaskSet: SavedTaskSet? {
        guard let id = selectedTaskSetID else { return nil }
        return savedTaskSets.first(where: { $0.id == id })
    }

    private var canSaveCurrentAsTaskSet: Bool {
        !items.isEmpty
    }

    private var showsSingleTopSelector: Bool {
        !shouldShowInstrumentSelector
    }

    @ViewBuilder
    private var selectorSectionContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if showsSingleTopSelector {
                Text("Activity")
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    selectorSectionContent
                }

                Section(header: Text("Tasks Pad").sectionHeader()) {
                    Toggle("Pre-fill tasks in Session Timer", isOn: $autofillEnabled)
                        .font(Theme.Text.body)
                        .tint(Theme.Colors.accent)
                        .onChange(of: autofillEnabled) { _ in
                            saveToggle()
                        }

                    HStack {
                        Text("Default task set")
                            .font(Theme.Text.body)
                        Spacer()
                        Button {
                            showDefaultTaskSetSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedTaskSet?.name ?? "Current list")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Theme.Colors.accent)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button(action: { showTaskImportLauncher = true }) {
                        Text("Import tasks")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    if canSaveCurrentAsTaskSet {
                        Button(action: saveCurrentItemsAsTaskSet) {
                            Text("Save current list as task set")
                                .font(Theme.Text.body)
                                .foregroundStyle(Theme.Colors.accent)
                        }
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
            }
            
            .fullScreenCover(isPresented: $showTaskImportLauncher) {
                TasksManagerImportLauncherSheet(
                    onCancel: {
                        showTaskImportLauncher = false
                    },
                    onPasteOrType: {
                        pastedImportText = ""
                        importDraftItems = []
                        importDraftLines = []
                        importDraftTaskSetName = defaultImportedTaskSetName(from: [])
                        showTaskImportLauncher = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showTaskImportPasteSheet = true
                        }
                    },
                    onScan: {
                        importDraftItems = []
                        importDraftLines = []
                        importDraftTaskSetName = defaultImportedTaskSetName(from: [])
                        showTaskImportLauncher = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showTaskImportScanSheet = true
                        }
                    }
                )
            }
.sheet(isPresented: $showTaskImportPasteSheet) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                Text("Add tasks")
                                    .sectionHeader()

                                Spacer()

                                Button {
                                    guard let pasted = UIPasteboard.general.string,
                                          pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                    else { return }

                                    suppressImportedRawTextObserver = true
                                    pastedImportText = pasted
                                    suppressImportedRawTextObserver = false
                                    handleImportedRawTextChanged(oldValue: "", newValue: pasted)
                                } label: {
                                    Text("Paste")
                                        .font(Theme.Text.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                                .fill(Color.secondary.opacity(0.12))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 0) {
                                if !importDraftLines.isEmpty {
                                    ForEach($importDraftLines) { $line in
                                        importedTaskDraftRow($line)
                                            .onDrop(
                                                of: [UTType.text],
                                                delegate: ImportedTaskDraftLineDropDelegate(
                                                    targetID: line.id,
                                                    draftLines: $importDraftLines,
                                                    draggedLineID: $draggedImportLineID
                                                )
                                            )

                                        if line.id != importDraftLines.last?.id {
                                            Divider()
                                        }
                                    }
                                }

                                if !importDraftLines.isEmpty && !pastedImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Divider()
                                        .padding(.vertical, 8)
                                }

                                TextEditor(text: $pastedImportText)
                                    .frame(minHeight: importDraftLines.isEmpty ? 140 : 44)
                                    .font(Theme.Text.body)
                                    .scrollContentBackground(.hidden)
                                    .onChange(of: pastedImportText) { oldValue, newValue in
                                        handleImportedRawTextChanged(oldValue: oldValue, newValue: newValue)
                                    }
                            }
                            .cardSurface()

                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                Text("Task set name")
                                    .sectionHeader()
                                TextField("Task set name", text: $importDraftTaskSetName)
                                    .font(Theme.Text.body)
                                    .textInputAutocapitalization(.words)
                                    .padding(.horizontal, 14)
                                    .frame(height: 44)
                                    .cardSurface()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded { dismissImportedTaskKeyboard() })
                    .navigationTitle("")
                                        .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showTaskImportPasteSheet = false
                            }
                            .foregroundStyle(Theme.Colors.accent)
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save task set") {
                                saveImportedTaskSetFromDraft()
                            }
                            .foregroundStyle(Theme.Colors.accent)
                            .disabled(importDraftItems.isEmpty)
                        }
                    }
                    .appBackground()
                }
            }
            .sheet(isPresented: $showTaskImportScanSheet) {
                TasksManagerImportScanSheet {
                    recognizedText in
                    let parsed = Self.parseImportedTaskLines(from: recognizedText)
                    importDraftItems = parsed
                    importDraftLines = parsed.map { EditableImportedTaskLine(text: $0) }
                    importDraftTaskSetName = defaultImportedTaskSetName(from: parsed)
                    pastedImportText = ""
                    showTaskImportScanSheet = false
                    showTaskImportPasteSheet = true
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showDefaultTaskSetSheet) {
                NavigationStack {
                    Form {
                        Section {
                            HStack(spacing: Theme.Spacing.m) {
                                Button {
                                    selectedTaskSetID = nil
                                    draftTaskSetName = ""
                                    saveTaskSetSelectionAndItems()
                                    showDefaultTaskSetSheet = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedTaskSetID == nil ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Theme.Colors.accent)
                                        Text("Current list")
                                            .font(Theme.Text.body)
                                            .foregroundStyle(.primary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Spacer(minLength: 0)
                            }
                        }

                        if !savedTaskSets.isEmpty {
                            Section {
                                ForEach(savedTaskSets) { set in
                                    HStack(spacing: Theme.Spacing.m) {
                                        Button {
                                            selectTaskSet(set.id)
                                            showDefaultTaskSetSheet = false
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: selectedTaskSetID == set.id ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(Theme.Colors.accent)
                                                Text(set.name)
                                                    .font(Theme.Text.body)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        Spacer(minLength: 0)

                                        Button {
                                            deleteTaskSet(set.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("")
                                        .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showDefaultTaskSetSheet = false
                            }
                            .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .appBackground()
                }
            }
            .alert("Save task set", isPresented: $showSaveCurrentTaskSetPrompt) {
                TextField("Task set name", text: $draftTaskSetName)
                Button("Save") {
                    commitSaveCurrentItemsAsTaskSet()
                }
                Button("Cancel", role: .cancel) {
                    if let selectedTaskSet {
                        draftTaskSetName = selectedTaskSet.name
                    } else {
                        draftTaskSetName = ""
                    }
                }
            } message: {
                Text("Save the current list as a reusable task set.")
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

        savedTaskSets = loadSavedTaskSets()

        if let rawDefaultID = defaults.string(forKey: defaultTaskSetIDKey),
           let uuid = UUID(uuidString: rawDefaultID),
           savedTaskSets.contains(where: { $0.id == uuid }) {
            selectedTaskSetID = uuid
        } else {
            selectedTaskSetID = nil
        }

        if let selectedTaskSet {
            items = selectedTaskSet.items
            draftTaskSetName = selectedTaskSet.name
        } else if let arr = defaults.array(forKey: tasksKey) as? [String] {
            items = arr
            draftTaskSetName = ""
        } else if let legacyArr = defaults.array(forKey: legacyTasksKey) as? [String] {
            items = legacyArr
            draftTaskSetName = ""
        } else {
            items = []
            draftTaskSetName = ""
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
        if let selectedID = selectedTaskSetID,
           let index = savedTaskSets.firstIndex(where: { $0.id == selectedID }) {
            savedTaskSets[index].items = items
            saveSavedTaskSets()
        }
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

    private func loadSavedTaskSets() -> [SavedTaskSet] {
        let defaults = UserDefaults.standard
        var merged: [SavedTaskSet] = []
        var seenIDs = Set<UUID>()
        var seenContentSignatures = Set<String>()

        func merge(_ sets: [SavedTaskSet]) {
            for set in sets {
                let trimmedName = set.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedItems = set.items
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let contentSignature = trimmedName.lowercased() + "||" + normalizedItems.joined(separator: "\u{241E}").lowercased()

                if seenIDs.contains(set.id) || seenContentSignatures.contains(contentSignature) {
                    continue
                }

                seenIDs.insert(set.id)
                seenContentSignatures.insert(contentSignature)
                merged.append(SavedTaskSet(id: set.id, name: trimmedName.isEmpty ? defaultImportedTaskSetName(from: normalizedItems) : trimmedName, items: normalizedItems))
            }
        }

        if let data = defaults.data(forKey: globalTaskSetsKey),
           let decoded = try? JSONDecoder().decode([SavedTaskSet].self, from: data) {
            merge(decoded)
        }

        let legacyKeys = legacyTaskSetKeysForMigration()
        for key in legacyKeys {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([SavedTaskSet].self, from: data) else { continue }
            merge(decoded)
        }

        if let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: globalTaskSetsKey)
        }

        return merged
    }

    private func saveSavedTaskSets() {
        if let data = try? JSONEncoder().encode(savedTaskSets) {
            UserDefaults.standard.set(data, forKey: globalTaskSetsKey)
        }
    }

    private func legacyTaskSetKeysForMigration() -> [String] {
        var keys = Set<String>()

        let activityRefs = allActivityRefs
        let instrumentSuffixes: [String]
        if shouldShowInstrumentSelector {
            let ids = instrumentsForProfile.compactMap(\.id)
            instrumentSuffixes = ids.isEmpty ? [""] : ids.map { "::inst:" + $0.uuidString }
        } else {
            instrumentSuffixes = [""]
        }

        for activityRef in activityRefs {
            let normalizedRef = normalizedActivityRef(activityRef)
            for instrumentSuffix in instrumentSuffixes {
                let scopedTasksKey = "practiceTasks_v1::" + ownerScope + "::" + normalizedRef + instrumentSuffix
                keys.insert(scopedTasksKey + "::saved_sets_v1")
            }
        }

        keys.insert(taskSetsKey)
        return Array(keys)
    }

    private func selectTaskSet(_ id: UUID) {
        guard let set = savedTaskSets.first(where: { $0.id == id }) else { return }
        selectedTaskSetID = set.id
        draftTaskSetName = set.name
        items = set.items
        saveTaskSetSelectionAndItems()
    }

    private func saveTaskSetSelectionAndItems() {
        let defaults = UserDefaults.standard
        if let selectedTaskSet {
            defaults.set(selectedTaskSet.id.uuidString, forKey: defaultTaskSetIDKey)
            defaults.set(selectedTaskSet.items, forKey: tasksKey)
            items = selectedTaskSet.items
        } else {
            defaults.removeObject(forKey: defaultTaskSetIDKey)
            defaults.set(items, forKey: tasksKey)
        }
    }

    private func commitTaskSetNameIfNeeded() {
        guard let selectedID = selectedTaskSetID,
              let index = savedTaskSets.firstIndex(where: { $0.id == selectedID }) else { return }
        let trimmed = draftTaskSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard savedTaskSets[index].name != trimmed else { return }
        savedTaskSets[index].name = trimmed
        saveSavedTaskSets()
        saveTaskSetSelectionAndItems()
    }

    private func saveCurrentItemsAsTaskSet() {
        draftTaskSetName = defaultImportedTaskSetName(from: items)
        showSaveCurrentTaskSetPrompt = true
    }

    private func commitSaveCurrentItemsAsTaskSet() {
        let trimmedName = draftTaskSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? defaultImportedTaskSetName(from: items) : trimmedName
        let finalName = uniqueTaskSetName(from: baseName)
        let newSet = SavedTaskSet(id: UUID(), name: finalName, items: items)
        savedTaskSets.append(newSet)
        saveSavedTaskSets()
        selectTaskSet(newSet.id)
        showSaveCurrentTaskSetPrompt = false
    }

    private func saveImportedTaskSetFromDraft() {
        syncImportDraftItemsFromLines()
        let cleanedItems = importDraftItems
        guard !cleanedItems.isEmpty else { return }

        let trimmedName = importDraftTaskSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? defaultImportedTaskSetName(from: cleanedItems) : trimmedName
        let finalName = uniqueTaskSetName(from: baseName)
        let newSet = SavedTaskSet(id: UUID(), name: finalName, items: cleanedItems)
        savedTaskSets.append(newSet)
        saveSavedTaskSets()
        selectTaskSet(newSet.id)
        pastedImportText = ""
        importDraftItems = []
        importDraftLines = []
        importDraftTaskSetName = ""
        showTaskImportPasteSheet = false
    }

    @ViewBuilder
    private func importedTaskDraftRow(_ line: Binding<EditableImportedTaskLine>) -> some View {
        HStack(spacing: 6) {
            TextField("Task", text: line.text)
                .textFieldStyle(.plain)
                .font(Theme.Text.body)
                .disableAutocorrection(true)
                .focused($focusedImportLineID, equals: line.wrappedValue.id)
                .onChange(of: line.wrappedValue.text) { _, _ in
                    syncImportDraftItemsFromLines()
                }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
                    .onDrag {
                        dismissImportedTaskKeyboard()
                        draggedImportLineID = line.wrappedValue.id
                        return NSItemProvider(object: NSString(string: line.wrappedValue.id.uuidString))
                    }
                    .accessibilityLabel("Reorder task")

                Button(role: .destructive) {
                    importDraftLines.removeAll { $0.id == line.wrappedValue.id }
                    syncImportDraftItemsFromLines()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                        .frame(width: 20, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func handleImportedRawTextChanged(oldValue: String, newValue: String) {
        guard suppressImportedRawTextObserver == false else { return }
        guard newValue.contains("\n") else { return }

        let isLikelyPaste = abs(newValue.count - oldValue.count) > 1

        let committedText: String
        let remainingText: String

        if isLikelyPaste {
            committedText = newValue
            remainingText = ""
        } else if newValue.hasSuffix("\n") {
            committedText = newValue
            remainingText = ""
        } else {
            var components = newValue.components(separatedBy: .newlines)
            remainingText = components.popLast() ?? ""
            committedText = components.joined(separator: "\n")
        }

        let parsed = Self.parseImportedTaskLines(from: committedText)
        guard !parsed.isEmpty else { return }

        importDraftLines.append(contentsOf: parsed.map { EditableImportedTaskLine(text: $0) })
        syncImportDraftItemsFromLines()

        if importDraftTaskSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importDraftTaskSetName == defaultImportedTaskSetName(from: importDraftItems) {
            importDraftTaskSetName = defaultImportedTaskSetName(from: importDraftItems)
        }

        suppressImportedRawTextObserver = true
        pastedImportText = remainingText
        suppressImportedRawTextObserver = false

        dismissImportedTaskKeyboard()
    }

    private func syncImportDraftItemsFromLines() {
        importDraftItems = importDraftLines
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func dismissImportedTaskKeyboard() {
        focusedImportLineID = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func deleteTaskSet(_ id: UUID) {
        guard let index = savedTaskSets.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = (selectedTaskSetID == id)
        savedTaskSets.remove(at: index)
        saveSavedTaskSets()

        if wasSelected {
            selectedTaskSetID = nil
            draftTaskSetName = ""
            saveTaskSetSelectionAndItems()
        }
    }

    private func uniqueTaskSetName(from baseName: String) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? defaultImportedTaskSetName(from: items) : trimmed
        let existingNames = Set(savedTaskSets.map { $0.name.lowercased() })

        if !existingNames.contains(seed.lowercased()) {
            return seed
        }

        var counter = 2
        while true {
            let candidate = "\(seed) (\(counter))"
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
            counter += 1
        }
    }

    private func defaultImportedTaskSetName(from lines: [String]) -> String {
        if let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: Date())
    }

    static func parseImportedTaskLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*(?:[-•*]|\d+[\.)])\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}


private struct TasksManagerImportLauncherSheet: View {
    let onCancel: () -> Void
    let onPasteOrType: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .font(Theme.Text.body.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
                .buttonStyle(.plain)

                Spacer()

                Spacer()

                Color.clear
                    .frame(width: 92, height: 56)
            }

            Text("Import tasks")
                .sectionHeader()
                .padding(.horizontal, 16)
                .padding(.bottom, 18)

            VStack(spacing: 12) {
                Button(action: onPasteOrType) {
                    Text("Paste or type")
                        .font(Theme.Text.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onScan) {
                    Text("Scan")
                        .font(Theme.Text.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .cardSurface()
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .appBackground()
    }
}


#if canImport(VisionKit) && canImport(UIKit)
private struct TasksManagerImportScanSheet: UIViewControllerRepresentable {
    let onRecognizedText: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognizedText: onRecognizedText)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onRecognizedText: (String) -> Void

        init(onRecognizedText: @escaping (String) -> Void) {
            self.onRecognizedText = onRecognizedText
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let group = DispatchGroup()
            var pageTexts: [String] = Array(repeating: "", count: scan.pageCount)

            for index in 0..<scan.pageCount {
                group.enter()
                let image = scan.imageOfPage(at: index)
                recognizeText(in: image) { text in
                    pageTexts[index] = text
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let joined = pageTexts.filter { !$0.isEmpty }.joined(separator: "\n")
                controller.dismiss(animated: true) {
                    self.onRecognizedText(joined)
                }
            }
        }

        private func recognizeText(in image: UIImage, completion: @escaping (String) -> Void) {
            guard let cgImage = image.cgImage else {
                completion("")
                return
            }

            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                completion(lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        }
    }
}
#else
private struct TasksManagerImportScanSheet: View {
    let onRecognizedText: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Scanning is not available on this device.")
                        .font(Theme.Text.body)
                }
            }
            .navigationTitle("")
                        .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onRecognizedText("")
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            .appBackground()
        }
    }
}
#endif

