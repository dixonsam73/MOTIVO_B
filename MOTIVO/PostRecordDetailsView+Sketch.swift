//
//  PostRecordDetailsView+Sketch.swift
//  MOTIVO
//
//  A MANUSCRIPT SKETCH ON THE REVIEW PAGE (after a timed session): a fourth
//  button beside photo, file and score, and a sketch's tile opens the pad,
//  as in the entry editor.
//
//  THE TIMER HOLDS THE SKETCH. This page is shown over the Timer, and its
//  Back button returns there with the session kept. So a sketch drawn or
//  changed here is staged ON THE TIMER at the pad's Save
//  (`ReviewSketchStaging`), exactly as one drawn on the Timer page is, and
//  this page shows its copy of it. Back to Timer then loses nothing: the
//  sketch is on the Timer's attachments, and comes back here at the next
//  Finish. Save Session saves this page's copy, and the Timer drops its
//  staged items as it does for every other kind.
//
//  What protects the drawing is the Timer's rule and nothing new: the pad's
//  recovery copy until the staged file has landed, then the staged file.
//

import SwiftUI

/// What the review page asks of the Timer for its sketches.
struct ReviewSketchStaging {
    /// The pad's Save for a new sketch. Returns the id it is staged under.
    var stageNew: (ManuscriptPadResult) -> UUID
    /// The pad's Save for a staged sketch that was reopened.
    var applyEdit: (ManuscriptPadResult, UUID) -> Void
    var rename: (UUID, String) -> Void
    /// Removed on purpose, from the page it was drawn on.
    var remove: (UUID) -> Void
}

/// A staged sketch being reopened on the pad from the review page.
struct PRDVSketchEditRequest: Identifiable {
    let id: UUID
    let sketch: ManuscriptSketch
    let title: String
}

extension PostRecordDetailsView {

    private static let displayNamesKey = "stagedAttachmentDisplayNames_temp"

    /// The Timer's sketches arrive as the PDFs that carry their drawings.
    func noteTimerSketches_PRDV(in attachments: [StagedAttachment]) {
        guard sketchStaging != nil else { return }
        for att in attachments where att.kind == .pdf && ManuscriptSketchFile.carriesSketch(data: att.data) {
            sketchAttachmentIDs_PRDV.insert(att.id)
        }
    }

    func sketchTitle_PRDV(_ id: UUID) -> String {
        let name = (UserDefaults.standard.dictionary(forKey: Self.displayNamesKey) as? [String: String])?[id.uuidString]
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ManuscriptPadView.defaultTitle : trimmed
    }

    private func setSketchDisplayName_PRDV(_ title: String, id: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var names = (UserDefaults.standard.dictionary(forKey: Self.displayNamesKey) as? [String: String]) ?? [:]
        if trimmed.isEmpty { names.removeValue(forKey: id.uuidString) } else { names[id.uuidString] = trimmed }
        UserDefaults.standard.set(names, forKey: Self.displayNamesKey)
        attachmentTitlesRefreshTick &+= 1
    }

    /// The pad's Save for a new sketch: staged on the Timer, shown here
    /// under the same id.
    func stageNewSketch_PRDV(_ result: ManuscriptPadResult) {
        guard let staging = sketchStaging else { return }
        let id = staging.stageNew(result)
        stagedAttachments.append(StagedAttachment(id: id, data: result.data, kind: .pdf))
        sketchAttachmentIDs_PRDV.insert(id)
        sketchesDrawnHere_PRDV.insert(id)
        setSketchDisplayName_PRDV(result.title, id: id)
    }

    /// A tap on a sketch's tile: back to the pad, to carry on drawing.
    func openSketch_PRDV(_ att: StagedAttachment) {
        do {
            let sketch = try ManuscriptSketchFile.read(data: att.data)
            sketchEdit_PRDV = PRDVSketchEditRequest(id: att.id, sketch: sketch, title: sketchTitle_PRDV(att.id))
        } catch {
            consentState.present(notice: "This sketch can't be opened for editing.")
        }
    }

    /// The pad's Save for a sketch reopened here.
    func applyEditedSketch_PRDV(_ result: ManuscriptPadResult, id: UUID) {
        guard let index = stagedAttachments.firstIndex(where: { $0.id == id }) else { return }
        let old = stagedAttachments[index]
        stagedAttachments[index] = StagedAttachment(id: old.id, data: result.data, kind: old.kind,
                                                    selectedPages: old.selectedPages, sourceFormat: old.sourceFormat)
        // The viewer reads a staged item from its temporary file, if one was written.
        if let surrogate = existingSurrogateURL_tmpOnly(id: id, kind: .pdf) {
            try? result.data.write(to: surrogate, options: .atomic)
        }
        sketchStaging?.applyEdit(result, id)
    }

    func renameSketch_PRDV(_ id: UUID, to title: String) {
        setSketchDisplayName_PRDV(title, id: id)
        sketchStaging?.rename(id, title)
    }

    /// A sketch's tile was binned here. One drawn on this page in this visit
    /// goes from the Timer too: it was never seen there. One that came from
    /// the Timer stays on the Timer, like every other kind that came with it.
    func sketchRemoved_PRDV(_ id: UUID) {
        sketchAttachmentIDs_PRDV.remove(id)
        if sketchesDrawnHere_PRDV.remove(id) != nil { sketchStaging?.remove(id) }
    }
}

/// The pad, for a new sketch and for one reopened from its tile.
struct PRDVSketchPresentation: ViewModifier {
    @Binding var showNew: Bool
    @Binding var edit: PRDVSketchEditRequest?
    let onNew: (ManuscriptPadResult) -> Void
    let onEdited: (ManuscriptPadResult, UUID) -> Void
    let onRename: (UUID, String) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showNew) {
                ManuscriptPadView(recovery: .new()) { result in
                    onNew(result)
                }
            }
            .fullScreenCover(item: $edit) { request in
                // The Timer's key for this sketch, so an edit lost when the
                // app stopped is found from either page.
                ManuscriptPadView(existing: request.sketch,
                                  title: request.title,
                                  recovery: .reopening(key: TimerSketchEditRequest.recoveryKey(for: request.id),
                                                       attachment: nil, held: false),
                                  onRename: { onRename(request.id, $0) }) { result in
                    onEdited(result, request.id)
                }
            }
    }
}
