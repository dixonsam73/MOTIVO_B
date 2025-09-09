//
//  PostRecordDetailsView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct PostRecordDetailsView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    // From timer
    let proposedTitle: String
    let startedAt: Date
    let durationSeconds: Int
    let existingNotes: String
    let onSaved: () -> Void   // <-- callback to close parent

    // Editable
    @State private var title: String
    @State private var notes: String
    @State private var mood: Double = 5   // 0...10
    @State private var effort: Double = 5 // 0...10
    @State private var isPublic: Bool = true
    @State private var tagsInput: String = "" // comma-separated

    init(proposedTitle: String, startedAt: Date, durationSeconds: Int, existingNotes: String, onSaved: @escaping () -> Void) {
        self.proposedTitle = proposedTitle
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.existingNotes = existingNotes
        self.onSaved = onSaved
        _title = State(initialValue: proposedTitle)
        _notes = State(initialValue: existingNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    keyValue("When", absoluteTimestamp(startedAt))
                    keyValue("Duration", formatDuration(Int64(durationSeconds)))
                }

                Section("How did it feel?") {
                    sliderRow("Mood", value: $mood)
                    sliderRow("Effort", value: $effort)
                }

                Section("Privacy") {
                    Toggle("Make this session public", isOn: $isPublic)
                }

                Section("Tags") {
                    TextField("Add tags (comma-separated)", text: $tagsInput)
                    Text("Example: scales, tone, repertoire")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextField("What did you work on?", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        let s = Session(context: moc)
        s.id = UUID()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        s.title = t.isEmpty ? proposedTitle : t
        s.notes = notes
        s.durationSeconds = Int64(max(0, durationSeconds))
        s.timestamp = startedAt
        s.isPublic = isPublic
        s.mood = Int16(mood)
        s.effort = Int16(effort)

        // Upsert tags
        let names = tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var tagObjects: [Tag] = []
        for name in names {
            if let tag = fetchTag(named: name) {
                tagObjects.append(tag)
            } else {
                let tag = Tag(context: moc)
                tag.id = UUID()
                tag.name = name
                tagObjects.append(tag)
            }
        }
        s.tags = NSSet(array: tagObjects)

        try? moc.save()

        // Close details and tell the timer to close itself
        onSaved()
    }

    private func fetchTag(named: String) -> Tag? {
        let req: NSFetchRequest<Tag> = Tag.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "name ==[c] %@", named)
        return try? moc.fetch(req).first
    }

    // Helpers
    private func keyValue(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
    private func sliderRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: 0...10, step: 1)
            Text("\(Int(value.wrappedValue))").frame(width: 28, alignment: .trailing)
        }
    }
}

private func absoluteTimestamp(_ date: Date) -> String {
    let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
    return df.string(from: date)
}
private func formatDuration(_ value: Int64) -> String {
    let total = Int(value), h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
