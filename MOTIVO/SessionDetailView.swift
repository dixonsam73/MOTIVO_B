////////
//  SessionDetailView.swift
//  MOTIVO
//
//  [ROLLBACK ANCHOR] v7.8 Scope0 — pre-unify (detail view had local label/description logic)
//
//  Scope 0: Route all activity labels/titles/descriptions through SessionActivityHelpers.
//  No behavior changes expected; removes duplicate derivation logic.
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
    @State private var previewURL: URL?
    @State private var isShowingPreview = false

    private let grid = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    // Unified via helpers
    private var headerTitle: String {
        SessionActivity.headerTitle(for: session)
    }
    private var activityDescriptionText: String {
        SessionActivity.description(for: session)
    }

    var body: some View {
        Form {
            // 1) Top card — Activity Description (headline), shown only if non-empty
            if !activityDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Text(activityDescriptionText)
                        .fixedSize(horizontal: false, vertical: true) // allow multiline
                }
            }

            // 2) Second card — Instrument : Activity + Date • Time • Duration
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(headerTitle)
                        Spacer()
                    }
                    Text(metaLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Notes
            if let notes = session.notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") { Text(notes) }
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
                HStack(spacing: 12) {
                    Button("Edit") { showEdit = true }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        // ⬇️ Use fullScreenCover so nothing underneath flashes when we close parent
        .fullScreenCover(isPresented: $showEdit) {
            AddEditSessionView(
                isPresented: $showEdit,
                session: session,
                onSaved: { dismiss() } // pop detail → Feed
            )
        }
        .sheet(isPresented: $isShowingPreview) {
            if let url = previewURL { QuickLookPreview(url: url) }
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Meta line (date • time • duration)

    private var metaLine: String {
        let ts = session.timestamp ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dateStr = dateFormatter.string(from: ts)
        let timeStr = timeFormatter.string(from: ts)
        let durStr = formattedDurationDisplay(Int(session.durationSeconds))

        return "\(dateStr) • \(timeStr) • \(durStr)"
    }

    private func formattedDurationDisplay(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    // MARK: - Attachments split & preview

    private func splitAttachments() -> (images: [Attachment], others: [Attachment]) {
        let set = (session.attachments as? Set<Attachment>) ?? []
        let images = set.filter { ($0.kind ?? "") == "image" }.sorted { (a, b) in
            let da = (a.value(forKey: "createdAt") as? Date) ?? .distantPast
            let db = (b.value(forKey: "createdAt") as? Date) ?? .distantPast
            return da < db
        }
        let others = set.filter { ($0.kind ?? "") != "image" }.sorted { (a, b) in
            let da = (a.value(forKey: "createdAt") as? Date) ?? .distantPast
            let db = (b.value(forKey: "createdAt") as? Date) ?? .distantPast
            return da < db
        }
        return (images, others)
    }

    private func openQuickLook(_ a: Attachment) {
        guard let url = resolveURL(a) else { return }
        previewURL = url
        isShowingPreview = true
    }

    private func resolveURL(_ a: Attachment) -> URL? {
        guard let s = a.fileURL, !s.isEmpty else { return nil }
        let fm = FileManager.default
        if let u = URL(string: s), u.isFileURL, fm.fileExists(atPath: u.path) { return u }
        if fm.fileExists(atPath: s) { return URL(fileURLWithPath: s) }
        let filename = URL(fileURLWithPath: s).lastPathComponent
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent(filename, isDirectory: false)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func loadImage(_ a: Attachment) -> UIImage? {
        guard let url = resolveURL(a) else { return nil }
        if let data = try? Data(contentsOf: url) { return UIImage(data: data) }
        return UIImage(contentsOfFile: url.path)
    }

    private func deleteSession() {
        viewContext.delete(session)
        do { try viewContext.save() } catch { print("Delete error: \(error)") }
        dismiss()
    }
}

// MARK: - Rows

fileprivate struct AttachmentRow: View {
    let attachment: Attachment
    let onTap: () -> Void
    var body: some View {
        HStack {
            Image(systemName: icon(for: attachment.kind ?? "file"))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName(of: attachment)).lineLimit(1)
                HStack(spacing: 12) {
                    Text((attachment.kind ?? "file")).font(.footnote)
                    if (attachment.value(forKey: "isThumbnail") as? Bool) == true {
                        Text("★").font(.footnote)
                    }
                }.foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onTapGesture { onTap() }
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
                if let ui = image { Image(uiImage: ui).resizable().scaledToFill() }
                else { Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary) }
            }
            .frame(width: 84, height: 84)
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

//  [ROLLBACK ANCHOR] v7.8 Scope0 — post-unify (detail view now uses SessionActivity helpers)
