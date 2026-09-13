import AVFoundation
import CSoundpipeAudioKit
import Foundation

struct TunerInputUpdate: Sendable {
    let estimate: TunerPitchEstimate?
    let timestamp: TimeInterval
    let resetHistory: Bool
}

/// A single tap owns both PTrack and confidence analysis. Audio and UI each have one pending slot.
/// Lock-protected delivery state is separate from DSP state owned only by `worker`.
final class TunerInputTap: @unchecked Sendable {
    private struct Packet {
        let samples: [Float]
        let sampleRate: Double
        let timestamp: TimeInterval
        let discontinuous: Bool
    }
    private let node: AVAudioNode
    private let handler: @MainActor @Sendable (TunerInputUpdate) -> Void
    private let worker = DispatchQueue(label: "etudes.tuner.analysis", qos: .userInitiated)
    private let lock = NSLock()
    private var active = false
    private var pending: Packet?
    private var workerScheduled = false
    private var latestOutput: TunerInputUpdate?
    private var outputScheduled = false
    private var installed = false // start/stop are called only by the main-actor service

    private var tracker: PitchTrackerRef?
    private var rate: Double = 0
    private var accumulated: [Float] = []
    private let analyzer = TunerSignalAnalyzer()

    init(node: AVAudioNode, handler: @escaping @MainActor @Sendable (TunerInputUpdate) -> Void) {
        self.node = node
        self.handler = handler
    }

    deinit {
        if let tracker { akPitchTrackerDestroy(tracker) }
    }

    @MainActor func start() {
        guard !installed else { return }
        lock.lock(); active = true; lock.unlock()
        node.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.offer(buffer)
        }
        installed = true
    }

    @MainActor func stop() {
        lock.lock()
        active = false
        pending = nil
        latestOutput = nil
        lock.unlock()
        if installed { node.removeTap(onBus: 0); installed = false }
    }

    private func offer(_ buffer: AVAudioPCMBuffer) {
        let count = Int(buffer.frameLength)
        guard count > 0, count <= 32768, let first = buffer.floatChannelData?[0] else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        // AVAudioEngine reuses its buffer. Copy valid frames only; never extend frameLength.
        let samples = (0..<count).map { first[$0 * stride] }
        lock.lock()
        guard active else { lock.unlock(); return }
        pending = Packet(samples: samples, sampleRate: buffer.format.sampleRate, timestamp: timestamp,
                         discontinuous: pending != nil)
        let schedule = !workerScheduled
        workerScheduled = true
        lock.unlock()
        if schedule { worker.async { [weak self] in self?.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard active, let packet = pending else {
                workerScheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            process(packet)
        }
    }

    private func process(_ packet: Packet) {
        let sampleRate = packet.sampleRate
        guard sampleRate.isFinite, (8000...192000).contains(sampleRate) else { return }
        let reset = packet.discontinuous || sampleRate != rate
        if reset || tracker == nil {
            if let tracker { akPitchTrackerDestroy(tracker) }
            tracker = akPitchTrackerCreate(UInt32(sampleRate.rounded()), 4096, 20)
            rate = sampleRate
            accumulated.removeAll(keepingCapacity: true)
            analyzer.reset()
            publish(TunerInputUpdate(estimate: nil, timestamp: packet.timestamp, resetHistory: true))
        }
        guard let tracker else { return }
        accumulated.append(contentsOf: packet.samples)
        while accumulated.count >= 4096 {
            var block = Array(accumulated.prefix(4096))
            accumulated.removeFirst(4096)
            akPitchTrackerAnalyze(tracker, &block, UInt32(block.count))
            var frequency: Float = 0, amplitude: Float = 0
            akPitchTrackerGetResults(tracker, &amplitude, &frequency)
            let estimate = analyzer.process(samples: block, sampleRate: sampleRate,
                                            candidateFrequency: Double(frequency), amplitude: Double(amplitude))
            let timestamp = packet.timestamp - Double(accumulated.count) / sampleRate
            publish(TunerInputUpdate(estimate: estimate, timestamp: timestamp, resetHistory: reset))
        }
    }

    private func publish(_ update: TunerInputUpdate) {
        lock.lock()
        guard active else { lock.unlock(); return }
        // A reset must survive coalescing with a newer estimate until the UI consumes it.
        latestOutput = TunerInputUpdate(estimate: update.estimate, timestamp: update.timestamp,
                                       resetHistory: update.resetHistory || latestOutput?.resetHistory == true)
        let schedule = !outputScheduled
        outputScheduled = true
        lock.unlock()
        if schedule {
            DispatchQueue.main.async { [weak self] in self?.deliverLatest() }
        }
    }

    @MainActor private func deliverLatest() {
        lock.lock()
        let output = active ? latestOutput : nil
        latestOutput = nil
        outputScheduled = false
        lock.unlock()
        if let output { handler(output) }
    }
}
