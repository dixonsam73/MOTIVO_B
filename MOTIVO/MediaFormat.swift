//
//  MediaFormat.swift
//  MOTIVO
//
//  PHASE 5 · UNIT 1 — VALIDATED SOURCE-FORMAT IDENTITY.
//
//  **THE DEFECT THIS EXISTS TO CORRECT.** An imported attachment used to lose
//  its format at the door: `stageData` kept only `(id, data, kind)`, and the
//  extension was then FABRICATED from the kind — image→jpg, audio→m4a,
//  video→mov — with the MIME derived from that fabrication. So the declared
//  type described the kind's DEFAULT, never the bytes.
//
//  Those defaults are exactly right for Études' own capture (the recorder writes
//  `.m4a` AAC and `.mov`), which is why it never showed. Everything IMPORTED was
//  renamed to match an assumption false for it — **measured on device: an
//  ordinary iPhone camera photo is stored `.jpg` while its bytes are HEIC.**
//
//  **THIS CARRIES A VALIDATED FORMAT, NOT A FILENAME.** No source URL and no
//  user-supplied name is retained — only a value from the deliberate set below.
//  Études-generated media pass `nil` and keep their known formats.
//
//  **THE SET IS DELIBERATE, NOT WHATEVER AN EXTENSION SWITCH RECOGNISED.**
//  GIF, BMP, TIFF, CAF, M4V, AVI and raw ADTS AAC are excluded on purpose:
//  Études is a musician's journal, not a general-purpose file manager.
//

import Foundation
import UniformTypeIdentifiers

enum MediaFormat: String, CaseIterable {
    // Audio the product deliberately supports.
    case wav, aiff, mp3, m4a, flac
    // Normal Apple photo workflows.
    case jpeg, png, heic, heif
    // Video.
    case mov, mp4
    // Documents — score/document import only.
    case pdf

    /// The extension written to local storage. Truthful by construction.
    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .mp3: return "mp3"
        case .m4a: return "m4a"
        case .flac: return "flac"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .heif: return "heif"
        case .mov: return "mov"
        case .mp4: return "mp4"
        case .pdf: return "pdf"
        }
    }

    /// What the bytes ACTUALLY are.
    var mimeType: String {
        switch self {
        case .wav: return "audio/wav"
        case .aiff: return "audio/aiff"
        case .mp3: return "audio/mpeg"
        case .m4a: return "audio/m4a"
        case .flac: return "audio/flac"
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .heic: return "image/heic"
        case .heif: return "image/heif"
        case .mov: return "video/quicktime"
        case .mp4: return "video/mp4"
        case .pdf: return "application/pdf"
        }
    }

    var kind: AttachmentKind {
        switch self {
        case .wav, .aiff, .mp3, .m4a, .flac: return .audio
        case .jpeg, .png, .heic, .heif: return .image
        case .mov, .mp4: return .video
        case .pdf: return .pdf
        }
    }

    /// **Connected carries a DERIVED representation where the original is not
    /// directly publishable** — the same principle PDF already uses (local PDF,
    /// Connected JPEG). Policy A: all deliberate audio publishes as M4A/AAC, so
    /// no lossless MIME is needed in the Connected bucket at all.
    var needsConnectedAudioDerivative: Bool {
        switch self {
        case .wav, .aiff, .mp3, .flac, .m4a: return kind == .audio
        default: return false
        }
    }

    /// Recognises only the deliberate set. Anything else is UNSUPPORTED and must
    /// be refused at import rather than becoming a `.file` that can never
    /// publish.
    static func from(fileExtension raw: String) -> MediaFormat? {
        switch raw.lowercased() {
        case "wav", "wave": return .wav
        case "aiff", "aif": return .aiff
        case "mp3": return .mp3
        case "m4a": return .m4a
        case "flac": return .flac
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "heif": return .heif
        case "mov": return .mov
        case "mp4": return .mp4
        case "pdf": return .pdf
        default: return nil
        }
    }

    static func from(url: URL) -> MediaFormat? { from(fileExtension: url.pathExtension) }

    /// The system importer's allowed types. Narrowing this makes unsupported
    /// files UNSELECTABLE rather than selectable-then-refused.
    static var importerContentTypes: [UTType] {
        var types: [UTType] = [.pdf, .wav, .aiff, .mp3, .mpeg4Audio, .png, .jpeg]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        return types
    }
}
