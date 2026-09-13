import Foundation
import Synchronization

/// Only these lock-free scalar atomics cross the main/audio boundary. Each run owns a new mailbox.
final class MetronomeMailbox: Sendable {
    let command: Atomic<UInt64>
    let beat = Atomic<UInt64>(0)
    let frames = Atomic<UInt64>(0)
    init(settings: MetronomeSettings) { command = Atomic(settings.command(running: true)) }
}

private struct MetronomeVoice {
    var sample = 0
    var position = 0
    var gain: Float = 0
}

/// Mutable members and voice memory are used exclusively by the source-node render thread.
/// Control code can only touch `mailbox`; immutable `bank` lives until the node releases the kernel.
final class MetronomeRenderKernel: @unchecked Sendable {
    let mailbox: MetronomeMailbox
    let bank: MetronomeSoundBank
    private var timeline: MetronomeTimeline
    private var settings: MetronomeRenderSettings
    private var running = false
    private var smoothedVolume: Float
    private let smoothing: Float
    private let voices: UnsafeMutablePointer<MetronomeVoice>
    private let voiceCapacity = 16
    private var voiceSlot = 0
    private var beatSequence: UInt64 = 0
    private var renderedFrames: UInt64 = 0
    // Read only after rendering has stopped; used by offline validation, never by the live UI.
    private(set) var maximumUnclampedSample: Float = 0

    init(bank: MetronomeSoundBank, mailbox: MetronomeMailbox) {
        self.bank = bank
        self.mailbox = mailbox
        settings = MetronomeRenderSettings(command: mailbox.command.load(ordering: .acquiring))
        timeline = MetronomeTimeline(sampleRate: bank.sampleRate, settings: settings)
        smoothedVolume = settings.volume
        smoothing = Float(1 - exp(-1 / (bank.sampleRate * 0.004)))
        voices = .allocate(capacity: voiceCapacity)
        voices.initialize(repeating: MetronomeVoice(), count: voiceCapacity)
    }
    deinit { voices.deinitialize(count: voiceCapacity); voices.deallocate() }

    func beginBuffer() {
        let next = MetronomeRenderSettings(command: mailbox.command.load(ordering: .acquiring))
        if !next.running {
            if running {
                for index in 0..<voiceCapacity { voices[index].gain = 0 }
            }
            running = false
        } else {
            if !running {
                timeline = MetronomeTimeline(sampleRate: bank.sampleRate, settings: next)
                smoothedVolume = next.volume
                beatSequence = 0
            } else {
                timeline.update(next)
            }
            running = true
        }
        settings = next
    }

    func nextSample() -> Float {
        guard running else { return 0 }
        if let tick = timeline.nextFrame() {
            voices[voiceSlot] = MetronomeVoice(sample: tick.role.sampleIndex,
                                             position: 0, gain: tick.role.gain)
            voiceSlot = (voiceSlot + 1) % voiceCapacity
            if tick.isPrimary {
                beatSequence &+= 2
                mailbox.beat.store(beatSequence | (tick.role == .downbeat ? 1 : 0), ordering: .releasing)
            }
        }
        // Zero really means silence, including a click tail. Other volume changes are smoothed.
        smoothedVolume = settings.volume == 0 ? 0 : smoothedVolume + (settings.volume - smoothedVolume) * smoothing
        var sample: Float = 0
        for index in 0..<voiceCapacity where voices[index].gain != 0 {
            let voice = voices[index]
            sample += bank.sample(voice.sample, voice.position) * voice.gain
            voices[index].position += 1
            if voices[index].position >= bank.count(voice.sample) { voices[index].gain = 0 }
        }
        sample *= smoothedVolume
        maximumUnclampedSample = max(maximumUnclampedSample, abs(sample))
        return min(1, max(-1, sample))
    }

    func endBuffer(frameCount: Int) {
        renderedFrames &+= UInt64(frameCount)
        mailbox.frames.store(renderedFrames, ordering: .releasing)
    }
}
