///
///  AttachmentStore.swift
//  MOTIVO
//

import Foundation
import CoreData
import UniformTypeIdentifiers
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

enum AttachmentKind: String {
    case audio, video, image, file
}

struct AttachmentStore {

    // MARK: - Lightweight video poster generation (in-memory cache)
    #if canImport(UIKit)
    private final class _PosterCache {
        static let shared = _PosterCache()
        let cache = NSCache<NSString, UIImage>()
        private init() {}
    }
    #endif

    /// Generates (and caches) a poster image for a local video URL.
    /// - Note: Synchronous generator is called off-main by callers. This method is safe to call from background threads.
    #if canImport(UIKit)
    static func generateVideoPoster(url: URL, at seconds: Double = 0.5) -> UIImage? {
        let key = url.path as NSString
        if let cached = _PosterCache.shared.cache.object(forKey: key) { return cached }
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let duration = asset.duration.seconds
        let clamped = min(max(seconds, 0), max(duration * 0.5, 0.5))
        do {
            let cg = try gen.copyCGImage(at: CMTime(seconds: clamped, preferredTimescale: 600), actualTime: nil)
            let img = UIImage(cgImage: cg)
            _PosterCache.shared.cache.setObject(img, forKey: key)
            return img
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - Public API

    static func saveData(_ data: Data, suggestedName: String, ext: String) throws -> String {
        let dir = try ensureDocumentsDir()
        let filename = uniqueFilename(base: suggestedName, ext: ext, in: dir)
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: [.atomic])
        return url.path
    }

    /// Writes data to Documents and returns (path, rollback) where rollback removes the file if invoked.
    static func saveDataWithRollback(_ data: Data, suggestedName: String, ext: String) throws -> (path: String, rollback: () -> Void) {
        let dir = try ensureDocumentsDir()
        let filename = uniqueFilename(base: suggestedName, ext: ext, in: dir)
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: [.atomic])
        let rollback = { removeIfExists(path: url.path) }
        return (url.path, rollback)
    }

    // Best-effort removal helper (safe no-op if missing)
    static func removeIfExists(path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
    }

    #if DEBUG
    static func fileSize(atURL url: URL) -> Int64 {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    static func fileSize(atPath path: String) -> Int64 {
        return fileSize(atURL: URL(fileURLWithPath: path))
    }
    #endif

    /// Delete a single attachment file on disk.
    /// - Note: Best-effort, constrained to the app's Documents directory for safety.
    static func deleteAttachmentFile(at url: URL) {
        let fm = FileManager.default

        guard let docs = try? ensureDocumentsDir().standardizedFileURL else {
            #if DEBUG
            print("[AttachmentStore] deleteAttachmentFile — unable to resolve Documents directory")
            #endif
            return
        }

        let normalized = url.standardizedFileURL
        let rootPath = docs.path.hasSuffix("/") ? docs.path : docs.path + "/"

        // Safety guard: refuse to delete anything outside Documents.
        guard normalized.path.hasPrefix(rootPath) else {
            #if DEBUG
            print("[AttachmentStore] deleteAttachmentFile — refusing to delete outside Documents: \(normalized.path)")
            #endif
            return
        }

        if fm.fileExists(atPath: normalized.path) {
            do {
                try fm.removeItem(at: normalized)
            } catch {
                #if DEBUG
                print("[AttachmentStore] deleteAttachmentFile — failed to remove \(normalized.path): \(error)")
                #endif
            }
        } else {
            #if DEBUG
            print("[AttachmentStore] deleteAttachmentFile — file not found at path: \(normalized.path)")
            #endif
        }
    }

    /// Convenience overload for Core Data `fileURL` String attributes.
    static func deleteAttachmentFile(atPath path: String) {
        deleteAttachmentFile(at: URL(fileURLWithPath: path))
    }

    /// Batch helper for URL-based deletions.
    static func deleteAttachmentFiles(at urls: [URL]) {
        urls.forEach { deleteAttachmentFile(at: $0) }
    }

    /// Batch helper for String path deletions.
    static func deleteAttachmentFiles(atPaths paths: [String]) {
        paths.forEach { deleteAttachmentFile(atPath: $0) }
    }

    /// Creates and attaches a Core Data `Attachment` to a session.
    /// NOTE: We ONLY set the inverse (`att.session = session`). Core Data keeps the other side in sync.
    @MainActor
    @discardableResult
    static func addAttachment(kind: AttachmentKind,
                              filePath: String,
                              to session: Session,
                              isThumbnail: Bool,
                              ctx: NSManagedObjectContext) throws -> Attachment {
        let att = Attachment(context: ctx)
        if att.value(forKey: "id") == nil { att.setValue(UUID(), forKey: "id") }
        if att.value(forKey: "createdAt") == nil { att.setValue(Date(), forKey: "createdAt") }

        att.setValue(kind.rawValue, forKey: "kind")
        att.setValue(filePath,      forKey: "fileURL")
        att.setValue(isThumbnail,   forKey: "isThumbnail")

        // Inverse relationship is enough; avoid assigning to session.attachments directly.
        att.setValue(session,       forKey: "session")

        // 🔐 V4 hardening: ensure ownerUserID is stamped
        if let uid = PersistenceController.shared.currentUserID, !uid.isEmpty {
            att.setValue(uid, forKey: "ownerUserID")
        } else if let sid = (session.value(forKey: "ownerUserID") as? String), !sid.isEmpty {
            // Inherit from session if available
            att.setValue(sid, forKey: "ownerUserID")
        }
        // (If neither branch applies, PersistenceController's WillSave observer/backfill will still cover it.)

        return att
    }

    // MARK: - Replace / Adopt Temp Export

    /// Atomically replace an existing attachment file with a new exported temp file.
    /// - Parameters:
    ///   - tempURL: A file URL in a temporary location (e.g., /tmp) returned by the trimmer/exporter.
    ///   - existingPath: The current attachment's file path (Documents) to be replaced.
    ///   - kind: The attachment kind (used to choose extension and poster regeneration for video).
    /// - Returns: The final path (String) of the adopted file inside Documents.
    /// - Behavior:
    ///   1. Moves the temp file into Documents atomically (unique filename if needed).
    ///   2. Deletes the old/original file.
    ///   3. Clears any cached poster for the old path and regenerates for the new path (video only).
    ///   4. Returns the new file path.
    /// - Notes:
    ///   - This method is constrained to Documents for safety.
    static func replaceAttachmentFile(withTempURL tempURL: URL, forExistingPath existingPath: String, kind: AttachmentKind) throws -> String {
        let fm = FileManager.default
        let docs = try ensureDocumentsDir()

        // Determine extension from kind, but preserve incoming extension if present.
        let incomingExt = tempURL.pathExtension
        let defaultExt: String
        switch kind {
        case .audio: defaultExt = incomingExt.isEmpty ? "m4a" : incomingExt
        case .video: defaultExt = incomingExt.isEmpty ? "mp4" : incomingExt
        case .image: defaultExt = incomingExt.isEmpty ? "jpg" : incomingExt
        case .file:  defaultExt = incomingExt.isEmpty ? (tempURL.pathExtension.isEmpty ? "dat" : tempURL.pathExtension) : incomingExt
        }

        // Target filename: reuse base name from existingPath when possible to avoid churn.
        let existingURL = URL(fileURLWithPath: existingPath)
        let base = existingURL.deletingPathExtension().lastPathComponent
        let candidateName = base.isEmpty ? UUID().uuidString : base
        let finalFilename = uniqueFilename(base: candidateName, ext: defaultExt, in: docs)
        let finalURL = docs.appendingPathComponent(finalFilename, isDirectory: false)

        #if DEBUG
        let originalSize = fileSize(atPath: existingPath)
        let tempSize = fileSize(atURL: tempURL)
        print("[AttachmentStore] replace begin\n  original=\(existingPath) size=\(originalSize)\n  temp=\(tempURL.path) size=\(tempSize)\n  final=\(finalURL.path)")
        #endif

        // Move temp into Documents (atomic move removes tempURL path on success).
        try fm.moveItem(at: tempURL, to: finalURL)

        // Delete old/original file (best-effort, restricted to Documents).
        deleteAttachmentFile(atPath: existingPath)

        // Invalidate poster cache for old path and prewarm for new video path.
        #if canImport(UIKit)
        if kind == .video {
            _PosterCache.shared.cache.removeObject(forKey: existingURL.path as NSString)
            _ = generateVideoPoster(url: finalURL)
        }
        #endif

        #if DEBUG
        let finalSize = fileSize(atURL: finalURL)
        print("[AttachmentStore] replace done\n  final=\(finalURL.path) size=\(finalSize)")
        #endif

        return finalURL.path
    }

    /// Adopt a temp export as a new file in Documents (used for Save-as-New flows).
    /// - Returns: Final path in Documents.
    static func adoptTempExport(_ tempURL: URL, suggestedName: String, kind: AttachmentKind) throws -> String {
        let docs = try ensureDocumentsDir()
        let ext = tempURL.pathExtension.isEmpty ? (kind == .audio ? "m4a" : kind == .video ? "mp4" : "dat") : tempURL.pathExtension
        let filename = uniqueFilename(base: suggestedName, ext: ext, in: docs)
        let finalURL = docs.appendingPathComponent(filename, isDirectory: false)
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        #if canImport(UIKit)
        if kind == .video { _ = generateVideoPoster(url: finalURL) }
        #endif
        return finalURL.path
    }

    // MARK: - Helpers

    private static func ensureDocumentsDir() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "AttachmentStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Documents directory missing"])
        }
        return url
    }

    private static func uniqueFilename(base: String, ext: String, in dir: URL) -> String {
        let safeBase = base.isEmpty ? UUID().uuidString : base
        var candidate = "\(safeBase).\(ext)"
        var idx = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = "\(safeBase)-\(idx).\(ext)"
            idx += 1
        }
        return candidate
    }
}
