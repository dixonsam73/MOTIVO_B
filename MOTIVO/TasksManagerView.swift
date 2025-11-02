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
    @Environment(\.editMode) private var editMode

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
                    VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                        HStack {
                            TextField("Add task", text: $newItem)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .focused($newItemFocused)
                                .font(Theme.Text.body)
                            Button("Add") { addNew() }
                                .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.vertical, 0)
                    }
                    .cardSurface()
                } header: {
                    Text("Add Task").sectionHeader()
                }

                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                        Toggle(isOn: Binding(get: {
                            autofillEnabled
                        }, set: { v in
                            autofillEnabled = v
                            saveToggle()
                        })) {
                            Text("Auto-fill on Practice")
                                .font(Theme.Text.body)
                        }
                    }
                    .cardSurface()
                } footer: {
                    Text("If enabled, the Practice Timer will pre-populate your Notes/Tasks pad with this list when you open it and it's currently empty.")
                }

                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
                        if items.isEmpty {
                            Text("No tasks yet").foregroundStyle(.secondary)
                                .font(Theme.Text.body)
                        } else {
                            ForEach(items.indices, id: \.self) { idx in
                                TaskRow(
                                    text: Binding(
                                        get: { items[idx] },
                                        set: { items[idx] = $0; saveItems() }
                                    ),
                                    onDelete: { delete(at: IndexSet(integer: idx)) }
                                )
                                .padding(.vertical, Theme.Spacing.inline)
                            }
                            .onMove(perform: move)
                            .onDelete(perform: delete)
                        }
                    }
                    .cardSurface()
                } header: {
                    Text("Your Tasks").sectionHeader()
                }
            }
            .listStyle(.plain)
            .padding(.horizontal, Theme.Spacing.l)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Manage Tasks")
                        .font(Theme.Text.pageTitle)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
            .onAppear { loadAll() }
            .appBackground()
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
        HStack(spacing: Theme.Spacing.inline) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Task", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(Theme.Text.body)
            Spacer(minLength: Theme.Spacing.inline)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete task")
        }
        .padding(.vertical, Theme.Spacing.inline)
    }
}

