import Foundation

/// Immutable, preallocated mono samples. Created off the render thread and retained for its run.
final class MetronomeSoundBank: @unchecked Sendable {
    let sampleRate: Double
    private let samples: UnsafeMutablePointer<Float>
    private let offsets: UnsafeMutablePointer<Int>
    private let lengths: UnsafeMutablePointer<Int>
    private let total: Int
    private let voiceCount: Int

    init(normal: [Float], accent: [Float], sourceRate: Double, renderRate: Double) {
        precondition(sourceRate > 0 && renderRate > 0 && !normal.isEmpty && !accent.isEmpty)
        sampleRate = renderRate
        var voices: [[Float]] = []
        for role in [MetronomeClickRole.downbeat, .beat, .subdivision, .groupAccent] {
            // A whole-tone lift gives group starts a middle voice between the two recordings.
            // Prepare it once here; the audio callback still reads only preallocated samples.
            let input: [Float]
            if role == .groupAccent {
                input = Self.resample(normal, from: sourceRate * pow(2, 2.0 / 12), to: sourceRate)
            } else {
                input = role == .downbeat ? accent : normal
            }
            let shaped = Self.shape(input, rate: sourceRate, role: role)
            voices.append(Self.resample(shaped, from: sourceRate, to: renderRate))
        }
        total = voices.reduce(0) { $0 + $1.count }
        voiceCount = voices.count
        samples = .allocate(capacity: total)
        offsets = .allocate(capacity: voiceCount)
        lengths = .allocate(capacity: voiceCount)
        var offset = 0
        for (index, voice) in voices.enumerated() {
            offsets.initialize(to: offset, at: index)
            lengths.initialize(to: voice.count, at: index)
            voice.withUnsafeBufferPointer { source in
                samples.advanced(by: offset).initialize(from: source.baseAddress!, count: source.count)
            }
            offset += voice.count
        }
    }
    deinit {
        samples.deinitialize(count: total); samples.deallocate()
        offsets.deinitialize(count: voiceCount); offsets.deallocate()
        lengths.deinitialize(count: voiceCount); lengths.deallocate()
    }
    func count(_ voice: Int) -> Int { lengths[voice] }
    func sample(_ voice: Int, _ frame: Int) -> Float { samples[offsets[voice] + frame] }

    static func shape(_ input: [Float], rate: Double, role: MetronomeClickRole) -> [Float] {
        // The approved Dry envelope, derived from the original recordings without changing assets.
        let duration: Double = role == .subdivision ? 0.020 : 0.080
        let count = min(input.count, max(2, Int(duration * rate)))
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let time = Double(i) / rate
            var value = input[i] * Float(exp(-time / 0.035))
            if role == .subdivision {
                // Retain the recorded attack; end with a smooth taper instead of an abrupt cut.
                let envelope = pow(max(0, 1 - Double(i) / Double(count - 1)), 1.5)
                value *= Float(envelope)
            } else {
                let fadeFrames = max(2, Int(rate * 0.004))
                if i >= count - fadeFrames { value *= Float(count - 1 - i) / Float(fadeFrames) }
            }
            if role == .groupAccent {
                // Keep the strike intact, then gently damp its pitched ring. The smooth join
                // avoids a second transient, and the original beat/subdivision voices stay intact.
                let tail = max(0, time - 0.010) / 0.022
                value *= Float(exp(-tail * tail))
            }
            result[i] = value
        }
        return result
    }

    /// Windowed-sinc conversion is performed once while preparing the bank, never while rendering.
    static func resample(_ input: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        if sourceRate == targetRate { return input }
        let count = max(1, Int((Double(input.count) * targetRate / sourceRate).rounded()))
        var result = [Float](repeating: 0, count: count)
        let cutoff = min(1, targetRate / sourceRate)
        let radius = 16
        for i in 0..<count {
            let position = Double(i) * sourceRate / targetRate
            let centre = Int(position)
            var sum = 0.0
            var weightSum = 0.0
            for j in (centre - radius + 1)...(centre + radius) {
                let distance = position - Double(j)
                guard abs(distance) < Double(radius) else { continue }
                let x = Double.pi * distance * cutoff
                let sinc = abs(x) < 1e-12 ? 1 : sin(x) / x
                let window = 0.5 + 0.5 * cos(Double.pi * distance / Double(radius))
                let weight = sinc * window * cutoff
                weightSum += weight
                if j >= 0 && j < input.count { sum += Double(input[j]) * weight }
            }
            result[i] = Float(weightSum == 0 ? 0 : sum / weightSum)
        }
        return result
    }
}

private extension UnsafeMutablePointer where Pointee == Int {
    func initialize(to value: Int, at index: Int) { advanced(by: index).initialize(to: value) }
}
