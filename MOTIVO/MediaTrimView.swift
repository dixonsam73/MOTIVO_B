import SwiftUI
import AVFoundation
import AVKit
// CHANGE-ID: 20260429_115500_MediaTrim_LandscapeScrollGapFix
// SCOPE: MediaTrimView - landscape-only correction: restore scroll access and add breathing room between preview and scrubber; preserve trim/export/rotate/save/audio/portrait logic.
// SEARCH-TOKEN: 20260429_115500_MediaTrim_LandscapeScrollGapFix
// CHANGE-ID: 20260429_114500_MediaTrim_LandscapeFinalFit
// SCOPE: MediaTrimView - landscape-only final density pass: compact control strip, rebalance preview, and remove scroll dependency; preserve trim/export/rotate/save/audio/portrait logic.
// SEARCH-TOKEN: 20260429_114500_MediaTrim_LandscapeFinalFit
// CHANGE-ID: 20260429_113500_MediaTrim_LandscapeDensityPass
// SCOPE: MediaTrimView - landscape-only density polish for video trim editor; preserve trim, export, rotate, save, audio, and portrait logic.
// SEARCH-TOKEN: 20260429_113500_MediaTrim_LandscapeDensityPass
// CHANGE-ID: 20260429_112500_MediaTrim_LandscapeCompactPreview
// SCOPE: MediaTrimView - cap video preview height in landscape phone editing layout only; preserve trim, export, rotate, save, audio, and AVV playback logic.
// SEARCH-TOKEN: 20260429_112500_MediaTrim_LandscapeCompactPreview
// CHANGE-ID: 20260429_111000_MediaTrim_LiveRotatePreview
// SCOPE: MediaTrimView - show selected video rotation in the live preview only; preserve export, trim, save, audio, and surrounding UI logic.
// SEARCH-TOKEN: 20260429_111000_MediaTrim_LiveRotatePreview
// CHANGE-ID: 20260429_104500_MediaTrim_VideoRotateExport
// SCOPE: MediaTrimView - add video-only 90-degree rotate control and bake rotation into export; preserve audio and non-rotated export behaviour.
// SEARCH-TOKEN: 20260429_104500_MediaTrim_VideoRotateExport
// CHANGE-ID: 20260222_160500_MediaTrim_BoundedFallback
// SCOPE: Replace HighestQuality fallback with bounded export presets (HEVC/1080p/720p/Medium) for video trim


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
    public let onSaveAsNewAttachment: (URL, MediaType) -> Void
    public let onReplaceAttachment: (URL, URL, MediaType) -> Void

    @StateObject private var model = Model()

    public init(assetURL: URL,
                mediaType: MediaType,
                onCancel: @escaping () -> Void,
                onSaveAsNewAttachment: @escaping (URL, MediaType) -> Void,
                onReplaceAttachment: @escaping (URL, URL, MediaType) -> Void) {
        self.assetURL = assetURL
        self.mediaType = mediaType
        self.onCancel = onCancel
        self.onSaveAsNewAttachment = onSaveAsNewAttachment
        self.onReplaceAttachment = onReplaceAttachment
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
        GeometryReader { geo in
            let isLandscapePhone = (UIDevice.current.userInterfaceIdiom == .phone) && (geo.size.width > geo.size.height)

            Group {
                mainContent(isLandscapePhone: isLandscapePhone, availableHeight: geo.size.height)
            }
            .interactiveDismissDisabled(isLandscapePhone)
        }
    }

    @ViewBuilder
    private func mainContent(isLandscapePhone: Bool, availableHeight: CGFloat) -> some View {
        // QA (visual only):
        // 1) Video sits in rounded card; pillar bars feel subdued.
        // 2) Handles are outline-only, readable over video.
        // 3) Timeline shows start/mid/end ticks with labels above; no overflow.
        // 4) Thin playhead line moves and loops within range.
        // 5) Single centered “current • total” time readout updates.
        // 6) Buttons match primary/secondary styles; spacing feels calmer.
        // 7) Light/dark mode parity OK; a11y labels intact.

        // Visual hierarchy constants
        let accent = Theme.Colors.accent
        let secondaryText = Theme.Colors.secondaryText
        let stroke = Color.secondary.opacity(0.25)
        let playFillOpacity: Double = (colorScheme == .dark) ? 0.22 : 0.18
        let handleStrokeOpacity: Double = 0.60
        let playheadOpacity: Double = 0.95
        let landscapeVideoPreviewHeight: CGFloat = min(250, max(210, availableHeight * 0.46))
        let mainStackSpacing: CGFloat = isLandscapePhone ? Theme.Spacing.xs : Theme.Spacing.m
        let cardStackSpacing: CGFloat = isLandscapePhone ? Theme.Spacing.xs : Theme.Spacing.m
        let cardPadding: CGFloat = isLandscapePhone ? Theme.Spacing.s : Theme.Spacing.l
        let cardBottomPadding: CGFloat = isLandscapePhone ? Theme.Spacing.s : Theme.Spacing.xl
        let selectorHeight: CGFloat = isLandscapePhone ? 40 : 56
        let selectorBottomPadding: CGFloat = isLandscapePhone ? 0 : Theme.Spacing.m
        let actionTopPadding: CGFloat = isLandscapePhone ? Theme.Spacing.xs : Theme.Spacing.xl
        let outerVerticalPadding: CGFloat = isLandscapePhone ? Theme.Spacing.s : Theme.Spacing.l

        // QA (tone & hierarchy):
        // 1) Primary button now reads “Save as new”; calls Save-as-New.
        // 2) Play button reads as the primary interactive element (translucent accent bg).
        // 3) Moving playhead is brighter than handles and clearly visible while looping.
        // 4) Handles are lighter; active handle gets full opacity while dragging.
        // 5) Light/dark parity OK; Theme tokens used where available. No logic changed.

        let editorStack = AnyView(
            VStack(spacing: mainStackSpacing) {
                if !isLandscapePhone {
                // Title Row
                HStack {
                    Text(mediaType == .audio ? "Trim Audio" : "Trim Video")
                        .sectionHeader()
                    Spacer()
                    Text(model.selectedDurationFormatted)
                        .font(.callout)
                        .foregroundStyle(secondaryText)
                }
            }

            Button(action: { onCancel() }) {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .foregroundStyle(secondaryText)
            }
            .accessibilityLabel("Cancel")
            .accessibilityHint("Close without trimming")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isLandscapePhone ? 0 : 4)

            // Card Surface
            VStack(spacing: cardStackSpacing) {
                if mediaType == .video {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .cardSurface()
                        if let player = model.player {
                            if isLandscapePhone {
                                VideoPlayer(player: player)
                                    .rotationEffect(.degrees(Double(model.videoRotationDegrees)))
                                    .scaleEffect(model.videoRotationPreviewScale)
                                    .animation(.easeInOut(duration: 0.18), value: model.videoRotationDegrees)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: landscapeVideoPreviewHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .padding(Theme.Spacing.s)
                                    .onDisappear { player.pause() }
                            } else {
                                VideoPlayer(player: player)
                                    .rotationEffect(.degrees(Double(model.videoRotationDegrees)))
                                    .scaleEffect(model.videoRotationPreviewScale)
                                    .animation(.easeInOut(duration: 0.18), value: model.videoRotationDegrees)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .padding(Theme.Spacing.m)
                                    .onDisappear { player.pause() }
                            }
                        } else {
                            if isLandscapePhone {
                                ZStack {
                                    Color(UIColor.secondarySystemBackground)
                                    ProgressView()
                                }
                                .aspectRatio(16/9, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeVideoPreviewHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(Theme.Spacing.s)
                            } else {
                                ZStack {
                                    Color(UIColor.secondarySystemBackground)
                                    ProgressView()
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(Theme.Spacing.m)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.Colors.cardStroke(colorScheme)))
                    .accessibilityHidden(true)
                    .padding(.bottom, isLandscapePhone ? Theme.Spacing.s : 0)

                    VideoRangeSelector(startTime: $model.startTime,
                                       endTime: $model.endTime,
                                       duration: model.duration,
                                       currentTime: model.scrubPosition,
                                       onChange: { focus in model.handleDragChanged(focus: focus) },
                                       onEnd: { focus in model.handleDragEnded(focus: focus) })
                        .frame(height: selectorHeight)
                        .padding(.bottom, selectorBottomPadding)
                }

                if mediaType == .audio {
                    WaveformSection(model: model, currentTime: model.scrubPosition)
                        .frame(height: 180)
                        .padding(.bottom, Theme.Spacing.m)
                }

                // Minimal scrubber + play/pause
                PlaybackControls(model: model, mediaType: mediaType, compactLandscape: isLandscapePhone && mediaType == .video)
            }
            .padding(cardPadding)
            .padding(.bottom, cardBottomPadding)
            .cardSurface()

            // Actions (PracticeTimer-style soft accent)
            // QA (buttons):
            // 1) "Cancel" appears as a plain link under the title and dismisses the sheet.
            // 2) Bottom row shows "Save copy" (soft translucent) and "Replace" (outlined), equal height/width.
            // 3) No label truncation in compact width; buttons wrap within a max-width container if needed.
            // 4) Light/Dark parity OK; Theme colors only; no logic changed.

            HStack { Spacer() }
            .frame(height: 0) // spacer to separate card and buttons visually

            HStack {
                HStack(spacing: isLandscapePhone ? Theme.Spacing.s : Theme.Spacing.m) {
                    Button(action: { model.export(mode: .saveAsNew) { url in onSaveAsNewAttachment(url, mediaType) } }) {
                        Text("Save as new")
                            .frame(maxWidth: .infinity, minHeight: isLandscapePhone ? 40 : 44)
                            .foregroundStyle(accent)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(accent.opacity(playFillOpacity))
                                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
                            )
                    }
                    .accessibilityLabel("Save as new")
                    .accessibilityHint("Export a trimmed duplicate and keep the original")

                    Button(action: { model.export(mode: .replaceOriginal) { url in onReplaceAttachment(assetURL, url, mediaType) } }) {
                        Text("Replace")
                            .frame(maxWidth: .infinity, minHeight: isLandscapePhone ? 40 : 44)
                            .foregroundStyle(accent)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(accent.opacity(0.55), lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Replace original")
                    .accessibilityHint("Overwrite the original with the trimmed version")
                }
                .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, isLandscapePhone ? Theme.Spacing.s : Theme.Spacing.l)
            .padding(.top, actionTopPadding)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, outerVerticalPadding)
        )

        Group {
            if isLandscapePhone {
                ScrollView(.vertical, showsIndicators: false) {
                    editorStack
                }
            } else {
                editorStack
            }
        }
        .overlay(alignment: .topLeading) {
            if model.isExporting {
                ExportOverlay(progress: model.exportProgress)
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSizeClass
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
    let mediaType: MediaTrimView.MediaType
    let compactLandscape: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if compactLandscape {
            HStack(spacing: Theme.Spacing.s) {
                playbackButton

                if mediaType == .video {
                    rotateButton
                }

                Text("\(model.formatTime(model.scrubPosition))  •  \(model.formatTime(model.duration))")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.leading, Theme.Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            VStack(spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    playbackButton

                    if mediaType == .video {
                        rotateButton
                    }
                }

                Text("\(model.formatTime(model.scrubPosition))  •  \(model.formatTime(model.duration))")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    private var playbackButton: some View {
        Button(action: { model.togglePlayPause() }) {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: compactLandscape ? 36 : 44, height: compactLandscape ? 36 : 44)
                .background(controlBackground)
                .shadow(radius: 1)
        }
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
        .accessibilityHint("Toggles playback")
    }

    private var rotateButton: some View {
        Button(action: { model.rotateVideoClockwise() }) {
            Image(systemName: "rotate.right")
                .font(.title2)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: compactLandscape ? 36 : 44, height: compactLandscape ? 36 : 44)
                .background(controlBackground)
                .shadow(radius: 1)
        }
        .accessibilityLabel("Rotate video")
        .accessibilityHint("Rotate the exported video 90 degrees clockwise")
    }

    private var controlBackground: some View {
        RoundedRectangle(cornerRadius: compactLandscape ? 18 : 22, style: .continuous)
            .fill(Theme.Colors.accent.opacity((scheme == .dark) ? 0.22 : 0.18))
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
    @State private var isDraggingStart: Bool = false
    @State private var isDraggingEnd: Bool = false

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
                    let count = max(samples.count, 1)
                    let denom = max(count - 1, 1)
                    for (i, v) in samples.enumerated() {
                        let amp = CGFloat(v) * (height / 2)
                        let x = (CGFloat(i) / CGFloat(denom)) * size.width
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
                    .opacity(0.95)
                    .accessibilityHidden(true)

                // Time ruler
                TimeRuler(duration: duration)
                    .frame(height: 24)
                    .offset(y: height)

                // Handles
                HandleView(isActive: isDraggingStart)
                    .position(x: selectedStartX, y: yCenter)
                    .gesture(handleDragGesture(for: .start, width: width))
                    .accessibilityLabel("Start Handle")
                    .accessibilityHint("Drag to adjust the start of the selection")
                HandleView(isActive: isDraggingEnd)
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
                if target == .start {
                    isDraggingStart = true
                    isDraggingEnd = false
                } else {
                    isDraggingEnd = true
                    isDraggingStart = false
                }
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
                isDraggingStart = false
                isDraggingEnd = false
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
        .stroke(Theme.Colors.accent.opacity(0.95), lineWidth: 1)
    }
}

private struct HandleView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Capsule(style: .circular)
                .stroke(Theme.Colors.accent.opacity(isActive ? 1.0 : 0.60), lineWidth: 2)
                .frame(width: 12, height: 32)
                .overlay(
                    Capsule(style: .circular)
                        .stroke(Color.primary.opacity(isActive ? 0.85 : 0.75), lineWidth: 1)
                        .padding(1)
                )
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

            Canvas { ctx, size in
                let height = size.height
                let baselineY = height
                let baselinePath = Path { p in
                    p.move(to: CGPoint(x: 0, y: baselineY))
                    p.addLine(to: CGPoint(x: size.width, y: baselineY))
                }
                ctx.stroke(baselinePath, with: .color(Color.secondary.opacity(0.25)), lineWidth: 1)

                guard duration > 0 else { return }
                func x(for t: Double) -> CGFloat { CGFloat(t / max(duration, 0.0001)) * size.width }

                // Determine labels adaptively
                var labelTimes: [Double] = []
                if duration <= 12 {
                    labelTimes = [] // no labels
                } else if duration <= 60 {
                    labelTimes = [0, duration / 2, duration]
                } else {
                    // Start, end, and evenly spaced majors capped at 5 total
                    let maxLabels = 5
                    let segments = maxLabels - 1
                    labelTimes = (0...segments).map { i in duration * Double(i) / Double(segments) }
                }

                // Avoid labels at extreme edges and under handles: inset by handle width + 8
                let handleWidth: CGFloat = 12
                let edgeInset: CGFloat = handleWidth + 8

                for t in labelTimes {
                    let label = formatTime(t)
                    let rawX = x(for: t)
                    let clampedX = min(max(rawX, edgeInset), size.width - edgeInset)

                    // Tick
                    var tick = Path()
                    tick.move(to: CGPoint(x: clampedX, y: baselineY - height))
                    tick.addLine(to: CGPoint(x: clampedX, y: baselineY))
                    ctx.stroke(tick, with: .color(Color.secondary.opacity(0.4)), lineWidth: 1)

                    // Label above baseline
                    let text = Text(label).font(.caption2).foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                    ctx.draw(text, at: CGPoint(x: clampedX, y: 2), anchor: .top)
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
    @State private var isDraggingStart: Bool = false
    @State private var isDraggingEnd: Bool = false

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
                        .opacity(0.95)
                        .accessibilityHidden(true)

                    // Handles
                    HandleView(isActive: isDraggingStart)
                        .position(x: startX, y: yCenter)
                        .gesture(handleDragGesture(for: .start, width: width))
                        .accessibilityLabel("Start Handle")
                        .accessibilityHint("Drag to adjust the start of the selection")

                    HandleView(isActive: isDraggingEnd)
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
                if target == .start {
                    isDraggingStart = true
                    isDraggingEnd = false
                } else {
                    isDraggingEnd = true
                    isDraggingStart = false
                }
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
                isDraggingStart = false
                isDraggingEnd = false
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
        @Published var videoRotationDegrees: Int = 0

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

        private var loadGeneration: UUID = UUID()

        struct ModelAlert: Identifiable { let id = UUID(); let title: String; let message: String }

        var selectedDurationFormatted: String {
            let s = max(0, Int((endTime - startTime).rounded()))
            let m = s / 60
            let r = s % 60
            return String(format: "%02d:%02d", m, r)
        }

        var videoRotationPreviewScale: CGFloat {
            let normalized = ((videoRotationDegrees % 360) + 360) % 360
            return (normalized == 90 || normalized == 270) ? 0.56 : 1.0
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
            videoRotationDegrees = 0

            let generation = UUID()
            self.loadGeneration = generation

            let asset = AVURLAsset(url: url)
            self.asset = asset

            // Player (immediate setup to preserve original behavior)
            let item = AVPlayerItem(asset: asset)
            self.playerItem = item
            let player = AVPlayer(playerItem: item)
            self.player = player
            observeTime(player: player)

            if mediaType == .audio {
                decodeWaveform(for: asset)
            }

            // Load duration asynchronously (tolerant: single retry before alert)
            Task { [weak self] in
                guard let self else { return }
                do {
                    let dur = try await asset.load(.duration)
                    var seconds = CMTimeGetSeconds(dur)
                    // If first read yields near-zero, retry once after a short delay
                    if seconds <= 0.01 {
                        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                        let dur2 = try await asset.load(.duration)
                        seconds = CMTimeGetSeconds(dur2)
                    }
                    await MainActor.run {
                        guard self.loadGeneration == generation else { return }
                        self.duration = max(0, seconds)
                        self.startTime = 0
                        self.endTime = self.duration
                        self.scrubPosition = 0
                    }
                } catch {
                    // Retry once before alerting
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    do {
                        let dur2 = try await asset.load(.duration)
                        let seconds2 = CMTimeGetSeconds(dur2)
                        await MainActor.run {
                            guard self.loadGeneration == generation else { return }
                            self.duration = max(0, seconds2)
                            self.startTime = 0
                            self.endTime = self.duration
                            self.scrubPosition = 0
                        }
                    } catch {
                        await MainActor.run {
                            guard self.loadGeneration == generation else { return }
                            self.duration = 0
                            self.startTime = 0
                            self.endTime = 0
                            self.alert = ModelAlert(title: "Unable to load media", message: error.localizedDescription)
                        }
                    }
                }
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

        func rotateVideoClockwise() {
            guard currentType == .video else { return }
            videoRotationDegrees = (videoRotationDegrees + 90) % 360
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
            // We need a real file URL for AVAudioFile
            guard let urlAsset = asset as? AVURLAsset else {
                throw NSError(domain: "Waveform", code: -10, userInfo: [NSLocalizedDescriptionKey: "Asset is not URL-backed"])
            }

            let audioFile = try AVAudioFile(forReading: urlAsset.url)
            let format = audioFile.processingFormat
            let sampleRate = format.sampleRate
            let channels = Int(format.channelCount)
            guard channels > 0 else {
                throw NSError(domain: "Waveform", code: -11, userInfo: [NSLocalizedDescriptionKey: "Invalid channel count"])
            }

            // Time-faithful envelope: choose a window size in seconds.
            // 0.01s = 10ms windows gives good “editor” detail without being huge.
            let windowSeconds: Double = 0.01
            let framesPerWindow = max(1, Int(sampleRate * windowSeconds))

            // We’ll compute RMS per window across the whole file.
            var rmsValues: [CGFloat] = []
            rmsValues.reserveCapacity(Int(audioFile.length) / framesPerWindow + 1)

            // Read in chunks to avoid memory spikes
            let chunkFrames: AVAudioFrameCount = 8192
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                throw NSError(domain: "Waveform", code: -12, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate PCM buffer"])
            }

            // Rolling window accumulator (works across chunk boundaries)
            var windowSumSq: Double = 0
            var windowCount: Int = 0

            audioFile.framePosition = 0

            while audioFile.framePosition < audioFile.length {
                try audioFile.read(into: buffer, frameCount: chunkFrames)
                let framesRead = Int(buffer.frameLength)
                if framesRead == 0 { break }

                // Access channel data (Float32)
                guard let channelData = buffer.floatChannelData else { break }

                for f in 0..<framesRead {
                    // Downmix to mono (average channels)
                    var mono: Float = 0
                    if channels == 1 {
                        mono = channelData[0][f]
                    } else {
                        var sum: Float = 0
                        for c in 0..<channels {
                            sum += channelData[c][f]
                        }
                        mono = sum / Float(channels)
                    }

                    let v = Double(mono)
                    windowSumSq += v * v
                    windowCount += 1

                    if windowCount >= framesPerWindow {
                        let rms = sqrt(windowSumSq / Double(windowCount))
                        rmsValues.append(CGFloat(rms))
                        windowSumSq = 0
                        windowCount = 0
                    }
                }
            }

            // Flush last partial window
            if windowCount > 0 {
                let rms = sqrt(windowSumSq / Double(windowCount))
                rmsValues.append(CGFloat(rms))
            }

            // If somehow empty, return flat line
            guard !rmsValues.isEmpty else {
                return Array(repeating: 0, count: 600)
            }

            // Normalize 0..1
            if let maxVal = rmsValues.max(), maxVal > 0 {
                let inv = 1 / maxVal
                for i in rmsValues.indices { rmsValues[i] *= inv }
            }

            // Now resample to a stable column count for your Canvas renderer.
            // IMPORTANT: columns should scale with duration so short clips don’t under-represent events.
            let duration = max(asset.duration.seconds, 0.001)
            let columnsPerSecond: Double = 80 // editor-friendly; adjust 60–120 if desired
            let targetColumns = max(200, min(2400, Int(duration * columnsPerSecond)))

            if rmsValues.count == targetColumns { return rmsValues }

            // Simple resample: map each output column to a source index range and take max (keeps transients visible)
            var out: [CGFloat] = []
            out.reserveCapacity(targetColumns)

            for i in 0..<targetColumns {
                let start = Int(Double(i) * Double(rmsValues.count) / Double(targetColumns))
                let end = Int(Double(i + 1) * Double(rmsValues.count) / Double(targetColumns))
                let s = max(0, min(start, rmsValues.count - 1))
                let e = max(s + 1, min(end, rmsValues.count))
                var m: CGFloat = 0
                for j in s..<e { m = max(m, rmsValues[j]) }
                out.append(m)
            }

            return out
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

            let fm = FileManager.default
            let tmpDir = fm.temporaryDirectory
            let ext = (currentType == .audio) ? "m4a" : "mp4"
            let tempURL = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            // Clean any pre-existing (unlikely)
            try? fm.removeItem(at: tempURL)
            let normalizedRotation = ((videoRotationDegrees % 360) + 360) % 360
            let shouldApplyVideoRotation = (currentType == .video && normalizedRotation != 0)

            // Choose preset. Rotation requires re-encoding because passthrough ignores video composition transforms.
            var preset = AVAssetExportPresetPassthrough
            if currentType == .audio {
                if !AVAssetExportSession.exportPresets(compatibleWith: asset).contains(preset) {
                    preset = AVAssetExportPresetAppleM4A
                }
            } else {
                let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
                if shouldApplyVideoRotation || !compatiblePresets.contains(preset) {
                    let boundedFallbacks: [String] = [
                        AVAssetExportPresetHEVC1920x1080,
                        AVAssetExportPreset1920x1080,
                        AVAssetExportPreset1280x720,
                        AVAssetExportPresetMediumQuality
                    ]
                    if let chosen = boundedFallbacks.first(where: { compatiblePresets.contains($0) }) {
                        preset = chosen
                    } else if let chosen = compatiblePresets.first(where: { $0 != AVAssetExportPresetHighestQuality && $0 != AVAssetExportPresetPassthrough }) ?? compatiblePresets.first(where: { $0 != AVAssetExportPresetPassthrough }) {
                        // Last-resort fallback: choose the first compatible non-passthrough preset if possible.
                        preset = chosen
                    } else {
                        isExporting = false
                        alert = ModelAlert(title: "Export failed", message: "No compatible export preset available for this video.")
                        return
                    }
                }
            }

            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
                isExporting = false
                alert = ModelAlert(title: "Export failed", message: "Unable to create export session")
                return
            }
            exporter.timeRange = range
            exporter.outputURL = tempURL
            exporter.shouldOptimizeForNetworkUse = true
            exporter.outputFileType = currentType == .audio ? .m4a : .mp4

            if shouldApplyVideoRotation {
                guard let composition = makeVideoRotationComposition(for: asset, rotationDegrees: normalizedRotation) else {
                    isExporting = false
                    alert = ModelAlert(title: "Export failed", message: "Unable to prepare video rotation.")
                    removeIfExists(tempURL)
                    return
                }
                exporter.videoComposition = composition
            }

            // Debug
            if let inputURL = currentURL {
                print("[Trim] inputURL=\(inputURL.path) size=\(fileSize(at: inputURL))")
            }
            print("[Trim] export tempURL=\(tempURL.path)")

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

                    func finishWithCleanup(_ urlToReturn: URL?) {
                        // If returning nil (failure), remove temp
                        if urlToReturn == nil {
                            self.removeIfExists(tempURL)
                        }
                    }

                    switch exporter.status {
                    case .completed:
                        let exportedSize = self.fileSize(at: tempURL)
                        print("[Trim] export completed tempURL size=\(exportedSize)")

                        switch mode {
                        case .saveAsNew:
                            // Caller is expected to move this file into permanent storage and then delete the temp.
                            completion(tempURL)
                            // Do not delete temp here; caller owns it now.

                        case .replaceOriginal:
                            // Replace original path atomically via caller; we will return the tempURL for the caller to adopt/move.
                            // Log before returning; also ensure that if caller fails, our temp is still cleaned by their path or Step-0A sweep.
                            let originalURL = self.currentURL
                            let originalSize = originalURL.map { self.fileSize(at: $0) } ?? 0
                            print("[Trim] replaceOriginal originalURL=\(originalURL?.path ?? "nil") size=\(originalSize)")

                            completion(tempURL)
                            // The caller (AttachmentStore.replace) should move tempURL into place and delete the old file and any posters.
                            // We do not delete tempURL here because it must be moved by the caller. If they move it, the path no longer exists.
                        }

                    case .failed, .cancelled:
                        print("[Trim] export \(exporter.status == .failed ? "failed" : "cancelled") error=\(exporter.error?.localizedDescription ?? "none")")
                        self.alert = ModelAlert(title: "Export failed", message: exporter.error?.localizedDescription ?? "Unknown error")
                        finishWithCleanup(nil)

                    default:
                        // Unknown state; cleanup temp to be safe
                        finishWithCleanup(nil)
                    }
                }
            }
        }

        private func makeVideoRotationComposition(for asset: AVAsset, rotationDegrees: Int) -> AVMutableVideoComposition? {
            guard let track = asset.tracks(withMediaType: .video).first else { return nil }

            let naturalSize = track.naturalSize
            let baseTransform = track.preferredTransform
            let baseRect = CGRect(origin: .zero, size: naturalSize).applying(baseTransform)
            let baseSize = CGSize(width: abs(baseRect.width), height: abs(baseRect.height))

            let radians = CGFloat(rotationDegrees) * .pi / 180
            let rotation = CGAffineTransform(rotationAngle: radians)
            let rotatedRect = CGRect(origin: .zero, size: baseSize).applying(rotation)
            let renderSize = CGSize(width: abs(rotatedRect.width), height: abs(rotatedRect.height))

            var transform = baseTransform
            transform = transform.concatenating(CGAffineTransform(translationX: -baseRect.minX, y: -baseRect.minY))
            transform = transform.concatenating(rotation)
            transform = transform.concatenating(CGAffineTransform(translationX: -rotatedRect.minX, y: -rotatedRect.minY))

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]

            let composition = AVMutableVideoComposition()
            composition.instructions = [instruction]
            composition.renderSize = renderSize
            composition.frameDuration = CMTime(value: 1, timescale: 30)

            return composition
        }

        private func fileSize(at url: URL) -> Int64 {
            let fm = FileManager.default
            if let attrs = try? fm.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber {
                return size.int64Value
            }
            return 0
        }

        private func removeIfExists(_ url: URL) {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }
}

// MARK: - Previews

struct MediaTrimView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            MediaTrimView(assetURL: URL(fileURLWithPath: "/dev/null"), mediaType: .audio, onCancel: {}, onSaveAsNewAttachment: { _, _ in }, onReplaceAttachment: { _, _, _ in })
                .frame(height: 480)
            MediaTrimView(assetURL: URL(fileURLWithPath: "/dev/null"), mediaType: .video, onCancel: {}, onSaveAsNewAttachment: { _, _ in }, onReplaceAttachment: { _, _, _ in })
                .frame(height: 480)
        }
        .padding()
    }
}
