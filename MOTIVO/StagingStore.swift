import Foundation
import UniformTypeIdentifiers

/// Lightweight reference to a staged media file stored under Application Support/MOTIVO/Staging.
/// Only small metadata is stored in UserDefaults; raw media bytes are kept on disk.
struct StagedAttachmentRef: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case audio, video, image }
    let id: UUID
    let kind: Kind
    let relativePath: String   // path under Staging (e.g., "2025-11-02/abc123.mp4")
    let createdAt: Date
    var duration: Double?      // seconds, optional
    var posterPath: String?    // relative path to generated thumbnail/poster if any
}

/// StagingStore manages persistence of large staged media outside of UserDefaults.
///
/// - Stores media under Application Support/MOTIVO/Staging
/// - Marks the Staging directory as excluded from iCloud/iTunes backup
/// - Performs file I/O on a background queue
/// - Stores only lightweight references (StagedAttachmentRef) in UserDefaults under key "stagedAttachments_v2"
@MainActor
enum StagingStore {
    // MARK: - Public API

    /// Base folder: Application Support/MOTIVO/Staging
    static var baseURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MOTIVO", isDirectory: true)
                          .appendingPathComponent("Staging", isDirectory: true)
    }

    /// Ensure directory exists and is excluded from backups.
    static func bootstrap() throws {
        let fm = FileManager.default
        let dir = baseURL
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutable = dir
        try mutable.setResourceValues(resourceValues)
    }

    /// Save a new staged media by moving/copying from a source URL.
    /// - Parameters:
    ///   - sourceURL: Source file URL (temporary or external).
    ///   - kind: Media kind (audio, video, image).
    ///   - suggestedName: Optional base name (without extension). If nil, a UUID is used.
    ///   - duration: Optional duration in seconds.
    ///   - poster: Optional poster/thumbnail URL to copy alongside the media.
    /// - Returns: Newly created StagedAttachmentRef stored in UserDefaults.
    static func saveNew(from sourceURL: URL,
                        kind: StagedAttachmentRef.Kind,
                        suggestedName: String? = nil,
                        duration: Double? = nil,
                        poster: URL? = nil) async throws -> StagedAttachmentRef {
        try bootstrap()
        let id = UUID()
        let ext = preferredExtension(for: sourceURL, kind: kind)
        let dayFolder = dateFolderName(Date())
        let targetDir = baseURL.appendingPathComponent(dayFolder, isDirectory: true)

        let ref: StagedAttachmentRef = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let fm = FileManager.default
                    if !fm.fileExists(atPath: targetDir.path) {
                        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                    }

                    let baseName = (suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? suggestedName! : id.uuidString
                    var targetURL = targetDir.appendingPathComponent(baseName).appendingPathExtension(ext)

                    // Move if possible, else copy
                    if fm.fileExists(atPath: targetURL.path) {
                        // Avoid collision by appending UUID
                        targetURL = targetDir.appendingPathComponent("\(baseName)-\(id.uuidString)").appendingPathExtension(ext)
                    }
                    try moveOrCopy(sourceURL: sourceURL, to: targetURL)

                    var posterPath: String? = nil
                    if let poster {
                        let posterExt = poster.pathExtension.isEmpty ? "jpg" : poster.pathExtension
                        let posterURL = targetDir.appendingPathComponent("\(baseName)_poster").appendingPathExtension(posterExt)
                        if fm.fileExists(atPath: posterURL.path) {
                            try? fm.removeItem(at: posterURL)
                        }
                        try fm.copyItem(at: poster, to: posterURL)
                        posterPath = relativePath(for: posterURL)
                    }

                    let rel = relativePath(for: targetURL)
                    let newRef = StagedAttachmentRef(id: id, kind: kind, relativePath: rel, createdAt: Date(), duration: duration, posterPath: posterPath)
                    // Append to UserDefaults
                    var list = loadRefs()
                    list.append(newRef)
                    saveRefs(list)

                    cont.resume(returning: newRef)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        return ref
    }

    /// Atomically replace the file for a given ref with contents from sourceURL. The ref's id remains unchanged.
    static func replace(original ref: StagedAttachmentRef, with sourceURL: URL) async throws -> StagedAttachmentRef {
        try bootstrap()
        let abs = absoluteURL(for: ref)
        let updated: StagedAttachmentRef = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let fm = FileManager.default
                    let dir = abs.deletingLastPathComponent()
                    let tmp = dir.appendingPathComponent(".tmp_\(UUID().uuidString)")
                    if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
                    // Move/copy into tmp first
                    try moveOrCopy(sourceURL: sourceURL, to: tmp)
                    // Atomic replace (URL-based API)
                    try fm.replaceItemAt(abs, withItemAt: tmp, backupItemName: nil, options: [.usingNewMetadataOnly])

                    // Update ref (keep same id). The destination path (abs) remains the same name; only contents changed.
                    var newRef = ref
                    // If, for any reason, the file name changed, recompute the relative path from disk.
                    // In our flow, replaceItemAt keeps the original URL (abs), so this usually won't run.
                    let finalURL = abs
                    if finalURL.lastPathComponent != abs.lastPathComponent {
                        newRef = StagingStore.refByChangingPath(ref, to: relativePath(for: finalURL))
                    }

                    // Persist update
                    var list = loadRefs()
                    if let idx = list.firstIndex(where: { $0.id == ref.id }) { list[idx] = newRef }
                    saveRefs(list)

                    cont.resume(returning: newRef)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        return updated
    }

    /// Return all staged refs from UserDefaults.
    static func list() -> [StagedAttachmentRef] { loadRefs() }

    /// Update a ref in UserDefaults by id.
    static func update(_ ref: StagedAttachmentRef) {
        var list = loadRefs()
        if let idx = list.firstIndex(where: { $0.id == ref.id }) { list[idx] = ref }
        saveRefs(list)
    }

    /// Remove ref and delete associated files (media + poster if any).
    static func remove(_ ref: StagedAttachmentRef) {
        let fm = FileManager.default
        let abs = absoluteURL(for: ref)
        if fm.fileExists(atPath: abs.path) { try? fm.removeItem(at: abs) }
        if let poster = ref.posterPath {
            let p = absoluteURL(forRelative: poster)
            if fm.fileExists(atPath: p.path) { try? fm.removeItem(at: p) }
        }
        var list = loadRefs()
        list.removeAll { $0.id == ref.id }
        saveRefs(list)
    }

    /// Get absolute URL on disk for a ref.
    static func absoluteURL(for ref: StagedAttachmentRef) -> URL {
        absoluteURL(forRelative: ref.relativePath)
    }

    /// Convert a relative path under Staging to an absolute URL.
    static func absoluteURL(forRelative relative: String) -> URL {
        baseURL.appendingPathComponent(relative)
    }

    // MARK: - Helpers (nonisolated where appropriate)

    /// Pick a file extension based on source and kind.
    private static func preferredExtension(for source: URL, kind: StagedAttachmentRef.Kind) -> String {
        let ext = source.pathExtension
        if !ext.isEmpty { return ext }
        switch kind {
        case .audio: return "m4a"
        case .video: return "mp4"
        case .image: return "jpg"
        }
    }

    /// yyyy-MM-dd folder name for grouping staged items by day.
    private static func dateFolderName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Convert an absolute URL under baseURL to a relative path string.
    private static func relativePath(for url: URL) -> String {
        let base = baseURL.standardizedFileURL
        let std = url.standardizedFileURL
        let path = std.path
        let basePath = base.path
        if path.hasPrefix(basePath) {
            let idx = path.index(path.startIndex, offsetBy: basePath.count + (path.hasSuffix("/") ? 0 : 1))
            return String(path[idx...])
        }
        // Fallback: return lastPathComponent (still relative under day folder)
        let day = dateFolderName(Date())
        return day + "/" + url.lastPathComponent
    }

    /// Move if same-volume; else copy.
    private static func moveOrCopy(sourceURL: URL, to destURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        do {
            try fm.moveItem(at: sourceURL, to: destURL)
        } catch {
            // Cross-volume move may fail; fall back to copy
            try fm.copyItem(at: sourceURL, to: destURL)
        }
    }

    /// Replace helper: update only the path of a ref without changing its id.
    private static func refByChangingPath(_ ref: StagedAttachmentRef, to newRelative: String) -> StagedAttachmentRef {
        StagedAttachmentRef(id: ref.id, kind: ref.kind, relativePath: newRelative, createdAt: ref.createdAt, duration: ref.duration, posterPath: ref.posterPath)
    }

    // MARK: - UserDefaults storage

    private static let defaultsKey = "stagedAttachments_v2"

    private static func loadRefs() -> [StagedAttachmentRef] {
        let d = UserDefaults.standard
        guard let data = d.data(forKey: defaultsKey) else { return [] }
        do { return try JSONDecoder().decode([StagedAttachmentRef].self, from: data) }
        catch { return [] }
    }

    private static func saveRefs(_ refs: [StagedAttachmentRef]) {
        let d = UserDefaults.standard
        do {
            let data = try JSONEncoder().encode(refs)
            d.set(data, forKey: defaultsKey)
        } catch {
            // On encoding failure, do not crash; drop the write.
        }
    }
}
