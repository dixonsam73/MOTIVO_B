//
//  AddEditSessionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    /// Pass a Session to edit; leave nil to create a new one.
    var existing: Session?

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var durationMinutes: Int = 30
    @State private var when: Date = Date()

    init(existing: Session? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title (e.g. Bass Practice)", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Duration") {
                    Stepper("\(durationMinutes) min", value: $durationMinutes, in: 1...600)
                }

                Section("Timestamp") {
                    DatePicker("When", selection: $when, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle(existing == nil ? "Add Session" : "Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { loadIfEditing() }
        }
    }

    // MARK: - Private

    private func loadIfEditing() {
        guard let s = existing else { return }
        title = s.title ?? ""
        notes = s.notes ?? ""
        // durationSeconds is Int64 (non-optional recommended)
        durationMinutes = max(1, Int(s.durationSeconds) / 60)
        when = s.timestamp ?? Date()
    }

    private func save() {
        let isNew = (existing == nil)
        let session = existing ?? Session(context: moc)
        if isNew { session.id = UUID() }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        session.title = trimmed.isEmpty ? "Untitled" : trimmed
        session.notes = notes
        session.durationSeconds = Int64(durationMinutes * 60)  // Int64, not NSNumber
        session.timestamp = when

        try? moc.save()
        dismiss()
    }
}

#Preview {
    // If your PersistenceController already has `.preview`, use it. Otherwise remove this block.
    let context = PersistenceController.preview.container.viewContext
    return NavigationStack {
        AddEditSessionView()
            .environment(\.managedObjectContext, context)
    }
}
