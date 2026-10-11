//
//  SaveThoughtHandoffTests.swift
//  MOTIVOTests
//
//  SAVE A SPONTANEOUS RECORDING AS A THOUGHT — the hand-off, the consumption
//  rule, the editor's final-id title migration, the thumbnail map and the
//  trim format, driven as the production code the timer and editor call.
//
//  The views' `@State` cannot be driven from XCTest, so what can run, runs on
//  disposable fixtures (a staging root override, a UserDefaults suite), and
//  the wiring that only the views hold is pinned structurally — CODE ONLY,
//  comments stripped (`U5c-34`), as `C84SessionPreservationTests` does.
//

import XCTest
@testable import Etudes

@MainActor
final class SaveThoughtHandoffTests: XCTestCase {

    private let fm = FileManager.default
    private var stagingRoot: URL!
    private var defaults: UserDefaults!
    private let suite = "SaveThoughtHandoffTests"

    override func setUp() async throws {
        try await super.setUp()
        guard UnitTestHost.isActive else {
            throw XCTSkip("UnitTestHost.isActive is false; the staging root override would be ignored")
        }
        stagingRoot = fm.temporaryDirectory.appendingPathComponent("SaveThought-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        StagingStore.unitTestRootOverride = stagingRoot
        try StagingStore.bootstrap()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        StagingStore.unitTestRootOverride = nil
        if let stagingRoot, fm.fileExists(atPath: stagingRoot.path) { try? fm.removeItem(at: stagingRoot) }
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func tempFile(_ contents: String, ext: String) throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("st-\(UUID().uuidString)").appendingPathExtension(ext)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func stage(_ contents: String, ext: String, kind: StagedAttachmentRef.Kind, id: UUID = UUID()) async throws -> StagedAttachmentRef {
        try await StagingStore.saveNew(from: try tempFile(contents, ext: ext), kind: kind,
                                       suggestedName: id.uuidString, id: id)
    }

    private func audio(_ id: UUID, _ bytes: String = "AUDIO") -> StagedAttachment {
        StagedAttachment(id: id, data: Data(bytes.utf8), kind: .audio)
    }

    private func image(_ id: UUID) -> StagedAttachment {
        StagedAttachment(id: id, data: Data("IMAGE".utf8), kind: .image)
    }

    private func make(audio a: [StagedAttachment] = [], videos v: [TimerStagedVideo] = [], images i: [StagedAttachment] = [],
                      audioTitles: [UUID: String] = [:], videoTitles: [UUID: String] = [:],
                      thumbnail: UUID? = nil, pending: Int = 0,
                      readVideo: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }) throws -> TimerThoughtHandoff {
        try TimerThoughtHandoffBuilder.make(audio: a, videos: v, images: i,
                                            audioTitles: audioTitles, videoTitles: videoTitles,
                                            thumbnailID: thumbnail, threadLabel: "Études",
                                            pendingStagingCount: pending, readVideo: readVideo)
    }

    // MARK: - The hand-off builder (real staging store)

    func testOneAudioOneVideoSeveralClipsAndPhotosMakeOnePayloadWithPlayableMedia() async throws {
        let a1 = try await stage("A1", ext: "m4a", kind: .audio)
        let a2 = try await stage("A2", ext: "m4a", kind: .audio)
        let v1 = try await stage("V1-MOV", ext: "mov", kind: .video)
        let v2 = try await stage("V2-MP4", ext: "mp4", kind: .video)
        let p1 = try await stage("P1", ext: "jpg", kind: .image)

        let payload = try make(
            audio: [audio(a1.id, "A1"), audio(a2.id, "A2")],
            videos: [TimerStagedVideo(id: v1.id, fileURL: StagingStore.absoluteURL(for: v1)),
                     TimerStagedVideo(id: v2.id, fileURL: StagingStore.absoluteURL(for: v2))],
            images: [image(p1.id)],
            audioTitles: [a1.id: "  Idea one  ", a2.id: "   "],
            videoTitles: [v2.id: "Riff"],
            thumbnail: p1.id)

        XCTAssertEqual(payload.attachments.count, 5)
        XCTAssertEqual(Set(payload.sourceIDs), [a1.id, a2.id, v1.id, v2.id, p1.id])
        XCTAssertEqual(payload.sourceIDs.count, 5, "no duplicates")
        // Original ids are kept, so privacy keyed on the staged id carries over and consumption can match.
        XCTAssertEqual(Set(payload.attachments.map(\.id)), Set(payload.sourceIDs))
        // Video bytes are the staged file's bytes, materialised once, with the REAL format (C-85).
        let video1 = payload.attachments.first { $0.id == v1.id }!
        let video2 = payload.attachments.first { $0.id == v2.id }!
        XCTAssertEqual(video1.data, Data("V1-MOV".utf8))
        XCTAssertEqual(video1.sourceFormat, .mov)
        XCTAssertEqual(video2.sourceFormat, .mp4, "a trimmed MP4 is never declared MOV")
        XCTAssertEqual(AttachmentImportPolicy.fileExtension(for: video2), "mp4")
        // Titles: trimmed, blank dropped, only for carried ids.
        XCTAssertEqual(payload.audioTitles, [a1.id: "Idea one"])
        XCTAssertEqual(payload.videoTitles, [v2.id: "Riff"])
        XCTAssertEqual(payload.thumbnailID, p1.id)
        XCTAssertEqual(payload.threadLabel, "Études")
    }

    func testThumbnailMustBeACarriedPhoto() async throws {
        let a1 = try await stage("A1", ext: "m4a", kind: .audio)
        let payload = try make(audio: [audio(a1.id)], thumbnail: UUID())
        XCTAssertNil(payload.thumbnailID)
    }

    func testAnUnstagedClipFailsTheWholeHandoffVisibly() async throws {
        let a1 = try await stage("A1", ext: "m4a", kind: .audio)
        let orphan = UUID()   // in memory, no ref: its staging failed or has not landed
        XCTAssertThrowsError(try make(audio: [audio(a1.id), audio(orphan)])) { error in
            XCTAssertEqual(error as? TimerThoughtHandoffError, .notStaged(kind: .audio))
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription, "the member sees why")
        }
        // The staged original is untouched by a failed hand-off.
        XCTAssertNotNil(StagingStore.ref(withId: a1.id))
    }

    func testAnUnreadableVideoFailsRatherThanBeingDropped() async throws {
        let v1 = try await stage("V1", ext: "mov", kind: .video)
        struct Boom: Error {}
        XCTAssertThrowsError(try make(videos: [TimerStagedVideo(id: v1.id, fileURL: StagingStore.absoluteURL(for: v1))],
                                      readVideo: { _ in throw Boom() })) { error in
            XCTAssertEqual(error as? TimerThoughtHandoffError, .unreadable(kind: .video))
        }
        XCTAssertNotNil(StagingStore.ref(withId: v1.id))
        XCTAssertTrue(fm.fileExists(atPath: StagingStore.absoluteURL(for: v1).path))
    }

    func testPendingStagingBlocksTheHandoff() async throws {
        let a1 = try await stage("A1", ext: "m4a", kind: .audio)
        XCTAssertThrowsError(try make(audio: [audio(a1.id)], pending: 1)) { error in
            XCTAssertEqual(error as? TimerThoughtHandoffError, .stagingInProgress)
        }
        XCTAssertThrowsError(try make()) { error in
            XCTAssertEqual(error as? TimerThoughtHandoffError, .nothingToSave)
        }
    }

    func testAWrongKindRefIsNotStaged() async throws {
        // An id staged as audio cannot be handed off as a photo.
        let a1 = try await stage("A1", ext: "m4a", kind: .audio)
        XCTAssertThrowsError(try make(images: [image(a1.id)])) { error in
            XCTAssertEqual(error as? TimerThoughtHandoffError, .notStaged(kind: .image))
        }
    }

    // MARK: - Consumption: exactly the committed source ids, repeatable

    func testOnlyCommittedSourceIDsStillStagedAreConsumed() {
        let kept = UUID(), saved = UUID(), removedInEditor = UUID(), editorImport = UUID(), gone = UUID()
        let committed = [saved, editorImport, gone, saved]          // the editor's list: includes its own import, a duplicate, and an id already consumed
        let sources = [kept, saved, removedInEditor, gone]          // the payload
        let stillStaged: Set<UUID> = [kept, saved, removedInEditor] // the timer now
        XCTAssertEqual(TimerThoughtHandoffBuilder.idsToConsume(committed: committed, sourceIDs: sources, stillStaged: stillStaged), [saved])
        XCTAssertEqual(TimerThoughtHandoffBuilder.idsToConsume(committed: committed, sourceIDs: sources, stillStaged: [kept, removedInEditor]), [],
                       "a second application consumes nothing")
        XCTAssertEqual(TimerThoughtHandoffBuilder.idsToConsume(committed: [], sourceIDs: sources, stillStaged: stillStaged), [],
                       "nothing committed, nothing consumed — never assume everything passed in was saved")
    }

    func testConsumingRemovesThoseRefsAndFilesAndNoOthers() async throws {
        let a1 = try await stage("A1", ext: "m4a", kind: .audio)
        let a2 = try await stage("A2", ext: "m4a", kind: .audio)
        let v1 = try await stage("V1", ext: "mov", kind: .video)
        let ids = TimerThoughtHandoffBuilder.idsToConsume(committed: [a1.id, v1.id], sourceIDs: [a1.id, a2.id, v1.id],
                                                          stillStaged: [a1.id, a2.id, v1.id])
        StagingStore.removeMany(ids: ids)
        XCTAssertNil(StagingStore.ref(withId: a1.id))
        XCTAssertNil(StagingStore.ref(withId: v1.id))
        XCTAssertFalse(fm.fileExists(atPath: StagingStore.absoluteURL(for: a1).path))
        XCTAssertFalse(fm.fileExists(atPath: StagingStore.absoluteURL(for: v1).path))
        XCTAssertNotNil(StagingStore.ref(withId: a2.id), "the left-out clip stays staged")
        XCTAssertTrue(fm.fileExists(atPath: StagingStore.absoluteURL(for: a2).path))
        // Repeat: safe.
        StagingStore.removeMany(ids: ids)
        XCTAssertNotNil(StagingStore.ref(withId: a2.id))
        // A second thought from the remainder does not bring the first's clips back.
        let second = try make(audio: [audio(a2.id)])
        XCTAssertEqual(second.sourceIDs, [a2.id])
    }

    // MARK: - The editor's final-id title migration

    private func attempt(_ pairs: [(UUID, UUID)]) -> AttachmentCommitAttempt {
        AttachmentCommitAttempt(stagedToFinalID: Dictionary(uniqueKeysWithValues: pairs),
                                stagedToFinalURL: [:],
                                committedStagedIDs: pairs.map(\.0),
                                fileRollbacks: [])
    }

    func testFinalIDTitlesAreWrittenForCommittedAudioAndVideoOnly() {
        let audioStaged = UUID(), audioFinal = UUID()
        let videoStaged = UUID(), videoFinal = UUID()
        let leftOutStaged = UUID()
        let imageStaged = UUID(), imageFinal = UUID()
        StagedTitleMigration.seedStagedTitles(audio: [audioStaged: "Idea", leftOutStaged: "Not saved"],
                                              video: [videoStaged: "  Riff  "], defaults: defaults)
        let kinds: [UUID: AttachmentKind] = [audioStaged: .audio, videoStaged: .video, imageStaged: .image]
        StagedTitleMigration.writeFinalTitles(for: attempt([(audioStaged, audioFinal), (videoStaged, videoFinal), (imageStaged, imageFinal)]),
                                              kind: { kinds[$0] }, defaults: defaults)
        let audioTitles = defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyAudioTitlesKey) as? [String: String] ?? [:]
        let videoTitles = defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyVideoTitlesKey) as? [String: String] ?? [:]
        XCTAssertEqual(audioTitles, [audioFinal.uuidString: "Idea"], "the committed clip, by FINAL id; the left-out clip is not written")
        XCTAssertEqual(videoTitles, [videoFinal.uuidString: "Riff"], "trimmed, by final id")
    }

    func testFinalIDTitleSurvivesAReopenRead() {
        let staged = UUID(), final = UUID()
        StagedTitleMigration.seedStagedTitles(audio: [staged: "Idea"], video: [:], defaults: defaults)
        StagedTitleMigration.writeFinalTitles(for: attempt([(staged, final)]), kind: { _ in .audio }, defaults: defaults)
        // What the detail views read after reopening: the shared store keyed by the attachment id.
        let read = (defaults.dictionary(forKey: "persistedAudioTitles_v1") as? [String: String])?[final.uuidString]
        XCTAssertEqual(read, "Idea")
    }

    // MARK: - Thumbnail: applied against the final id

    func testChosenThumbnailIsTranslatedThroughTheAttemptMap() {
        let staged = UUID(), final = UUID(), existing = UUID()
        let a = attempt([(staged, final)])
        XCTAssertEqual(TimerThoughtHandoffBuilder.finalThumbnailID(chosen: staged, attempt: a), final, "a newly staged photo maps to its row")
        XCTAssertEqual(TimerThoughtHandoffBuilder.finalThumbnailID(chosen: existing, attempt: a), existing, "an already persisted attachment keeps its id")
        XCTAssertNil(TimerThoughtHandoffBuilder.finalThumbnailID(chosen: nil, attempt: a))
    }

    // MARK: - C-85 — a trim's container follows the bytes

    func testTrimOutputFormatIsAdoptedForTheSameKindOnly() {
        let mp4 = URL(fileURLWithPath: "/tmp/x.mp4"), mov = URL(fileURLWithPath: "/tmp/x.mov"), m4a = URL(fileURLWithPath: "/tmp/x.m4a")
        XCTAssertEqual(AttachmentImportPolicy.format(forTrimOutput: mp4, kind: .video, previous: nil), .mp4)
        XCTAssertEqual(AttachmentImportPolicy.format(forTrimOutput: mp4, kind: .video, previous: .mov), .mp4, "a MOV original trimmed to MP4 is MP4")
        XCTAssertEqual(AttachmentImportPolicy.format(forTrimOutput: mov, kind: .video, previous: .mp4), .mov)
        XCTAssertEqual(AttachmentImportPolicy.format(forTrimOutput: m4a, kind: .video, previous: .mov), .mov, "a wrong-kind URL changes nothing")
        XCTAssertEqual(AttachmentImportPolicy.format(forTrimOutput: m4a, kind: .audio, previous: nil), .m4a)
        let trimmed = StagedAttachment(id: UUID(), data: Data(), kind: .video,
                                       sourceFormat: AttachmentImportPolicy.format(forTrimOutput: mp4, kind: .video, previous: nil))
        XCTAssertEqual(AttachmentImportPolicy.fileExtension(for: trimmed), "mp4", "persisted and declared as MP4, not MOV")
    }

    // MARK: - Wiring the views hold (code only)

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("MOTIVO")
    }

    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func block(after marker: String, in s: String) -> String? {
        guard let r = s.range(of: marker), let open = s[r.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = open
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 } else if s[i] == "}" { depth -= 1; if depth == 0 { return String(s[open...i]) } }
            i = s.index(after: i)
        }
        return nil
    }

    func testTheEditorDeliversCommittedIDsInsideFinalisationNotAfterTheSharingGate() {
        let aesv = code("AddEditSessionView.swift")
        guard let finalise = block(after: "finalise: { attempt in", in: aesv) else { return XCTFail("finalise step not found") }
        XCTAssertTrue(finalise.contains("finaliseStagedAttachmentCommit(attempt)"))
        XCTAssertTrue(finalise.contains("didCommitLocally = true"), "a second local save is blocked once the commit has succeeded")
        XCTAssertTrue(finalise.contains("onLocalCommit(attempt.committedStagedIDs.filter { prefilledStagedIDs.contains($0) })"),
                      "exactly the committed staged ids that came from the timer")
        XCTAssertTrue(block(after: "func save(", in: aesv)?.contains("if didCommitLocally { return }") ?? false)
        XCTAssertTrue(aesv.contains("|| didCommitLocally)"), "the Save button follows")
        XCTAssertTrue(block(after: "private func seedPrefilledAttachmentsIfNeeded(", in: aesv)?.contains("guard !didSeedPrefill") ?? false,
                      "seeded once per presentation")
        XCTAssertTrue(aesv.contains("func removalMenuTitle(for att: StagedAttachment) -> String"), "Remove from thought")
        // The editor's own existing finish callback is untouched.
        XCTAssertTrue(aesv.contains("sharingSaveGate.handle(sharingSaveResult, stoppingSharing: !isPublic, finalise: finishEditor)"))
    }

    func testTheEditorMigratesTitlesAndMapsTheThumbnailAtFinalisation() {
        let s = code("AddEditSessionView+Attachments.swift")
        guard let b = block(after: "func finaliseStagedAttachmentCommit(", in: s) else { return XCTFail("not found") }
        XCTAssertTrue(b.contains("StagedTitleMigration.writeFinalTitles(for: attempt, kind: { stagedByID[$0]?.kind })"))
        XCTAssertTrue(block(after: "func commitStagedAttachments(", in: s)?
            .contains("TimerThoughtHandoffBuilder.finalThumbnailID(chosen: chosenThumbID, attempt: attempt)") ?? false)
        XCTAssertEqual(s.components(separatedBy: "AttachmentImportPolicy.format(forTrimOutput:").count - 1, 2,
                       "both trim constructors (replace, save-as-new) carry the real format")
        XCTAssertFalse(s.contains("StagedAttachment(id: old.id, data: data, kind: old.kind)"), "the format-dropping constructor is gone")
        XCTAssertFalse(s.contains("StagedAttachment(id: newID, data: data, kind: kind)"), "and so is save-as-new's")
    }

    func testTheTimerHandsOffOnePayloadAndConsumesThroughOneRemoval() {
        let ptv = code("PracticeTimerView.swift")
        let st = code("PracticeTimerView+SaveThought.swift")
        let handoff = code("TimerThoughtHandoff.swift")
        XCTAssertTrue(handoff.contains(".sheet(item: $handoff)"), "one payload per presentation, released on dismiss")
        XCTAssertTrue(ptv.contains("TimerThoughtHandoffPresentation(handoff: $thoughtHandoff,"))
        XCTAssertTrue(ptv.contains("if showSaveThoughtRow {"), "the contextual row")
        XCTAssertTrue(block(after: "var isSaveThoughtAvailable: Bool", in: st)?.contains("!hasStartedSinceReset && hasAttachments") ?? false,
                      "the shared started-since-reset check gates it")
        XCTAssertTrue(block(after: "func beginSaveThought(", in: st)?.contains("guard isSaveThoughtAvailable else { return }") ?? false,
                      "rechecked at the tap")
        XCTAssertTrue(block(after: "func beginSaveThought(", in: st)?.contains("commitAudioTitleEditingBuffers()") ?? false,
                      "pending title edits are flushed first")
        guard let consume = block(after: "func consumeStagedAttachmentsSavedAsThought(", in: st) else { return XCTFail("not found") }
        XCTAssertEqual(consume.components(separatedBy: "StagingStore.removeMany(ids: ids)").count - 1, 1, "exactly these ids")
        for forbidden in ["reset()", "resetUIOnly()", "discardSessionCompletely()", "clearAllStagingStoreRefs()",
                          "clearPersistedStagedAttachments()", "resetTasksForNewSessionContext()", "clearPersistedTasks()",
                          "StagingStore.remove(", "StagingStore.deleteFiles(", "AttachmentStore."] {
            XCTAssertFalse(consume.contains(forbidden), "consumption must never reset, discard or touch permanent media — found \(forbidden)")
        }
        XCTAssertTrue(consume.contains("TimerThoughtHandoffBuilder.idsToConsume(committed: committed, sourceIDs: sourceIDs, stillStaged: stillStaged)"))
        XCTAssertTrue(consume.contains("persistStagedAttachments()"), "persisted id arrays follow")
        // Post-record details is unchanged: its hand-off still drops unreadable video silently, by design.
        XCTAssertTrue(block(after: "func makeReviewPrefill(", in: ptv)?.contains("compactMap") ?? false)
        // The "+" menu drops its thought entry while Save thought is showing.
        XCTAssertTrue(ptv.contains("if !hasAttachments {\n                        Button {\n                            showAddEntryActions = false\n                            showThoughtEditorSheet = true"))
    }

    // MARK: - A thought made from the timer returns to the timer

    func testThoughtsMadeFromTheTimerReturnToTheTimerWithAViewNotice() {
        let ptv = code("PracticeTimerView.swift")
        let st = code("PracticeTimerView+SaveThought.swift")
        let aesv = code("AddEditSessionView.swift")
        XCTAssertFalse(block(after: "func thoughtHandoffEditor(", in: st)?.contains("appRoute.route") ?? true, "Save Thought no longer navigates away")
        XCTAssertFalse(block(after: "private var thoughtEditorSheet", in: ptv)?.contains("appRoute.route") ?? true, "nor does Add thought")
        XCTAssertTrue(st.contains("onSavedEntry: { objectID in savedThoughtNotice = SavedThoughtNotice(objectID: objectID) }"))
        XCTAssertTrue(ptv.contains("onSavedEntry: { objectID in savedThoughtNotice = SavedThoughtNotice(objectID: objectID) }"))
        XCTAssertTrue(block(after: "let finishEditor: () -> Void = {", in: aesv)?.contains("onSavedEntry?(savedObjectID)") ?? false,
                      "the saved entry is named exactly once, with the existing finish")
        XCTAssertEqual(aesv.components(separatedBy: "appRoute.route = .content").count - 1, 0, "the editor itself never routes")
        // Other entry points keep their navigation: the manual session sheet still routes to the journal.
        XCTAssertTrue(block(after: ".sheet(isPresented: $showManualAddSheet)", in: ptv)?.contains("appRoute.route = .content") ?? false)
    }

    func testThoughtModeOrdersAttachmentsFirstOnlyWhenTheyCameIn() {
        let aesv = code("AddEditSessionView.swift")
        let stack = block(after: "private var contentStack: some View", in: aesv) ?? ""
        let order = ["if arrivedWithAttachments && !stagedAttachments.isEmpty {", "threadRow", "startTimeRow", "notesCard", "visibilityRow",
                     "if !arrivedWithAttachments && !stagedAttachments.isEmpty {", "addAttachmentControls"]
        var cursor = stack.startIndex
        for token in order {
            guard let r = stack.range(of: token, range: cursor..<stack.endIndex) else { return XCTFail("\(token) out of order or missing") }
            cursor = r.upperBound
        }
        XCTAssertTrue(aesv.contains("private var arrivedWithAttachments: Bool { !prefillAttachments.isEmpty }"), "fixed for the presentation; removing all media does not reflow")
        XCTAssertTrue(block(after: "ToolbarItem(placement: .confirmationAction) {", in: aesv)?.contains("Button(\"Save Thought\")") ?? false, "one save action, in the toolbar")
        XCTAssertTrue(block(after: "ToolbarItem(placement: .confirmationAction) {", in: aesv)?.contains(".opacity(saveEnabled ? 1.0 : 0.6)") ?? false, "disabled is visibly quieter")
        XCTAssertEqual(stack.components(separatedBy: "bottomSaveButton").count - 1, 1, "the bottom save button is sessions only")
    }

    // MARK: - Audio-only thoughts are named by their recording

    func testAudioSummaryNamingAndFormatting() {
        // The timer's generated name is not a heading; a member-given title is.
        XCTAssertTrue(ThoughtMediaSummaryBuilder.isGeneratedName("2026oct11_15:18"))
        XCTAssertTrue(ThoughtMediaSummaryBuilder.isGeneratedName("2026JAN05_09:07"))
        XCTAssertFalse(ThoughtMediaSummaryBuilder.isGeneratedName("Bridge idea"))
        XCTAssertFalse(ThoughtMediaSummaryBuilder.isGeneratedName("2026oct11_15:18_2"), "a suffixed save-as-new name is a member-kept name")
        XCTAssertFalse(ThoughtMediaSummaryBuilder.isGeneratedName("2026xyz11_15:18"))
        XCTAssertFalse(code("ThoughtMediaSummary.swift").contains("fallbackTitle"), "no fallback title text; the spoken kind is for VoiceOver only")
        XCTAssertFalse(code("ThoughtMediaSummary.swift").contains("durationText"), "duration belongs to the player, not the rows")
        XCTAssertNil(ThoughtMediaSummary(title: "x", kind: .audio, count: 1, uniformKind: true).countText)
        XCTAssertEqual(ThoughtMediaSummary(title: "x", kind: .audio, count: 3, uniformKind: true).countText, "3 recordings")
        XCTAssertEqual(ThoughtMediaSummary(title: "x", kind: .video, count: 2, uniformKind: true).countText, "2 videos")
        XCTAssertEqual(ThoughtMediaSummary(title: "x", kind: .image, count: 4, uniformKind: true).countText, "4 photos")
        XCTAssertEqual(ThoughtMediaSummary(title: "x", kind: .video, count: 3, uniformKind: false).countText, "3 attachments")
        XCTAssertEqual(ThoughtMediaSummary(title: nil, kind: .video, count: 1, uniformKind: true).systemImage, "video")
    }

    func testPersistedTitleWinsOverTheStem() {
        let id = UUID()
        let suite = UserDefaults(suiteName: "SaveThoughtHandoffTests.titles")!
        suite.removePersistentDomain(forName: "SaveThoughtHandoffTests.titles")
        AttachmentTitlePersistenceKeys.writeLocalTitle("Bridge idea", kind: .audio, attachmentID: id, defaults: suite)
        XCTAssertEqual(LocalAttachmentTitles.title(for: id, kind: .audio, defaults: suite), "Bridge idea")
        XCTAssertNil(LocalAttachmentTitles.title(for: UUID(), kind: .audio, defaults: suite))
        suite.removePersistentDomain(forName: "SaveThoughtHandoffTests.titles")
    }

    func testBothJournalThoughtRowsUseTheSummaryWhenThereIsNoHeading() {
        let month = code("ContentViewMonthThoughtRow.swift")
        let week = code("ContentViewThoughtRow.swift")
        XCTAssertTrue(month.contains("ThoughtMediaSummaryBuilder.summary(for: session)"))
        XCTAssertTrue(week.contains("ThoughtMediaSummaryBuilder.summary(for: session)?.title"), "the week card takes only a member-given title")
        XCTAssertTrue(month.contains("if showsKindIndicator, let audioSummary {"), "the month card's one indicator sits on the date line, only without a heading")
        XCTAssertFalse(week.contains("systemImage"), "no extra indicator row in the week card")
        XCTAssertTrue(block(after: "private var audioSummary: ThoughtMediaSummary?", in: month)?.contains("writtenHeader == nil") ?? false,
                      "a written heading always wins")
    }

    func testEveryStagingWriteIsTrackedAsPending() {
        let ptv = code("PracticeTimerView.swift")
        for fn in ["func stageAudioURL(", "func stageVideoURL(", "func stageImage(", "func handleTrimSaveAsNew(", "func handleTrimReplaceOriginal("] {
            guard let b = block(after: fn, in: ptv) else { XCTFail("\(fn) not found"); continue }
            XCTAssertTrue(b.contains("pendingStagingOps.insert("), "\(fn) must register its staging")
            XCTAssertTrue(b.contains("pendingStagingOps.remove("), "\(fn) must release it on success or failure")
        }
    }
}
