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

