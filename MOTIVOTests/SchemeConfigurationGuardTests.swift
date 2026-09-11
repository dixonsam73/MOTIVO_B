//
//  SchemeConfigurationGuardTests.swift
//  MOTIVOTests
//
//  C-52 — THE SHARED SCHEME'S RUN ACTION MUST BUILD RELEASE, WITH NO PINNED
//  STOREKIT CONFIGURATION.
//
//  It was silently reverted TWICE, each time as a side effect of an unrelated
//  commit: `0daecd1` (2026-08-14, Debug + a pinned StoreKit file) and `3d49c4c`
//  (2026-09-09, Debug). Both times `CLAUDE.md` kept saying "the Run action is
//  Release", which is exactly why a durable document is not evidence of a
//  repository fact. Debug's bundle id is unknown to App Store Connect, so on a
//  Debug run `Product.products(for:)` returns nothing — the C-29 signature —
//  and any QA that needs real StoreKit is quietly invalid.
//
//  A third revert now fails the suite instead of waiting to be noticed.
//

import XCTest

final class SchemeConfigurationGuardTests: XCTestCase {

    private func launchAction() -> String? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let scheme = root.appendingPathComponent("MOTIVO.xcodeproj/xcshareddata/xcschemes/MOTIVO.xcscheme")
        guard let xml = try? String(contentsOf: scheme, encoding: .utf8),
              let start = xml.range(of: "<LaunchAction"),
              let end = xml.range(of: "</LaunchAction>", range: start.upperBound..<xml.endIndex) else { return nil }
        return String(xml[start.lowerBound..<end.upperBound])
    }

    func testRunActionBuildsRelease() {
        guard let action = launchAction() else { return XCTFail("LaunchAction not found in the shared scheme") }
        XCTAssertTrue(action.contains("buildConfiguration = \"Release\""),
                      "the shared scheme's Run action must build Release (C-52); Debug cannot transact")
    }

    func testRunActionPinsNoStoreKitConfiguration() {
        guard let action = launchAction() else { return XCTFail("LaunchAction not found in the shared scheme") }
        XCTAssertFalse(action.lowercased().contains("storekitconfiguration"),
                       "a pinned StoreKit configuration silences real StoreKit in every configuration (C-52)")
    }
}
