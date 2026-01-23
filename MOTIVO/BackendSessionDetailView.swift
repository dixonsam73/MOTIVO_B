// CHANGE-ID: 20260123_114306_14_2_2_BackendDetailParity
// SCOPE: Phase 14.2.2 — Mirror SessionDetailView UI for BackendSessionDetailView (read-only; display name only; duration + notes + attachments)
// SEARCH-TOKEN: 20260123_114306_BackendDetailParity

import SwiftUI
import Foundation

/// Connected-mode detail view for *non-owner* posts.
/// Mirrors SessionDetailView’s card layout and typography, but is strictly read-only.
struct BackendSessionDetailView: View {
    let model: BackendSessionViewModel

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager

    // Phase 14 directory (display-name only; no avatar until Phase 15)
    @State private var directoryAccount: DirectoryAccount? = nil
    @State private var isLoadingDirectory: Bool = false

    // Comments sheet
    @State private var isCommentsPresented: Bool = false

    // Attachment viewer state
    @State private var isViewerPresented: Bool = false
    @State private var viewerImageURLs: [URL] = []
    @State private var viewerVideoURLs: [URL] = []
    @State private var viewerAudioURLs: [URL] = []
    @State private var viewerAudioTitles: [String]? = nil
    @State private var isLoadingAttachments: Bool = false
    @State private var attachmentLoadError: String? = nil

    // Thumbnail signed URLs (images only)
    @State private var thumbSignedURLs: [String: URL] = [:]

    // MARK: - Derived display fields (mirror SessionDetailView rules)

    private var ownerUserID: String {
        (model.ownerUserID ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private var displayName: String {
        let n = (directoryAccount?.displayName ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return n.isEmpty ? "User" : n
    }

    private var activityName: String {
        let raw = (model.activityLabel ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return raw.isEmpty ? "Practice" : raw
    }

    private var instrumentName: String {
        let raw = (model.instrumentLabel ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return raw.isEmpty ? "Instrument" : raw
    }

    private var headerLine: String {
        "\(activityName) • \(instrumentName)"
    }

    private var titleLine: String {
        let detail = (model.activityDetail ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return detail.isEmpty ? "" : detail
    }

    private var sessionDate: Date {
        parseBackendDate(model.sessionTimestampRaw) ??
        parseBackendDate(model.createdAtRaw) ??
        Date()
    }

    private var metaLine: String {
        let (time, date) = timeAndDateStrings(for: sessionDate)
        let duration = durationString(seconds: model.durationSeconds)
        // SessionDetailView shows: "19 Jan 2026 • 17:18 • 32m"
        if duration.isEmpty {
            return "\(date) • \(time)"
        } else {
            return "\(date) • \(time) • \(duration)"
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                // Header card
                VStack(alignment: .leading, spacing: 10) {
                    identityHeader()

                    if !titleLine.isEmpty {
                        Text(titleLine)
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Theme.Colors.surface(colorScheme))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Theme.Colors.cardStroke(colorScheme), lineWidth: 1)
                            )
                            .accessibilityIdentifier("detail.titleChip")
                    }

                    Text(headerLine)
                        .font(.headline)
                        .lineLimit(2)
                        .accessibilityIdentifier("detail.headerLine")

                    Text(metaLine)
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .accessibilityIdentifier("detail.metaLine")
                }
                .cardSurface()

                // Notes card
                let notesText = (model.notes ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !notesText.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Notes").sectionHeader()
                        Text(notesText)
                    }
                    .cardSurface()
                }

// Attachments
                attachmentsCard()

                // Interactions row (Save + Comments). Share is owner-only and this view is for non-owners.
                interactionsCard()
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.m)
        }
        .background(Theme.Colors.background(colorScheme))
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDirectoryAccountIfNeeded()
            await loadThumbURLsIfNeeded()
        }
        .sheet(isPresented: $isCommentsPresented) {
            // Placeholder author for composer; actual identity in comments comes from stores/backends.
            CommentsView(sessionID: model.id, placeholderAuthor: "You")
        }
        .sheet(isPresented: $isViewerPresented) {
            AttachmentViewerView(
                imageURLs: viewerImageURLs,
                videoURLs: viewerVideoURLs,
                audioURLs: viewerAudioURLs,
                startIndex: 0,
                audioTitles: viewerAudioTitles,
                isReadOnly: true,
                canShare: false
            )
        }
    }

    // MARK: - Identity header (display name only; Phase 15 adds avatar)

    @ViewBuilder
    private func identityHeader() -> some View {
        HStack(spacing: 8) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("detail.displayName")

            Spacer(minLength: 0)
        }
    }

    // MARK: - Attachments

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

                // Images / Videos grid
                let visual = refs.filter { r in
                    let k = kindEnum(r)
                    return k == .image || k == .video
                }

                if !visual.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
                        ForEach(visual, id: \.self) { ref in
                            BackendThumbCell(
                                kind: kindEnum(ref),
                                url: thumbSignedURLs[cacheKey(ref)],
                                showViewIcon: true
                            )
                            .onTapGesture {
                                Task {
                                    await presentViewer()
                                }
                            }
                        }
                    }
                }

                // Audio list (simple rows)
                let audios = refs.filter { kindEnum($0) == .audio }
                if !audios.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(audios, id: \.self) { ref in
                            HStack(spacing: 10) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                Text(filename(from: ref.path))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "eye")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task {
                                    await presentViewer()
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                if let msg = attachmentLoadError {
                    Text(msg)
                        .font(Theme.Text.meta)
                        .foregroundStyle(.red)
                        .padding(.top, 6)
                }
            }
            .cardSurface()
        }
    }

    private func presentViewer() async {
        await loadViewerSignedURLsIfNeeded()
        if viewerImageURLs.isEmpty && viewerVideoURLs.isEmpty && viewerAudioURLs.isEmpty {
            attachmentLoadError = attachmentLoadError ?? "Unable to load attachment URLs."
            return
        }
        isViewerPresented = true
    }

    private func loadThumbURLsIfNeeded() async {
        let refs = model.attachmentRefs.filter { kindEnum($0) == .image }
        guard !refs.isEmpty else { return }

        for ref in refs {
            let key = cacheKey(ref)
            if thumbSignedURLs[key] != nil { continue }

            if let url = await signedURL(bucket: ref.bucket, path: ref.path, expiresInSeconds: 300) {
                thumbSignedURLs[key] = url
            }
        }
    }

    private func loadViewerSignedURLsIfNeeded() async {
        guard !isLoadingAttachments else { return }
        isLoadingAttachments = true
        attachmentLoadError = nil
        defer { isLoadingAttachments = false }

        let refs = model.attachmentRefs
        guard !refs.isEmpty else { return }

        var images: [URL] = []
        var videos: [URL] = []
        var audios: [URL] = []
        var audioTitles: [String] = []

        for ref in refs {
            let k = kindEnum(ref)
            if let url = await signedURL(bucket: ref.bucket, path: ref.path, expiresInSeconds: 120) {
                switch k {
                case .image: images.append(url)
                case .video: videos.append(url)
                case .audio:
                    audios.append(url)
                    audioTitles.append(filename(from: ref.path))
                }
            }
        }

        viewerImageURLs = images
        viewerVideoURLs = videos
        viewerAudioURLs = audios
        viewerAudioTitles = audioTitles.isEmpty ? nil : audioTitles

        if images.isEmpty && videos.isEmpty && audios.isEmpty {
            attachmentLoadError = "Unable to load attachment URLs."
        }
    }

    private func signedURL(bucket: String, path: String, expiresInSeconds: Int) async -> URL? {
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

    // MARK: - Interactions (Save + Comment)

    @ViewBuilder
    private func interactionsCard() -> some View {
        HStack(spacing: 0) {
            Button {
                FeedInteractionStore.toggleHeart(model.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: FeedInteractionStore.isHearted(model.id) ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(width: 1)
                .background(Theme.Colors.cardStroke(colorScheme))

            Button {
                isCommentsPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Comment")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.Colors.cardStroke(colorScheme), lineWidth: 1)
        )
        .cardSurface(padding: 0)
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

    // MARK: - Date + Duration formatting

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

    private func timeAndDateStrings(for date: Date) -> (time: String, date: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.doesRelativeDateFormatting = false

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return (timeFormatter.string(from: date), dateFormatter.string(from: date))
    }

    private func durationString(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let mins = seconds / 60
        let hrs = mins / 60
        let remMins = mins % 60
        if hrs > 0 {
            if remMins == 0 {
                return "\(hrs)h"
            } else {
                return "\(hrs)h \(remMins)m"
            }
        } else {
            return "\(mins)m"
        }
    }
}

private struct BackendThumbCell: View {
    let kind: BackendSessionViewModel.BackendAttachmentRef.Kind
    let url: URL?
    let showViewIcon: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Colors.surface(colorScheme))

            if kind == .image, let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "photo")
                            .imageScale(.large)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Image(systemName: iconName(for: kind))
                    .imageScale(.large)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            if showViewIcon {
                Image(systemName: "eye")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(8)
            }
        }
        .frame(height: 108)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.Colors.cardStroke(colorScheme), lineWidth: 1)
        )
        .clipped()
    }

    private func iconName(for kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> String {
        switch kind {
        case .audio: return "waveform"
        case .video: return "video"
        case .image: return "photo"
        }
    }
}
