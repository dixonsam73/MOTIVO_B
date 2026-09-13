import Foundation
import Combine
import AVFoundation
import AudioKit
import AudioKitEX

@MainActor
final class TunerService: ObservableObject {
    @Published private(set) var state: TunerDisplayState = .listening
    @Published private(set) var lifecycle = TunerLifecycle()
    var availability: TunerAvailability { lifecycle.availability }

    private var engine: AudioEngine?
    private var pitchTap: TunerInputTap?
    private var mutedInput: Fader?
    private var analysisMixer: Mixer?
    private let mapper = TunerMapper()
    private var ownsAudioSession = false
    private var observers: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var lastAudioTimestamp: TimeInterval?
    private var minimumResultTime: TimeInterval = 0
    private var routeFingerprint = ""

    init() { installObservers() }

    deinit {
        watchdog?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func start(referenceA4: Int = 440) {
        switch availability {
        case .starting, .requestingPermission, .listening: return
        default: break
        }
        releaseAudio()
        mapper.reset()
        mapper.setReferenceA4(Double(referenceA4))
        state = .listening
        minimumResultTime = ProcessInfo.processInfo.systemUptime
        let permission = AVAudioApplication.shared.recordPermission
        let token = lifecycle.begin(needsPermission: permission == .undetermined)
        switch permission {
        case .granted:
            startEngine(token: token)
        case .denied:
            _ = lifecycle.resolvePermission(granted: false, token: token)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.lifecycle.resolvePermission(granted: granted, token: token) else { return }
                    self.startEngine(token: token)
                }
            }
        @unknown default:
            _ = lifecycle.resolvePermission(granted: false, token: token)
        }
    }

    func setReferenceA4(_ reference: Int) {
        mapper.setReferenceA4(Double(reference))
        state = .listening
        minimumResultTime = ProcessInfo.processInfo.systemUptime
    }

    func stop() {
        lifecycle.stop() // invalidate callbacks before touching the audio graph
        releaseAudio()
        mapper.reset()
        state = .listening
    }

    private func startEngine(token: UUID) {
        guard lifecycle.token == token, availability == .starting else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            ownsAudioSession = true // partial setup must also be restored on failure
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredInput(nil)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            guard session.isInputAvailable else { fail(.inputUnavailable, token: token); return }

            let engine = AudioEngine()
            self.engine = engine
            let hardware = engine.avEngine.inputNode.outputFormat(forBus: 0)
            guard hardware.sampleRate > 0, hardware.channelCount > 0,
                  let input = engine.input else { fail(.inputUnavailable, token: token); return }
            let analysisMixer = Mixer(input)
            let mutedInput = Fader(analysisMixer, gain: 0)
            self.analysisMixer = analysisMixer
            self.mutedInput = mutedInput
            engine.output = mutedInput
            let format = input.avAudioNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { fail(.inputUnavailable, token: token); return }

            let tap = TunerInputTap(node: input.avAudioNode) { [weak self] update in
                self?.receive(update, token: token)
            }
            pitchTap = tap
            tap.start()
            try engine.start()
            guard engine.avEngine.isRunning else { fail(.engineStart, token: token); return }
            guard lifecycle.started(token: token) else { releaseAudio(); return }
            routeFingerprint = currentRouteFingerprint()
            lastAudioTimestamp = ProcessInfo.processInfo.systemUptime
            startWatchdog(token: token)
        } catch {
            #if DEBUG
            print("[Tuner] Audio startup failed: \(error)")
            #endif
            fail(.engineStart, token: token)
        }
    }

    private func receive(_ update: TunerInputUpdate, token: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        guard lifecycle.acceptsOutput(token: token), update.timestamp >= minimumResultTime,
              now - update.timestamp <= 0.4 else { return }
        if update.resetHistory { mapper.reset() }
        lastAudioTimestamp = update.timestamp
        state = mapper.process(frequency: update.estimate?.frequency ?? 0,
                               amplitude: update.estimate?.amplitude ?? 0,
                               timestamp: update.timestamp)
    }

    private func startWatchdog(token: UUID) {
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lifecycle.acceptsOutput(token: token) else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if now - (self.lastAudioTimestamp ?? 0) >= 0.2 {
                    self.state = self.mapper.noSignal(at: now)
                }
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func fail(_ reason: TunerFailure, token: UUID) {
        guard lifecycle.token == token else { return }
        lifecycle.fail(reason, token: token)
        releaseAudio()
        mapper.reset()
        state = .listening
    }

    private func releaseAudio() {
        watchdog?.cancel(); watchdog = nil
        pitchTap?.stop(); pitchTap = nil
        engine?.stop(); engine?.output = nil; engine = nil
        mutedInput = nil; analysisMixer = nil
        lastAudioTimestamp = nil
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        let session = AVAudioSession.sharedInstance()
        // Preserve the tuner's existing playback-restoration policy and category/options.
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("[Tuner] Playback restoration failed: \(error)")
            #endif
        }
    }

    private func currentRouteFingerprint() -> String {
        let session = AVAudioSession.sharedInstance()
        return "\(session.sampleRate)|" + session.currentRoute.inputs.map { "\($0.uid):\($0.portType.rawValue)" }.joined(separator: "|")
    }

    private func installObservers() {
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            guard began else { return }
            MainActor.assumeIsolated {
                guard let self, let token = self.lifecycle.token, self.lifecycle.acceptsOutput(token: token) else { return }
                self.fail(.interrupted, token: token)
            }
        })
        observers.append(centre.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let token = self.lifecycle.token, self.lifecycle.acceptsOutput(token: token),
                      self.currentRouteFingerprint() != self.routeFingerprint else { return }
                self.fail(.routeChanged, token: token)
            }
        })
        observers.append(centre.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let token = self.lifecycle.token, self.lifecycle.acceptsOutput(token: token) else { return }
                self.fail(.mediaReset, token: token)
            }
        })
    }
}
