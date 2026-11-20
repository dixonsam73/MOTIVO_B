//
//  ManuscriptSketchRecovery.swift
//  MOTIVO
//
//  Unfinished sketching, kept on this device so that a crash, or the app
//  being closed mid-drawing, is not a decision to discard it.
//
//  While the pad is open its drawing is written here, one file per sketch
//  being worked on. The file goes when the sketch is saved or the person
//  discards it; if it is still there when that pad is next opened, the
//  drawing is offered back.
//
//  Device-only by design: never synced, never backed up, removed by Erase.
//  The saved sketch (the attachment's PDF) is not touched by any of this.
//

import Foundation
import PencilKit

enum ManuscriptSketchRecovery {

    /// The slot for a sketch that has not been saved yet. There is one: a
    /// new sketch is started from one place at a time.
    static let newSketchKey = "new"

    private struct Draft: Codable {
        var paper: ManuscriptPaper
        var drawing: Data
        var savedAt: Date
    }

    static func directory() -> URL {
        var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SketchRecovery", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    private static func url(for key: String) -> URL {
        let safe = key.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        return directory().appendingPathComponent(String(String.UnicodeScalarView(safe)), isDirectory: false).appendingPathExtension("draft")
    }

    /// Keeps the drawing as it is now. Returns false if it could not be written.
    @discardableResult
    static func keep(_ sketch: ManuscriptSketch, key: String) -> Bool {
        let draft = Draft(paper: sketch.paper, drawing: sketch.drawing.dataRepresentation(), savedAt: Date())
        guard let data = try? JSONEncoder().encode(draft) else { return false }
        return (try? data.write(to: url(for: key), options: .atomic)) != nil
    }

    /// The unfinished drawing for this sketch, if one was left.
    static func draft(key: String) -> ManuscriptSketch? {
        guard let data = try? Data(contentsOf: url(for: key)),
              let draft = try? JSONDecoder().decode(Draft.self, from: data),
              let drawing = try? PKDrawing(data: draft.drawing) else { return nil }
        return ManuscriptSketch(paper: draft.paper, drawing: drawing)
    }

    static func clear(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    /// Erase All Études Data: nothing drawn stays behind.
    static func wipeForFactoryReset() {
        try? FileManager.default.removeItem(at: directory())
    }
}
