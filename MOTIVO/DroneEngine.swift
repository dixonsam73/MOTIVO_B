// DroneEngine.swift — original drone voice with format-aware rendering and explicit lifecycle.
import Foundation
import AVFoundation
import Combine

private enum DroneOutputFailure: Error { case invalidFormat }

@MainActor
protocol DroneAudioOutput: AnyObject {
    var sourceFormat: AVAudioFormat { get }
    var isRunning: Bool { get }
    var notificationObject: AnyObject { get }
    func start(renderer: DroneRenderKernel) throws
    func stop()
}

@MainActor
final class SystemDroneAudioOutput: DroneAudioOutput {
    private let engine = AVAudioEngine()
    let sourceFormat: AVAudioFormat
    var isRunning: Bool { engine.isRunning }
    var notificationObject: AnyObject { engine }

    init() throws {
        let output = engine.outputNode.inputFormat(forBus: 0)
        guard output.sampleRate.isFinite, output.sampleRate > 0, output.channelCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: output.sampleRate, channels: output.channelCount) else {
            throw DroneOutputFailure.invalidFormat
        }
        sourceFormat = format
    }

    func start(renderer: DroneRenderKernel) throws {
        let node = AVAudioSourceNode(format: sourceFormat) { _, _, count, buffers in
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
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: sourceFormat)
        engine.prepare()
        try engine.start()
    }

    func stop() { engine.stop() }
}

@MainActor
final class DroneEngine: ObservableObject {
    private static weak var activeInstance: DroneEngine?
    @Published private(set) var isRunning = false
    private var output: (any DroneAudioOutput)?
    private var renderer: DroneRenderKernel?
    private var runID: UUID?
    private var pollTimer: Timer?
    private let observers: AudioNotificationObservers
    private let makeOutput: @MainActor () throws -> any DroneAudioOutput
    private let activateSession: @MainActor () throws -> Void
    private let routeIdentity: @MainActor () -> String
    private let clock: () -> TimeInterval
    private var initialRoute = ""
    private var lastFrames: UInt64 = 0
    private var lastProgress: TimeInterval = 0

    init(makeOutput: @escaping @MainActor () throws -> any DroneAudioOutput = { try SystemDroneAudioOutput() },
         activateSession: @escaping @MainActor () throws -> Void = { try DroneEngine.configureSession() },
         routeIdentity: @escaping @MainActor () -> String = { DroneEngine.currentRouteIdentity() },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         notificationCenter: NotificationCenter = .default) {
        self.makeOutput = makeOutput
        self.activateSession = activateSession
        self.routeIdentity = routeIdentity
        self.clock = clock
        observers = AudioNotificationObservers(center: notificationCenter)
    }

    @discardableResult
    func start(frequency: Double, volume: Double) -> Bool {
        hardStop()
        if let other = Self.activeInstance, other !== self { other.hardStop() }
        let token = UUID()
        runID = token
        do {
            try activateSession()
            let audio = try makeOutput()
            let rate = audio.sourceFormat.sampleRate
            guard rate.isFinite, rate > 0 else { hardStop(); return false }
            let kernel = DroneRenderKernel(sampleRate: rate, frequency: Self.validFrequency(frequency),
                                           volume: Self.validVolume(volume))
            output = audio
            renderer = kernel
            try audio.start(renderer: kernel)
            guard audio.isRunning else { hardStop(); return false }
            isRunning = true
            Self.activeInstance = self
            initialRoute = routeIdentity()
            lastFrames = 0
            lastProgress = clock()
            installObservers(audio: audio, token: token)
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll(token: token) }
            }
            pollTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            return true
        } catch {
            hardStop()
            return false
        }
    }

    // Keep the legacy synchronous main-thread entry point used by permission callbacks.
    // Render/control state itself remains isolated; background callers are marshalled to main.
    nonisolated func stop() {
        if Thread.isMainThread { MainActor.assumeIsolated { stopOnMain() } }
        else { DispatchQueue.main.async { [weak self] in self?.stopOnMain() } }
    }

    private func stopOnMain() {
        if let other = Self.activeInstance, other !== self { other.stop(); return }
        guard let token = runID else { return }
        isRunning = false
        renderer?.mailbox.volume.store(0.0.bitPattern, ordering: .releasing)
        pollTimer?.invalidate(); pollTimer = nil
        // Keep the original 0.3-second fade. An older fade may never stop a newer start.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard self?.runID == token else { return }
            self?.hardStop()
        }
    }

    func update(frequency: Double) {
        renderer?.mailbox.frequency.store(Self.validFrequency(frequency).bitPattern, ordering: .releasing)
    }

    func updateVolume(_ volume: Double) {
        guard isRunning else { return }
        renderer?.mailbox.volume.store(Self.validVolume(volume).bitPattern, ordering: .releasing)
    }

    // Map "A4", "Bb3" etc. → Hz using an arbitrary A4 reference
    static func frequency(for note: String, baseA4: Double = 440) -> Double {
        guard note.count >= 2 else { return baseA4 }

        let chars = Array(note)
        var namePart = ""
        var octavePart = ""

        // Split into pitch name + octave (e.g. "Bb" + "4")
        for c in chars {
            if c.isNumber {
                octavePart.append(c)
            } else if octavePart.isEmpty {
                namePart.append(c)
            }
        }

        let noteName = namePart
        let octave = Int(octavePart) ?? 4

        // Semitone offsets within an octave relative to C
        let semitoneMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1,
            "D": 2, "D#": 3, "Eb": 3,
            "E": 4,
            "F": 5, "F#": 6, "Gb": 6,
            "G": 7, "G#": 8, "Ab": 8,
            "A": 9, "A#": 10, "Bb": 10,
            "B": 11
        ]

        guard let semitone = semitoneMap[noteName] else { return baseA4 }

        // MIDI note number: C-1 = 0 → A4 = 69
        let midi = (octave + 1) * 12 + semitone

        // Standard equal temperament using arbitrary A4 reference
        let freq = baseA4 * pow(2.0, Double(midi - 69) / 12.0)
        return freq
    }

    // Convenience: compute using default A=440
    static func frequency(for note: String) -> Int {
        Int(frequency(for: note, baseA4: 440).rounded())
    }

    private static func validFrequency(_ value: Double) -> Double {
        value.isFinite ? max(20, min(20_000, value)) : 440
    }
    private static func validVolume(_ value: Double) -> Double {
        value.isFinite ? max(0, min(1, value)) : 0
    }

    private static func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Preserve a recording-capable session owned by the recorder.
        if session.category != .playAndRecord {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true)
    }

    private static func currentRouteIdentity() -> String {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs.map { $0.uid }.joined(separator: "|") + ":\(session.sampleRate)"
    }

    private func hardStop() {
        runID = nil
        isRunning = false
        pollTimer?.invalidate(); pollTimer = nil
        observers.removeAll()
        output?.stop()
        output = nil
        renderer = nil
        if Self.activeInstance === self { Self.activeInstance = nil }
        // Leave the shared session active for the recorder/metronome/other playback.
    }

    private func invalidate(_ token: UUID) {
        guard runID == token else { return }
        hardStop()
    }

    private func installObservers(audio: any DroneAudioOutput, token: UUID) {
        observers.observe(AVAudioSession.interruptionNotification) { [weak self] note in
            guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
            self?.invalidate(token)
        }
        observers.observe(AVAudioSession.routeChangeNotification) { [weak self] _ in
            guard let self, self.runID == token else { return }
            if self.routeIdentity() != self.initialRoute || self.output?.isRunning != true {
                self.invalidate(token)
            }
        }
        observers.observe(.AVAudioEngineConfigurationChange, object: audio.notificationObject) { [weak self] _ in
            // Recreate the format/engine on the next explicit start. No automatic restart.
            self?.invalidate(token)
        }
        observers.observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            self?.invalidate(token)
        }
    }

    private func poll(token: UUID) {
        guard runID == token, isRunning, let renderer else { return }
        guard output?.isRunning == true else { invalidate(token); return }
        let frames = renderer.mailbox.frames.load(ordering: .acquiring)
        if frames != lastFrames { lastFrames = frames; lastProgress = clock() }
        else if clock() - lastProgress > 1 { invalidate(token) }
    }
}
