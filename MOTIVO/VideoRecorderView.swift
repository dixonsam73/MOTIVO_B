// CHANGE-ID: 20251128-HEVC-001
// SCOPE: v7.13A — Video recorder HEVC 1080p pipeline (AVAssetWriter-based)

import SwiftUI
import AVFoundation
import AVKit

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
                GeometryReader { g in
                    let h = g.size.height
                    let scale: CGFloat = h < 700 ? max(0.82, h/700) : 1.0
                    VStack(spacing: 6) {
                        Text(controller.title)
                            .font(.headline)
                            .accessibilityIdentifier("VideoRecorderView_Title")
                            .lineLimit(1)
                        Text(controller.formattedTime)
                            .font(.system(.largeTitle, design: .rounded))
                            .monospacedDigit()
                            .accessibilityIdentifier("VideoRecorderView_Clock")
                            .lineLimit(1)

                        let tintRecord = Color(red: 0.92, green: 0.30, blue: 0.28)       // soft coral/red
                        let tintStopDelete = Color(red: 0.72, green: 0.42, blue: 0.40)   // muted clay / gray-red
                        let tintPlay = Color(red: 0.36, green: 0.60, blue: 0.52)         // desaturated mint / slate green
                        let tintConfirm = Color(red: 0.38, green: 0.48, blue: 0.62)      // slate blue-gray

                        HStack(spacing: 20) {
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
                    .padding(.horizontal, 6)
                    .padding(.bottom, 0)
                    .cardSurface(padding: 12)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .scaleEffect(scale, anchor: .bottom)
                }
                .frame(height: 180)
                .zIndex(10)
            }
        }
        .onAppear {
            controller.onAppear()
            controller.isShowingLivePreview = true
            controller.startCaptureSession()
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
///
/// NOTE: This is a best-effort implementation based on your existing state machine and UI contract.
/// It may need iterative refinement in Xcode with live device testing.
final class VideoRecorderController: NSObject,
                                     ObservableObject,
                                     AVCaptureVideoDataOutputSampleBufferDelegate,
                                     AVCaptureAudioDataOutputSampleBufferDelegate {

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
    private var player: AVPlayer?
    private var playerItemObserver: Any?

    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?

    // Writer pipeline
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    private var recordingStartTime: CMTime?
    private var writerStatusObservation: NSKeyValueObservation?

    private let captureQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.captureQueue")

    private var isSessionConfigured = false
    private var shouldResumeAfterInterruption = false
    private var shouldResumeAfterRouteChange = false
    private var shouldResumeAfterResignActive = false

    private let onSave: (URL) -> Void

    init(onSave: @escaping (URL) -> Void) {
        self.onSave = onSave
        super.init()
    }

    deinit {
        removePlayerObserver()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle hooks

    func onAppear() {
        configureSessionIfNeeded()
        isShowingLivePreview = true
        startCaptureSession()
        installNotifications()
    }

    func onDisappear() {
        stopTimer()
        removeNotifications()
        stopCaptureSession()
        cleanupRecordingFile()
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
            elapsedRecordingTime += 0.1
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
        guard !isSessionConfigured else { return }

        let session = AVCaptureSession()
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
        vOutput.alwaysDiscardsLateVideoFrames = true
        vOutput.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(vOutput) {
            session.addOutput(vOutput)
        }

        // Audio data output
        let aOutput = AVCaptureAudioDataOutput()
        aOutput.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(aOutput) {
            session.addOutput(aOutput)
        }

        // Match orientation & mirroring to preview
        if let conn = vOutput.connection(with: .video) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = PreviewContainerView.currentOrientation()
            }
            if conn.isVideoMirroringSupported {
                conn.isVideoMirrored = (preferredPosition == .front)
            }
        }

        session.commitConfiguration()

        self.captureSession = session
        self.videoOutput = vOutput
        self.audioOutput = aOutput
        self.isSessionConfigured = true
    }

    func flipCamera() {
        // Ensure session exists
        configureSessionIfNeeded()
        guard let session = captureSession else { return }

        // Compute next position and update preference
        let nextPosition: AVCaptureDevice.Position = (preferredPosition == .front) ? .back : .front

        // If currently recording, ignore flip (button is disabled in UI)
        if state == .recording { return }

        // Briefly fade out the preview for a smooth transition
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isShowingLivePreview = false
            }
        }

        preferredPosition = nextPosition

        // Reconfigure inputs on a high-priority queue
        DispatchQueue.global(qos: .userInitiated).async {
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
                }
                if conn.isVideoMirroringSupported {
                    conn.isVideoMirrored = (nextPosition == .front)
                }
            }

            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }

            // Fade back in on main
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.isShowingLivePreview = true
                }
            }
        }
    }

    func startCaptureSession() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .background).async { session.startRunning() }
    }

    private func stopCaptureSession() {
        if let session = captureSession, session.isRunning {
            DispatchQueue.global(qos: .background).async { session.stopRunning() }
        }
        captureSession = nil
        videoOutput = nil
        audioOutput = nil
        isSessionConfigured = false
    }

    // MARK: - Writer Setup

    private func setupWriter(for url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Video settings: HEVC 1080p, balanced bitrate
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000, // ~5 Mbps target
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

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
    }

    // MARK: - Recording Control

    private func startRecording() {
        guard state == .idle || state == .pausedRecording else { return }
        configureAudioSession()
        configureSessionIfNeeded()
        startCaptureSession()

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

        elapsedRecordingTime = 0
        elapsedPausedTime = 0
        state = .recording
        isShowingLivePreview = true
        startTimer()
    }

    private func stopRecording() {
        guard state == .recording || state == .pausedRecording else { return }
        stopTimer()

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
    }

    private func resetState() {
        elapsedRecordingTime = 0
        elapsedPausedTime = 0
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
            handleVideoSampleBuffer(sampleBuffer, from: connection)
        case kCMMediaType_Audio:
            handleAudioSampleBuffer(sampleBuffer)
        default:
            break
        }
    }

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                         from connection: AVCaptureConnection) {
        guard state == .recording else { return }
        guard let writer = assetWriter,
              let vInput = videoInput else { return }

        if writer.status == .unknown {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            recordingStartTime = pts
        }

        guard writer.status == .writing else { return }

        if vInput.isReadyForMoreMediaData {
            _ = vInput.append(sampleBuffer)
        }
    }

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording else { return }
        guard let writer = assetWriter,
              let aInput = audioInput else { return }

        // Ensure we have a video start time before appending audio to keep A/V aligned.
        guard recordingStartTime != nil else { return }

        if writer.status == .writing, aInput.isReadyForMoreMediaData {
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
            uiView.setNeedsLayout()
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

    static func currentOrientation() -> AVCaptureVideoOrientation {
        let o = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation
        switch o {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
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
