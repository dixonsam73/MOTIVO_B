//
//  QueuePayloadCompatibilityProbe.swift
//  MOTIVOTests
//
//  PHASE 5 · C-63 Unit 1 — MEASURING the durable-consent payload migration
//  before committing to it, not asserting it.
//
//  Two directions matter and they are different questions:
//   FORWARD  — a NEW build must decode an OLD queue file (the field is absent).
//   ROLLBACK — an OLD build must decode a NEW queue file (an unknown key).
//
//  `op` set the forward precedent in P4-U2a-2; this measures the ROLLBACK
//  direction too, which nothing has previously established.
//

import XCTest
@testable import Etudes

final class QueuePayloadCompatibilityProbe: XCTestCase {

    /// A queue file written by TODAY's build.
    private func currentEncoded() throws -> Data {
        let p = SessionSyncQueue.PostPublishPayload(
            id: UUID(), sessionID: UUID(), sessionTimestamp: Date(), title: "compat",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: true, notes: nil, areNotesPrivate: false)
        return try JSONEncoder().encode(p)
    }

    /// FORWARD: today's decoder must tolerate a payload missing a key it does
    /// not yet know about — i.e. the shape a legacy file already has.
    func testLegacyPayloadWithoutTheNewKeyDecodes() throws {
        let json = #"""
        {"id":"11111111-1111-1111-1111-111111111111",
         "sessionID":"22222222-2222-2222-2222-222222222222",
         "isPublic":true,"areNotesPrivate":false,"title":"legacy"}
        """#
        let decoded = try JSONDecoder().decode(SessionSyncQueue.PostPublishPayload.self,
                                               from: Data(json.utf8))
        XCTAssertEqual(decoded.title, "legacy")
        XCTAssertTrue(decoded.isPublic)
    }

    /// **ROLLBACK — the direction nothing had established.** An older build
    /// decoding a file that carries a key it has never heard of.
    func testUnknownKeyIsIgnoredByTheDecoder() throws {
        var obj = try JSONSerialization.jsonObject(with: currentEncoded()) as! [String: Any]
        obj["authorisedOmissions"] = ["33333333-3333-3333-3333-333333333333"]
        let data = try JSONSerialization.data(withJSONObject: obj)

        XCTAssertNoThrow(try JSONDecoder().decode(SessionSyncQueue.PostPublishPayload.self, from: data),
                         "an unknown key must not break an older build's decode")
    }

    /// Non-vacuity: the decoder must still REJECT a genuinely malformed file,
    /// or the two passes above prove nothing about its strictness.
    func testDecoderStillRejectsMalformedPayloads() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            SessionSyncQueue.PostPublishPayload.self, from: Data(#"{"isPublic":"yes"}"#.utf8)))
    }
}
