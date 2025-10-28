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
import CryptoKit

private func privacyMap() -> [String: Bool] {
    UserDefaults.standard.dictionary(forKey: AttachmentPrivacy.mapKey) as? [String: Bool] ?? [:]
}

private func privacyKey(id: UUID?, url: URL?) -> String? {
    AttachmentPrivacy.privacyKey(id: id, url: url)
}

private func isPrivateAttachment(id: UUID?, url: URL?) -> Bool {
    return AttachmentPrivacy.isPrivate(id: id, url: url)
}

private func setPrivacy(_ isPrivate: Bool, id: UUID?, url: URL?) {
    AttachmentPrivacy.setPrivate(id: id, url: url, isPrivate)
}

private func togglePrivacy(id: UUID?, url: URL?) {
    AttachmentPrivacy.toggle(id: id, url: url)
}

struct SessionDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager

    @ObservedObject private var commentsStore = CommentsStore.shared

    let session: Session

    @State private var showEdit = false
    @State private var editWasPresented: Bool = false
    @State private var showDeleteConfirm = false
    @State private var previewURL: URL?
    @State private var isShowingPreview = false
    
    @State private var isShowingAttachmentViewer = false
    @State private var viewerStartIndex = 0
    @State private var viewerTappedURL: URL? = nil

    @State private var isCommentsPresented: Bool = false

    #if DEBUG
    @State private var isDebugPresented: Bool = false
    #endif
    #if DEBUG
    @State private var _debugJSONBuffer: String = ""
    #endif
    #if DEBUG
    @State private var debugTitle: String = "Session Debug"
    @State private var debugSessionRef: Session? = nil
    #endif

    @State private var privacyToken: Int = 0

    // Forces view refresh when attachments of this session change
    @State private var _refreshTick: Int = 0

    // Added state for local interaction counts and liked state
    @State private var isLikedLocal: Bool = false
    @State private var likeCountLocal: Int = 0
    @State private var commentCountLocal: Int = 0

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

    // Added private computed properties for session UUID and privacy
    private var sessionUUID: UUID? { session.value(forKey: "id") as? UUID }
    private var isPrivatePost: Bool { session.isPublic == false }

    // Stable session ID for comments. Prefer real UUID if present; otherwise derive from Core Data objectID.
    private var sessionIDForComments: UUID? {
        if let real = sessionUUID { return real }
        #if canImport(CoreData)
        let uri = session.objectID.uriRepresentation().absoluteString
        return stableUUID(from: uri)
        #else
        return nil
        #endif
    }

    private var commentsCount: Int {
        guard let id = sessionIDForComments else { return 0 }
        return commentsStore.comments(for: id).count
    }

    private func stableUUID(from string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(digest)
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid
    }

    // Added helper to build share text
    private func shareText() -> String {
        let title = SessionActivity.headerTitle(for: session)
        return "Check out my session: \(title) — via Motivo"
    }

    var body: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {

            SessionIdentityHeader(session: session)
                .environmentObject(auth)
                #if DEBUG
                .onLongPressGesture(minimumDuration: 0.6) {
                    debugSessionRef = session
                    debugTitle = "Session Debug"
                    isDebugPresented = true
                }
                #endif
                .padding(.bottom, 4)

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
                                    viewerTappedURL = url
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
                                        if let u = url {
                                            viewerTappedURL = u
                                            isShowingAttachmentViewer = true
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(others, id: \.objectID) { a in
                        let kind = (a.kind ?? "")
                        if kind == "audio" {
                            AttachmentRow(attachment: a) {
                                // Open unified AttachmentViewerView for audio, matching image/video behavior
                                let url = resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
                                viewerTappedURL = url
                                isShowingAttachmentViewer = true
                            }
                        } else {
                            AttachmentRow(attachment: a) { openQuickLook(a) }
                        }
                    }
                }
                .cardSurface()
            }
            
            if let sid = sessionUUID {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    interactionRow(sessionID: sid)
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
    .sheet(isPresented: $isCommentsPresented) {
        if let id = sessionIDForComments {
            CommentsView(sessionID: id, placeholderAuthor: "You")
        } else {
            Text("Comments unavailable for this item.")
                .padding()
        }
    }
    #if DEBUG
    .sheet(isPresented: $isDebugPresented) {
        NavigationStack {
            DebugViewerView(title: debugTitle, jsonString: $_debugJSONBuffer)
                .onAppear {
                    guard let s = debugSessionRef else {
                        _debugJSONBuffer = "{\"error\":\"unavailable\"}"
                        return
                    }
                    // Defer to next runloop to ensure presentation and fault realization
                    DispatchQueue.main.async {
                        _debugJSONBuffer = DebugDump.dump(session: s)
                    }
                }
        }
    }
    #endif
    .fullScreenCover(isPresented: $isShowingAttachmentViewer) {
        // Build URLs from the same source-of-truth order as thumbnails
        let split = splitAttachments()
        let images = split.images
        let videos = split.videos
        let others = split.others

        let imageURLs: [URL] = images.compactMap { a in
            resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
        }
        let videoURLs: [URL] = videos.compactMap { a in
            resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
        }
        // Treat non-image, non-video attachments as audio when possible
        let audioURLs: [URL] = others.compactMap { a in
            let kind = (a.kind ?? "")
            guard kind == "audio" else { return nil }
            return resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
        }

        // Compute start index based on the tapped URL within the combined media order [images, videos, audios]
        let combined: [URL] = imageURLs + videoURLs + audioURLs
        let startIndex: Int = {
            guard let tapped = viewerTappedURL, let idx = combined.firstIndex(of: tapped) else {
                // Fallback: if we only had an image index previously, try to map it
                if let first = imageURLs.first, combined.firstIndex(of: first) != nil {
                    return min(max(viewerStartIndex, 0), (combined.count > 0 ? combined.count - 1 : 0))
                }
                return 0
            }
            return idx
        }()

        AttachmentViewerView(
            imageURLs: imageURLs,
            startIndex: startIndex,
            themeBackground: Color(.systemBackground),
            videoURLs: videoURLs,
            audioURLs: audioURLs,
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
            },
            onFavourite: { url in
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
            },
            isFavourite: { url in
                let set = (session.attachments as? Set<Attachment>) ?? []
                if let a = set.first(where: { att in
                    guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                    return resolveAttachmentURL(from: stored) == url
                }) {
                    return (a.value(forKey: "isThumbnail") as? Bool) == true
                }
                return false
            },
            onTogglePrivacy: { url in
                let set = (session.attachments as? Set<Attachment>) ?? []
                let match = set.first { att in
                    guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                    return resolveAttachmentURL(from: stored) == url
                }
                togglePrivacy(id: (match?.value(forKey: "id") as? UUID), url: url)
                _refreshTick &+= 1
            },
            isPrivate: { url in
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
    // Added task to hydrate local interaction state on sessionUUID change
    .task(id: sessionUUID) {
        if let sid = sessionUUID {
            isLikedLocal = FeedInteractionStore.isLiked(sid)
            likeCountLocal = FeedInteractionStore.likeCount(sid)
            commentCountLocal = FeedInteractionStore.commentCount(sid)
        }
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

    // Added interactionRow view builder for Like · Comment · Share
    @ViewBuilder
    private func interactionRow(sessionID: UUID) -> some View {
        HStack(spacing: 0) {
            // Like
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                let newState = FeedInteractionStore.toggleLike(sessionID)
                isLikedLocal = newState
                likeCountLocal = FeedInteractionStore.likeCount(sessionID)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isLikedLocal ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(isLikedLocal ? Color.red : Theme.Colors.secondaryText)
                    Text("\(likeCountLocal)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLikedLocal ? "Unlike" : "Like")

            // Comment
            Button {
                if sessionIDForComments != nil {
                    isCommentsPresented = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text("\(commentsCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open comments")

            // Share
            Group {
                let isOwner = (session.ownerUserID ?? "") == (auth.currentUserID ?? "")
                if isPrivatePost && !isOwner {
                    ShareLink(item: shareText()) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                    .opacity(0.4)
                } else {
                    ShareLink(item: shareText()) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
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


fileprivate struct SessionIdentityHeader: View {
    let session: Session
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var auth: AuthManager

    private var ownerUserID: String? { session.ownerUserID ?? auth.currentUserID }
    private var isCurrentUser: Bool { ownerUserID == auth.currentUserID }

    private var avatarImage: UIImage? { ProfileStore.avatarImage(for: ownerUserID) }
    private var location: String { ProfileStore.location(for: ownerUserID) }

    private var displayName: String {
        if isCurrentUser {
            // Lookup real name from Profile entity
            let req: NSFetchRequest<Profile> = Profile.fetchRequest()
            req.fetchLimit = 1
            if let profile = try? viewContext.fetch(req).first, let n = profile.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return n
            }
            return "You"
        } else {
            return "User"
        }
    }

    // Updated privacy logic as requested
    private var isPrivate: Bool { session.isPublic == false }

    // Fallback initials
    private var initials: String {
        let name = displayName
        let words = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
        let first = words.first?.first.map { String($0).uppercased() } ?? "Y"
        let last = words.last?.first.map { String($0).uppercased() } ?? "U"
        return first + last
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Avatar
            Group {
                #if canImport(UIKit)
                if let img = avatarImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color.gray.opacity(0.2))
                        Text(initials)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                #else
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2))
                    Text(initials).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                }
                #endif
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))

            // Name and optional location
            HStack(spacing: 6) {
                Text(displayName).font(.subheadline.weight(.semibold))
                if !location.isEmpty {
                    Text("•").foregroundStyle(Theme.Colors.secondaryText)
                    Text(location).font(.footnote).foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            Spacer(minLength: 0)
            // Updated privacy icon from lock.fill to eye.slash
            if isPrivate {
                Image(systemName: "eye.slash")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .padding(.bottom, 2)
    }
}

