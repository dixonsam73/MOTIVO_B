//
//  SessionDetailView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

private func formatDuration(_ value: Int64?) -> String {
    let total = Int(value ?? 0)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

private func absoluteTimestamp(_ date: Date?) -> String {
    let date = date ?? Date()
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df.string(from: date)
}

private struct KeyValueRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingDeleteAlert = false

    let session: Session

    var body: some View {
        List {
            Section("Details") {
                KeyValueRow(title: "Title",
                            value: ((session.title ?? "").isEmpty ? "Untitled" : (session.title ?? "Untitled")))
                KeyValueRow(title: "Duration",
                            value: formatDuration((session.durationSeconds as Int64?)))
                KeyValueRow(title: "When",
                            value: absoluteTimestamp(session.timestamp))
            }

            if let notes = session.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.body)
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: { Image(systemName: "trash") }
            }
        }
        .alert("Delete this session?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingEdit) {
            AddEditSessionView(existing: session)
                .environment(\.managedObjectContext, moc)
        }
    }

    private func delete() {
        moc.delete(session)
        try? moc.save()
        dismiss()
    }
}

#Preview {
    // Uses the template's preview if present. If not, you can remove this block.
    let context = PersistenceController.preview.container.viewContext
    let s = Session(context: context)
    s.id = UUID()
    s.title = "Sight Reading"
    s.notes = "Etudes 1–3"
    s.durationSeconds = 35 * 60
    s.timestamp = .now
    try? context.save()

    return NavigationStack {
        SessionDetailView(session: s)
            .environment(\.managedObjectContext, context)
    }
}
