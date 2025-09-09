//
//  SessionDetailView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var session: Session
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {
                // SUMMARY
                Section {
                    KeyValueRow(label: "When", value: absoluteTimestamp(session.timestamp))
                    KeyValueRow(label: "Duration", value: formatDuration(session.durationSeconds))
                    HStack {
                        Text("Privacy")
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: session.isPublic ? "globe" : "lock.fill")
                                .imageScale(.small)
                            Text(session.isPublic ? "Public" : "Private")
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(displayTitle)
                } footer: {
                    Text(relativeTimestamp(session.timestamp))
                }

                // FEEL
                Section("How it felt") {
                    MeterRow(name: "Mood",
                             value: Double(clampedInt16(session.mood)),
                             maxValue: 10)
                    MeterRow(name: "Effort",
                             value: Double(clampedInt16(session.effort)),
                             maxValue: 10)
                }

                // TAGS
                if !tagNames.isEmpty {
                    Section("Tags") {
                        TagsGrid(names: tagNames)
                    }
                }

                // NOTES
                Section("Notes") {
                    if let notes = session.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                    } else {
                        Text("No notes")
                            .foregroundStyle(.secondary)
                    }
                }

                // ATTACHMENTS (placeholder)
                Section("Attachments") {
                    Label("Add photo / audio / video (coming soon)", systemImage: "paperclip")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete Session")
                }
            }
            .alert("Delete this session?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { deleteSession() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Derived

    private var displayTitle: String {
        let t = (session.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Practice Session" : t
    }

    private var tagNames: [String] {
        guard let set = session.tags as? Set<Tag> else { return [] }
        return set.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Actions

    private func deleteSession() {
        moc.delete(session)
        try? moc.save()
        dismiss()
    }
}

// MARK: - Small components

private struct KeyValueRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private struct MeterRow: View {
    let name: String
    let value: Double    // current
    let maxValue: Double // maximum

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                Spacer()
                Text("\(Int(value))/\(Int(maxValue))")
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: normalized, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
        .padding(.vertical, 2)
    }

    private var normalized: Double {
        let denom = maxValue > 0 ? maxValue : 1
        return Swift.min(Swift.max(value / denom, 0), 1)
    }
}

private struct TagsGrid: View {
    let names: [String]
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 80), spacing: 8)] }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(names, id: \.self) { tag in
                Text(tag)
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Helpers

private func absoluteTimestamp(_ date: Date?) -> String {
    let d = date ?? Date()
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df.string(from: d)
}
private func relativeTimestamp(_ date: Date?) -> String {
    let d = date ?? Date()
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f.localizedString(for: d, relativeTo: Date())
}

private func formatDuration(_ value: Int64) -> String {
    let total = Int(value)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                 : String(format: "%d:%02d", m, s)
}

private func clampedInt16(_ v: Int16) -> Int {
    // Defensive clamp to 0...10 in case defaults differ
    return Swift.max(0, Swift.min(10, Int(v)))
}
