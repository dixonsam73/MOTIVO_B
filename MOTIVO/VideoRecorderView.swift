// CHANGE-ID: 20251214-VIDREC-MONOTONIC-STRUCTFIX-001
// SCOPE: Repair structure (helpers at type scope) + re-apply monotonic video PTS guard. No other behavior/UI changes intended.

import SwiftUI
import AVFoundation
import AVKit
import QuartzCore

@MainActor
final class StagingStoreObject: ObservableObject {
    func bootstrap() async throws { try StagingStore.bootstrap() }
    func list() -> [StagedAttachmentRef] { StagingStore.list() }
    func update(_ ref: StagedAttachmentRef) { StagingStore.update(ref) }
    func remove(_ ref: StagedAttachmentRef) { StagingStore.remove(ref) }
    func absoluteURL(for ref: StagedAttachmentRef) -> URL { StagingStore.absoluteURL(for: ref) }
    func absoluteURL(forRelative path: String) -> URL { StagingStore.absoluteURL(forRelative: path) }
    func saveNew(from sourceURL: URL,
                 kind: StagedAttachmentRef.Kind,
                 suggestedName: String? = nil,
                 duration: Double? = nil,
                 poster: URL? = nil) async throws -> StagedAttachmentRef {
        try await StagingStore.saveNew(from: sourceURL, kind: kind, suggestedName: suggestedName, duration: duration, poster: poster)
    }
}

public struct VideoRecorderView: View {
    public init(onSave: @escaping (URL) -> Void) {
        _controller = StateObject(wrappedValue: VideoRecorderController(onSave: onSave))
    }

    @StateObject private var controller: VideoRecorderController
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var stagingStore: StagingStoreObject
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ZStack {
            CameraPreview(session: controller.captureSession, isLive: controller.isShowingLivePreview)
                .ignoresSafeArea()

            if controller.recordingURL != nil && !controller.isShowingLivePreview {
                if controller.state == .playing {
                    PlayerPreview(player: controller.exposePlayer())
                        .ignoresSafeArea()
                } else if let img = controller.previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    // Fallback while thumbnail is generating
                    Color.black.opacity(0.6).ignoresSafeArea()
                }
            }

            // Close and Flip buttons row
            VStack {
                HStack {
                    // Close button (left)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")

                    Spacer()

                    // Flip button (right)
                    Button {
                        controller.flipCamera()
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .opacity(controller.state == .recording ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.state == .recording)
                    .accessibilityLabel(Text("Flip Camera"))
                }
                .padding(.horizontal, 16)
                .padding(.top, UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first?.safeAreaInsets.top }.first ?? 0 + 8)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
            .zIndex(10)

            VStack(spacing: 12) {
                Spacer()

                // Use actual interface orientation, not the card's width/height
                let orientation = PreviewContainerView.currentOrientation()
                let isLandscape = (orientation == .landscapeLeft || orientation == .landscapeRight)

                GeometryReader { g in
                    let h = g.size.height
                    let baseScale: CGFloat = h < 700 ? max(0.82, h / 700) : 1.0
                    // Slightly smaller card in landscape
                    let scale: CGFloat = isLandscape ? baseScale * 0.9 : baseScale

                    // Tint colours unchanged
                    let tintRecord = Color(red: 0.92, green: 0.30, blue: 0.28)       // soft coral/red
                    let tintStopDelete = Color(red: 0.72, green: 0.42, blue: 0.40)   // muted clay / gray-red
                    let tintPlay = Color(red: 0.36, green: 0.60, blue: 0.52)         // desaturated mint / slate green
                    let tintConfirm = Color(red: 0.38, green: 0.48, blue: 0.62)      // slate blue-gray

                    VStack(spacing: isLandscape ? 2 : 6) {
                        // In landscape we hide the title to save vertical space.
                        if !isLandscape {
                            Text(controller.title)
                                .font(.headline)
                                .accessibilityIdentifier("VideoRecorderView_Title")
                                .lineLimit(1)
                        }

                        Text(controller.formattedTime)
                            .font(.system(.largeTitle, design: .rounded))
                            .monospacedDigit()
                            .accessibilityIdentifier("VideoRecorderView_Clock")
                            .lineLimit(1)

                        HStack(spacing: isLandscape ? 16 : 20) {
                            ControlButton(systemName: "trash",
                                          color: tintStopDelete,
                                          accessibilityLabel: "Delete",
                                          action: { controller.deleteTapped() },
                                          isDisabled: controller.recordingURL == nil)
                            ControlButton(systemName: controller.recordingButtonSystemName,
                                          color: tintRecord,
                                          accessibilityLabel: controller.recordingButtonAccessibilityLabel,
                                          action: { controller.recordPauseResumeTapped() },
                                          isDisabled: controller.recordingButtonDisabled)
                            ControlButton(systemName: "stop.fill",
                                          color: tintStopDelete,
                                          accessibilityLabel: "Stop",
                                          action: { controller.stopTapped() },
                                          isDisabled: !(controller.state == .recording || controller.state == .pausedRecording))
                            ControlButton(systemName: controller.playPauseButtonSystemName,
                                          color: tintPlay,
                                          accessibilityLabel: controller.playPauseButtonAccessibilityLabel,
                                          action: { controller.playPauseTapped() },
                                          isDisabled: controller.recordingURL == nil)
                            ControlButton(systemName: "checkmark.circle.fill",
                                          color: tintConfirm,
                                          accessibilityLabel: "Save",
                                          action: { controller.saveTapped() },
                                          isDisabled: !controller.isReadyToSave)
                        }
                        .accessibilityIdentifier("VideoRecorderView_Controls")
                        .layoutPriority(1)
                        .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, isLandscape ? 4 : 6)
                    .padding(.bottom, isLandscape ? 0 : 0)
                    .cardSurface(padding: isLandscape ? 10 : 12)
                    .padding(.horizontal, isLandscape ? 6 : 10)
                    // In landscape, remove extra bottom padding so the bar hugs the bottom edge more closely.
                    .padding(.bottom, isLandscape ? 0 : 10)
                    .scaleEffect(scale, anchor: .bottom)
                }
                .frame(height: isLandscape ? 150 : 180)
                .zIndex(10)
            }
        }
        .onAppear {
            controller.onAppear()
        }
        .onDisappear {
            controller.onDisappear()
            Task {
                try? await StagingStore.bootstrap()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - ControlButton
    private struct ControlButton: View {
        let systemName: String
        let color: Color
        let accessibilityLabel: String
        let action: () -> Void
        var isDisabled: Bool = false

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 36))
                    .minimumScaleFactor(0.8)
                    .foregroundColor(color.opacity(isDisabled ? 0.4 : 1))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color(.systemGray6)).frame(width: 64, height: 64))
                    .opacity(isDisabled ? 0.5 : 1)
                    .contentShape(Circle())
            }
            .disabled(isDisabled)
            .accessibility(label: Text(accessibilityLabel))
        }
    }
}

/// AVAssetWriter-based video recorder with HEVC 1080p output.
final class VideoRecorderController: NSObject,
                                     ObservableObject,
                                     AVCaptureVideoDataOutputSampleBufferDelegate,
                                     AVCaptureAudioDataOutputSampleBufferDelegate {

    // MARK: - Debug logging (logging-only; no behavior change)
    private let dbgID = String(UUID().uuidString.prefix(6))
    private var dbgSawFirstVideoSample = false
    private var dbgSawFirstAudioSample = false

    private func dbg(_ msg: String) {
        let t = String(format: "%.3f", CACurrentMediaTime())
        let thread = Thread.isMainThread ? "main" : "bg"
        print("[VidRec \(dbgID)] [\(t)] [\(thread)] \(msg)")
    }

    enum RecordingState {
        case idle
        case recording
        case pausedRecording
        case playing
        case paused
    }

    // MARK: - Published State

    @Published var state: RecordingState = .idle
    @Published var elapsedRecordingTime: TimeInterval = 0
    @Published var elapsedPausedTime: TimeInterval = 0
    @Published var playerCurrentTime: TimeInterval = 0

    @Published var recordingURL: URL?
    @Published private(set) var isReadyToSave: Bool = false
    @Published var preferredPosition: AVCaptureDevice.Position = .front

    // Track if showing live camera preview
    @Published var isShowingLivePreview: Bool = true

    // Poster thumbnail image
    @Published var previewImage: UIImage? = nil

    // MARK: - Private AV State

    private var timer: Timer?
    private var recordingWallClockStart: Date?
    private var player: AVPlayer?
    private var playerItemObserver: Any?

    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?

    // Writer pipeline
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    // Pending video frames when writer back-pressures (cold-start / intermittent stalls)
    private var pendingVideoBuffers: [CMSampleBuffer] = []
    private let maxPendingVideoBuffers = 180 // ~3s @ 60fps, ~6s @ 30fps

    // Pending audio frames until writer session start time is established (keeps A/V aligned)
    private var pendingAudioBuffers: [CMSampleBuffer] = []
    private let maxPendingAudioBuffers = 240 // bounded buffer during writer startup

    // MARK: - Fresh-install warm-up (one-time)
    // Warms the capture + writer pipeline once per fresh install to avoid first-run stutter.
    // Writes to a temp file, appends a minimum number of real video frames, then deletes the file.
    private static let freshInstallWarmupCompletedKey = "videoRecorder_freshInstallWarmupCompleted_v1"
    private let freshInstallWarmupMinimumVideoFrames: Int = 40

    private var isFreshInstallWarmupArmed: Bool = false
    private var isFreshInstallWarmupInProgress: Bool = false
    private var isFreshInstallWarmupCompleted: Bool = false
    private var queuedUserStartRecordingAfterWarmup: Bool = false

    private var warmupAssetWriter: AVAssetWriter?
    private var warmupVideoInput: AVAssetWriterInput?
    private var warmupTempURL: URL?
    private var warmupVideoFrameCount: Int = 0
    private var warmupStartPTS: CMTime?

    private var recordingStartTime: CMTime?
    // --- Monotonic/session guards (injected) ---
    private var lastVideoPTS: CMTime?
    private var writerStatusObservation: NSKeyValueObservation?

    private let videoCaptureQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.videoCaptureQueue")
    private let audioCaptureQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.audioCaptureQueue")
    private let writerQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.writerQueue")
    private let sessionQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.sessionQueue")

    private var isSessionConfigured = false
    private var shouldResumeAfterInterruption = false
    private var shouldResumeAfterRouteChange = false
    private var shouldResumeAfterResignActive = false

    // Cold-start warmup: ensure capture session has been running briefly before arming the first writer.
    private var captureSessionBecameRunningAt: Date?
    private var pendingStartRecordingToken: UUID?

    // DEBUG timing (single-line print once per app launch)
    private var debugRecordTapMonotonic: CFTimeInterval?
    private var debugDidPrintFirstFrameTiming: Bool = false

    private var currentVideoOrientation: AVCaptureVideoOrientation = .portrait

    private let onSave: (URL) -> Void

    private var isConfiguringSession: Bool = false

    init(onSave: @escaping (URL) -> Void) {
        self.onSave = onSave
        super.init()
        // Pre-start capture session ASAP to avoid first-run latency on record tap.
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.configureSessionIfNeeded()
            self.startCaptureSession()
        }
    }

    deinit {
        removePlayerObserver()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle hooks

    func onAppear() {
        installNotifications()
        armFreshInstallWarmupIfNeeded()
        DispatchQueue.main.async {
            self.isShowingLivePreview = true
        }
        sessionQueue.async {
            self.configureSessionIfNeeded()
            self.startCaptureSession()
        }
    }

    func onDisappear() {
        stopTimer()
        removeNotifications()
        sessionQueue.async {
            self.stopCaptureSession()
            self.cleanupRecordingFile()
        }
    }

    // MARK: - UI Computed

    var title: String {
        switch state {
        case .idle: return "Ready to Record"
        case .recording: return "Recording"
        case .pausedRecording: return "Paused Recording"
        case .playing: return "Playing"
        case .paused: return "Paused"
        }
    }

    var formattedTime: String {
        let time: TimeInterval
        switch state {
        case .recording, .pausedRecording:
            time = elapsedRecordingTime + elapsedPausedTime
        case .playing, .paused:
            time = playerCurrentTime
        default:
            time = 0
        }
        return Self.formatTime(time)
    }

    static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "00:00.0" }
        let totalTenths = Int(time * 10)
        let minutes = totalTenths / 600
        let seconds = (totalTenths / 10) % 60
        let tenths = totalTenths % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    var recordingButtonSystemName: String {
        return "record.circle.fill"
    }

    var recordingButtonColor: Color { .red }

    var recordingButtonAccessibilityLabel: String {
        switch state {
        case .recording: return "Record (disabled)"
        case .pausedRecording: return "Record"
        default: return "Record"
        }
    }

    var recordingButtonDisabled: Bool { state == .recording }

    var playPauseButtonSystemName: String {
        switch state {
        case .playing: return "pause.circle.fill"
        case .paused: return "play.circle.fill"
        default: return "play.circle.fill"
        }
    }

    var playPauseButtonAccessibilityLabel: String {
        switch state {
        case .playing: return "Pause"
        case .paused: return "Play"
        default: return "Play"
        }
    }

    // MARK: - Actions

    func recordPauseResumeTapped() {
        switch state {
        case .idle, .pausedRecording:
            startRecording()
        case .recording:
            // Pause not supported currently for writer pipeline; we preserve existing behaviour (no-op during recording).
            break
        default:
            break
        }
    }

    func stopTapped() {
        switch state {
        case .recording, .pausedRecording:
            stopRecording()
        default:
            break
        }
    }

    func playPauseTapped() {
        switch state {
        case .playing:
            pausePlayback()
        case .paused:
            resumePlayback()
        default:
            if recordingURL != nil { playRecording() }
        }
    }

    func saveTapped() {
        guard isReadyToSave, let url = recordingURL else { return }
        // [RecorderDebug] saveTapped
        print("[RecorderDebug] saveTapped")
        print("  url=\(url.path)")
        let existsAtSave = FileManager.default.fileExists(atPath: url.path)
        print("  exists=\(existsAtSave)")
        let sizeAtSave = getFileSize(url: url)
        print("  size=\(sizeAtSave) bytes")

        stopPlaybackIfNeeded()
        cleanupRecordingIfJunk()
        onSave(url)
        resetState()
    }

    func deleteTapped() {
        stopPlaybackIfNeeded()
        cleanupRecordingFile()
        resetState()
        isReadyToSave = false
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.timerFired()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timerFired() {
        switch state {
        case .recording:
            guard recordingWallClockStart != nil else { return }
            if let start = recordingWallClockStart {
                elapsedRecordingTime = Date().timeIntervalSince(start)
            }
            if elapsedRecordingTime >= 15 * 60 { stopRecording() }
        case .pausedRecording:
            elapsedPausedTime += 0.1
        case .playing:
            if let current = player?.currentTime() {
                let sec = CMTimeGetSeconds(current)
                if sec.isFinite && sec >= 0 { playerCurrentTime = sec }
            }
        default:
            break
        }
    }

    // MARK: - Session & Recording

    private func configureSessionIfNeeded() {
        precondition(!Thread.isMainThread, "configureSessionIfNeeded must be called on sessionQueue")
        guard !isSessionConfigured else { return }

        let session = AVCaptureSession()
        isConfiguringSession = true
        session.beginConfiguration()
        // Upgrade preset to 1080p; HEVC encoder will use this as canvas.
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        // Video input using preferredPosition (front default); fallback to opposite
        let desired = preferredPosition
        let fallback: AVCaptureDevice.Position = (desired == .front ? .back : .front)
        let desiredDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: desired)
        ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: fallback)

        guard let vDev = desiredDevice,
              let videoInput = try? AVCaptureDeviceInput(device: vDev),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            isConfiguringSession = false
            return
        }
        session.addInput(videoInput)

        // Audio input - ensure always added
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Video data output
        let vOutput = AVCaptureVideoDataOutput()
        vOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        vOutput.alwaysDiscardsLateVideoFrames = false
        vOutput.setSampleBufferDelegate(self, queue: videoCaptureQueue)
        if session.canAddOutput(vOutput) {
            session.addOutput(vOutput)
        }

        // Audio data output
        let aOutput = AVCaptureAudioDataOutput()
        aOutput.setSampleBufferDelegate(self, queue: audioCaptureQueue)
        if session.canAddOutput(aOutput) {
            session.addOutput(aOutput)
        }

        // Match orientation & mirroring to preview
        if let conn = vOutput.connection(with: .video) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = PreviewContainerView.currentOrientation()
                self.currentVideoOrientation = conn.videoOrientation
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = true
            }
        }

        session.commitConfiguration()
        isConfiguringSession = false

        self.captureSession = session
        self.videoOutput = vOutput
        self.audioOutput = aOutput
        self.isSessionConfigured = true
    }

    func flipCamera() {
        // If currently recording, ignore flip (button is disabled in UI)
        if state == .recording { return }

        // Fade out preview on main for smooth transition
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isShowingLivePreview = false
            }
        }

        let nextPosition: AVCaptureDevice.Position = (preferredPosition == .front) ? .back : .front
        preferredPosition = nextPosition

        sessionQueue.async {
            // Ensure session exists
            self.configureSessionIfNeeded()
            guard let session = self.captureSession else {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isShowingLivePreview = true
                    }
                }
                return
            }

            self.isConfiguringSession = true
            session.beginConfiguration()
            // Remove existing video inputs only
            for input in session.inputs {
                if let devInput = input as? AVCaptureDeviceInput, devInput.device.hasMediaType(.video) {
                    session.removeInput(devInput)
                }
            }
            // Add new video input
            let desired = nextPosition
            let fallback: AVCaptureDevice.Position = (desired == .front ? .back : .front)
            let desiredDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: desired)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: fallback)
            if let vDev = desiredDevice,
               let videoInput = try? AVCaptureDeviceInput(device: vDev),
               session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            // Ensure audio input exists
            let hasAudio = session.inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) ?? false }
            if !hasAudio,
               let audioDev = AVCaptureDevice.default(for: .audio),
               let audioIn = try? AVCaptureDeviceInput(device: audioDev),
               session.canAddInput(audioIn) {
                session.addInput(audioIn)
            }
            // Update orientation/mirroring
            if let vOutput = self.videoOutput,
               let conn = vOutput.connection(with: .video) {
                if conn.isVideoOrientationSupported {
                    conn.videoOrientation = PreviewContainerView.currentOrientation()
                    self.currentVideoOrientation = conn.videoOrientation
                }
                if conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = true
                }
            }
            session.commitConfiguration()
            self.isConfiguringSession = false
            if !session.isRunning { session.startRunning() }
            if self.captureSessionBecameRunningAt == nil {
                self.captureSessionBecameRunningAt = Date()
            }

            // Fade back in on main
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.isShowingLivePreview = true
                }
            }
        }
    }

    func startCaptureSession() {
        sessionQueue.async {
            if self.isConfiguringSession { return }
            guard let session = self.captureSession, !session.isRunning else { return }
            session.startRunning()

            // After session is running, refresh preview orientation on main
            DispatchQueue.main.async {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = scene.windows.first,
                   let rootView = window.rootViewController?.view {
                    rootView.setNeedsLayout()
                    rootView.layoutIfNeeded()
                }
                self.isShowingLivePreview = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    self.isShowingLivePreview = true
                }
            }

            // Also update the video output connection orientation/mirroring now that the session is running
            if let conn = self.videoOutput?.connection(with: .video) {
                if conn.isVideoOrientationSupported {
                    conn.videoOrientation = PreviewContainerView.currentOrientation()
                    self.currentVideoOrientation = conn.videoOrientation
                }
                if conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = true
                }
            }
        }
    }

    private func stopCaptureSession() {
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
        captureSession = nil
        videoOutput = nil
        audioOutput = nil
        isSessionConfigured = false
    }

    // MARK: - Writer Setup

    private func setupWriter(for url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Determine canvas dimensions based on orientation (we encode upright for the chosen orientation)
        let isLandscape = (currentVideoOrientation == .landscapeLeft || currentVideoOrientation == .landscapeRight)
        let width: Int
        let height: Int
        if isLandscape {
            width = 1920
            height = 1080
        } else {
            width = 1080
            height = 1920
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        // Do not rotate; choose width/height above to match orientation. Only mirror for front camera.
        var transform = CGAffineTransform.identity
        if preferredPosition == .front {
            // Horizontal mirror; translate back into the frame
            let mirror = CGAffineTransform(scaleX: -1, y: 1)
            let translate = CGAffineTransform(translationX: CGFloat(width), y: 0)
            transform = mirror.concatenating(translate)
        }

        vInput.transform = transform

        // Audio settings: AAC 44.1kHz mono
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        if writer.canAdd(vInput) { writer.add(vInput) }
        if writer.canAdd(aInput) { writer.add(aInput) }

        self.assetWriter = writer
        self.videoInput = vInput
        self.audioInput = aInput
        self.recordingStartTime = nil
        self.lastVideoPTS = nil
    }

    // MARK: - Monotonic/session helpers (type-scope)

    private func ensureSessionStarted(with pts: CMTime) {
        if recordingStartTime == nil {
            assetWriter?.startSession(atSourceTime: pts)
            recordingStartTime = pts
            lastVideoPTS = nil
        }
    }

    private func canAppendVideo(_ pts: CMTime) -> Bool {
        if let last = lastVideoPTS {
            return pts >= last
        }
        return true
    }

    private func recordVideoAppend(_ pts: CMTime) {
        lastVideoPTS = pts
    }

    // MARK: - Fresh-install warm-up helpers

    private func armFreshInstallWarmupIfNeeded() {
        // Cache the flag in-memory so we don't hit UserDefaults on every frame.
        let completed = UserDefaults.standard.bool(forKey: Self.freshInstallWarmupCompletedKey)
        isFreshInstallWarmupCompleted = completed
        if completed { return }
        isFreshInstallWarmupArmed = true
    }

    private func warmupRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("motivo_vid_warmup_\(UUID().uuidString).mov")
    }

    private func setupWarmupWriter(for url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Match the main writer's canvas calculation for consistency.
        let isLandscape = (currentVideoOrientation == .landscapeLeft || currentVideoOrientation == .landscapeRight)
        let width: Int
        let height: Int
        if isLandscape {
            width = 1920
            height = 1080
        } else {
            width = 1080
            height = 1920
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        // Mirror for front camera (same as main writer).
        var transform = CGAffineTransform.identity
        if preferredPosition == .front {
            let mirror = CGAffineTransform(scaleX: -1, y: 1)
            let translate = CGAffineTransform(translationX: CGFloat(width), y: 0)
            transform = mirror.concatenating(translate)
        }
        vInput.transform = transform

        if writer.canAdd(vInput) { writer.add(vInput) }

        warmupAssetWriter = writer
        warmupVideoInput = vInput
        warmupVideoFrameCount = 0
        warmupStartPTS = nil
    }

    private func completeFreshInstallWarmupIfNeeded() {
        guard isFreshInstallWarmupInProgress else { return }
        guard let writer = warmupAssetWriter else { return }

        // Prevent re-entry while finishWriting is in-flight.
        isFreshInstallWarmupInProgress = false
        isFreshInstallWarmupArmed = false
        isFreshInstallWarmupCompleted = true
        UserDefaults.standard.set(true, forKey: Self.freshInstallWarmupCompletedKey)

        let urlToDelete = warmupTempURL

        warmupAssetWriter = nil
        warmupVideoInput = nil
        warmupTempURL = nil
        warmupStartPTS = nil
        warmupVideoFrameCount = 0

        writer.finishWriting { [weak self] in
            if let url = urlToDelete {
                try? FileManager.default.removeItem(at: url)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.queuedUserStartRecordingAfterWarmup {
                    self.queuedUserStartRecordingAfterWarmup = false
                    self.startRecording()
                }
            }
        }
    }

    private func handleFreshInstallWarmupVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if isFreshInstallWarmupCompleted { return }
        if !isFreshInstallWarmupArmed { return }

        // Lazily create a warmup writer on the first video frame after activation.
        if !isFreshInstallWarmupInProgress {
            isFreshInstallWarmupInProgress = true
            warmupVideoFrameCount = 0
            warmupStartPTS = nil

            let url = warmupRecordingURL()
            warmupTempURL = url
            try? FileManager.default.removeItem(at: url)
            do {
                try setupWarmupWriter(for: url)
            } catch {
                // If warmup setup fails, disarm to avoid blocking recording.
                isFreshInstallWarmupInProgress = false
                isFreshInstallWarmupArmed = false
                return
            }
        }

        guard let writer = warmupAssetWriter,
              let vInput = warmupVideoInput else {
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if warmupStartPTS == nil {
            if writer.status == .unknown {
                writer.startWriting()
            }
            if writer.status == .writing {
                writer.startSession(atSourceTime: pts)
                warmupStartPTS = pts
            } else {
                return
            }
        }

        guard writer.status == .writing else { return }

        if vInput.isReadyForMoreMediaData {
            if vInput.append(sampleBuffer) {
                warmupVideoFrameCount += 1
            }
        }

        if warmupVideoFrameCount >= freshInstallWarmupMinimumVideoFrames {
            completeFreshInstallWarmupIfNeeded()
        }
    }

    // MARK: - Recording Control

    private func startRecording() {
        guard state == .idle || state == .pausedRecording else { return }
        dbg("startRecording() tap; state=\(state)")
        // DEBUG: mark record tap time (monotonic) for first-frame timing line
        debugRecordTapMonotonic = CACurrentMediaTime()
        debugDidPrintFirstFrameTiming = false
        configureAudioSession()
        sessionQueue.async {
            self.configureSessionIfNeeded()
            if let conn = self.videoOutput?.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = PreviewContainerView.currentOrientation()
                self.currentVideoOrientation = conn.videoOrientation
            }
            self.startCaptureSession()
        }

        isReadyToSave = false
        let url = newRecordingURL()
        recordingURL = url
        try? FileManager.default.removeItem(at: url)

        do {
            try setupWriter(for: url)
        } catch {
            print("[RecorderDebug] setupWriter failed: \(error)")
            recordingURL = nil
            assetWriter = nil
            videoInput = nil
            audioInput = nil
            return
        }

        // Prime assetWriter.startWriting() on record tap so the first-run cost isn't paid on the first video frame callback.
        // Session start (startSession) remains video-PTS anchored and will be started when the first buffered video buffer is available.
        writerQueue.async { [weak self] in
            guard let self else { return }
            guard let writer = self.assetWriter else { return }
            if writer.status == .unknown {
                writer.startWriting()
            }
            self.startWriterSessionFromBufferedIfPossible()
        }

        elapsedRecordingTime = 0
        elapsedPausedTime = 0
        recordingWallClockStart = Date()
        pendingStartRecordingToken = nil
        state = .recording
        isShowingLivePreview = true
        startTimer()
    }

    private func stopRecording() {
        guard state == .recording || state == .pausedRecording else { return }
        dbg("stopRecording() called; writer.status=\(assetWriter?.status.rawValue ?? -1); startTimeSet=\(recordingStartTime != nil)")
        pendingStartRecordingToken = nil
        stopTimer()
        recordingWallClockStart = nil

        guard let writer = assetWriter else {
            state = .idle
            finishRecordingWithError()
            return
        }

        let finishURL = recordingURL
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if writer.status == .completed, let url = finishURL {
                    self.handleRecordingFinishedSuccessfully(url: url)
                } else {
                    self.finishRecordingWithError()
                }
            }
        }

        state = .idle
    }

    private func handleRecordingFinishedSuccessfully(url: URL) {
        // [RecorderDebug] didFinishRecordingTo (writer-based)
        print("[RecorderDebug] didFinishRecordingTo (writer)")
        print("  url=\(url.path)")
        let existsAtFinish = FileManager.default.fileExists(atPath: url.path)
        print("  exists=\(existsAtFinish)")
        let sizeAtFinish = getFileSize(url: url)
        print("  size=\(sizeAtFinish) bytes")

        guard existsAtFinish else {
            finishRecordingWithError()
            return
        }

        recordingURL = url
        player = AVPlayer(url: url)
        playerCurrentTime = 0

        // Generate poster thumbnail from midpoint
        generateMidpointThumbnail(for: url) { [weak self] image in
            self?.previewImage = image
        }

        isReadyToSave = true
        state = .idle
        isShowingLivePreview = false

        Task {
            try? await StagingStore.bootstrap()
        }

        // Tear down writer state
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        recordingStartTime = nil
        lastVideoPTS = nil
        pendingVideoBuffers.removeAll(keepingCapacity: true)
        pendingAudioBuffers.removeAll(keepingCapacity: true)
    }

    private func finishRecordingWithError() {
        cleanupRecordingFile()
        resetState()
    }

    private func cleanupRecordingIfJunk() {
        guard let url = recordingURL else { return }
        let duration = getVideoDuration(url: url)
        let fileSize = getFileSize(url: url)
        if duration < 0.5 || fileSize == 0 {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            isReadyToSave = false
            previewImage = nil
        }
    }

    private func cleanupRecordingFile() {
        guard let url = recordingURL else {
            print("[RecorderDebug] cleanupRecordingFile: no recordingURL set.")
            return
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
                print("[RecorderDebug] cleanupRecordingFile: deleted file at \(url.path)")
            } catch {
                print("[RecorderDebug] cleanupRecordingFile: FAILED to delete at \(url.path): \(error)")
            }
        } else {
            print("[RecorderDebug] cleanupRecordingFile: file not found at \(url.path)")
        }
        recordingURL = nil
        isReadyToSave = false
        previewImage = nil

        // Tear down writer state if any
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        recordingStartTime = nil
        lastVideoPTS = nil
        pendingVideoBuffers.removeAll(keepingCapacity: true)
        pendingAudioBuffers.removeAll(keepingCapacity: true)
    }

    private func resetState() {
        elapsedRecordingTime = 0
        elapsedPausedTime = 0
        recordingWallClockStart = nil
        playerCurrentTime = 0
        state = .idle
        player = nil
        isReadyToSave = false
        isShowingLivePreview = true
        previewImage = nil

        assetWriter = nil
        videoInput = nil
        audioInput = nil
        recordingStartTime = nil
        lastVideoPTS = nil
        pendingVideoBuffers.removeAll(keepingCapacity: true)
        pendingAudioBuffers.removeAll(keepingCapacity: true)
    }

    // MARK: - Playback

    private func ensurePlaybackSessionActive() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            // ignore
        }
    }

    private func playRecording() {
        ensurePlaybackSessionActive()
        guard let url = recordingURL else { return }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        addPlayerObserver()
        player?.play()
        state = .playing
        isShowingLivePreview = false
        startTimer()
    }

    private func pausePlayback() {
        player?.pause()
        state = .paused
        stopTimer()
    }

    private func resumePlayback() {
        player?.play()
        state = .playing
        startTimer()
    }

    private func stopPlaybackIfNeeded() {
        if state == .playing || state == .paused {
            player?.pause()
            player = nil
            state = .idle
            stopTimer()
            isShowingLivePreview = true
        }
    }

    func exposePlayer() -> AVPlayer? {
        player
    }

    // MARK: - Helpers

    private func getFileSize(url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private func getVideoDuration(url: URL) -> Double {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            // Ignore silently
        }
    }

    private func addPlayerObserver() {
        removePlayerObserver()
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.playbackDidFinish()
        }
    }

    private func removePlayerObserver() {
        if let obs = playerItemObserver {
            NotificationCenter.default.removeObserver(obs)
            playerItemObserver = nil
        }
    }

    private func playbackDidFinish() {
        stopPlaybackIfNeeded()
    }

    // MARK: - Generate Midpoint Thumbnail

    private func generateMidpointThumbnail(for url: URL, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            guard duration.isFinite && duration > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let midpoint = CMTime(seconds: duration / 2.0, preferredTimescale: 600)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            do {
                let cgImage = try generator.copyCGImage(at: midpoint, actualTime: nil)
                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async { completion(image) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Notifications

    private func installNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAudioInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAudioRouteChange(_:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAudioInterruption(_ notif: Notification) {
        guard let userInfo = notif.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            if state == .recording {
                stopRecording()
                shouldResumeAfterInterruption = true
            } else if state == .playing {
                pausePlayback()
                shouldResumeAfterInterruption = true
            }
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), shouldResumeAfterInterruption {
                if state == .paused { resumePlayback() }
                shouldResumeAfterInterruption = false
            }
        @unknown default:
            break
        }
    }

    @objc private func handleAudioRouteChange(_ notif: Notification) {
        guard let userInfo = notif.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            if state == .recording {
                stopRecording()
                shouldResumeAfterRouteChange = true
            } else if state == .playing {
                pausePlayback()
                shouldResumeAfterRouteChange = true
            }
        }
    }

    @objc private func handleWillResignActive() {
        if state == .recording {
            stopRecording()
            shouldResumeAfterResignActive = true
        } else if state == .playing {
            pausePlayback()
            shouldResumeAfterResignActive = true
        }
    }

    @objc private func handleDidBecomeActive() {
        if shouldResumeAfterResignActive {
            if state == .paused { resumePlayback() }
            shouldResumeAfterResignActive = false
        }
    }

    // MARK: - File URL Helpers

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func newRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "motivo_vid_\(formatter.string(from: Date())).mov"
        return documentsDirectory().appendingPathComponent(filename)
    }

    // MARK: - Sample Buffer Delegates

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let mediaType = CMSampleBufferGetFormatDescription(sampleBuffer)
            .flatMap { CMFormatDescriptionGetMediaType($0) }

        switch mediaType {
        case kCMMediaType_Video:
            // Funnel ALL writer work through a single serial queue to avoid races on cold start.
            writerQueue.async { [weak self] in
                self?.handleVideoSampleBuffer(sampleBuffer, from: connection)
            }

        case kCMMediaType_Audio:
            // Funnel ALL writer work through a single serial queue to avoid races on cold start.
            writerQueue.async { [weak self] in
                self?.handleAudioSampleBuffer(sampleBuffer)
            }

        default:
            break
        }
    }

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                         from connection: AVCaptureConnection) {
        // Fresh-install warm-up runs while idle to prime the pipeline.
        if isFreshInstallWarmupArmed && !isFreshInstallWarmupCompleted {
            handleFreshInstallWarmupVideoSampleBuffer(sampleBuffer)
        }

        guard state == .recording else { return }

        if !dbgSawFirstVideoSample {
            dbgSawFirstVideoSample = true
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            dbg("first VIDEO sample received; pts=\(pts.seconds)s; writer.status=\(assetWriter?.status.rawValue ?? -1)")
        }

        guard let writer = assetWriter,
              let vInput = videoInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if writer.status == .unknown {
            // Lock orientation at first frame if needed
            if let conn = videoOutput?.connection(with: .video), conn.isVideoOrientationSupported {
                currentVideoOrientation = conn.videoOrientation
            }

            dbg("startWriting() begin")
            let __t0 = CACurrentMediaTime()
            writer.startWriting()
            let __dt = (CACurrentMediaTime() - __t0) * 1000.0
            dbg(String(format: "startWriting() end %.1f ms; status=\(writer.status.rawValue)", __dt))
            dbg("startSession(at: pts) about to call; pts=\(pts.seconds)s; writer.status=\(writer.status.rawValue); pendingVideo=\(pendingVideoBuffers.count); pendingAudio=\(pendingAudioBuffers.count)")

            ensureSessionStarted(with: pts)

            // DEBUG timing: print once on first video frame that starts the writer session
            if !debugDidPrintFirstFrameTiming, let tap = debugRecordTapMonotonic {
                debugDidPrintFirstFrameTiming = true
                let deltaMs = (CACurrentMediaTime() - tap) * 1000.0
                print(String(format: "[RecorderTiming] firstVideoFrame→writerStart %.0f ms", deltaMs))
            }

            // Start the UI timer when the writer session actually starts (not on button tap).
            DispatchQueue.main.async { [weak self] in
                if self?.recordingWallClockStart == nil {
                    self?.recordingWallClockStart = Date()
                }
            }
        }

        // Ensure we start a writer session before any append when startWriting() has been primed earlier.
        if recordingStartTime == nil, writer.status == .writing {
            dbg("startSession(at: pts) about to call; pts=\(pts.seconds)s; pendingVideo=\(pendingVideoBuffers.count); pendingAudio=\(pendingAudioBuffers.count)")
            ensureSessionStarted(with: pts)
        }

        guard writer.status == .writing else { return }

        if vInput.isReadyForMoreMediaData {
            // First, flush any buffered frames (oldest first) before writing the current frame.
            while !pendingVideoBuffers.isEmpty, vInput.isReadyForMoreMediaData {
                let buffered = pendingVideoBuffers.removeFirst()
                let bpts = CMSampleBufferGetPresentationTimeStamp(buffered)

                // Monotonic guard
                if !canAppendVideo(bpts) { continue }

                dbg("append VIDEO buffered; pts=\(bpts.seconds)s; sessionStarted=\(recordingStartTime != nil); writer.status=\(writer.status.rawValue)")
                if vInput.append(buffered) {
                    recordVideoAppend(bpts)
                }
            }

            if vInput.isReadyForMoreMediaData {
                // Monotonic guard
                if canAppendVideo(pts) {
                    dbg("append VIDEO current; pts=\(pts.seconds)s; sessionStarted=\(recordingStartTime != nil); writer.status=\(writer.status.rawValue); ready=\(vInput.isReadyForMoreMediaData)")
                    if vInput.append(sampleBuffer) {
                        recordVideoAppend(pts)
                    }
                }
            } else {
                // Writer back-pressured mid-flush: queue the current frame for later.
                if pendingVideoBuffers.count < maxPendingVideoBuffers {
                    pendingVideoBuffers.append(sampleBuffer)
                } else {
                    // FIFO full: drop newest (this frame) to preserve earliest continuity and avoid a start-gap.
                }
            }
        } else {
            // Not ready: enqueue current buffer (drop newest if over max to preserve the earliest frames).
            if pendingVideoBuffers.count < maxPendingVideoBuffers {
                pendingVideoBuffers.append(sampleBuffer)
            } else {
                // FIFO full: drop newest (this frame) to preserve earliest continuity and avoid a start-gap.
            }
        }
    }

    private func startWriterSessionFromBufferedIfPossible() {
        // Must be called on writerQueue
        guard let writer = assetWriter,
              let _ = videoInput else { return }
        guard recordingStartTime == nil else { return }
        guard writer.status == .writing else { return }
        guard let first = pendingVideoBuffers.first else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(first)
        dbg("startSession(at: pts) about to call; pts=\(pts.seconds)s; writer.status=\(writer.status.rawValue); pendingVideo=\(pendingVideoBuffers.count); pendingAudio=\(pendingAudioBuffers.count)")
        ensureSessionStarted(with: pts)

        // Single timing line: record tap → writer session start
        if !debugDidPrintFirstFrameTiming, let tap = debugRecordTapMonotonic {
            let ms = Int((CACurrentMediaTime() - tap) * 1000.0)
            debugDidPrintFirstFrameTiming = true
            print("[RecorderTiming] recordTap→writerSessionStart \(ms) ms")
        }
    }

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording else { return }
        if !dbgSawFirstAudioSample {
            dbgSawFirstAudioSample = true
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            dbg("first AUDIO sample received; pts=\(pts.seconds)s; writer.status=\(assetWriter?.status.rawValue ?? -1)")
        }

        guard let writer = assetWriter,
              let aInput = audioInput else { return }

        // Ensure we have a video start time before appending audio to keep A/V aligned.
        if recordingStartTime == nil {
            if pendingAudioBuffers.count < maxPendingAudioBuffers {
                pendingAudioBuffers.append(sampleBuffer)
            }
            return
        }
        // If we just started the session, flush any buffered audio that is >= start time.
        if !pendingAudioBuffers.isEmpty, let start = recordingStartTime {
            while !pendingAudioBuffers.isEmpty {
                let b = pendingAudioBuffers.removeFirst()
                let pts = CMSampleBufferGetPresentationTimeStamp(b)
                if pts >= start {
                    if aInput.isReadyForMoreMediaData {
                        dbg("append AUDIO buffered; pts=\(pts.seconds)s; sessionStarted=\(recordingStartTime != nil); writer.status=\(writer.status.rawValue)")
                        _ = aInput.append(b)
                    }
                }
            }
        }

        if writer.status == .writing, aInput.isReadyForMoreMediaData {
            dbg("append AUDIO current; pts=\(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)s; sessionStarted=\(recordingStartTime != nil); writer.status=\(writer.status.rawValue); ready=\(aInput.isReadyForMoreMediaData)")
            _ = aInput.append(sampleBuffer)
        }
    }
}

// MARK: - Preview & Player Views

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?
    let isLive: Bool

    func makeUIView(context: Context) -> PreviewContainerView {
        PreviewContainerView()
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if let l = uiView.layer as? AVCaptureVideoPreviewLayer {
            l.session = session
            l.videoGravity = .resizeAspectFill
            uiView.isHidden = !(isLive && session != nil)
            uiView.refreshOrientation()
        }
    }
}

private final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let l = self.layer as? AVCaptureVideoPreviewLayer {
            l.frame = bounds
            l.videoGravity = .resizeAspectFill
            if let conn = l.connection, conn.isVideoOrientationSupported {
                conn.videoOrientation = PreviewContainerView.currentOrientation()
            }
        }
    }

    func refreshOrientation() {
        if let l = self.layer as? AVCaptureVideoPreviewLayer,
           let conn = l.connection, conn.isVideoOrientationSupported {
            conn.videoOrientation = PreviewContainerView.currentOrientation()
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = true
            }
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    static func currentOrientation() -> AVCaptureVideoOrientation {
        // Ensure UIKit APIs are always accessed from the main thread.
        if Thread.isMainThread {
            return currentOrientationOnMain()
        } else {
            return DispatchQueue.main.sync {
                currentOrientationOnMain()
            }
        }
    }

    private static func currentOrientationOnMain() -> AVCaptureVideoOrientation {
        let o = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation

        switch o {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
}

private struct PlayerPreview: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerContainerView { PlayerContainerView() }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if let l = uiView.layer as? AVPlayerLayer {
            l.player = player
            uiView.setNeedsLayout()
        }
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let l = self.layer as? AVPlayerLayer {
            l.frame = bounds
            l.videoGravity = .resizeAspectFill
        }
    }
}

#if DEBUG
#Preview {
    VideoRecorderView { url in
        print("Saved video at url: \(url)")
    }
}
#endif
