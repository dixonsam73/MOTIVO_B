//
//  ConnectedSharePreflightTests.swift
//  MOTIVOTests
//
//  PHASE 5 · UNIT 1 — the pre-queue decision.
//
//  The load-bearing assertions are the ones about what the preflight must NOT
//  do: it must not reject a large lossless source whose derivative fits, and it
//  must never see a private attachment at all.
//

import XCTest
@testable import Etudes

final class ConnectedSharePreflightTests: XCTestCase {

    private let limit = 50 * 1024 * 1024

    private func c(_ format: MediaFormat?, bytes: Int, seconds: Double? = nil) -> ConnectedSharePreflight.Candidate {
        .init(id: UUID(), format: format, localBytes: bytes, durationSeconds: seconds)
    }

    // MARK: - Audio: the LOCAL size is irrelevant

    /// **A 200 MB WAV IS NOT REJECTED FOR BEING 200 MB.** Five minutes of
    /// lossless is ~50 MB locally and ~1.5 MB as a derivative.
    func testLargeLosslessAudioSharesWhenItsDerivativeFits() {
        for format in [MediaFormat.wav, .aiff, .flac] {
            let big = c(format, bytes: 200 * 1024 * 1024, seconds: 300)   // 5 minutes
            XCTAssertEqual(ConnectedSharePreflight.verdict(for: big, limitBytes: limit), .canShare,
                           "\(format): a 200 MB local original whose derivative fits must share")
        }
    }

    /// Beyond ~24.8 minutes the predicted derivative exceeds the ceiling.
    func testVeryLongAudioNeedsConsent() {
        let long = c(.wav, bytes: 10 * 1024 * 1024, seconds: 40 * 60)     // 40 minutes
        XCTAssertEqual(ConnectedSharePreflight.verdict(for: long, limitBytes: limit), .needsConsent)
    }

    func testTheBoundaryMatchesTheDerivativesOwnArithmetic() {
        let maxSecs = ConnectedAudioDerivative.maxPredictedDurationSeconds(limitBytes: limit)
        let justUnder = c(.wav, bytes: 999, seconds: maxSecs - 30)
        let justOver  = c(.wav, bytes: 999, seconds: maxSecs + 30)
        XCTAssertEqual(ConnectedSharePreflight.verdict(for: justUnder, limitBytes: limit), .canShare)
        XCTAssertEqual(ConnectedSharePreflight.verdict(for: justOver, limitBytes: limit), .needsConsent)
    }

    /// Unknown duration must not be optimistic.
    func testUnknownDurationFallsBackToLocalSize() {
        XCTAssertEqual(ConnectedSharePreflight.verdict(for: c(.wav, bytes: 200 * 1024 * 1024), limitBytes: limit),
                       .needsConsent)
        XCTAssertEqual(ConnectedSharePreflight.verdict(for: c(.wav, bytes: 1024), limitBytes: limit),
                       .canShare)
    }

    // MARK: - Everything else publishes from the local file

    /// Video has NO automatic optimisation in this unit — that is C-75.
    func testOversizedVideoNeedsConsentRatherThanBeingOptimised() {
        XCTAssertEqual(ConnectedSharePreflight.verdict(for: c(.mov, bytes: 80 * 1024 * 1024, seconds: 120), limitBytes: limit),
                       .needsConsent)
        XCTAssertEqual(ConnectedSharePreflight.verdict(for: c(.mp4, bytes: 20 * 1024 * 1024, seconds: 30), limitBytes: limit),
                       .canShare)
    }

    func testOrdinaryImagesAndPDFsShare() {
        for f in [MediaFormat.jpeg, .png, .heic, .heif, .pdf] {
            XCTAssertEqual(ConnectedSharePreflight.verdict(for: c(f, bytes: 4 * 1024 * 1024), limitBytes: limit),
                           .canShare, "\(f) should share")
        }
    }

    // MARK: - Restraint

    func testMultipleOversizedAttachmentsProduceOneRestrainedMessage() {
        let all = [c(.mov, bytes: 90 * 1024 * 1024), c(.mov, bytes: 70 * 1024 * 1024), c(.jpeg, bytes: 2048)]
        let needing = ConnectedSharePreflight.requiringConsent(all, limitBytes: limit)
        XCTAssertEqual(needing.count, 2)
        let msg = ConnectedSharePreflight.consentMessage(count: needing.count)
        XCTAssertTrue(msg.contains("2 attachments"))
        XCTAssertTrue(msg.contains("remain in your Journal"),
                      "the copy must say the local original is kept")
    }

    /// The copy must never suggest the local original is lost.
    func testConsentCopyNeverImpliesLocalLoss() {
        for n in [1, 3] {
            let m = ConnectedSharePreflight.consentMessage(count: n).lowercased()
            for forbidden in ["delete", "removed", "lost", "discard"] {
                XCTAssertFalse(m.contains(forbidden), "consent copy must not imply local loss: \(m)")
            }
        }
    }
}
