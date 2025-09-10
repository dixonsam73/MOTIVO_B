//
//  AttachmentStore.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 10/09/2025.
//

import Foundation
import CoreData
import UniformTypeIdentifiers

enum AttachmentKind: String {
    case audio, video, image, file
}

enum AttachmentStore {
    // MARK: - Paths

    static func documentsDir() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { throw NSError(domain: "Motivo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Documents dir not found"]) }
        return url
    }

    /// Writes data to Documents and returns the file path string saved in Core Data.
    @discardableResult
    static func saveData(_ data: Data, suggestedName: String, ext: String) throws -> String {
        let safeBase = suggestedName.isEmpty ? UUID().uuidString : suggestedName.replacingOccurrences(of: "/", with: "_")
        let safeExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filename = safeExt.isEmpty ? safeBase : "\(safeBase).\(safeExt)"

        let dest = try documentsDir().appendingPathComponent(filename) // ✅ no UTType overload
        try data.write(to: dest, options: .atomic)
        return dest.path
    }

    /// Utility to register a new Attachment in Core Data for a Session.
    static func addAttachment(kind: AttachmentKind, filePath: String, to session: Session, ctx: NSManagedObjectContext) throws {
        let a = Attachment(context: ctx)
        a.id = UUID()
        a.createdAt = Date()
        a.kind = kind.rawValue
        a.fileURL = filePath
        a.session = session
        try ctx.save()
    }

    /// Resolve a stored file path string to a URL.
    static func url(for filePath: String) -> URL {
        if filePath.hasPrefix("/") {
            return URL(fileURLWithPath: filePath)
        } else if let base = try? documentsDir() {
            return base.appendingPathComponent(filePath)
        } else {
            return URL(fileURLWithPath: filePath)
        }
    }

    // Optional: infer a UTType for later use (sharing, previews, etc.)
    static func type(forPath path: String) -> UTType {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return UTType(filenameExtension: ext) ?? .data
    }
}
