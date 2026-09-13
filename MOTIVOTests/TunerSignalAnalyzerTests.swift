import XCTest
@testable import Etudes

final class TunerSignalAnalyzerTests: XCTestCase {
    private func wave(frequency: Double, rate: Double, phase: Double = 0, harmonics: Bool = false,
                      missing: Bool = false, count: Int = 8192) -> [Float] {
        (0..<count).map { i in
            let x = phase + Double(i) * 2 * .pi * frequency / rate
            if missing { return Float(0.1 * (sin(2*x) + 0.7*sin(3*x) + 0.4*sin(4*x))) }
            if harmonics { return Float(0.1 * (sin(x) + 0.5*sin(2*x) + 0.333333*sin(3*x) + 0.25*sin(4*x) + 0.2*sin(5*x))) }
            return Float(0.25 * sin(x))
        }
    }
    private func noise(seed: UInt32, count: Int = 8192) -> [Float] {
        var value = seed
        return (0..<count).map { _ in
            value ^= value << 13; value ^= value >> 17; value ^= value << 5
            return Float((Double(value) / 2147483648 - 1) * 0.25)
        }
    }

    func testBassPrecisionWithBiasedCandidatesAndDifferentPhases() throws {
        for rate in [44100.0, 48000] {
            for midi in [23, 28, 33, 38, 43] {
                for cents in [-40.0, 0, 25] {
                    let hz = 440 * pow(2, (Double(midi) + cents/100 - 69)/12)
                    for phase in [0.0, 0.7, 2.1] {
                        let result = try XCTUnwrap(TunerSignalAnalyzer().process(
                            samples: wave(frequency: hz, rate: rate, phase: phase), sampleRate: rate,
                            candidateFrequency: hz * 1.02, amplitude: 0.5))
                        XCTAssertLessThanOrEqual(abs(1200 * log2(result.frequency / hz)), 3)
                    }
                }
            }
        }
    }

    func testWeakAndMissingFundamentalsRetainTheirBassPitch() throws {
        for rate in [44100.0, 48000] {
            for hz in [30.867706, 41.203445, 55, 73.416192, 97.998859] {
                for missing in [false, true] {
                    let result = try XCTUnwrap(TunerSignalAnalyzer().process(
                        samples: wave(frequency: hz, rate: rate, harmonics: true, missing: missing),
                        sampleRate: rate, candidateFrequency: hz * 0.98, amplitude: 0.5))
                    XCTAssertLessThanOrEqual(abs(1200 * log2(result.frequency / hz)), 3)
                }
            }
        }
    }

    func testHighHarmonicNotesAreNotRejectedByIntegerLagQuantisation() throws {
        for rate in [44100.0, 48000] {
            for midi in 100...108 {
                let hz = 440 * pow(2, Double(midi-69)/12)
                for missing in [false, true] {
                    let result = try XCTUnwrap(TunerSignalAnalyzer().process(
                        samples: wave(frequency: hz, rate: rate, harmonics: true, missing: missing),
                        sampleRate: rate, candidateFrequency: hz, amplitude: 0.5))
                    XCTAssertGreaterThanOrEqual(result.confidence, 0.88)
                }
            }
        }
    }

    func testSingleBadOctaveCandidateIsRevalidatedFromCurrentBassSamples() throws {
        let analyzer = TunerSignalAnalyzer()
        let hz = 30.1626869416
        let tone = wave(frequency: hz, rate: 44100, missing: true)
        _ = analyzer.process(samples: tone, sampleRate: 44100, candidateFrequency: hz, amplitude: 0.5)
        let recovered = try XCTUnwrap(analyzer.process(samples: tone, sampleRate: 44100,
                                                      candidateFrequency: hz * 2, amplitude: 0.5))
        XCTAssertEqual(1200 * log2(recovered.frequency / hz), 0, accuracy: 3)
        XCTAssertNil(analyzer.process(samples: tone, sampleRate: 44100,
                                     candidateFrequency: hz * 2, amplitude: 0.5))
    }

    func testOctaveRecoveryCannotValidateNoise() {
        let analyzer = TunerSignalAnalyzer()
        _ = analyzer.process(samples: wave(frequency: 55, rate: 48000), sampleRate: 48000,
                             candidateFrequency: 55, amplitude: 0.5)
        XCTAssertNil(analyzer.process(samples: noise(seed: 317), sampleRate: 48000,
                                     candidateFrequency: 110, amplitude: 0.5))
    }

    func testGenuineOctaveChangeIsNotHeldBySignalRecovery() throws {
        let analyzer = TunerSignalAnalyzer()
        _ = analyzer.process(samples: wave(frequency: 55, rate: 48000), sampleRate: 48000,
                             candidateFrequency: 55, amplitude: 0.5)
        let changed = try XCTUnwrap(analyzer.process(samples: wave(frequency: 110, rate: 48000),
                                                    sampleRate: 48000, candidateFrequency: 110, amplitude: 0.5))
        XCTAssertEqual(1200 * log2(changed.frequency / 110), 0, accuracy: 3)
    }

    func testNoiseCannotValidateDefaultOrRetainedPitch() {
        for rate in [44100.0, 48000] {
            for seed: UInt32 in [1, 1234567, 987654321] {
                for candidate in [100.0, 440, 2401] {
                    XCTAssertNil(TunerSignalAnalyzer().process(samples: noise(seed: seed), sampleRate: rate,
                                                             candidateFrequency: candidate, amplitude: 0.5))
                }
            }
        }
    }

    func testNoiseAfterToneWithdrawsConfidenceOnCurrentSamples() throws {
        let analyzer = TunerSignalAnalyzer()
        XCTAssertNotNil(analyzer.process(samples: wave(frequency: 440, rate: 48000), sampleRate: 48000,
                                        candidateFrequency: 440, amplitude: 0.5))
        XCTAssertNil(analyzer.process(samples: noise(seed: 1234567, count: 4096), sampleRate: 48000,
                                     candidateFrequency: 440, amplitude: 0.5))
    }

    func testQuietPeriodicInputAndModestBackgroundNoiseRemainUsable() throws {
        let tone = wave(frequency: 110, rate: 48000)
        let background = noise(seed: 3456)
        let mixed = zip(tone, background).map { $0 + 0.1 * $1 }
        XCTAssertNotNil(TunerSignalAnalyzer().process(samples: mixed, sampleRate: 48000,
                                                    candidateFrequency: 110, amplitude: 0.5))
        XCTAssertNotNil(TunerSignalAnalyzer().process(samples: tone.map { $0 * 0.02 }, sampleRate: 48000,
                                                    candidateFrequency: 110, amplitude: 0.03))
    }

    func testSilenceAndDCDoNotProduceSignal() {
        for level: Float in [0, 0.25, -0.5] {
            XCTAssertNil(TunerSignalAnalyzer().process(samples: [Float](repeating: level, count: 8192),
                                                     sampleRate: 48000, candidateFrequency: 440, amplitude: 0.5))
        }
    }

    func testInvalidSamplesAndRatesAreRejected() {
        let analyzer = TunerSignalAnalyzer()
        XCTAssertNil(analyzer.process(samples: [.nan], sampleRate: 48000, candidateFrequency: 440, amplitude: 0.5))
        for rate in [0.0, Double.nan, .infinity] {
            XCTAssertNil(analyzer.process(samples: [0.1], sampleRate: rate, candidateFrequency: 440, amplitude: 0.5))
        }
    }

    func testRateChangeRequiresFreshLowNoteHistory() {
        let analyzer = TunerSignalAnalyzer()
        let hz = 30.867706
        XCTAssertNotNil(analyzer.process(samples: wave(frequency: hz, rate: 44100), sampleRate: 44100,
                                        candidateFrequency: hz, amplitude: 0.5))
        XCTAssertNil(analyzer.process(samples: wave(frequency: hz, rate: 48000, count: 4096), sampleRate: 48000,
                                     candidateFrequency: hz, amplitude: 0.5))
    }

    func testInvalidOrBelowThresholdCandidateIsNotAccepted() {
        let tone = wave(frequency: 440, rate: 48000)
        for candidate in [0.0, -440, Double.nan, .infinity] {
            XCTAssertNil(TunerSignalAnalyzer().process(samples: tone, sampleRate: 48000,
                                                     candidateFrequency: candidate, amplitude: 0.5))
        }
        XCTAssertNil(TunerSignalAnalyzer().process(samples: tone, sampleRate: 48000,
                                                 candidateFrequency: 440, amplitude: 0.0199))
    }
    func testEstablishedBassGuitarAndPianoPitchesContinueIntoQuietDecay() throws {
        for rate in [44100.0, 48000] {
            for hz in [30.867706, 41.203445, 82.406889, 110, 261.625565, 440] {
                let analyzer = TunerSignalAnalyzer()
                XCTAssertNotNil(analyzer.process(samples: wave(frequency: hz, rate: rate),
                    sampleRate: rate, candidateFrequency: hz, amplitude: 0.5))
                for (index, level) in [0.03, 0.019, 0.012, 0.008, 0.006].enumerated() {
                    let current = hz * pow(2, Double(index) * 4 / 1200)
                    let tone = wave(frequency: current, rate: rate, harmonics: true).map { $0 * Float(level) }
                    let estimate = try XCTUnwrap(analyzer.process(samples: tone, sampleRate: rate,
                        candidateFrequency: current, amplitude: level))
                    XCTAssertEqual(1200 * log2(estimate.frequency / current), 0, accuracy: 3)
                    XCTAssertGreaterThanOrEqual(estimate.confidence, 0.88)
                }
            }
        }
    }

    func testQuietContinuationCannotValidateNoiseOrPersistAfterIt() {
        let hz = 110.0, rate = 48000.0
        for seed: UInt32 in [1, 317, 1234567] {
            let analyzer = TunerSignalAnalyzer()
            let tone = wave(frequency: hz, rate: rate)
            XCTAssertNotNil(analyzer.process(samples: tone, sampleRate: rate,
                candidateFrequency: hz, amplitude: 0.5))
            XCTAssertNil(analyzer.process(samples: noise(seed: seed).map { $0 * 0.008 },
                sampleRate: rate, candidateFrequency: hz, amplitude: 0.008))
            XCTAssertNil(analyzer.process(samples: tone.map { $0 * 0.008 },
                sampleRate: rate, candidateFrequency: hz, amplitude: 0.008))
        }
    }

    func testQuietContinuationCannotStartANewPitchOrSurviveReset() {
        for action in ["note", "reset", "rate", "silence", "tooQuiet"] {
            let analyzer = TunerSignalAnalyzer()
            XCTAssertNotNil(analyzer.process(samples: wave(frequency: 110, rate: 44100),
                sampleRate: 44100, candidateFrequency: 110, amplitude: 0.5))
            if action == "reset" { analyzer.reset() }
            if action == "silence" {
                XCTAssertNil(analyzer.process(samples: [Float](repeating: 0, count: 8192),
                    sampleRate: 44100, candidateFrequency: 110, amplitude: 0.008))
            }
            let rate = action == "rate" ? 48000.0 : 44100.0
            let hz = action == "note" ? 220.0 : 110.0
            XCTAssertNil(analyzer.process(samples: wave(frequency: hz, rate: rate).map { $0 * 0.008 },
                sampleRate: rate, candidateFrequency: hz, amplitude: action == "tooQuiet" ? 0.004 : 0.008), action)
            XCTAssertNotNil(analyzer.process(samples: wave(frequency: hz, rate: rate),
                sampleRate: rate, candidateFrequency: hz, amplitude: 0.5), action)
        }
    }

    func testQuietContinuationRequiresStrongerTonalEvidence() {
        let tone = wave(frequency: 110, rate: 48000)
        let mixed = zip(tone, noise(seed: 317)).map { $0 * 0.008 + $1 * 0.002 }
        // The same periodic signal qualifies at the existing acquisition confidence threshold.
        XCTAssertNotNil(TunerSignalAnalyzer().process(samples: mixed, sampleRate: 48000,
            candidateFrequency: 110, amplitude: 0.5))
        let analyzer = TunerSignalAnalyzer()
        XCTAssertNotNil(analyzer.process(samples: tone, sampleRate: 48000,
            candidateFrequency: 110, amplitude: 0.5))
        XCTAssertNil(analyzer.process(samples: mixed, sampleRate: 48000,
            candidateFrequency: 110, amplitude: 0.008))
    }

    func testQuietBassContinuationStopsOnTheNextNoiseOrSilenceBlock() {
        for rate in [44100.0, 48000] {
            for hz in [30.867706, 41.203445, 82.406889] {
                for silent in [true, false] {
                    let analyzer = TunerSignalAnalyzer()
                    let tone = wave(frequency: hz, rate: rate)
                    XCTAssertNotNil(analyzer.process(samples: tone, sampleRate: rate,
                        candidateFrequency: hz, amplitude: 0.5))
                    XCTAssertNotNil(analyzer.process(samples: tone.map { $0 * 0.008 }, sampleRate: rate,
                        candidateFrequency: hz, amplitude: 0.008))
                    let absent = silent ? [Float](repeating: 0, count: 4096)
                        : noise(seed: 97, count: 4096).map { $0 * 0.008 }
                    XCTAssertNil(analyzer.process(samples: absent, sampleRate: rate,
                        candidateFrequency: hz, amplitude: 0.008), "\(hz) Hz must not survive on older samples")
                }
            }
        }
    }

}
