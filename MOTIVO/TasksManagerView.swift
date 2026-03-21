// CHANGE-ID: 20260321_134500_TasksManager_ImportSavedSets_DefaultSelector
// SCOPE: Add task import (paste/scan), saved task sets, and default-set selector within existing TasksManager system. No Core Data/backend changes.
// SEARCH-TOKEN: 20260321_134500_TasksManager_ImportSavedSets_DefaultSelector

import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif
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
    @State private var showTaskImportSourceDialog: Bool = false
    @State private var showTaskImportPasteSheet: Bool = false
    @State private var showTaskImportScanSheet: Bool = false
    @State private var showSaveCurrentTaskSetPrompt: Bool = false
    @State private var showDefaultTaskSetSheet: Bool = false
    @State private var pastedImportText: String = ""
    @State private var importDraftItems: [String] = []
    @State private var importDraftTaskSetName: String = ""

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
                    Button(action: { showTaskImportSourceDialog = true }) {
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
            }
            .confirmationDialog("Import tasks", isPresented: $showTaskImportSourceDialog, titleVisibility: .visible) {
                Button("Paste or type") {
                    pastedImportText = ""
                    importDraftItems = []
                    importDraftTaskSetName = defaultImportedTaskSetName(from: [])
                    showTaskImportPasteSheet = true
                }
                Button("Scan") {
                    importDraftItems = []
                    importDraftTaskSetName = defaultImportedTaskSetName(from: [])
                    showTaskImportScanSheet = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showTaskImportPasteSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Paste or type").sectionHeader()) {
                            TextEditor(text: $pastedImportText)
                                .font(Theme.Text.body)
                                .frame(minHeight: 140)
                                .onChange(of: pastedImportText) { newValue in
                                    let parsed = Self.parseImportedTaskLines(from: newValue)
                                    importDraftItems = parsed
                                    if importDraftTaskSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importDraftTaskSetName == defaultImportedTaskSetName(from: importDraftItems) {
                                        importDraftTaskSetName = defaultImportedTaskSetName(from: parsed)
                                    }
                                }
                        }

                        Section(header: Text("Task set name").sectionHeader()) {
                            TextField("Task set name", text: $importDraftTaskSetName)
                                .font(Theme.Text.body)
                                .textInputAutocapitalization(.words)
                        }

                        Section(header: Text("Imported Tasks").sectionHeader()) {
                            if importDraftItems.isEmpty {
                                Text("No tasks yet")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            } else {
                                ForEach(importDraftItems.indices, id: \.self) { index in
                                    TextField("Task", text: Binding(
                                        get: { importDraftItems[index] },
                                        set: { importDraftItems[index] = $0 }
                                    ))
                                    .font(Theme.Text.body)
                                }
                                .onDelete { offsets in
                                    importDraftItems.remove(atOffsets: offsets)
                                }
                                .onMove { source, destination in
                                    importDraftItems.move(fromOffsets: source, toOffset: destination)
                                }
                            }
                        }
                    }
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
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

                        ToolbarItem(placement: .topBarTrailing) {
                            if !importDraftItems.isEmpty {
                                EditButton()
                                    .foregroundStyle(Theme.Colors.accent)
                            }
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
                    importDraftTaskSetName = defaultImportedTaskSetName(from: parsed)
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
                    .navigationBarTitleDisplayMode(.inline)
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
        guard let data = UserDefaults.standard.data(forKey: taskSetsKey),
              let decoded = try? JSONDecoder().decode([SavedTaskSet].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveSavedTaskSets() {
        if let data = try? JSONEncoder().encode(savedTaskSets) {
            UserDefaults.standard.set(data, forKey: taskSetsKey)
        }
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
        let cleanedItems = importDraftItems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
        importDraftTaskSetName = ""
        showTaskImportPasteSheet = false
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
            .navigationBarTitleDisplayMode(.inline)
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
