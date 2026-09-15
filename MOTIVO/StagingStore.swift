// CHANGE-ID: 20260303_095600_DeleteAccountV2_Stage3_FileWipes
// SCOPE: Delete Account v2 Stage 3 — file wipes helpers (Application Support/MOTIVO/Staging). No behavior changes unless invoked by LocalFactoryReset.
// SEARCH-TOKEN: 20260303_095600-DELETE-ACCOUNT-V2-STAGE3

import Foundation
import UniformTypeIdentifiers

// CHANGE-ID: 20260222_195434_LH_FileHygiene_StagingStore
// SCOPE: Fix1 copy-fallback source cleanup (safe); Fix5 root-path guard for remove(_:)


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

/// C-90 — a staging destination already holds bytes this operation does not own.
enum StagingStoreError: Error, Equatable {
    case destinationExists(String)
}

#if DEBUG
/// C-99 — TEST-ONLY observation and barrier points around the refs load/save.
/// Reached only inside a hosted unit-test run; absent from Release.
enum UnitTestRefsPoint: Hashable {
    case saveNewPlaced(UUID)        // background: after media/poster placement, before the refs load
    case saveNewLoaded(UUID)        // background: immediately after the refs load
    case saveNewCommitted(UUID)     // background: immediately after a successful refs save
    case replaceLoaded(UUID)        // background: immediately after the refs load (extension branch)
    case removeManyFilesDeleted     // main actor: after deleteFiles, before the refs save
}
#endif

/// StagingStore manages persistence of large staged media outside of UserDefaults.
///
/// - Stores media under Application Support/MOTIVO/Staging
/// - Marks the Staging directory as excluded from iCloud/iTunes backup
/// - Performs file I/O on a background queue
/// - Stores lightweight references (StagedAttachmentRef) in a JSON file "staged.json" under Application Support
@MainActor
enum StagingStore {
    // MARK: - Public API

    #if DEBUG
    /// C-90 — TEST-ONLY. A store root used ONLY inside a hosted unit-test run
    /// (`UnitTestHost.isActive`); ignored in every ordinary Debug launch and absent
    /// from Release. Set and cleared by `C90StagingMetadataWriteFailureTests` and
    /// `C99StagingRefsConcurrencyTests` only, never while their store work could still
    /// run — it is process-global and not safe for concurrent test classes.
    nonisolated(unsafe) static var unitTestRootOverride: URL?

    /// C-99 — TEST-ONLY hook, invoked at `UnitTestRefsPoint`s only inside a hosted
    /// unit-test run. Nil everywhere else.
    nonisolated(unsafe) static var unitTestRefsHook: ((UnitTestRefsPoint) -> Void)?

    nonisolated static func unitTestReach(_ point: UnitTestRefsPoint) {
        if UnitTestHost.isActive { unitTestRefsHook?(point) }
    }
    #endif

    /// Base folder: Application Support/MOTIVO/Staging
    nonisolated static var baseURL: URL {
        #if DEBUG
        if UnitTestHost.isActive, let root = unitTestRootOverride { return root }
        #endif
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MOTIVO", isDirectory: true)
                          .appendingPathComponent("Staging", isDirectory: true)
    }

    /// Ensure directory exists and is excluded from backups.
    nonisolated static func bootstrap() throws {
        let fm = FileManager.default
        let dir = baseURL
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Staging is scratch. Backup policy is owned by `BackupPolicy`; the parent
        // `MOTIVO/` directory is excluded at launch, and this is belt-and-braces for the
        // case where staging is bootstrapped before that runs.
        BackupPolicy.exclude(dir)
    }

    /// Save a new staged media by moving/copying from a source URL.
    static func saveNew(from sourceURL: URL,
                        kind: StagedAttachmentRef.Kind,
                        suggestedName: String? = nil,
                        duration: Double? = nil,
                        poster: URL? = nil,
                        id requestedID: UUID? = nil) async throws -> StagedAttachmentRef {
        try bootstrap()
        // C-84 — the caller may name the id, so its in-memory item never re-keys.
        let id = requestedID ?? UUID()
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

                    if fm.fileExists(atPath: targetURL.path) {
                        // Avoid collision by appending UUID
                        targetURL = targetDir.appendingPathComponent("\(baseName)-\(id.uuidString)").appendingPathExtension(ext)
                        // C-90 — never overwrite bytes this call does not own.
                        if fm.fileExists(atPath: targetURL.path) {
                            throw StagingStoreError.destinationExists(relativePath(for: targetURL))
                        }
                    }

                    var posterURL: URL? = nil
                    if let poster {
                        let posterExt = poster.pathExtension.isEmpty ? "jpg" : poster.pathExtension
                        let url = targetDir.appendingPathComponent("\(baseName)_poster").appendingPathExtension(posterExt)
                        // C-90 — an existing poster here may be another item's; refuse rather than delete it.
                        if fm.fileExists(atPath: url.path) {
                            throw StagingStoreError.destinationExists(relativePath(for: url))
                        }
                        posterURL = url
                    }

                    // Move if possible, else copy
                    try moveOrCopy(sourceURL: sourceURL, to: targetURL)

                    // C-90 — from here on, any failure undoes only what THIS call created,
                    // and is reported. It used to report success for a ref never written.
                    var createdPoster: URL? = nil
                    do {
                        var posterPath: String? = nil
                        if let poster, let posterURL {
                            try fm.copyItem(at: poster, to: posterURL)
                            createdPoster = posterURL
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

                        #if DEBUG
                        unitTestReach(.saveNewPlaced(id))
                        #endif
                        // C-99 — the refs load, append and save in ONE critical section, so a
                        // concurrent writer can neither be overwritten by nor overwrite this ref.
                        try withRefsLock {
                            var list = loadRefs()
                            #if DEBUG
                            unitTestReach(.saveNewLoaded(id))
                            #endif
                            list.append(newRef)
                            try saveRefs(list)
                            #if DEBUG
                            unitTestReach(.saveNewCommitted(id))
                            #endif
                        }

                        cont.resume(returning: newRef)
                    } catch {
                        if let createdPoster { try? fm.removeItem(at: createdPoster) }
                        undoPlacement(of: targetURL, source: sourceURL)
                        throw error
                    }
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
                    let newExt = sourceURL.pathExtension
                    var newRef = ref
                    if !newExt.isEmpty && newExt.lowercased() != abs.pathExtension.lowercased() {
                        // C-85 — the file must be named for what it now contains (a trim of
                        // a `.mov` recording is MP4). The new file is placed first, then the
                        // ref points at it, then the old container goes: no step leaves the
                        // recording without a referenced file.
                        let target = abs.deletingPathExtension().appendingPathExtension(newExt)
                        // C-90 — an existing file here may be another staged item's media;
                        // refuse rather than delete it.
                        if fm.fileExists(atPath: target.path) {
                            throw StagingStoreError.destinationExists(relativePath(for: target))
                        }
                        try moveOrCopy(sourceURL: sourceURL, to: target)
                        newRef = StagingStore.refByChangingPath(ref, to: relativePath(for: target))
                        let newRelative = newRef.relativePath
                        do {
                            // C-99 — load, merge and save in one critical section, applying ONLY
                            // the path change to the ref as it is NOW: a rename made after the
                            // caller took `ref` is kept, and no concurrent list write is lost.
                            let merged: StagedAttachmentRef? = try withRefsLock {
                                var list = loadRefs()
                                #if DEBUG
                                unitTestReach(.replaceLoaded(ref.id))
                                #endif
                                guard let idx = list.firstIndex(where: { $0.id == ref.id }) else { return nil }
                                list[idx] = StagingStore.refByChangingPath(list[idx], to: newRelative)
                                try saveRefs(list)
                                return list[idx]
                            }
                            if let merged { newRef = merged }
                        } catch {
                            // C-90 — the ref still names the original, so the original stays.
                            // Undo only the trim this call placed (outside the lock), and report it.
                            undoPlacement(of: target, source: sourceURL)
                            throw error
                        }
                        try? fm.removeItem(at: abs)
                    } else {
                        let dir = abs.deletingLastPathComponent()
                        let tmp = dir.appendingPathComponent(".tmp_\(UUID().uuidString)")
                        if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
                        try moveOrCopy(sourceURL: sourceURL, to: tmp)
                        _ = try fm.replaceItemAt(abs, withItemAt: tmp, backupItemName: nil, options: [.usingNewMetadataOnly])
                        // C-99 — the path is unchanged, so no ref is written. Writing the caller's
                        // `ref` back here used to undo a rename made after the caller took it. The
                        // returned ref is that caller snapshot: its path is current; its other
                        // metadata may not be.
                    }

                    cont.resume(returning: newRef)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        return updated
    }

    static func list() -> [StagedAttachmentRef] { withRefsLock { loadRefs() } }

    /// C-84 / P4 — clean up only what is genuinely abandoned: empty folders, and
    /// refs whose file is already gone. **Unreferenced media is KEPT** —
    /// `saveNew` writes the file before its ref, so a death between the two
    /// leaves a real recording that nothing names, and deleting it would make
    /// that partial commit permanent.
    @discardableResult
    static func cleanupAbandoned() -> (removedFolders: Int, removedRefs: Int) {
        let fm = FileManager.default
        // C-99 — the refs part in one critical section; empty-folder removal stays outside.
        let removedRefs: Int = withRefsLock {
            var list = loadRefs()
            let before = list.count
            list.removeAll { !fm.fileExists(atPath: absoluteURL(for: $0).path) }
            let removed = before - list.count
            if removed > 0 { try? saveRefs(list) }
            return removed
        }

        var removedFolders = 0
        if let items = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for dir in items where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let contents = try? fm.contentsOfDirectory(atPath: dir.path), contents.isEmpty,
                   (try? fm.removeItem(at: dir)) != nil {
                    removedFolders += 1
                }
            }
        }
        return (removedFolders, removedRefs)
    }

    /// C-84 — write (or overwrite) a staged video's poster, so a restore that
    /// decodes nothing still shows the right frame after a trim.
    @discardableResult
    static func writePoster(for id: UUID, jpeg: Data) -> Bool {
        // C-99 — snapshot the ref under the lock, write the JPEG OUTSIDE it, then commit
        // against a fresh load, so the poster write never holds the lock and a concurrent
        // change to the list is not overwritten.
        let snapshot: StagedAttachmentRef? = withRefsLock { loadRefs().first(where: { $0.id == id }) }
        guard let snapshot else { return false }
        let media = absoluteURL(for: snapshot)
        let posterURL = snapshot.posterPath.map { absoluteURL(forRelative: $0) }
            ?? media.deletingLastPathComponent()
                .appendingPathComponent(media.deletingPathExtension().lastPathComponent + "_poster")
                .appendingPathExtension("jpg")
        do {
            try jpeg.write(to: posterURL, options: .atomic)
        } catch {
            return false
        }
        let posterRelative = relativePath(for: posterURL)
        // C-90 — report a failed metadata write. The poster bytes written above are
        // NOT rolled back; `false` does not promise that they were.
        return withRefsLock {
            var list = loadRefs()
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return false }
            list[idx].posterPath = posterRelative
            do { try saveRefs(list) } catch { return false }
            return true
        }
    }

    /// C-99 — serialised with every other refs write. It still writes the CALLER'S
    /// whole ref, so a change made after the caller took it is overwritten (residual
    /// R-c; no production caller).
    static func update(_ ref: StagedAttachmentRef) {
        withRefsLock {
            var list = loadRefs()
            if let idx = list.firstIndex(where: { $0.id == ref.id }) { list[idx] = ref }
            try? saveRefs(list)
        }
    }

    static func updateAudioMetadata(id: UUID, title: String?, autoTitle: String?, duration: Double?) {
        // C-99 — the load, merge and save in one critical section.
        withRefsLock {
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
                try? saveRefs(list)
            }
        }
    }

    static func ref(withId id: UUID) -> StagedAttachmentRef? {
        withRefsLock { loadRefs().first(where: { $0.id == id }) }
    }

    /// Remove ref and delete associated files (media + poster if any).
    static func remove(_ ref: StagedAttachmentRef) {
    let fm = FileManager.default
    let abs = absoluteURL(for: ref).standardizedFileURL

    let base = baseURL.standardizedFileURL
    let rootPath = base.path.hasSuffix("/") ? base.path : base.path + "/"

    // Safety guard — never delete anything outside our staging container
    if abs.path.hasPrefix(rootPath) {
        if fm.fileExists(atPath: abs.path) { try? fm.removeItem(at: abs) }
    } else {
        #if DEBUG
        print("[StagingStore] remove — refusing to delete outside baseURL: \(abs.path)")
        #endif
    }

    if let poster = ref.posterPath {
        let p = absoluteURL(forRelative: poster).standardizedFileURL
        if p.path.hasPrefix(rootPath) {
            if fm.fileExists(atPath: p.path) { try? fm.removeItem(at: p) }
        } else {
            #if DEBUG
            print("[StagingStore] remove — refusing to delete poster outside baseURL: \(p.path)")
            #endif
        }
    }

    // C-99 — the files above are deleted by the caller's paths (residual R-d); the
    // index is updated against a fresh load in one critical section.
    withRefsLock {
        var list = loadRefs()
        list.removeAll { $0.id == ref.id }
        try? saveRefs(list)
    }
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

    nonisolated private static func dateFolderName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    nonisolated private static func relativePath(for url: URL) -> String {
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

    nonisolated private static func moveOrCopy(sourceURL: URL, to destURL: URL) throws {
        let fm = FileManager.default
    if fm.fileExists(atPath: destURL.path) {
        try fm.removeItem(at: destURL)
    }
    do {
        try fm.moveItem(at: sourceURL, to: destURL)
    } catch {
        // Copy fallback. If copy succeeds, best-effort delete the source *only* when it's inside our sandbox roots.
        try fm.copyItem(at: sourceURL, to: destURL)

        // Defensive: avoid deleting any external user-provided file URLs (e.g. from Files / iCloud Drive).
        if shouldDeleteSourceAfterCopyFallback(sourceURL),
           fm.fileExists(atPath: sourceURL.path) {
            do {
                try fm.removeItem(at: sourceURL)
            } catch {
                #if DEBUG
                print("[StagingStore] moveOrCopy — copy succeeded but failed to delete source: \(sourceURL.path) err=\(error)")
                #endif
            }
        } else {
            #if DEBUG
            if !shouldDeleteSourceAfterCopyFallback(sourceURL) {
                print("[StagingStore] moveOrCopy — copy succeeded; refusing to delete non-sandbox source: \(sourceURL.path)")
            }
            #endif
        }
    }
}

    nonisolated private static func shouldDeleteSourceAfterCopyFallback(_ sourceURL: URL) -> Bool {
        let src = sourceURL.standardizedFileURL.path

    // temporaryDirectory is always safe (our process owns it)
    let tmpRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
    if src.hasPrefix(tmpRoot.hasSuffix("/") ? tmpRoot : tmpRoot + "/") { return true }

    // Also allow cleanup within our own container roots
    let roots: [FileManager.SearchPathDirectory] = [.documentDirectory, .cachesDirectory, .applicationSupportDirectory]
    for dir in roots {
        if let root = FileManager.default.urls(for: dir, in: .userDomainMask).first?.standardizedFileURL.path {
            let rp = root.hasSuffix("/") ? root : root + "/"
            if src.hasPrefix(rp) { return true }
        }
    }
    return false
}

    nonisolated private static func refByChangingPath(_ ref: StagedAttachmentRef, to newRelative: String) -> StagedAttachmentRef {
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

    /// Remove multiple staged items by their IDs. Best-effort: missing IDs or files are ignored.
    /// - Behavior:
    ///   - Loads current staged refs from staged.json
    ///   - For each matching id, deletes underlying file(s) from Staging (media + poster)
    ///   - Removes the entry from the in-memory list
    ///   - Persists the updated list back to staged.json
    /// - Safety: never deletes outside the Staging baseURL; ignores missing files; tolerates unknown ids.
    static func removeMany(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        // Build lookup for fast membership test
        let toRemove = Set(ids)

        // C-99 — a locked SNAPSHOT names the refs to delete; their files are deleted
        // outside the lock; the index is then updated against a FRESH load, so a ref
        // committed by another writer meanwhile is not dropped by a stale list.
        let doomed: [StagedAttachmentRef] = withRefsLock { loadRefs().filter { toRemove.contains($0.id) } }
        if doomed.isEmpty { return }

        #if DEBUG
        // Pre-deletion accounting
        let fm = FileManager.default
        var totalBytes: Int64 = 0
        var existingFileCount = 0
        var pathsToDelete: [String] = []

        for ref in doomed {
            let abs = absoluteURL(for: ref).standardizedFileURL
            let path = abs.path
            pathsToDelete.append(path)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                do {
                    let attrs = try fm.attributesOfItem(atPath: path)
                    if let size = attrs[.size] as? NSNumber {
                        totalBytes += size.int64Value
                    }
                    existingFileCount += 1
                } catch {
                    print("[StagingStore] removeMany — failed to read size for: \(path). Error: \(error)")
                }
            } else {
                print("[StagingStore] removeMany — missing file for id=\(ref.id) path=\(path)")
            }

            if let poster = ref.posterPath {
                let posterURL = absoluteURL(forRelative: poster).standardizedFileURL
                let pPath = posterURL.path
                pathsToDelete.append(pPath)
                var pIsDir: ObjCBool = false
                if fm.fileExists(atPath: pPath, isDirectory: &pIsDir), !pIsDir.boolValue {
                    do {
                        let attrs = try fm.attributesOfItem(atPath: pPath)
                        if let size = attrs[.size] as? NSNumber {
                            totalBytes += size.int64Value
                        }
                        existingFileCount += 1
                    } catch {
                        print("[StagingStore] removeMany — failed to read size for poster: \(pPath). Error: \(error)")
                    }
                } else {
                    // Poster missing is not an error, but note it for debugging.
                    print("[StagingStore] removeMany — missing poster for id=\(ref.id) path=\(pPath)")
                }
            }
        }
        #endif

        // Best-effort delete of files
        deleteFiles(for: doomed)
        #if DEBUG
        unitTestReach(.removeManyFilesDeleted)
        #endif

        // Remove from index — a fresh load, filtered to the refs whose files were deleted above.
        // Same-id limitation (R-b): if that id was replaced or re-staged meanwhile, its
        // current ref is still removed and any new file is left unreferenced.
        let gone = Set(doomed.map(\.id))
        withRefsLock {
            var list = loadRefs()
            list.removeAll { gone.contains($0.id) }
            try? saveRefs(list)
        }

        #if DEBUG
        // Post-deletion summary
        let removedCount = doomed.count
        let bytes = totalBytes
        let mb = Double(bytes) / (1024.0 * 1024.0)
        print("[StagingStore] removeMany — requested=\(ids.count), removed=\(removedCount), totalBytes=\(bytes) (~\(String(format: "%.2f", mb)) MB)")
        // Optionally list the paths we attempted to delete for traceability.
        if !pathsToDelete.isEmpty {
            print("[StagingStore] removeMany — paths=\n\(pathsToDelete.joined(separator: "\n"))")
        }
        #endif
    }

    // MARK: - File-backed JSON storage

    nonisolated private static func refsFileURL() -> URL {
        do {
            try bootstrap()
        } catch {}
        return baseURL.appendingPathComponent("staged.json")
    }

    nonisolated private static func loadRefs() -> [StagedAttachmentRef] {
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
                    // C-90 — the defaults key is the only copy until the file is written, so it
                    // is removed only after a successful write. A failed write is caught HERE,
                    // so the decoded refs are still returned below rather than `[]`.
                    do {
                        try saveRefs(refs)
                        d.removeObject(forKey: defaultsKey)
                        #if DEBUG
                        print("[StagingStore] Migrated refs from UserDefaults to file (count: \(refs.count))")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[StagingStore] Migration write failed; legacy key kept: \(error)")
                        #endif
                    }
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

    /// C-99 — ONE process-wide critical section for every refs load → modify → save and
    /// for reads (a load can migrate-write). Never held across media or poster file work,
    /// an `await` or a main-actor hop, and never taken re-entrantly: `loadRefs`/`saveRefs`
    /// do not take it. How long the main thread can wait under contention is NOT bounded
    /// or measured.
    nonisolated(unsafe) private static let refsLock = NSLock()

    nonisolated private static func withRefsLock<T>(_ body: () throws -> T) rethrows -> T {
        refsLock.lock()
        defer { refsLock.unlock() }
        return try body()
    }

    /// C-90 — THROWS. It used to swallow its error, so every writer reported success
    /// for a reference list that was never written. `saveNew`, extension-changing
    /// `replace`, `writePoster` and the legacy migration act on the failure; every
    /// other writer calls it with `try?`, keeping its existing best-effort behaviour —
    /// their metadata durability is NOT addressed by C-90.
    nonisolated private static func saveRefs(_ refs: [StagedAttachmentRef]) throws {
        let url = refsFileURL()
        let data = try JSONEncoder().encode(refs)
        try data.write(to: url, options: [.atomic])
    }

    /// C-90 — undo a placement this call made. If the source still exists (a copy, or a
    /// move whose source removal did not happen) it is never overwritten or deleted:
    /// only the staged copy this call created is removed. If the source is gone, the
    /// file is moved back. If that move fails, the bytes stay where they are
    /// (unreferenced media is kept) and the caller still reports the original error.
    nonisolated private static func undoPlacement(of placed: URL, source: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: source.path) {
            try? fm.removeItem(at: placed)
        } else {
            try? fm.moveItem(at: placed, to: source)
        }
    }

    // MARK: - Delete Account v2 (Local Factory Reset)

    /// Best-effort removal of all staged media and metadata under Application Support/MOTIVO/Staging.
    static func wipeOnDiskForFactoryReset() {
        let fm = FileManager.default
        let dir = baseURL.standardizedFileURL
        do {
            if fm.fileExists(atPath: dir.path) {
                try fm.removeItem(at: dir)
            }
        } catch {
            NSLog("[StagingStore] wipeOnDiskForFactoryReset — failed to remove \(dir.path): \(error)")
        }
    }

}
