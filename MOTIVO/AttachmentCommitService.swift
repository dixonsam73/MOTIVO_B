//
//  AttachmentCommitService.swift
//  MOTIVO
//
//  PHASE 6 · BATCH 1 · P6-I-01 — THE ATTACHMENT COMMIT, AS CALLABLE CODE.
//
//  The loop that writes permanent media and creates `Attachment` rows used to
//  exist twice, once inside each editor's `View` extension, reading the editor's
//  `@State` directly. That made the riskiest code in the save path untestable:
//  a `@State` write on a view struct that was never installed is ignored, so a
//  test could not put a single staged attachment in front of the loop. Measured
//  during this batch — the earlier behavioural suite drove an EMPTY list and
//  would have asserted against a loop that never ran.
//
//  The loop now lives here and takes its inputs as PARAMETERS. Both editors are
//  thin wrappers that pass their own state, and the disposable-fixture tests
//  drive exactly the code the app runs.
//
//  WHAT DELIBERATELY DID NOT MOVE. The staged→final migration of privacy, page
//  selections and titles stays in each editor, because the two differ:
//  `AddEditSessionView` keeps a local `privacyMap` cache and uses
//  `migratePrivacy_AESV`, while `PostRecordDetailsView` also persists audio and
//  video titles. Folding those together would change behaviour under cover of a
//  refactor. This service owns only what is genuinely identical: write the file,
//  create the row, record what to undo.
//

import Foundation
import CoreData

@MainActor
enum AttachmentCommitService {

    /// Everything the loop needs, supplied by the calling editor.
    struct Inputs {
        /// The staged items to commit, already filtered by the caller —
        /// `AddEditSessionView` excludes items already persisted.
        let staged: [StagedAttachment]
        /// The staged id chosen as the session thumbnail, if any.
        let chosenThumbnailID: UUID?
        /// The filename stem for an item. The editors differ: one honours a
        /// renamed audio stem for every kind, the other only for audio.
        let suggestedName: (StagedAttachment) -> String
        /// The display name to store on the row, if any.
        let displayName: (StagedAttachment) -> String?

        init(staged: [StagedAttachment],
             chosenThumbnailID: UUID?,
             suggestedName: @escaping (StagedAttachment) -> String,
             displayName: @escaping (StagedAttachment) -> String?) {
            self.staged = staged
            self.chosenThumbnailID = chosenThumbnailID
            self.suggestedName = suggestedName
            self.displayName = displayName
        }
    }

    /// Writes permanent media and creates the rows. **Throws** on the first
    /// failure, after removing this attempt's files and objects.
    ///
    /// Nothing outside Core Data and the files it writes is touched, so a caller
    /// that aborts here still has every staged original, every staged privacy
    /// value, every staged page selection and every staged title.
    static func commit(_ inputs: Inputs,
                       to session: Session,
                       ctx: NSManagedObjectContext) throws -> AttachmentCommitAttempt {
        var stagedToFinalID: [UUID: UUID] = [:]
        var stagedToFinalURL: [UUID: URL] = [:]
        var committedStagedIDs: [UUID] = []
        var rollbacks: [() -> Void] = []
        var created: [Attachment] = []

        for att in inputs.staged {
            do {
                // C-77 — the persisted extension must describe the BYTES, from
                // the one place that decides it.
                let ext = AttachmentImportPolicy.fileExtension(for: att)
                let result = try AttachmentStore.saveDataWithRollback(att.data,
                                                                     suggestedName: inputs.suggestedName(att),
                                                                     ext: ext)
                rollbacks.append(result.rollback)

                let isThumb = (att.kind == .image) && (inputs.chosenThumbnailID == att.id)
                let row = try AttachmentStore.addAttachment(kind: att.kind,
                                                            filePath: result.path,
                                                            to: session,
                                                            isThumbnail: isThumb,
                                                            displayName: inputs.displayName(att),
                                                            ctx: ctx)
                created.append(row)

                if let finalID = row.value(forKey: "id") as? UUID {
                    stagedToFinalID[att.id] = finalID
                    stagedToFinalURL[att.id] = URL(fileURLWithPath: result.path)
                    committedStagedIDs.append(att.id)
                }
            } catch {
                // Roll back ONLY this attempt. The caller's staged state is
                // untouched, so a retry has the same inputs the first attempt had.
                for rollback in rollbacks { rollback() }
                for row in created { ctx.delete(row) }
                throw AttachmentCommitFailure(stagedID: att.id, underlying: error)
            }
        }

        return AttachmentCommitAttempt(stagedToFinalID: stagedToFinalID,
                                       stagedToFinalURL: stagedToFinalURL,
                                       committedStagedIDs: committedStagedIDs,
                                       fileRollbacks: rollbacks)
    }

    /// Applies the session's thumbnail flags. A Core Data mutation, so it belongs
    /// in the same save — and inside the attempt's undo group.
    static func applyThumbnailFlags(finalThumbnailID: UUID?,
                                    to session: Session,
                                    ctx: NSManagedObjectContext) {
        do {
            let request: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            request.predicate = NSPredicate(format: "session == %@", session.objectID)
            for a in try ctx.fetch(request) {
                let id = a.value(forKey: "id") as? UUID
                a.setValue(id != nil && id == finalThumbnailID, forKey: "isThumbnail")
            }
        } catch {
            print("Failed to update thumbnail flags: ", error)
        }
    }
}
