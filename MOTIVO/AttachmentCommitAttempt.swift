//
//  AttachmentCommitAttempt.swift
//  MOTIVO
//
//  PHASE 6 · BATCH 1 · P6-I-01 — A FAILED ATTACHMENT WRITE MUST NEVER BECOME A
//  SUCCESSFUL SAVE, AND MUST NEVER COST THE STAGED ORIGINAL.
//
//  Both editors used to catch a write/add failure, roll back, `break`, and then
//  RETURN NORMALLY. The caller could not see it, saved the session anyway, and
//  then deleted every staged original — `PostRecordDetailsView` passed
//  `stagedAttachments.map(\.id)` to `StagingStore.removeMany`, which is all
//  staged ids and not the committed ones. An attachment filesystem failure need
//  not make the much smaller Core Data save fail, so "no attachments" was a
//  representable, silent, lossy outcome. This affects Solo as well as Connected.
//
//  THE SHAPE OF THE FIX IS THREE PHASES WITH THE SAVE IN THE MIDDLE, and the
//  ordering is the whole point:
//
//    A. `commitStagedAttachments` — writes permanent media and creates the
//       Attachment objects. THROWS. Nothing outside Core Data and the newly
//       written files is touched, so a failure is fully reversible.
//    B. the caller saves the context. On failure it calls `rollBackFiles()` and
//       keeps every staged original and every staged metadata key.
//    C. `finaliseStagedAttachmentCommit` — ONLY after the save succeeds. This is
//       where staged→final migration and staging removal happen.
//
//  WHY PHASE C EXISTS AT ALL. `PDFSelectedPagesStore.migratePages` CLEARS the
//  staged page selection (`setPages(nil, for: stagedID)`), and the three
//  `*_temp` title dictionaries were removed unconditionally. Run inside the
//  loop, those destroy the retry's inputs for every attachment processed before
//  the failure — so a second attempt would silently produce different files
//  from the first. Deferring them is what makes retry faithful rather than
//  merely possible.
//
//  WHY THIS TYPE IS DELIBERATELY SMALL. The per-attachment finalisation still
//  lives in each editor, because `migratePrivacy_AESV` mutates the view's own
//  `privacyMap` cache; an escaping closure would capture a copy of the `View`
//  struct and that write would go nowhere. This type carries only what both
//  editors genuinely share: the identity map and the undo list.
//

import Foundation

/// Raised when the commit could not complete. Carries the underlying error so
/// the caller can show something specific, and so a diagnosis is not reduced to
/// a boolean.
struct AttachmentCommitFailure: LocalizedError {
    /// The staged attachment whose write or insert failed, when known.
    let stagedID: UUID?
    let underlying: Error

    var errorDescription: String? {
        "Your recording could not be saved to this session. Nothing has been removed — please try saving again."
    }

    /// Non-localised, for logs.
    var diagnosticDescription: String {
        "attachment commit failed (stagedID=\(stagedID?.uuidString ?? "nil")): \(underlying)"
    }
}

/// One commit attempt's reversible work.
///
/// `rollBackFiles()` removes exactly the permanent-media files this attempt
/// wrote and nothing else — never a staged original, never a file from an
/// earlier attempt, never one belonging to an attachment already saved. It is
/// idempotent, so a caller that rolls back and then hits a second failure
/// cannot double-delete.
struct AttachmentCommitAttempt {
    /// staged UUID → final Attachment UUID, for the attachments this attempt created.
    let stagedToFinalID: [UUID: UUID]
    /// staged UUID → final permanent-media URL, for the same set.
    let stagedToFinalURL: [UUID: URL]
    /// The staged ids this attempt committed, in commit order. `finalise` and the
    /// caller's staging removal must use THIS, never the full staged list.
    let committedStagedIDs: [UUID]

    private let fileRollbacks: [() -> Void]
    private let alreadyRolledBack: Box

    final class Box { var value = false }

    init(stagedToFinalID: [UUID: UUID],
         stagedToFinalURL: [UUID: URL],
         committedStagedIDs: [UUID],
         fileRollbacks: [() -> Void]) {
        self.stagedToFinalID = stagedToFinalID
        self.stagedToFinalURL = stagedToFinalURL
        self.committedStagedIDs = committedStagedIDs
        self.fileRollbacks = fileRollbacks
        self.alreadyRolledBack = Box()
    }

    static var empty: AttachmentCommitAttempt {
        AttachmentCommitAttempt(stagedToFinalID: [:], stagedToFinalURL: [:],
                                committedStagedIDs: [], fileRollbacks: [])
    }

    /// Removes this attempt's permanent-media files. Safe to call more than once.
    func rollBackFiles() {
        guard !alreadyRolledBack.value else { return }
        alreadyRolledBack.value = true
        for rollback in fileRollbacks { rollback() }
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// P6-I-01 — the save-failure alert, as a modifier rather than another `.alert`
/// in the editors' view chains.
///
/// `AddEditSessionView`'s body is already at the Swift type-checker's limit:
/// adding the alert inline produced *"the compiler is unable to type-check this
/// expression in reasonable time"*. A `ViewModifier` is one generic application
/// instead of another builder branch, so the message ships without touching the
/// surrounding layout. Both editors use it, so the copy cannot drift.
struct AttachmentSaveErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Couldn’t Save",
            isPresented: Binding(get: { message != nil },
                                 set: { if !$0 { message = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(message ?? "") }
        )
    }
}
#endif

/// P6-I-01 — THE ORCHESTRATION SEAM.
///
/// The ORDER of commit → save → finalise is the fix, and it used to exist only
/// as a statement sequence inside two SwiftUI view methods. That made it
/// unreachable from a test: the editors' `@State` cannot be configured on an
/// uninstalled view struct (measured — see
/// `P6I01AttachmentCommitFailureTests.testStagedFixtureOnAnUnmountedViewIsActuallyConfigured`),
/// so the rule could only be pinned by reading source text.
///
/// The sequence now lives here, once, and both editors call it. Tests drive it
/// with stub steps and assert the contract directly, WITHOUT restating the
/// algorithm: there is exactly one implementation and the tests observe it.
@MainActor
enum AttachmentCommitTransaction {

    /// The four steps a caller supplies. Each editor passes its own.
    struct Steps {
        /// Phase A. Writes media and creates objects; throws on failure.
        let commit: () throws -> AttachmentCommitAttempt
        /// The caller's `viewContext.save()`.
        let save: () throws -> Void
        /// Phase C. Consumes staged state. Runs ONLY after `save` succeeds.
        let finalise: (AttachmentCommitAttempt) -> Void
        /// Discards this attempt's Core Data work, leaving unrelated pending
        /// changes alone. Called on either failure, never on success.
        let discardAttempt: () -> Void
    }

    enum Outcome {
        case committed(AttachmentCommitAttempt)
        /// The write failed. Nothing was saved and nothing staged was consumed.
        case commitFailed(Error)
        /// The writes succeeded and the save did not. This attempt's files have
        /// been removed and nothing staged was consumed.
        case saveFailed(Error)

        var error: Error? {
            switch self {
            case .committed: return nil
            case .commitFailed(let e), .saveFailed(let e): return e
            }
        }
    }

    /// Runs the sequence. The guarantees, which the tests assert directly:
    ///
    /// 1. `finalise` runs if and only if both `commit` and `save` succeeded.
    /// 2. A commit failure never reaches `save`.
    /// 3. A save failure rolls back the attempt's files exactly once.
    /// 4. `discardAttempt` runs on either failure and never on success.
    static func run(_ steps: Steps) -> Outcome {
        let attempt: AttachmentCommitAttempt
        do {
            attempt = try steps.commit()
        } catch {
            steps.discardAttempt()
            return .commitFailed(error)
        }

        do {
            try steps.save()
        } catch {
            attempt.rollBackFiles()
            steps.discardAttempt()
            return .saveFailed(error)
        }

        steps.finalise(attempt)
        return .committed(attempt)
    }
}
