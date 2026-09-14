import Foundation
import Synchronization

/// Scalar atomics are the only state shared by the controls and render callback.
final class DroneMailbox: Sendable {
    let frequency: Atomic<UInt64>
    let volume: Atomic<UInt64>
    let frames = Atomic<UInt64>(0)
    init(frequency: Double, volume: Double) {
        self.frequency = Atomic(frequency.bitPattern)
        self.volume = Atomic(volume.bitPattern)
    }
}

/// Owned exclusively by a single source node's render thread. The rate is the
/// node's explicit format, not a remembered session rate or a downstream output rate.
final class DroneRenderKernel: @unchecked Sendable {
    let sampleRate: Double
    let mailbox: DroneMailbox
    private var phase: Double = 0
    private var currentFrequency: Double
    private var targetFrequency: Double
    private var currentVolume: Double = 0
    private var targetVolume: Double
    private var frames: UInt64 = 0

    init(sampleRate: Double, frequency: Double, volume: Double) {
        precondition(sampleRate.isFinite && sampleRate > 0)
        self.sampleRate = sampleRate
        currentFrequency = frequency
        targetFrequency = frequency
        targetVolume = volume
        mailbox = DroneMailbox(frequency: frequency, volume: volume)
    }

    func beginBuffer() {
        targetFrequency = Double(bitPattern: mailbox.frequency.load(ordering: .acquiring))
        targetVolume = Double(bitPattern: mailbox.volume.load(ordering: .acquiring))
    }

    func nextSample() -> Float {
        // Preserve the original smoothing, gain and small second harmonic.
        currentFrequency += (targetFrequency - currentFrequency) * 0.002
        currentVolume += (targetVolume - currentVolume) * 0.002
        phase += 2 * .pi * currentFrequency / sampleRate
        if phase > 2 * .pi { phase -= 2 * .pi }
        return Float(sin(phase) * currentVolume * 0.9 + sin(2 * phase) * currentVolume * 0.1)
    }

    func endBuffer(frameCount: Int) {
        frames &+= UInt64(frameCount)
        mailbox.frames.store(frames, ordering: .releasing)
    }
}
