// CHANGE-ID: 20260604_121750_TaskManagerDefaultListUI
// SCOPE: Main Task Manager default-list UI refinement only — remove separate auto-fill toggle, reframe selector header as "Default Task List When:", replace Assigned status with Default control, and replace chevron editor affordance with explicit Edit button. Preserve Task Set Editor, reorder, import, storage model, and task editing behaviour.
// SEARCH-TOKEN: 20260604_121750_TaskManagerDefaultListUI

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

    @State private var selectedActivityRef: String = "core:0"
    @State private var items: [TaskTemplateLine] = []
    @State private var newItemText: String = ""
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
    @State private var importDraftItems: [TaskTemplateLine] = []
    @State private var importDraftTaskSetName: String = ""
    @State private var importDraftLines: [EditableImportedTaskLine] = []
    @State private var draggedImportLineID: UUID? = nil
    @State private var suppressImportedRawTextObserver: Bool = false
    @FocusState private var focusedImportLineID: UUID?
    @FocusState private var focusedManagerLineID: UUID?
    @State private var ignoreNextManagerTapLineID: UUID? = nil
    @State private var showTaskSetEditor: Bool = false
    @State private var editingTaskSetID: UUID? = nil
    @State private var newEditorItemText: String = ""
    @FocusState private var focusedEditorLineID: UUID?

    private let managerDeleteIconWidth: CGFloat = 20
    private let managerDragDeleteSpacing: CGFloat = 16
    private let managerContextTextLeadingInset: CGFloat = 6

    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    )
    private var instruments: FetchedResults<Instrument>

    @FetchRequest(entity: Profile.entity(), sortDescriptors: [])
    private var profiles: FetchedResults<Profile>

    @State private var selectedInstrumentID: UUID? = nil

    fileprivate enum TaskLineType: String, Codable {
        case task
        case context
    }

    fileprivate struct TaskTemplateLine: Codable, Identifiable, Equatable {
        let id: UUID
        var text: String
        var type: TaskLineType

        init(id: UUID = UUID(), text: String, type: TaskLineType = .task) {
            self.id = id
            self.text = text
            self.type = type
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case text
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            text = try container.decode(String.self, forKey: .text)
            type = try container.decodeIfPresent(TaskLineType.self, forKey: .type) ?? .task
        }
    }

    fileprivate struct SavedTaskSet: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var items: [TaskTemplateLine]
    }

    fileprivate struct LegacySavedTaskSet: Codable {
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
    private var autofillCompatibilityKey: String { "practiceTasks_autofill_enabled::" + ownerScope + "::" + currentNormalizedActivityRef + currentInstrumentKeySuffix }
    private var legacyAutofillCompatibilityKey: String { "practiceTasks_autofill_enabled::" + ownerScope }
    private var taskSetsKey: String { tasksKey + "::saved_sets_v1" }
    private var globalTaskSetsKey: String { "practiceTasks_saved_sets_v2::" + ownerScope }
    private var defaultTaskSetIDKey: String { tasksKey + "::default_set_id_v1" }

    private var legacyTasksKey: String { "practiceTasks_v1::" + ownerScope }

    private func normalizedTaskTemplateLines(from strings: [String]) -> [TaskTemplateLine] {
        strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { TaskTemplateLine(text: $0, type: .task) }
    }

    private func normalizedTaskTemplateLines(from typedLines: [TaskTemplateLine]) -> [TaskTemplateLine] {
        typedLines
            .map {
                TaskTemplateLine(
                    id: $0.id,
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    type: $0.type
                )
            }
            .filter { !$0.text.isEmpty }
    }

    private func textItems(from typedLines: [TaskTemplateLine]) -> [String] {
        normalizedTaskTemplateLines(from: typedLines).map(\.text)
    }

    private func loadTypedTaskTemplateLines(forKey key: String, defaults: UserDefaults) -> [TaskTemplateLine]? {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TaskTemplateLine].self, from: data) {
            let normalized = normalizedTaskTemplateLines(from: decoded)
            return normalized.isEmpty ? [] : normalized
        }

        if let arr = defaults.array(forKey: key) as? [String] {
            return normalizedTaskTemplateLines(from: arr)
        }

        return nil
    }

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

    private func managerLineTextBinding(for lineID: UUID) -> Binding<String> {
        Binding(
            get: {
                items.first(where: { $0.id == lineID })?.text ?? ""
            },
            set: { newValue in
                guard let index = items.firstIndex(where: { $0.id == lineID }) else { return }
                items[index].text = newValue
                saveItems()
            }
        )
    }

    private func toggleManagerLineType(_ lineID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == lineID }) else { return }
        items[index].type = (items[index].type == .task) ? .context : .task
        saveItems()

        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        #endif
    }



    @ViewBuilder
    private func managerTaskRow(for line: TaskTemplateLine) -> some View {
        HStack(spacing: 6) {
            managerTaskTextArea(for: line)

            Spacer(minLength: 8)

            HStack(spacing: managerDragDeleteSpacing) {
                Button(role: .destructive) {
                    deleteManagerLine(line.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                        .frame(width: managerDeleteIconWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: managerDeleteIconWidth, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func managerTaskTextArea(for line: TaskTemplateLine) -> some View {
        TextField(
            line.type == .context ? "Context" : "Task",
            text: managerLineTextBinding(for: line.id)
        )
        .textFieldStyle(.plain)
        .font(line.type == .context ? Theme.Text.body.weight(.medium) : Theme.Text.body)
        .disableAutocorrection(true)
        .textInputAutocapitalization(.sentences)
        .focused($focusedManagerLineID, equals: line.id)
        .onTapGesture {
            if ignoreNextManagerTapLineID == line.id {
                ignoreNextManagerTapLineID = nil
                focusedManagerLineID = nil
                return
            }
            focusedManagerLineID = line.id
        }
        .padding(.leading, line.type == .context ? managerContextTextLeadingInset : 0)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    ignoreNextManagerTapLineID = line.id
                    dismissManagerKeyboard()
                    toggleManagerLineType(line.id)
                }
        )
    }


    private var editingTaskSet: SavedTaskSet? {
        guard let editingTaskSetID else { return nil }
        return savedTaskSets.first(where: { $0.id == editingTaskSetID })
    }

    private func taskSetNameBinding(for setID: UUID) -> Binding<String> {
        Binding(
            get: {
                savedTaskSets.first(where: { $0.id == setID })?.name ?? ""
            },
            set: { newValue in
                guard let index = savedTaskSets.firstIndex(where: { $0.id == setID }) else { return }
                savedTaskSets[index].name = newValue
                saveSavedTaskSets()
                if selectedTaskSetID == setID {
                    draftTaskSetName = newValue
                    saveTaskSetSelectionAndItems()
                }
            }
        )
    }

    private func editorLineTextBinding(setID: UUID, lineID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let setIndex = savedTaskSets.firstIndex(where: { $0.id == setID }),
                      let lineIndex = savedTaskSets[setIndex].items.firstIndex(where: { $0.id == lineID })
                else { return "" }
                return savedTaskSets[setIndex].items[lineIndex].text
            },
            set: { newValue in
                guard let setIndex = savedTaskSets.firstIndex(where: { $0.id == setID }),
                      let lineIndex = savedTaskSets[setIndex].items.firstIndex(where: { $0.id == lineID })
                else { return }
                savedTaskSets[setIndex].items[lineIndex].text = newValue
                persistEditedTaskSet(setID)
            }
        )
    }

    private func persistEditedTaskSet(_ setID: UUID) {
        saveSavedTaskSets()
        if selectedTaskSetID == setID {
            saveTaskSetSelectionAndItems()
        }
    }

    private func openTaskSetEditor(_ setID: UUID) {
        editingTaskSetID = setID
        newEditorItemText = ""
        showTaskSetEditor = true
    }

    private func addEmptyEditorLine(to setID: UUID) {
        guard let index = savedTaskSets.firstIndex(where: { $0.id == setID }) else { return }
        let newLine = TaskTemplateLine(text: "", type: .task)
        savedTaskSets[index].items.append(newLine)
        persistEditedTaskSet(setID)

        DispatchQueue.main.async {
            focusedEditorLineID = newLine.id
        }
    }

    private func toggleEditorLineType(setID: UUID, lineID: UUID) {
        guard let setIndex = savedTaskSets.firstIndex(where: { $0.id == setID }),
              let lineIndex = savedTaskSets[setIndex].items.firstIndex(where: { $0.id == lineID })
        else { return }
        savedTaskSets[setIndex].items[lineIndex].type = (savedTaskSets[setIndex].items[lineIndex].type == .task) ? .context : .task
        persistEditedTaskSet(setID)

        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        #endif
    }

    private func deleteEditorLine(setID: UUID, lineID: UUID) {
        guard let setIndex = savedTaskSets.firstIndex(where: { $0.id == setID }) else { return }
        savedTaskSets[setIndex].items.removeAll { $0.id == lineID }
        persistEditedTaskSet(setID)
    }

    private func moveEditorLines(setID: UUID, from source: IndexSet, to destination: Int) {
        guard let setIndex = savedTaskSets.firstIndex(where: { $0.id == setID }) else { return }
        savedTaskSets[setIndex].items.move(fromOffsets: source, toOffset: destination)
        persistEditedTaskSet(setID)
    }

    private func duplicateTaskSet(_ setID: UUID) {
        guard let set = savedTaskSets.first(where: { $0.id == setID }) else { return }
        let duplicate = SavedTaskSet(
            id: UUID(),
            name: uniqueTaskSetName(from: set.name),
            items: normalizedTaskTemplateLines(from: set.items)
        )
        savedTaskSets.append(duplicate)
        saveSavedTaskSets()
    }

    @ViewBuilder
    private func defaultPill(isSelected: Bool) -> some View {
        Text("Default")
            .font(Theme.Text.meta.weight(.semibold))
            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Colors.accent.opacity(0.18) : Theme.Colors.secondaryText.opacity(0.20),
                        lineWidth: 1
                    )
            )
    }

    @ViewBuilder
    private func taskSetLibraryRow(_ set: SavedTaskSet) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleDefaultTaskSet(set.id)
            } label: {
                Text(set.name)
                    .font(Theme.Text.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if selectedTaskSetID == set.id {
                Button {
                    toggleDefaultTaskSet(set.id)
                } label: {
                    defaultPill(isSelected: true)
                }
                .buttonStyle(.plain)
            }

            Button {
                openTaskSetEditor(set.id)
            } label: {
                Text("Edit")
                    .font(Theme.Text.meta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func editorTaskRow(setID: UUID, line: TaskTemplateLine) -> some View {
        HStack(spacing: 6) {
            TextField(
                line.type == .context ? "Context" : "Task",
                text: editorLineTextBinding(setID: setID, lineID: line.id)
            )
            .textFieldStyle(.plain)
            .font(line.type == .context ? Theme.Text.body.weight(.medium) : Theme.Text.body)
            .disableAutocorrection(true)
            .textInputAutocapitalization(.sentences)
            .focused($focusedEditorLineID, equals: line.id)
            .padding(.leading, line.type == .context ? managerContextTextLeadingInset : 0)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        focusedEditorLineID = nil
                        toggleEditorLineType(setID: setID, lineID: line.id)
                    }
            )

            Spacer(minLength: 8)

            HStack(spacing: managerDragDeleteSpacing) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                    .frame(width: managerDeleteIconWidth, height: 28)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Reorder task")

                Button(role: .destructive) {
                    deleteEditorLine(setID: setID, lineID: line.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                        .frame(width: managerDeleteIconWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: managerDeleteIconWidth + managerDragDeleteSpacing, alignment: .trailing)
        }
        .frame(minHeight: 36)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var taskSetEditorView: some View {
        if let set = editingTaskSet {
            Form {
                Section(header: Text("Task Set").sectionHeader()) {
                    TextField("Task set name", text: taskSetNameBinding(for: set.id))
                        .font(Theme.Text.body)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }

                Section(header: Text("Tasks").sectionHeader()) {
                    ForEach(set.items) { line in
                        editorTaskRow(setID: set.id, line: line)
                    }
                    .onMove { source, destination in
                        focusedEditorLineID = nil
                        moveEditorLines(setID: set.id, from: source, to: destination)
                    }

                    Button {
                        addEmptyEditorLine(to: set.id)
                    } label: {
                        HStack(spacing: 4) {
                            Text("+")
                            Text("Add line")
                        }
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.accent.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("")
            .safeAreaInset(edge: .bottom) {
                Button {
                    deleteTaskSet(set.id)
                    showTaskSetEditor = false
                    editingTaskSetID = nil
                } label: {
                    Label("Delete Task Set", systemImage: "trash")
                        .font(Theme.Text.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(Theme.Colors.accent.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
            }
         
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var selectorSectionContent: some View {
        VStack(spacing: 0) {
            if shouldShowInstrumentSelector {
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
                    selectorRowLabel(
                        title: "Instrument",
                        value: instrumentDisplayName(for: selectedInstrumentID)
                    )
                }
                .buttonStyle(.plain)

                Divider()
            }

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
                selectorRowLabel(
                    title: "Activity",
                    value: activityDisplayName(for: selectedActivityRef)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func selectorRowLabel(title: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Text.body)
                .foregroundStyle(Theme.Colors.secondaryText)

            Spacer(minLength: Theme.Spacing.m)

            Text(value)
                .font(Theme.Text.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.8))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Default Task Set When:").sectionHeader()) {
                    selectorSectionContent
                }

                if hasSavedTaskSets {
                    Section(header:
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Task Sets").sectionHeader()
                                Text("Tap a task set to make it the default.")
                                    .font(Theme.Text.meta)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        ) {
                        ForEach(savedTaskSets) { set in
                            taskSetLibraryRow(set)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
            .navigationDestination(isPresented: $showTaskSetEditor) {
                taskSetEditorView
            }
            .onAppear {
                selectedActivityRef = normalizedActivityRef(activityRef)
                loadUserActivities()
                if shouldShowInstrumentSelector, selectedInstrumentID == nil {
                    selectedInstrumentID = instrumentsForProfile.first?.id
                }
                loadAll()
            }
            .onChange(of: selectedActivityRef) { loadAll() }
            .onChange(of: selectedInstrumentID) { loadAll() }
            .appBackground()
        }
    }

    private var taskImportPasteSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    importPasteHeader
                    importDraftEditorCard
                    importTaskSetNameSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                dismissImportedTaskKeyboard()
            }
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

    private var importPasteHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Add tasks")
                .sectionHeader()

            Spacer()

            Button(action: pasteImportedTasksFromClipboard) {
                Text("Paste")
                    .font(Theme.Text.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(importPasteButtonBackground)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importPasteButtonBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
    }

    private var importDraftEditorCard: some View {
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
    }

    private var importTaskSetNameSection: some View {
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

    private var defaultTaskSetSheet: some View {
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
                            defaultTaskSetRow(set)
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

    private func defaultTaskSetRow(_ set: SavedTaskSet) -> some View {
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

    private func pasteImportedTasksFromClipboard() {
        #if canImport(UIKit)
        guard let pasted = UIPasteboard.general.string else { return }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        suppressImportedRawTextObserver = true
        pastedImportText = pasted
        suppressImportedRawTextObserver = false
        handleImportedRawTextChanged(oldValue: "", newValue: pasted)
        #endif
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TaskTemplateLine(text: trimmed, type: .task))
        newItemText = ""
        saveItems()
    }

    private func deleteManagerLine(_ lineID: UUID) {
        items.removeAll { $0.id == lineID }
        saveItems()
    }

    private func syncAutofillCompatibilityFlag() {
        let defaults = UserDefaults.standard
        defaults.set(selectedTaskSetID != nil, forKey: autofillCompatibilityKey)
        defaults.removeObject(forKey: legacyAutofillCompatibilityKey)
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

        syncAutofillCompatibilityFlag()

        if let selectedTaskSet {
            items = normalizedTaskTemplateLines(from: selectedTaskSet.items)
            draftTaskSetName = selectedTaskSet.name
        } else if let typed = loadTypedTaskTemplateLines(forKey: tasksKey, defaults: defaults) {
            items = typed
            draftTaskSetName = ""
        } else if let typedLegacy = loadTypedTaskTemplateLines(forKey: legacyTasksKey, defaults: defaults) {
            items = typedLegacy
            draftTaskSetName = ""
        } else {
            items = []
            draftTaskSetName = ""
        }

    }

    private func saveItems() {
        let normalizedItems = normalizedTaskTemplateLines(from: items)

        if let selectedID = selectedTaskSetID,
           let index = savedTaskSets.firstIndex(where: { $0.id == selectedID }) {
            savedTaskSets[index].items = normalizedItems
            saveSavedTaskSets()
        }

        if let data = try? JSONEncoder().encode(normalizedItems) {
            UserDefaults.standard.set(data, forKey: tasksKey)
        }
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
                let normalizedItems = normalizedTaskTemplateLines(from: set.items)
                let contentSignature = trimmedName.lowercased() + "||" + normalizedItems.map { $0.type.rawValue + ":" + $0.text.lowercased() }.joined(separator: "\u{241E}")

                if seenIDs.contains(set.id) || seenContentSignatures.contains(contentSignature) {
                    continue
                }

                seenIDs.insert(set.id)
                seenContentSignatures.insert(contentSignature)
                merged.append(SavedTaskSet(id: set.id, name: trimmedName.isEmpty ? defaultImportedTaskSetName(from: textItems(from: normalizedItems)) : trimmedName, items: normalizedItems))
            }
        }

        if let data = defaults.data(forKey: globalTaskSetsKey) {
            if let decoded = try? JSONDecoder().decode([SavedTaskSet].self, from: data) {
                merge(decoded)
            } else if let legacyDecoded = try? JSONDecoder().decode([LegacySavedTaskSet].self, from: data) {
                merge(legacyDecoded.map { SavedTaskSet(id: $0.id, name: $0.name, items: normalizedTaskTemplateLines(from: $0.items)) })
            }
        }

        let legacyKeys = legacyTaskSetKeysForMigration()
        for key in legacyKeys {
            guard let data = defaults.data(forKey: key) else { continue }

            if let decoded = try? JSONDecoder().decode([SavedTaskSet].self, from: data) {
                merge(decoded)
                continue
            }

            if let legacyDecoded = try? JSONDecoder().decode([LegacySavedTaskSet].self, from: data) {
                merge(legacyDecoded.map { SavedTaskSet(id: $0.id, name: $0.name, items: normalizedTaskTemplateLines(from: $0.items)) })
            }
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

    private func toggleDefaultTaskSet(_ id: UUID) {
        if selectedTaskSetID == id {
            selectedTaskSetID = nil
            draftTaskSetName = ""
            saveTaskSetSelectionAndItems()
        } else {
            selectTaskSet(id)
        }
    }

    private func selectTaskSet(_ id: UUID) {
        guard let set = savedTaskSets.first(where: { $0.id == id }) else { return }
        selectedTaskSetID = set.id
        draftTaskSetName = set.name
        items = normalizedTaskTemplateLines(from: set.items)
        saveTaskSetSelectionAndItems()
    }

    private func saveTaskSetSelectionAndItems() {
        let defaults = UserDefaults.standard
        if let selectedTaskSet {
            defaults.set(selectedTaskSet.id.uuidString, forKey: defaultTaskSetIDKey)
            let normalizedItems = normalizedTaskTemplateLines(from: selectedTaskSet.items)
            if let data = try? JSONEncoder().encode(normalizedItems) {
                defaults.set(data, forKey: tasksKey)
            }
            items = normalizedItems
        } else {
            defaults.removeObject(forKey: defaultTaskSetIDKey)
            let normalizedItems = normalizedTaskTemplateLines(from: items)
            if let data = try? JSONEncoder().encode(normalizedItems) {
                defaults.set(data, forKey: tasksKey)
            }
        }

        syncAutofillCompatibilityFlag()
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
        draftTaskSetName = defaultImportedTaskSetName(from: textItems(from: items))
        showSaveCurrentTaskSetPrompt = true
    }

    private func commitSaveCurrentItemsAsTaskSet() {
        let trimmedName = draftTaskSetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? defaultImportedTaskSetName(from: textItems(from: items)) : trimmedName
        let finalName = uniqueTaskSetName(from: baseName)
        let newSet = SavedTaskSet(id: UUID(), name: finalName, items: normalizedTaskTemplateLines(from: items))
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
        let baseName = trimmedName.isEmpty ? defaultImportedTaskSetName(from: textItems(from: cleanedItems)) : trimmedName
        let finalName = uniqueTaskSetName(from: baseName)
        let newSet = SavedTaskSet(id: UUID(), name: finalName, items: normalizedTaskTemplateLines(from: cleanedItems))
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

        if importDraftTaskSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importDraftTaskSetName == defaultImportedTaskSetName(from: textItems(from: importDraftItems)) {
            importDraftTaskSetName = defaultImportedTaskSetName(from: textItems(from: importDraftItems))
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
            .map { TaskTemplateLine(text: $0, type: .task) }
    }

    private func dismissImportedTaskKeyboard() {
        focusedImportLineID = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func dismissManagerKeyboard() {
        focusedManagerLineID = nil
        ignoreNextManagerTapLineID = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func moveManagerLines(from source: IndexSet, to destination: Int) {
        dismissManagerKeyboard()
        items.move(fromOffsets: source, toOffset: destination)
        saveItems()
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
        let seed = trimmed.isEmpty ? defaultImportedTaskSetName(from: textItems(from: items)) : trimmed
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Import tasks")
                        .sectionHeader()

                    Text("Bring tasks into this list from paper or text.")
                        .font(Theme.Text.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    VStack(spacing: 12) {
                        importOptionButton(
                            title: "Scan task list",
                            subtitle: "Import from paper or notes",
                            systemImage: "camera",
                            action: onScan
                        )

                        importOptionButton(
                            title: "Paste or type",
                            subtitle: "Enter tasks manually",
                            systemImage: "keyboard",
                            action: onPasteOrType
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .appBackground()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func importOptionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Theme.Text.body)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.m)
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Radius.control,
                    style: .continuous
                )
                .fill(Color.secondary.opacity(0.12))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
