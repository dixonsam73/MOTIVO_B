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

    // Native iPad is turned on one configuration at a time (RELEASE.md,
    // section B): Debug first, then Sync Test, Release last, each when its
    // step is reached. Until then an iPad runs Release and Sync Test in
    // compatibility mode, exactly as before. Change the expectation here in
    // the same commit that turns the next configuration on.
    func testNativeIPadIsOnInDebugOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("MOTIVO.xcodeproj/project.pbxproj"), encoding: .utf8)
        func deviceFamily(bundleID: String) -> String? {
            guard let idRange = project.range(of: "PRODUCT_BUNDLE_IDENTIFIER = \(bundleID);"),
                  let start = project.range(of: "buildSettings = {", options: .backwards, range: project.startIndex..<idRange.lowerBound),
                  let end = project.range(of: "};", range: idRange.upperBound..<project.endIndex),
                  let key = project.range(of: "TARGETED_DEVICE_FAMILY = ", range: start.lowerBound..<end.upperBound) else { return nil }
            return String(project[key.upperBound...].prefix { $0 != ";" }).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        XCTAssertEqual(deviceFamily(bundleID: "com.samueldixon.motivo.dev"), "1,2", "Debug runs natively on iPad")
        XCTAssertEqual(deviceFamily(bundleID: "com.samueldixon.motivo.synctest"), "1", "Sync Test stays iPhone-only until its step")
        XCTAssertEqual(deviceFamily(bundleID: "com.sdsongs.etudes"), "1", "Release stays iPhone-only until the last page is signed off")

        // One app window on iPad. Xcode's generated scene manifest allows
        // several and wins over the file, so a configuration that runs
        // natively on iPad turns generation off and takes the manifest in
        // MOTIVO/Info.plist, which allows one.
        func generatesManifest(bundleID: String) -> Bool {
            guard let idRange = project.range(of: "PRODUCT_BUNDLE_IDENTIFIER = \(bundleID);"),
                  let start = project.range(of: "buildSettings = {", options: .backwards, range: project.startIndex..<idRange.lowerBound) else { return true }
            return project[start.lowerBound..<idRange.lowerBound].contains("INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
        }
        XCTAssertFalse(generatesManifest(bundleID: "com.samueldixon.motivo.dev"), "Debug takes the one-window manifest from Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: root.appendingPathComponent("MOTIVO/Info.plist")))
        let manifest = try XCTUnwrap(plist["UIApplicationSceneManifest"] as? [String: Any])
        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false, "one app window at launch")
    }
}
