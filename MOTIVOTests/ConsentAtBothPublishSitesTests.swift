//
//  ConsentAtBothPublishSitesTests.swift
//  MOTIVOTests
//
//  PHASE 5 · UNIT 1b — BOTH publish call sites, asserted.
//
//  **Unit 1b was initially half done and said so:** the decision was wired at
//  `AddEditSessionView` only, so an oversized explicitly-shared attachment
//  created through `PostRecordDetailsView` still reached the queue without
//  consent. This is the assertion that would have caught it, and that stops it
//  regressing.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`, and five times since).
//

import XCTest
@testable import Etudes

final class ConsentAtBothPublishSitesTests: XCTestCase {

    private func code(_ file: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(file)"), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let sites = ["AddEditSessionView.swift", "PostRecordDetailsView.swift"]

    /// Every publish site's SAVE BUTTON runs the preflight.
    ///
    /// **THE FIRST VERSION OF THIS WAS VACUOUS.** It asserted that the file
    /// merely CONTAINED `attemptSaveWithConnectedPreflight()`, which matches the
    /// function's own DECLARATION — so removing the call from the Save button
    /// still passed. Presence of the fix again, the trap P5-M recorded. It now
    /// pins the BUTTON'S ACTION, and reverting the gate fails it.
    func testBothSitesGateTheSaveButtonOnThePreflight() {
        for file in sites {
            let s = code(file)
            XCTAssertTrue(s.contains("Button(action: { attemptSaveWithConnectedPreflight() })"),
                          "\(file): the Save button itself must run the Connected preflight")
            let all = s + code(file.replacingOccurrences(of: ".swift", with: "+Attachments.swift"))
            XCTAssertTrue(all.contains("ConnectedSharePreflight.requiringConsent("),
                          "\(file): must ask the shared preflight, not its own rule")
        }
    }

    /// One consent model, not two.
    func testBothSitesReuseTheSameConsentBoundary() {
        for file in sites {
            let s = code(file)
            XCTAssertTrue(s.contains("ConnectedShareConsentState()"),
                          "\(file): must reuse the shared consent state")
            XCTAssertTrue(s.contains("confirmShareWithoutOmittedAttachments()"),
                          "\(file): must offer Share Without It")
        }
    }

    /// The consent must reach the durable payload at BOTH sites, or a retry
    /// would omit nothing.
    func testBothSitesCarryConsentIntoThePayload() {
        for file in sites {
            XCTAssertTrue(code(file).contains("authorisedOmissions: authorisedOmissions.isEmpty ? nil : authorisedOmissions"),
                          "\(file): the authorised set must travel in the payload")
        }
    }

    /// **THE INVARIANT THAT MATTERS MOST.** Consent must never be achieved by
    /// rewriting the member's persistent privacy choice.
    func testNeitherSiteMutatesPrivacyToAchieveAnOmission() {
        for file in sites {
            let s = code(file) + code(file.replacingOccurrences(of: ".swift", with: "+Attachments.swift"))
            guard let r = s.range(of: "func confirmShareWithoutOmittedAttachments()") else {
                return XCTFail("\(file): consent path not found")
            }
            let body = String(s[r.lowerBound...].prefix(400))
            XCTAssertFalse(body.contains("setPrivate("),
                           "\(file): an omission must not rewrite the private-eye state")
            XCTAssertFalse(body.contains("AttachmentPrivacy.setPrivate"),
                           "\(file): an omission must not rewrite the private-eye state")
        }
    }
}
