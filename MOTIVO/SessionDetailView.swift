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

private let kPrivacyMapKey = "attachmentPrivacyMap_v1" // [String: Bool] keyed by URL.absoluteString or id://<UUID>

private func privacyMap() -> [String: Bool] {
    (UserDefaults.standard.dictionary(forKey: kPrivacyMapKey) as? [String: Bool]) ?? [:]
}

private func privacyKey(id: UUID?, url: URL?) -> String? {
    if let id { return "id://\(id.uuidString)" }
    if let url { return url.absoluteString }
    return nil
}

private func isPrivateAttachment(id: UUID?, url: URL?) -> Bool {
    let map = privacyMap()
    if let id = id {
        let key = "id://\(id.uuidString)"
        if let v = map[key] { return v }
    }
    if let url = url {
        if let v = map[url.absoluteString] { return v }
    }
    return false
}

private func setPrivacy(_ isPrivate: Bool, id: UUID?, url: URL?) {
    var map = privacyMap()
    if let id = id { map["id://\(id.uuidString)"] = isPrivate }
    if let url = url { map[url.absoluteString] = isPrivate }
    UserDefaults.standard.set(map, forKey: kPrivacyMapKey)
}

private func togglePrivacy(id: UUID?, url: URL?) {
    let current = isPrivateAttachment(id: id, url: url)
    setPrivacy(!current, id: id, url: url)
}

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let session: Session

    @State private var showEdit = false
    @State private var editWasPresented: Bool = false
    @State private var showDeleteConfirm = false
    @State private var previewURL: URL?
    @State private var isShowingPreview = false
    
    @State private var isShowingAttachmentViewer = false
    @State private var viewerStartIndex = 0

    @State private var privacyToken: Int = 0

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
            let originalNotes = session.notes ?? ""
            let (focusDotIndex, displayNotes) = extractFocusDotIndex(from: originalNotes)
            if !displayNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Notes").sectionHeader()
                    Text(displayNotes)
                }
                .cardSurface()
            }

            // Read-only State card (only if FocusDotIndex exists)
            if let dot = focusDotIndex {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Focus").sectionHeader()

                    GeometryReader { geo in
                        let totalWidth = geo.size.width
                        let spacing: CGFloat = 8
                        let count = stateDotsCountDetail
                        // compute diameter so dots + spacings fill available width
                        let diameter = max(14, min(32,
                            (totalWidth - spacing * CGFloat(count - 1)) / CGFloat(count)))
                        let ringDot = max(0, min(count - 1, dot))

                        HStack(spacing: spacing) {
                            ForEach(0..<count, id: \.self) { i in
                                let isRinged = (i == ringDot)
                                let baseScale: CGFloat = isRinged ? 1.18 : 1.0
                                Circle()
                                    // Adaptive fill: black in light mode, white in dark mode, using centralized opacity ramp
                                    .fill(FocusDotStyle.fillColor(index: i, total: count, colorScheme: colorScheme))
                                    // Hairline outline on every dot for guaranteed contrast
                                    .overlay(
                                        Circle().stroke(FocusDotStyle.hairlineColor, lineWidth: FocusDotStyle.hairlineWidth)
                                    )
                                    // Adaptive ring for the selected/average index
                                    .overlay(
                                        Group {
                                            if i == ringDot {
                                                Circle().stroke(
                                                    FocusDotStyle.ringColor(for: colorScheme),
                                                    lineWidth: FocusDotStyle.ringWidth
                                                )
                                            }
                                        }
                                    )
                                    .frame(width: diameter, height: diameter)
                                    .scaleEffect(baseScale)                // NEW: persistent emphasis
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 44)
                    .accessibilityLabel({
                        let bucket: String
                        switch (dot / 3) {
                        case 0: bucket = "State: Searching"
                        case 1: bucket = "State: Working"
                        case 2: bucket = "State: Flowing"
                        default: bucket = "State: Breakthrough"
                        }
                        return bucket
                    }())
                }
                .cardSurface()
            }

            // Attachments (only show when present)
            let (images, videos, others) = splitAttachments()
            if !(images.isEmpty && videos.isEmpty && others.isEmpty) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Attachments").sectionHeader()
                    if !images.isEmpty {
                        LazyVGrid(columns: grid, spacing: 12) {
                            ForEach(Array(images.enumerated()), id: \.element.objectID) { (idx, a) in
                                let img = loadImage(a)
                                let starred = (a.value(forKey: "isThumbnail") as? Bool) == true
                                let url = resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
                                ThumbCell(
                                    image: img,
                                    isStarred: starred,
                                    fileURL: url,
                                    attachment: a
                                )
                                .contentShape(Rectangle())
                                .accessibilityLabel(simpleThumbLabel(index: idx, total: images.count, fileURLString: a.value(forKey: "fileURL") as? String))
                                .accessibilityIdentifier("thumb.attachment.\(idx)")
                                .onTapGesture {
                                    viewerStartIndex = idx
                                    isShowingAttachmentViewer = true
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if !videos.isEmpty {
                        LazyVGrid(columns: grid, spacing: 12) {
                            ForEach(Array(videos.enumerated()), id: \.element.objectID) { (idx, a) in
                                let url = resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
                                VideoThumbCell(fileURL: url, attachment: a)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let u = url { previewURL = u; isShowingPreview = true }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(others, id: \.objectID) { a in
                        AttachmentRow(attachment: a) { openQuickLook(a) }
                    }
                }
                .cardSurface()
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xl)
    }
    .navigationTitle("Session")
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button("Edit") { 
                    editWasPresented = true
                    showEdit = true 
                }
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
    .onChange(of: showEdit) { _, newValue in
        if newValue == false {
            // Editor dismissed; if no save occurred, stop auto-pop behavior
            // We will also clear this flag on successful save when we dismiss below
            // (handled by the context change observer)
        }
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
            }
            , onTogglePrivacy: { url in
                // Also stamp by id when possible for cross-screen consistency
                let set = (session.attachments as? Set<Attachment>) ?? []
                let match = set.first { att in
                    guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                    return resolveAttachmentURL(from: stored) == url
                }
                togglePrivacy(id: (match?.value(forKey: "id") as? UUID), url: url)
                _refreshTick &+= 1
            }
            , isPrivate: { url in
                let set = (session.attachments as? Set<Attachment>) ?? []
                let match = set.first { att in
                    guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                    return resolveAttachmentURL(from: stored) == url
                }
                return isPrivateAttachment(id: (match?.value(forKey: "id") as? UUID), url: url)
            }
        )
        .onDisappear { _refreshTick &+= 1 }
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
        // If the edit sheet was (or is) presented and this session was updated, pop back to ContentView
        if editWasPresented && (touchesThisSession(updated) || touchesThisSession(inserted)) {
            editWasPresented = false
            // Ensure the edit sheet is closed, then dismiss this detail view
            showEdit = false
            DispatchQueue.main.async {
                dismiss()
            }
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

// v7.9E — Read-only State strip (must match editor semantics)
private let stateDotsCountDetail: Int = 12

/// DARK → LIGHT across the row (left→right).
private func detailOpacityForDot(_ i: Int) -> Double {
    // 0 = darkest (high opacity), 11 = lightest (low opacity)
    let start: Double = 0.95   // darker (more opaque) on the left
    let end:   Double = 0.15   // lighter (less opaque) on the right
    guard stateDotsCountDetail > 1 else { return start }
    let t = Double(i) / Double(stateDotsCountDetail - 1)
    return start + (end - start) * t
}

private func detailZoneCenterDot(for zone: Int) -> Int {
    switch zone {
    case 0: return 0      // leftmost dot for zone 0 (matches editor extreme behavior)
    case 1: return 4
    case 2: return 7
    default: return 11    // rightmost dot for zone 3
    }
}

/// Extracts FocusDotIndex (0…11) if present; falls back to legacy StateIndex (0…3 → mapped to center dots).
/// Returns (dotIndex?, cleanedNotesWithoutTokens)
private func extractFocusDotIndex(from notes: String) -> (Int?, String) {
    var working = notes

    // 1) Prefer FocusDotIndex: n (0…11)
    if let r = working.range(of: "FocusDotIndex:") {
        let tail = working[r.upperBound...]
        let end = tail.firstIndex(of: "\n") ?? working.endIndex
        let raw = String(working[r.upperBound..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(raw), (0...11).contains(n) {
            // Remove the token line
            working.removeSubrange(r.lowerBound..<end)
            while working.contains("\n\n") { working = working.replacingOccurrences(of: "\n\n", with: "\n") }
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
            return (n, working)
        }
    }

    // 2) Fallback: legacy StateIndex: n (0…3) → map to representative center dots [1,4,7,10]
    if let r = working.range(of: "StateIndex:") {
        let tail = working[r.upperBound...]
        let end = tail.firstIndex(of: "\n") ?? working.endIndex
        let raw = String(working[r.upperBound..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(raw), (0...3).contains(n) {
            let centers = [1, 4, 7, 10]
            let dot = centers[n]
            // Remove the token line
            working.removeSubrange(r.lowerBound..<end)
            while working.contains("\n\n") { working = working.replacingOccurrences(of: "\n\n", with: "\n") }
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
            return (dot, working)
        }
    }

    // 3) No tokens found → return original notes
    return (nil, notes)
}

    // MARK: - Attachments split & preview

    private func splitAttachments() -> (images: [Attachment], videos: [Attachment], others: [Attachment]) {
        let set = (session.attachments as? Set<Attachment>) ?? []
        let images = set.filter { ($0.kind ?? "") == "image" }.sorted { (a, b) in
            let da = (a.value(forKey: "createdAt") as? Date) ?? .distantPast
            let db = (b.value(forKey: "createdAt") as? Date) ?? .distantPast
            return da < db
        }
        let videos = set.filter { ($0.kind ?? "") == "video" }.sorted { (a, b) in
            let da = (a.value(forKey: "createdAt") as? Date) ?? .distantPast
            let db = (b.value(forKey: "createdAt") as? Date) ?? .distantPast
            return da < db
        }
        let others = set.filter { let k = ($0.kind ?? ""); return k != "image" && k != "video" }.sorted { (a, b) in
            let da = (a.value(forKey: "createdAt") as? Date) ?? .distantPast
            let db = (b.value(forKey: "createdAt") as? Date) ?? .distantPast
            return da < db
        }
        return (images, videos, others)
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

    private func simpleThumbLabel(index: Int, total: Int, fileURLString: String?) -> String {
        let base = "Attachment \(index+1) of \(total)"
        guard let s = fileURLString, !s.isEmpty else { return base }
        let name = URL(fileURLWithPath: s).lastPathComponent
        return name.isEmpty ? base : "\(base), \(name)"
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
    let fileURL: URL?

    private var attachmentID: UUID? {
        // KVC-safe lookup for id field
        (attachment.value(forKey: "id") as? UUID)
    }

    let attachment: Attachment

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Existing thumbnail + star remains in an inner ZStack to keep its topTrailing alignment
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

            // Read-only privacy badge (supports ID-first and URL fallback)
            if isPrivateAttachment(id: attachmentID, url: fileURL) {
                Image(systemName: "eye.slash")
                    .imageScale(.small)
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
    }
}

#if canImport(UIKit)
import AVKit
fileprivate struct VideoThumbCell: View {
    let fileURL: URL?
    let attachment: Attachment
    @State private var poster: UIImage? = nil

    private var attachmentID: UUID? { (attachment.value(forKey: "id") as? UUID) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .center) {
                Group {
                    if let poster {
                        Image(uiImage: poster).resizable().scaledToFill()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                            Image(systemName: "video")
                                .imageScale(.large)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                }
                .frame(width: 84, height: 84)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.secondary.opacity(0.15), lineWidth: 1)
                )

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            if isPrivateAttachment(id: attachmentID, url: fileURL) {
                Image(systemName: "eye.slash")
                    .imageScale(.small)
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .task(id: fileURL) {
            guard poster == nil, let u = fileURL else { return }
            await generatePoster(u)
        }
    }

    private func generatePoster(_ url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    self.poster = img
                    continuation.resume()
                }
            }
        }
    }
}
#endif
