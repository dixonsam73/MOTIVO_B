import Foundation
import Accelerate

struct TunerPitchEstimate: Sendable {
    let frequency: Double
    let amplitude: Double
    let confidence: Double
    let rms: Double
}

/// Checks PTrack's candidate against CURRENT samples. A retained PTrack frequency is not confidence.
/// Owned by the tuner's serial analysis queue; keeps at most 8192 valid first-channel samples.
final class TunerSignalAnalyzer {
    private var samples: [Double] = []
    private var sampleRate: Double = 0
    private let capacity = 8192
    private var lastValidatedFrequency: Double?
    private var usedOctaveRecovery = false

    func reset() {
        samples.removeAll(keepingCapacity: true)
        sampleRate = 0
        lastValidatedFrequency = nil
        usedOctaveRecovery = false
    }

    func process(samples input: [Float], sampleRate rate: Double,
                 candidateFrequency: Double, amplitude: Double) -> TunerPitchEstimate? {
        guard rate.isFinite, (8000...192000).contains(rate), !input.isEmpty,
              input.allSatisfy({ $0.isFinite }) else { reset(); return nil }
        if rate != sampleRate { reset(); sampleRate = rate }
        samples.append(contentsOf: input.suffix(capacity).map(Double.init))
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        guard candidateFrequency.isFinite, (20...5000).contains(candidateFrequency),
              amplitude.isFinite, amplitude >= 0.02 else { return nil }

        if let estimate = analyseCandidate(candidateFrequency, rate: rate, amplitude: amplitude) {
            lastValidatedFrequency = estimate.frequency
            usedOctaveRecovery = false
            return estimate
        }
        // PTrack can emit one octave error on a weak bass fundamental. Recover only one
        // such frame, and only by validating the previous pitch against CURRENT samples.
        // A genuine new octave validates above and is never held back by this recovery.
        guard !usedOctaveRecovery, let previous = lastValidatedFrequency,
              abs(abs(1200 * log2(candidateFrequency / previous)) - 1200) < 50 else { return nil }
        usedOctaveRecovery = true
        return analyseCandidate(previous, rate: rate, amplitude: amplitude)
    }

    private func analyseCandidate(_ candidateFrequency: Double, rate: Double,
                                  amplitude: Double) -> TunerPitchEstimate? {
        let period = rate / candidateFrequency
        // Several cycles are essential for low notes. A short onset must not validate an old candidate.
        guard samples.count >= max(2048, Int(ceil(period * 3))) else { return nil }
        let count = min(samples.count, max(2048, Int(ceil(period * 4))))
        let data = Array(samples.suffix(count))
        var sum = [Double](repeating: 0, count: count + 1)
        var squares = sum
        for i in data.indices {
            sum[i + 1] = sum[i] + data[i]
            squares[i + 1] = squares[i] + data[i] * data[i]
        }
        let variance = max(0, squares[count] / Double(count) - pow(sum[count] / Double(count), 2))
        let rms = sqrt(variance)
        guard rms >= 0.0005 else { return nil }

        // Pearson correlation compensates for DC and the different overlap energies at each lag.
        // Search locally around PTrack, retaining it as the pitch source and octave decision.
        let low = max(2, Int(floor(period * 0.94)))
        let high = min(count / 2 - 1, Int(ceil(period * 1.06)))
        guard low < high else { return nil }
        var correlations = [Double](repeating: 0, count: high - low + 3)
        var multiplePeriodConfidence: Double = 0
        data.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            func correlation(at lag: Int) -> Double {
                let length = count - lag
                var dot: Double = 0
                vDSP_dotprD(base, 1, base.advanced(by: lag), 1, &dot, vDSP_Length(length))
                let sx = sum[length], sy = sum[count] - sum[lag]
                let xx = squares[length] - sx * sx / Double(length)
                let yy = squares[count] - squares[lag] - sy * sy / Double(length)
                let denominator = sqrt(max(0, xx * yy))
                return denominator > 1e-20
                    ? (dot - sx * sy / Double(length)) / denominator : 0
            }
            for lag in (low - 1)...(high + 1) {
                correlations[lag - low + 1] = correlation(at: lag)
            }
            if candidateFrequency > 1000 {
                // At high pitches one period has few samples. Use additional complete periods
                // to avoid rejecting harmonic-rich notes solely due to integer-lag quantisation.
                // This qualifies periodicity only; PTrack still determines the note/octave.
                for multiple in 2...4 {
                    let lag = Int((period * Double(multiple)).rounded())
                    if lag < count / 2 {
                        multiplePeriodConfidence = max(multiplePeriodConfidence, correlation(at: lag))
                    }
                }
            }
        }
        var best = 1
        for i in 2..<(correlations.count - 1) where correlations[i] > correlations[best] { best = i }
        let confidence = min(1, max(0, max(correlations[best], multiplePeriodConfidence)))
        guard confidence >= 0.88 else { return nil }

        // Refine bass/low-mid notes where PTrack's FFT estimate wobbles. At high notes its
        // spectral estimate is more precise than a parabola over only a few samples per period.
        var frequency = candidateFrequency
        if candidateFrequency <= 200 {
            let left = correlations[best - 1], centre = correlations[best], right = correlations[best + 1]
            let curvature = left - 2 * centre + right
            guard curvature < -1e-12, best > 1, best < correlations.count - 2 else { return nil }
            let shift = max(-0.5, min(0.5, 0.5 * (left - right) / curvature))
            let lag = Double(low + best - 1) + shift
            frequency = rate / lag
        }
        return TunerPitchEstimate(frequency: frequency, amplitude: amplitude,
                                  confidence: confidence, rms: rms)
    }
}
