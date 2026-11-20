//
//  ManuscriptSketchRecovery.swift
//  MOTIVO
//
//  A sketch that has been drawn but is not yet durably part of an entry,
//  kept on this device so that a crash, or the app being closed, is not a
//  decision to discard it.
//
//  There are two stretches in which drawn work exists nowhere durable:
//
//  1. while the pad is open, before Save;
//  2. AFTER the pad's Save and BEFORE the entry is saved. The finished PDF
//     is then only in the editor's memory (a new sketch) or in a file the
//     saved record does not name yet (an edit of a saved sketch).
//
//  One recovery copy per sketch covers both. It is written while the person
//  draws, kept when the pad hands the sketch to the editor, and removed only
//  when the entry's save is durable or the person discards the work. If the
//  app stops in between, the copy is offered back the next time that sketch,
//  or a new sketch, is opened.
//
//  Every sketch has its own copy, so several unsaved sketches never share a
//  slot. Device-only by design: never synced, never backed up, removed by
//  Erase. The saved sketch (the attachment's PDF) is not touched by this.
//

import Foundation
import PencilKit

enum ManuscriptSketchRecovery {

    /// A recovery copy as found on disk.
    struct Copy {
        let key: String
        let sketch: ManuscriptSketch
        /// The SAVED attachment this is an edit of; nil for a sketch that is
        /// not part of any saved entry yet.
        let attachment: UUID?
        /// True once the pad's Save handed it to the editor.
        let handedOver: Bool
        let savedAt: Date
    }

    private struct Stored: Codable {
        var paper: ManuscriptPaper
        var drawing: Data
        var savedAt: Date
        var attachment: UUID?
        var handedOver: Bool?
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

    private static func safe(_ key: String) -> String {
        String(String.UnicodeScalarView(key.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }))
    }

    private static func url(for key: String) -> URL {
        directory().appendingPathComponent(safe(key), isDirectory: false).appendingPathExtension("draft")
    }

    /// A key for a sketch that has none yet. Each new sketch gets its own.
    static func newKey() -> String { UUID().uuidString }

    /// The key for an edit of a saved attachment: one copy per attachment.
    static func key(forSaved attachment: UUID) -> String { attachment.uuidString }

    // MARK: Writing

    /// Keeps the sketch as it is now. Returns false if it could not be written.
    @discardableResult
    static func keep(_ sketch: ManuscriptSketch, key: String, attachment: UUID? = nil, handedOver: Bool = false) -> Bool {
        let stored = Stored(paper: sketch.paper, drawing: sketch.drawing.dataRepresentation(), savedAt: Date(),
                            attachment: attachment, handedOver: handedOver)
        guard let data = try? JSONEncoder().encode(stored) else { return false }
        return (try? data.write(to: url(for: key), options: .atomic)) != nil
    }

    static func clear(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    static func clear<Keys: Sequence>(keys: Keys) where Keys.Element == String {
        for key in keys { clear(key: key) }
    }

    // MARK: Reading

    static func copy(key: String) -> Copy? { copy(at: url(for: key)) }

    private static func copy(at url: URL) -> Copy? {
        guard url.pathExtension == "draft",
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              let drawing = try? PKDrawing(data: stored.drawing) else { return nil }
        return Copy(key: url.deletingPathExtension().lastPathComponent,
                    sketch: ManuscriptSketch(paper: stored.paper, drawing: drawing),
                    attachment: stored.attachment, handedOver: stored.handedOver ?? false, savedAt: stored.savedAt)
    }

    /// Copies of sketches that belong to no saved entry, oldest first,
    /// leaving out those an open editor is already holding.
    static func unattached(excluding held: Set<String> = []) -> [Copy] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)) ?? []
        let excluded = Set(held.map(safe))
        return files.compactMap(copy(at:))
            .filter { $0.attachment == nil && !excluded.contains($0.key) }
            .sorted { ($0.savedAt, $0.key) < ($1.savedAt, $1.key) }
    }

    // MARK: What the pad asks

    /// How the pad was opened, as far as recovery is concerned.
    struct Opening {
        /// The copy this sketch writes to. A restored copy keeps its own key.
        var key: String
        /// The saved attachment being edited; nil for a sketch not yet saved.
        var attachment: UUID?
        /// True when the editor that opened the pad is already holding this
        /// sketch (it came from the pad earlier in the same editor): its copy
        /// is not news, and must outlive a cancelled re-edit.
        var held: Bool
        /// For a brand-new sketch: copies the open editor holds, which are
        /// not on offer.
        var excluding: Set<String>
        /// True for a brand-new sketch, which may be offered any sketch left
        /// unsaved earlier.
        var isNew: Bool

        static func new(excluding: Set<String> = []) -> Opening {
            Opening(key: ManuscriptSketchRecovery.newKey(), attachment: nil, held: false, excluding: excluding, isNew: true)
        }

        static func reopening(key: String, attachment: UUID?, held: Bool) -> Opening {
            Opening(key: key, attachment: attachment, held: held, excluding: [], isNew: false)
        }
    }

    /// The copy to offer back when the pad opens, if any.
    static func offer(for opening: Opening) -> Copy? {
        if opening.isNew { return unattached(excluding: opening.excluding).first }
        return opening.held ? nil : copy(key: opening.key)
    }

    /// The pad's Save: the finished sketch stays recoverable until the entry
    /// that now holds it is durably saved.
    @discardableResult
    static func handOver(_ sketch: ManuscriptSketch, opening: Opening) -> Bool {
        keep(sketch, key: opening.key, attachment: opening.attachment, handedOver: true)
    }

    enum HandOverError: Error, Equatable {
        /// The recovery copy could not be written, so the sketch was not
        /// given to the editor: it would have had nothing protecting it.
        case copyNotKept
    }

    /// The pad's Save, in its one order: the recovery copy first, and only
    /// if that was written is the finished sketch given to the editor. If
    /// the copy cannot be kept this throws and `editor` is not called, so
    /// the pad stays open with the drawing in it.
    static func handOver(_ sketch: ManuscriptSketch, data: Data, opening: Opening,
                         to editor: (Data, String) throws -> Void) throws {
        guard handOver(sketch, opening: opening) else { throw HandOverError.copyNotKept }
        try editor(data, opening.key)
    }

    /// The pad was left on purpose without saving. A sketch the editor is
    /// holding goes back to what the editor holds; anything else is dropped.
    static func leftWithoutSaving(opening: Opening, heldSketch: ManuscriptSketch?) {
        if opening.held, let heldSketch {
            keep(heldSketch, key: opening.key, attachment: opening.attachment, handedOver: true)
        } else {
            clear(key: opening.key)
        }
    }

    /// Erase All Études Data: nothing drawn stays behind.
    static func wipeForFactoryReset() {
        try? FileManager.default.removeItem(at: directory())
    }
}

/// The recovery copies one open entry editor is holding: sketches the pad
/// has handed to it and the entry has not saved yet.
struct ManuscriptSketchRecoveryLedger {
    /// The editor's attachment id (staged or saved) → its recovery copy's key.
    private(set) var keys: [UUID: String] = [:]

    var held: Set<String> { Set(keys.values) }

    func key(for attachment: UUID) -> String? { keys[attachment] }

    /// The pad saved a sketch into this editor under `attachment`.
    mutating func handedOver(key: String, for attachment: UUID) {
        keys[attachment] = key
    }

    /// The person removed that attachment in the editor: its work is discarded.
    mutating func discarded(_ attachment: UUID) {
        if let key = keys.removeValue(forKey: attachment) { ManuscriptSketchRecovery.clear(key: key) }
    }

    /// The entry's save is durable: everything held here is part of it now.
    mutating func entrySaved() {
        ManuscriptSketchRecovery.clear(keys: keys.values)
        keys = [:]
    }

    /// The person left the editor without saving: its unsaved work is discarded.
    mutating func editorCancelled() {
        ManuscriptSketchRecovery.clear(keys: keys.values)
        keys = [:]
    }
}
