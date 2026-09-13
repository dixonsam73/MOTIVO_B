// Metronome-only transport. Keep BPM tied to the source-node render rate (20260612 timing fix).
import Foundation
import AVFoundation
import Combine

@MainActor
final class MetronomeEngine: ObservableObject {
    private static weak var activeInstance: MetronomeEngine?
    @Published private(set) var availability: MetronomeAvailability = .stopped
    var isRunning: Bool { availability == .running && engine?.isRunning == true }

    private var engine: AVAudioEngine?
    private var kernel: MetronomeRenderKernel?
    private var lifecycle = MetronomeLifecycle()
    private var settings = MetronomeSettings()
    private var listeners: [UUID: (Bool) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private var uiTimer: Timer?
    private var lastBeat: UInt64 = 0
    private var lastFrames: UInt64 = 0
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var routeIdentity = ""

    @discardableResult
    func start(settings: MetronomeSettings) -> Bool {
        stop()
        if let other = Self.activeInstance, other !== self { other.stop() }
        self.settings = settings
        let token = lifecycle.begin()
        publish()
        do {
            try configureSession()
        } catch {
            fail(.setup, token: token)
            return false
        }
        do {
            let audio = AVAudioEngine()
            let rate = audio.outputNode.inputFormat(forBus: 0).sampleRate
            guard rate.isFinite, rate > 0,
                  let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
                fail(.setup, token: token); return false
            }
            let normal = try load("metronome_click_normal")
            let accent = try load("metronome_click_accent")
            guard normal.rate == accent.rate else { throw MetronomeResourceError.invalid }
            let bank = MetronomeSoundBank(normal: normal.samples, accent: accent.samples,
                                         sourceRate: normal.rate, renderRate: rate)
            let mailbox = MetronomeMailbox(settings: settings)
            let renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
            let source = AVAudioSourceNode(format: format) { _, _, count, buffers in
                // This closure only accesses render-owned state, immutable samples and scalar atomics.
                let output = UnsafeMutableAudioBufferListPointer(buffers)
                renderer.beginBuffer()
                for frame in 0..<Int(count) {
                    let sample = renderer.nextSample()
                    for buffer in output {
                        guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        for channel in 0..<Int(buffer.mNumberChannels) {
                            pointer[frame * Int(buffer.mNumberChannels) + channel] = sample
                        }
                    }
                }
                renderer.endBuffer(frameCount: Int(count))
                return noErr
            }
            audio.attach(source)
            audio.connect(source, to: audio.mainMixerNode, format: format)
            engine = audio
            kernel = renderer
            audio.prepare()
            do { try audio.start() }
            catch { fail(.start, token: token); return false }
            guard lifecycle.started(token, audioRunning: audio.isRunning) else {
                tearDownAudio(); publish(); return false
            }
            Self.activeInstance = self
            routeIdentity = currentRouteIdentity()
            lastBeat = 0
            lastFrames = 0
            lastProgress = ProcessInfo.processInfo.systemUptime
            installObservers(audio: audio, token: token)
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll(token: token) }
            }
            RunLoop.main.add(timer, forMode: .common)
            uiTimer = timer
            publish()
            return true
        } catch {
            fail(.resources, token: token)
            return false
        }
    }

    func update(settings: MetronomeSettings) {
        self.settings = settings
        kernel?.mailbox.command.store(settings.command(running: isRunning), ordering: .releasing)
    }

    func stop() {
        lifecycle.stop()
        tearDownAudio()
        publish()
    }

    @discardableResult func addBeatListener(_ listener: @escaping (Bool) -> Void) -> UUID {
        let value = UUID(); listeners[value] = listener; return value
    }
    func removeBeatListener(_ token: UUID) { listeners.removeValue(forKey: token) }

    private func publish() { availability = lifecycle.availability }
    private func fail(_ reason: MetronomeFailure, token: UUID) {
        guard lifecycle.fail(reason, token: token) else { return }
        tearDownAudio()
        publish()
    }
    private func tearDownAudio() {
        kernel?.mailbox.command.store(settings.command(running: false), ordering: .releasing)
        uiTimer?.invalidate(); uiTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        engine?.stop()
        engine = nil
        kernel = nil
        lastBeat = 0
        if Self.activeInstance === self { Self.activeInstance = nil }
        // Do not deactivate the shared session: Drone/recording/other app audio may still own it.
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Preserve the established recording-capable session and routing when another tool owns it.
        if session.category != .playAndRecord {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(44_100)
        }
        try session.setActive(true)
    }

    private func load(_ name: String) throws -> (samples: [Float], rate: Double) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            throw MetronomeResourceError.invalid
        }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.length <= 1_000_000,
              file.processingFormat.sampleRate > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw MetronomeResourceError.invalid
        }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { throw MetronomeResourceError.invalid }
        let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        guard samples.allSatisfy({ $0.isFinite }) else { throw MetronomeResourceError.invalid }
        return (samples, buffer.format.sampleRate)
    }

    private func currentRouteIdentity() -> String {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs.map { $0.uid }.joined(separator: "|") + ":\(session.sampleRate)"
    }

    private func installObservers(audio: AVAudioEngine, token: UUID) {
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated { self?.fail(.interrupted, token: token) }
        })
        observers.append(centre.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lifecycle.token == token else { return }
                if self.currentRouteIdentity() != self.routeIdentity || self.engine?.isRunning != true {
                    self.fail(.routeChanged, token: token)
                }
            }
        })
        observers.append(centre.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lifecycle.token == token else { return }
                if self.engine?.isRunning != true || self.currentRouteIdentity() != self.routeIdentity {
                    self.fail(.routeChanged, token: token)
                }
            }
        })
        observers.append(centre.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fail(.mediaReset, token: token) }
        })
    }

    private func poll(token: UUID) {
        guard lifecycle.token == token, lifecycle.availability == .running, let kernel else { return }
        guard engine?.isRunning == true else { fail(.stoppedAudio, token: token); return }
        let frames = kernel.mailbox.frames.load(ordering: .acquiring)
        let now = ProcessInfo.processInfo.systemUptime
        if frames != lastFrames { lastFrames = frames; lastProgress = now }
        else if now - lastProgress > 1 { fail(.stoppedAudio, token: token); return }
        let beat = kernel.mailbox.beat.load(ordering: .acquiring)
        guard beat != lastBeat, beat != 0 else { return }
        lastBeat = beat
        // Coalesce delayed visual beats. The audio never waits for or dispatches UI work.
        for listener in Array(listeners.values) { listener(beat & 1 == 1) }
    }
}

private enum MetronomeResourceError: Error { case invalid }
