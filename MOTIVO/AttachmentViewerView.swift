import SwiftUI
import AVKit
import AVFoundation

struct AttachmentViewerView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let topButtonSize: CGFloat = 40
    private let fillOpacityLight: CGFloat = 0.96
    private let fillOpacityDark: CGFloat = 0.88
    private let headerSpacing: CGFloat = Theme.Spacing.l

    let imageURLs: [URL]
    let videoURLs: [URL]
    let audioURLs: [URL]
    @State var startIndex: Int
    var themeBackground: Color = Color.clear // inherits app background

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var isPagerInteractable = false
    @State private var pendingDragTranslation: CGFloat = 0
    @State private var hasCommittedOnce: Bool = false
    @State private var localIsPrivate: Bool = false
    @State private var cachedURL: URL? = nil
    @State private var isAnyPlayerActive = false
    @State private var stopAllPlayersToggle = false

    // Storage Safety: Track any temp surrogate files created by the viewer (e.g., posters, exported shares)
    @State private var tempFilesToCleanup: Set<URL> = []

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
    var onFavourite: ((URL) -> Void)? = nil
    var isFavourite: ((URL) -> Bool)? = nil
    var onTogglePrivacy: ((URL) -> Void)? = nil
    var isPrivate: ((URL) -> Bool)? = nil

    private func currentURL() -> URL? {
        imageURLs.indices.contains(currentIndex) ? imageURLs[currentIndex] : nil
    }

    init(imageURLs: [URL], startIndex: Int, themeBackground: Color = Color.clear, videoURLs: [URL] = [], audioURLs: [URL] = [], onDelete: ((URL) -> Void)? = nil, onFavourite: ((URL) -> Void)? = nil, isFavourite: ((URL) -> Bool)? = nil, onTogglePrivacy: ((URL) -> Void)? = nil, isPrivate: ((URL) -> Bool)? = nil) {
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
            Color.clear.appBackground().ignoresSafeArea()

            GeometryReader { proxy in
                TabView(selection: $currentIndex) {
                    ForEach(media.indices, id: \.self) { i in
                        MediaPage(attachment: media[i], isAnyPlayerActive: $isAnyPlayerActive, onRequestStopAll: $stopAllPlayersToggle, background: themeBackground)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .tag(i)
                    }
                }
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
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
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
                        let isFav = (isFavourite?(currentURL) ?? false)
                        let isPriv = localIsPrivate

                        HStack(spacing: headerSpacing) {
                            Button {
                                let url = currentURL
                                let priv = isPrivate?(url) ?? false
                                onFavourite?(url)
                                if !priv { /* presenter enforces single-thumbnail rule */ }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.thinMaterial)
                                        .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                    Image(systemName: isFav ? "star.fill" : "star")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                .frame(width: topButtonSize, height: topButtonSize)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isFav ? "Unfavourite attachment" : "Favourite attachment")

                            Button {
                                let url = currentURL
                                // Optimistic UI update – no rebuild, no flash
                                localIsPrivate.toggle()
                                onTogglePrivacy?(url)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.thinMaterial)
                                        .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                    Image(systemName: isPriv ? "eye.slash" : "eye")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                .frame(width: topButtonSize, height: topButtonSize)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isPriv ? "Make attachment visible to others" : "Hide attachment from others")

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
                                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                    Image(systemName: "trash")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                .frame(width: topButtonSize, height: topButtonSize)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete attachment")

                            ShareLink(item: currentURL) {
                                ZStack {
                                    Circle()
                                        .fill(.thinMaterial)
                                        .opacity(colorScheme == .dark ? fillOpacityDark : fillOpacityLight)
                                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
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
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)

                Spacer()
            }
            .zIndex(2) // ensure buttons are above the pager
            .allowsHitTesting(true)
        }
        .onAppear {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker])
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

private final class _ImageCache {
    static let shared = _ImageCache()
    let cache = NSCache<NSURL, UIImage>()
    private init() {}
}

// MARK: - Async URL Image Loader (no blocking on main)
private struct URLImageView: View {
    let url: URL
    var background: Color = Color.clear
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

    // Added state and observers tracking
    @State private var isPlayingState: Bool = false
    @State private var rateObserver: NSKeyValueObservation? = nil
    @State private var endObserver: Any? = nil

    var body: some View {
        ZStack {
            ZStack {
                Group {
                    if let poster { Image(uiImage: poster).resizable().scaledToFit() }
                    else { Image(systemName: "film").imageScale(.large).foregroundStyle(.secondary) }
                }
                .task(id: url) { await generatePoster() }

                if let player { PlayerContainerView(player: player).onDisappear { player.pause() } }
            }
            .contentShape(Rectangle())
            .onTapGesture { togglePlayPauseFromBackgroundTap() }

            // Play overlay
            Button(action: { requestPlay() }) {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 56, height: 56)
                    Image(systemName: "play.fill").font(.system(size: 20, weight: .semibold))
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
                    // Progress slider (visual only; does not alter existing logic)
                    ProgressView(value: player?.currentItem?.currentTime().seconds ?? 0,
                                 total: player?.currentItem?.duration.seconds.isFinite == true ? player?.currentItem?.duration.seconds ?? 1 : 1)
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
        .onChange(of: onRequestStopAll) { _, _ in stop() }
        .onDisappear {
            // Stop playback and reset to start so revisiting begins from the beginning
            stop()
            if let player {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            stopObservingPlayer()
        }
    }
    private func requestPlay() {
        onRequestStopAll.toggle()
        if player == nil { player = AVPlayer(url: url) }
        guard let player else { return }
        startObservingPlayerIfNeeded()
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
                DispatchQueue.main.async { self.poster = img; cont.resume() }
            }
        }
    }

    private func togglePlayPause() {
        if player == nil { player = AVPlayer(url: url) }
        startObservingPlayerIfNeeded()
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
        let newTime = CMTime(seconds: max(0, target), preferredTimescale: current.timescale)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePlayPauseFromBackgroundTap() {
        if player == nil { player = AVPlayer(url: url) }
        startObservingPlayerIfNeeded()
        togglePlayPause()
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
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            self.isPlayingState = false
        }
    }

    private func stopObservingPlayer() {
        rateObserver?.invalidate()
        rateObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
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

// New class added above AudioPage
private final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    private var player: AVAudioPlayer?

    func play(url: URL) {
        stop()
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
        } catch {
            // Removed print statement here as requested
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
}

private struct AudioPage: View {
    let url: URL
    @Binding var isAnyPlayerActive: Bool
    @Binding var onRequestStopAll: Bool
    @StateObject private var audioController = AudioPlayerController()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform").imageScale(.large).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button(action: {
                    if audioController.isPlaying {
                        audioController.stop()
                        isAnyPlayerActive = false
                    } else {
                        // Fix: ensure file exists before playback, fallback to resolveAudioURL (see SessionDetailView resolveAttachmentURL logic)
                        guard let resolvedURL = resolveAudioURL(url) else {
                            return
                        }
                        audioController.play(url: resolvedURL)
                        isAnyPlayerActive = true
                    }
                }) {
                    Image(systemName: audioController.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onChange(of: onRequestStopAll) { _, _ in
            audioController.stop()
            isAnyPlayerActive = false
        }
        .onDisappear {
            audioController.stop()
            isAnyPlayerActive = false
        }
    }

    /// Try to resolve a valid audio file URL from potentially stale or partial URLs. Returns nil if not found.
    private func resolveAudioURL(_ src: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: src.path) { return src }
        let filename = src.lastPathComponent
        let candidateDirs: [URL?] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fm.urls(for: .libraryDirectory, in: .userDomainMask).first,
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fm.temporaryDirectory
        ]
        for base in candidateDirs.compactMap({ $0 }) {
            let candidate = base.appendingPathComponent(filename)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

// MARK: - Helpers
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

