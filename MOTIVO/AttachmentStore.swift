//
//  AttachmentStore.swift
//  MOTIVO
//

import Foundation
import CoreData
import UniformTypeIdentifiers

enum AttachmentKind: String {
    case audio, video, image, file
}

struct AttachmentStore {

    // MARK: - Public API

    static func saveData(_ data: Data, suggestedName: String, ext: String) throws -> String {
        let dir = try ensureDocumentsDir()
        let filename = uniqueFilename(base: suggestedName, ext: ext, in: dir)
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: [.atomic])
        return url.path
    }

    /// Creates and attaches a Core Data `Attachment` to a session.
    /// NOTE: We ONLY set the inverse (`att.session = session`). Core Data keeps the other side in sync.
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
