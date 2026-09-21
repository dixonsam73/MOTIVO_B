// CHANGE-ID: 20260523_153400_VideoRecorder_AudioSessionPreactivation
// SCOPE: VideoRecorder startup lifecycle hardening — preactivate recording AVAudioSession after preview interactive readiness to reduce first-record cold-start delay. Preserve UI, encoding, bitrate, storage, staging, trim, cadence, and timer behavior.
// SEARCH-TOKEN: 20260523_153400_VideoRecorder_AudioSessionPreactivation

// CHANGE-ID: 20260523_151800_VideoRecorder_PreviewIsolation
// SCOPE: VideoRecorder startup lifecycle hardening — remove preview-time writer warm-up so first-launch camera monitoring remains isolated; preserve duplicate-start latch. No UI, encoding, bitrate, storage, staging, or trim changes.
// SEARCH-TOKEN: 20260523_151800_VideoRecorder_PreviewIsolation


// CHANGE-ID: 20260313_202600_RecorderHygiene_Video_1b9d5e24
// SCOPE: Recorder hygiene hardening — add targeted launch sweep helper for abandoned Documents/motivo_vid_*.mov capture files.
// SEARCH-TOKEN: 20260313_202600_RecorderHygiene_Video_1b9d5e24

// CHANGE-ID: 20260313_164500_REVIEW_LETTERBOX_FIX
// SCOPE: Review-state only — letterboxed playback (.resizeAspect) + scaledToFit for image preview. No recording, writer, orientation, or live preview logic changed.
// SEARCH-TOKEN: 20260313_164500_REVIEW_LETTERBOX_FIX

// CHANGE-ID: 20251215-VIDREC-ORIENT-008
// SCOPE: Fix landscape orientation regressions (front preview snap + squashed output) and rear-camera crash on Stop by syncing orientation at writer setup and serializing stop/finish on writerQueue. Preserve cadence-gated start + retimed commit.

// CHANGE-ID: 20260201_180400_AudioRouteDebugLogs
// SCOPE: DEBUG-only: log AVAudioSession route snapshots at key points (startRecording, routeChange, afterAddAudioInput). No UI/logic changes.
// SEARCH-TOKEN: 20260201_180400_AudioRouteDebugLogs

// CHANGE-ID: 20260201_183200_VidRec_RemoveAllowBluetooth
// SCOPE: Force A2DP-only output; prevent HFP mic takeover in VideoRecorder (DEBUG logs unchanged)
// SEARCH-TOKEN: 20260201_183200_VidRec_RemoveAllowBluetooth

// CHANGE-ID: 20260220_084520_VidRec_ReadinessGate
// SCOPE: VideoRecorder first-launch UX stability — add interactive readiness gate + preparing overlay (Theme token fix only; no changes to A/V capture or writer timing)
// SEARCH-TOKEN: 20260220_084520_VidRec_ReadinessGate

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

    @State private var showPreparingOverlay: Bool = false
    @State private var preparingOverlayTask: Task<Void, Never>? = nil

    public var body: some View {
        ZStack {
            CameraPreview(session: controller.captureSession, isLive: controller.isShowingLivePreview && controller.isInteractiveReady)
                .ignoresSafeArea()

            if controller.state == .idle && showPreparingOverlay && !controller.isInteractiveReady {
                VideoRecorderPreparingOverlay()
                    .transition(.opacity)
                    .accessibilityIdentifier("VideoRecorderView_PreparingOverlay")
            }

            if controller.recordingURL != nil && !controller.isShowingLivePreview {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if controller.state == .playing {
                        PlayerPreview(player: controller.exposePlayer(), gravity: .resizeAspect)
                    } else if let img = controller.previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.black.opacity(0.6)
                    }
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
                            Text(controller.state == .idle && !controller.isInteractiveReady ? "Preparing…" : controller.title)
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
                                          isDisabled: controller.recordingButtonDisabled || !controller.isInteractiveReady || controller.state == .playing || controller.state == .paused)
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
                        .disabled(controller.isFinishingRecording)
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
            startPreparingOverlayTimer()
        }
        .onChange(of: controller.isInteractiveReady) { _, ready in
            if ready {
                preparingOverlayTask?.cancel()
                preparingOverlayTask = nil
                if showPreparingOverlay {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showPreparingOverlay = false
                    }
                }
            }
        }
        .onChange(of: controller.state) { _, newState in
            // C-50. Hooked in the VIEW, exactly as `AudioRecorderView` already
            // does — `VideoRecorderController` is not main-actor isolated, so a
            // `didSet` on `state` could not call a @MainActor guard, and hopping
            // asynchronously would let two rapid transitions land out of order.
            //
            // ONE HOOK FOR 13 ASSIGNMENT SITES: every path that ends a recording
            // — success, cancel and all three error branches — sets
            // `state = .idle`, so none needs its own call. `pausedRecording`
            // deliberately does NOT hold: nothing is being captured, and holding
            // it would keep the screen awake indefinitely.
            RecordingIdleTimerGuard.setHolding(newState == .recording, owner: "video-recorder")
        }
        .onDisappear {
            // C-50. Release explicitly: teardown need not deliver a final SwiftUI onChange.
            RecordingIdleTimerGuard.release("video-recorder")
            controller.onDisappear()
            preparingOverlayTask?.cancel()
            preparingOverlayTask = nil
            showPreparingOverlay = false
            Task {
                try? StagingStore.bootstrap()
            }
        }
        .alert("Video recording", isPresented: Binding(
            get: { controller.recordingError != nil },
            set: { if !$0 { controller.recordingError = nil } }
        )) {
            Button("OK", role: .cancel) { controller.recordingError = nil }
        } message: {
            Text(controller.recordingError ?? "")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - ControlButton
    
    private func startPreparingOverlayTimer() {
        preparingOverlayTask?.cancel()
        preparingOverlayTask = nil
        showPreparingOverlay = false

        // Delay showing the overlay so warm launches feel instant.
        preparingOverlayTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
            if Task.isCancelled { return }

            let shouldShow = (controller.state == .idle) && (!controller.isInteractiveReady)
            if shouldShow {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showPreparingOverlay = true
                    }
                }
            }
        }
    }

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
    @Published private(set) var isFinishingRecording = false
    @Published var recordingError: String?
    var presentationID = UUID()                         // C-97: internal for wiring tests
    /// C-97 part (2). Main-thread only.
    var disruption = CaptureDisruptionTracker()         // C-97: internal for wiring tests
    /// C-97. writerQueue-owned. Never read or written from main.
    var startCoordinator = PendingStartCoordinator()   // C-97: internal for wiring tests
    /// C-97. Injectable so file PRESERVATION can be tested on real files.
    var fileEffects = RecordingFileEffects()
    /// C-97. MAIN-owned mirror of the token main minted for the current start. A
    /// cancellation names THIS claim, so a start armed after the disrupting event -- which
    /// an interruption permits, since it does not set `awaitingReopen` -- is never
    /// cancelled by an older event's request.
    var currentStartToken: UUID?                        // C-97: internal for wiring tests
    /// Advanced on every appear and disappear, so queued disruption work from an earlier
    /// presentation is dropped. Main-thread only.
    private var disruptionGeneration = 0
    private var audioResetObserver: NSObjectProtocol?
    /// `sessionQueue`-owned: the generation capture observers are bound to, and their tokens.
    private var sessionGeneration = 0
    private var captureObserverTokens: [NSObjectProtocol] = []
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

    // Capture session running state (for interactive readiness gating)
    @Published private(set) var isSessionRunning: Bool = false

    // Interactive readiness for UX: preview + controls become available only once the session is running,
    // the first video sample buffer has arrived, and a short settle delay has elapsed. This is set once per presentation.
    @Published private(set) var isInteractiveReady: Bool = false

    private var interactiveReadyWorkItem: DispatchWorkItem? = nil
    private var hasSetInteractiveReady: Bool = false

    private let audioSessionPreactivationQueue = DispatchQueue(label: "com.motivo.videoRecorder.audioSessionPreactivation")
    private var hasPreactivatedRecordingAudioSession: Bool = false
    private var isPreactivatingRecordingAudioSession: Bool = false

    var isArmedToRecord: Bool = false                   // C-97: internal for wiring tests
    var isRecordStartInProgress: Bool = false           // C-97: internal for wiring tests

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

    // Accessed only on writerQueue; created lazily after the existing A/V origin is committed.
    private var audioDelivery: BufferedRecordingAudio<CMSampleBuffer>?

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
    var writerSessionReady: Bool = false                // C-97: internal for wiring tests // startSession(atSourceTime:) has returned; commit on next video frame
    private var retimeBasePTS: CMTime? = nil // first frame PTS used to retime output so playback starts when UI shows recording
    // --- Monotonic/session guards (injected) ---
    private var lastVideoPTS: CMTime?
    private var writerStatusObservation: NSKeyValueObservation?

    private let captureVideoQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.captureVideoQueue")
    private let captureAudioQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.captureAudioQueue")
    // C-97: internal for wiring tests.
    let writerQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.writerQueue")
    private let sessionStartQueue = DispatchQueue(label: "com.motivo.VideoRecorderController.sessionStartQueue")
    var isStartingWriterSession: Bool = false           // C-97: internal for wiring tests
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
    private var shouldResumeAfterResignActive = false
    private var captureSessionBecameRunningAt: Date?

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
        isRecordStartInProgress = false
    }

    deinit {
        removePlayerObserver()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle hooks
    private static let abandonedCapturePrefix = "motivo_vid_"
    private static let abandonedCaptureExtension = "mov"

    static func sweepAbandonedCaptureFilesInDocuments() {
        let fm = FileManager.default
        let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        guard let urls = try? fm.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls {
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix(abandonedCapturePrefix), url.pathExtension.lowercased() == abandonedCaptureExtension else { continue }
            try? fm.removeItem(at: url)
        }
    }


    func onAppear() {
        presentationID = UUID()
        disruptionGeneration += 1
        disruption.reset()
        // C-97. A claim from the previous presentation is RETIRED, not dropped: its
        // startSession may still be blocked, and its continuation must clean up its own
        // writer and file exactly once without touching this presentation's claim.
        writerQueue.async { [weak self] in
            self?.startCoordinator.retireForPresentationChange()
        }

        installNotifications()
        DispatchQueue.main.async {
            self.isShowingLivePreview = true
        }
        isRecorderReady = false
        isArmedToRecord = false

        let generation = disruptionGeneration
        sessionQueue.async {
            // Bind capture observers to THIS presentation, including a session kept from init.
            self.sessionGeneration = generation
            if let session = self.captureSession {
                self.unregisterCaptureObservers(for: session)
                self.registerCaptureObservers(for: session)
            }
            self.configureSessionIfNeeded()
            self.startCaptureSession()
        }
    }

    func onDisappear() {
        stopTimer()
        let wasArmedAtDisappear = isArmedToRecord
        disruptionGeneration += 1
        removeNotifications()
        // C-68 — release the review player explicitly rather than relying on
        // this controller being deallocated with the view. Lifecycle hardening
        // only: no user-visible failure was reproduced, and this is NOT an
        // explanation of C-50.
        player?.pause()
        player = nil
        presentationID = UUID()
        let closingPresentation = presentationID
        isArmedToRecord = false
        state = .idle

        // C-97. Detach a PENDING start's url from main SYNCHRONOUSLY, here at the
        // lifecycle boundary, before any queue hop.
        //
        // Otherwise: this teardown's main cleanup is queued behind a presentation guard;
        // a quick reopen changes `presentationID` so that cleanup is SKIPPED; the next
        // Record finds `recordingURL` still non-nil, REUSES it and deletes it; and the
        // old continuation later deletes what is by then the new take's output. A unique
        // name cannot prevent that, because the url is inherited rather than minted.
        let pendingStartURL: URL? = isRecordStartInProgress || wasArmedAtDisappear ? recordingURL : nil
        if pendingStartURL != nil {
            recordingURL = nil
            isReadyToSave = false
        }
        isRecordStartInProgress = false
        currentStartToken = nil
        writerQueue.async {
            self.audioDelivery?.cancel()
            self.audioDelivery = nil
            // C-97. Retire the claim FIRST, on the queue that owns it. If its
            // `startSession` is still blocked off-queue, the continuation owns that
            // writer and that file and will clean both up exactly once -- so this
            // teardown must not cancel the writer or delete the file underneath it. Two
            // cancellations racing a live startSession is exactly what the retired path
            // exists to avoid.
            let ownedByContinuation = self.startCoordinator.retireForPresentationChange()
            if ownedByContinuation == nil,
               self.assetWriter?.status == .writing {
                self.assetWriter?.cancelWriting()
            }
            // A pending start's file is deleted HERE, from the url latched on main, and
            // never by re-reading `recordingURL` later. If a continuation owns it, it is
            // left alone: that continuation cleans up exactly once.
            if let pendingStartURL, ownedByContinuation == nil {
                self.fileEffects.removeFile(pendingStartURL)
            }
            DispatchQueue.main.async {
                // Detaching a pointer to a file a CONTINUATION owns is done whatever the
                // presentation, and only when it is still exactly that url: leaving it
                // behind is how a later start inherits it and the continuation then
                // deletes the new take. Nothing is deleted here.
                if let owned = ownedByContinuation, self.recordingURL == owned {
                    self.recordingURL = nil
                    self.isReadyToSave = false
                }
                guard self.presentationID == closingPresentation else { return }
                self.isFinishingRecording = false
                guard pendingStartURL == nil, ownedByContinuation == nil else { return }
                self.cleanupRecordingFile()      // a reviewable take, as before
            }
        }
        sessionQueue.async { self.stopCaptureSession() }
    }

    // MARK: - UI Computed

    var title: String {
        if isFinishingRecording { return "Finishing…" }
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
        guard time.isFinite && time >= 0 else { return "00:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

    var recordingButtonDisabled: Bool { state == .recording || isFinishingRecording }

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
        guard !isFinishingRecording else { return }
        recordingError = nil
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
        guard !isFinishingRecording else { return }
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
        guard !isFinishingRecording, isReadyToSave, let url = recordingURL else { return }
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
        guard !isFinishingRecording else { return }
        recordingError = nil
        stopPlaybackIfNeeded()
        stopTimer()
        isArmedToRecord = false
        state = .idle
        isReadyToSave = false
        isFinishingRecording = true
        let presentation = presentationID
        // Cancel queued audio before deleting its writer/file, including Delete during a take.
        writerQueue.async {
            self.audioDelivery?.cancel()
            self.audioDelivery = nil
            if self.assetWriter?.status == .writing { self.assetWriter?.cancelWriting() }
            DispatchQueue.main.async {
                guard self.presentationID == presentation else { return }
                self.cleanupRecordingFile()
                self.resetState()
                self.isFinishingRecording = false
            }
        }
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

            if !dbgDidLogFirstTimerTick {
                dbgDidLogFirstTimerTick = true
             
            }
         
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
        registerCaptureObservers(for: session)
    }

    func flipCamera() {
        // If currently recording, ignore flip (button is disabled in UI)
        if state == .recording { return }
        // C-97 (2): after a reset, capture is only rebuilt by closing and reopening.
        if disruption.blocksNewCapture { recordingError = CaptureDisruptionTracker.reopenMessage; return }

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
                self.isSessionRunning = true
                self.maybeScheduleInteractiveReady()
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
        if let session = captureSession {
            unregisterCaptureObservers(for: session)
            if session.isRunning { session.stopRunning() }
        }
        captureSession = nil
        videoOutput = nil
        audioOutput = nil
        isSessionConfigured = false
 
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSessionRunning = false
            self.isInteractiveReady = false
            self.hasSetInteractiveReady = false
            self.interactiveReadyWorkItem?.cancel()
            self.interactiveReadyWorkItem = nil
        }
    }

    private func maybeScheduleInteractiveReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.hasSetInteractiveReady else { return }
            guard self.isSessionRunning, self.isRecorderReady else { return }

            // Debounce so we only become interactive once the capture pipeline has had a moment to settle.
            self.interactiveReadyWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                guard !self.hasSetInteractiveReady else { return }
                self.hasSetInteractiveReady = true
                self.isInteractiveReady = true
                self.preactivateRecordingAudioSessionIfNeeded()
            }
            self.interactiveReadyWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
        }
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

        // Do not rotate or mirror; choose width/height above to match orientation. Keep preview mirroring only.
        vInput.transform = .identity

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

        // C-97. From here the start CANNOT be stopped: startSession blocks off-queue
        // holding its own strong `writer`. The continuation below is therefore a
        // mandatory participant in cancellation, and carries the claim's token so it can
        // tell "mine", "mine but cancelled" and "retired" apart.
        let token = startCoordinator.currentToken
        let claimPresentation = startCoordinator.claim?.presentation
        if let token { startCoordinator.advance(token, to: .sessionStarting) }

        // Kick startSession on a separate queue so we never block writerQueue (sample processing).
        sessionStartQueue.async { [weak self] in
            guard let self = self else { return }
            self.startWriterSessionBlocking(startPTS: pts, writer: writer, token: token,
                                            claimPresentation: claimPresentation)
        }
    }

    private func startWriterSessionBlocking(startPTS pts: CMTime, writer: AVAssetWriter, token: UUID?,
                                            claimPresentation: UUID?) {
        // Runs on sessionStartQueue. This call may block inside AVAssetWriter.startSession(...)
        // so it MUST NOT run on writerQueue (which also processes capture samples).
        // All state mutations remain on writerQueue.

        // Snapshot the first accepted buffer (latched on writerQueue before this is called).
     

        // Start writer + session on this (non-sample) queue.
        if writer.status == .unknown {
          
            writer.startWriting()
        }

        writer.startSession(atSourceTime: .zero)

        // Now that startSession has returned, commit start state and append the first buffer.
        writerQueue.async { [weak self] in
            guard let self = self else { return }

            // C-97. Resolve ownership BEFORE touching any shared state. A stale
            // continuation that merely returned would leak this writer and leave its file
            // on disk; one that fell through would corrupt a NEWER claim's state.
            guard self.handleSessionStartReturn(token: token, writer: writer,
                                                claimPresentation: claimPresentation) else { return }

            // startSession(atSourceTime:) has returned. Do NOT commit recordingStartTime yet.
            // We commit on the *next* video frame so output begins exactly where UI shows recording.
            self.sessionStartPTS = .zero
            self.writerSessionReady = true

            // Clear any pre-session buffers (we intentionally drop pre-roll).
            self.pendingVideoBuffers.removeAll(keepingCapacity: true)
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

    /// C-97: internal entry so the real arm path can be driven by the wiring tests.
    func startRecordingForTesting() { startRecording() }

    private func startRecording() {
        guard state == .idle || state == .pausedRecording else { return }
        // C-97 (2): after a reset, Record does not rebuild capture; close and reopen does.
        if disruption.blocksNewCapture { recordingError = CaptureDisruptionTracker.reopenMessage; return }
        guard !isRecordStartInProgress && !isArmedToRecord else {
            return
        }

        isRecordStartInProgress = true
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

        // C-97. The claim this start is cancellable by. The url is latched HERE and is
        // immutable for the claim's life; every later file effect acts on that value and
        // never re-reads `recordingURL`, which main may have moved on by then.
        let startToken = UUID()
        currentStartToken = startToken
        let startPresentation = presentationID
        // C-97. `recordingURL` is REUSED when non-nil, so minting a unique name is not on
        // its own enough to give each claim a fresh url. A cancelled start clears it (see
        // completePendingStartCancellation) precisely so the next claim cannot inherit the
        // path whose file was just deleted.
        let claimURL = recordingURL

        // Initialize cadence gate for Solution A (discard early frames until cadence is stable).
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            // C-97. These four were reset on MAIN, while writerQueue owns them and reads
            // them for every sample buffer. Moved here so the start path's writer state
            // is mutated on its owning queue; the block is enqueued before any frame of
            // this take can be processed, so the ordering is unchanged.
            self.assetWriter = nil
            self.videoInput = nil
            self.audioInput = nil
            self.recordingStartTime = nil
            self.lastVideoPTS = nil
            self.lastAppendedVideoPTS = nil
            if let claimURL {
                // A previous claim that left a partial file and has no continuation to
                // clean it up would otherwise leak it into Documents.
                if let abandoned = self.startCoordinator.arm(token: startToken,
                                                             presentation: startPresentation,
                                                             url: claimURL),
                   abandoned != claimURL {
                    self.fileEffects.removeFile(abandoned)
                }
            }
            self.isRecordingArmed = true
            self.cadenceStableCount = 0
            self.cadenceLastPTS = nil
            self.cadenceArmMonotonic = CACurrentMediaTime()
            self.sessionStartPTS = nil
            self.writerSessionReady = false
            self.retimeBasePTS = nil
            self.droppedAudioBeforeSessionCount = 0

            // C-97. Reset the rest of the per-start pipeline HERE, at the claim
            // boundary. A claim retired while `startSession` was blocked leaves
            // `isStartingWriterSession` TRUE, and the cadence gate returns on that flag
            // for every frame -- so the next start could never progress. The retired
            // continuation cannot release it either, because it deliberately touches no
            // shared state. Its own captured writer is NOT touched here; only this
            // recorder's pipeline is.
            self.isStartingWriterSession = false
            self.pendingFirstAcceptedVideoBuffer = nil
            self.pendingSessionStartPTS = nil
            self.pendingVideoBuffers.removeAll(keepingCapacity: true)
            self.pendingVideoDuringSessionStart.removeAll(keepingCapacity: true)
            self.pendingAudioDuringSessionStart.removeAll(keepingCapacity: true)
            // An audio delivery belonging to a previous start is finished with; leaving
            // it attached would feed the new writer from the old take's buffer.
            self.audioDelivery?.cancel()
            self.audioDelivery = nil
        }

        // Remove immediate UI/timer start semantics on tap:
        // recordingWallClockStart = Date()
        // state = .recording
        // startTimer()
        // Keep isShowingLivePreview true as-is
        isShowingLivePreview = true
    }

    private func stopRecording() {
        guard !isFinishingRecording, state == .recording || state == .pausedRecording else { return }
        isFinishingRecording = true
        isReadyToSave = false
        let presentation = presentationID
        stopTimer()
        recordingWallClockStart = nil
        isArmedToRecord = false
        isRecordStartInProgress = false

        guard let finishURL = recordingURL else {
            state = .idle
            isFinishingRecording = false
            finishRecordingWithError()
            disruptionWriterFinished(succeeded: false, url: nil, strongerMessage: nil)
            return
        }

        writerQueue.async { [weak self] in
            guard let self else { return }
            self.isStoppingRecording = true
            guard let writer = self.assetWriter else {
                DispatchQueue.main.async {
                    guard self.presentationID == presentation else { return }
                    self.isFinishingRecording = false
                    self.finishRecordingWithError()
                    self.disruptionWriterFinished(succeeded: false, url: nil, strongerMessage: nil)
                }
                return
            }
            // Preserve the existing video drain/finish behavior. Audio gets its own
            // bounded asynchronous drain, retaining the timestamps chosen at startup.
            if let vInput = self.videoInput {
                self.drainPendingVideo(vInput)
                vInput.markAsFinished()
            }
            let finish: (RecordingAudioDeliveryFailure?) -> Void = { [weak self] failure in
                guard let self, self.assetWriter === writer else { return }
                if writer.status == .writing { self.audioInput?.markAsFinished() }
                let completed: () -> Void = { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, self.presentationID == presentation, self.assetWriter === writer else { return }
                        let succeeded = writer.status == .completed
                        var strongerMessage: String?
                        if succeeded {
                            self.handleRecordingFinishedSuccessfully(url: finishURL)
                            if failure != nil {
                                self.recordingError = "Recording stopped because some audio could not be saved. The available video has been kept; review its soundtrack before saving it."
                                strongerMessage = self.recordingError
                            }
                        } else {
                            self.finishRecordingWithError()
                            self.recordingError = "The recording could not be completed. Please try again."
                            strongerMessage = self.recordingError
                        }
                        self.isFinishingRecording = false
                        self.state = .idle
                        // C-97 (2): only now — after verified finalisation — any disruption
                        // message and deferred capture tear-down.
                        self.disruptionWriterFinished(succeeded: succeeded, url: finishURL, strongerMessage: strongerMessage)
                    }
                }
                if writer.status == .writing {
                    writer.finishWriting(completionHandler: completed)
                    // Stop must also recover if the writer itself never finishes after the drain.
                    self.writerQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self, self.assetWriter === writer else { return }
                        if writer.status == .writing { writer.cancelWriting() }
                        completed()
                    }
                } else { completed() }
            }
            if let delivery = self.audioDelivery { delivery.finish(finish) }
            else { finish(nil) }
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

        // Phase 2 (C-4): an in-flight capture is transient — swept at launch by
        // `sweepAbandonedCaptureFilesInDocuments()`, and promoted through StagingStore into
        // a persisted attachment when kept. It sits in Documents purely as a working
        // location, so it must not ride into a backup. Before Phase 2 this was the one
        // media class whose policy was inverted: permanent media was excluded and this
        // scratch file was not. Applied here rather than at creation because the file only
        // exists from this point.
        BackupPolicy.exclude(url)

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
            try? StagingStore.bootstrap()
        }

        // Tear down writer state
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        recordingStartTime = nil
        lastVideoPTS = nil
        lastAppendedVideoPTS = nil
        pendingVideoBuffers.removeAll(keepingCapacity: true)
        isArmedToRecord = false
        isRecordStartInProgress = false
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioDelivery?.cancel()
            self.audioDelivery = nil
            self.isRecordingArmed = false
            if let t = self.startCoordinator.currentToken { self.startCoordinator.settle(t) }
            self.isStartingWriterSession = false
            self.pendingSessionStartPTS = nil
            self.writerSessionReady = false
            self.pendingFirstAcceptedVideoBuffer = nil
            self.pendingVideoDuringSessionStart.removeAll(keepingCapacity: true)
            self.pendingAudioDuringSessionStart.removeAll(keepingCapacity: true)
        }
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
        isArmedToRecord = false
        isRecordStartInProgress = false
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioDelivery?.cancel()
            self.audioDelivery = nil
            self.isRecordingArmed = false
            if let t = self.startCoordinator.currentToken { self.startCoordinator.settle(t) }
            self.isStartingWriterSession = false
            self.pendingSessionStartPTS = nil
            self.writerSessionReady = false
            self.pendingFirstAcceptedVideoBuffer = nil
            self.pendingVideoDuringSessionStart.removeAll(keepingCapacity: true)
            self.pendingAudioDuringSessionStart.removeAll(keepingCapacity: true)
        }
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
        isArmedToRecord = false
        isRecordStartInProgress = false
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioDelivery?.cancel()
            self.audioDelivery = nil
            self.isRecordingArmed = false
            if let t = self.startCoordinator.currentToken { self.startCoordinator.settle(t) }
            self.isStartingWriterSession = false
            self.pendingSessionStartPTS = nil
            self.writerSessionReady = false
            self.pendingFirstAcceptedVideoBuffer = nil
            self.pendingVideoDuringSessionStart.removeAll(keepingCapacity: true)
            self.pendingAudioDuringSessionStart.removeAll(keepingCapacity: true)
        }
        // Note: Do not reset isRecorderReady here to avoid breaking readiness mid-session.
    }

    // MARK: - Playback

    private func ensurePlaybackSessionActive() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
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
        let asset = AVURLAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            applyPreferredRecordingInput()
        } catch {
            // Ignore silently
        }
    }

    private func preactivateRecordingAudioSessionIfNeeded() {
        guard !hasPreactivatedRecordingAudioSession && !isPreactivatingRecordingAudioSession else { return }

        isPreactivatingRecordingAudioSession = true

        audioSessionPreactivationQueue.async { [weak self] in
            let session = AVAudioSession.sharedInstance()
            var didPreactivate = false

            do {
                try session.setCategory(.playAndRecord,
                                        options: [.defaultToSpeaker, .allowBluetoothA2DP])
                try session.setActive(true)

                let inputs = session.availableInputs ?? []
                if let usb = inputs.first(where: { $0.portType == .usbAudio }) {
                    try? session.setPreferredInput(usb)
                } else if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
                    try? session.setPreferredInput(builtIn)
                }

                didPreactivate = true
            } catch {
                didPreactivate = false
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isPreactivatingRecordingAudioSession = false
                if didPreactivate {
                    self.hasPreactivatedRecordingAudioSession = true
                }
                // C-97 R1. Observation only. Already on main, so it is taken
                // here rather than through `observeRecordingRoute`, which would
                // hop again and read a later moment. Runs whatever
                // `didPreactivate` was: a failed preactivation is exactly when
                // the route is worth knowing.
                RecordingRouteObservation.observe(SystemRecordingInputSession(),
                                                  stage: .preactivationDeferred)
            }
        }
    }

    private func applyPreferredRecordingInput() {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.availableInputs ?? []

        // The branches are ALTERNATIVES, not two verification points. The old
        // `return` after the USB branch is what a single exit removes: with an
        // observation at the end, that return would have skipped it on the USB
        // path -- the one most worth observing. Selection behaviour is
        // unchanged.
        if let usb = inputs.first(where: { $0.portType == .usbAudio }) {
            try? session.setPreferredInput(usb)
        } else if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }

        // C-97 R1. Observation only, deferred like the other path.
        observeRecordingRoute(stage: .preferenceAppliedDeferred)
    }

    /// C-97 R1. Observe the route on main. Read-only, never a decision, and
    /// non-blocking: a blocking hop would add a wait to capture setup to buy an
    /// atomicity this diagnostic does not claim.
    private func observeRecordingRoute(stage: RecordingRouteObservation.Stage) {
        DispatchQueue.main.async {
            RecordingRouteObservation.observe(SystemRecordingInputSession(), stage: stage)
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
            let asset = AVURLAsset(url: url)
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
        // C-97 (2). Audio-session reset: NOT filtered by capture-session object; bound to
        // this presentation's generation instead.
        if let old = audioResetObserver { NotificationCenter.default.removeObserver(old) }
        let generation = disruptionGeneration
        audioResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.handleDisruptionOnMain(.audioServicesReset, source: nil, generation: generation) }
        }
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
        if let old = audioResetObserver { NotificationCenter.default.removeObserver(old) }
        audioResetObserver = nil
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

        // Re-assert preferred recording input on meaningful route changes.
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            DispatchQueue.main.async { [weak self] in
                self?.applyPreferredRecordingInput()
            }
        default:
            break
        }

        if reason == .oldDeviceUnavailable {
            if state == .recording {
                stopRecording()
            } else if state == .playing {
                pausePlayback()
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

    // MARK: - C-97 (2) capture disruption

    /// Capture events are observed for ONE session object and bound to the presentation
    /// generation current on `sessionQueue` when registered. Called on `sessionQueue`.
    private func registerCaptureObservers(for session: AVCaptureSession) {
        let generation = sessionGeneration
        let center = NotificationCenter.default
        let pairs: [(Notification.Name, CaptureDisruptionTracker.Event)] = [
            (AVCaptureSession.runtimeErrorNotification, .captureRuntimeError),
            (AVCaptureSession.wasInterruptedNotification, .captureInterruptionBegan),
            (AVCaptureSession.interruptionEndedNotification, .captureInterruptionEnded),
        ]
        captureObserverTokens = pairs.map { name, event in
            center.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                let source = note.object as AnyObject?
                DispatchQueue.main.async {
                    self?.handleDisruptionOnMain(event, source: source, generation: generation)
                }
            }
        }
    }

    private func unregisterCaptureObservers(for session: AVCaptureSession) {
        captureObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
        captureObserverTokens = []
    }

    /// Main thread. Every delivery must belong to the current generation; a capture event
    /// must also come from the current session.
    private func handleDisruptionOnMain(_ event: CaptureDisruptionTracker.Event, source: AnyObject?, generation: Int?) {
        if let generation, generation != disruptionGeneration { return }
        let isCurrent = source.map { $0 === captureSession } ?? true
        perform(disruption.handle(event, disruptionSnapshot(isCurrentSession: isCurrent)), for: event)
    }

    private func disruptionSnapshot(isCurrentSession: Bool) -> CaptureDisruptionTracker.Snapshot {
        let take: CaptureDisruptionTracker.TakeState
        if isFinishingRecording {
            take = .finishing
        } else if state == .recording || state == .pausedRecording {
            take = .recording
        } else if isArmedToRecord || isRecordStartInProgress {
            take = .startPending
        } else if recordingURL != nil && !isShowingLivePreview {
            take = .underReview
        } else {
            take = .none
        }
        return .init(isCurrentSession: isCurrentSession, take: take,
                     isAppActive: UIApplication.shared.applicationState == .active,
                     isShowingLivePreview: isShowingLivePreview)
    }

    /// Main thread. Every capture change is re-checked on `sessionQueue` against the
    /// session identity it was decided for.
    private func perform(_ actions: [CaptureDisruptionTracker.Action],
                         for event: CaptureDisruptionTracker.Event? = nil) {
        for action in actions {
            switch action {
            case .requestPendingStartCancel:
                requestPendingStartCancellation(for: event)
            case .stopActiveTake:
                stopRecording()                       // the existing finalise path
            case .inhibitPlaybackResume:
                shouldResumeAfterResignActive = false
                shouldResumeAfterInterruption = false
                if state == .playing { pausePlayback() }   // the take and its file are untouched
            case .tearDownCapture:
                let expected = captureSession
                let generation = disruptionGeneration
                sessionQueue.async { [weak self] in
                    guard let self, let expected, self.captureSession === expected else { return }
                    // Eligibility is re-checked NOW, on main, not only when it was decided.
                    // (`main.sync` from a background queue is the existing pattern here, e.g.
                    // `currentOrientation()`; main never waits on `sessionQueue`.)
                    let mayRun = DispatchQueue.main.sync {
                        CaptureDisruptionTracker.mayExecute(
                            action, sameGeneration: generation == self.disruptionGeneration,
                            self.disruptionSnapshot(isCurrentSession: self.captureSession === expected),
                            awaitingReopen: self.disruption.awaitingReopen)
                    }
                    guard mayRun else { return }
                    self.stopCaptureSession()
                }
            case .showMessage(let message):
                recordingError = message
            }
        }
    }

    // MARK: - C-97: cancelling a start that is in flight

    /// writerQueue. THE decision a sample buffer makes before any writer exists.
    ///
    /// A buffer enqueued just before the Record tap runs here BEFORE the arm block,
    /// because main sets its arm flags and only then enqueues the arm. Such a frame must
    /// decide NOTHING: no writer, and above all no mutation of main's arm state, which
    /// would kill a start that is about to be armed.
    func preWriterDecisionForFrame() -> PendingStartCoordinator.FrameDisposition {
        startCoordinator.frameDisposition
    }

    /// writerQueue. Resolves who owns a returning `startSession` before any shared state
    /// is touched. Returns true when the caller should continue with the ordinary
    /// session-ready path.
    @discardableResult
    func handleSessionStartReturn(token: UUID?, writer: AVAssetWriter?,
                                  claimPresentation: UUID?) -> Bool {
        // ABSENCE IS A REFUSAL, as at S5: a continuation that cannot name its claim must
        // not mutate shared pipeline state, which may now belong to a newer start.
        guard let token else {
            if let writer { fileEffects.cancelWriting(writer) }
            return false
        }
        switch startCoordinator.sessionStartReturned(token) {
        case .proceed:
            startCoordinator.advance(token, to: .sessionReady)
            return true
        case .finaliseCancelled(let url):
            if let writer { fileEffects.cancelWriting(writer) }
            fileEffects.removeFile(url)
            isStartingWriterSession = false
            writerSessionReady = false
            pendingFirstAcceptedVideoBuffer = nil
            isRecordingArmed = false
            isArmedToRecord = false
            if let claimPresentation {
                DispatchQueue.main.async { [weak self] in
                    self?.completePendingStartCancellation(token: token,
                                                           presentation: claimPresentation,
                                                           generation: nil)
                }
            }
            return false
        case .cleanUpRetired(let url):
            // A claim from an earlier presentation, or superseded. Clean up ITS writer
            // and ITS file, exactly once, and touch nothing shared: a newer claim may be
            // live on this very queue.
            if let writer { fileEffects.cancelWriting(writer) }
            fileEffects.removeFile(url)
            return false
        case .alreadySettled:
            if let writer { fileEffects.cancelWriting(writer) }
            return false
        }
    }

    /// Main thread. Publishes a cancellation to `writerQueue`, which owns the writer and
    /// is the only place that can say whether the cancellation won or the start already
    /// did. Nothing is decided here.
    func requestPendingStartCancellation(for event: CaptureDisruptionTracker.Event?) {
        let generation = disruptionGeneration
        let presentation = presentationID
        // The claim THIS event is about, named on main at request time. Taking whichever
        // token happens to be live when the queue gets round to it would cancel a start
        // the member began after the event.
        guard let token = currentStartToken else { return }
        writerQueue.async { [weak self] in
            guard let self else { return }
            switch self.startCoordinator.requestCancel(token: token) {
            case .noClaim:
                return

            case .cancelledBeforeWriter:
                // Nothing was written; there is no file to remove.
                self.isRecordingArmed = false
                self.isArmedToRecord = false
                DispatchQueue.main.async { [weak self] in
                    self?.completePendingStartCancellation(token: token, presentation: presentation,
                                                           generation: generation)
                }

            case .cancelledWithWriter(let url):
                if let writer = self.assetWriter { self.fileEffects.cancelWriting(writer) }
                self.fileEffects.removeFile(url)
                self.assetWriter = nil
                self.videoInput = nil
                self.audioInput = nil
                self.isRecordingArmed = false
                self.isArmedToRecord = false
                self.writerSessionReady = false
                DispatchQueue.main.async { [weak self] in
                    self?.completePendingStartCancellation(token: token, presentation: presentation,
                                                           generation: generation)
                }

            case .deferredUntilSessionReturns:
                // startSession is blocked off-queue. Its continuation finalises.
                return

            case .startupAlreadyWon:
                // The start committed before this reached the queue, so there IS a take.
                // This main hop is enqueued AFTER the `state = .recording` transition
                // that S5 dispatched, so `stopRecording()` sees `.recording`.
                DispatchQueue.main.async { [weak self] in
                    self?.adoptDisruptedStartedTake(for: event, token: token,
                                                    presentation: presentation, generation: generation)
                }
            }
        }
    }

    /// Main thread. The cancellation WON: the start never became a take, so capture is
    /// torn down and the reopen message given -- in that order, and only now.
    func completePendingStartCancellation(token: UUID,
                                                  presentation: UUID,
                                                  generation: Int? = nil) {
        // Main-owned identity, validated HERE and not only where the work was decided: a
        // reopened recorder must not be mutated by a completion from the old one.
        guard presentation == presentationID, token == currentStartToken else { return }
        if let generation, generation != disruptionGeneration { return }
        isArmedToRecord = false
        isRecordStartInProgress = false
        currentStartToken = nil
        // The start never became a take, so its url must not be inherited by the next
        // claim -- its file has just been deleted.
        recordingURL = nil
        isReadyToSave = false
        perform(disruption.pendingStartCancelled())
    }

    /// Main thread. STARTUP WON. The tracker never saw a `.recording` take for this
    /// event, so it holds neither `takeDisrupted` nor `tearDownAfterFinish` and
    /// `writerFinished` would produce neither the tear-down nor the kept message. Adopt
    /// the state it would have held, then stop the take through the ordinary path.
    func adoptDisruptedStartedTake(for event: CaptureDisruptionTracker.Event?,
                                           token: UUID,
                                           presentation: UUID,
                                           generation: Int?) {
        guard presentation == presentationID, token == currentStartToken else { return }
        if let generation, generation != disruptionGeneration { return }
        guard let event else { return }
        perform(disruption.adoptDisruptedStartedTake(from: event), for: event)
    }

    /// The existing stop path has finished with the writer (or found none).
    func disruptionWriterFinished(succeeded: Bool, url: URL?, strongerMessage: String?) {
        let kept = url.map { FileManager.default.fileExists(atPath: $0.path) && recordingURL == $0 } ?? false
        perform(disruption.writerFinished(succeeded: succeeded, keptFileExists: kept, existingMessage: strongerMessage))
    }

    // MARK: - File URL Helpers

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func newRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        // C-97: a full UUID suffix, because the claim that a cancellation cannot reach a
        // reviewed or newer take DEPENDS on urls being distinct. Second resolution alone
        // is not distinct: two starts inside one second produced the SAME path, so a
        // cancelled claim could delete a newer take's file. Both consumers of this name
        // match on the `motivo_vid_` PREFIX only (BackupReconciliation:57,
        // VideoRecorderView:494), so the suffix is free.
        let filename = "motivo_vid_\(formatter.string(from: Date()))_\(UUID().uuidString).mov"
        // Backup policy is applied in `handleRecordingFinishedSuccessfully(url:)`, not
        // here — this URL names a file that does not exist yet, and setting a resource
        // value on a non-existent path fails.
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
                self.maybeScheduleInteractiveReady()
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
            // C-97. Gate on the writerQueue-owned CLAIM, and on nothing else, through
            // the same method the wiring tests drive.
            //
            // A sample buffer enqueued just before the Record tap can run here BEFORE the
            // arm block, because main sets `isArmedToRecord = true` and only then
            // enqueues the arm. Such a frame used to fall into the no-url branch and
            // clear main's arm flags, killing a start that was about to be armed. It now
            // decides NOTHING: no writer, no main mutation, no disarm.
            guard case .proceed(let token, let url) = preWriterDecisionForFrame() else {
                return
            }
            let claimPresentationForFailure = startCoordinator.claim?.presentation
            do {
                // Advanced BEFORE the throwing call: AVAssetWriter can create the output
                // file and then fail, so from this point a partial file may exist and the
                // claim must own it.
                startCoordinator.advance(token, to: .writerCreated)
                try setupWriter(for: url)
            } catch {
                dbg("setupWriter failed: \(error)")
                // C-97. The start failed on its own. Retire the claim and remove whatever
                // partial file it may have created -- by the claim's url.
                if let orphan = startCoordinator.failed(token) { fileEffects.removeFile(orphan) }
                isArmedToRecord = false
                let failedPresentation = claimPresentationForFailure
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // A stale failure must not clear a NEWER start's in-progress flag.
                    guard self.currentStartToken == token,
                          self.presentationID == failedPresentation else { return }
                    self.isRecordStartInProgress = false
                    self.currentStartToken = nil
                }
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

                // C-97. The claim is `committed` BEFORE the main transition is
                // enqueued, so a cancellation arriving after this point resolves as
                // `startupAlreadyWon` and its own main hop is enqueued AFTER this one --
                // which is what makes `stopRecording()` find `state == .recording`
                // rather than no-op against `.idle`.
                let committedToken = startCoordinator.currentToken
                let committedPresentation = startCoordinator.claim?.presentation
                if let committedToken {
                    startCoordinator.advance(committedToken, to: .committed)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // C-97. A transition from a claim that is no longer main's current
                    // start must not move a reopened recorder into `.recording`.
                    // ABSENCE IS A REFUSAL: an unidentifiable transition on a path that
                    // claims identity is exactly the case that must not fall through.
                    guard let committedToken, let committedPresentation,
                          committedToken == self.currentStartToken,
                          committedPresentation == self.presentationID else { return }
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

        guard !isStoppingRecording else { return }
        if audioDelivery == nil {
            var loggedFirstAppend = false
            audioDelivery = BufferedRecordingAudio(queue: writerQueue,
                isWriting: { writer.status == .writing },
                isReady: { aInput.isReadyForMoreMediaData },
                append: { buffer in
                    let appended = aInput.append(buffer)
                    #if DEBUG
                    if appended, !loggedFirstAppend {
                        loggedFirstAppend = true
                        let session = AVAudioSession.sharedInstance()
                        print("[RecordingAudio] firstVideoAudioPTS=\(CMSampleBufferGetPresentationTimeStamp(buffer).seconds) input=\(session.currentRoute.inputs.map { $0.portType.rawValue }) rate=\(session.sampleRate)")
                    }
                    #endif
                    return appended
                },
                timestamp: { CMSampleBufferGetPresentationTimeStamp($0).seconds },
                onFailure: { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.assetWriter === writer, !self.isFinishingRecording else { return }
                        self.stopRecording()
                    }
                })
        }
        audioDelivery?.receive(outSB)
    }

}
private struct VideoRecorderPreparingOverlay: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // Fully occlude unstable first-run preview with a calm surface.
            Color.black.opacity(0.001) // ensures taps don't hit underlying controls

            VStack(spacing: Theme.Spacing.s) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Preparing camera…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Colors.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let gravity: AVLayerVideoGravity

    init(player: AVPlayer?, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.player = player
        self.gravity = gravity
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if let l = uiView.layer as? AVPlayerLayer {
            l.player = player
            uiView.videoGravity = gravity
            uiView.setNeedsLayout()
        }
    }
}

private final class PlayerContainerView: UIView {
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let l = self.layer as? AVPlayerLayer {
            l.frame = bounds
            l.videoGravity = videoGravity
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
