//
//  C84SessionPreservationTests.swift
//  MOTIVOTests
//
//  C-84 — AN UNSAVED PRACTICE TIMER SESSION IS PRESERVED UNLESS THE MEMBER
//  EXPLICITLY, CONFIRMEDLY DISCARDS IT.
//
//  Whole-session staged data is removed only after a successful Save or an
//  explicit confirmed session discard. Removing one attachment is separate.
//  Dismissal without explicit destructive confirmation preserves the session.
//
//  Device-reproduced before the change: a relaunch after SIGKILL, a swipe-down
//  of the review sheet, and "Back to Timer" each lost a staged clip.
//
//  `PracticeTimerView` cannot be driven from XCTest (its state is SwiftUI
//  `@State`), so its policy is pinned structurally — CODE ONLY, comments
//  stripped (`U5c-34`). Everything that can run, runs: the discard summary and
//  the `StagingStore` operations the policy relies on.
//

import XCTest
@testable import Etudes

@MainActor
final class C84SessionPreservationTests: XCTestCase {

    // MARK: - The Reset card copy

    private func tail(_ p: String) -> String {
        " for your next attempt, or discard \(p) with the timer. Discarding permanently deletes \(p) and can’t be undone."
    }

    func testDiscardSummaryNamesExactlyWhatIsLost() {
        let all = SessionDiscardSummary(recordings: 2, videos: 1, photos: 3, hasTasks: true)
        XCTAssertTrue(all.needsConfirmation)
        XCTAssertEqual(all.message, "Keep 2 recordings, 1 video, 3 photos and your tasks" + tail("them"))
        XCTAssertEqual(SessionDiscardSummary(recordings: 1).message, "Keep 1 recording" + tail("it"))
        XCTAssertEqual(SessionDiscardSummary(photos: 1).message, "Keep 1 photo" + tail("it"))
        XCTAssertEqual(SessionDiscardSummary(videos: 2, photos: 1).message, "Keep 2 videos and 1 photo" + tail("them"))
        XCTAssertEqual(SessionDiscardSummary(hasTasks: true).message, "Keep your tasks" + tail("them"))
        XCTAssertEqual(SessionDiscardSummary.title, "Reset the timer?")
        XCTAssertEqual(SessionDiscardSummary.keepTitle, "Reset timer")
        XCTAssertEqual(SessionDiscardSummary.confirmTitle, "Reset and discard draft")
    }

    func testNothingToLoseNeedsNoConfirmation() {
        XCTAssertFalse(SessionDiscardSummary().needsConfirmation, "the timer value alone never asks")
        XCTAssertNil(SessionDiscardSummary().message)
        XCTAssertTrue(SessionDiscardSummary(photos: 1).needsConfirmation, "any staged media asks")
    }

    func testTaskContentIsMemberCreatedOnlyWhenTypedEditedOrTicked() {
        let preset = TaskLine(text: "Scales", isDone: false, type: .task)
        let auto = [preset.id: "Scales"]
        XCTAssertFalse(SessionDiscardSummary.memberTaskContent([preset], autoTexts: auto), "an untouched preset is not member content")
        XCTAssertFalse(SessionDiscardSummary.memberTaskContent([TaskLine(text: "   ", type: .task)], autoTexts: [:]), "a blank line is not content")
        XCTAssertTrue(SessionDiscardSummary.memberTaskContent([TaskLine(text: "Bach bars 1-8", type: .task)], autoTexts: [:]), "typed")
        XCTAssertTrue(SessionDiscardSummary.memberTaskContent([TaskLine(text: "Tempo 60", type: .context)], autoTexts: [:]), "typed context")
        var edited = preset; edited.text = "Scales in B"
        XCTAssertTrue(SessionDiscardSummary.memberTaskContent([edited], autoTexts: auto), "edited preset")
        var ticked = preset; ticked.isDone = true
        XCTAssertTrue(SessionDiscardSummary.memberTaskContent([ticked], autoTexts: auto), "ticked preset")
    }

    // MARK: - StagingStore behaviour the policy relies on (simulator store)

    private var refsBackup: Data?
    private var createdRefIDs: [UUID] = []
    private var createdPaths: [URL] = []
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
        for p in createdPaths { try? FileManager.default.removeItem(at: p) }
        if let refsBackup { try? refsBackup.write(to: refsURL, options: .atomic) }
        createdRefIDs = []; createdPaths = []
        try await super.tearDown()
    }

    private func tempFile(_ contents: String, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("c84-\(UUID().uuidString)").appendingPathExtension(ext)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func stage(_ contents: String, ext: String = "m4a", kind: StagedAttachmentRef.Kind = .audio,
                       id: UUID? = nil) async throws -> StagedAttachmentRef {
        let ref = try await StagingStore.saveNew(from: try tempFile(contents, ext: ext), kind: kind,
                                                 suggestedName: "c84-\(UUID().uuidString)", id: id)
        createdRefIDs.append(ref.id)
        return ref
    }

    func testCleanupRemovesEmptyFoldersAndDanglingRefsButKeepsUnreferencedMedia() async throws {
        let fm = FileManager.default
        let emptyDir = StagingStore.baseURL.appendingPathComponent("1999-01-01", isDirectory: true)
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        createdPaths.append(emptyDir)
        let orphanDir = StagingStore.baseURL.appendingPathComponent("1999-01-02", isDirectory: true)
        try fm.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        let orphan = orphanDir.appendingPathComponent("unreferenced.m4a")
        try Data("real recording, ref never written".utf8).write(to: orphan)
        createdPaths.append(orphanDir)

        let kept = try await stage("kept")
        let dangling = try await stage("dangling")
        try fm.removeItem(at: StagingStore.absoluteURL(for: dangling))

        StagingStore.cleanupAbandoned()

        XCTAssertFalse(fm.fileExists(atPath: emptyDir.path), "an empty folder is removed")
        XCTAssertNil(StagingStore.ref(withId: dangling.id), "a ref whose file is gone is removed")
        XCTAssertNotNil(StagingStore.ref(withId: kept.id), "a live ref is kept")
        XCTAssertTrue(fm.fileExists(atPath: StagingStore.absoluteURL(for: kept).path), "its file is kept")
        XCTAssertTrue(fm.fileExists(atPath: orphan.path),
                      "UNREFERENCED MEDIA IS KEPT — a death between file and ref must not become loss")
    }

    func testSaveNewHonoursTheCallersID() async throws {
        let wanted = UUID()
        let ref = try await stage("mine", id: wanted)
        XCTAssertEqual(ref.id, wanted, "the in-memory id must be the store id — no re-key window")
    }

    /// CONTROL — the atomic replace the trim path moves onto already fails safe.
    func testReplaceFailureLeavesTheOriginalIntact() async throws {
        let ref = try await stage("original")
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("c84-missing-\(UUID().uuidString).m4a")
        do {
            _ = try await StagingStore.replace(original: ref, with: missing)
            XCTFail("replacing from a missing source must throw")
        } catch {}
        let bytes = try Data(contentsOf: StagingStore.absoluteURL(for: ref))
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "original", "the original must survive a failed replace")
    }

    func testWritePosterRecordsAPosterOnTheRef() async throws {
        let ref = try await stage("video bytes", ext: "mov", kind: .video)
        XCTAssertNil(ref.posterPath)
        XCTAssertTrue(StagingStore.writePoster(for: ref.id, jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9])))
        let updated = try XCTUnwrap(StagingStore.ref(withId: ref.id))
        let path = try XCTUnwrap(updated.posterPath, "the ref must name its poster")
        XCTAssertEqual(try Data(contentsOf: StagingStore.absoluteURL(forRelative: path)), Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    // MARK: - The policy, structurally

    private let deleters = [
        "clearAllStagingStoreRefs(", "StagingStore.remove", "deleteFiles(",
        "clearPersistedTimer(", "clearPersistedStagedAttachments(", "clearPersistedTasks(",
        "purgeStagedTempFiles(", "resetUIOnly(",
        "stagedAudio.removeAll", "stagedVideos.removeAll", "stagedImages.removeAll",
    ]

    private func assertDeletesNothing(_ block: String?, _ what: String, extra: [String] = [],
                                      file: StaticString = #filePath, line: UInt = #line) {
        guard let block else { return XCTFail("\(what): not found", file: file, line: line) }
        let found = (deleters + extra).filter { block.contains($0) }
        XCTAssertTrue(found.isEmpty, "\(what) must preserve the session — found \(found)", file: file, line: line)
    }

    func testNewProcessRestoresAndDeletesNothing() {
        assertDeletesNothing(block(after: "if lastBootID != currentBootID {", in: ptv), "the new-process branch",
                             extra: ["forKey: sessionActiveKey", "currentSessionIDKey"])
    }

    func testTerminationDeletesNothing() {
        assertDeletesNothing(block(after: "func handleAppTerminationCleanup(", in: ptv), "termination cleanup")
    }

    func testReviewDismissalWithoutSaveDeletesNothing() {
        assertDeletesNothing(block(after: ".onChange(of: showReviewSheet)", in: ptv), "review dismissal")
    }

    func testBackToTimerDeletesNothing() {
        let s = code("PostRecordDetailsView.swift")
        XCTAssertEqual(s.components(separatedBy: "StagingStore.removeMany(").count - 1, 1,
                       "the review's only whole-session removal is the successful-Save consumption")
        XCTAssertTrue(block(after: "private func saveToCoreData(", in: s)?.contains("StagingStore.removeMany(ids: consumedIDs)") ?? false)
    }

    func testFailedSaveStaysInReview() {
        let s = code("PostRecordDetailsView.swift")
        // P6-I-02 Unit 2d-1: the save now reports failure as nil (success carries
        // the sharing-choice save result), so the property is unchanged.
        XCTAssertTrue(s.contains("private func saveToCoreData(visibility: Bool) -> SharingChoiceSaveResult?"), "the save must report failure")
        XCTAssertTrue(block(after: "private func commitSaveAndDismiss(", in: s)?
            .contains("guard let sharingSaveResult = saveToCoreData(visibility: visibility) else { return }") ?? false,
                      "a failed Save must not dismiss — dismissal lands in the discard path")
    }

    func testStaleDiscardFlagDeletesNothing() {
        assertDeletesNothing(block(after: "if UserDefaults.standard.bool(forKey: sessionDiscardedKey) {", in: ptv),
                             "the stale discard flag")
    }

    func testRestoreDoesNotLoadOrDecodeVideo() {
        XCTAssertTrue(ptv.contains("@State var stagedVideos: [TimerStagedVideo]"), "staged video is held by file")
        XCTAssertTrue(code("AttachmentsCard.swift").contains("@Binding var stagedVideos: [TimerStagedVideo]"))
        for fn in ["func hydrateTimerFromStorage(", "func mirrorFromStagingStore("] {
            guard let b = block(after: fn, in: ptv) else { XCTFail("\(fn) not found"); continue }
            XCTAssertFalse(b.contains("generateVideoThumbnail("), "\(fn) must not decode video")
            XCTAssertFalse(b.contains("AVAudioPlayer("), "\(fn) must not probe audio")
            XCTAssertFalse(b.contains("kind: .video)"), "\(fn) must not build a byte-backed video")
            XCTAssertTrue(b.contains("TimerStagedVideo("), "\(fn) builds file-backed videos")
        }
    }

    func testTrimSaveAsNewStagesTheClip() {
        XCTAssertTrue(block(after: "func handleTrimSaveAsNew(", in: ptv)?.contains("StagingStore.saveNew(") ?? false,
                      "a saved-as-new clip must be staged, or hydration drops it")
    }

    func testTrimReplaceIsAtomic() {
        guard let b = block(after: "func handleTrimReplaceOriginal(", in: ptv) else { return XCTFail("not found") }
        XCTAssertTrue(b.contains("StagingStore.replace("), "use the atomic replace")
        XCTAssertFalse(b.contains("removeItem(at: finalURL)"), "never delete the original before the new one is in place")
    }

    func testDiscardDraftConfirmsAndDiscardsCompletely() {
        // The whole-draft discard is reached ONLY through the Reset card, as its
        // destructive, named option — never from a second control on the timer row.
        XCTAssertTrue(block(after: "func requestResetTimer(", in: ptv)?.contains("currentDiscardSummary()") ?? false)
        XCTAssertTrue(ptv.contains("onResetDiscardingDraft: { discardSessionCompletely() }"))
        let card = code("TimerCard.swift")
        XCTAssertTrue(card.contains("Button(SessionDiscardSummary.confirmTitle, role: .destructive) { onResetDiscardingDraft() }"))
        XCTAssertTrue(card.contains("Button(SessionDiscardSummary.keepTitle) { onResetKeepingDraft() }"))
        XCTAssertFalse(ptv.contains("requestDiscardDraft("), "no separate discard entry point")
        guard let b = block(after: "func discardSessionCompletely(", in: ptv) else { return XCTFail("not found") }
        for needed in ["StagingStore.removeMany(", "clearAllStagingStoreRefs()", "reset()",
                       "stagedAudio.removeAll()", "stagedVideos.removeAll()", "stagedImages.removeAll()",
                       "resetTasksForNewSessionContext()", "set(true, forKey: sessionActiveKey)"] {
            XCTAssertTrue(b.contains(needed), "a confirmed discard must be complete — missing \(needed)")
        }
    }

    /// Reset timer is time only. It must never reach the whole-draft paths —
    /// not the discard, not `reset()`, not `resetUIOnly()` (activity and thread),
    /// not the task reset — and it must clear BOTH start dates and the timing
    /// identity, so reset time cannot come back through post-record details.
    func testResetTimerKeepsTheDraft() {
        XCTAssertTrue(ptv.contains("onResetTimer: { requestResetTimer() }"))
        guard let request = block(after: "func requestResetTimer(", in: ptv) else { return XCTFail("not found") }
        XCTAssertTrue(request.contains("if summary.hasAttachments {"), "asks only when attachments are staged, rechecked at the request")
        XCTAssertFalse(request.contains("trueElapsedSeconds()"), "the time alone never asks")
        XCTAssertTrue(ptv.contains("TimerResetAlert(isPresented: $showResetTimerConfirmation,"), "the card is the shared modifier")
        XCTAssertTrue(ptv.contains("onResetKeepingDraft: { resetTimerOnly() }"), "and its keep action is the timer-only reset")
        XCTAssertTrue(ptv.contains("resetRequiresConfirmation: hasAttachments"), "the card knows when Reset is immediate")
        XCTAssertEqual(TimerResetAlert.title, "Reset the timer?")
        XCTAssertTrue(SessionDiscardSummary(hasTasks: true).needsConfirmation)
        XCTAssertFalse(SessionDiscardSummary(hasTasks: true).hasAttachments, "tasks alone do not open the Reset card")
        XCTAssertTrue(SessionDiscardSummary(photos: 1).hasAttachments)
        guard let b = block(after: "func resetTimerOnly(", in: ptv) else { return XCTFail("not found") }
        for forbidden in ["reset()", "resetUIOnly()", "resetTasksForNewSessionContext()", "discardSessionCompletely()",
                          "StagingStore.", "clearAllStagingStoreRefs()", "clearPersistedStagedAttachments()",
                          "clearPersistedTasks()", "stagedAudio", "stagedVideos", "stagedImages",
                          "audioTitles", "videoTitles", "selectedThumbnailID", "taskLines", "provisionalThreadLabel",
                          "activity =", "activityDetail ="] {
            XCTAssertFalse(b.contains(forbidden), "Reset timer must keep the draft — found \(forbidden)")
        }
        for needed in ["accumulatedSeconds = 0", "startDate = nil", "finalizedDuration = 0", "finalizedStartDate = nil",
                       "reviewPrefill = []", "practiceStartedSinceReset = false", "clearTimingIdentity()", "persistTimerState()"] {
            XCTAssertTrue(b.contains(needed), "Reset timer must clear the time — missing \(needed)")
        }
        guard let identity = block(after: "func clearTimingIdentity(", in: ptv) else { return XCTFail("not found") }
        XCTAssertTrue(identity.contains("perSessionStartTimestampKey(for: sid)"), "the per-session start date goes")
        XCTAssertTrue(identity.contains("\"PracticeTimer.currentSessionStartTimestamp\""), "and the global fallback finish() reads")
        XCTAssertTrue(identity.contains("removeObject(forKey: currentSessionIDKey)"), "and the timing identity itself")
    }

    /// One shared "started since reset" check, and the timer card takes it rather
    /// than inferring it from the label (a pause under one second shows `00:00`).
    func testStartedSinceResetIsOneSharedCheck() {
        guard let check = block(after: "var hasStartedSinceReset: Bool", in: ptv) else { return XCTFail("not found") }
        XCTAssertTrue(check.contains("practiceStartedSinceReset"), "the persisted marker is part of it")
        XCTAssertTrue(block(after: "private var isIdleAddEntryAvailable: Bool", in: ptv)?.contains("!hasStartedSinceReset") ?? false)
        XCTAssertTrue(ptv.contains("hasStarted: hasStartedSinceReset,"), "the timer card is told")
        XCTAssertTrue(block(after: "func start(", in: ptv)?.contains("practiceStartedSinceReset = true") ?? false, "set after a successful start")
        XCTAssertTrue(block(after: "func hydrateTimerFromStorage(", in: ptv)?.contains("practiceStartedSinceReset = persistedPracticeStartMarkerExists()") ?? false, "reconciled on restore")
        let card = code("TimerCard.swift")
        XCTAssertTrue(card.contains("let hasStarted: Bool"))
        XCTAssertTrue(block(after: "private var isPaused: Bool", in: card)?.contains("!isRunning && hasStarted") ?? false,
                      "the transport mode uses the shared check, not the label")
        XCTAssertTrue(block(after: "private var showsElapsed: Bool", in: card)?.contains("elapsedLabel != \"00:00\"") ?? false,
                      "the label's own fade keeps its original timing")
    }

    /// Samuel, 2026-10-11: never an additional control on the timer row. Idle is
    /// "Start Timer" alone; running and paused carry one "Reset"; keep-or-discard
    /// lives in the Reset card.
    func testTimerRowHasNoSecondaryControl() {
        let s = code("TimerCard.swift")
        XCTAssertFalse(s.contains("Menu {"), "no ellipsis menu on the timer row, ever")
        XCTAssertFalse(s.contains("ellipsis"))
        guard let idle = block(after: "case .idle:", in: s) else { return XCTFail("not found") }
        XCTAssertTrue(idle.contains("\"Start Timer\""))
        XCTAssertFalse(idle.contains("\"Reset\""), "nothing has started, so there is no Reset")
        XCTAssertTrue(block(after: "case .running:", in: s)?.contains("title: \"Reset\"") ?? false, "running offers Reset")
        XCTAssertTrue(block(after: "case .paused:", in: s)?.contains("title: \"Reset\"") ?? false, "paused offers Reset")
        XCTAssertFalse(s.contains("\"Reset timer\""), "the button is labelled Reset; the card explains")
    }

    func testHandOffMaterialisesVideoOnce() {
        let s = code("PracticeTimerView+Sheets.swift")
        XCTAssertTrue(s.contains("prefillAttachments: reviewPrefill,"))
        XCTAssertFalse(s.contains("prefillAttachments: (stagedImages + stagedAudio + stagedVideos)"))
    }

    /// PracticeTimerView's 9: the post-Save `!isActive` block, the unreachable
    /// Quit (5), `discardSessionCompletely` (2) and the `clearAllStagingStoreRefs`
    /// helper body. **The prediction said 10 — a miss, recorded:** its "16 today"
    /// counted the helper's declaration line, which this rule excludes. The true
    /// baseline was 15, and 15 − 8 + 2 = 9. Verified site by site.
    func testWholeSessionDeletionSitesArePinned() {
        let expected: [String: Int] = [
            "PracticeTimerView.swift": 9, "PracticeTimerView+Sheets.swift": 1,
            "PracticeTimerView+AudioPlayback.swift": 1, "AttachmentsCard.swift": 2,
            "PostRecordDetailsView.swift": 1,
            // Save thought: the one consumption of exactly the committed ids,
            // after the thought's durable local save (SaveThoughtHandoffTests).
            "PracticeTimerView+SaveThought.swift": 1,
        ]
        let tokens = ["StagingStore.remove(", "StagingStore.removeMany(", "StagingStore.deleteFiles(", "clearAllStagingStoreRefs()"]
        for (file, want) in expected {
            let n = code(file).components(separatedBy: "\n")
                .filter { l in !l.contains("func clearAllStagingStoreRefs") && tokens.contains { l.contains($0) } }.count
            XCTAssertEqual(n, want, "\(file): whole-session deletion sites changed — review against the C-84 policy")
        }
    }

    // MARK: - Source helpers

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("MOTIVO")
    }
    private var ptv: String { code("PracticeTimerView.swift") }

    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The brace-matched block that follows `marker`.
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
