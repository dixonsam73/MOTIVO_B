//
//  PublishConsentCarriageTests.swift
//  MOTIVOTests
//
//  C-82 — THE MEMBER'S "SHARE WITHOUT IT" MUST SURVIVE EVERY REBUILD.
//
//  Unit 1b carried `authorisedOmissions` from both editors into the payload —
//  and `PublishService.publish` then REBUILT the payload without it, and the
//  queue's merge rebuilt it again without it. The consent never reached the
//  queue. Its only prior tests checked the editors' source text and an
//  encode/decode round trip, neither of which sees a rebuild.
//
//  **So the guard covers EVERY construction of the payload, not the sites
//  already known to be wrong.** A construction must carry the omissions, or be
//  provably unable to carry attachments, or be the one legacy site — exempt only
//  while it stays unreachable.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`).
//

import XCTest
@testable import Etudes

@MainActor
final class PublishConsentCarriageTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
    }

    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private var appFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: sourceRoot.path)) ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted()
    }

    /// Every `PostPublishPayload(` construction in app code, as (file, argument list).
    private func constructions() -> [(file: String, args: String)] {
        var out: [(String, String)] = []
        for f in appFiles {
            let s = code(f)
            var search = s.startIndex
            while let r = s.range(of: "PostPublishPayload(", range: search..<s.endIndex) {
                var depth = 1
                var i = r.upperBound
                while i < s.endIndex, depth > 0 {
                    if s[i] == "(" { depth += 1 } else if s[i] == ")" { depth -= 1 }
                    i = s.index(after: i)
                }
                out.append((f, String(s[r.upperBound..<i])))
                search = i
            }
        }
        return out
    }

    /// **THE C-82 GUARD.** No construction may silently drop the consent.
    func testEveryPayloadConstructionCarriesOmissionsOrCannotCarryAttachments() {
        let all = constructions()
        XCTAssertEqual(all.count, 9,
                       "the payload inventory changed — decide deliberately whether the new site can carry attachments")
        var offenders: [String] = []
        for (file, args) in all {
            let carries: Bool = {
                guard let r = args.range(of: "authorisedOmissions:") else { return false }
                let value = args[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                return !value.hasPrefix("nil")
            }()
            let attachmentFree = args.contains("isPublic: false") || args.contains("sessionID: nil")
            let legacy = file == "PublishService.swift" && args.contains("isPublic: sIsPublic")
            if !(carries || attachmentFree || legacy) {
                offenders.append("\(file): \(args.prefix(80))…")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "these rebuilds drop the member's consent: \(offenders)")
    }

    /// The legacy `publishIfNeeded` payload has no consent source, so it is exempt
    /// ONLY while nothing outside `PublishService` can reach it.
    func testLegacyPublishPathStaysUnreachable() {
        for f in appFiles where f != "PublishService.swift" {
            let s = code(f)
            for entry in ["publishIfNeeded(", ".publish(objectID:", ".unpublish(objectID:"] {
                XCTAssertFalse(s.contains(entry),
                               "\(f) reaches the legacy publish path (\(entry)), which carries no consent")
            }
        }
    }

    /// Behavioural: a later same-operation update keeps the earlier consent.
    func testQueueMergeKeepsAuthorisedOmissions() {
        let queue = SessionSyncQueue.shared
        queue.clear()
        defer { queue.clear() }
        let postID = UUID(), sessionID = UUID(), omitted = [UUID()]

        func payload(title: String, omissions: [UUID]?) -> SessionSyncQueue.PostPublishPayload {
            SessionSyncQueue.PostPublishPayload(
                id: postID, sessionID: sessionID, sessionTimestamp: nil, title: title,
                durationSeconds: nil, activityType: nil, activityDetail: nil,
                instrumentLabel: nil, mood: nil, effort: nil,
                isPublic: true, authorisedOmissions: omissions)
        }

        queue.enqueue(payload(title: "first", omissions: omitted))
        queue.enqueue(payload(title: "edited", omissions: nil))
        XCTAssertEqual(queue.items.first { $0.id == postID }?.authorisedOmissions, omitted,
                       "a same-operation merge must keep the member's consent")
        XCTAssertEqual(queue.items.first { $0.id == postID }?.title, "edited")

        let newer = [UUID()]
        queue.enqueue(payload(title: "re-consented", omissions: newer))
        XCTAssertEqual(queue.items.first { $0.id == postID }?.authorisedOmissions, newer,
                       "a newer consent replaces the older one")
    }

    /// The post-record save no longer queues a session-less public stub ahead of
    /// `publish`'s own asynchronous enqueue.
    func testPostRecordSaveQueuesNoStub() {
        XCTAssertFalse(code("PostRecordDetailsView.swift").contains("markForPublish("),
                       "the redundant stub enqueue must stay removed")
    }
}
