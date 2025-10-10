////////
//  SessionDetailView.swift
//  MOTIVO
//
//  [ROLLBACK ANCHOR] v7.8 Scope0 — pre-unify (detail view had local label/description logic)
//
//  Scope 0: Route all activity labels/titles/descriptions through SessionActivityHelpers.
//  No behavior changes expected; removes duplicate derivation logic.
//
//  v7.8 Stage 2 — Fix AddEditSessionView initializer call
//  - Replace outdated initializer that passed isPresented / onSaved with current form.
//
import SwiftUI
import CoreData
import UIKit
import Combine

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let session: Session

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var previewURL: URL?
    @State private var isShowingPreview = false
    
    @State private var isShowingAttachmentViewer = false
    @State private var viewerStartIndex = 0

    // Forces view refresh when attachments of this session change
    @State private var _refreshTick: Int = 0

    private let grid = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    // Unified via helpers
    private var headerTitle: String {
        SessionActivity.headerTitle(for: session)
    }
    private var headerLine: String {
        let line = headerTitle
        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return line }
        let instrument = parts[0]
        let activity = parts[1]
        let title = session.title ?? ""
        if title.range(of: activity, options: .caseInsensitive) != nil {
            return String(instrument)
        }
        return line
    }
    private var activityDescriptionText: String {
        SessionActivity.description(for: session)
    }

    var body: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {

            // 1) Top card — Activity Description (headline), shown only if non-empty
            if !activityDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activityDescriptionText)
                        .fixedSize(horizontal: false, vertical: true) // allow multiline
                }
                .cardSurface()
            }

            // 2) Second card — Instrument : Activity + Date • Time • Duration
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    HStack {
                        Text(headerLine)
                            .accessibilitySortPriority(2)
                        Spacer()
                    }
                    Text(metaLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilitySortPriority(1)
                }
                .accessibilityElement(children: .contain)
            }
            .cardSurface()

            // Notes
            if let notes = session.notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Notes").sectionHeader()
                    Text(notes)
                }
                .cardSurface()
            }

            // Attachments
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Attachments").sectionHeader()
                let (images, others) = splitAttachments()
                if images.isEmpty && others.isEmpty {
                    Text("No attachments").foregroundStyle(.secondary)
                } else {
                    if !images.isEmpty {
                        LazyVGrid(columns: grid, spacing: 12) {
                            ForEach(Array(images.enumerated()), id: \.element.objectID) { (idx, a) in
                                ThumbCell(
                                    image: loadImage(a),
                                    isStarred: (a.value(forKey: "isThumbnail") as? Bool) == true
                                )
                                .contentShape(Rectangle())
                                .accessibilityLabel({ let name = (a.value(forKey: "fileURL") as? String).flatMap { URL(fileURLWithPath: $0).lastPathComponent }; return name.map { "Attachment \(idx+1) of \(images.count), \($0)" } ?? "Attachment \(idx+1) of \(images.count)" }())
                                .accessibilityIdentifier("thumb.attachment.\(idx)")
                                .onTapGesture {
                                    viewerStartIndex = idx
                                    isShowingAttachmentViewer = true
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
            .cardSurface()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xl)
    }
    .navigationTitle("Session")
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button("Edit") { showEdit = true }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete session")
                .accessibilityIdentifier("button.deleteSession")
            }
        }
    }
    // ⬇️ Use fullScreenCover so nothing underneath flashes when we close parent
    .fullScreenCover(isPresented: $showEdit) {
        // [v7.8 Stage 2] Updated to match current AddEditSessionView initializer
        AddEditSessionView(session: session)
    }
    .sheet(isPresented: $isShowingPreview) {
        if let url = previewURL { QuickLookPreview(url: url) }
    }
    .fullScreenCover(isPresented: $isShowingAttachmentViewer) {
        // Build URLs from the same source-of-truth order as thumbnails
        let images = splitAttachments().images
        let urls: [URL] = images.compactMap { a in
            // If you have a typed property, prefer it:
            // (a.fileURL as? URL) ?? resolveAttachmentURL(from: a.fileURLString)
            // Otherwise, keep this KVC fallback:
            resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
        }
        AttachmentViewerView(
            imageURLs: urls,
            startIndex: viewerStartIndex,
            onDelete: { url in
                // Attempt to find the matching Attachment in this session by resolving stored fileURL strings
                let set = (session.attachments as? Set<Attachment>) ?? []
                if let match = set.first(where: { att in
                    guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                    return resolveAttachmentURL(from: stored) == url
                }) {
                    viewContext.delete(match)
                    do { try viewContext.save() } catch { print("Attachment delete error: \(error)") }
                } else {
                    print("[AttachmentViewer] No matching attachment found for URL: \(url)")
                }
            }
            , onFavourite: { url in
                // Resolve the Attachment for this url from the session’s attachments (reuse in-memory objects)
                let set = (session.attachments as? Set<Attachment>) ?? []
                if let match = set.first(where: { att in
                    guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                    return resolveAttachmentURL(from: stored) == url
                }) {
                    // Ensure only one favourite
                    for att in set { att.setValue(att == match, forKey: "isThumbnail") }
                    do { try viewContext.save() } catch { print("Favourite save error:", error) }
                } else {
                    print("onFavourite: attachment not found for", url)
                }
            }
            , isFavourite: { url in
                let set = (session.attachments as? Set<Attachment>) ?? []
                if let a = set.first(where: { att in
                    guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                    return resolveAttachmentURL(from: stored) == url
                }) {
                    return (a.value(forKey: "isThumbnail") as? Bool) == true
                }
                return false
            })
    }
    .alert("Delete Session?", isPresented: $showDeleteConfirm) {
        Button("Delete", role: .destructive) { deleteSession() }
        Button("Cancel", role: .cancel) { }
    }
    
    .id(_refreshTick)
    .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
        func touchesThisSession(_ set: Set<NSManagedObject>?) -> Bool {
            guard let set = set else { return false }
            for obj in set {
                if let att = obj as? Attachment, att.session == self.session { return true }
                if let ses = obj as? Session, ses.objectID == self.session.objectID { return true }
            }
            return false
        }
        let updated = note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>
        let inserted = note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>
        let deleted = note.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>
        if touchesThisSession(updated) || touchesThisSession(inserted) || touchesThisSession(deleted) {
            _refreshTick &+= 1
        }
    }
.appBackground()
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

    // Resolves legacy/new stored fileURL strings to actual local file URLs on disk.
    // Handles: file:// URLs, absolute paths, and bare filenames (searching common app dirs).
    private func resolveAttachmentURL(from stored: String?) -> URL? {
        guard let s = stored, !s.isEmpty else { return nil }

        // Case 1: Already a valid file URL string
        if let u = URL(string: s), u.isFileURL {
            return u
        }

        // Case 2: Absolute POSIX path
        if s.hasPrefix("/") {
            let u = URL(fileURLWithPath: s)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }

        // Case 3: Bare filename or relative path → search common app folders
        let filename = URL(fileURLWithPath: s).lastPathComponent
        let fm = FileManager.default

        let candidateDirs: [URL] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fm.urls(for: .libraryDirectory, in: .userDomainMask).first,
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fm.temporaryDirectory
        ].compactMap { $0 }

        for base in candidateDirs {
            let candidate = base.appendingPathComponent(filename)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
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



