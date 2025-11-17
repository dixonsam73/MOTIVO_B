import Foundation
import UniformTypeIdentifiers

/// Lightweight reference to a staged media file stored under Application Support/MOTIVO/Staging.
/// Only small metadata is stored in a JSON file under Application Support; raw media bytes are kept on disk.
struct StagedAttachmentRef: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case audio, video, image }
    let id: UUID
    let kind: Kind
    let relativePath: String   // path under Staging (e.g., "2025-11-02/abc123.mp4")
    let createdAt: Date
    var duration: Double?      // seconds, optional
    var posterPath: String?    // relative path to generated thumbnail/poster if any
    // Audio naming: store both auto and user-entered; display prefers user when non-empty
    var audioUserTitle: String?    // set when user edits the title; if empty or nil, fall back to auto
    var audioAutoTitle: String?    // seeded from filename at creation; never overwritten by user edits
    var audioDisplayTitle: String? // denormalized convenience: user if present, else auto (kept in sync on updates)
}

/// StagingStore manages persistence of large staged media outside of UserDefaults.
///
/// - Stores media under Application Support/MOTIVO/Staging
/// - Marks the Staging directory as excluded from iCloud/iTunes backup
/// - Performs file I/O on a background queue
/// - Stores lightweight references (StagedAttachmentRef) in a JSON file "staged.json" under Application Support
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
                    #if DEBUG
                    print("[StagingStore] Saved new item id=\(id) kind=\(kind) target=\(targetURL.path) rel=\(rel)")
                    #endif
                    var newRef = StagedAttachmentRef(id: id, kind: kind, relativePath: rel, createdAt: Date(), duration: duration, posterPath: posterPath, audioUserTitle: nil, audioAutoTitle: nil, audioDisplayTitle: nil)
                    if kind == .audio {
                        let stem = (targetURL.deletingPathExtension().lastPathComponent)
                        let auto = (suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? suggestedName! : stem
                        newRef.audioAutoTitle = auto
                        newRef.audioUserTitle = nil
                        newRef.audioDisplayTitle = auto
                    }

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
                    try moveOrCopy(sourceURL: sourceURL, to: tmp)
                    try fm.replaceItemAt(abs, withItemAt: tmp, backupItemName: nil, options: [.usingNewMetadataOnly])

                    var newRef = ref
                    let finalURL = abs
                    if finalURL.lastPathComponent != abs.lastPathComponent {
                        newRef = StagingStore.refByChangingPath(ref, to: relativePath(for: finalURL))
                    }

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

    static func list() -> [StagedAttachmentRef] { loadRefs() }

    static func update(_ ref: StagedAttachmentRef) {
        var list = loadRefs()
        if let idx = list.firstIndex(where: { $0.id == ref.id }) { list[idx] = ref }
        saveRefs(list)
    }

    static func updateAudioMetadata(id: UUID, title: String?, autoTitle: String?, duration: Double?) {
        var list = loadRefs()
        if let idx = list.firstIndex(where: { $0.id == id }) {
            var r = list[idx]
            if let duration { r.duration = duration }

            if let at = autoTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !at.isEmpty {
                r.audioAutoTitle = at
            }
            if let t = title {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                r.audioUserTitle = trimmed.isEmpty ? nil : trimmed
            }

            if let user = r.audioUserTitle, !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                r.audioDisplayTitle = user
            } else if let auto = r.audioAutoTitle, !auto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                r.audioDisplayTitle = auto
            } else {
                r.audioDisplayTitle = nil
            }

            list[idx] = r
            saveRefs(list)
        }
    }

    static func ref(withId id: UUID) -> StagedAttachmentRef? {
        loadRefs().first(where: { $0.id == id })
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

    static func absoluteURL(for ref: StagedAttachmentRef) -> URL {
        absoluteURL(forRelative: ref.relativePath)
    }

    static func absoluteURL(forRelative relative: String) -> URL {
        baseURL.appendingPathComponent(relative)
    }

    // MARK: - Helpers

    private static func preferredExtension(for source: URL, kind: StagedAttachmentRef.Kind) -> String {
        let ext = source.pathExtension
        if !ext.isEmpty { return ext }
        switch kind {
        case .audio: return "m4a"
        case .video: return "mp4"
        case .image: return "jpg"
        }
    }

    private static func dateFolderName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func relativePath(for url: URL) -> String {
        let base = baseURL.standardizedFileURL
        let std = url.standardizedFileURL
        let path = std.path
        let basePath = base.path
        if path.hasPrefix(basePath) {
            let idx = path.index(path.startIndex, offsetBy: basePath.count + (path.hasSuffix("/") ? 0 : 1))
            return String(path[idx...])
        }
        let day = dateFolderName(Date())
        return day + "/" + url.lastPathComponent
    }

    private static func moveOrCopy(sourceURL: URL, to destURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        do {
            try fm.moveItem(at: sourceURL, to: destURL)
        } catch {
            try fm.copyItem(at: sourceURL, to: destURL)
        }
    }

    private static func refByChangingPath(_ ref: StagedAttachmentRef, to newRelative: String) -> StagedAttachmentRef {
        StagedAttachmentRef(id: ref.id, kind: ref.kind, relativePath: newRelative, createdAt: ref.createdAt, duration: ref.duration, posterPath: ref.posterPath, audioUserTitle: ref.audioUserTitle, audioAutoTitle: ref.audioAutoTitle, audioDisplayTitle: ref.audioDisplayTitle)
    }

    // MARK: - Deletion Helpers (Step 0A — no behaviour changes)

    /// Delete disk files (media + poster) for a set of staged refs. Does not update refs.json.
    static func deleteFiles(for refs: [StagedAttachmentRef]) {
        refs.forEach { deleteFile(for: $0) }
    }

    /// Delete disk files for a single ref. Does not update refs.json.
    static func deleteFile(for ref: StagedAttachmentRef) {
        let fm = FileManager.default
        let abs = absoluteURL(for: ref).standardizedFileURL

        let base = baseURL.standardizedFileURL
        let rootPath = base.path.hasSuffix("/") ? base.path : base.path + "/"

        // Safety guard — never delete anything outside our staging container
        guard abs.path.hasPrefix(rootPath) else {
            #if DEBUG
            print("[StagingStore] deleteFile — refusing to delete outside baseURL: \(abs.path)")
            #endif
            return
        }

        if fm.fileExists(atPath: abs.path) {
            try? fm.removeItem(at: abs)
        }

        if let poster = ref.posterPath {
            let posterURL = absoluteURL(forRelative: poster).standardizedFileURL
            if posterURL.path.hasPrefix(rootPath),
               fm.fileExists(atPath: posterURL.path) {
                try? fm.removeItem(at: posterURL)
            }
        }
    }

    // MARK: - File-backed JSON storage

    private static func refsFileURL() -> URL {
        do {
            try bootstrap()
        } catch {}
        return baseURL.appendingPathComponent("staged.json")
    }

    private static func loadRefs() -> [StagedAttachmentRef] {
        let url = refsFileURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let refs = try JSONDecoder().decode([StagedAttachmentRef].self, from: data)
                var normalized = refs
                for i in normalized.indices {
                    if normalized[i].audioDisplayTitle == nil {
                        if let user = normalized[i].audioUserTitle, !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            normalized[i].audioDisplayTitle = user
                        } else if let auto = normalized[i].audioAutoTitle, !auto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            normalized[i].audioDisplayTitle = auto
                        }
                    }
                }
                return normalized
            } catch {
                return []
            }
        } else {
            let defaultsKey = "stagedAttachments_v2"
            let d = UserDefaults.standard
            if let data = d.data(forKey: defaultsKey) {
                do {
                    let refs = try JSONDecoder().decode([StagedAttachmentRef].self, from: data)
                    saveRefs(refs)
                    d.removeObject(forKey: defaultsKey)
                    #if DEBUG
                    print("[StagingStore] Migrated refs from UserDefaults to file (count: \(refs.count))")
                    #endif
                    var normalized = refs
                    for i in normalized.indices {
                        if normalized[i].audioDisplayTitle == nil {
                            if let user = normalized[i].audioUserTitle, !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                normalized[i].audioDisplayTitle = user
                            } else if let auto = normalized[i].audioAutoTitle, !auto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                normalized[i].audioDisplayTitle = auto
                            }
                        }
                    }
                    return normalized
                } catch {
                    return []
                }
            } else {
                return []
            }
        }
    }

    private static func saveRefs(_ refs: [StagedAttachmentRef]) {
        let url = refsFileURL()
        do {
            let data = try JSONEncoder().encode(refs)
            try data.write(to: url, options: [.atomic])
        } catch {}
    }
}
