// CHANGE-ID: 20260220_212955_AAVAudioTransportParity_ScrubberSmooth_1b7a3d
// SCOPE: AAV AudioPage — add transport controls parity with VideoPage (scrubber, ±10s, mute, AirPlay) and remove hidden waveform scrub gesture; preserve natural-end reset and position-preserving pause; no waveform redesign or routing/backend changes.
// SEARCH-TOKEN: 20260220_212955_AAVAudioTransportParity_ScrubberSmooth_1b7a3d

// CHANGE-ID: 20260220_181209_AAVAudioWaveformEndReset_cc3cbb
// SCOPE: AAV AudioPage — on natural playback end, stop waveform timer, reset playhead/progress to 0, and reset waveform to hard-left; manual pause preserves position (bugfix only; no waveform redesign)
// SEARCH-TOKEN: 20260220_181209_AAVAudioWaveformEndReset_cc3cbb

// CHANGE-ID: 20260220_072500_AAVVideoEndReset_530c66
// SCOPE: AAV VideoPage — on natural playback end, seek to 0 and reset paused/ready state (no UI redesign; manual pause preserves position)
// SEARCH-TOKEN: 20260206_100245_AVVKeysImmutable_079028

// CHANGE-ID: 20260206_095420_AVVInitKeys_1cd203
// SCOPE: Fix AttachmentViewerView initializers to fully initialize new stable-key title properties (audio/video keys + title maps). No UI/layout changes.
// SEARCH-TOKEN: 20260206_095420_AVVInitKeys_1cd203

// CHANGE-ID: 20260206_092154_AttachDisplayNames_94a0e8
// SCOPE: Remote attachment display-name parity: viewer resolves audio/video titles by stable attachment key (not signed URL).
// SEARCH-TOKEN: 20260206_092154_AttachDisplayNames_94a0e8

// CHANGE-ID: 20260114_172800_9F_URLRefresh
// SCOPE: Step 9F Option A — viewer detects signed URL failures and offers calm tap-to-retry which requests a fresh signed URL via injected closure (no backend/schema/social changes).

// CHANGE-ID: 20260114_120500_9E_FIX2
// SCOPE: Fix infinite recursion crash in AttachmentViewerView audio stopPlayback (triggered by rename / stopAllPlayersToggle)

// CHANGE-ID: 20260105_181300-avv-include-thumb-invariant-fix3
// SCOPE: Enforce attachment inclusion↔thumbnail invariants in AttachmentViewerView (⭐ implies 👁; private clears ⭐; per-item optimistic state; eye-slash only in control panel). No UI/layout, backend, schema, or publish/sync changes.

// CHANGE-ID: 20260114_103700_9E
// SCOPE: 9E allow audio/video/image playback from signed HTTPS URLs

import SwiftUI
import AVKit
import AVFoundation

// CHANGE-ID: 20260201_170000_AttachmentPlaybackRouteFix
// SCOPE: Fix AttachmentViewer audio playback to respect current output route (e.g., AirPods) by using .playback without speaker override.
// NOTE: No other UI/logic changes.

struct AttachmentViewerView: View {
    let imageURLs: [URL]
    let audioKeys: [String]
    let audioTitlesByKey: [String: String]
    let videoKeys: [String]
    let videoTitlesByKey: [String: String]
    let audioTitles: [String]?
    let isReadOnly: Bool
    let canShare: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let topButtonSize: CGFloat = 40
    private let fillOpacityLight: CGFloat = 0.96
    private let fillOpacityDark: CGFloat = 0.88
    private let headerSpacing: CGFloat = Theme.Spacing.l

    @State var videoURLs: [URL]
    @State var audioURLs: [URL]
    @State var startIndex: Int
    var themeBackground: Color = Color.clear // inherits app background

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var isPagerInteractable = false
    @State private var pendingDragTranslation: CGFloat = 0
    @State private var hasCommittedOnce: Bool = false
    @State private var localPrivateByKey: [String: Bool] = [:]
    @State private var localFavouriteKey: String? = nil
    @State private var suppressedFavouriteKeys: Set<String> = []
    @State private var cachedURL: URL? = nil
    @State private var isAnyPlayerActive = false
    @State private var stopAllPlayersToggle = false
    @State private var isShowingTrimmer: Bool = false
    @State private var trimURL: URL? = nil
    @State private var trimKind: AttachmentKind? = nil
    @State private var mediaMutationTick: Int = 0

    // Storage Safety: Track any temp surrogate files created by the viewer (e.g., posters, exported shares)
    @State private var tempFilesToCleanup: Set<URL> = []
    @State private var isRenaming: Bool = false
    @State private var renameTargetURL: URL? = nil
    @State private var renameText: String = ""

    // Viewer-first title overrides so the UI updates immediately after rename.
    @State private var localTitleOverrides: [URL: String] = [:]

    // New enum for replace strategy
    enum ReplaceStrategy { case immediate, deferred }
    var replaceStrategy: ReplaceStrategy = .immediate

    private func registerTemp(_ url: URL?) {
        guard let url else { return }
        if url.isFileURL { tempFilesToCleanup.insert(url) }
    }

    private func cleanupTempFiles() {
        let fm = FileManager.default
        for url in tempFilesToCleanup {
            if fm.fileExists(atPath: url.path) {
                do { try fm.removeItem(at: url) } catch { /* idempotent: ignore */ }
                #if DEBUG
                print("[AttachmentViewer] Removed temp surrogate: \(url.lastPathComponent)")
                #endif
            }
        }
        tempFilesToCleanup.removeAll()
    }

    var onDelete: ((URL) -> Void)? = nil
    /// Optional title resolver used for viewer display + rename prefill.
    /// Must honor existing app title stores (caller responsibility).
    var titleForURL: ((URL, AttachmentKind) -> String?)? = nil
    /// Preferred rename callback (viewer-first). Empty string means "clear title" for video.
    var onRename: ((URL, String, AttachmentKind) -> Void)? = nil
    /// Legacy callback kept for compatibility during rollout.
    var onRenameLegacy: ((URL, String) -> Void)? = nil
    var onFavourite: ((URL) -> Void)? = nil
    var isFavourite: ((URL) -> Bool)? = nil
    var onTogglePrivacy: ((URL) -> Void)? = nil
    var isPrivate: ((URL) -> Bool)? = nil
    var onReplaceAttachment: ((URL, URL, AttachmentKind) -> Void)? = nil
    var onSaveAsNewAttachment: ((URL, AttachmentKind) -> Void)? = nil
    var onSaveAsNewAttachmentFromSource: ((URL, URL, AttachmentKind) -> Void)? = nil

    /// Step 9F (Option A): Ask the presenter/store for a fresh signed URL when remote load/playback fails.
    /// Contract: viewer supplies the AttachmentKind and the *original* URL it was given; the presenter may map that URL
    /// back to its attachment reference (bucket/path) and return a new signed URL.
    var onRequestFreshURL: ((AttachmentKind, URL) async -> Result<URL, Error>)? = nil

    // Step 9F local resilience state (viewer-owned; no backend state)
    @State private var failedKeys: Set<String> = []
    @State private var isRefreshingKeys: Set<String> = []
    @State private var errorMessageByKey: [String: String] = [:]
    @State private var refreshedURLByKey: [String: URL] = [:]

    private func effectiveURL(for original: URL) -> URL {
        refreshedURLByKey[urlKey(original)] ?? original
    }

    private func markFailed(_ original: URL, message: String? = nil) {
        let k = urlKey(original)
        failedKeys.insert(k)
        if let m = message, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessageByKey[k] = m
        }
    }

    private func clearFailure(_ original: URL) {
        let k = urlKey(original)
        failedKeys.remove(k)
        errorMessageByKey.removeValue(forKey: k)
    }

    private func isFailed(_ original: URL) -> Bool {
        failedKeys.contains(urlKey(original))
    }

    private func isRefreshing(_ original: URL) -> Bool {
        isRefreshingKeys.contains(urlKey(original))
    }

    private func errorMessage(_ original: URL) -> String? {
        errorMessageByKey[urlKey(original)]
    }

    private func requestFreshURL(for original: URL, kind: AttachmentKind) {
        guard let onRequestFreshURL else { return }
        let k = urlKey(original)
        guard !isRefreshingKeys.contains(k) else { return }

        isRefreshingKeys.insert(k)

        Task { @MainActor in
            let result = await onRequestFreshURL(kind, original)
            switch result {
            case .success(let newURL):
                refreshedURLByKey[k] = newURL
                clearFailure(original)
                mediaMutationTick &+= 1 // force page re-render
            case .failure(let err):
                markFailed(original, message: String(describing: err))
            }
            isRefreshingKeys.remove(k)
        }
    }


    
    init(
        imageURLs: [URL],
        videoURLs: [URL],
        audioURLs: [URL],
        startIndex: Int,
        audioKeys: [String] = [],
        audioTitlesByKey: [String: String] = [:],
        videoKeys: [String] = [],
        videoTitlesByKey: [String: String] = [:],
        audioTitles: [String]? = nil,
        isReadOnly: Bool,
        canShare: Bool,
        themeBackground: Color = Color.clear,
        onDelete: ((URL) -> Void)? = nil,
        titleForURL: ((URL, AttachmentKind) -> String?)? = nil,
        onRename: ((URL, String, AttachmentKind) -> Void)? = nil,
        onRenameLegacy: ((URL, String) -> Void)? = nil,
        onFavourite: ((URL) -> Void)? = nil,
        isFavourite: ((URL) -> Bool)? = nil,
        onTogglePrivacy: ((URL) -> Void)? = nil,
        isPrivate: ((URL) -> Bool)? = nil,
        onReplaceAttachment: ((URL, URL, AttachmentKind) -> Void)? = nil,
        onSaveAsNewAttachment: ((URL, AttachmentKind) -> Void)? = nil,
        onSaveAsNewAttachmentFromSource: ((URL, URL, AttachmentKind) -> Void)? = nil,
        onRequestFreshURL: ((AttachmentKind, URL) async -> Result<URL, Error>)? = nil
    ) {
        self.imageURLs = imageURLs
        self.audioKeys = audioKeys
        self.audioTitlesByKey = audioTitlesByKey
        self.videoKeys = videoKeys
        self.videoTitlesByKey = videoTitlesByKey
        self.audioTitles = audioTitles
        self.isReadOnly = isReadOnly
        self.canShare = canShare
        self.themeBackground = themeBackground

        self.onDelete = onDelete
        self.titleForURL = titleForURL
        self.onRename = onRename
        self.onRenameLegacy = onRenameLegacy
        self.onFavourite = onFavourite
        self.isFavourite = isFavourite
        self.onTogglePrivacy = onTogglePrivacy
        self.isPrivate = isPrivate
        self.onReplaceAttachment = onReplaceAttachment
        self.onSaveAsNewAttachment = onSaveAsNewAttachment
        self.onSaveAsNewAttachmentFromSource = onSaveAsNewAttachmentFromSource
        self.onRequestFreshURL = onRequestFreshURL

        self._videoURLs = State(initialValue: videoURLs)
        self._audioURLs = State(initialValue: audioURLs)
        self._startIndex = State(initialValue: startIndex)
    }

private func currentURL() -> URL? {
        imageURLs.indices.contains(currentIndex) ? imageURLs[currentIndex] : nil
    }


    private func urlKey(_ url: URL) -> String {
        // URL is our stable handle inside the viewer (hosts can map URL→ID however they like).
        url.absoluteString
    }

    private func seedPrivacy(for url: URL) {
        localPrivateByKey[urlKey(url)] = isPrivate?(url) ?? true
    }

    private func optimisticIsPrivate(_ url: URL) -> Bool {
        localPrivateByKey[urlKey(url)] ?? (isPrivate?(url) ?? true)
    }

    private func setOptimisticPrivacy(_ isPrivate: Bool, for url: URL) {
        localPrivateByKey[urlKey(url)] = isPrivate
    }

    private func seedFavouriteIfNeeded() {
        guard localFavouriteKey == nil else { return }
        // Seed from host once so the star reflects whatever the presenter considers "thumbnail".
        // Do not seed a favourite for an attachment that is currently private (⭐ must never be private),
        // and respect any local suppression (e.g., user explicitly turned ⭐ off in the viewer).
        for item in media {
            let k = urlKey(item.url)
            if suppressedFavouriteKeys.contains(k) { continue }
            if optimisticIsPrivate(item.url) { continue }
            if (isFavourite?(item.url) ?? false) {
                localFavouriteKey = k
                break
            }
        }
    }

    private func optimisticIsFavourite(_ url: URL) -> Bool {
        let k = urlKey(url)
        if suppressedFavouriteKeys.contains(k) { return false }
        // Hard rule: ⭐ must never be private.
        if optimisticIsPrivate(url) { return false }
        if let key = localFavouriteKey {
            return key == k
        }
        return isFavourite?(url) ?? false
    }


    private var currentAttachmentKind: AttachmentKind {
        guard media.indices.contains(currentIndex) else { return .file }
        return media[currentIndex].kind
    }


    // MARK: - Capability gating
    private var canDelete: Bool {
        !isReadOnly && onDelete != nil
    }
    private var canPrivacy: Bool {
        guard !isReadOnly else { return false }
        return (isPrivate != nil) && (onTogglePrivacy != nil)
    }
    private var canFavourite: Bool {
        guard !isReadOnly else { return false }
        return (isFavourite != nil) && (onFavourite != nil)
    }
    private func canRename(for kind: AttachmentKind, url: URL) -> Bool {
        guard !isReadOnly else { return false }
        guard kind == .audio || kind == .video else { return false }
        // Require both a title source and a rename handler (either modern or legacy)
        let hasTitleSource = (titleForURL != nil)
        let hasRenameHandler = (onRename != nil) || (onRenameLegacy != nil)
        return hasTitleSource && hasRenameHandler
    }
    private func canTrim(for kind: AttachmentKind) -> Bool {
        guard !isReadOnly else { return false }
        guard kind == .audio || kind == .video else { return false }
        return (onReplaceAttachment != nil) || (onSaveAsNewAttachment != nil)
    }
    private var canShowShare: Bool { canShare }

    
    // MARK: - Initializers

    /// Preferred initializer (viewer-first) with explicit defaults to avoid memberwise ordering traps.
    init(
        imageURLs: [URL],
        startIndex: Int,
        themeBackground: Color = Color.clear,
        videoURLs: [URL] = [],
        audioURLs: [URL] = [],
        audioKeys: [String] = [],
        audioTitlesByKey: [String: String] = [:],
        videoKeys: [String] = [],
        videoTitlesByKey: [String: String] = [:],
        audioTitles: [String]? = nil,
        onDelete: ((URL) -> Void)? = nil,
        titleForURL: ((URL, AttachmentKind) -> String?)? = nil,
        onRename: ((URL, String, AttachmentKind) -> Void)? = nil,
        onRenameLegacy: ((URL, String) -> Void)? = nil,
        onFavourite: ((URL) -> Void)? = nil,
        isFavourite: ((URL) -> Bool)? = nil,
        onTogglePrivacy: ((URL) -> Void)? = nil,
        isPrivate: ((URL) -> Bool)? = nil,
        onReplaceAttachment: ((URL, URL, AttachmentKind) -> Void)? = nil,
        onSaveAsNewAttachment: ((URL, AttachmentKind) -> Void)? = nil,
        onSaveAsNewAttachmentFromSource: ((URL, URL, AttachmentKind) -> Void)? = nil,
        isReadOnly: Bool = false,
        canShare: Bool = true,
        replaceStrategy: ReplaceStrategy = .immediate
    ) {
        #if DEBUG
        print("[AttachmentViewer] init image=\(imageURLs.count) video=\(videoURLs.count) audio=\(audioURLs.count) startIndex=\(startIndex)")
        #endif

        self.imageURLs = imageURLs
        self._videoURLs = State(initialValue: videoURLs)
        self._audioURLs = State(initialValue: audioURLs)
        self.audioKeys = audioKeys
        self.audioTitlesByKey = audioTitlesByKey
        self.videoKeys = videoKeys
        self.videoTitlesByKey = videoTitlesByKey
        self.audioTitles = audioTitles
        self._startIndex = State(initialValue: startIndex)
        self._currentIndex = State(initialValue: startIndex)
        self.themeBackground = themeBackground
        self.onDelete = onDelete
        self.titleForURL = titleForURL
        self.onRename = onRename
        self.onRenameLegacy = onRenameLegacy
        self.onFavourite = onFavourite
        self.isFavourite = isFavourite
        self.onTogglePrivacy = onTogglePrivacy
        self.isPrivate = isPrivate
        self.onReplaceAttachment = onReplaceAttachment
        self.onSaveAsNewAttachment = onSaveAsNewAttachment
        self.onSaveAsNewAttachmentFromSource = onSaveAsNewAttachmentFromSource
        self.isReadOnly = isReadOnly
        self.canShare = canShare
        self.replaceStrategy = replaceStrategy
    }

    /// Legacy initializer kept during rollout (2-arg onRename).
    init(
        imageURLs: [URL],
        startIndex: Int,
        themeBackground: Color = Color.clear,
        videoURLs: [URL] = [],
        audioURLs: [URL] = [],
        audioKeys: [String] = [],
        audioTitlesByKey: [String: String] = [:],
        videoKeys: [String] = [],
        videoTitlesByKey: [String: String] = [:],
        audioTitles: [String]? = nil,
        onDelete: ((URL) -> Void)? = nil,
        onRename: ((URL, String) -> Void)? = nil,
        onFavourite: ((URL) -> Void)? = nil,
        isFavourite: ((URL) -> Bool)? = nil,
        onTogglePrivacy: ((URL) -> Void)? = nil,
        isPrivate: ((URL) -> Bool)? = nil,
        onReplaceAttachment: ((URL, URL, AttachmentKind) -> Void)? = nil,
        onSaveAsNewAttachment: ((URL, AttachmentKind) -> Void)? = nil,
        onSaveAsNewAttachmentFromSource: ((URL, URL, AttachmentKind) -> Void)? = nil,
        replaceStrategy: ReplaceStrategy = .immediate
    ) {
        self.init(
            imageURLs: imageURLs,
            startIndex: startIndex,
            themeBackground: themeBackground,
            videoURLs: videoURLs,
            audioURLs: audioURLs,
            audioKeys: audioKeys,
            audioTitlesByKey: audioTitlesByKey,
            videoKeys: videoKeys,
            videoTitlesByKey: videoTitlesByKey,
            audioTitles: audioTitles,
            onDelete: onDelete,
            titleForURL: nil,
            onRename: nil,

            onRenameLegacy: onRename,
            onFavourite: onFavourite,
            isFavourite: isFavourite,
            onTogglePrivacy: onTogglePrivacy,
            isPrivate: isPrivate,
            onReplaceAttachment: onReplaceAttachment,
            onSaveAsNewAttachment: onSaveAsNewAttachment,
            onSaveAsNewAttachmentFromSource: onSaveAsNewAttachmentFromSource,
            isReadOnly: false,
            canShare: true,
            replaceStrategy: replaceStrategy
        )
    }

    struct MediaAttachment: Identifiable {
        let id = UUID()
        let kind: AttachmentKind
        let url: URL
    }

    private var media: [MediaAttachment] {
        var items: [MediaAttachment] = []
        items.append(contentsOf: imageURLs.map { MediaAttachment(kind: .image, url: $0) })
        items.append(contentsOf: videoURLs.map { MediaAttachment(kind: .video, url: $0) })
        items.append(contentsOf: audioURLs.map { MediaAttachment(kind: .audio, url: $0) })
        return items
    }


    // Proxy to resolve audio title from arrays passed into the viewer
    static func resolvedAudioTitleProxy(url: URL, audioURLs: [URL], audioTitles: [String]?) -> String? {
        guard let titles = audioTitles, titles.count == audioURLs.count,
              let idx = audioURLs.firstIndex(of: url) else { return nil }
        let t = titles[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }


    

    private static func resolvedTitleByStableKey(
        url: URL,
        kind: AttachmentKind,
        urls: [URL],
        keys: [String]?,
        titlesByKey: [String: String]?
    ) -> String? {
        guard let keys, let titlesByKey else { return nil }
        guard keys.count == urls.count, let idx = urls.firstIndex(of: url) else { return nil }
        let key = keys[idx]
        let t = (titlesByKey[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

// MARK: - Title resolution

    private func normalizedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Resolve a display title for a given URL + kind.
    /// Order:
    /// 1) local override (just edited)
    /// 2) titleForURL callback (caller-supplied source of truth)
    /// 3) legacy audioTitles proxy (audio only)
    /// 4) nil (no title) — video has no fallback by design
    private func resolvedTitle(for url: URL, kind: AttachmentKind) -> String? {
        if let ov = normalizedTitle(localTitleOverrides[url]) { return ov }

        if let t = normalizedTitle(titleForURL?(url, kind)) { return t }

        if kind == .audio, let t = normalizedTitle(Self.resolvedTitleByStableKey(url: url, kind: kind, urls: audioURLs, keys: audioKeys, titlesByKey: audioTitlesByKey)) { return t }
        if kind == .video, let t = normalizedTitle(Self.resolvedTitleByStableKey(url: url, kind: kind, urls: videoURLs, keys: videoKeys, titlesByKey: videoTitlesByKey)) { return t }

        if kind == .audio, let t = normalizedTitle(
            Self.resolvedAudioTitleProxy(url: url, audioURLs: audioURLs, audioTitles: audioTitles)
        ) { return t }

        return nil
    }

    private var hasRenameCapability: Bool {
        onRename != nil || onRenameLegacy != nil
    }

    var body: some View {
        #if DEBUG
        let _ = {
            let count = media.count
            print("[AttachmentViewer] body initial media.count=\(count) currentIndex=\(currentIndex)")
            return 0
        }()
        #endif

        ZStack {
            Color.clear.appBackground().ignoresSafeArea()

            GeometryReader { proxy in
                TabView(selection: $currentIndex) {
                    ForEach(media.indices, id: \.self) { i in
                        MediaPage(
                            attachment: media[i],
                            isAnyPlayerActive: $isAnyPlayerActive,
                            onRequestStopAll: $stopAllPlayersToggle,
                            background: themeBackground,
                            audioURLs: audioURLs,
                            audioTitles: audioTitles,
                            titleForURL: { url, kind in
                                resolvedTitle(for: url, kind: kind)
                            },
                            effectiveURL: { original in
                                effectiveURL(for: original)
                            },
                            isFailed: { original in
                                isFailed(original)
                            },
                            isRefreshing: { original in
                                isRefreshing(original)
                            },
                            errorMessage: { original in
                                errorMessage(original)
                            },
                            markFailed: { original, message in
                                markFailed(original, message: message)
                            },
                            clearFailure: { original in
                                clearFailure(original)
                            },
                            requestFreshURL: { original, kind in
                                requestFreshURL(for: original, kind: kind)
                            }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .tag(i)
                    }
                }
                .id(mediaMutationTick)
                .frame(width: proxy.size.width, height: proxy.size.height) // <-- key
                .contentShape(Rectangle()) // full-area swipe target
                .tabViewStyle(.page(indexDisplayMode: .never))
                .allowsHitTesting(isPagerInteractable)
                .onChange(of: currentIndex) { oldValue, newValue in
                    guard !media.isEmpty else {
                        currentIndex = 0
                        return
                    }
                    let upper = media.count - 1
                    let clamped = min(max(newValue, 0), upper)
                    if clamped != newValue {
                        currentIndex = clamped
                        return
                    }
                    DispatchQueue.main.async {
                        if currentIndex == clamped {
                            currentIndex = clamped
                        }
                        hasCommittedOnce = true
                    }
                    prefetchNeighbors(around: clamped)
                    // Stop any playing media when page changes
                    stopAllPlayersToggle.toggle()
                    if media.indices.contains(clamped) {
                        let url = media[clamped].url
                        cachedURL = url
                        seedPrivacy(for: url)
                        // Note: Private items should not be considered as default thumbnail candidates by the presenter.
                    }
                }
                .onAppear {
                    let idx: Int
                    if media.isEmpty {
                        idx = 0
                    } else {
                        let upper = media.count - 1
                        idx = min(max(startIndex, 0), upper)
                    }
                    currentIndex = idx
                    DispatchQueue.main.async { currentIndex = idx }
                    prefetchNeighbors(around: idx)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        currentIndex = idx
                        isPagerInteractable = true
                    }
                    if media.indices.contains(idx) {
                        let url = media[idx].url
                        cachedURL = url
                        seedPrivacy(for: url)
                    }
                }
            }

            // Top controls
            VStack {
                HStack {
                    Button {
                        stopAllPlayersToggle.toggle()
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                .shadow(
                                    color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15),
                                    radius: 2,
                                    y: 1
                                )
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: topButtonSize, height: topButtonSize)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Spacer()

                    if media.indices.contains(currentIndex) {
                        let currentURL = media[currentIndex].url
                        let _ = seedFavouriteIfNeeded()
                        let isFav = optimisticIsFavourite(currentURL)
                        let isPriv = optimisticIsPrivate(currentURL)
                        let currentAttachmentKind = media[currentIndex].kind

                        HStack(spacing: headerSpacing) {
                            if canFavourite {
                                Button {
                                    let url = currentURL
                                    let key = urlKey(url)
                                    let isFavNow = optimisticIsFavourite(url)

                                    if isFavNow {
                                        // Turning ⭐ OFF does not imply removing 👁 (inclusion stays as-is).
                                        localFavouriteKey = nil
                                        suppressedFavouriteKeys.insert(key)
                                        onFavourite?(url)
                                    } else {
                                        // Turning ⭐ ON ⇒ must be included.
                                        if optimisticIsPrivate(url) {
                                            setOptimisticPrivacy(false, for: url)
                                            onTogglePrivacy?(url)
                                        }

                                        // Optimistically set as the current favourite.
                                        suppressedFavouriteKeys.remove(key)

                                        localFavouriteKey = key
                                        onFavourite?(url)
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.thinMaterial)
                                            .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                            .shadow(
                                                color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15),
                                                radius: 2,
                                                y: 1
                                            )
                                        Image(systemName: isFav ? "star.fill" : "star")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .frame(width: topButtonSize, height: topButtonSize)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isFav ? "Unfavourite attachment" : "Favourite attachment")
                            }

                            if canPrivacy && !isReadOnly {
                                Button {
                                    let url = currentURL
                                    let wasPrivate = optimisticIsPrivate(url)
                                    let willBePrivate = !wasPrivate

                                    if willBePrivate {
                                        // Invariant: private ⇒ cannot remain thumbnail.
                                        if optimisticIsFavourite(url) {
                                            localFavouriteKey = nil
                                            suppressedFavouriteKeys.insert(urlKey(url))
                                            onFavourite?(url)
                                        }
                                        setOptimisticPrivacy(true, for: url)
                                        onTogglePrivacy?(url)
                                    } else {
                                        setOptimisticPrivacy(false, for: url)
                                        onTogglePrivacy?(url)
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.thinMaterial)
                                            .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                            .shadow(
                                                color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15),
                                                radius: 2,
                                                y: 1
                                            )
                                        Image(systemName: isPriv ? "eye.slash" : "eye")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .frame(width: topButtonSize, height: topButtonSize)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isPriv ? "Only visible to you" : "Included in post")
                            }

                            if canRename(for: currentAttachmentKind, url: currentURL) {
                                Button {
                                    let url = currentURL
                                    renameTargetURL = url
                                    let kind = currentAttachmentKind
                                    if kind == .video {
                                        renameText = resolvedTitle(for: url, kind: .video) ?? ""
                                    } else {
                                        renameText = resolvedTitle(for: url, kind: .audio)
                                            ?? url.deletingPathExtension().lastPathComponent
                                    }
                                    isRenaming = true
                                    stopAllPlayersToggle.toggle()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.thinMaterial)
                                            .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                            .shadow(
                                                color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15),
                                                radius: 2,
                                                y: 1
                                            )
                                        Image(systemName: "pencil")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .frame(width: topButtonSize, height: topButtonSize)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Rename attachment")
                            }

                            if canTrim(for: currentAttachmentKind) {
                                Button {
                                    trimURL = currentURL
                                    trimKind = currentAttachmentKind
                                    isShowingTrimmer = true
                                    stopAllPlayersToggle.toggle()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.thinMaterial)
                                            .opacity(
                                                colorScheme == .dark ? fillOpacityDark : fillOpacityLight
                                            )
                                            .shadow(
                                                color: .black.opacity(
                                                    colorScheme == .dark ? 0.35 : 0.15
                                                ),
                                                radius: 2,
                                                y: 1
                                            )
                                        Image(systemName: "scissors")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .frame(width: topButtonSize, height: topButtonSize)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(currentAttachmentKind == .video ? "Trim video" : "Trim audio")
                                .accessibilityHint("Open trimmer to shorten this recording")
                            }

                            if canDelete {
                                Button {
                                    let url = currentURL
                                    onDelete?(url)
                                    stopAllPlayersToggle.toggle()
                                    dismiss()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.thinMaterial)
                                            .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                            .shadow(
                                                color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15),
                                                radius: 2,
                                                y: 1
                                            )
                                        Image(systemName: "trash")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .frame(width: topButtonSize, height: topButtonSize)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete attachment")
                            }

                            if canShowShare {
                                ShareLink(item: currentURL) {
                                    ZStack {
                                        Circle()
                                            .fill(.thinMaterial)
                                            .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                            .shadow(
                                                color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15),
                                                radius: 2,
                                                y: 1
                                            )
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .frame(width: topButtonSize, height: topButtonSize)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .onAppear {
                                    // If a temp surrogate is used as the share item, ensure we clean it up on dismiss
                                    let tmp = FileManager.default.temporaryDirectory
                                    if currentURL.isFileURL, currentURL.path.hasPrefix(tmp.path) {
                                        registerTemp(currentURL)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)

                // Video title (presentation-only)
                if media.indices.contains(currentIndex) {
                    let att = media[currentIndex]
                    if att.kind == .video {
                        let rawTitle = resolvedTitle(for: att.url, kind: .video)
                        let trimmed = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !trimmed.isEmpty {
                            // Strip common file extensions for display only
                            let display: String = {
                                let lower = trimmed.lowercased()
                                if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v") || lower.hasSuffix(".avi") {
                                    return String(trimmed.split(separator: ".").dropLast().joined(separator: "."))
                                }
                                return trimmed
                            }()
                            Text(display)
                                .font(.callout)
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .padding(.top, 6)
                                .padding(.horizontal, Theme.Spacing.l)
                                .accessibilityLabel("Video title: \(display)")
                        }
                    }
                }

                Spacer()
            }
            .zIndex(2) // ensure buttons are above the pager
            .allowsHitTesting(true)
        }
        .onAppear {
            // CHANGE-ID: 20260201_170000_AttachmentPlaybackRouteFix
            // SCOPE: Attachment audio playback should respect current output route (e.g., AirPods) and never force speaker.
            // Use a playback session without speaker override; keep behaviour otherwise unchanged.
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                // Non-fatal: fall back silently
            }
        }
        .onDisappear {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } catch { }
            // Storage Safety: Ensure any temp surrogates created by the viewer are removed on dismiss
            cleanupTempFiles()
        }
        .sheet(isPresented: $isRenaming, onDismiss: {
            renameTargetURL = nil
            renameText = ""
        }) {
            NavigationStack {
                VStack(spacing: Theme.Spacing.m) {
                    Text("Rename attachment")
                        .font(.headline)
                        .padding(.top, Theme.Spacing.l)

                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, Theme.Spacing.l)

                    Spacer()

                    HStack(spacing: Theme.Spacing.m) {
                        Button("Cancel") {
                            isRenaming = false
                            renameTargetURL = nil
                            renameText = ""
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Button("Save") {
                            guard let target = renameTargetURL else {
                                isRenaming = false
                                renameTargetURL = nil
                                renameText = ""
                                return
                            }

                            let kind = currentAttachmentKind
                            let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)

                            // Audio: empty is a no-op (we never want to show UUID/filenames as "cleared").
                            // Video: empty means "clear title".
                            if kind == .audio, trimmed.isEmpty {
                                isRenaming = false
                                renameTargetURL = nil
                                renameText = ""
                                return
                            }

                            // Optimistic UI update
                            if trimmed.isEmpty {
                                localTitleOverrides.removeValue(forKey: target)
                            } else {
                                localTitleOverrides[target] = trimmed
                            }

                            if let cb = onRename {
                                cb(target, trimmed, kind)
                            } else if let cbLegacy = onRenameLegacy {
                                cbLegacy(target, trimmed)
                            }

                            isRenaming = false
                            renameTargetURL = nil
                            renameText = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.l)
                }
            }
        }

        .sheet(isPresented: $isShowingTrimmer, onDismiss: {
            isShowingTrimmer = false
            trimURL = nil
            trimKind = nil
        }) {
            if let url = trimURL, let kind = trimKind {
                MediaTrimView(
                    assetURL: url,
                    mediaType: kind == .audio ? .audio : .video,
                    onCancel: {
                        isShowingTrimmer = false
                        trimURL = nil
                        trimKind = nil
                    },
                    onSaveAsNewAttachment: { tempURL, _ in
                        guard onSaveAsNewAttachment != nil || onSaveAsNewAttachmentFromSource != nil else { return }
                        guard let currentMediaIndex = media.firstIndex(where: { $0.url == url }) else {
                            isShowingTrimmer = false
                            trimURL = nil
                            trimKind = nil
                            return
                        }
                        let suggestedName = url
                            .deletingPathExtension()
                            .lastPathComponent
                            .isEmpty ? "Trimmed" : url.deletingPathExtension().lastPathComponent
                        let globalKind: AttachmentKind = kind
                        if let newPath = try? AttachmentStore.adoptTempExport(
                            tempURL,
                            suggestedName: suggestedName,
                            kind: globalKind
                        ) {
                            let newURL = URL(fileURLWithPath: newPath)
                            switch kind {
                            case .video:
                                var newVideos = videoURLs
                                let insertIndex = currentMediaIndex - imageURLs.count
                                if insertIndex >= 0 && insertIndex <= newVideos.count {
                                    newVideos.insert(newURL, at: insertIndex + 1)
                                } else {
                                    newVideos.append(newURL)
                                }
                                self.videoURLs = newVideos
                                currentIndex = currentIndex + 1
                            case .audio:
                                var newAudios = audioURLs
                                let insertIndex = currentMediaIndex - imageURLs.count - videoURLs.count
                                if insertIndex >= 0 && insertIndex <= newAudios.count {
                                    newAudios.insert(newURL, at: insertIndex + 1)
                                } else {
                                    newAudios.append(newURL)
                                }
                                self.audioURLs = newAudios
                                currentIndex = currentIndex + 1
                            case .image: break
                            case .file: break
                            }
                            cachedURL = newURL
                            stopAllPlayersToggle.toggle()
                            #if canImport(UIKit)
                            if kind == .video {
                                _ = AttachmentStore.generateVideoPoster(url: newURL)
                            }
                            #endif
                            mediaMutationTick += 1

                            if let cb2 = onSaveAsNewAttachmentFromSource {
                                cb2(url, newURL, globalKind)
                            }
                            if let cb = onSaveAsNewAttachment {
                                cb(newURL, globalKind)
                            }
                        }
                        isShowingTrimmer = false
                        trimURL = nil
                        trimKind = nil
                    },
                    onReplaceAttachment: { originalURL, tempURL, _ in
                        guard onReplaceAttachment != nil else { return }
                        guard let currentMediaIndex = media.firstIndex(where: { $0.url == originalURL }),
                              originalURL.isFileURL else {
                            isShowingTrimmer = false
                            trimURL = nil
                            trimKind = nil
                            return
                        }
                        let originalPath = originalURL.path
                        let globalKind: AttachmentKind = kind

                        switch replaceStrategy {
                        case .immediate:
                            if let finalPath = try? AttachmentStore.replaceAttachmentFile(
                                withTempURL: tempURL,
                                forExistingPath: originalPath,
                                kind: globalKind
                            ) {
                                let finalURL = URL(fileURLWithPath: finalPath)
                                switch kind {
                                case .video:
                                    var newVideos = videoURLs
                                    let videoIndex = currentMediaIndex - imageURLs.count
                                    if videoIndex >= 0 && videoIndex < newVideos.count {
                                        newVideos[videoIndex] = finalURL
                                    }
                                    self.videoURLs = newVideos
                                    let upper = media.count - 1
                                    currentIndex = min(max(currentIndex, 0), max(upper, 0))
                                case .audio:
                                    var newAudios = audioURLs
                                    if currentMediaIndex - imageURLs.count - videoURLs.count < newAudios.count {
                                        let audioIndex = currentMediaIndex - imageURLs.count - videoURLs.count
                                        if audioIndex >= 0 && audioIndex < newAudios.count {
                                            newAudios[audioIndex] = finalURL
                                        }
                                    }
                                    self.audioURLs = newAudios
                                    let upper = media.count - 1
                                    currentIndex = min(max(currentIndex, 0), max(upper, 0))
                                case .image: break
                            case .file: break
                                }
                                cachedURL = finalURL
                                onReplaceAttachment?(url, finalURL, globalKind)
                                stopAllPlayersToggle.toggle()
                                #if canImport(UIKit)
                                if kind == .video {
                                    _ = AttachmentStore.generateVideoPoster(url: finalURL)
                                }
                                #endif
                                mediaMutationTick += 1
                            }
                        case .deferred:
                            let finalURL = tempURL
                            switch kind {
                            case .video:
                                var newVideos = videoURLs
                                let videoIndex = currentMediaIndex - imageURLs.count
                                if videoIndex >= 0 && videoIndex < newVideos.count {
                                    newVideos[videoIndex] = finalURL
                                }
                                self.videoURLs = newVideos
                            case .audio:
                                var newAudios = audioURLs
                                let audioIndex = currentMediaIndex - imageURLs.count - videoURLs.count
                                if audioIndex >= 0 && audioIndex < newAudios.count {
                                    newAudios[audioIndex] = finalURL
                                }
                                self.audioURLs = newAudios
                            case .image: break
                            case .file: break
                            }
                            cachedURL = finalURL
                            onReplaceAttachment?(url, finalURL, globalKind)
                            stopAllPlayersToggle.toggle()
                            #if canImport(UIKit)
                            if kind == .video {
                                _ = AttachmentStore.generateVideoPoster(url: finalURL)
                            }
                            #endif
                            mediaMutationTick += 1
                        }

                        isShowingTrimmer = false
                        trimURL = nil
                        trimKind = nil
                    }
                )
            }
        }
    }

    /// Prefetch only image thumbnails around given index to improve scroll performance
    private func prefetchNeighbors(around index: Int) {
        guard !media.isEmpty else { return }
        let neighbors = [index - 1, index, index + 1].filter { media.indices.contains($0) }
        for i in neighbors {
            guard media.indices.contains(i), media[i].kind == .image else { continue }
            let url = media[i].url as NSURL
            if _ImageCache.shared.cache.object(forKey: url) != nil { continue }
            Task(priority: .background) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url as URL)
                    if let img = UIImage(data: data) {
                        _ImageCache.shared.cache.setObject(img, forKey: url)
                    }
                } catch {
                    // ignore prefetch failures
                }
            }
        }
    }
}

private final class _ImageCache {
    static let shared = _ImageCache()
    let cache = NSCache<NSURL, UIImage>()
}


// MARK: - Async URL Image Loader (no blocking on main)
private struct URLImageView: View {
    let url: URL
    var background: Color = Color.clear
    var onFailure: (() -> Void)? = nil
    var onSuccess: (() -> Void)? = nil
    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Track the load task so we can cancel on disappear/reuse
            loadTask = Task { await loadIfNeeded() }
            await loadTask?.value
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .background(Color.clear)
        .ignoresSafeArea()
    }

    @MainActor
    private func setImage(_ image: UIImage?) {
        self.uiImage = image
    }

    private func loadIfNeeded() async {
        if Task.isCancelled { return }
        if uiImage != nil || isLoading { return }
        isLoading = true
        let key = url as NSURL
        if let cached = _ImageCache.shared.cache.object(forKey: key) {
            await setImage(cached)
            if Task.isCancelled { return }
            isLoading = false
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return }
            if let img = UIImage(data: data) {
                await setImage(img)
                _ImageCache.shared.cache.setObject(img, forKey: key)
                onSuccess?()
            } else {
                await setImage(UIImage(systemName: "photo"))
                onFailure?()
            }
        } catch {
            await setImage(UIImage(systemName: "photo"))
            onFailure?()
        }
        isLoading = false
    }
}

// MARK: - Media Router & Pages
private struct MediaPage: View {
    let attachment: AttachmentViewerView.MediaAttachment
    @Binding var isAnyPlayerActive: Bool
    @Binding var onRequestStopAll: Bool
    var background: Color
    let audioURLs: [URL]
    let audioTitles: [String]?
    let titleForURL: ((URL, AttachmentKind) -> String?)?

    // Step 9F: resilience hooks
    let effectiveURL: (URL) -> URL
    let isFailed: (URL) -> Bool
    let isRefreshing: (URL) -> Bool
    let errorMessage: (URL) -> String?
    let markFailed: (URL, String?) -> Void
    let clearFailure: (URL) -> Void
    let requestFreshURL: (URL, AttachmentKind) -> Void

    var body: some View {
        let original = attachment.url
        let kind = attachment.kind

        if isFailed(original) {
            RetryPane(
                isRefreshing: isRefreshing(original),
                message: errorMessage(original),
                onRetry: { requestFreshURL(original, kind) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
        } else {
            switch kind {
            case .image:
                ImagePage(
                    url: effectiveURL(original),
                    background: background
                )
            case .video:
                VideoPage(
                    url: effectiveURL(original),
                    isAnyPlayerActive: $isAnyPlayerActive,
                    onRequestStopAll: $onRequestStopAll,
                    onFailure: { markFailed(original, "Video failed to load") }
                )
            case .audio:
                let displayTitle: String? = {
                    let raw = titleForURL?(original, .audio)
                    let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }()
                AudioPage(
                    url: effectiveURL(original),
                    isAnyPlayerActive: $isAnyPlayerActive,
                    onRequestStopAll: $onRequestStopAll,
                    displayTitle: displayTitle,
                    onFailure: { markFailed(original, "Audio failed to load") }
                )
            case .file:
                EmptyView()
            }
        }
    }
}

private struct RetryPane: View {
    let isRefreshing: Bool
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(isRefreshing ? "Refreshing…" : "Failed to load — tap to retry")
                .font(Theme.Text.meta.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondaryText)
            if let m = message, !m.isEmpty {
                Text(m)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            Button(action: onRetry) {
                Text(isRefreshing ? "Refreshing…" : "Retry")
                    .font(Theme.Text.meta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.l)
    }
}

private struct ImagePage: View {
    let url: URL
    var background: Color
    var body: some View { URLImageView(url: url, background: background) }
}

private struct VideoPage: View {
    let url: URL
    @Binding var isAnyPlayerActive: Bool
    @Binding var onRequestStopAll: Bool
    var onFailure: (() -> Void)? = nil
    @State private var player: AVPlayer? = nil
    @State private var isMuted: Bool = false
    @State private var poster: UIImage? = nil
    @State private var playRequested: Bool = false

    // Added state and observers tracking
    @State private var isPlayingState: Bool = false
    @State private var rateObserver: NSKeyValueObservation? = nil
    @State private var endObserver: Any? = nil

    @State private var overlayTapGuard: Bool = false

    @State private var ignoreStopBroadcastUntil: Date? = nil

    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing: Bool = false
    @State private var timeObserverToken: Any? = nil
    @State private var itemStatusObserver: NSKeyValueObservation? = nil

    var body: some View {
        ZStack {
            ZStack {
                Group {
                    if let poster {
                        Image(uiImage: poster)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "film")
                            .imageScale(.large)
                            .foregroundStyle(.secondary)
                    }
                }
                .task(id: url) { await generatePoster() }

                if let player {
                    PlayerContainerView(player: player)
                        .onDisappear { player.pause() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if overlayTapGuard { return }
                togglePlayPauseFromBackgroundTap()
            }

            // Play overlay
            Button(action: {
                // Guard against simultaneous background tap handling
                overlayTapGuard = true
                defer {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { overlayTapGuard = false }
                }
                requestPlay()
            }) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .opacity(isPlayingState ? 0 : 1)
            .accessibilityLabel("Play video")

            // Bottom transport bar (unified)
            VStack(spacing: 8) {
                Spacer()
                // Slider row
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: {
                                min(
                                    max(currentTime, 0),
                                    duration > 0 ? duration : 0
                                )
                            },
                            set: { newValue in
                                currentTime = newValue
                                // Realtime scrubbing: seek player as the slider moves
                                if let player {
                                    let cm = CMTime(
                                        seconds: max(0, min(newValue, duration)),
                                        preferredTimescale: CMTimeScale(NSEC_PER_SEC)
                                    )
                                    player.seek(
                                        to: cm,
                                        toleranceBefore: .zero,
                                        toleranceAfter: .zero
                                    )
                                }
                            }
                        ),
                        in: 0...(duration > 0 ? duration : 1),
                        onEditingChanged: { began in
                            if began {
                                isScrubbing = true
                            } else {
                                commitSeek()
                            }
                        }
                    )
                    .tint(Theme.Colors.accent)
                }
                // Transport controls row
                HStack(spacing: 16) {
                    // Speaker (mute/unmute)
                    Button(action: { toggleMute() }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Back 10s
                    Button(action: { seek(by: -10) }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Play/Pause
                    Button(action: { togglePlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: isPlayingState ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Forward 10s
                    Button(action: { seek(by: 10) }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: "goforward.10")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // AirPlay
                    RoutePickerView()
                        .frame(width: 28, height: 28)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)
                .background(
                    Color.clear.cardSurface()
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .onChange(of: onRequestStopAll) { _, _ in
            if let until = ignoreStopBroadcastUntil, Date() < until {
                // Ignore self-originated broadcast
                return
            }
            stop()
        }
        .onDisappear {
            // Stop playback and reset to start so revisiting begins from the beginning
            stop()
            if let player {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            removeTimeObservation()
            stopObservingPlayer()
        }
    }

    private func requestPlay() {
        onRequestStopAll.toggle()
        ignoreStopBroadcastUntil = Date().addingTimeInterval(0.15)
        if player == nil { player = AVPlayer(url: url) }
        guard let player else { return }
        startObservingPlayerIfNeeded()
        setupTimeObservationIfNeeded()
        if let item = player.currentItem {
            let dur = item.duration.seconds
            if dur.isFinite && dur > 0 { duration = dur }
        }
        player.isMuted = isMuted
        // Ensure we start/resume playback from the current position consistently
        let current = player.currentTime()
        player.seek(to: current, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        isAnyPlayerActive = true
    }

    private func stop() {
        player?.pause()
        isAnyPlayerActive = false
        isPlayingState = false
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    private func generatePoster() async {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    self.poster = img
                    cont.resume()
                }
            }
        }
    }

    private func togglePlayPause() {
        if player == nil { player = AVPlayer(url: url) }
        startObservingPlayerIfNeeded()
        setupTimeObservationIfNeeded()
        if (player?.rate ?? 0) == 0 {
            player?.play()
            isAnyPlayerActive = true
        } else {
            player?.pause()
            isAnyPlayerActive = false
        }
        player?.isMuted = isMuted
        isPlayingState = ((player?.rate ?? 0) > 0)
    }

    private func seek(by seconds: Double) {
        guard let player else { return }
        let current = player.currentTime()
        let target = CMTimeGetSeconds(current) + seconds
        let newTime = CMTime(
            seconds: max(0, target),
            preferredTimescale: current.timescale
        )
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = CMTimeGetSeconds(newTime)
    }

    private func togglePlayPauseFromBackgroundTap() {
        if player == nil { player = AVPlayer(url: url) }
        startObservingPlayerIfNeeded()
        setupTimeObservationIfNeeded()
        // If currently playing, pause immediately
        if isPlayingState {
            togglePlayPause()
            return
        }
        // If paused, defer slightly; if the overlay button handled play, isPlayingState will be true and we won't double-trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if !isPlayingState {
                requestPlay()
            }
        }
    }

    // Added helper methods for KVO and notifications
    private func startObservingPlayerIfNeeded() {
        guard let player else { return }
        // Observe rate changes to reflect playing/paused state
        rateObserver = player.observe(\.rate, options: [.initial, .new]) { _, _ in
            DispatchQueue.main.async {
                self.isPlayingState = (player.rate > 0)
            }
        }
        // Observe end of item to set state to paused
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            guard let player = self.player else { return }
            // Natural end only: reset to start and leave paused/ready (do not auto-play).
            self.isPlayingState = false
            self.isAnyPlayerActive = false
            self.isScrubbing = false
            self.currentTime = 0

            player.pause()
            let zero = CMTime(seconds: 0, preferredTimescale: 600)
            player.seek(to: zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                DispatchQueue.main.async {
                    self.currentTime = 0
                }
            }
        }
        if let item = player.currentItem {
            itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { item, _ in
                if item.status == .readyToPlay {
                    let dur = item.duration.seconds
                    if dur.isFinite && dur > 0 {
                        DispatchQueue.main.async { self.duration = dur }
                    }
                }
            }
        }
    }

    private func stopObservingPlayer() {
        rateObserver?.invalidate()
        rateObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func setupTimeObservationIfNeeded() {
        guard timeObserverToken == nil, let player else { return }
        // Update roughly every 0.1s
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            let seconds = CMTimeGetSeconds(time)
            if !isScrubbing { currentTime = seconds }
            if let item = player.currentItem {
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 { duration = dur }
            }
        }
    }

    private func removeTimeObservation() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
    }

    private func commitSeek() {
        guard let player else { return }
        isScrubbing = false
        let target = max(0, min(currentTime, duration))
        let cm = CMTime(
            seconds: target,
            preferredTimescale: CMTimeScale(NSEC_PER_SEC)
        )
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

private struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = UIColor.label
        view.activeTintColor = UIColor.label
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct PlayerContainerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.player = player
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        private func commonInit() {
            // Match SwiftUI's scaledToFit behavior
            playerLayer.videoGravity = .resizeAspect
            // No controls are added here; AVPlayerLayer draws video only
            backgroundColor = .clear
        }
    }
}

// MARK: - Audio player + waveform

private final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    @Published var didFail: Bool = false
    @Published var currentLevel: Float = 0 // 0...1 for waveform


    var onNaturalEnd: (() -> Void)?

    private var player: AVAudioPlayer?

    var volume: Float {
        get { player?.volume ?? 1.0 }
        set { player?.volume = newValue }
    }

    var canResume: Bool { player != nil }

    var duration: TimeInterval { player?.duration ?? 0 }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    func setCurrentTime(_ time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
    }

    func play(url: URL) {
        stop()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.volume = 1.0
            player?.isMeteringEnabled = true
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
        } catch {
            isPlaying = false
            currentLevel = 0
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        currentLevel = 0
    }

    func resume() {
        guard let player else { return }
        // Resume from currentTime without resetting.
        player.play()
        isPlaying = true
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentLevel = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentLevel = 0
            self.onNaturalEnd?()
        }
    }


    /// Sample current audio power level and normalize to 0...1.
    func sampleLevel() {
        guard let player, isPlaying else {
            currentLevel = 0
            return
        }
        player.updateMeters()
        let db = player.averagePower(forChannel: 0)
        currentLevel = normalizedPower(db)
    }

    private func normalizedPower(_ decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        let minDb: Float = -60
        let clamped = max(decibels, minDb)
        let linear = (clamped - minDb) / -minDb
        return max(0, min(1, linear))
    }
}


final class RemoteAudioPlayerController: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false


    var onNaturalEnd: (() -> Void)?

    private var player: AVPlayer?


    var volume: Float {
        get { player?.volume ?? 1.0 }
        set { player?.volume = newValue }
    }
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentURL: URL?

    var canResume: Bool { player != nil }

    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0

    deinit {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func toggle(url: URL) {
        if player == nil || currentURL != url {
            prepare(url: url)
            play()
            return
        }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func prepare(url: URL) {
        currentURL = url

        // Clear any previous end observer so it never leaks across items.
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        attachTimeObserver(to: p)

        // Natural-end handler: pause/ready + notify view layer (which performs the reset).
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.onNaturalEnd?()
        }

        duration = 0
        currentTime = 0
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
    }

    func stop() {
        guard let player else { return }
        player.pause()
        isPlaying = false
    }

    func setCurrentTime(_ time: TimeInterval) {
        guard let player else { return }
        let d = duration > 0 ? duration : max(time, 0)
        let clamped = max(0, min(time, d))
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    private func attachTimeObserver(to player: AVPlayer) {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            self.currentTime = t.seconds

            if let item = player.currentItem {
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 {
                    self.duration = dur
                }
            }
        }
    }
}

private struct AudioPage: View {
    let url: URL
    @Binding var isAnyPlayerActive: Bool
    @Binding var onRequestStopAll: Bool
    let displayTitle: String?
    var onFailure: (() -> Void)? = nil
    @StateObject private var audioController = AudioPlayerController()
    @StateObject private var remoteController = RemoteAudioPlayerController()

    // Waveform ring buffer
    @State private var waveformSamples: [CGFloat] = Array(repeating: 0.1, count: 120)
    @State private var waveformWriteIndex: Int = 0
    @State private var waveformHasWrapped: Bool = false
    @State private var waveformTimer: Timer?

    // New state for scrubbing and playback progress
    @State private var audioDuration: TimeInterval = 0
    @State private var audioCurrentTime: TimeInterval = 0
    @State private var wasPlayingBeforeScrub: Bool = false
    @State private var isScrubbing: Bool = false

    @State private var isMuted: Bool = false
    @State private var lastVolume: Float = 1.0


    private var isRemoteURL: Bool {
        let s = url.scheme?.lowercased()
        return s == "http" || s == "https"
    }

    private var isPlaybackPlaying: Bool { isRemoteURL ? remoteController.isPlaying : audioController.isPlaying }
    private var playbackDuration: TimeInterval { isRemoteURL ? remoteController.duration : audioController.duration }
    private var playbackCurrentTime: TimeInterval { isRemoteURL ? remoteController.currentTime : audioController.currentTime }

    private func stopPlayback() {
            if isRemoteURL {
                remoteController.stop()
            } else {
                audioController.stop()
            }
        }

    private func setPlaybackTime(_ time: TimeInterval) {
        if isRemoteURL {
            remoteController.setCurrentTime(time)
        } else {
            audioController.setCurrentTime(time)
        }
    }


    var body: some View {
        VStack(spacing: 16) {

            Text(displayTitle ?? url.deletingPathExtension().lastPathComponent)
                .font(.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Theme.Spacing.l)

            AttachmentWaveformView(
                samples: renderBars(),
                isPlaying: audioController.isPlaying
            )
            .frame(height: 60)
            .padding(.horizontal, Theme.Spacing.l)
            .accessibilityHidden(true)
VStack(spacing: 8) {
                // Slider row
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: {
                                min(
                                    max(audioCurrentTime, 0),
                                    audioDuration > 0 ? audioDuration : 0
                                )
                            },
                            set: { newValue in
                                let clamped = max(0, min(newValue, audioDuration))
                                audioCurrentTime = clamped
                                setPlaybackTime(clamped)
                            }
                        ),
                        in: 0...(audioDuration > 0 ? audioDuration : 1),
                        onEditingChanged: { began in
                            if began {
                                wasPlayingBeforeScrub = isPlaybackPlaying
                                isScrubbing = true
                                stopWaveform()
                            } else {
                                isScrubbing = false
                                resetWaveformToStart()
                                if wasPlayingBeforeScrub && !isRemoteURL {
                                    startWaveform()
                                }
                            }
                        }
                    )
                    .tint(Theme.Colors.accent)
                }

                // Transport controls row
                HStack(spacing: 16) {
                    // Speaker (mute/unmute)
                    Button(action: { toggleMute() }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Back 10s
                    Button(action: { jump(by: -10) }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Play/Pause
                    Button(action: {
                        if isPlaybackPlaying {
                            // Manual pause: preserve position (no reset).
                            if isRemoteURL {
                                remoteController.pause()
                            } else {
                                audioController.pause()
                            }
                            audioCurrentTime = playbackCurrentTime
                            stopWaveform()
                            isAnyPlayerActive = false
                        } else {
                            // Play / resume.
                            if isRemoteURL {
                                // toggle() will prepare+play on first use, and play() when paused.
                                remoteController.toggle(url: url)
                                audioDuration = playbackDuration
                                isAnyPlayerActive = true
                            } else {
                                // Resume if we already have a prepared player; otherwise start fresh.
                                if audioController.canResume {
                                    // If we're at start, ensure waveform is hard-left before animation begins.
                                    if audioCurrentTime <= 0.0001 {
                                        resetWaveformToStart()
                                        audioController.setCurrentTime(0)
                                    }
                                    audioController.resume()
                                } else {
                                    guard let resolvedURL = resolveAudioURL(url) else { return }
                                    // Starting fresh always begins at time 0 and
                                    // hard-left waveform.
                                    resetWaveformToStart()
                                    audioController.play(url: resolvedURL)
                                }

                                audioDuration = playbackDuration
                                isAnyPlayerActive = true
                                startWaveform()
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: isPlaybackPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Forward 10s
                    Button(action: { jump(by: 10) }) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            Image(systemName: "goforward.10")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // AirPlay
                    RoutePickerView()
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            audioController.onNaturalEnd = {
                handleNaturalEnd()
            }
            remoteController.onNaturalEnd = {
                handleNaturalEnd()
            }
        }
        .onChange(of: onRequestStopAll) { _, _ in
            stopPlayback()
            audioCurrentTime = 0
            stopWaveform()
            resetWaveformToStart()
            isAnyPlayerActive = false
        }
        .onDisappear {
            stopPlayback()
            audioCurrentTime = 0
            stopWaveform()
            resetWaveformToStart()
            isAnyPlayerActive = false
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // Keep scrubber in sync even if play-state lags; only freeze while scrubbing.
            if !isScrubbing && (audioController.canResume || remoteController.canResume) {
                let dur = playbackDuration
                if dur.isFinite && dur > 0 { audioDuration = dur }
                audioCurrentTime = playbackCurrentTime
            }
        }
    }

    private func resolveAudioURL(_ src: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: src.path) { return src }
        let filename = src.lastPathComponent
        let dirs: [URL] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask).first!,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first!,
            fm.urls(for: .libraryDirectory, in: .userDomainMask).first!,
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!,
            fm.temporaryDirectory
        ]
        for base in dirs {
            let candidate = base.appendingPathComponent(filename)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func resetWaveformToStart() {
        waveformSamples = Array(repeating: 0.1, count: waveformSamples.count)
        waveformWriteIndex = 0
        waveformHasWrapped = false
    }
private func toggleMute() {
    if isMuted {
        let restore = lastVolume > 0.0001 ? lastVolume : 1.0
        audioController.volume = restore
        remoteController.volume = restore
        isMuted = false
    } else {
        let current = isRemoteURL ? remoteController.volume : audioController.volume
        let candidate = current > 0.0001 ? current : (lastVolume > 0.0001 ? lastVolume : 1.0)
        lastVolume = candidate
        audioController.volume = 0
        remoteController.volume = 0
        isMuted = true
    }
}

private func jump(by seconds: TimeInterval) {
    guard audioDuration > 0 else { return }
    let wasPlaying = isPlaybackPlaying
    let target = max(0, min(audioCurrentTime + seconds, audioDuration))
    audioCurrentTime = target
    setPlaybackTime(target)

    resetWaveformToStart()
    if wasPlaying && !isRemoteURL {
        stopWaveform()
        startWaveform()
    }
}


    private func handleNaturalEnd() {
        // Natural completion resets to start (manual pause does NOT).
        stopWaveform()
        setPlaybackTime(0)
        audioCurrentTime = 0
        resetWaveformToStart()
        isAnyPlayerActive = false
    }

    // MARK: Waveform helpers

    private func startWaveform() {
        stopWaveform()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            audioController.sampleLevel()
            writeWaveformSample(audioController.currentLevel)
            // Keep scrubber synced during local playback (smooth updates).
            if !isScrubbing {
                let dur = playbackDuration
                if dur.isFinite && dur > 0 { audioDuration = dur }
                audioCurrentTime = playbackCurrentTime
            }
        }
        if let waveformTimer {
            RunLoop.main.add(waveformTimer, forMode: .common)
        }
    }

    private func stopWaveform() {
        waveformTimer?.invalidate()
        waveformTimer = nil
    }

    private func writeWaveformSample(_ value: Float) {
        let clamped = CGFloat(max(0, min(1, value)))
        waveformSamples[waveformWriteIndex] = clamped
        waveformWriteIndex += 1
        if waveformWriteIndex >= waveformSamples.count {
            waveformWriteIndex = 0
            waveformHasWrapped = true
        }
    }

    private func renderBars() -> [CGFloat] {
        guard !waveformSamples.isEmpty else { return [] }
        if waveformHasWrapped {
            let head = waveformSamples[waveformWriteIndex..<waveformSamples.count]
            let tail = waveformSamples[0..<waveformWriteIndex]
            return Array(head + tail)
        } else {
            return waveformSamples
        }
    }

    
}

/// MARK: - Waveform view

private struct AttachmentWaveformView: View {
    let samples: [CGFloat]
    let isPlaying: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(samples.count, 1)

            // Bars now tile the width with no gaps.
            let barWidth = max(width / CGFloat(count), 1)

            HStack(alignment: .center, spacing: 0) {
                ForEach(samples.indices, id: \.self) { i in
                    let s = samples[i]
                    Capsule()
                        .frame(
                            width: barWidth,
                            height: max(height * boosted(s), 2)
                        )
                        .foregroundStyle(color)
                }
            }
        }
    }

    private func boosted(_ s: CGFloat) -> CGFloat {
        let minHeight: CGFloat = 0.015
        let boosted = (exp(s * 3) - 1) / (exp(3) - 1)
        return max(minHeight, boosted)
    }

    private var color: Color {
        isPlaying
        ? Theme.Colors.primaryAction.opacity(0.45)
        : Theme.Colors.secondaryText.opacity(0.35)
    }
}
// MARK: - Helpers
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
