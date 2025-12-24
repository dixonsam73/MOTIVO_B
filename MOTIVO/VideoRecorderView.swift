// CHANGE-ID: 20251215-VIDREC-ORIENT-008
// SCOPE: Fix landscape orientation regressions (front preview snap + squashed output) and rear-camera crash on Stop by syncing orientation at writer setup and serializing stop/finish on writerQueue. Preserve cadence-gated start + retimed commit.

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
                            Text(controller.state == .idle && !controller.isRecorderReady ? "Preparing…" : controller.title)
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
                                          isDisabled: controller.recordingButtonDisabled || !controller.isRecorderReady || controller.state == .playing || controller.state == .paused)
                            ControlButton(systemName: "stop.fill",
                                          color: tintStopDelete,
                                          accessibilityLabel: "Stop",
                                          action: { controller.stopTapped() },
                                          isDisabled: !(controller.state == .recording || controller.state == .pausedRecording))
                            ControlButton(systemName: controller.playPauseButtonSystemName,
                                          color: tintPlay,
                                          accessibilityLabel: controller.playPauseButtonAccessibilityLabel,
                                          action: { controller.playPauseTapped() },
                                          isDisabled: controller.state == .recording || controller.state == .pausedRecording || controller.recordingURL == nil)
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
    private var dbgDidLogFirstTimerTick: Bool = false
    private var dbgLastElapsedSeconds: Double? = nil
    private var dbgDidLogWriterStartWriting: Bool = false
    private var dbgDidLogWriterInputsCreated: Bool = false
    private var dbgDidLogFirstBufferedFlush: Bool = false
    private var dbgSawFirstAudioSample = false

    private func dbg(_ msg: String) {
        let t = String(format: "%.3f", CACurrentMediaTime())
        let thread = Thread.isMainThread ? "main" : "bg"
        print("[VidRec \(dbgID)] [\(t)] [\(thread)] \(msg)")
    }

    // Video first-2s logging state
    private var logVideoFirst2sStartPTS: CMTime? = nil
    private var logVideoFirst2sFrameIndex: Int = 0

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
    
    // Recorder readiness for UI ("Preparing…" vs title). Set true on first received video frame.
    @Published private(set) var isRecorderReady: Bool = false

    private var isArmedToRecord: Bool = false

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

    // Added: Track last appended video PTS for monotonicity enforcement
    private var lastAppendedVideoPTS: CMTime? = nil

    // MARK: - Cadence stabilization gate (Solution A)
    // User taps Record -> recording is armed, but writer session does not start until video cadence is stable.
    // We observe and discard early video frames until we see N consecutive frame deltas within tolerance,
    // and (optionally) a minimum elapsed time has passed. Hard-capped to avoid pathological waits.
    private var isRecordingArmed: Bool = false
    private var cadenceStableCount: Int = 0
    private var cadenceLastPTS: CMTime? = nil
    private var cadenceArmMonotonic: CFTimeInterval = 0

    private let cadenceMinDelta: Double = 0.025   // seconds
    private let cadenceMaxDelta: Double = 0.045   // seconds
    private let cadenceRequiredStable: Int = 6
    private let cadenceMinElapsed: Double = 0.250 // seconds
    private let cadenceHardCap: Double = 2.000    // seconds

    private var droppedAudioBeforeSessionCount: Int = 0

    private var recordingStartTime: CMTime?
    private var sessionStartPTS: CMTime? // PTS used for writer.startSession; set at first accepted video frame (Solution A)
    private var writerSessionReady: Bool = false // startSession(atSourceTime:) has returned; commit on next video frame
    private var retimeBasePTS: CMTime? = nil // first frame PTS used to retime output so playback starts when UI shows recording
    // --- Monotonic/session guards (injected) ---
    private var lastVideoPTS: CMTime?
    private var writerStatusObservation: NSKeyValueObservation?

    private let captureVideoQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.captureVideoQueue")
    private let captureAudioQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.captureAudioQueue")
    private let writerQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.writerQueue")
    private let sessionStartQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.sessionStartQueue")
    private var isStartingWriterSession: Bool = false
    private var isStoppingRecording: Bool = false
    private var pendingFirstAcceptedVideoBuffer: CMSampleBuffer?
    // Buffers accumulated while startSession(atSourceTime:) is blocking off-queue.
    // These are *post-gate* stable cadence frames; we flush them immediately once the writer session is started
    // to avoid a leading timeline gap (frozen first frame).
    private var pendingSessionStartPTS: CMTime?
    private var pendingVideoDuringSessionStart: [CMSampleBuffer] = []
    private var pendingAudioDuringSessionStart: [CMSampleBuffer] = []
    private let sessionQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.sessionQueue")

    private var isSessionConfigured = false
    private var shouldResumeAfterInterruption = false
    private var shouldResumeAfterRouteChange = false
    private var shouldResumeAfterResignActive = false
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
        isRecorderReady = false
        isArmedToRecord = false
    }

    deinit {
        removePlayerObserver()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle hooks

    func onAppear() {
        installNotifications()
        DispatchQueue.main.async {
            self.isShowingLivePreview = true
        }
        isRecorderReady = false
        isArmedToRecord = false

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
        case .idle:
            if !isRecorderReady {
                return "Preparing…"
            }
            return "Ready to Record"
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
        dbg("UI timer startTimer() invoked; state=\(state)")
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

            if !dbgDidLogFirstTimerTick {
                dbgDidLogFirstTimerTick = true
                dbg("UI timer first tick; elapsed=\(String(format: "%.3f", elapsedRecordingTime))s; recordingWallClockStart=\(recordingWallClockStart != nil)")
            }
            if let last = dbgLastElapsedSeconds {
                // If elapsed time ever moves backwards, capture it (this matches the 'erratic timer' symptom).
                if elapsedRecordingTime + 0.050 < last {
                    dbg("UI timer anomaly: elapsed moved backwards; last=\(String(format: "%.3f", last))s now=\(String(format: "%.3f", elapsedRecordingTime))s")
                }
            }
            dbgLastElapsedSeconds = elapsedRecordingTime
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
        vOutput.setSampleBufferDelegate(self, queue: captureVideoQueue)
        if session.canAddOutput(vOutput) {
            session.addOutput(vOutput)
        }

        // Audio data output
        let aOutput = AVCaptureAudioDataOutput()
        aOutput.setSampleBufferDelegate(self, queue: captureAudioQueue)
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
            if !dbgDidLogWriterInputsCreated {
                dbgDidLogWriterInputsCreated = true
                dbg("writer inputs created+added; videoSettings=\(String(describing: vInput.outputSettings)); audioSettings=\(String(describing: aInput.outputSettings))")
            }

        self.assetWriter = writer
        self.videoInput = vInput
        self.audioInput = aInput
        self.recordingStartTime = nil
        self.lastVideoPTS = nil
        self.lastAppendedVideoPTS = nil
    }

    // MARK: - Monotonic/session helpers (type-scope)

    private func beginStartWriterSessionIfNeeded(startPTS pts: CMTime, firstVideoBuffer: CMSampleBuffer) {
        // Called on writerQueue from video sample processing.
        guard let writer = assetWriter else { return }
        guard recordingStartTime == nil else { return } // already started
        guard !isStartingWriterSession else { return }

        // Latch the first accepted buffer so we can append it after startSession returns.
        isStartingWriterSession = true
        pendingFirstAcceptedVideoBuffer = firstVideoBuffer

        // Kick startSession on a separate queue so we never block writerQueue (sample processing).
        sessionStartQueue.async { [weak self] in
            guard let self = self else { return }
            self.startWriterSessionBlocking(startPTS: pts, writer: writer)
        }
    }

    private func startWriterSessionBlocking(startPTS pts: CMTime, writer: AVAssetWriter) {
        // Runs on sessionStartQueue. This call may block inside AVAssetWriter.startSession(...)
        // so it MUST NOT run on writerQueue (which also processes capture samples).
        // All state mutations remain on writerQueue.

        // Snapshot the first accepted buffer (latched on writerQueue before this is called).
        var firstBuf: CMSampleBuffer?
        writerQueue.sync {
            firstBuf = pendingFirstAcceptedVideoBuffer
        }

        // Start writer + session on this (non-sample) queue.
        if writer.status == .unknown {
            dbg("writer.startWriting() at session start; status=\(writer.status.rawValue)")
            writer.startWriting()
        }

        writer.startSession(atSourceTime: .zero)

        // Now that startSession has returned, commit start state and append the first buffer.
        writerQueue.async { [weak self] in
            guard let self = self else { return }

            // startSession(atSourceTime:) has returned. Do NOT commit recordingStartTime yet.
            // We commit on the *next* video frame so output begins exactly where UI shows recording.
            self.sessionStartPTS = .zero
            self.writerSessionReady = true

            // Clear any pre-session buffers (we intentionally drop pre-roll).
            self.pendingVideoBuffers.removeAll(keepingCapacity: true)
            self.pendingAudioBuffers.removeAll(keepingCapacity: true)
            self.pendingVideoDuringSessionStart.removeAll(keepingCapacity: true)
            self.pendingAudioDuringSessionStart.removeAll(keepingCapacity: true)

            self.pendingFirstAcceptedVideoBuffer = nil
            self.pendingSessionStartPTS = nil
            self.isStartingWriterSession = false

            self.dbg(String(format: "startSession (at 0) returned; awaiting first frame to commit; gatePTS=%.3f",
                            pts.seconds))
        }
    }

    private func ensureSessionStarted(with pts: CMTime) {
        // Deprecated by Solution A async session start.
        // Session start is performed only by startWriterSessionBlocking(...) on sessionStartQueue.
        // Keep this as a safety no-op to avoid reintroducing pre-session writes.
        if recordingStartTime == nil {
            dbg(String(format: "ensureSessionStarted ignored (session start handled elsewhere); pts=%.3f", pts.seconds))
        }
    }

    
    private func retimedSampleBuffer(_ sampleBuffer: CMSampleBuffer, basePTS: CMTime) -> CMSampleBuffer? {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: CMTimeSubtract(pts, basePTS),
            decodeTimeStamp: dts.isValid ? CMTimeSubtract(dts, basePTS) : dts
        )

        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &out
        )
        if status != noErr { return nil }
        return out
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


    

    

    

    

    

    // MARK: - Recording Control

    private func startRecording() {
        guard state == .idle || state == .pausedRecording else { return }
        dbg("startRecording() tap; state=\(state)")
        // DEBUG: mark record tap time (monotonic) for first-frame timing line
        debugRecordTapMonotonic = CACurrentMediaTime()
        // Reset timer state for a new clip (prevents zero-stuck / backwards anomalies)
        elapsedRecordingTime = 0
        elapsedPausedTime = 0
        recordingWallClockStart = nil
        isStoppingRecording = false
        debugDidPrintFirstFrameTiming = false
        configureAudioSession()
        // Latch current interface orientation immediately on main to avoid race with async session connection updates.
        // This ensures writer canvas/orientation is correct for first frames in landscape.
        self.currentVideoOrientation = PreviewContainerView.currentOrientation()
        sessionQueue.async {
            self.configureSessionIfNeeded()
            if let conn = self.videoOutput?.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = PreviewContainerView.currentOrientation()
                self.currentVideoOrientation = conn.videoOrientation
            }
            self.startCaptureSession()
        }

        // Arm to record on first accepted frame
        isArmedToRecord = true
        
        
        isReadyToSave = false
        
        // Create URL now, but do NOT create writer or start writing here - will be deferred to first accepted frame
        if recordingURL == nil {
            let url = newRecordingURL()
            recordingURL = url
        }
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        // Clear any prior writer in case
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        recordingStartTime = nil
        lastVideoPTS = nil
        lastAppendedVideoPTS = nil

        // Initialize cadence gate for Solution A (discard early frames until cadence is stable).
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRecordingArmed = true
            self.cadenceStableCount = 0
            self.cadenceLastPTS = nil
            self.cadenceArmMonotonic = CACurrentMediaTime()
            self.sessionStartPTS = nil
            self.writerSessionReady = false
            self.retimeBasePTS = nil
            self.droppedAudioBeforeSessionCount = 0
        }

        // Remove immediate UI/timer start semantics on tap:
        // recordingWallClockStart = Date()
        // state = .recording
        // startTimer()
        // Keep isShowingLivePreview true as-is
        isShowingLivePreview = true
    }

    private func stopRecording() {
        guard state == .recording || state == .pausedRecording else { return }

        // Stop must be serialized against ongoing sample appends to avoid races/crashes (especially rear camera in landscape).
        // We stop accepting new samples immediately, then finish the writer on writerQueue.
        dbg("stopRecording() called; writer.status=\(assetWriter?.status.rawValue ?? -1); startTimeSet=\(recordingStartTime != nil)")

        pendingStartRecordingToken = nil
        stopTimer()
        recordingWallClockStart = nil

        // Prevent any further sample processing as early as possible.
        isArmedToRecord = false
        writerQueue.async { [weak self] in
            self?.isStoppingRecording = true
        }

        guard let finishURL = recordingURL else {
            state = .idle
            finishRecordingWithError()
            return
        }

        // Finish on writerQueue to avoid calling markAsFinished/finishWriting concurrently with append on writerQueue.
        writerQueue.async { [weak self] in
            guard let self = self else { return }

            guard let writer = self.assetWriter else {
                DispatchQueue.main.async {
                    self.state = .idle
                    self.finishRecordingWithError()
                }
                return
            }

            self.dbg("stopRecording finishing on writerQueue; pendingVideo=\(self.pendingVideoBuffers.count); pendingAudio=\(self.pendingAudioBuffers.count)")

            // Best effort: drain any buffered video that can still be appended before closing.
            if let vInput = self.videoInput {
                self.drainPendingVideo(vInput)
                vInput.markAsFinished()
            }
            if let aInput = self.audioInput {
                aInput.markAsFinished()
            }

            writer.finishWriting { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if writer.status == .completed {
                        self.handleRecordingFinishedSuccessfully(url: finishURL)
                    } else {
                        self.finishRecordingWithError()
                    }
                    self.state = .idle
                }
            }
        }

        // Immediately reflect stopped state in UI.
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
        lastAppendedVideoPTS = nil
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
        lastAppendedVideoPTS = nil
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
        lastAppendedVideoPTS = nil
        pendingVideoBuffers.removeAll(keepingCapacity: true)
        pendingAudioBuffers.removeAll(keepingCapacity: true)
        isArmedToRecord = false
        // Note: Do not reset isRecorderReady here to avoid breaking readiness mid-session.
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
            let sb = sampleBuffer // retain reference
            writerQueue.async { [weak self] in
                self?.handleVideoSampleBuffer(sb, from: connection)
            }
        case kCMMediaType_Audio:
            let sb = sampleBuffer // retain reference
            writerQueue.async { [weak self] in
                self?.handleAudioSampleBuffer(sb)
            }
        default:
            break
        }
    }

    // Helper to drain pending video buffers with monotonic check and logging
    private func drainPendingVideo(_ vInput: AVAssetWriterInput) {
        var drained = 0
        while !pendingVideoBuffers.isEmpty, vInput.isReadyForMoreMediaData {
            let buffered = pendingVideoBuffers.removeFirst()
            let bpts = CMSampleBufferGetPresentationTimeStamp(buffered)
            // Monotonic check
            if let last = lastAppendedVideoPTS, bpts < last {
                dbg("NON_MONOTONIC_VIDEO_PTS drop buffered; last=\(last.seconds) pts=\(bpts.seconds)")
                continue
            }
            // First-2s logging for buffered frames
            if let start = logVideoFirst2sStartPTS {
                let dt = CMTimeGetSeconds(CMTimeSubtract(bpts, start))
                if dt >= 0 && dt <= 2.0 {
                    let idx = logVideoFirst2sFrameIndex
                    let last = lastAppendedVideoPTS?.seconds ?? lastVideoPTS?.seconds
                    let delta = (last != nil) ? (bpts.seconds - (last!)) : 0.0
                    dbg(String(format: "VIDEO[%.0fms] idx=%d pts=%.6fs Δ=%.6f action=append(buffered) ready=%@", dt*1000.0, idx, bpts.seconds, delta, vInput.isReadyForMoreMediaData ? "true" : "false"))
                    logVideoFirst2sFrameIndex = idx + 1
                }
            }
            if vInput.append(buffered) {
                lastAppendedVideoPTS = bpts
                recordVideoAppend(bpts)
                drained += 1
            }
        }
        if drained > 0 {
            dbg("drain video: drained=\(drained) pending=\(pendingVideoBuffers.count)")
        }
    }

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                         from connection: AVCaptureConnection) {
        // Assume we're on writerQueue here

        // Mark the recorder as ready once we receive any video frame for preview.
        if !isRecorderReady {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.isRecorderReady { self.isRecorderReady = true }
            }
        }

        // Only process writer logic when recording is armed (button tap occurred).
        guard isArmedToRecord else { return }

        // If a stop is in progress, ignore any late-arriving samples to avoid races with finishWriting().
        if isStoppingRecording { return }

        // Lazily create writer on first observed frame after arming.
        // Keep our latched orientation in sync with the actual capture connection.
        // This avoids writing a portrait canvas when the UI is in landscape (race during session reconfiguration).
        if connection.isVideoOrientationSupported {
            self.currentVideoOrientation = connection.videoOrientation
        }

        if assetWriter == nil {
            guard let url = recordingURL else {
                isArmedToRecord = false
                return
            }
            do {
                try setupWriter(for: url)
            } catch {
                dbg("setupWriter failed: \(error)")
                isArmedToRecord = false
                return
            }
        }

        guard let writer = assetWriter,
              let vInput = videoInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // -------------------------
        // Solution A: Cadence gate
        // -------------------------
        if recordingStartTime == nil {
            // While startSession(atSourceTime:) is blocking off-queue, discard all frames (we intentionally drop pre-roll).
            if isStartingWriterSession {
                return
            }

            // If startSession has returned, commit recording start on the *next* video frame.
            if writerSessionReady {
                writerSessionReady = false
                retimeBasePTS = pts

                // Commit start in input-time domain.
                recordingStartTime = pts
                sessionStartPTS = .zero
                lastVideoPTS = .zero
                lastAppendedVideoPTS = nil

                // Append this first frame retimed to t=0.
                if let v0 = retimedSampleBuffer(sampleBuffer, basePTS: pts), vInput.isReadyForMoreMediaData {
                    _ = vInput.append(v0)
                    lastAppendedVideoPTS = .zero
                    recordVideoAppend(.zero)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.state != .recording { self.state = .recording }
                    self.recordingWallClockStart = Date()
                    self.startTimer()
                }

                return
            }

            // -------------------------
            // Solution A: Cadence gate
            // -------------------------
            if !isRecordingArmed {
                isRecordingArmed = true
                cadenceStableCount = 0
                cadenceLastPTS = nil
                cadenceArmMonotonic = CACurrentMediaTime()
            }

            if let last = cadenceLastPTS {
                let delta = CMTimeGetSeconds(CMTimeSubtract(pts, last))
                if delta >= cadenceMinDelta && delta <= cadenceMaxDelta {
                    cadenceStableCount += 1
                } else {
                    cadenceStableCount = 0
                }
            }
            cadenceLastPTS = pts

            let elapsed = CACurrentMediaTime() - cadenceArmMonotonic
            let gateOpen = (cadenceStableCount >= cadenceRequiredStable && elapsed >= cadenceMinElapsed) || elapsed >= cadenceHardCap

            if !gateOpen {
                // Discard early frames until cadence stabilizes.
                return
            }

            // Open once per armed recording.
            if isStartingWriterSession || pendingSessionStartPTS != nil { return }
            pendingSessionStartPTS = pts
            dbg(String(format: "cadence gate open; stable=%d elapsedMs=%d gatePTS=%.3f",
                       cadenceStableCount,
                       Int(elapsed * 1000.0),
                       pts.seconds))

            beginStartWriterSessionIfNeeded(startPTS: pts, firstVideoBuffer: sampleBuffer)
            return
        }


        guard writer.status == .writing,
              let startPTS = recordingStartTime else { return }

        // Monotonic safety: never append a video frame earlier than our latched start PTS.
        if pts < startPTS { return }

        guard let base = retimeBasePTS,
              let outSB = retimedSampleBuffer(sampleBuffer, basePTS: base) else { return }
        let outPTS = CMSampleBufferGetPresentationTimeStamp(outSB)

        // Append or buffer when backpressured (post-start behavior).
        if !vInput.isReadyForMoreMediaData {
            if pendingVideoBuffers.count < maxPendingVideoBuffers {
                pendingVideoBuffers.append(outSB)
                dbg("enqueue video (backpressure) pending=\(pendingVideoBuffers.count) pts=\(outPTS.seconds)")
            }
            return
        }

        // If there are buffered frames waiting to be drained, keep ordering by PTS:
        // enqueue this live frame and let drainPendingVideo() flush in-order.
        if !pendingVideoBuffers.isEmpty {
            if pendingVideoBuffers.count < maxPendingVideoBuffers {
                pendingVideoBuffers.append(outSB)
            }
            // Try to drain as soon as we become ready to avoid starving the writer (frozen playback).
            drainPendingVideo(vInput)
            return
        }

        if canAppendVideo(outPTS) && vInput.append(outSB) {
            lastAppendedVideoPTS = outPTS
            recordVideoAppend(outPTS)
            drainPendingVideo(vInput)
        } else {
            if pendingVideoBuffers.count < maxPendingVideoBuffers {
                pendingVideoBuffers.append(outSB)
                dbg("enqueue video (append-failed) pending=\(pendingVideoBuffers.count) pts=\(outPTS.seconds)")
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
        dbg("startSession(at: pts) about to call; pts=\(pts.seconds); writer.status=\(writer.status.rawValue); pendingVideo=\(pendingVideoBuffers.count); pendingAudio=\(pendingAudioBuffers.count)")

        ensureSessionStarted(with: sessionStartPTS ?? pts)
        if recordingStartTime == nil {
            // Waiting for cold-start stabilization; do not start session yet.
            return
        }

        // Single timing line: record tap → writer session start
        if !debugDidPrintFirstFrameTiming, let tap = debugRecordTapMonotonic {
            let ms = Int((CACurrentMediaTime() - tap) * 1000.0)
            debugDidPrintFirstFrameTiming = true
            print("[RecorderTiming] recordTap→writerSessionStart \(ms) ms")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.state != .recording {
                self.state = .recording
            }
            if self.recordingWallClockStart == nil {
                self.recordingWallClockStart = Date()
            }
            if self.timer == nil {
                self.startTimer()
            }
        }
    }

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording else { return }

        // Drop all audio until we have committed the first video frame (retimeBasePTS is set).
        guard let base = retimeBasePTS else {
            droppedAudioBeforeSessionCount += 1
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if pts < base {
            droppedAudioBeforeSessionCount += 1
            return
        }

        guard let writer = assetWriter,
              let aInput = audioInput,
              let outSB = retimedSampleBuffer(sampleBuffer, basePTS: base) else { return }

        if writer.status == .writing, aInput.isReadyForMoreMediaData {
            _ = aInput.append(outSB)
        } else {
            if pendingAudioBuffers.count < maxPendingAudioBuffers {
                pendingAudioBuffers.append(outSB)
            }
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

