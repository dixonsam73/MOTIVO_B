import SwiftUI
import AVKit
import AVFoundation

private final class _ImageCache {
    static let shared = _ImageCache()
    let cache = NSCache<NSURL, UIImage>()
    private init() {}
}

struct AttachmentViewerView: View {
    let imageURLs: [URL]
    let videoURLs: [URL]
    let audioURLs: [URL]
    @State var startIndex: Int
    var themeBackground: Color = Color(.systemBackground) // dynamic light/dark

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var isPagerInteractable = false
    @State private var pendingDragTranslation: CGFloat = 0
    @State private var hasCommittedOnce: Bool = false
    @State private var localIsPrivate: Bool = false
    @State private var cachedURL: URL? = nil
    @State private var isAnyPlayerActive = false
    @State private var stopAllPlayersToggle = false
    var onDelete: ((URL) -> Void)? = nil
    var onFavourite: ((URL) -> Void)? = nil
    var isFavourite: ((URL) -> Bool)? = nil
    var onTogglePrivacy: ((URL) -> Void)? = nil
    var isPrivate: ((URL) -> Bool)? = nil

    private func currentURL() -> URL? {
        imageURLs.indices.contains(currentIndex) ? imageURLs[currentIndex] : nil
    }

    init(imageURLs: [URL], startIndex: Int, themeBackground: Color = Color(.systemBackground), videoURLs: [URL] = [], audioURLs: [URL] = [], onDelete: ((URL) -> Void)? = nil, onFavourite: ((URL) -> Void)? = nil, isFavourite: ((URL) -> Bool)? = nil, onTogglePrivacy: ((URL) -> Void)? = nil, isPrivate: ((URL) -> Bool)? = nil) {
        self.imageURLs = imageURLs
        self.videoURLs = videoURLs
        self.audioURLs = audioURLs
        self._startIndex = State(initialValue: startIndex)
        self._currentIndex = State(initialValue: startIndex)
        self.themeBackground = themeBackground
        self.onDelete = onDelete
        self.onFavourite = onFavourite
        self.isFavourite = isFavourite
        self.onTogglePrivacy = onTogglePrivacy
        self.isPrivate = isPrivate
    }

    enum MediaKind { case image, video, audio }
    struct MediaAttachment: Identifiable {
        let id = UUID()
        let kind: MediaKind
        let url: URL
    }

    private var media: [MediaAttachment] {
        var items: [MediaAttachment] = []
        items.append(contentsOf: imageURLs.map { MediaAttachment(kind: .image, url: $0) })
        items.append(contentsOf: videoURLs.map { MediaAttachment(kind: .video, url: $0) })
        items.append(contentsOf: audioURLs.map { MediaAttachment(kind: .audio, url: $0) })
        return items
    }

    var body: some View {
        ZStack {
            themeBackground.ignoresSafeArea()

            GeometryReader { proxy in
                TabView(selection: $currentIndex) {
                    ForEach(media.indices, id: \.self) { i in
                        MediaPage(attachment: media[i], isAnyPlayerActive: $isAnyPlayerActive, onRequestStopAll: $stopAllPlayersToggle, background: themeBackground)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .background(Color.clear)
                            .clipped()
                            .tag(i)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height) // <-- key
                .contentShape(Rectangle()) // full-area swipe target
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .indexViewStyle(.page(backgroundDisplayMode: .automatic))
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
                        localIsPrivate = isPrivate?(url) ?? false
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
                        localIsPrivate = isPrivate?(url) ?? false
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
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Spacer()

                    if media.indices.contains(currentIndex) {
                        let currentURL = media[currentIndex].url
                        let isFav = (isFavourite?(currentURL) ?? false)
                        let isPriv = localIsPrivate

                        Button {
                            let url = currentURL
                            let priv = isPrivate?(url) ?? false
                            onFavourite?(url)
                            if !priv { /* presenter enforces single-thumbnail rule */ }
                        } label: {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFav ? "Unfavourite attachment" : "Favourite attachment")

                        Button {
                            let url = currentURL
                            // Optimistic UI update – no rebuild, no flash
                            localIsPrivate.toggle()
                            onTogglePrivacy?(url)
                        } label: {
                            Image(systemName: isPriv ? "eye.slash" : "eye")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPriv ? "Make attachment visible to others" : "Hide attachment from others")

                        Button {
                            let url = currentURL
                            onDelete?(url)
                            stopAllPlayersToggle.toggle()
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete attachment")

                        ShareLink(item: currentURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
            }
            .zIndex(2) // ensure buttons are above the pager
            .allowsHitTesting(true)
        }
        .onAppear {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: [.defaultToSpeaker])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                // Non-fatal: fall back silently
            }
        }
        .onDisappear {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } catch { }
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
                if let data = try? Data(contentsOf: url as URL),
                   let img = UIImage(data: data) {
                    _ImageCache.shared.cache.setObject(img, forKey: url)
                }
            }
        }
    }
}

// MARK: - Async URL Image Loader (no blocking on main)
private struct URLImageView: View {
    let url: URL
    var background: Color = Color(.systemBackground)
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
        .background(background)
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
            } else {
                await setImage(UIImage(systemName: "photo"))
            }
        } catch {
            await setImage(UIImage(systemName: "photo"))
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

    var body: some View {
        switch attachment.kind {
        case .image:
            ImagePage(url: attachment.url, background: background)
        case .video:
            VideoPage(url: attachment.url, isAnyPlayerActive: $isAnyPlayerActive, onRequestStopAll: $onRequestStopAll)
        case .audio:
            AudioPage(url: attachment.url, isAnyPlayerActive: $isAnyPlayerActive, onRequestStopAll: $onRequestStopAll)
        }
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
    @State private var player: AVPlayer? = nil
    @State private var isMuted: Bool = false
    @State private var poster: UIImage? = nil
    @State private var playRequested: Bool = false
    var body: some View {
        ZStack {
            Group {
                if let poster { Image(uiImage: poster).resizable().scaledToFit() }
                else { Image(systemName: "film").imageScale(.large).foregroundStyle(.secondary) }
            }
            .task(id: url) { await generatePoster() }

            if let player { VideoPlayer(player: player).onDisappear { player.pause() } }

            // Play overlay
            Button(action: { requestPlay() }) {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 56, height: 56)
                    Image(systemName: "play.fill").font(.system(size: 20, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .opacity((player?.rate ?? 0) == 0 ? 1 : 0)
            .accessibilityLabel("Play video")

            // Mute toggle (top-right)
            VStack { HStack { Spacer(); Button(action: { toggleMute() }) { Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle()) }
                    .buttonStyle(.plain)
                }
                Spacer() }
            .padding(12)
        }
        .onChange(of: onRequestStopAll) { _, _ in stop() }
        .onDisappear { stop() }
    }
    private func requestPlay() {
        onRequestStopAll.toggle()
        if player == nil { player = AVPlayer(url: url) }
        player?.isMuted = isMuted
        player?.play()
        isAnyPlayerActive = true
    }
    private func stop() { player?.pause(); isAnyPlayerActive = false }
    private func toggleMute() { isMuted.toggle(); player?.isMuted = isMuted }
    private func generatePoster() async {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async { self.poster = img; cont.resume() }
            }
        }
    }
}

private struct AudioPage: View {
    let url: URL
    @Binding var isAnyPlayerActive: Bool
    @Binding var onRequestStopAll: Bool
    @State private var player: AVAudioPlayer? = nil
    @State private var isPlaying: Bool = false
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform").imageScale(.large).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button(action: { togglePlay() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onChange(of: onRequestStopAll) { _, _ in stop() }
        .onDisappear { stop() }
    }
    private func togglePlay() {
        if isPlaying { stop(); return }
        onRequestStopAll.toggle()
        do {
            if player == nil { 
                player = try AVAudioPlayer(contentsOf: url)
                player?.volume = 1.0
                player?.prepareToPlay()
            }
            player?.play()
            isPlaying = true
            isAnyPlayerActive = true
        } catch { isPlaying = false }
    }
    private func stop() { player?.stop(); player = nil; isPlaying = false; isAnyPlayerActive = false }
}

// MARK: - Helpers
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
