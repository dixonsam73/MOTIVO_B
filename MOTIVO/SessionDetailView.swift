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
// CHANGE-ID: 20251227_212500-e51e0181
// SCOPE: Type-checker fix (extract subviews + AnyView erasure) + compile errors fix (DEBUG block + AttachmentViewerView arg order)
import SwiftUI
import CoreData
import UIKit
import Combine
import CryptoKit
import AVFoundation

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

private let persistedAudioTitlesKey = "persistedAudioTitles_v1"

private func loadPersistedAudioTitles() -> [String: String] {
    (UserDefaults.standard.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
}

private func persistedAudioTitle(for attachmentID: UUID) -> String? {
    let raw = loadPersistedAudioTitles()[attachmentID.uuidString] ?? ""
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private let persistedVideoTitlesKey = "persistedVideoTitles_v1"

private func loadPersistedVideoTitles() -> [String: String] {
    (UserDefaults.standard.dictionary(forKey: persistedVideoTitlesKey) as? [String: String]) ?? [:]
}

private func persistedVideoTitle(for attachmentID: UUID) -> String? {
    let raw = loadPersistedVideoTitles()[attachmentID.uuidString] ?? ""
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
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


    private let grid = [GridItem(.adaptive(minimum: 128), spacing: 12)]

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
    private var areNotesPrivate: Bool {
        // Only touch KVC if the attribute exists on this entity; otherwise, default to false.
        let entity = session.entity
        if entity.attributesByName.keys.contains("areNotesPrivate") {
            return (session.value(forKey: "areNotesPrivate") as? Bool) == true
        }
        // Attribute not present in this store/model version → treat notes as public.
        return false
    }

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


    // Type-erased wrappers to help Xcode's type-checker on large view trees.
    private func mainContentErased() -> AnyView {
        AnyView(mainContent())
    }

    #if DEBUG
    private func debugSheetErased() -> AnyView {
        AnyView(NavigationStack {
                DebugViewerView(title: debugTitle, jsonString: $_debugJSONBuffer)
                    .onAppear {
                        guard let s = debugSessionRef else {
                            _debugJSONBuffer = "{\"error\":\"unavailable\"}"
                            return
                        }
                        DispatchQueue.main.async {
                            let json = DebugDump.dump(session: s)
                            NSLog("[DebugViewer] session dump = %@", json)
                            _debugJSONBuffer = json
                        }
                    }
            })
    }
    #endif

    private func attachmentViewerSheetErased() -> AnyView {
        AnyView(attachmentViewerSheet())
    }

    // Extracted sheet content (kept identical) so it can be type-erased for compiler performance.
    private func attachmentViewerSheet() -> some View {

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

            return AttachmentViewerView(
                imageURLs: imageURLs,
                startIndex: startIndex,
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
                titleForURL: { url, kind in
                    switch kind {
                    case .audio:
                        // Resolve the attachment by matching resolved fileURL strings as SDV already does elsewhere
                        let set = (session.attachments as? Set<Attachment>) ?? []
                        if let match = set.first(where: { att in
                            guard let stored = att.value(forKey: "fileURL") as? String else { return false }
                            return resolveAttachmentURL(from: stored) == url
                        }), let attID = match.value(forKey: "id") as? UUID {
                            if let persisted = persistedAudioTitle(for: attID) {
                                return persisted
                            }
                        }
                        // Fallback to existing behavior: use filename stem
                        let stem = url.deletingPathExtension().lastPathComponent
                        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? nil : trimmed
                    case .video:
                        // Match by stable basename (UUID-like) ignoring extension
                        let stem = url.deletingPathExtension().lastPathComponent
                        let set = (session.attachments as? Set<Attachment>) ?? []
                        if let match = set.first(where: { att in
                            guard let stored = att.value(forKey: "fileURL") as? String, !stored.isEmpty else { return false }
                            let storedStem = URL(fileURLWithPath: stored).deletingPathExtension().lastPathComponent
                            return storedStem == stem
                        }), let attID = match.value(forKey: "id") as? UUID {
                            return persistedVideoTitle(for: attID)
                        }
                        return nil
                    case .image, .file:
                        return nil
                    }
                },
                onRename: { url, newTitle, kind in
                    guard kind == .video else { return }
                    // Persist video title keyed by Attachment UUID (match by stem to handle extension changes)
                    let stem = url.deletingPathExtension().lastPathComponent
                    let set = (session.attachments as? Set<Attachment>) ?? []
                    if let match = set.first(where: { att in
                        guard let stored = att.value(forKey: "fileURL") as? String, !stored.isEmpty else { return false }
                        let storedStem = URL(fileURLWithPath: stored).deletingPathExtension().lastPathComponent
                        return storedStem == stem
                    }), let attID = match.value(forKey: "id") as? UUID {
                        var map = loadPersistedVideoTitles()
                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            map.removeValue(forKey: attID.uuidString)
                        } else {
                            map[attID.uuidString] = trimmed
                        }
                        UserDefaults.standard.set(map, forKey: persistedVideoTitlesKey)
                        _refreshTick &+= 1
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
                },
                onReplaceAttachment: { originalURL, newURL, kind in
                    // Match by stable basename (UUID-like) ignoring extension, since replace moves .mov -> .mp4
                    let originalStem = originalURL.deletingPathExtension().lastPathComponent
                    let set = (session.attachments as? Set<Attachment>) ?? []
                    if let match = set.first(where: { att in
                        guard let stored = att.value(forKey: "fileURL") as? String, !stored.isEmpty else { return false }
                        let storedLast = URL(fileURLWithPath: stored).deletingPathExtension().lastPathComponent
                        return storedLast == originalStem
                    }) {
                        match.setValue(newURL.path, forKey: "fileURL")
                        do { try viewContext.save() } catch { print("Replace attachment save error:", error) }
                        _refreshTick &+= 1
                    } else {
                        print("[AttachmentViewer] onReplaceAttachment: attachment not found (stem)", originalStem)
                    }
                },
                onSaveAsNewAttachment: { newURL, kind in
                    // Persist a new Attachment for this session; do not modify or delete the original
                    let finalPath = newURL.path
                    // Map AttachmentKind from viewer callback to storage kind
                    let storageKind: AttachmentKind = kind
                    do {
                        _ = try AttachmentStore.addAttachment(kind: storageKind,
                                                              filePath: finalPath,
                                                              to: session,
                                                              isThumbnail: false,
                                                              ctx: viewContext)
                        try viewContext.save()
                        _refreshTick &+= 1
                    } catch {
                        print("Save-as-new attachment error:", error)
                    }
                },
                isReadOnly: true,
                canShare: (session.ownerUserID == auth.currentUserID)
            )
            .onDisappear { _refreshTick &+= 1 }
    }

    var body: some View {
        ScrollView {
            mainContentErased()
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .navigationTitle("Session")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Show Edit only when the current user owns the session
                    let isOwner = (session.ownerUserID ?? "") == (auth.currentUserID ?? "")
                    if isOwner {
                        Button("Edit") {
                            editWasPresented = true
                            showEdit = true
                        }
                    }
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
            debugSheetErased()
        }
        #endif
        .fullScreenCover(isPresented: $isShowingAttachmentViewer) {
            attachmentViewerSheetErased()
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
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            _refreshTick &+= 1
        }
        .appBackground()
        // Added task to hydrate local interaction state on sessionUUID change
        .task(id: sessionUUID) {
            if let sid = sessionUUID {
                isLikedLocal = FeedInteractionStore.isLiked(sid)
             
            }
        }
    }
    
    @ViewBuilder
    private func mainContent() -> some View {
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

            if !activityDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activityDescriptionText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardSurface()
            }

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    HStack {
                        Text(headerLine)
                            .accessibilitySortPriority(2)
                        Spacer()
                    }
                    Text(metaLine)
                        .font(Theme.Text.meta)
                        .foregroundStyle(.secondary)
                        .accessibilitySortPriority(1)
                }
                .accessibilityElement(children: .contain)
            }
            .cardSurface()

            let originalNotes = session.notes ?? ""
            let (focusDotIndex, displayNotes) = extractFocusDotIndex(from: originalNotes)
            let isOwner = (session.ownerUserID ?? "") == (auth.currentUserID ?? "")
            if !displayNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if areNotesPrivate && !isOwner {
                    // Do not show notes to non-owners when private
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Notes").sectionHeader()
                            Spacer(minLength: 0)
                            // REMOVED: no privacy icon here per instructions
                        }
                        Text(displayNotes)
                    }
                    .cardSurface()
                }
            }

            if let dot = focusDotIndex {
                FocusSectionCard(dotIndex: dot, colorScheme: colorScheme)
            }

            let (images, videos, others) = splitAttachments()
            if !(images.isEmpty && videos.isEmpty && others.isEmpty) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Attachments").sectionHeader()
                    if !images.isEmpty || !videos.isEmpty {
                        LazyVGrid(columns: grid, spacing: 12) {
                            // Images first
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
                            // Then videos
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
                            let url = resolveAttachmentURL(from: a.value(forKey: "fileURL") as? String)
                            let path = (a.value(forKey: "fileURL") as? String) ?? ""
                            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                            // Prefer persisted title if available for this attachment ID
                            let id = a.value(forKey: "id") as? UUID
                            let persisted = id.flatMap { persistedAudioTitle(for: $0) }
                            let title: String = {
                                if let t = persisted, !t.isEmpty { return t }
                                let trimmedStem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
                                return trimmedStem.isEmpty ? "Audio clip" : trimmedStem
                            }()
                            let durationText: String? = {
                                guard let u = url else { return nil }
                                let asset = AVURLAsset(url: u)
                                let seconds = CMTimeGetSeconds(asset.duration)
                                guard seconds.isFinite, seconds > 0 else { return nil }
                                let total = Int(seconds.rounded())
                                let minutes = total / 60
                                let secs = total % 60
                                return String(format: "%d:%02d", minutes, secs)
                            }()
                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    viewerTappedURL = url
                                    isShowingAttachmentViewer = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 16, weight: .semibold))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(title)
                                                .font(.footnote)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            if let durationText {
                                                Text(durationText)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Open audio clip \(title)")
                                Spacer(minLength: 8)
                                let isOwner = (session.ownerUserID ?? "") == (auth.currentUserID ?? "")
                                if isOwner && !AttachmentPrivacy.isPrivate(id: (a.value(forKey: "id") as? UUID), url: nil) {
                                    Image(systemName: "eye")
                                        .imageScale(.small)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                        .padding(4)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                        .padding([.top, .trailing], 4)
                                        .accessibilityLabel("Included in post")
                                }
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                        } else {
                            AttachmentRow(attachment: a) { openQuickLook(a) }
                        }
                    }
                }
                .cardSurface(padding: Theme.Spacing.m)
            }

            if let sid = sessionUUID {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    interactionRow(sessionID: sid)
                }
                .cardSurface(padding: Theme.Spacing.m)
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

    
    // MARK: - Type-checker assist (Focus strip extraction)
    private struct FocusSectionCard: View {
        let dotIndex: Int
        let colorScheme: ColorScheme

        private let count: Int = 12
        private let spacing: CGFloat = 8

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Focus").sectionHeader()
                FocusDotStripView(dotIndex: dotIndex, count: count, spacing: spacing, colorScheme: colorScheme)
                    .frame(height: 44)
                    .accessibilityLabel(Text(bucketLabel(for: dotIndex)))
            }
            .cardSurface(padding: Theme.Spacing.m)
        }

        private func bucketLabel(for dot: Int) -> String {
            switch (dot / 3) {
            case 0: return "State: Searching"
            case 1: return "State: Working"
            case 2: return "State: Flowing"
            default: return "State: Breakthrough"
            }
        }
    }

    private struct FocusDotStripView: View {
        let dotIndex: Int
        let count: Int
        let spacing: CGFloat
        let colorScheme: ColorScheme

        var body: some View {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let diameter = max(14, min(32, (totalWidth - spacing * CGFloat(max(0, count - 1))) / CGFloat(max(1, count))))
                let ringDot = max(0, min(count - 1, dotIndex))

                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        dotView(index: i, ringDot: ringDot, diameter: diameter)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        @ViewBuilder
        private func dotView(index i: Int, ringDot: Int, diameter: CGFloat) -> some View {
            let isRinged = (i == ringDot)
            let baseScale: CGFloat = isRinged ? 1.18 : 1.0

            Circle()
                .fill(FocusDotStyle.fillColor(index: i, total: count, colorScheme: colorScheme))
                .overlay(Circle().stroke(FocusDotStyle.hairlineColor, lineWidth: FocusDotStyle.hairlineWidth))
                .overlay(ringOverlay(isRinged: isRinged))
                .frame(width: diameter, height: diameter)
                .scaleEffect(baseScale)
                .accessibilityHidden(true)
        }

        @ViewBuilder
        private func ringOverlay(isRinged: Bool) -> some View {
            if isRinged {
                Circle().stroke(
                    FocusDotStyle.ringColor(for: colorScheme),
                    lineWidth: FocusDotStyle.ringWidth
                )
            }
        }
    }

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
        // Delete on-disk media files for this session's attachments before deleting the Core Data object
        let attachments = (session.attachments as? Set<Attachment>) ?? []
        let paths: [String] = attachments.compactMap { att in
            if let s = att.value(forKey: "fileURL") as? String, !s.isEmpty { return s }
            return nil
        }
        if !paths.isEmpty {
            AttachmentStore.deleteAttachmentFiles(atPaths: paths)
        }

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
                let newState = FeedInteractionStore.toggleHeart(sessionID)
                isLikedLocal = newState
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isLikedLocal ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(isLikedLocal ? Color.red : Theme.Colors.secondaryText)
                    
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open comments")


            // Comment
            Button {
                if sessionIDForComments != nil {
                    isCommentsPresented = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: commentsCount > 0 ? "text.bubble" : "bubble.right")
                        .font(.system(size: 20, weight: .regular))
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
            let isOwner = ((attachment.session?.ownerUserID) ?? "") == ((try? PersistenceController.shared.currentUserID) ?? "")
            if isOwner && !AttachmentPrivacy.isPrivate(id: (attachment.value(forKey: "id") as? UUID), url: nil) {
                Image(systemName: "eye")
                    .imageScale(.small)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Included in post")
            }
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
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let last = url.lastPathComponent
        return last.isEmpty ? "file" : last
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
        ZStack(alignment: .topTrailing) {
            // Existing thumbnail + star remains in an inner ZStack to keep its topTrailing alignment
            ZStack(alignment: .topTrailing) {
                Group {
                    if let ui = image { Image(uiImage: ui).resizable().scaledToFill() }
                    else { Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary) }
                }
                .frame(width: 128, height: 128)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            let isOwner = ((attachment.session?.ownerUserID) ?? "") == ((try? PersistenceController.shared.currentUserID) ?? "")
            if isOwner && !isPrivateAttachment(id: attachmentID, url: fileURL) {
                Image(systemName: "eye")
                    .imageScale(.small)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding([.top, .trailing], 4)
                    .accessibilityLabel("Included in post")
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
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .center) {
                Group {
                    if let poster {
                        Image(uiImage: poster).resizable().scaledToFill()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                            Image(systemName: "video")
                                .imageScale(.large)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                }
                .frame(width: 128, height: 128)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.secondary.opacity(0.15), lineWidth: 1)
                )

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            let isOwner = ((attachment.session?.ownerUserID) ?? "") == ((try? PersistenceController.shared.currentUserID) ?? "")
            if isOwner && !isPrivateAttachment(id: attachmentID, url: fileURL) {
                Image(systemName: "eye")
                    .imageScale(.small)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding([.top, .trailing], 4)
                    .accessibilityLabel("Included in post")
            }
        }
        .frame(width: 128, height: 128)
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
            // REMOVED privacy icon from lock.fill to eye.slash per instructions (nothing here)
        }
        .padding(.bottom, 2)
    }
}

