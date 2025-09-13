//
//  SessionDetailView.swift
//  MOTIVO
//
//  NOTE: This version preserves your previous UI (Edit button, Delete, Quick Look, sections)
//        and ONLY adds a favourite indicator (★) next to attachments where isThumbnail == true.
//

import SwiftUI
import CoreData

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let session: Session

    @State private var showEdit = false
    @State private var previewURL: URL? = nil

    var body: some View {
        List {
            // When & Duration
            Section {
                DetailRow(label: "Date", value: formattedDate(session.timestamp))
                DetailRow(label: "Duration", value: formattedDuration(Int(session.durationSeconds)))
            }

            // Instrument & Privacy
            Section {
                DetailRow(label: "Instrument", value: session.instrument?.name ?? "—")
                DetailRow(label: "Privacy", value: session.isPublic ? "Public" : "Private")
                DetailRow(label: "Mood", value: String(Int(session.mood)))
                DetailRow(label: "Effort", value: String(Int(session.effort)))
            }

            // Tags
            Section("Tags") {
                let names = tagNames()
                if names.isEmpty {
                    Text("No tags").foregroundStyle(.secondary)
                } else {
                    Text(names.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }

            // Notes
            if let notes = session.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.body)
                }
            }

            // Attachments (now shows ★ for favourite)
            Section("Attachments") {
                let atts = attachmentsSorted()
                if atts.isEmpty {
                    Text("No attachments").foregroundStyle(.secondary)
                } else {
                    ForEach(atts, id: \.objectID) { att in
                        Button {
                            if let url = safeFileURL(att.fileURL) {
                                previewURL = url
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "paperclip.circle")
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(attachmentTitle(att))
                                        if (att.value(forKey: "isThumbnail") as? Bool) == true {
                                            Text("★")
                                                .font(.caption)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .accessibilityLabel("Thumbnail")
                                        }
                                    }
                                    if let date = att.createdAt {
                                        Text(shortDate(date))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(displayTitle())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    deleteSession()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditSessionView(
                isPresented: $showEdit,
                session: session,
                onSaved: {
                    // After saving from the sheet, close Detail → return to Feed.
                    dismiss()
                }
            )
            .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL {
                QuickLookPreview(url: url)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Title & Formatting

    private func displayTitle() -> String {
        if let t = session.title, !t.isEmpty { return t }
        if let name = session.instrument?.name, !name.isEmpty { return "\(name) Practice" }
        return "Practice"
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - Tags & Attachments

    private func tagNames() -> [String] {
        let set = (session.tags as? Set<Tag>) ?? []
        let names = set.compactMap { $0.name }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func attachmentsSorted() -> [Attachment] {
        let set = (session.attachments as? Set<Attachment>) ?? []
        return set.sorted { (a, b) in
            let da = a.createdAt ?? .distantPast
            let db = b.createdAt ?? .distantPast
            return da > db
        }
    }

    private func safeFileURL(_ path: String?) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let alt = docs.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: alt.path) {
                return alt
            }
        }
        return nil
    }

    private func attachmentTitle(_ att: Attachment) -> String {
        let name = URL(fileURLWithPath: att.fileURL ?? "").lastPathComponent
        if let kind = att.kind, !kind.isEmpty {
            return "\(kind.capitalized): \(name)"
        } else {
            return name.isEmpty ? "Attachment" : name
        }
    }

    // MARK: - Delete

    private func deleteSession() {
        viewContext.delete(session)
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Delete failed: \(error)")
        }
    }
}

// MARK: - Row component

fileprivate struct DetailRow: View {
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
