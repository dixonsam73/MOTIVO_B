//
//  ConnectedDerivativeProbe.swift
//  MOTIVOTests
//
//  PHASE 5 · C-63 — MEASURING the automatic Connected-derivative idea before
//  proposing it. Nothing here ships; it exists to turn "AAC would be smaller"
//  into numbers.
//
//  Source: a 60-second 44.1 kHz stereo 16-bit WAV (10.1 MB), plus FLAC, AIFF
//  and raw ADTS AAC transcodes of the same audio.
//
//  **A SYNTHETIC TONE COMPRESSES UNREALISTICALLY WELL**, so lossless sizes here
//  are NOT representative of music. The AAC figure is, because the preset
//  targets a bitrate rather than a quality level.
//

import XCTest
import AVFoundation
@testable import Etudes

final class ConnectedDerivativeProbe: XCTestCase {

    private func fixture(_ n: String) -> URL? { Bundle(for: Self.self).url(forResource: n, withExtension: nil) }

    private func exportM4A(from src: URL) async -> (bytes: Int, seconds: Double)? {
        let asset = AVURLAsset(url: src)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("derivative-\(UUID().uuidString).m4a")
        session.outputURL = out
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed,
              let size = (try? FileManager.default.attributesOfItem(atPath: out.path))?[.size] as? NSNumber
        else { return nil }
        let dur = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        try? FileManager.default.removeItem(at: out)
        return (size.intValue, dur)
    }

    /// **THE NUMBER THE PLAN NEEDS.** What does Apple's M4A preset actually
    /// produce, per minute?
    func testAppleM4APresetSizePerMinute() async throws {
        guard let src = fixture("tone60.wav") else { return XCTFail("fixture missing") }
        guard let r = await exportM4A(from: src) else { return XCTFail("export failed") }
        XCTAssertGreaterThan(r.seconds, 55, "fixture should be ~60s")
        let mbPerMin = (Double(r.bytes) / 1_048_576.0) / (r.seconds / 60.0)
        let kbps = (Double(r.bytes) * 8.0 / r.seconds) / 1000.0
        NSLog("[C-63] AppleM4A preset: %d bytes for %.1fs -> %.2f MB/min, ~%.0f kbps",
              r.bytes, r.seconds, mbPerMin, kbps)
        XCTAssertLessThan(mbPerMin, 3.0, "an AAC derivative should be well under 3 MB/min")
    }

    /// Every deliberate lossless/compressed source must be READABLE by the
    /// export path, or the derivative idea does not apply to it.
    func testAllDeliberateAudioSourcesCanBeExported() async throws {
        for name in ["tone60.wav", "tone60.aiff", "tone60.flac"] {
            guard let src = fixture(name) else { return XCTFail("missing \(name)") }
            let r = await exportM4A(from: src)
            XCTAssertNotNil(r, "\(name): AVAssetExportSession could not produce an M4A derivative")
            if let r { NSLog("[C-63] %@ -> %d bytes (%.1fs)", name, r.bytes, r.seconds) }
        }
    }

    /// Raw ADTS `.aac` — does Études' player stack even open it?
    func testRawAACDecodability() throws {
        guard let url = fixture("tone60.aac") else { return XCTFail("fixture missing") }
        let player = try? AVAudioPlayer(contentsOf: url)
        NSLog("[C-63] raw ADTS .aac AVAudioPlayer opened: %@", player == nil ? "NO" : "YES")
        // Reported, not asserted: the disposition is a product decision.
    }

    /// Uncompressed sizes are deterministic and DO generalise to real music.
    func testLinearPCMSizeIsDeterministic() throws {
        guard let url = fixture("tone60.wav"),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else { return XCTFail("fixture missing") }
        let mbPerMin = Double(size.intValue) / 1_048_576.0
        NSLog("[C-63] 44.1kHz stereo 16-bit WAV: %.2f MB/min -> 50 MB at ~%.1f minutes",
              mbPerMin, 50.0 / mbPerMin)
        XCTAssertEqual(mbPerMin, 10.1, accuracy: 0.3)
    }
}
