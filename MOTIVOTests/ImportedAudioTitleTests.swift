//
//  ImportedAudioTitleTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-78 — AN IMPORTED AUDIO FILE KEEPS ITS NAME.
//
//  Importing `Again.wav` must title the attachment `Again`. The name was
//  dropped at staging on BOTH production import paths, because each view's
//  `stageData` recorded a passed name only for `.file`/`.pdf` — and it recorded
//  it into `stagedAttachmentDisplayNames_temp`, which **no audio-title reader
//  consults**. The audio UI reads `stagedAudioNames_temp` (and, once saved,
//  `persistedAudioTitles_v1` or the persisted file's stem).
//
//  **WHY THE GUARD COUNTS CALL SITES.** This workstream produced three
//  one-of-N misses in a row. The seeding must happen in BOTH `stageData`
//  bodies through the ONE shared rule, and a third copy must fail here.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`). **The counted token
//  is the qualified CALL, `AttachmentImportPolicy.seedImportedAudioTitle(`,
//  which the declaration `static func seedImportedAudioTitle(` does not
//  contain** — a source assertion that matches its own declaration is vacuous
//  (Unit 1b §4).
//

import XCTest
@testable import Etudes

final class ImportedAudioTitleTests: XCTestCase {

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

    /// The body of `func stageData(` in a file, up to the next member function.
    private func stageDataBody(in file: String) -> String? {
        let s = code(file)
        guard let start = s.range(of: "func stageData(") else { return nil }
        let rest = s[start.upperBound...]
        let end = rest.range(of: "\n    func ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    private let callToken = "AttachmentImportPolicy.seedImportedAudioTitle("
    private let importPaths = ["AddEditSessionView+Attachments.swift",
                               "PostRecordDetailsView+Attachments.swift"]

    // MARK: - Structural: both paths, one rule, no third copy

    /// **FAILS ON THE PRE-C-78 IMPLEMENTATION** — neither `stageData` seeds a
    /// title for audio at all.
    func testBothStageDataBodiesSeedTheImportedAudioTitle() {
        for file in importPaths {
            guard let body = stageDataBody(in: file) else {
                XCTFail("\(file): stageData not found"); continue
            }
            XCTAssertEqual(body.components(separatedBy: callToken).count - 1, 1,
                           "\(file): stageData must seed an imported audio title exactly once, through the shared rule")
        }
    }

    /// **THE ONE-OF-N GUARD.** Exactly two call sites in the whole app — one
    /// per production import path. A third means a third import path whose
    /// parity must be checked deliberately.
    func testSeedingIsCalledFromExactlyTheTwoImportPaths() {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: sourceRoot.path)) ?? [])
            .filter { $0.hasSuffix(".swift") }
        var sites: [String: Int] = [:]
        for f in files {
            let n = code(f).components(separatedBy: callToken).count - 1
            if n > 0 { sites[f] = n }
        }
        XCTAssertEqual(sites, Dictionary(uniqueKeysWithValues: importPaths.map { ($0, 1) }),
                       "imported-audio title seeding must be called once from each of the two import paths and nowhere else")
    }

    /// Neither view keeps its own copy of the rule — no direct write of the
    /// audio-names map inside `stageData`.
    func testNeitherStageDataWritesTheAudioNamesMapDirectly() {
        for file in importPaths {
            guard let body = stageDataBody(in: file) else {
                XCTFail("\(file): stageData not found"); continue
            }
            XCTAssertFalse(body.contains("\"stagedAudioNames_temp\""),
                           "\(file): stageData must defer to AttachmentImportPolicy, not write the map itself")
        }
    }

    // MARK: - Behavioural: the rule itself

    private var defaults: UserDefaults!
    private let suite = "ImportedAudioTitleTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func names() -> [String: String] {
        (defaults.dictionary(forKey: AttachmentImportPolicy.stagedAudioNamesKey) as? [String: String]) ?? [:]
    }

    /// `Again.wav` → `Again`, trimmed, without disturbing other staged names.
    func testAudioImportSeedsItsStemAsTheTitle() {
        let other = UUID(), id = UUID()
        defaults.set([other.uuidString: "Earlier take"], forKey: AttachmentImportPolicy.stagedAudioNamesKey)
        AttachmentImportPolicy.seedImportedAudioTitle(stagedID: id, kind: .audio, displayName: "  Again \n", defaults: defaults)
        XCTAssertEqual(names()[id.uuidString], "Again")
        XCTAssertEqual(names()[other.uuidString], "Earlier take")
    }

    /// Only audio takes its title from the source name (video is C-80's).
    func testNonAudioKindsSeedNothing() {
        for kind in [AttachmentKind.image, .video, .pdf, .file] {
            let id = UUID()
            AttachmentImportPolicy.seedImportedAudioTitle(stagedID: id, kind: kind, displayName: "Again", defaults: defaults)
            XCTAssertNil(names()[id.uuidString], "\(kind) must not be titled from its source name")
        }
    }

    /// Recordings and photo-library items pass no name — nothing is seeded.
    func testMissingOrBlankNameSeedsNothing() {
        for name in [nil, "", "   \n"] as [String?] {
            AttachmentImportPolicy.seedImportedAudioTitle(stagedID: UUID(), kind: .audio, displayName: name, defaults: defaults)
        }
        XCTAssertTrue(names().isEmpty)
    }

    /// A rename always wins; the seed never overwrites.
    func testSeedNeverOverwritesAnExistingTitle() {
        let id = UUID()
        defaults.set([id.uuidString: "Renamed"], forKey: AttachmentImportPolicy.stagedAudioNamesKey)
        AttachmentImportPolicy.seedImportedAudioTitle(stagedID: id, kind: .audio, displayName: "Again", defaults: defaults)
        XCTAssertEqual(names()[id.uuidString], "Renamed")
    }

    /// The seeded map is the one the audio readers actually consult — the
    /// register's first proposal wrote a map none of them read.
    func testTheSeededKeyIsTheOneAudioReadersUse() {
        XCTAssertEqual(AttachmentImportPolicy.stagedAudioNamesKey, "stagedAudioNames_temp")
        XCTAssertNotEqual(AttachmentImportPolicy.stagedAudioNamesKey, "stagedAttachmentDisplayNames_temp")
        for file in importPaths {
            XCTAssertTrue(code(file).contains("\"stagedAudioNames_temp\""),
                          "\(file): its audio-title readers must read the map the rule seeds")
        }
    }
}
