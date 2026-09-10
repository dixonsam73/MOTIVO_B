//
//  AttachmentImportPolicy.swift
//  MOTIVO
//
//  PHASE 5 · C-77 — THE IMPORT RULES, IN ONE PLACE.
//
//  **WHY THIS TYPE EXISTS, AND IT IS NOT TIDINESS.** Two views own session
//  attachments — `AddEditSessionView` and `PostRecordDetailsView` — and each has
//  its own `stageData`, `kindForURL`, `handleFileImport`, file importer and
//  photo picker. Unit 1a fixed **one of the two**, so every C-63 and C-74
//  protection was absent from the other: unsupported files stayed selectable,
//  the source format was discarded, and the MIME still described the kind's
//  default.
//
//  **That was device-observed, not theorised:** an 83 MB, 3 min 24 s WAV
//  imported through the second view was wrongly refused from Connected — 204
//  seconds predicts a ~7.2 MB derivative — and persisted as `.m4a`.
//
//  **THE FIX IS NOT TO REPAIR THE DUPLICATE.** A third copy of the rules would
//  be a third thing to miss. The RULES live here; each view keeps only its own
//  state handling.
//

import Foundation
import UniformTypeIdentifiers

enum AttachmentImportPolicy {

    /// Shown when a file outside the deliberate set is chosen.
    static let unsupportedFileMessage = "That file type isn’t supported in Études."

    /// Shown when a picked photo-library item is neither a supported image nor
    /// a supported movie.
    static let unsupportedItemMessage = "That item isn’t a photo or video Études can use."

    /// The deliberate set, for a document importer. Narrowing this makes
    /// unsupported files UNSELECTABLE rather than selectable-then-refused.
    static var importerContentTypes: [UTType] { MediaFormat.importerContentTypes }

    /// A file chosen from a document importer. `nil` means REFUSE — it could
    /// never publish, so accepting it would only defer the failure to a publish
    /// the member believes succeeded.
    static func classify(fileURL url: URL) -> MediaFormat? {
        MediaFormat.from(url: url)
    }

    /// An item from the photo library, classified by its own UTType rather than
    /// by a filename — which is why an iPhone HEIC is recognised as HEIC.
    static func classify(pickerType type: UTType) -> MediaFormat? {
        if let ext = type.preferredFilenameExtension,
           let format = MediaFormat.from(fileExtension: ext) {
            return format
        }
        // Conformance fallback keeps a supported-but-unusually-typed item usable
        // rather than refusing a legitimate photo or video outright.
        if type.conforms(to: .image) { return .jpeg }
        if type.conforms(to: .movie) { return .mov }
        return nil
    }

    /// The kind an attachment takes, for the two views' `kindForURL`.
    /// Anything outside the deliberate set is `.file`, and `.file` is refused at
    /// import rather than staged.
    static func kind(forFileURL url: URL) -> AttachmentKind {
        classify(fileURL: url)?.kind ?? .file
    }
}
