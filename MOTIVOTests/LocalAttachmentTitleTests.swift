//
//  LocalAttachmentTitleTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-L / C-47 — ATTACHMENT TITLES ARE LOCAL JOURNAL DATA.
//
//  A title a member types describes a local attachment. It must persist
//  whether or not a Connected identity exists, survive sign-out, and be keyed
//  by the attachment's unique id — never its filename. Three defects broke
//  that: audio renames in SessionDetailView were discarded, video renames were
//  dropped with no identity, and sign-out erased the per-identity store
//  SessionDetailView wrote to.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`).
//

import XCTest
@testable import Etudes

final class LocalAttachmentTitleTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
    }

    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ file: String, from start: String, to end: String) -> String? {
        let s = code(file)
        guard let a = s.range(of: start) else { return nil }
        let rest = s[a.upperBound...]
        guard let b = rest.range(of: end) else { return nil }
        return String(rest[..<b.lowerBound])
    }

    /// SessionDetailView's rename handler, from `onRename:` to `onFavourite:`.
    private func sessionDetailRenameHandler() -> String? {
        slice("SessionDetailView.swift", from: "onRename: { url, newTitle, kind in", to: "onFavourite:")
    }

    // MARK: - Structural

    func testSessionDetailRenamePersistsAudio() {
        guard let h = sessionDetailRenameHandler() else { return XCTFail("rename handler not found") }
        XCTAssertFalse(h.contains("guard kind == .video else { return }"),
                       "an audio rename must not be discarded after the viewer has shown it")
        XCTAssertTrue(h.contains("AttachmentTitlePersistenceKeys.writeLocalTitle("),
                      "audio and video renames must persist through the shared writer")
    }

    func testSessionDetailRenameNeedsNoIdentity() {
        guard let h = sessionDetailRenameHandler() else { return XCTFail("rename handler not found") }
        XCTAssertFalse(h.contains("sessionDetailNamespaceUserID"),
                       "a local title must persist for a never-signed-in Solo member")
    }

    func testSignOutPreservesAttachmentTitles() {
        guard let body = slice("AuthManager.swift", from: "func signOut() {", to: "Keychain.delete(\"appleUserID\")") else {
            return XCTFail("signOut not found")
        }
        for token in ["audioNamespacedKey", "videoNamespacedKey", "legacyAudioTitlesKey", "legacyVideoTitlesKey"] {
            XCTAssertFalse(body.contains(token), "sign-out must not remove attachment titles (\(token))")
        }
    }

    /// Factory reset is the one place titles may go — it must still do so.
    func testFactoryResetStillRemovesTitles() {
        let s = code("LocalFactoryReset.swift")
        XCTAssertTrue(s.contains("AttachmentTitlePersistenceKeys.legacyAudioTitlesKey"))
        XCTAssertTrue(s.contains("AttachmentTitlePersistenceKeys.legacyVideoTitlesKey"))
        XCTAssertTrue(s.contains("AttachmentTitlePersistenceKeys.audioPrefix"))
        XCTAssertTrue(s.contains("AttachmentTitlePersistenceKeys.videoPrefix"))
    }

    /// **THE ONE-OF-N GUARD, AND THE ID-ONLY RULE.** Every title write goes
    /// through the shared writer, except `PostRecordDetailsView`'s two existing
    /// stem-keyed fallbacks — which are pinned so they cannot grow.
    func testEveryTitleWriteGoesThroughTheSharedWriter() {
        let keyTokens = ["persistedAudioTitlesKey", "persistedVideoTitlesKey",
                         "\"persistedAudioTitles_v1\"", "\"persistedVideoTitles_v1\"",
                         "forKey: namespacedKey"]
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: sourceRoot.path)) ?? [])
            .filter { $0.hasSuffix(".swift") && $0 != "AttachmentTitlePersistenceKeys.swift" }
        var direct = 0
        var stemKeyed = 0
        for f in files {
            for line in code(f).components(separatedBy: .newlines) {
                if line.contains("UserDefaults.standard.set("), keyTokens.contains(where: { line.contains($0) }) {
                    direct += 1
                }
                if line.contains("persisted[stem] =") { stemKeyed += 1 }
            }
        }
        XCTAssertEqual(stemKeyed, 2, "the name-based fallback must not be expanded")
        XCTAssertEqual(direct, 2, "only the two pinned stem fallbacks may write a title store directly")
    }
}
