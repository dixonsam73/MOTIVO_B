//
//  StorefrontReloadTests.swift
//  MOTIVOTests
//
//  P5-L — STOREFRONT-CHANGE HARDENING. SEPARATE FROM C-42's HISTORICAL
//  OBSERVATION, which was measured on Release, did not reproduce, and is not
//  explained or fixed by this.
//
//  Products load once at `start()`. If the member's App Store storefront
//  changes while the app runs, the membership screen would keep the old
//  storefront's prices until relaunch — Apple's own sheet would still be right.
//  StoreKit's supported `Storefront.updates` sequence reports the change; the
//  store reloads products when it does, with the same task pattern it already
//  uses for `Transaction.updates`.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`).
//

import XCTest

final class StorefrontReloadTests: XCTestCase {

    private func code() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/ConnectedMembershipStore.swift"),
                               encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// A storefront change reloads products, and observation starts with the store.
    func testStorefrontChangeReloadsProducts() {
        let s = code()
        guard let loop = s.range(of: "in Storefront.updates") else {
            return XCTFail("the store must observe Storefront.updates")
        }
        let body = String(s[loop.upperBound...].prefix(400))
        XCTAssertTrue(body.contains("await loadProducts()"), "a storefront change must reload products")

        guard let start = s.range(of: "func start() {") else { return XCTFail("start() not found") }
        let startBody = String(s[start.upperBound...].prefix(400))
        XCTAssertTrue(startBody.contains("startStorefrontObservation()"),
                      "storefront observation must begin with the store, like transaction observation")
    }
}
