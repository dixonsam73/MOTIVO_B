// CHANGE-ID: 20260219_222900_BSDV_AAVParity_FirstTapFix_4a12
// SCOPE: BSDV — item-based AttachmentViewer launch + PRDV/SDV-style gallery grouping/startIndex (no UI redesign; BSDV-only).
// INVARIANTS: No backend/schema/RLS/RPC changes. No attachment persistence changes. No UI redesign. Changes localized to BSDV viewer launch.

import SwiftUI
import Foundation
import UIKit


// MARK: - Backend detail signed URL cache (session-memory)
// Cache key must be stable (bucket|path), not the signed URL string (token changes).
// This prevents repeated /object/sign calls when revisiting the same post in a single session.
private actor BackendDetailSignedURLCache {
    static let shared = BackendDetailSignedURLCache()

    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]

    private func key(bucket: String, path: String) -> String {
        "\(bucket)|\(path)"
    }

    func get(bucket: String, path: String, expiresInSeconds: Int, fetcher: @Sendable @escaping () async -> URL?) async -> URL? {
        let k = key(bucket: bucket, path: path)
        let now = Date()

        if let entry = cache[k] {
            // Small safety margin to avoid returning an about-to-expire signed URL.
            if entry.expiresAt.timeIntervalSince(now) > 5 {
                return entry.url
            } else {
                cache[k] = nil
            }
        }

        if let task = inflight[k] {
            return await task.value
        }

        let task = Task<URL?, Never> {
            let url = await fetcher()
            return url
        }
        inflight[k] = task

        let url = await task.value
        inflight[k] = nil

        if let url {
            cache[k] = Entry(url: url, expiresAt: now.addingTimeInterval(TimeInterval(expiresInSeconds)))
        }

        return url
    }
}


/// Connected-mode detail view for backend posts (read-only).
/// Parity target: SessionDetailView (UI), with the only allowed differences:
/// - No Edit button / no edit flow when viewing non-owner posts.
/// - Identity header is display-name only (no avatar yet; Phase 15 later).
struct BackendSessionDetailView: View {
    let model: BackendSessionViewModel

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager

    @ObservedObject private var commentsStore = CommentsStore.shared
    @ObservedObject private var commentPresence = CommentPresenceStore.shared

    // Phase 14 directory (display-name only; no avatar until Phase 15)
    @State private var directoryAccount: DirectoryAccount? = nil
    @State private var isLoadingDirectory: Bool = false

    // Profile peek sheet (non-owner identity header tap)
    @State private var isProfilePeekPresented: Bool = false



    #if canImport(UIKit)
    @State private var remoteAvatar: UIImage? = nil
    #endif

    // Comments sheet
    @State private var isCommentsPresented: Bool = false

    // Attachment viewer state (request owns payload to avoid first-tap empty-cover race)
    private enum ViewerMode {
        case visual
        case audio
    }

    private struct ViewerPayload {
        let mode: ViewerMode
        let startIndex: Int

        let imageURLs: [URL]
        let videoURLs: [URL]
        let audioURLs: [URL]

        let audioKeys: [String]
        let audioTitlesByKey: [String: String]

        let videoKeys: [String]
        let videoTitlesByKey: [String: String]
    }

    private struct ViewerRequest: Identifiable {
        let id = UUID()
        let payload: ViewerPayload
    }

    @State private var viewerRequest: ViewerRequest? = nil

    @State private var isLoadingAttachments: Bool = false
    @State private var attachmentLoadError: String? = nil
    @State private var thumbSignedURLs: [String: URL] = [:]

    // Mirrors SessionDetailView’s local interaction state
    @State private var isLikedLocal: Bool = false

    private let grid = [GridItem(.adaptive(minimum: 128), spacing: 12)]

    private var ownerUserID: String {
        (model.ownerUserID ?? "").lowercased()
    }

    private var effectiveViewerUserID: String? {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let override = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override.lowercased()
        }
        #endif
        let raw = (auth.backendUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw.lowercased()
    }

    private var viewerIsOwner: Bool {
        guard let viewer = effectiveViewerUserID, !viewer.isEmpty else { return false }
        guard !ownerUserID.isEmpty else { return false }
        return viewer == ownerUserID
    }

    // MARK: - SessionActivity-style header + chip (parity with SessionDetailView)

    private var headerTitle: String {
        let instrument = (model.instrumentLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = (model.activityLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !instrument.isEmpty && !activity.isEmpty {
            return "\(instrument): \(activity)"
        }
        return instrument.isEmpty ? activity : instrument
    }

    private var headerLine: String {
        let line = headerTitle
        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return line }
        let instrument = parts[0]
        let activity = parts[1]
        let title = (model.activityDetail ?? "")
        if title.range(of: activity, options: .caseInsensitive) != nil {
            return String(instrument)
        }
        return line
    }

    /// Parity rule: chip text is trimmed; if empty → chip hidden.
    private var activityDescriptionText: String {
        (model.activityDetail ?? "")
    }

    // MARK: - Date • time • duration (must match SessionDetailView exactly)

    private var sessionDate: Date {
        parseBackendDate(model.sessionTimestampRaw) ??
        parseBackendDate(model.createdAtRaw) ??
        Date()
    }

    private var metaLine: String {
        let ts = sessionDate

        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dateStr = dateFormatter.string(from: ts)
        let timeStr = timeFormatter.string(from: ts)
        let durStr = formattedDurationDisplay(Int(model.durationSeconds ?? 0))

        return "\(dateStr) • \(timeStr) • \(durStr)"
    }

    private func formattedDurationDisplay(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    // MARK: - Comments

    private var commentsCount: Int {
        commentsStore.comments(for: model.id).count
    }

    private var hasComments: Bool {
        if auth.isConnected {
            return commentPresence.hasComments(postID: model.id)
        }
        return commentsCount > 0
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            mainContentErased()
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .navigationTitle("Session")
        .onAppear {
            isLikedLocal = FeedInteractionStore.isHearted(model.id)
            Task {
                await loadThumbURLsIfNeeded()
                await loadDirectoryAccountIfNeeded()
            }
        }
        .sheet(isPresented: $isCommentsPresented) {
            if let viewer = effectiveViewerUserID, !viewer.isEmpty, !ownerUserID.isEmpty {
                CommentsView(postID: model.id, ownerUserID: ownerUserID, viewerUserID: viewer, ownerDisplayName: directoryAccount?.displayName)
            } else {
                Text("Comments unavailable.").padding()
            }
        }
.sheet(isPresented: $isProfilePeekPresented) {
    ProfilePeekView(
        ownerID: ownerUserID,
        directoryDisplayName: directoryAccount?.displayName,
        directoryAccountID: directoryAccount?.accountID,
        directoryLocation: directoryAccount?.location,
        directoryAvatarKey: directoryAccount?.avatarKey,
        directoryInstruments: directoryAccount?.instruments
    )
}
        .fullScreenCover(item: $viewerRequest) { req in
            let p = req.payload
            AttachmentViewerView(
                imageURLs: p.imageURLs,
                videoURLs: p.videoURLs,
                audioURLs: p.audioURLs,
                startIndex: p.startIndex,
                audioKeys: p.audioKeys,
                audioTitlesByKey: p.audioTitlesByKey,
                videoKeys: p.videoKeys,
                videoTitlesByKey: p.videoTitlesByKey,
                isReadOnly: true,
                canShare: false
            )
        }
        .appBackground()
        .onDisappear {
            NotificationCenter.default.post(name: Notification.Name("BackendSessionDetailView.didPop"), object: nil)
            resetViewerState()
        }
    }

    private func resetViewerState() {
        viewerRequest = nil
    }


    // Type-erased wrapper to help Xcode's type-checker on large view trees.
    private func mainContentErased() -> AnyView {
        AnyView(mainContent())
    }

    @ViewBuilder
    private func mainContent() -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            identityHeader()
                .padding(.bottom, 4)

            if !activityDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activityDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines))
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

            let originalNotes = model.notes ?? ""
            let (focusDotIndexFromNotes, displayNotes) = extractFocusDotIndex(from: originalNotes)

            if !displayNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Notes").sectionHeader()
                        Spacer(minLength: 0)
                    }
                    Text(displayNotes)
                }
                .cardSurface()
            }

            // Prefer legacy token if present; otherwise fall back to persisted effort on the backend post.
            // Treat default effort (5) as "unset" to preserve SessionDetailView semantics.
            let focusDotIndex: Int? = {
                if let legacy = focusDotIndexFromNotes { return legacy }
                if let effortDot = model.effortDotIndex {
                    return (effortDot == 5) ? nil : effortDot
                }
                return nil
            }()

            if let dot = focusDotIndex {
                FocusSectionCard(dotIndex: dot, colorScheme: colorScheme)
            }

            attachmentsCard()

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                interactionRow()
            }
            .cardSurface(padding: Theme.Spacing.m)
        }
    }

    // MARK: - Identity header (display name only; Phase 15 adds avatar)

    @ViewBuilder
    private func identityHeader() -> some View {
                HStack(alignment: .center, spacing: 8) {
            // Avatar (owner uses local; non-owner uses directory avatar_key when available)
            #if canImport(UIKit)
            let avatarKey = directoryAccount?.avatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cacheKey = "avatars|\(avatarKey)"

            Group {
                if viewerIsOwner, let img = ProfileStore.avatarImage(for: effectiveViewerUserID ?? "") {
                    Image(uiImage: img).resizable().scaledToFill()
                } else if !avatarKey.isEmpty, let cached = RemoteAvatarImageCache.get(cacheKey) {
                    Image(uiImage: cached).resizable().scaledToFill()
                } else if !avatarKey.isEmpty, let remoteAvatar = remoteAvatar {
                    Image(uiImage: remoteAvatar).resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color.gray.opacity(0.2))
                        Text(initials(from: displayName))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !viewerIsOwner else { return }
                isProfilePeekPresented = true
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .task(id: avatarKey) {
                guard !viewerIsOwner else {
                    remoteAvatar = nil
                    return
                }
                guard !avatarKey.isEmpty else {
                    remoteAvatar = nil
                    return
                }
                if RemoteAvatarImageCache.get(cacheKey) != nil { return }
                if let ui = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: avatarKey) {
                    remoteAvatar = ui
                }
            }
            #else
            ZStack {
                Circle().fill(Color.gray.opacity(0.2))
                Text("U").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            #endif

            HStack(spacing: 6) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("detail.displayName")

                let loc = locationText
                if !loc.isEmpty {
                    Text("•").foregroundStyle(Theme.Colors.secondaryText)
                    Text(loc)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .accessibilityIdentifier("detail.location")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        let words = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        if words.isEmpty { return "?" }
        if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
        let first = words.first?.first.map { String($0).uppercased() } ?? ""
        let last = words.last?.first.map { String($0).uppercased() } ?? ""
        let combo = (first + last)
        return combo.isEmpty ? "U" : combo
    }


    private var locationText: String {
        // Owner uses local ProfileStore; follower contexts use backend directory value.
        if viewerIsOwner {
            let viewer = effectiveViewerUserID ?? ""
            return ProfileStore.location(for: viewer)
        }

        if let account = directoryAccount,
           let s = account.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !s.isEmpty {
            return s
        }

        return ""
    }
    private var displayName: String {
        if viewerIsOwner {
            return "You"
        }
        if let account = directoryAccount {
            let name = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }
        return "User"
    }

    // MARK: - Attachments (parity layout with SessionDetailView)

    private func kindEnum(_ ref: BackendSessionViewModel.BackendAttachmentRef) -> BackendSessionViewModel.BackendAttachmentRef.Kind {
        ref.kind
    }

    private func cacheKey(_ ref: BackendSessionViewModel.BackendAttachmentRef) -> String {
        "\(ref.bucket)|\(ref.path)"
    }

    private func filename(from path: String) -> String {
        let comps = path.split(separator: "/")
        return comps.last.map(String.init) ?? path
    }

    @ViewBuilder
    private func attachmentsCard() -> some View {
        let refs = model.attachmentRefs

        if refs.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Attachments").sectionHeader()

                let images = refs.filter { kindEnum($0) == .image }
                let videos = refs.filter { kindEnum($0) == .video }
                let audios = refs.filter { kindEnum($0) == .audio }

                if !images.isEmpty || !videos.isEmpty {
                    LazyVGrid(columns: grid, spacing: 12) {
                        ForEach(Array(images.enumerated()), id: \.offset) { (_, ref) in
                            BackendThumbCell(kind: .image, bucket: ref.bucket, path: ref.path, url: thumbSignedURLs[cacheKey(ref)], showViewIcon: false)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await presentViewer(tapped: ref) }
                                }
                        }
                        ForEach(Array(videos.enumerated()), id: \.offset) { (_, ref) in
                            BackendThumbCell(kind: .video, bucket: ref.bucket, path: ref.path, url: thumbSignedURLs[cacheKey(ref)], showViewIcon: false)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await presentViewer(tapped: ref) }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !audios.isEmpty {
                    ForEach(audios, id: \.self) { ref in
                        let title = {
                            if let dn = ref.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty {
                                return dn
                            }
                            let stem = URL(fileURLWithPath: filename(from: ref.path)).deletingPathExtension().lastPathComponent
                            let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
                            return trimmed.isEmpty ? "Audio clip" : trimmed
                        }()

                        HStack(alignment: .center, spacing: 12) {
                            Button {
                                Task { await presentViewer(tapped: ref) }
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
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Open audio clip \(title)")

                            Spacer(minLength: 8)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }

                if let msg = attachmentLoadError {
                    Text(msg)
                        .font(Theme.Text.meta)
                        .foregroundStyle(.red)
                        .padding(.top, 6)
                }
            }
            .cardSurface(padding: Theme.Spacing.m)
        }
    }

    private func presentViewer(tapped ref: BackendSessionViewModel.BackendAttachmentRef) async {
        guard !isLoadingAttachments else { return }
        isLoadingAttachments = true
        attachmentLoadError = nil
        defer { isLoadingAttachments = false }

        let refs = model.attachmentRefs
        guard !refs.isEmpty else {
            attachmentLoadError = "Unable to load attachment URLs."
            return
        }

        let tappedKind = kindEnum(ref)
        let tappedKey = cacheKey(ref)

        let imagesAll = refs.filter { kindEnum($0) == .image }
        let videosAll = refs.filter { kindEnum($0) == .video }
        let audiosAll = refs.filter { kindEnum($0) == .audio }

        // Build the entire viewer payload locally first, then present with fullScreenCover(item:)
        // so the cover never sees an empty/default payload on first tap.
        if tappedKind == .audio {
            var audioURLs: [URL] = []
            var audioKeys: [String] = []
            var audioTitlesByKey: [String: String] = [:]

            for r in audiosAll {
                let key = cacheKey(r)
                guard let url = await signedURL(bucket: r.bucket, path: r.path, expiresInSeconds: 120) else { continue }
                audioURLs.append(url)
                audioKeys.append(key)
                if let dn = r.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty {
                    audioTitlesByKey[key] = dn
                }
            }

            guard !audioURLs.isEmpty, let startIndex = audioKeys.firstIndex(of: tappedKey) else {
                attachmentLoadError = "Unable to load attachment URLs."
                return
            }

            let payload = ViewerPayload(
                mode: .audio,
                startIndex: startIndex,
                imageURLs: [],
                videoURLs: [],
                audioURLs: audioURLs,
                audioKeys: audioKeys,
                audioTitlesByKey: audioTitlesByKey,
                videoKeys: [],
                videoTitlesByKey: [:]
            )

            await MainActor.run {
                viewerRequest = nil
                viewerRequest = ViewerRequest(payload: payload)
            }
        } else {
            var imageURLs: [URL] = []
            var imageKeys: [String] = []

            for r in imagesAll {
                let key = cacheKey(r)
                guard let url = await signedURL(bucket: r.bucket, path: r.path, expiresInSeconds: 120) else { continue }
                imageURLs.append(url)
                imageKeys.append(key)
            }

            var videoURLs: [URL] = []
            var videoKeys: [String] = []
            var videoTitlesByKey: [String: String] = [:]

            for r in videosAll {
                let key = cacheKey(r)
                guard let url = await signedURL(bucket: r.bucket, path: r.path, expiresInSeconds: 120) else { continue }
                videoURLs.append(url)
                videoKeys.append(key)
                if let dn = r.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty {
                    videoTitlesByKey[key] = dn
                }
            }

            let startIndex: Int
            if tappedKind == .image {
                guard let idx = imageKeys.firstIndex(of: tappedKey) else {
                    attachmentLoadError = "Unable to load attachment URLs."
                    return
                }
                startIndex = idx
            } else if tappedKind == .video {
                guard let idx = videoKeys.firstIndex(of: tappedKey) else {
                    attachmentLoadError = "Unable to load attachment URLs."
                    return
                }
                startIndex = imageURLs.count + idx
            } else {
                // Unknown kind: fail closed rather than presenting an empty viewer.
                attachmentLoadError = "Unable to load attachment URLs."
                return
            }

            guard !(imageURLs.isEmpty && videoURLs.isEmpty) else {
                attachmentLoadError = "Unable to load attachment URLs."
                return
            }

            let payload = ViewerPayload(
                mode: .visual,
                startIndex: startIndex,
                imageURLs: imageURLs,
                videoURLs: videoURLs,
                audioURLs: [],
                audioKeys: [],
                audioTitlesByKey: [:],
                videoKeys: videoKeys,
                videoTitlesByKey: videoTitlesByKey
            )

            await MainActor.run {
                viewerRequest = nil
                viewerRequest = ViewerRequest(payload: payload)
            }
        }
    }

    private func loadThumbURLsIfNeeded() async {
        let refs = model.attachmentRefs.filter { kindEnum($0) == .image || kindEnum($0) == .video }
        guard !refs.isEmpty else { return }

        for ref in refs {
            let key = cacheKey(ref)
            if thumbSignedURLs[key] != nil { continue }

            if let url = await signedURL(bucket: ref.bucket, path: ref.path, expiresInSeconds: 300) {
                thumbSignedURLs[key] = url
            }
        }
    }

    private func signedURL(bucket: String, path: String, expiresInSeconds: Int) async -> URL? {
        await BackendDetailSignedURLCache.shared.get(bucket: bucket, path: path, expiresInSeconds: expiresInSeconds) {
            let result = await NetworkManager.shared.createSignedStorageObjectURL(
                bucket: bucket,
                path: path,
                expiresInSeconds: expiresInSeconds
            )
            switch result {
            case .success(let url):
                return url
            case .failure:
                return nil
            }
        }
    }


    // MARK: - Interactions row (must match SessionDetailView)

    private func interactionRow() -> some View {
        HStack(spacing: 0) {
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                let newState = FeedInteractionStore.toggleHeart(model.id)
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

            Button {
                isCommentsPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: hasComments ? "text.bubble" : "bubble.right")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open comments")

            if viewerIsOwner {
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
        .accessibilityElement(children: .contain)
    }

    private func shareText() -> String {
        let title = headerTitle
        return "Check out my session: \(title) — via Etudes"
    }

    // MARK: - Directory lookup (Phase 14)

    private func loadDirectoryAccountIfNeeded() async {
        guard !isLoadingDirectory else { return }
        guard !ownerUserID.isEmpty else { return }
        isLoadingDirectory = true
        defer { isLoadingDirectory = false }

        let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: [ownerUserID])
        switch result {
        case .success(let map):
            directoryAccount = map[ownerUserID]
        case .failure:
            break
        }
    }

    // MARK: - Date parsing (unchanged)

    private func parseBackendDate(_ raw: String?) -> Date? {
        guard let s = raw?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)

        df.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        if let d = df.date(from: s) { return d }

        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
        if let d = df.date(from: s) { return d }

        return nil
    }
}

// MARK: - BSDV decoded preview caches (app-lifetime)
//
// These caches intentionally key by stable attachment identity (bucket|path), NOT by signed URL (token changes).
// Purpose: prevent visible thumbnail/poster “reload” phases when BSDV is presented repeatedly during one app run.
fileprivate enum BackendDetailPreviewCache {
    static let imageThumbCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    static let videoPosterCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()
}



// MARK: - Focus token extraction (copied from SessionDetailView for parity)

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

// MARK: - Backend attachment thumb cell (parity with SessionDetailView thumb styling)

private struct BackendThumbCell: View {
    let kind: BackendSessionViewModel.BackendAttachmentRef.Kind
    let bucket: String
    let path: String
    let url: URL?
    let showViewIcon: Bool

    @State private var imageThumb: UIImage? = nil
    @State private var poster: UIImage? = nil

    private var stableKey: NSString {
        "\(bucket)|\(path)" as NSString
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .center) {
                Group {
                    switch kind {
                    case .image:
                        if let cached = BackendDetailPreviewCache.imageThumbCache.object(forKey: stableKey) {
                            Image(uiImage: cached).resizable().scaledToFill()
                        } else if let imageThumb {
                            Image(uiImage: imageThumb).resizable().scaledToFill()
                        } else {
                            neutralPlaceholder()
                        }

                    case .video:
                        if let cached = BackendDetailPreviewCache.videoPosterCache.object(forKey: stableKey) {
                            Image(uiImage: cached).resizable().scaledToFill()
                        } else if let poster {
                            Image(uiImage: poster).resizable().scaledToFill()
                        } else {
                            neutralPlaceholder()
                        }

                    case .audio:
                        placeholderIcon(systemName: "waveform")
                    }
                }
                .frame(width: 128, height: 128)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.secondary.opacity(0.15), lineWidth: 1)
                )
                .clipped()

                if kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }

            if showViewIcon {
                Image(systemName: "eye")
                    .imageScale(.small)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding([.top, .trailing], 4)
            }
        }
        .frame(width: 128, height: 128)
        .task(id: url) {
            switch kind {
            case .image:
                await hydrateImageThumbIfNeeded()
            case .video:
                await hydrateVideoPosterIfNeeded()
            case .audio:
                break
            }
        }
    }

    private func hydrateImageThumbIfNeeded() async {
        if BackendDetailPreviewCache.imageThumbCache.object(forKey: stableKey) != nil { return }
        if imageThumb != nil { return }
        guard let u = url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: u)
            guard let img = UIImage(data: data) else { return }
            BackendDetailPreviewCache.imageThumbCache.setObject(img, forKey: stableKey)
            await MainActor.run { self.imageThumb = img }
        } catch {
            // Silent failure: keep neutral placeholder.
        }
    }

    private func hydrateVideoPosterIfNeeded() async {
        if BackendDetailPreviewCache.videoPosterCache.object(forKey: stableKey) != nil { return }
        if poster != nil { return }
        guard let u = url else { return }
        let img = await generatePoster(u)
        guard let img else { return }
        BackendDetailPreviewCache.videoPosterCache.setObject(img, forKey: stableKey)
        await MainActor.run { self.poster = img }
    }

    private func neutralPlaceholder() -> some View {
        // Quiet placeholder (no glyph) to avoid “generic icon → real thumbnail” swap while remote media hydrates.
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
    }

    func placeholderIcon(systemName: String) -> some View {
        // For stable non-thumbnail types (audio), an icon is fine and not a hydration artifact.
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            Image(systemName: systemName)
                .imageScale(.large)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private func generatePoster(_ url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                continuation.resume(returning: img)
            }
        }
    }
}
