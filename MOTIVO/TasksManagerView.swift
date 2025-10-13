// CHANGE-ID: 20251013_140811-tasks-manager-v79B-a1
// SCOPE: New file: TasksManagerView — practice defaults manager with namespaced UserDefaults and auto-fill toggle

import SwiftUI
import CoreData

/// Profile-side manager for default Practice tasks.
/// Storage is namespaced per signed-in user; falls back to a device scope when not signed in.
/// Keys:
///  - tasks:   "practiceTasks_v1::<owner>"
///  - toggle:  "practiceTasks_autofill_enabled::<owner>"
struct TasksManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - User-scoped keys
    private var ownerScope: String {
        if let id = PersistenceController.shared.currentUserID, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        return "device"
    }
    private var tasksKey: String { "practiceTasks_v1::" + ownerScope }
    private var toggleKey: String { "practiceTasks_autofill_enabled::" + ownerScope }

    // MARK: - State
    @State private var items: [String] = []
    @State private var newItem: String = ""
    @State private var autofillEnabled: Bool = true
    @FocusState private var newItemFocused: Bool

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add task", text: $newItem)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .focused($newItemFocused)
                        Button("Add") { addNew() }
                            .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Add Task")
                }

                Section {
                    Toggle(isOn: Binding(get: {
                        autofillEnabled
                    }, set: { v in
                        autofillEnabled = v
                        saveToggle()
                    })) {
                        Text("Auto-fill on Practice")
                    }
                } footer: {
                    Text("If enabled, the Practice Timer will pre-populate your Notes/Tasks pad with this list when you open it and it's currently empty.")
                }

                Section {
                    if items.isEmpty {
                        Text("No tasks yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(items.indices, id: \.self) { idx in
                            TaskRow(
                                text: Binding(
                                    get: { items[idx] },
                                    set: { items[idx] = $0; saveItems() }
                                ),
                                onDelete: { delete(at: IndexSet(integer: idx)) }
                            )
                        }
                        .onMove(perform: move)
                        .onDelete(perform: delete)
                    }
                } header: {
                    Text("Your Tasks")
                }
            }
            .navigationTitle("Manage Tasks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadAll() }
        }
    }

    // MARK: - Actions
    private func addNew() {
        let trimmed = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newItem = ""
        saveItems()
        // keep focus for fast adding
        DispatchQueue.main.async { newItemFocused = true }
    }

    private func move(from offsets: IndexSet, to newOffset: Int) {
        items.move(fromOffsets: offsets, toOffset: newOffset)
        saveItems()
    }

    private func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }

    // MARK: - Persistence
    private func loadAll() {
        let defaults = UserDefaults.standard
        if let arr = defaults.array(forKey: tasksKey) as? [String] {
            items = arr
        } else {
            items = []
        }
        if defaults.object(forKey: toggleKey) == nil {
            autofillEnabled = true // default ON
            saveToggle()
        } else {
            autofillEnabled = defaults.bool(forKey: toggleKey)
        }
    }

    private func saveItems() {
        UserDefaults.standard.set(items, forKey: tasksKey)
    }

    private func saveToggle() {
        UserDefaults.standard.set(autofillEnabled, forKey: toggleKey)
    }
}

private struct TaskRow: View {
    @Binding var text: String
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Task", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Spacer(minLength: 8)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete task")
        }
    }
}
