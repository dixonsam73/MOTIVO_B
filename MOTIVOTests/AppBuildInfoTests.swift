import XCTest
@testable import Etudes

final class AppBuildInfoTests: XCTestCase {
    func testLabelShowsVersionBuildAndCommit() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.0",
                                   "CFBundleVersion": "1750",
                                   "EtudesGitCommit": "8cbcd8e"]
        XCTAssertEqual(AppBuildInfo.label(info: info), "Version 1.0 (1750 · 8cbcd8e)")
    }

    func testLabelWithoutACommitStillShowsTheBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "131"]
        XCTAssertEqual(AppBuildInfo.label(info: info), "Version 1.0 (131)")
    }
}
