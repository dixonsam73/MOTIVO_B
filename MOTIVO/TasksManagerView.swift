import SwiftUI
import CoreData

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
    private var tasksKey: String { "practiceTasks_v1::" + ownerScope + "::" + currentNormalizedActivityRef }
    private var toggleKey: String { "practiceTasks_autofill_enabled::" + ownerScope + "::" + currentNormalizedActivityRef }

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

                // Auto-fill toggle
                Section(header: Text("Auto-fill for this activity").sectionHeader()) {
                    Toggle(isOn: $autofillEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("When on, the Tasks pad starts with this list whenever it's empty.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                loadAll()
            }
            .onChange(of: selectedActivityRef) { _ in
                // When user switches activity, reload its defaults
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
    }

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
        } else if currentNormalizedActivityRef == "core:0",
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
        } else if currentNormalizedActivityRef == "core:0",
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
