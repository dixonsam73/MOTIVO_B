import XCTest
import AVFoundation
import CryptoKit
@testable import Etudes

enum MetronomeTestSamples {
    static func load(_ name: String) throws -> (samples: [Float], rate: Double) {
        // Host validation supplies a source directory; native app-hosted tests use bundled assets.
        let override = ProcessInfo.processInfo.environment["ETUDES_METRONOME_SAMPLES"]
        let url = override.map { URL(fileURLWithPath: $0).appendingPathComponent(name + ".wav") }
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
        let file = try AVAudioFile(forReading: XCTUnwrap(url))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let data = try XCTUnwrap(buffer.floatChannelData)
        return (Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))), buffer.format.sampleRate)
    }
    static func bank(rate: Double = 44100) throws -> MetronomeSoundBank {
        let normal = try load("metronome_click_normal"), accent = try load("metronome_click_accent")
        return MetronomeSoundBank(normal: normal.samples, accent: accent.samples, sourceRate: normal.rate, renderRate: rate)
    }
}

final class MetronomeSoundTests: XCTestCase {
    func testSoleVoicePreservesTheApprovedDryWaveforms() throws {
        // PCM fingerprints captured from the previous build's Dry bank, before this refinement.
        let expected = ["ba976b6570946a4d677d926d2e6f511952e69702a21c4d8836394e5137727789",
                        "8f254d890f359b45b375ec50cdc84c5ac656971f05c54d3f5f7c4d5ba4a68493",
                        "9628044e1a018292e0a8dc891331f99a2da9447ced0a263889389306e2aca609"]
        let bank = try MetronomeTestSamples.bank(rate: 44100)
        for voice in 0..<3 {
            let pcm = (0..<bank.count(voice)).map { Int16((max(-1, min(1, bank.sample(voice, $0))) * 32767).rounded()) }
            let hash = pcm.withUnsafeBytes { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
            XCTAssertEqual(hash, expected[voice], "Approved Dry voice \(voice) changed")
        }
    }
    func testConvertedSamplesPreserveDurationAndToneFrequency() {
        let sourceRate = 44100.0
        let tone = (0..<4410).map { Float(sin(2 * Double.pi * 1600 * Double($0) / sourceRate)) }
        for rate in [48000.0, 96000] {
            let converted = MetronomeSoundBank.resample(tone, from: sourceRate, to: rate)
            XCTAssertEqual(Double(converted.count) / rate, 0.1, accuracy: 1 / rate)
            var error = 0.0
            for i in 40..<(converted.count - 40) {
                let ideal = sin(2 * Double.pi * 1600 * Double(i) / rate)
                error += pow(Double(converted[i]) - ideal, 2)
            }
            XCTAssertLessThan(sqrt(error / Double(converted.count - 80)), 0.002)
        }
    }
    func testSubdivisionsHaveShorterEnvelopesAndQuietEndpoints() throws {
        let bank = try MetronomeTestSamples.bank()
        XCTAssertEqual(Double(bank.count(2)) / bank.sampleRate, 0.020, accuracy: 1 / bank.sampleRate)
        XCTAssertLessThan(bank.count(2), bank.count(1))
        for voice in 0..<4 {
            XCTAssertEqual(bank.sample(voice, bank.count(voice) - 1), 0, accuracy: 0.00001)
        }
    }
    func testAllVoicesAreFiniteAndContainRecordedEnergy() throws {
        for rate in [44100.0, 48000, 96000] {
            let bank = try MetronomeTestSamples.bank(rate: rate)
            for voice in 0..<4 {
                var energy: Double = 0
                for i in 0..<bank.count(voice) {
                    let value = bank.sample(voice, i)
                    XCTAssertTrue(value.isFinite); XCTAssertLessThan(abs(value), 1)
                    energy += Double(value * value)
                }
                XCTAssertGreaterThan(energy, 0.001)
            }
        }
    }
    func testGroupAccentRaisesPitchByOneToneWithoutMovingItsAttack() {
        let sourceRate = 44100.0
        let tone = (0..<6890).map { Float(sin(2 * Double.pi * 1000 * Double($0) / sourceRate)) }
        for rate in [44100.0, 48000, 96000] {
            let bank = MetronomeSoundBank(normal: tone, accent: tone, sourceRate: sourceRate, renderRate: rate)
            var crossings: [Double] = []
            // Measure the stable body; the deliberately silent tail is not a pitch crossing.
            for i in Int(rate * 0.01)..<Int(rate * 0.06) {
                let previous = Double(bank.sample(3, i - 1)), current = Double(bank.sample(3, i))
                if previous < 0 && current >= 0 {
                    crossings.append(Double(i - 1) + (-previous) / (current - previous))
                }
            }
            let frequency = Double(crossings.count - 1) * rate / (crossings.last! - crossings.first!)
            XCTAssertEqual(frequency, 1000 * pow(2, 2.0 / 12), accuracy: 0.2)
            XCTAssertEqual(Double(bank.count(3)) / rate, 0.080, accuracy: 1 / rate)
            let attack = (0..<bank.count(3)).first { abs(bank.sample(3, $0)) > 0.01 }
            XCTAssertLessThanOrEqual(attack ?? Int.max, Int(rate * 0.0001), "No audible pre-roll or onset delay")
        }
    }
    func testGroupAccentRetainsComparableLevelAndStaysBetweenTheRecordedTones() throws {
        let bank = try MetronomeTestSamples.bank()
        func energy(_ voice: Int) -> Double {
            (0..<bank.count(voice)).reduce(0.0) { $0 + pow(Double(bank.sample(voice, $1)), 2) }
        }
        let relativeDB = 10 * log10(energy(3) / energy(1))
        XCTAssertLessThan(abs(relativeDB), 1, "Changing the group tone should not also make a large level change")
        // Spectral peaks distinguish the actual wooden clicks, rather than relying only on gain.
        func peak(_ voice: Int) -> Double {
            stride(from: 1300.0, through: 2400, by: 10).max { frequencyA, frequencyB in
                func power(_ frequency: Double) -> Double {
                    var re = 0.0, im = 0.0
                    for i in 0..<bank.count(voice) {
                        let phase = 2 * Double.pi * frequency * Double(i) / bank.sampleRate
                        let value = Double(bank.sample(voice, i))
                        re += value * cos(phase); im -= value * sin(phase)
                    }
                    return re * re + im * im
                }
                return power(frequencyA) < power(frequencyB)
            }!
        }
        XCTAssertGreaterThan(peak(3), peak(1) * 1.09)
        XCTAssertLessThan(peak(3), peak(0) * 0.94)
    }

    func testGroupAccentDampsTheRingWithoutChangingTheStrike() throws {
        let normal = try MetronomeTestSamples.load("metronome_click_normal")
        let lifted = MetronomeSoundBank.resample(normal.samples,
            from: normal.rate * pow(2, 2.0 / 12), to: normal.rate)
        // The earlier group voice used the regular Dry envelope after the same pitch shift.
        let previous = MetronomeSoundBank.shape(lifted, rate: normal.rate, role: .beat)
        let revised = MetronomeSoundBank.shape(lifted, rate: normal.rate, role: .groupAccent)
        XCTAssertEqual(revised.count, previous.count)
        for frame in 0..<Int(normal.rate * 0.010) {
            XCTAssertEqual(revised[frame], previous[frame], "The initial recorded strike must remain intact")
        }
        let tail = Int(normal.rate * 0.020)..<previous.count
        let oldEnergy = tail.reduce(0.0) { $0 + pow(Double(previous[$1]), 2) }
        let newEnergy = tail.reduce(0.0) { $0 + pow(Double(revised[$1]), 2) }
        XCTAssertLessThan(newEnergy / oldEnergy, 0.5, "The sustained ring should be audibly reduced")
        XCTAssertEqual(revised.last!, 0, accuracy: 0.00001)
    }

}
