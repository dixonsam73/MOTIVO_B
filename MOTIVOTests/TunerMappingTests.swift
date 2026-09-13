import XCTest
@testable import Etudes

final class TunerMappingTests: XCTestCase {
    private func frequency(_ midi: Double, reference: Double = 440) -> Double {
        reference * pow(2, (midi - 69) / 12)
    }
    @discardableResult private func settle(_ mapper: TunerMapper, midi: Double, start: Double = 0,
                                          count: Int = 8) -> TunerDisplayState {
        var result = TunerDisplayState.listening
        for i in 0..<count {
            result = mapper.process(frequency: frequency(midi), amplitude: 0.5, timestamp: start + Double(i) * 0.085)
        }
        return result
    }

    func testSteadyNotesAndDetuningsAcrossPianoRange() {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        for midi in 21...108 {
            for cents in [0.0, -40, -25, -6.1, -5, 5, 6.1, 25, 40] {
                let result = settle(TunerMapper(), midi: Double(midi) + cents / 100)
                XCTAssertEqual(result.noteName, "\(names[midi % 12])\(midi / 12 - 1)")
                XCTAssertEqual(result.cents, Int(cents.rounded()))
                XCTAssertEqual(result.isInTune, abs(cents) <= 6)
                XCTAssertTrue(result.hasSignal)
            }
        }
    }

    func testA4ToDetunedE2DoesNotStickOnBFlat() {
        let mapper = TunerMapper(); settle(mapper, midi: 69)
        let result = settle(mapper, midi: 40.4, start: 0.7, count: 3)
        XCTAssertEqual(result.noteName, "E2")
        XCTAssertEqual(result.cents, 40)
        XCTAssertTrue(result.hasSignal)
    }

    func testE2ToDetunedA2DoesNotStickOnG() {
        let mapper = TunerMapper(); settle(mapper, midi: 40)
        let result = settle(mapper, midi: 44.6, start: 0.7, count: 3)
        XCTAssertEqual(result.noteName, "A2")
        XCTAssertEqual(result.cents, -40)
    }

    func testOneOctaveOutlierIsNeutralAndDoesNotPolluteLaterReadings() {
        let mapper = TunerMapper(); settle(mapper, midi: 45)
        let outlier = settle(mapper, midi: 57, start: 0.7, count: 1)
        XCTAssertEqual(outlier.noteName, "A2")
        XCTAssertEqual(outlier.cents, 0)
        XCTAssertFalse(outlier.hasSignal)
        XCTAssertFalse(outlier.isInTune)
        let recovered = settle(mapper, midi: 45, start: 0.785, count: 1)
        XCTAssertEqual(recovered.cents, 0)
        XCTAssertTrue(recovered.isInTune)
    }

    func testGenuineOctaveChangeAcquiresWithoutIntermediateNotes() {
        let mapper = TunerMapper(); settle(mapper, midi: 45)
        let first = settle(mapper, midi: 57, start: 0.7, count: 1)
        let second = settle(mapper, midi: 57, start: 0.785, count: 1)
        XCTAssertFalse(first.hasSignal)
        XCTAssertEqual(second.noteName, "A3")
        XCTAssertEqual(second.cents, 0)
        XCTAssertTrue(second.hasSignal)
    }

    func testLocalBoundaryHysteresisHasABoundedRelease() {
        let mapper = TunerMapper(); settle(mapper, midi: 69)
        XCTAssertEqual(settle(mapper, midi: 69.55, start: 1).noteName, "A4")
        let released = settle(mapper, midi: 69.65, start: 2)
        XCTAssertEqual(released.noteName, "B♭4")
        XCTAssertEqual(released.cents, -35)
    }

    func testFrequencyAndCentsDescribeTheSameAcceptedEstimate() throws {
        let mapper = TunerMapper(); settle(mapper, midi: 69)
        for (index, cents) in [12.0, 22, 8, -4, 16, 1].enumerated() {
            let state = mapper.process(frequency: frequency(69 + cents / 100), amplitude: 0.5,
                                       timestamp: 1 + Double(index) * 0.085)
            let hz = try XCTUnwrap(state.frequencyHz)
            let shown = try XCTUnwrap(state.cents)
            XCTAssertEqual(1200 * log2(hz / 440), Double(shown), accuracy: 0.50001)
        }
    }

    func testSignalHoldIsNeutralAndExpiresWithoutAnAudioCallback() {
        let mapper = TunerMapper()
        _ = mapper.process(frequency: 440, amplitude: 0.5, timestamp: 0)
        let held = mapper.noSignal(at: 0.399)
        XCTAssertEqual(held.noteName, "A4")
        XCTAssertFalse(held.hasSignal)
        XCTAssertFalse(held.isInTune)
        XCTAssertEqual(mapper.noSignal(at: 0.401), .listening)
    }

    func testInvalidInputNeverProducesAPitch() {
        for hz in [0.0, -10, Double.nan, .infinity, -.infinity, .leastNonzeroMagnitude] {
            XCTAssertEqual(TunerMapper().process(frequency: hz, amplitude: 0.5, timestamp: 0), .listening)
        }
        for amp in [0.0, 0.019, Double.nan, .infinity] {
            XCTAssertEqual(TunerMapper().process(frequency: 440, amplitude: amp, timestamp: 0), .listening)
        }
    }

    func testReferenceChangesClearHistoryAndUseTheSelectedConcertPitch() {
        let mapper = TunerMapper(); settle(mapper, midi: 69)
        for reference in [392.0, 415, 440, 442, 460] {
            mapper.setReferenceA4(reference)
            let result = mapper.process(frequency: reference, amplitude: 0.5, timestamp: reference)
            XCTAssertEqual(result.noteName, "A4")
            XCTAssertEqual(result.cents, 0)
            XCTAssertTrue(result.isInTune)
        }
    }

    func testSixCentThresholdIsNotWidenedByRounding() {
        for cents in [-6.1, -5.9, 5.9, 6.1] {
            let state = settle(TunerMapper(), midi: 69 + cents / 100)
            XCTAssertEqual(state.isInTune, abs(cents) <= 6)
        }
    }

    func testRepeatedIdenticalFrequencyRemainsCurrent() {
        let mapper = TunerMapper()
        for i in 0..<100 {
            let state = mapper.process(frequency: 440, amplitude: 0.5, timestamp: Double(i) / 10)
            XCTAssertTrue(state.hasSignal)
            XCTAssertTrue(state.isInTune)
        }
    }
}
