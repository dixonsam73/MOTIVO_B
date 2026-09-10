//
//  ConnectedAudioDerivativeTests.swift
//  MOTIVOTests
//
//  PHASE 5 · UNIT 1. Real fixtures, not synthetic assertions: WAV, AIFF and
//  FLAC produced with `afconvert`, plus white noise as the encoder's worst case.
//

import XCTest
import AVFoundation
@testable import Etudes

final class ConnectedAudioDerivativeTests: XCTestCase {

    private func fixture(_ n: String) -> URL? { Bundle(for: Self.self).url(forResource: n, withExtension: nil) }
    private var scratch: [URL] = []

    override func tearDown() {
        for u in scratch { try? FileManager.default.removeItem(at: u) }
        scratch = []
        super.tearDown()
    }

    private func out() -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("t-\(UUID().uuidString).m4a")
        scratch.append(u)
        return u
    }

    // MARK: - The deliberate audio set converts

    func testEveryDeliberateLosslessSourceProducesAnM4A() async throws {
        for name in ["tone60.wav", "tone60.aiff", "tone60.flac"] {
            guard let src = fixture(name) else { return XCTFail("missing \(name)") }
            let r = try await ConnectedAudioDerivative.make(from: src, to: out())
            XCTAssertGreaterThan(r.bytes, 0, "\(name): empty derivative")
            XCTAssertEqual(r.seconds, 60, accuracy: 1.0, "\(name): duration must be preserved")
        }
    }

    /// Sample rate and channels come from the SOURCE, never hard-coded.
    func testSourceSampleRateAndChannelsArePreserved() async throws {
        guard let src = fixture("tone60.wav") else { return XCTFail("missing fixture") }
        let dst = out()
        _ = try await ConnectedAudioDerivative.make(from: src, to: dst)
        guard let track = try await AVURLAsset(url: dst).loadTracks(withMediaType: .audio).first,
              let asbd = try await track.load(.formatDescriptions).first
                  .flatMap({ CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee })
        else { return XCTFail("no output track") }
        XCTAssertEqual(asbd.mSampleRate, 44_100, accuracy: 1)
        XCTAssertEqual(Int(asbd.mChannelsPerFrame), 2)
    }

    // MARK: - The margin

    /// **THE REASON THE MARGIN EXISTS.** White noise makes the encoder EXCEED
    /// the requested bitrate, so `duration × bitrate` is not an upper bound —
    /// but the margined prediction must still cover it.
    func testMarginCoversTheEncodersWorstCase() async throws {
        guard let src = fixture("noise60.wav") else { throw XCTSkip("noise fixture absent") }
        let r = try await ConnectedAudioDerivative.make(from: src, to: out())
        let unmargined = Int(60.0 * Double(ConnectedAudioDerivative.targetBitrate) / 8.0)
        XCTAssertGreaterThan(r.bytes, unmargined,
                             "white noise is expected to EXCEED the theoretical size; if it does not, re-derive the margin")
        XCTAssertLessThan(r.bytes, ConnectedAudioDerivative.predictedBytes(durationSeconds: 60),
                          "the margined prediction must cover the measured worst case")
    }

    func testPredictionIsConservativeForOrdinaryContent() async throws {
        guard let src = fixture("tone60.wav") else { return XCTFail("missing fixture") }
        let r = try await ConnectedAudioDerivative.make(from: src, to: out())
        XCTAssertLessThan(r.bytes, ConnectedAudioDerivative.predictedBytes(durationSeconds: r.seconds))
    }

    /// ~24.8 minutes at 256 kbps under a 50 MB ceiling.
    func testMaxPredictedDuration() {
        let secs = ConnectedAudioDerivative.maxPredictedDurationSeconds(limitBytes: 50 * 1024 * 1024)
        XCTAssertEqual(secs / 60, 24.8, accuracy: 0.3)
    }

    // MARK: - Failure propagates rather than degrading

    func testUnreadableSourceThrowsRatherThanProducingAnEmptyFile() async {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).wav")
        try? Data("not audio".utf8).write(to: bogus)
        scratch.append(bogus)
        do {
            _ = try await ConnectedAudioDerivative.make(from: bogus, to: out())
            XCTFail("a non-audio source must throw, not yield a silent empty derivative")
        } catch { /* expected */ }
    }

    // MARK: - Format identity

    func testDeliberateSetOnly() {
        for ext in ["wav", "aiff", "aif", "mp3", "m4a", "flac", "jpg", "jpeg", "png", "heic", "heif", "mov", "mp4", "pdf"] {
            XCTAssertNotNil(MediaFormat.from(fileExtension: ext), "\(ext) must be deliberate")
        }
        for ext in ["gif", "bmp", "tiff", "tif", "caf", "m4v", "avi", "aac", "zip", "docx", "mid"] {
            XCTAssertNil(MediaFormat.from(fileExtension: ext), "\(ext) must NOT be supported")
        }
    }

    /// Every format declares what it actually is — the C-74 defect.
    func testMimeAndExtensionAreTruthful() {
        XCTAssertEqual(MediaFormat.heif.mimeType, "image/heif", "heif had no branch at all before")
        XCTAssertEqual(MediaFormat.heic.mimeType, "image/heic")
        XCTAssertEqual(MediaFormat.png.mimeType, "image/png")
        XCTAssertEqual(MediaFormat.flac.fileExtension, "flac")
        XCTAssertEqual(MediaFormat.wav.mimeType, "audio/wav")
        for f in MediaFormat.allCases {
            XCTAssertEqual(MediaFormat.from(fileExtension: f.fileExtension), f,
                           "\(f) must round-trip through its own extension")
        }
    }

    /// Policy A: all deliberate audio publishes as M4A/AAC.
    func testAllDeliberateAudioTakesTheDerivativePath() {
        for f in MediaFormat.allCases where f.kind == .audio {
            XCTAssertTrue(f.needsConnectedAudioDerivative, "\(f) must publish as an M4A derivative")
        }
        for f in MediaFormat.allCases where f.kind != .audio {
            XCTAssertFalse(f.needsConnectedAudioDerivative)
        }
    }
}

// MARK: - C-79 — the Float32 WAV case, found on device

extension ConnectedAudioDerivativeTests {

    /// **DEVICE-OBSERVED FAILURE, REPRODUCED HERE.** A 48 kHz **Float32** WAV —
    /// an ordinary export from a DAW, and one Études deliberately supports —
    /// failed conversion on device with AVFoundation's "Cannot Open", while the
    /// identical file converts on macOS. `AVAudioPlayer` reads it fine, which is
    /// why the preflight correctly saw a duration and raised no dialog.
    ///
    /// If this passes on the simulator but the device still fails, the cause is
    /// not the sample format and this test must not be read as covering it.
    func testFloat32WAVConverts() async throws {
        guard let src = Bundle(for: Self.self).url(forResource: "float32_60.wav", withExtension: nil) else {
            throw XCTSkip("float32 fixture absent")
        }
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("f32-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: dst) }

        let r = try await ConnectedAudioDerivative.make(from: src, to: dst)
        XCTAssertGreaterThan(r.bytes, 0, "a Float32 WAV must produce a derivative")
        XCTAssertEqual(r.seconds, 60, accuracy: 1.0)
    }
}
