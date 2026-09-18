//
//  P6I01SaveOrderingTests.swift
//  MOTIVOTests
//
//  PHASE 6 · BATCH 1 · P6-I-01 — THE CALLER SEQUENCE.
//
//  The behavioural suite drives `commitStagedAttachments` and
//  `finaliseStagedAttachmentCommit` directly. What it cannot reach is the
//  ORDER the two editors call them in relative to `viewContext.save()`, because
//  that lives inside SwiftUI view methods that depend on environment objects,
//  StoreKit-backed app mode and the publish pipeline.
//
//  That order is the whole fix, so it is pinned here structurally — the same
//  technique as `ConsentAtBothPublishSitesTests` and `SharedOnlyUploadTests`.
//
//  **CODE ONLY — COMMENT LINES ARE STRIPPED FIRST** (`U5c-34`: a file that
//  explains a rule in prose must not be able to satisfy an assertion about the
//  rule by mentioning it).
//

import XCTest
@testable import Etudes

final class P6I01SaveOrderingTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
    }

    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private let editors = ["AddEditSessionView.swift", "PostRecordDetailsView.swift"]
    private let commits = ["AddEditSessionView+Attachments.swift", "PostRecordDetailsView+Attachments.swift"]

    // MARK: - Phase A cannot report success

    func testNeitherCommitPathSwallowsAFailure() {
        for file in commits {
            let s = code(file)
            XCTAssertTrue(s.contains("throws -> AttachmentCommitAttempt"),
                          "\(file): the commit must be able to report failure to its caller")
            XCTAssertFalse(commitBody(file).contains("break"),
                           "\(file): the swallowing `break` must be gone from the commit")
        }
        // The throw itself now lives in the one shared commit.
        let service = code("AttachmentCommitService.swift")
        XCTAssertTrue(service.contains("throw AttachmentCommitFailure("),
                      "the shared commit must rethrow a typed failure")
        for file in commits {
            let s = code(file)
        }
    }

    /// Phase A must not consume staged state. These are the exact statements that
    /// used to run whether or not the loop had failed.
    func testPhaseADoesNotConsumeStagedState() {
        for file in commits {
            let body = commitBody(file)
            XCTAssertFalse(body.isEmpty, "\(file): commit body not found")
            let forbidden = ["stagedAttachments.removeAll()",
                             "UserDefaults.standard.removeObject(forKey: namesKey)",
                             "UserDefaults.standard.removeObject(forKey: \"stagedAudioNames_temp\")",
                             "PDFSelectedPagesStore.migratePages"]
            for forbidden in forbidden {
                XCTAssertFalse(body.contains(forbidden),
                               "\(file): `\(forbidden)` must not run before the save")
            }
        }
    }

    /// The commit body, from its signature to the next method.
    private func commitBody(_ file: String) -> String {
        let s = code(file)
        let sig = "func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) throws -> AttachmentCommitAttempt {"
        guard let start = s.range(of: sig) else { return "" }
        let end = s.range(of: "\n    func ", range: start.upperBound..<s.endIndex)?.lowerBound ?? s.endIndex
        return String(s[start.upperBound..<end])
    }

    // MARK: - Both editors route through the ONE transaction
    //
    // The ordering rules themselves are executed in `P6I01TransactionTests`.
    // What remains structural is that each editor actually goes through that
    // transaction and supplies the right steps — a test cannot observe which
    // function a SwiftUI view method calls.

    func testBothEditorsRouteThroughTheSharedTransaction() {
        for file in editors {
            let s = code(file)
            XCTAssertTrue(s.contains("AttachmentCommitTransaction.run(.init("),
                          "\(file): the save must go through the shared transaction")
            // P6-I-03 / C1 re-expressed, not relaxed: the commit step still TRIES
            // this editor's own commit and returns its attempt unchanged; it now
            // also hands that same attempt to the save step, which prepares the
            // sharing choice from it before `save()`.
            XCTAssertTrue(s.contains("let attempt = try commitStagedAttachments(to: s, ctx: viewContext)")
                          && s.contains("attemptForChoice = attempt\n                return attempt"),
                          "\(file): the commit step must be this editor's own commit")
            XCTAssertTrue(s.contains("finaliseStagedAttachmentCommit(attempt)"),
                          "\(file): the finalise step must be this editor's own finalise")
            XCTAssertTrue(s.contains("case .commitFailed(let error):") && s.contains("case .saveFailed(let error):"),
                          "\(file): both failure outcomes must be handled")
            XCTAssertEqual(s.components(separatedBy: "AttachmentCommitTransaction.run(.init(").count - 1, 1,
                           "\(file): exactly one transaction, so no path can bypass the ordering")
        }
    }

    /// `finalise` is only reachable from inside the transaction's finalise step,
    /// so no failure path can run it.
    func testFinaliseIsOnlyReachableFromTheFinaliseStep() throws {
        for file in editors {
            let s = code(file)
            let finalise = try XCTUnwrap(s.range(of: "finaliseStagedAttachmentCommit(attempt)"), "\(file)")
            let runStart = try XCTUnwrap(s.range(of: "AttachmentCommitTransaction.run(.init("), "\(file)")
            let switchStart = try XCTUnwrap(s.range(of: "switch outcome {", range: runStart.upperBound..<s.endIndex), "\(file)")
            XCTAssertTrue(finalise.lowerBound > runStart.upperBound && finalise.upperBound < switchStart.lowerBound,
                          "\(file): finalise must live inside the transaction's steps, not on any other path")
        }
    }

    /// Privacy lands on the final ids before the publish reads them.
    func testBothEditorsFinaliseBeforeTheyPublish() throws {
        for file in editors {
            let s = code(file)
            let finalise = try XCTUnwrap(s.range(of: "finaliseStagedAttachmentCommit(attempt)"), "\(file)")
            // P6-I-03 / C1: the enqueue is now `publishPrepared`; the payload it
            // carries holds ids only, and attachment privacy is read at flush.
            let publish = try XCTUnwrap(s.range(of: "PublishService.shared.publishPrepared("), "\(file)")
            XCTAssertTrue(finalise.upperBound < publish.lowerBound,
                          "\(file): privacy must be migrated onto the final ids before the publish reads them")
        }
    }

    // MARK: - Staging removal is scoped to what was committed

    func testPRDRemovesOnlyTheCommittedStagedIDs() {
        let s = code("PostRecordDetailsView.swift")
        XCTAssertTrue(s.contains("let consumedIDs: [UUID] = attempt.committedStagedIDs"),
                      "the staging removal must name the committed ids, not every staged id")
        XCTAssertFalse(s.contains("let consumedIDs: [UUID] = stagedAttachments.map { $0.id }"),
                       "removing every staged id is what destroyed the originals after a silent failure")
    }

    // MARK: - The heuristics the review removed must not come back

    func testNeitherEditorUsesTemporaryIDAsProvenance() {
        for file in editors {
            let s = code(file)
            XCTAssertFalse(s.contains("a.objectID.isTemporaryID, let path = a.value(forKey: \"fileURL\")"),
                           "\(file): a temporary object id is not provenance — it can miss this attempt's "
                           + "files and delete another attempt's")
        }
    }

    /// Neither editor may discard by deleting objects or rolling the whole
    /// context back; both undo their own attempt group.
    func testBothEditorsDiscardByUndoingTheirOwnAttempt() {
        for file in editors {
            let s = code(file)
            XCTAssertTrue(s.contains("AttemptScopedUndo.undoAndRelease(undoTicket)"),
                          "\(file): the discard must undo this attempt's group")
            XCTAssertFalse(s.contains("viewContext.rollback()"),
                           "\(file): a blanket context rollback would discard unrelated pending changes")
            XCTAssertFalse(s.contains("viewContext.delete(s)"),
                           "\(file): deleting the session is not attempt-scoped — in edit mode it is the member's own")
            XCTAssertTrue(s.contains("AttemptScopedUndo.release(undoTicket)"),
                          "\(file): the success path must release the group exactly once")
        }
    }

    // MARK: - Deferred physical deletion of removed attachments

    func testAESVDefersRemovedAttachmentFileDeletionUntilAfterTheSave() throws {
        let s = code("AddEditSessionView.swift")
        XCTAssertTrue(s.contains("var pendingFileDeletions: [String] = []"),
                      "the paths must be collected rather than deleted before the save")
        let collect = try XCTUnwrap(s.range(of: "pendingFileDeletions.append(path)"))
        let run = try XCTUnwrap(s.range(of: "AttachmentCommitTransaction.run(.init("))
        let delete = try XCTUnwrap(s.range(of: "for path in pendingFileDeletions { AttachmentStore.removeIfExists(path: path) }"))
        XCTAssertTrue(collect.upperBound < run.lowerBound, "collection happens before the transaction")
        XCTAssertTrue(delete.lowerBound > run.lowerBound, "deletion happens inside the finalise step")
    }

    // MARK: - The attempt boundary, and the score retry defect

    /// The undo group must open BEFORE the first mutation of the save. A group
    /// opened later registers everything earlier OUTSIDE itself and cannot undo
    /// it — which is how a failed create could leave an empty session pending.
    func testBothEditorsOpenTheAttemptBoundaryBeforeTheirFirstMutation() throws {
        let firstMutation = [
            "PostRecordDetailsView.swift": "let s = Session(context: viewContext)",
            "AddEditSessionView.swift": "let s = session ?? Session(context: viewContext)"
        ]
        for (file, mutation) in firstMutation {
            let s = code(file)
            let open = try XCTUnwrap(s.range(of: "try AttemptScopedUndo.open(in: viewContext)"), "\(file): open")
            let first = try XCTUnwrap(s.range(of: mutation), "\(file): first mutation")
            XCTAssertTrue(open.upperBound < first.lowerBound,
                          "\(file): the attempt boundary must precede `\(mutation)`")
        }
    }

    /// The refusal path must abort before any mutation, not trap.
    func testBothEditorsAbortWhenTheAttemptBoundaryCannotBeOpened() {
        for file in editors {
            let s = code(file)
            XCTAssertTrue(s.contains("catch {") && s.contains("Nothing has been changed"),
                          "\(file): an unopenable boundary must abort with a recoverable message")
        }
    }

    /// The score retry defect: the map that says "this score is already attached"
    /// must be written in finalise, after the save — not during the attempt, where
    /// a failure would leave it claiming an attachment that was undone and make the
    /// retry skip recreating it.
    func testAESVDefersTheScoreAttachmentMapUntilFinalise() throws {
        let s = code("AddEditSessionView+Attachments.swift")
        let commitStart = try XCTUnwrap(s.range(of: "func commitScoreAttachments_AESV"))
        let commitEnd = try XCTUnwrap(s.range(of: "\n    func ", range: commitStart.upperBound..<s.endIndex))
        let commitBody = String(s[commitStart.upperBound..<commitEnd.lowerBound])
        XCTAssertFalse(commitBody.contains("existingScoreAttachmentIDsByScoreID_AESV[score.id] = finalID"),
                       "the score map must not be written during the attempt")
        XCTAssertFalse(commitBody.contains("AttachmentPrivacy.setPrivate"),
                       "score privacy must not be written during the attempt")
        XCTAssertTrue(commitBody.contains("pendingScoreFinalisations_AESV.append"),
                      "it must be recorded for finalise instead")

        let finaliseStart = try XCTUnwrap(s.range(of: "func finaliseStagedAttachmentCommit"))
        let finaliseBody = String(s[finaliseStart.upperBound...])
        XCTAssertTrue(finaliseBody.contains("existingScoreAttachmentIDsByScoreID_AESV[scoreID] = attachmentID"),
                      "and applied in finalise, once the save is durable")
    }

    // MARK: - Metadata the undo group cannot restore must be deferred
    //
    // `AttachmentPrivacy` and `PDFSelectedPagesStore` write the privacy map and
    // `UserDefaults`. An undo group restores Core Data and nothing else, so any
    // such write made DURING an attempt survives a failed save. Both editors must
    // therefore record them and apply them only in finalise.
    //
    // STRUCTURAL, and truthfully so: these sites are `View` methods reading
    // `@State`, which a test cannot configure (measured). The behavioural half is
    // covered for the parts that were extracted — see `P6I01CommitServiceTests`.

    func testNeitherEditorWritesUndoableMetadataDuringTheAttempt() throws {
        let sites = [
            ("PostRecordDetailsView.swift", "commitUsedScoreAttachments"),
            ("AddEditSessionView+Attachments.swift", "commitScoreAttachments_AESV")
        ]
        for (file, function) in sites {
            let s = code(file)
            let start = try XCTUnwrap(s.range(of: "func \(function)"), "\(file): \(function)")
            let end = s.range(of: "\n    func ", range: start.upperBound..<s.endIndex)?.lowerBound ?? s.endIndex
            let body = String(s[start.upperBound..<end])
            XCTAssertFalse(body.contains("AttachmentPrivacy.setPrivate"),
                           "\(file): \(function) must not write the privacy map during the attempt")
            XCTAssertFalse(body.contains("PDFSelectedPagesStore.setPages"),
                           "\(file): \(function) must not write page selections during the attempt")
            XCTAssertTrue(body.contains("pending"),
                          "\(file): \(function) must record them for finalise instead")
        }
    }

    /// The staged-thumbnail "implies included" write was made on the STAGED id
    /// before the throwing commit; a failed save left it applied.
    func testPRDDoesNotWriteStagedThumbnailPrivacyDuringTheAttempt() {
        let body = commitBody("PostRecordDetailsView+Attachments.swift")
        XCTAssertFalse(body.contains("setPrivate(id: tid"),
                       "the staged thumbnail privacy write must not happen during the attempt")
    }

    func testBothEditorsApplyDeferredMetadataOnlyInFinalise() throws {
        let sites = [
            ("PostRecordDetailsView+Attachments.swift", "pendingMetadataFinalisations"),
            ("AddEditSessionView+Attachments.swift", "pendingScoreFinalisations_AESV")
        ]
        for (file, store) in sites {
            let s = code(file)
            let finalise = try XCTUnwrap(s.range(of: "func finaliseStagedAttachmentCommit"), "\(file)")
            let body = String(s[finalise.upperBound...])
            XCTAssertTrue(body.contains("for ") && body.contains(store),
                          "\(file): finalise must apply \(store)")
            XCTAssertTrue(body.contains("AttachmentPrivacy.setPrivate") || body.contains("migratePrivacy"),
                          "\(file): and that is where the privacy write belongs")
        }
    }

    /// A failed attempt must drop the pending records rather than carry them into
    /// the next one.
    func testBothEditorsClearPendingMetadataOnDiscard() {
        let stores = [
            ("PostRecordDetailsView.swift", "pendingMetadataFinalisations.removeAll()"),
            ("AddEditSessionView.swift", "pendingScoreFinalisations_AESV.removeAll()")
        ]
        for (file, clear) in stores {
            let s = code(file)
            guard let discard = s.range(of: "discardAttempt: {"),
                  let end = s.range(of: "\n        ))", range: discard.upperBound..<s.endIndex) else {
                return XCTFail("\(file): discard step not found")
            }
            XCTAssertTrue(String(s[discard.upperBound..<end.lowerBound]).contains(clear),
                          "\(file): the discard must clear its pending metadata")
        }
    }
}
