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
                            ControlButton(systemName: "trash", color: tintStopDelete, accessibilityLabel: "Delete", action: { controller.deleteTapped() }, isDisabled: controller.recordingURL == nil)
                            ControlButton(systemName: controller.recordingButtonSystemName, color: tintRecord, accessibilityLabel: controller.recordingButtonAccessibilityLabel, action: { controller.recordPauseResumeTapped() }, isDisabled: controller.recordingButtonDisabled)
                            ControlButton(systemName: "stop.fill", color: tintStopDelete, accessibilityLabel: "Stop", action: { controller.stopTapped() }, isDisabled: !(controller.state == .recording || controller.state == .pausedRecording))
                            ControlButton(systemName: controller.playPauseButtonSystemName, color: tintPlay, accessibilityLabel: controller.playPauseButtonAccessibilityLabel, action: { controller.playPauseTapped() }, isDisabled: controller.recordingURL == nil)
                            ControlButton(systemName: "checkmark.circle.fill", color: tintConfirm, accessibilityLabel: "Save", action: { controller.saveTapped() }, isDisabled: !controller.isReadyToSave)
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

final class VideoRecorderController: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    enum RecordingState {
        case idle
        case recording
        case pausedRecording
        case playing
        case paused
    }

    @Published var state: RecordingState = .idle
    @Published var elapsedRecordingTime: TimeInterval = 0
    @Published var elapsedPausedTime: TimeInterval = 0
    @Published var playerCurrentTime: TimeInterval = 0

    @Published var recordingURL: URL?
    @Published private(set) var isReadyToSave: Bool = false
    @Published var preferredPosition: AVCaptureDevice.Position = .front

    // Added: track if showing live camera preview
    @Published var isShowingLivePreview: Bool = true

    // Added: poster thumbnail image
    @Published var previewImage: UIImage? = nil

    private var timer: Timer?
    private var player: AVPlayer?
    private var playerItemObserver: Any?
    
    private var isFlippingDuringRecording = false

    private(set) var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?

    private var isSessionConfigured = false

    private var shouldResumeAfterInterruption = false
    private var shouldResumeAfterRouteChange = false
    private var shouldResumeAfterResignActive = false

    private let onSave: (URL) -> Void

    init(onSave: @escaping (URL) -> Void) {
        self.onSave = onSave
        super.init()
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
            // Pause not supported for movie output; disable during recording
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
        // Mirror save to StagingStore (video) on main actor
        Task {
            try? await StagingStore.bootstrap()
            let vidURL = url
            let duration = getVideoDuration(url: vidURL)
            var posterURL: URL? = nil
            if let image = previewImage, let jpg = image.jpegData(compressionQuality: 0.85) {
                let p = documentsDirectory().appendingPathComponent("\(UUID().uuidString)_poster").appendingPathExtension("jpg")
                try? jpg.write(to: p, options: .atomic)
                posterURL = p
            }
            do {
                let ref = try await StagingStore.saveNew(from: vidURL, kind: .video, suggestedName: vidURL.deletingPathExtension().lastPathComponent, duration: duration.isFinite ? duration : nil, poster: posterURL)
                // [RecorderDebug] saveNew result
                print("[RecorderDebug] saveNew succeeded")
                print("  id=\(ref.id)")
                print("  relativePath=\(ref.relativePath)")
                let stagedURL = await StagingStore.absoluteURL(forRelative: ref.relativePath)
                let stagedSize = self.getFileSize(url: stagedURL)
                print("  stagedSize=\(stagedSize) bytes")

                // On success, best-effort delete original .mov and temp poster .jpg
                let fm = FileManager.default
                // Delete original video
                if fm.fileExists(atPath: vidURL.path) {
                    do {
                        try fm.removeItem(at: vidURL)
                        print("[RecorderDebug] deleted original video at \(vidURL.path)")
                    } catch {
                        print("[RecorderDebug] FAILED to delete original video at \(vidURL.path): \(error)")
                    }
                } else {
                    print("[RecorderDebug] original video already missing at \(vidURL.path)")
                }
                // Delete poster if present
                if let p = posterURL {
                    if fm.fileExists(atPath: p.path) {
                        do {
                            try fm.removeItem(at: p)
                            print("[RecorderDebug] deleted poster at \(p.path)")
                        } catch {
                            print("[RecorderDebug] FAILED to delete poster at \(p.path): \(error)")
                        }
                    } else {
                        print("[RecorderDebug] poster already missing at \(p.path)")
                    }
                }
            } catch {
                // Staging failed — keep original files; no further action.
                #if DEBUG
                print("[VideoRecorder] Staging failed, keeping original: \(error)")
                #endif
            }
        }
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
        session.sessionPreset = .hd1280x720

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

        // Movie file output
        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            self.movieOutput = movieOutput
        } else {
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
        self.captureSession = session
        isSessionConfigured = true
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
            if !hasAudio, let audioDev = AVCaptureDevice.default(for: .audio), let audioIn = try? AVCaptureDeviceInput(device: audioDev), session.canAddInput(audioIn) {
                session.addInput(audioIn)
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
        movieOutput = nil
        isSessionConfigured = false
    }

    private func startRecording() {
        guard state == .idle || state == .pausedRecording else { return }
        configureAudioSession()
        guard let movieOutput = movieOutput else { return }
        startCaptureSession()

        isReadyToSave = false
        let url = newRecordingURL()
        recordingURL = url
        try? FileManager.default.removeItem(at: url)
        
        if let conn = movieOutput.connection(with: .video) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = PreviewContainerView.currentOrientation()
            }
            if conn.isVideoMirroringSupported {
                conn.isVideoMirrored = (preferredPosition == .front)
            }
        }
        
        movieOutput.startRecording(to: url, recordingDelegate: self)

        elapsedRecordingTime = 0
        elapsedPausedTime = 0
        state = .recording
        isShowingLivePreview = true
        startTimer()
    }

    private func stopRecording() {
        guard state == .recording || state == .pausedRecording else { return }
        movieOutput?.stopRecording()
        stopTimer()
        state = .idle
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
    }

    // MARK: - Playback
    private func playRecording() {
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
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
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

    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            // [RecorderDebug] didFinishRecordingTo
            print("[RecorderDebug] didFinishRecordingTo")
            print("  url=\(outputFileURL.path)")
            let existsAtFinish = FileManager.default.fileExists(atPath: outputFileURL.path)
            print("  exists=\(existsAtFinish)")
            let sizeAtFinish = self?.getFileSize(url: outputFileURL) ?? 0
            print("  size=\(sizeAtFinish) bytes")

            guard let self = self else { return }
            if let _ = error {
                self.cleanupRecordingFile()
                self.resetState()
                return
            }
            // Prepare for preview
            self.recordingURL = outputFileURL
            self.player = AVPlayer(url: outputFileURL)
            self.playerCurrentTime = 0
            
            // Generate poster thumbnail from midpoint
            self.generateMidpointThumbnail(for: outputFileURL) { [weak self] image in
                self?.previewImage = image
            }
            
            self.isReadyToSave = true
            self.state = .idle
            self.isShowingLivePreview = false
            
            Task {
                try? await StagingStore.bootstrap()
            }
        }
    }
}

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

