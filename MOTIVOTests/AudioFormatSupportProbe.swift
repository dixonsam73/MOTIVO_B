//
//  AudioFormatSupportProbe.swift
//  MOTIVOTests
//
//  PHASE 5 · C-63 format matrix — MEASUREMENT, NOT ASSERTION.
//
//  Établishes what Études' own playback stack can actually decode, so the
//  supported-format decision rests on a measurement rather than on "Apple
//  supports it in principle". Fixtures were produced with `afconvert` from a
//  `say`-generated AIFF and are real files of each container.
//
//  **IT MEASURES DECODABILITY ONLY.** It says nothing about whether a format
//  should be offered, whether the picker can select it, or whether Connected
//  storage accepts it — those are separate rows of the matrix.
//

import XCTest
import AVFoundation
@testable import Etudes

final class AudioFormatSupportProbe: XCTestCase {

    private func fixture(_ name: String) -> URL? {
        Bundle(for: Self.self).url(forResource: name, withExtension: nil)
    }

    private func probe(_ name: String) -> (loaded: Bool, duration: TimeInterval) {
        guard let url = fixture(name) else { return (false, 0) }
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return (false, 0) }
        return (true, p.duration)
    }

    /// The formats `kindForURL` already classifies as `.audio`.
    func testCurrentlyRecognisedAudioFormatsDecode() {
        for name in ["probe.aiff", "probe.wav", "probe.caf", "probe.m4a"] {
            let r = probe(name)
            XCTAssertTrue(r.loaded, "\(name): AVAudioPlayer could not open it")
            XCTAssertGreaterThan(r.duration, 0, "\(name): decoded but reported no duration")
        }
    }

    /// **THE FLAC QUESTION.** Not currently recognised by `kindForURL`, so it
    /// becomes `.file` and is inert in Études today. This measures only whether
    /// the playback stack could decode it if it were classified as audio.
    func testFLACDecodabilityIsMeasuredNotAssumed() throws {
        let r = probe("probe.flac")
        XCTAssertTrue(r.loaded, "FLAC did not open with AVAudioPlayer on this OS")
        XCTAssertGreaterThan(r.duration, 0, "FLAC opened but reported no duration")
    }

    /// Non-vacuity: the probe must be capable of reporting a FAILURE, or the
    /// passes above mean nothing.
    func testProbeCanFail() {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).flac")
        try? Data("this is not audio".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }
        XCTAssertNil(try? AVAudioPlayer(contentsOf: bogus),
                     "the probe must reject a file that is not audio")
    }
}
