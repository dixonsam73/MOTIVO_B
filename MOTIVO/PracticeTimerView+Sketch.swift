//
//  PracticeTimerView+Sketch.swift
//  MOTIVO
//
//  A MANUSCRIPT SKETCH ON THE TIMER PAGE: the fourth staged kind, beside
//  audio, photo and video (RELEASE.md, section B).
//
//  The sketch button opens the pad and starts nothing: not the timer, not
//  audio. A finished sketch is staged exactly as a photo is: in memory for
//  the page, and in `StagingStore` so it is still there after a relaunch.
//  From there it follows the existing hand-offs and nothing new:
//
//  - before the timer starts, Save Thought carries it to the thought editor;
//  - if the timer is started, it is still staged at Finish and goes to the
//    review page with the recordings;
//  - a thought already saved is never taken back by a later Start, because
//    saving consumed its staged ids.
//
//  It travels as the one PDF that carries its own drawing
//  (`ManuscriptSketchFile`), so both editors show it as a PDF and the entry
//  editor reopens it as ink.
//
//  WHAT PROTECTS THE DRAWING. While the pad is open, and from the pad's Save
//  until the staged file has landed, it is the pad's recovery copy
//  (`ManuscriptSketchRecovery`). Once the file is in the staging store that
//  file is the durable copy, and the recovery copy is released. If staging
//  fails the recovery copy is kept, so the drawing is offered back the next
//  time a sketch is started.
//

import SwiftUI

/// A staged sketch being reopened on the pad.
struct TimerSketchEditRequest: Identifiable {
    let id: UUID
    let sketch: ManuscriptSketch
    let title: String

    /// The recovery copy for an edit of this staged sketch: one per sketch,
    /// so an edit lost when the app stopped is found when it is reopened.
    var recoveryKey: String { "timer-" + id.uuidString }
}

extension PracticeTimerView {

    // MARK: - Names

    func stagedSketchTitle(_ id: UUID) -> String {
        let trimmed = (sketchTitles[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ManuscriptPadView.defaultTitle : trimmed
    }

    func renameStagedSketch(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == ManuscriptPadView.defaultTitle {
            sketchTitles.removeValue(forKey: id)
        } else {
            sketchTitles[id] = trimmed
        }
        persistStagedAttachments()
    }

    /// Both editors read a staged PDF's name from the staged display names,
    /// by staged id. A sketch keeps its id through a hand-off, so its name is
    /// written there just before one.
    func seedSketchDisplayNames() {
        guard !stagedSketches.isEmpty else { return }
        let key = "stagedAttachmentDisplayNames_temp"
        var names = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        for sketch in stagedSketches {
            names[sketch.id.uuidString] = stagedSketchTitle(sketch.id)
        }
        UserDefaults.standard.set(names, forKey: key)
    }

    // MARK: - From the pad

    /// The pad's Save for a new sketch.
    func stageNewSketch(_ result: ManuscriptPadResult) {
        let id = UUID()
        let revealAttachments = !hasAttachments
        stagedSketches.append(StagedAttachment(id: id, data: result.data, kind: .pdf))
        if result.title != ManuscriptPadView.defaultTitle { sketchTitles[id] = result.title }
        if revealAttachments { isAttachmentsVisible = true }
        persistStagedAttachments()
        landSketchInStagingStore(id: id, data: result.data, recoveryKey: result.recoveryKey)
    }

    /// The pad's Save for a staged sketch that was reopened.
    func applyEditedStagedSketch(_ result: ManuscriptPadResult, id: UUID) {
        guard let index = stagedSketches.firstIndex(where: { $0.id == id }) else { return }
        stagedSketches[index] = StagedAttachment(id: id, data: result.data, kind: .pdf)
        persistStagedAttachments()
        landSketchInStagingStore(id: id, data: result.data, recoveryKey: result.recoveryKey)
    }

    /// Writes the sketch's PDF into the staging store under ITS id (as C-89
    /// does for a photo), replacing the staged file if there is one. Only
    /// when that has succeeded is the pad's recovery copy released.
    private func landSketchInStagingStore(id: UUID, data: Data, recoveryKey: String) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sketch-" + UUID().uuidString)
            .appendingPathExtension("pdf")
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            // Nothing staged on disk: the recovery copy goes on protecting it.
            return
        }
        pendingStagingOps.insert(id)
        Task {
            defer { pendingStagingOps.remove(id) }
            do {
                if let existing = StagingStore.ref(withId: id), existing.kind == .sketch {
                    _ = try await StagingStore.replace(original: existing, with: tmp)
                } else {
                    _ = try await StagingStore.saveNew(from: tmp, kind: .sketch, suggestedName: id.uuidString,
                                                       duration: nil, poster: nil, id: id)
                }
                ManuscriptSketchRecovery.clear(key: recoveryKey)
            } catch {
                // Not staged: the recovery copy is kept and the drawing is
                // offered back the next time a sketch is started.
            }
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    // MARK: - On the page

    /// A tap on a staged sketch's tile: back to the pad, to carry on drawing.
    func openStagedSketch(_ id: UUID) {
        guard let staged = stagedSketches.first(where: { $0.id == id }),
              let sketch = try? ManuscriptSketchFile.read(data: staged.data) else { return }
        stopAttachmentPlayback()
        timerSketchEdit = TimerSketchEditRequest(id: id, sketch: sketch, title: stagedSketchTitle(id))
    }

    /// The tile's bin. Removed on purpose, so no copy is kept to offer back.
    func deleteStagedSketch(_ id: UUID) {
        stagedSketches.removeAll { $0.id == id }
        sketchTitles.removeValue(forKey: id)
        ManuscriptSketchRecovery.clear(key: "timer-" + id.uuidString)
        persistStagedAttachments()
        if let ref = StagingStore.ref(withId: id) { StagingStore.remove(ref) }
        if !hasAttachments {
            UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
            isAttachmentsVisible = false
        }
    }

    /// Wherever the whole draft's staged items are dropped from the page
    /// (a saved session, a confirmed discard), the sketches go with them.
    /// The staged files are removed by those paths' own store clearing.
    func clearStagedSketches() {
        for sketch in stagedSketches {
            ManuscriptSketchRecovery.clear(key: "timer-" + sketch.id.uuidString)
        }
        stagedSketches.removeAll()
        sketchTitles.removeAll()
    }
}

/// The pad, for a new sketch and for one reopened from its tile, as ONE
/// modifier: `PracticeTimerView`'s body is at the type-checker's limit.
struct TimerSketchPresentation: ViewModifier {
    @Binding var showNew: Bool
    @Binding var edit: TimerSketchEditRequest?
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
                ManuscriptPadView(existing: request.sketch,
                                  title: request.title,
                                  recovery: .reopening(key: request.recoveryKey, attachment: nil, held: false),
                                  onRename: { onRename(request.id, $0) }) { result in
                    onEdited(result, request.id)
                }
            }
    }
}
