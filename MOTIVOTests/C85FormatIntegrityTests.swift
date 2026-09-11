//
//  C85FormatIntegrityTests.swift
//  MOTIVOTests
//
//  C-85 — A TRIMMED VIDEO IS MP4, AND MUST STAY IDENTIFIED AS MP4.
//
//  The trim tool always exports video as MP4 (`MediaTrimView`). The hand-off
//  used to pass it with no source format, so it was persisted as `.mov` and
//  uploaded as `video/quicktime`; its playback surrogate was forced to `.mov`;
//  and "Replace original" wrote the MP4 into the recording's `.mov` file.
//  Pre-existing, made more reachable by C-84. No transcoding: the bytes are
//  what they are, and every name and type now says so. The recorder's `.mov`
//  is unchanged.
//
//  Structural checks read CODE ONLY, comments stripped (`U5c-34`).
//

import XCTest
@testable import Etudes

@MainActor
final class C85FormatIntegrityTests: XCTestCase {

    // MARK: - The format decision

    func testTrimmedVideoIsIdentifiedAsMP4ThroughTheHandOff() {
        let trimmed = URL(fileURLWithPath: "/tmp/c85/1EF1B2C2-2F70-4C58-90CD-0FE1C1AC61A1.mp4")
        XCTAssertEqual(TimerStagedVideo.format(forFile: trimmed), .mp4, "an .mp4 file is MP4")
        let handed = StagedAttachment(id: UUID(), data: Data(), kind: .video,
                                      sourceFormat: TimerStagedVideo.format(forFile: trimmed))
        let ext = AttachmentImportPolicy.fileExtension(for: handed)
        XCTAssertEqual(ext, "mp4", "post-record details must persist it as .mp4")
        XCTAssertEqual(MediaFormat.from(fileExtension: ext)?.mimeType, "video/mp4", "and upload it as video/mp4")
    }

    /// CONTROL — the recorder's QuickTime output is unchanged.
    func testRecorderMovIsUnchanged() {
        let recorded = URL(fileURLWithPath: "/tmp/c85/19E75D01-7E2C-464B-A3C7-867DAA897836.mov")
        XCTAssertEqual(TimerStagedVideo.format(forFile: recorded), .mov)
        XCTAssertEqual(AttachmentImportPolicy.fileExtension(for: StagedAttachment(id: UUID(), data: Data(), kind: .video)),
                       "mov", "a video with no source format keeps the recorder's .mov")
        XCTAssertEqual(MediaFormat.mov.mimeType, "video/quicktime")
    }

    // MARK: - StagingStore.replace (simulator store)

    private var refsBackup: Data?
    private var createdRefIDs: [UUID] = []
    private var refsURL: URL { StagingStore.baseURL.appendingPathComponent("staged.json") }

    override func setUp() async throws {
        try await super.setUp()
        try StagingStore.bootstrap()
        refsBackup = try? Data(contentsOf: refsURL)
    }

    override func tearDown() async throws {
        for id in createdRefIDs {
            if let ref = StagingStore.ref(withId: id) { StagingStore.remove(ref) }
        }
        if let refsBackup { try? refsBackup.write(to: refsURL, options: .atomic) }
        createdRefIDs = []
        try await super.tearDown()
    }

    private func tempFile(_ contents: String, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("c85-\(UUID().uuidString)").appendingPathExtension(ext)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func stage(_ contents: String, ext: String, kind: StagedAttachmentRef.Kind) async throws -> StagedAttachmentRef {
        let ref = try await StagingStore.saveNew(from: try tempFile(contents, ext: ext), kind: kind,
                                                 suggestedName: "c85-\(UUID().uuidString)")
        createdRefIDs.append(ref.id)
        return ref
    }

    func testReplaceAdoptsTheTrimsContainer() async throws {
        let ref = try await stage("recorded quicktime", ext: "mov", kind: .video)
        let original = StagingStore.absoluteURL(for: ref)
        let updated = try await StagingStore.replace(original: ref, with: try tempFile("trimmed mp4", ext: "mp4"))
        let replaced = StagingStore.absoluteURL(for: updated)
        XCTAssertEqual(replaced.pathExtension, "mp4", "the file must be named for what it now contains")
        XCTAssertEqual(replaced.deletingPathExtension().lastPathComponent,
                       original.deletingPathExtension().lastPathComponent, "same stem")
        XCTAssertEqual(String(decoding: try Data(contentsOf: replaced), as: UTF8.self), "trimmed mp4")
        XCTAssertEqual(StagingStore.ref(withId: ref.id)?.relativePath, updated.relativePath, "the stored ref names the new file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path), "no stale .mov left behind")
    }

    /// CONTROL — a replace in the same container keeps its path.
    func testReplaceWithTheSameContainerKeepsItsPath() async throws {
        let ref = try await stage("take one", ext: "m4a", kind: .audio)
        let updated = try await StagingStore.replace(original: ref, with: try tempFile("take two", ext: "m4a"))
        XCTAssertEqual(updated.relativePath, ref.relativePath)
        XCTAssertEqual(String(decoding: try Data(contentsOf: StagingStore.absoluteURL(for: updated)), as: UTF8.self), "take two")
    }

    // MARK: - Structural

    func testHandOffCarriesTheVideosRealFormat() {
        XCTAssertTrue(block(after: "func makeReviewPrefill(", in: ptv)?
            .contains("sourceFormat: TimerStagedVideo.format(forFile:") ?? false,
                      "the hand-off must carry the video's real format")
    }

    func testSurrogatesUseTheTruthfulExtension() {
        let forcedMov = "appendingPathExtension(\"mov\")"
        for (marker, what) in [("private func playVideo(", "playback"), ("private func purgeStagedTempFiles(", "the purge")] {
            guard let b = block(after: marker, in: ptv) else { XCTFail("\(what) not found"); continue }
            XCTAssertTrue(b.contains("videoSurrogateURL(for:"), "\(what) must use the truthful surrogate")
        }
        XCTAssertFalse(block(after: "private func playVideo(", in: ptv)?.contains(forcedMov) ?? true, "playback must not force .mov")
        XCTAssertFalse(block(after: "func handleTrimReplaceOriginal(", in: ptv)?.contains(forcedMov) ?? true,
                       "the trim replace must not force .mov")
        XCTAssertTrue(ptv.contains("(mov|mp4|m4a|jpg)"), "the temp sweep must match MP4 surrogates")
    }

    // MARK: - Source helpers

    private var ptv: String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func block(after marker: String, in s: String) -> String? {
        guard let r = s.range(of: marker), let open = s[r.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = open
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 }
            else if s[i] == "}" { depth -= 1; if depth == 0 { return String(s[open...i]) } }
            i = s.index(after: i)
        }
        return nil
    }
}
