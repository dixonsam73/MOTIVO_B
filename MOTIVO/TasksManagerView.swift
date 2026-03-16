import SwiftUI
import CoreData
#if canImport(UIKit)
import UIKit
#endif

// CHANGE-ID: 20260228_214215_TasksManager_AddButtonKeyboardDismiss
// SCOPE: Dismiss keyboard on return and Add button in Add Task; no other UI/logic changes

/// TasksManagerView
///
/// Manages the default task list that can auto-fill into PracticeTimerView's task pad
/// for a given activity.
///
/// Storage is namespaced per signed-in user; falls back to a device scope when not signed in.
/// Keys (v7.12+):
///  - tasks:   "practiceTasks_v1::<owner>::<activityRef>"
///  - toggle:  "practiceTasks_autofill_enabled::<owner>::<activityRef>"
///
/// Legacy (pre-v7.12) practice-only keys are still read as a fallback for migration:
///  - tasks:   "practiceTasks_v1::<owner>"
///  - toggle:  "practiceTasks_autofill_enabled::<owner>"
struct TasksManagerView: View {
    /// Initial activity reference string (e.g. "core:0" or "custom:Rehearsal") whose defaults we are editing.
    let activityRef: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - State

    /// The activity currently being edited in this sheet. Can be switched by the user.
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

    // MARK: - Init

    init(activityRef: String) {
        self.activityRef = activityRef
        _selectedActivityRef = State(initialValue: activityRef)
    }

    // MARK: - Storage keys

    private var ownerScope: String {
        if let id = PersistenceController.shared.currentUserID,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        return "device"
    }

    /// Normalizes an activity ref string to "core:<raw>" / "custom:<name>" or "core:0" if malformed.
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

    /// Per-activity keys (v7.12+)
    private var tasksKey: String { "practiceTasks_v1::" + ownerScope + "::" + currentNormalizedActivityRef + currentInstrumentKeySuffix }
    private var toggleKey: String { "practiceTasks_autofill_enabled::" + ownerScope + "::" + currentNormalizedActivityRef + currentInstrumentKeySuffix }

    /// Legacy keys (v7.9–v7.11, practice-only)
    private var legacyTasksKey: String { "practiceTasks_v1::" + ownerScope }
    private var legacyToggleKey: String { "practiceTasks_autofill_enabled::" + ownerScope }

    // MARK: - Activity helpers

    /// All activity refs available in the system: core activities + custom UserActivity entries.
    private var allActivityRefs: [String] {
        var result: [String] = []

        // Core activities
        for t in SessionActivityType.allCases {
            let ref = "core:\(t.rawValue)"
            result.append(ref)
        }

        // Custom activities from Core Data
        let customs: [String] = userActivities.compactMap { ua in
            let n = (ua.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "custom:\(n)"
        }
        for c in customs where !result.contains(c) {
            result.append(c)
        }

        // Ensure current selection is present even if unknown
        let normalized = currentNormalizedActivityRef
        if !result.contains(normalized) {
            result.insert(normalized, at: 0)
        }

        return result
    }

    private func activityDisplayName(for ref: String) -> String {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("core:") {
            if let rawPart = trimmed.split(separator: ":").last,
               let rawValue = Int16(rawPart),
               let t = SessionActivityType(rawValue: rawValue) {
                return t.label
            }
            return SessionActivityType.practice.label
        } else if trimmed.hasPrefix("custom:") {
            let name = String(trimmed.dropFirst("custom:".count))
            return name.isEmpty ? "Custom" : name
        }

        return SessionActivityType.practice.label
    }


    // MARK: - Instrument helpers

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
        guard shouldShowInstrumentSelector else { return "" }
        guard let id = selectedInstrumentID else { return "" }
        return "::inst:" + id.uuidString
    }

    private func instrumentDisplayName(for id: UUID?) -> String {
        guard let id else { return "" }
        return instrumentsForProfile.first(where: { $0.id == id })?.name ?? ""
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Activity selector
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


                // Instrument selector (only when user has 2+ instruments)
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

                // Auto-fill toggle
                Section(header: Text("Auto-fill for this activity").sectionHeader()) {
                    Toggle(isOn: $autofillEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("When on, this list fills the Tasks pad when empty.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.Colors.accent)
                    .onChange(of: autofillEnabled) { _ in
                        saveToggle()
                    }
                }

                // Add task
                Section(header: Text("Add Task").sectionHeader()) {
                    HStack {
                        TextField("Add task", text: $newItemText)
                            .font(Theme.Text.body)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit {
                                hideKeyboard()
                            }

                        if !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: addItem) {
                                Text("Add")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                }

                // Existing tasks
                Section(header: Text("Your Tasks").sectionHeader()) {
                    if items.isEmpty {
                        Text("No tasks yet.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .font(Theme.Text.body)
                    } else {
                        ForEach(items.indices, id: \.self) { index in
                            Text(items[index])
                                .font(Theme.Text.body)
                        }
                        .onDelete(perform: delete)
                    }
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
                    .accessibilityLabel("Close tasks manager")
                }
                ToolbarItem(placement: .principal) {
                    Text("Tasks Manager")
                        .font(Theme.Text.pageTitle)
                }
            }
            .onAppear {
                // Normalize initial ref and load data
                selectedActivityRef = normalizedActivityRef(activityRef)
                loadUserActivities()
                // Seed instrument selection only when 2+ instruments exist (keeps UI/behavior identical for 0–1 instrument).
                if shouldShowInstrumentSelector, selectedInstrumentID == nil {
                    selectedInstrumentID = instrumentsForProfile.first?.id
                }
                loadAll()
            }
            .onChange(of: selectedActivityRef) { _ in
                // When user switches activity, reload its defaults
                loadAll()
            }
            .onChange(of: selectedInstrumentID) { _ in
                // When user switches instrument, reload its defaults (only relevant when selector is visible)
                loadAll()
            }
            .appBackground()
        }
    }

    // MARK: - Actions

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newItemText = ""
        saveItems()
    

        // Dismiss keyboard after user commits via Add.
        #if canImport(UIKit)
        hideKeyboard()
        #endif
}


    #if canImport(UIKit)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #else
    private func hideKeyboard() { }
    #endif

    private func deleteItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        saveItems()
    }

    private func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }

    // MARK: - Persistence

    private func loadAll() {
        let defaults = UserDefaults.standard

        // Tasks — prefer per-activity key, fall back to legacy practice-only key for migration.
        if let arr = defaults.array(forKey: tasksKey) as? [String] {
            items = arr
        } else if !shouldShowInstrumentSelector,
                  currentNormalizedActivityRef == "core:0",
                  let legacyArr = defaults.array(forKey: legacyTasksKey) as? [String] {
            items = legacyArr
            // Migrate to the new per-activity slot for the current activity.
            defaults.set(legacyArr, forKey: tasksKey)
        } else {
            items = []
        }

        // Toggle — prefer per-activity key, fall back to legacy key, default ON if missing.
        if defaults.object(forKey: toggleKey) != nil {
            autofillEnabled = defaults.bool(forKey: toggleKey)
        } else if !shouldShowInstrumentSelector,
                  currentNormalizedActivityRef == "core:0",
                  defaults.object(forKey: legacyToggleKey) != nil {
            autofillEnabled = defaults.bool(forKey: legacyToggleKey)
            saveToggle()
        } else {
            autofillEnabled = true // default ON
            saveToggle()
        }
    }

    private func saveItems() {
        let defaults = UserDefaults.standard
        defaults.set(items, forKey: tasksKey)
    }

    private func saveToggle() {
        let defaults = UserDefaults.standard
        defaults.set(autofillEnabled, forKey: toggleKey)
    }

    // MARK: - Data fetch

    private func loadUserActivities() {
        let req: NSFetchRequest<UserActivity> = UserActivity.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
        userActivities = (try? viewContext.fetch(req)) ?? []
    }
}
