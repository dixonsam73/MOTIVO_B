///
//  SessionDetailView.swift
//  MOTIVO
//
//  Shows image thumbnails (with ★ for the chosen thumbnail) and keeps non-image files as rows.
//  Tap any item to Quick Look.
//

import SwiftUI
import CoreData
import UIKit

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let session: Session

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    // Quick Look
    @State private var previewURL: URL? = nil
    @State private var isShowingPreview = false

    // Layout
    private let grid = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        List {
            // Header / meta
            Section {
                DetailRow(label: "Instrument", value: session.instrument?.name ?? "—")
                DetailRow(label: "Duration", value: formattedDuration(Int(session.durationSeconds)))
                DetailRow(label: "When", value: formattedDate(session.timestamp ?? Date()))
                DetailRow(label: "Privacy", value: session.isPublic ? "Public" : "Private")
            }

            // Notes
            if let notes = session.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).font(.body)
                }
            }

            // Attachments
            Section("Attachments") {
                let (images, others) = splitAttachments()
                if images.isEmpty && others.isEmpty {
                    Text("No attachments").foregroundStyle(.secondary)
                } else {
                    if !images.isEmpty {
                        LazyVGrid(columns: grid, spacing: 12) {
                            ForEach(images, id: \.objectID) { a in
                                ThumbCell(
                                    image: loadImage(a),
                                    isStarred: (a.value(forKey: "isThumbnail") as? Bool) == true
                                )
                                .onTapGesture { openQuickLook(a) }
                                .contextMenu {
                                    Button("Open") { openQuickLook(a) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(others, id: \.objectID) { a in
                        AttachmentRow(attachment: a) { openQuickLook(a) }
                    }
                }
            }
        }
        .navigationTitle("Session")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showEdit = true }
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Text("Delete") }
                } label: { Text("Edit") }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditSessionView(isPresented: $showEdit, session: session)
        }
        .sheet(isPresented: $isShowingPreview) {
            if let url = previewURL {
                QuickLookPreview(url: url)
            }
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private func splitAttachments() -> ([Attachment], [Attachment]) {
        let set = (session.attachments as? Set<Attachment>) ?? []
        let sorted = set.sorted { (a, b) in
            let da = (a.value(forKey: "createdAt") as? Date) ?? .distantPast
            let db = (b.value(forKey: "createdAt") as? Date) ?? .distantPast
            return da < db
        }
        let images = sorted.filter { ($0.kind ?? "") == "image" }
        let others = sorted.filter { ($0.kind ?? "") != "image" }
        return (images, others)
    }

    private func openQuickLook(_ a: Attachment) {
        guard let url = urlFromAttachment(a) else { return }
        previewURL = url
        isShowingPreview = true
    }

    private func loadImage(_ a: Attachment) -> UIImage? {
        guard let url = urlFromAttachment(a) else { return nil }
        if let data = try? Data(contentsOf: url) { return UIImage(data: data) }
        return UIImage(contentsOfFile: url.path)
    }

    // ✅ Path-resilient URL resolution used by both thumbnails and Quick Look
    private func urlFromAttachment(_ a: Attachment) -> URL? {
        guard let s = a.fileURL, !s.isEmpty else { return nil }
        let fm = FileManager.default

        if let u = URL(string: s), u.isFileURL, fm.fileExists(atPath: u.path) {
            return u
        }
        if fm.fileExists(atPath: s) {
            return URL(fileURLWithPath: s)
        }
        let filename = URL(fileURLWithPath: s).lastPathComponent
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent(filename, isDirectory: false)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func deleteSession() {
        viewContext.delete(session)
        do {
            try viewContext.save()
        } catch {
            print("Delete error: \(error)")
        }
        dismiss()
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Subviews

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

fileprivate struct AttachmentRow: View {
    let attachment: Attachment
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack {
                Image(systemName: icon(for: attachment.kind ?? "file"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName(of: attachment)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text((attachment.kind ?? "file")).font(.footnote)
                        if (attachment.value(forKey: "isThumbnail") as? Bool) == true {
                            Text("★").font(.footnote)
                        }
                    }.foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
    private func icon(for kind: String) -> String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "image": return "photo"
        default: return "doc"
        }
    }
    private func fileName(of a: Attachment) -> String {
        guard let path = a.fileURL, !path.isEmpty else { return "file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

fileprivate struct ThumbCell: View {
    let image: UIImage?
    let isStarred: Bool
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let ui = image {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.secondary.opacity(0.15), lineWidth: 1)
            )

            if isStarred {
                Text("★")
                    .font(.system(size: 16))
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(4)
                    .accessibilityLabel("Thumbnail")
            }
        }
    }
}
