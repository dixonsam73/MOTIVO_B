import SwiftUI
import AVFoundation
import AVKit

// MARK: - MediaTrimView

/// A reusable, self-contained SwiftUI view to trim local audio (.m4a) and video (.mp4) clips using AVFoundation.
/// - Features:
///   - Waveform rendering (audio) with draggable trim handles and time ruler.
///   - Inline AVPlayer preview (video and audio).
///   - Play/Pause, debounced seeking, loop within selected range.
///   - Export via AVAssetExportSession as .m4a (AAC) or .mp4 (H.264 + AAC) with passthrough when possible.
public struct MediaTrimView: View {
    public enum MediaType { case audio, video }

    public let assetURL: URL
    public let mediaType: MediaType
    public let onCancel: () -> Void
    public let onSaveAsNew: (URL) -> Void
    public let onReplaceOriginal: (URL) -> Void

    @StateObject private var model = Model()

    public init(assetURL: URL,
                mediaType: MediaType,
                onCancel: @escaping () -> Void,
                onSaveAsNew: @escaping (URL) -> Void,
                onReplaceOriginal: @escaping (URL) -> Void) {
        self.assetURL = assetURL
        self.mediaType = mediaType
        self.onCancel = onCancel
        self.onSaveAsNew = onSaveAsNew
        self.onReplaceOriginal = onReplaceOriginal
    }

    public var body: some View {
        content
            .onAppear { model.load(url: assetURL, mediaType: mediaType) }
            .onChange(of: assetURL) { newURL in
                model.load(url: newURL, mediaType: mediaType)
            }
            .onDisappear { model.teardown() }
            .appBackground()
            .alert(item: $model.alert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: Theme.Spacing.m) {
            // Title Row
            HStack {
                Text(mediaType == .audio ? "Trim Audio" : "Trim Video")
                    .sectionHeader()
                Spacer()
                Text(model.selectedDurationFormatted)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            // Card Surface
            VStack(spacing: Theme.Spacing.m) {
                if mediaType == .video {
                    VideoPreview(player: model.player)
                        .frame(minHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.cardStroke(colorScheme)))
                        .accessibilityHidden(true)

                    VideoRangeSelector(startTime: $model.startTime,
                                       endTime: $model.endTime,
                                       duration: model.duration,
                                       currentTime: model.scrubPosition,
                                       onChange: { focus in model.handleDragChanged(focus: focus) },
                                       onEnd: { focus in model.handleDragEnded(focus: focus) })
                        .frame(height: 56)
                        .padding(.bottom, 8)
                }

                if mediaType == .audio {
                    WaveformSection(model: model, currentTime: model.scrubPosition)
                        .frame(height: 180)
                        .padding(.bottom, 8)
                }

                // Minimal scrubber + play/pause
                PlaybackControls(model: model)
            }
            .padding(Theme.Spacing.l)
            .cardSurface()

            // Actions
            HStack(spacing: Theme.Spacing.m) {
                Button(action: { onCancel() }) {
                    Text("Cancel")
                }
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismiss without saving changes")

                Spacer()

                Button(action: { model.export(mode: .saveAsNew) { url in onSaveAsNew(url) } }) {
                    Text("Save as New")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .accessibilityLabel("Save as New")
                .accessibilityHint("Export the selected range as a new file")

                Button(action: { model.export(mode: .replaceOriginal) { url in onReplaceOriginal(url) } }) {
                    Text("Replace Original")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Replace Original")
                .accessibilityHint("Export and replace the original clip with the trimmed version")
            }
        }
        .padding(Theme.Spacing.l)
        .overlay(alignment: .topLeading) {
            if model.isExporting {
                ExportOverlay(progress: model.exportProgress)
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
}

// MARK: - Subviews

private struct VideoPreview: View {
    let player: AVPlayer?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let player {
            VideoPlayer(player: player)
                .onDisappear { player.pause() }
        } else {
            ZStack {
                Color(UIColor.secondarySystemBackground)
                ProgressView()
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1))
        }
    }
}

private struct PlaybackControls: View {
    @ObservedObject var model: MediaTrimView.Model

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Button(action: { model.togglePlayPause() }) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                .accessibilityHint("Toggles playback")
            }
            HStack {
                Text(model.formatTime(0))
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Spacer()
                Text(model.formatTime(model.duration))
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}

private struct WaveformSection: View {
    @ObservedObject var model: MediaTrimView.Model
    let currentTime: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            if let samples = model.waveformSamples, !samples.isEmpty {
                WaveformRenderer(samples: samples,
                                 startTime: $model.startTime,
                                 endTime: $model.endTime,
                                 duration: model.duration,
                                 currentTime: currentTime,
                                 onHandleChange: { focus in model.handleDragChanged(focus: focus) },
                                 onHandleEnd: { focus in model.handleDragEnded(focus: focus) })
            } else if model.waveformFailed {
                UnavailableWaveformView()
            } else {
                WaveformPlaceholderView()
            }
        }
    }
}

private struct UnavailableWaveformView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground))
            Text("Waveform unavailable")
                .font(.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}

private struct WaveformPlaceholderView: View {
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let gradient = LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.35), Color.gray.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
            RoundedRectangle(cornerRadius: 8)
                .fill(gradient)
                .mask(
                    Rectangle()
                        .fill(
                            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.2), Color.black, Color.black.opacity(0.2)]), startPoint: .leading, endPoint: .trailing)
                        )
                        .offset(x: phase * geo.size.width)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1))
        .accessibilityLabel("Loading waveform")
    }
}

private struct WaveformRenderer: View {
    let samples: [CGFloat]
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let currentTime: Double
    var onHandleChange: (MediaTrimView.Model.DragFocus) -> Void
    var onHandleEnd: (MediaTrimView.Model.DragFocus) -> Void

    @State private var dragTarget: DragTarget? = nil

    private enum DragTarget { case start, end }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(geo.size.height - 24, 1) // leave room for ruler
            let yCenter = height / 2

            let selectedStartX = x(for: startTime, width: width)
            let selectedEndX = x(for: endTime, width: width)

            ZStack(alignment: .topLeading) {
                // Waveform
                Canvas { ctx, size in
                    let baseY = yCenter
                    var path = Path()
                    let columnWidth = max(size.width / CGFloat(samples.count), 1)
                    for (i, v) in samples.enumerated() {
                        let amp = CGFloat(v) * (height / 2)
                        let x = CGFloat(i) * columnWidth + columnWidth / 2
                        path.move(to: CGPoint(x: x, y: baseY - amp))
                        path.addLine(to: CGPoint(x: x, y: baseY + amp))
                    }
                    ctx.stroke(path, with: .color(Theme.Colors.accent), lineWidth: 1)
                    // Baseline
                    let baseline = Path { p in
                        p.move(to: CGPoint(x: 0, y: baseY))
                        p.addLine(to: CGPoint(x: size.width, y: baseY))
                    }
                    ctx.stroke(baseline, with: .color(Color.secondary.opacity(0.3)), lineWidth: 0.5)
                }
                .frame(height: height)
                .accessibilityHidden(true)

                // Selection overlay
                Rectangle()
                    .fill(Theme.Colors.accent.opacity(0.12))
                    .frame(width: max(selectedEndX - selectedStartX, 0), height: height)
                    .offset(x: selectedStartX)
                    .accessibilityHidden(true)

                // QA:
                // 1) Drag handles → preview seeks; playhead snaps and loops within range.
                // 2) Play → thin line moves within [start, end]; at end it loops to start.
                // 3) Pause → line freezes; handles still scrub preview.
                // 4) Export still works (Save as New / Replace Original).
                // 5) Light/Dark parity OK; no slider present.
                PlayheadLine(xPosition: x(for: min(max(currentTime, startTime), endTime), width: width), height: height)
                    .accessibilityHidden(true)

                // Time ruler
                TimeRuler(duration: duration)
                    .frame(height: 24)
                    .offset(y: height)

                // Handles
                HandleView()
                    .position(x: selectedStartX, y: yCenter)
                    .gesture(handleDragGesture(for: .start, width: width))
                    .accessibilityLabel("Start Handle")
                    .accessibilityHint("Drag to adjust the start of the selection")
                HandleView()
                    .position(x: selectedEndX, y: yCenter)
                    .gesture(handleDragGesture(for: .end, width: width))
                    .accessibilityLabel("End Handle")
                    .accessibilityHint("Drag to adjust the end of the selection")
            }
            .contentShape(Rectangle())
        }
    }

    private func handleDragGesture(for target: DragTarget, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragTarget = target
                let t = time(forX: max(0, min(width, value.location.x)), width: width)
                switch target {
                case .start:
                    startTime = min(max(0, t), endTime - 0.1)
                    onHandleChange(.start)
                case .end:
                    endTime = max(min(duration, t), startTime + 0.1)
                    onHandleChange(.end)
                }
            }
            .onEnded { _ in
                guard let currentTarget = dragTarget else { return }
                onHandleEnd(currentTarget == .start ? .start : .end)
                self.dragTarget = nil
            }
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }
    private func time(forX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * duration
    }
}

private struct PlayheadLine: View {
    let xPosition: CGFloat
    let height: CGFloat
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: xPosition, y: 0))
            p.addLine(to: CGPoint(x: xPosition, y: height))
        }
        .stroke(Theme.Colors.accent.opacity(0.9), lineWidth: 1)
    }
}

private struct HandleView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.Colors.accent)
                .frame(width: 28, height: 44)
                .shadow(radius: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement()
    }
}

private struct TimeRuler: View {
    let duration: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let majorInterval: Double = 5
            let minorInterval: Double = 1

            Canvas { ctx, size in
                let height = size.height
                let majorTickHeight: CGFloat = height
                let minorTickHeight: CGFloat = height * 0.4

                func x(for t: Double) -> CGFloat { CGFloat(t / max(duration, 0.0001)) * width }

                // Minor ticks suppressed to reduce clutter
//                if duration > 0 {
//                    var t: Double = 0
//                    while t <= duration {
//                        let xPos = x(for: t)
//                        var p = Path()
//                        p.move(to: CGPoint(x: xPos, y: height - minorTickHeight))
//                        p.addLine(to: CGPoint(x: xPos, y: height))
//                        ctx.stroke(p, with: .color(Color.secondary.opacity(0.3)), lineWidth: 0.5)
//                        t += minorInterval
//                    }
//                }
                // Major ticks + labels
                if duration > 0 {
                    var t: Double = 0
                    while t <= duration + 0.001 {
                        let xPos = x(for: t)
                        var p = Path()
                        p.move(to: CGPoint(x: xPos, y: height - majorTickHeight))
                        p.addLine(to: CGPoint(x: xPos, y: height))
                        ctx.stroke(p, with: .color(Color.secondary.opacity(0.4)), lineWidth: 1)

                        let label = formatTime(t)
                        let text = Text(label).font(.caption2)
                        ctx.draw(text, at: CGPoint(x: xPos + 2, y: 2), anchor: .topLeading)
                        t += majorInterval
                    }
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
}

private struct ExportOverlay: View {
    let progress: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(value: progress)
                Text("Exporting…")
                    .font(.callout)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        }
    }
}

// MARK: - VideoRangeSelector (New)

private struct VideoRangeSelector: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let currentTime: Double
    var onChange: (MediaTrimView.Model.DragFocus) -> Void
    var onEnd: (MediaTrimView.Model.DragFocus) -> Void

    @State private var dragTarget: DragTarget? = nil

    private enum DragTarget { case start, end }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = geo.size.height - 24
            let yCenter = height / 2

            let startX = x(for: startTime, width: width)
            let endX = x(for: endTime, width: width)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    // Baseline bar
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        .frame(height: 8)
                        .position(x: width / 2, y: yCenter)

                    // Selection overlay
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.accent.opacity(0.12))
                        .frame(width: max(endX - startX, 0), height: 8)
                        .offset(x: startX)

                    // QA:
                    // 1) Drag handles → preview seeks; playhead snaps and loops within range.
                    // 2) Play → thin line moves within [start, end]; at end it loops to start.
                    // 3) Pause → line freezes; handles still scrub preview.
                    // 4) Export still works (Save as New / Replace Original).
                    // 5) Light/Dark parity OK; no slider present.
                    PlayheadLine(xPosition: x(for: min(max(currentTime, startTime), endTime), width: width), height: 8)
                        .accessibilityHidden(true)

                    // Handles
                    HandleView()
                        .position(x: startX, y: yCenter)
                        .gesture(handleDragGesture(for: .start, width: width))
                        .accessibilityLabel("Start Handle")
                        .accessibilityHint("Drag to adjust the start of the selection")

                    HandleView()
                        .position(x: endX, y: yCenter)
                        .gesture(handleDragGesture(for: .end, width: width))
                        .accessibilityLabel("End Handle")
                        .accessibilityHint("Drag to adjust the end of the selection")
                }
                .frame(height: height)

                TimeRuler(duration: duration)
                    .frame(height: 24)
            }
        }
    }

    private func handleDragGesture(for target: DragTarget, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragTarget = target
                let t = time(forX: max(0, min(width, value.location.x)), width: width)
                switch target {
                case .start:
                    startTime = min(max(0, t), endTime - 0.1)
                    onChange(.start)
                case .end:
                    endTime = max(min(duration, t), startTime + 0.1)
                    onChange(.end)
                }
            }
            .onEnded { _ in
                guard let currentTarget = dragTarget else { return }
                onEnd(currentTarget == .start ? .start : .end)
                self.dragTarget = nil
            }
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func time(forX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * duration
    }
}

// MARK: - View Model

extension MediaTrimView {
    final class Model: ObservableObject {
        // Inputs/Outputs
        @Published var duration: Double = 0
        @Published var startTime: Double = 0
        @Published var endTime: Double = 0

        @Published var isPlaying: Bool = false
        @Published var scrubPosition: Double = 0

        @Published var waveformSamples: [CGFloat]? = nil
        @Published var waveformFailed: Bool = false

        @Published var isExporting: Bool = false
        @Published var exportProgress: Double = 0
        @Published var alert: ModelAlert? = nil

        // Internals
        private(set) var asset: AVAsset?
        private var playerItem: AVPlayerItem?
        private(set) var player: AVPlayer?

        private var timeObserver: Any?
        private var loopObserver: Any?
        private var suppressLoopWhileAdjustingEnd: Bool = false

        private var lastSeekTime: Date = .distantPast
        private let seekDebounce: TimeInterval = 0.15

        private var currentURL: URL?
        private var currentType: MediaTrimView.MediaType = .audio

        struct ModelAlert: Identifiable { let id = UUID(); let title: String; let message: String }

        var selectedDurationFormatted: String {
            let s = max(0, Int((endTime - startTime).rounded()))
            let m = s / 60
            let r = s % 60
            return String(format: "%02d:%02d", m, r)
        }

        func formatTime(_ seconds: Double) -> String {
            let s = max(0, Int(seconds.rounded()))
            let m = s / 60
            let r = s % 60
            return String(format: "%02d:%02d", m, r)
        }

        // MARK: Lifecycle
        func load(url: URL, mediaType: MediaTrimView.MediaType) {
            teardown()
            currentURL = url
            currentType = mediaType

            let asset = AVURLAsset(url: url)
            self.asset = asset

            // Load duration asynchronously
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                guard let self else { return }
                var error: NSError?
                let status = asset.statusOfValue(forKey: "duration", error: &error)
                DispatchQueue.main.async {
                    switch status {
                    case .loaded:
                        let seconds = CMTimeGetSeconds(asset.duration)
                        self.duration = max(0, seconds)
                        self.startTime = 0
                        self.endTime = self.duration
                        self.scrubPosition = 0
                    default:
                        self.duration = 0
                        self.startTime = 0
                        self.endTime = 0
                        self.alert = ModelAlert(title: "Unable to load media", message: error?.localizedDescription ?? "Unknown error")
                    }
                }
            }

            // Player
            let item = AVPlayerItem(asset: asset)
            self.playerItem = item
            let player = AVPlayer(playerItem: item)
            self.player = player
            observeTime(player: player)

            if mediaType == .audio {
                decodeWaveform(for: asset)
            }
        }

        func teardown() {
            if let player {
                player.pause()
            }
            isPlaying = false
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            timeObserver = nil
            if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
            loopObserver = nil
            waveformSamples = nil
            waveformFailed = false
            exportProgress = 0
            isExporting = false
            asset = nil
            playerItem = nil
            player = nil
        }

        // MARK: Playback
        private func observeTime(player: AVPlayer) {
            let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self else { return }
                let t = CMTimeGetSeconds(time)
                self.scrubPosition = t
                // Looping within selection
                if !self.suppressLoopWhileAdjustingEnd && t >= self.endTime - 0.02 {
                    self.seek(self.startTime) {
                        if self.isPlaying {
                            self.player?.play()
                        }
                    }
                }
            }
            loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.seek(self.startTime) {
                    if self.isPlaying {
                        self.player?.play()
                    }
                }
            }
        }

        func togglePlayPause() {
            guard let player else { return }
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                // Ensure within selected range
                if scrubPosition < startTime || scrubPosition > endTime {
                    seek(startTime) { [weak self] in self?.player?.play() }
                } else {
                    player.play()
                }
                isPlaying = true
            }
        }

        func scrubEditingChanged(isEditing: Bool) {
            if isEditing {
                // Pause while editing
                if isPlaying { player?.pause(); isPlaying = false }
            } else {
                seek(scrubPosition)
            }
        }

        // MARK: Drag handling with focus

        enum DragFocus {
            case start
            case end
        }

        // Existing signatures preserved for compatibility

        func handleDragChanged() {
            handleDragChanged(focus: nil)
        }

        func handleDragEnded() {
            handleDragEnded(focus: nil)
        }

        // New with focus parameter

        func handleDragChanged(focus: DragFocus?) {
            let now = Date()
            if now.timeIntervalSince(lastSeekTime) > seekDebounce {
                lastSeekTime = now
                if let focus = focus {
                    // Suppress looping when adjusting the end handle so seeks to end are visible
                    self.suppressLoopWhileAdjustingEnd = (focus == .end)
                    if isPlaying {
                        player?.pause()
                        isPlaying = false
                    }
                    let seekTime: Double
                    switch focus {
                    case .start:
                        seekTime = startTime
                    case .end:
                        seekTime = endTime
                    }
                    seek(seekTime, completion: nil)
                } else {
                    // fallback to previous behavior
                    seek(min(max(scrubPosition, startTime), endTime), completion: nil)
                }
            }
        }

        func handleDragEnded(focus: DragFocus?) {
            self.suppressLoopWhileAdjustingEnd = false
            if let focus = focus {
                let seekTime: Double
                switch focus {
                case .start:
                    seekTime = startTime
                case .end:
                    seekTime = endTime
                }
                // Precise seek without auto play
                seek(seekTime, completion: nil)
            } else {
                // fallback to previous behavior
                seek(max(min(scrubPosition, endTime), startTime), completion: nil)
            }
        }

        private func seek(_ seconds: Double, completion: (() -> Void)? = nil) {
            guard let player else { return }
            let t = CMTime(seconds: seconds, preferredTimescale: 600)
            player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                completion?()
            }
        }

        // MARK: Waveform Decoding
        private func decodeWaveform(for asset: AVAsset) {
            waveformFailed = false
            waveformSamples = nil

            Task(priority: .utility) {
                do {
                    let samples = try await decodeSamples(asset: asset)
                    await MainActor.run {
                        self.waveformSamples = samples
                    }
                } catch {
                    await MainActor.run {
                        self.waveformFailed = true
                    }
                }
            }
        }

        private func decodeSamples(asset: AVAsset) async throws -> [CGFloat] {
            let track = try await asset.loadTracks(withMediaType: .audio).first ?? { throw NSError(domain: "Waveform", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio track"]) }()

            let reader = try AVAssetReader(asset: asset)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)

            guard reader.startReading() else {
                throw reader.error ?? NSError(domain: "Waveform", code: -2, userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"])
            }

            // Accumulate floats
            var floats: [Float] = []
            while reader.status == .reading {
                if let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
                    let length = CMBlockBufferGetDataLength(block)
                    var data = Data(count: length)
                    data.withUnsafeMutableBytes { ptr in
                        _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                    }
                    let count = length / MemoryLayout<Float>.size
                    data.withUnsafeBytes { rawPtr in
                        let floatPtr = rawPtr.bindMemory(to: Float.self)
                        floats.append(contentsOf: UnsafeBufferPointer(start: floatPtr.baseAddress, count: count))
                    }
                    CMSampleBufferInvalidate(buffer)
                } else {
                    break
                }
            }

            if reader.status == .failed { throw reader.error ?? NSError(domain: "Waveform", code: -3, userInfo: [NSLocalizedDescriptionKey: "Reader failed"]) }

            // Downsample to N buckets based on an assumed width range (~400-800)
            let targetColumns = 600
            let bucketSize = max(1, floats.count / targetColumns)
            var buckets: [CGFloat] = []
            buckets.reserveCapacity(targetColumns)

            var i = 0
            while i < floats.count {
                let end = min(i + bucketSize, floats.count)
                let slice = floats[i..<end]
                // RMS
                let rms = sqrt(slice.reduce(0) { $0 + Double($1 * $1) } / Double(slice.count))
                buckets.append(CGFloat(rms))
                i = end
            }

            // Normalize 0..1
            if let maxVal = buckets.max(), maxVal > 0 {
                let inv = 1 / maxVal
                for j in buckets.indices { buckets[j] *= inv }
            }
            return buckets
        }

        // MARK: Export
        enum ExportMode { case saveAsNew, replaceOriginal }

        func export(mode: ExportMode, completion: @escaping (URL) -> Void) {
            guard let asset else { return }
            isExporting = true
            exportProgress = 0

            let start = CMTime(seconds: startTime, preferredTimescale: 600)
            let end = CMTime(seconds: endTime, preferredTimescale: 600)
            let range = CMTimeRange(start: start, end: end)

            let fileManager = FileManager.default
            let tmp = fileManager.temporaryDirectory
            let timestamp = Int(Date().timeIntervalSince1970)
            let ext = (currentType == .audio) ? "m4a" : "mp4"
            let outURL = tmp.appendingPathComponent("trimmed-\(timestamp).\(ext)")
            try? fileManager.removeItem(at: outURL)

            // Choose preset
            var preset = AVAssetExportPresetPassthrough
            if currentType == .audio {
                if !AVAssetExportSession.exportPresets(compatibleWith: asset).contains(preset) {
                    preset = AVAssetExportPresetAppleM4A
                }
            } else {
                // video
                if !AVAssetExportSession.exportPresets(compatibleWith: asset).contains(preset) {
                    preset = AVAssetExportPresetHighestQuality
                }
            }

            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
                isExporting = false
                alert = ModelAlert(title: "Export failed", message: "Unable to create export session")
                return
            }
            exporter.timeRange = range
            exporter.outputURL = outURL
            exporter.shouldOptimizeForNetworkUse = true
            exporter.outputFileType = currentType == .audio ? .m4a : .mp4

            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
                guard let self else { return }
                self.exportProgress = exporter.progress.isFinite ? Double(exporter.progress) : 0
                if !self.isExporting { t.invalidate() }
            }
            RunLoop.main.add(timer, forMode: .common)

            exporter.exportAsynchronously { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isExporting = false
                    timer.invalidate()
                    switch exporter.status {
                    case .completed:
                        completion(outURL)
                    case .failed, .cancelled:
                        self.alert = ModelAlert(title: "Export failed", message: exporter.error?.localizedDescription ?? "Unknown error")
                    default:
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Previews

struct MediaTrimView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            MediaTrimView(assetURL: URL(fileURLWithPath: "/dev/null"), mediaType: .audio, onCancel: {}, onSaveAsNew: { _ in }, onReplaceOriginal: { _ in })
                .frame(height: 480)
            MediaTrimView(assetURL: URL(fileURLWithPath: "/dev/null"), mediaType: .video, onCancel: {}, onSaveAsNew: { _ in }, onReplaceOriginal: { _ in })
                .frame(height: 480)
        }
        .padding()
    }
}

