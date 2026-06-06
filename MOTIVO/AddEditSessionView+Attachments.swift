// CHANGE-ID: 20260605_192500_AESV_AttachmentPass1
// SCOPE: AddEditSessionView — extract attachment viewer/plumbing into AddEditSessionView+Attachments without UI or logic changes.
// SEARCH-TOKEN: 20260605_192500_AESV_AttachmentPass1

import SwiftUI
import CoreData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

// MARK: - Attachment Viewer Request (AESV)
// Atomic presentation payload for AttachmentViewerView.
// This is AESV-scoped and matches PRDV’s launch contract: visual (images+videos) vs audio-only.
struct AESVAttachmentViewerRequest: Identifiable {
    enum Mode {
        case visual
        case audio
    }

    let id = UUID()
    let mode: Mode
    let startIndex: Int

    let imageURLs: [URL]
    let videoURLs: [URL]
    let audioURLs: [URL]
    let viewerAttachmentIDs: [UUID]
}

extension AddEditSessionView {
    // MARK: - Attachments (preload, stage & commit)

    /// Preload existing Core Data attachments so they appear in the grid during Edit (no duplication on save).
    func preloadExistingAttachments() {
        guard let s = session else { return }
        // Try to fetch via relationship; fall back to fetch request if needed.
        var existing: [Attachment] = []
        if let set = s.value(forKey: "attachments") as? Set<Attachment> {
            existing = Array(set)
        } else {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", s.objectID)
            existing = (try? viewContext.fetch(req)) ?? []
        }

        // Sort by createdAt if available for stable order
        existing.sort {
            let a = ($0.value(forKey: "createdAt") as? Date) ?? .distantPast
            let b = ($1.value(forKey: "createdAt") as? Date) ?? .distantPast
            return a < b
        }

        // Map Core Data attachments into staged rows (image data for previews; icons for others).
        for a in existing {
            let kindStr = (a.value(forKey: "kind") as? String) ?? "file"
            let kind = AttachmentKind(rawValue: kindStr) ?? .file
            let id = (a.value(forKey: "id") as? UUID) ?? UUID()

            if let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                if let url = resolveStoredFileURL(at: path) {
                    existingAttachmentURLMap[id] = url
                }
            }


            // For audio attachments, populate the temporary names map used for captions
            if kind == .audio {
                if let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                    let filename = (path as NSString).lastPathComponent
                    let stem = (filename as NSString).deletingPathExtension
                    if !stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let key = "stagedAudioNames_temp"
                        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
                        dict[id.uuidString] = stem
                        UserDefaults.standard.set(dict, forKey: key)
                    }
                }
            }

            var data = Data()
            if kind == .image, let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                if let d = loadImageData(at: path) { data = d }
            }

            // Stage item and remember it's existing to avoid duplication on save.
            let staged = StagedAttachment(id: id, data: data, kind: kind)
            stagedAttachments.append(staged)
            existingAttachmentIDs.insert(id)

            if (a.value(forKey: "isThumbnail") as? Bool) == true {
                // Do not surface an invalid thumbnail if the attachment is private.
                let storedPath = (a.value(forKey: "fileURL") as? String) ?? ""
                let resolvedURL = resolveStoredFileURL(at: storedPath)
                if !isPrivate(id: id, url: resolvedURL) {
                    selectedThumbnailID = id
                }
            }
        }
    }

    
    /// Resolves a stored Attachment.fileURL string into a valid on-disk file URL.
    /// Mirrors the resolution strategy used by loadImageData(at:), but returns URL without loading bytes.
    func resolveStoredFileURL(at pathOrURLString: String) -> URL? {
        let trimmed = pathOrURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fm = FileManager.default

        // Case A: absolute filesystem path
        if trimmed.hasPrefix("/") {
            if fm.fileExists(atPath: trimmed) { return URL(fileURLWithPath: trimmed) }
            if let filename = URL(fileURLWithPath: trimmed).pathComponents.last, !filename.isEmpty {
                let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
                if let hit = docs?.appendingPathComponent(filename), fm.fileExists(atPath: hit.path) { return hit }
            }
        }

        // Case B: URL string (e.g., "file:///...")
        if let url = URL(string: trimmed), url.isFileURL, fm.fileExists(atPath: url.path) {
            return url
        }

        // Case C: relative path previously stored (resolve against Documents directory)
        if !trimmed.contains(":"), !trimmed.hasPrefix("/") {
            if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let hit = docs.appendingPathComponent(trimmed)
                if fm.fileExists(atPath: hit.path) { return hit }
            }
        }

        return nil
    }

/// Attempts to read image bytes from: absolute path → file:// URL → relative path in Documents directory.
    func loadImageData(at pathOrURLString: String) -> Data? {
        let trimmed = pathOrURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        func loadAtAbsolutePath(_ abs: String) -> Data? {
            if FileManager.default.fileExists(atPath: abs) {
                if let ui = UIImage(contentsOfFile: abs) {
                    if let jpg = ui.jpegData(compressionQuality: 0.85) { return jpg }
                }
                if let raw = try? Data(contentsOf: URL(fileURLWithPath: abs)) { return raw }
            }
            return nil
        }

        // Case A: absolute filesystem path
        if trimmed.hasPrefix("/") {
            if let d = loadAtAbsolutePath(trimmed) { return d }
            // Fallback: treat as stale absolute path; try lastPathComponent in Documents
            if let filename = URL(fileURLWithPath: trimmed).pathComponents.last, !filename.isEmpty {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                if let hit = docs?.appendingPathComponent(filename), FileManager.default.fileExists(atPath: hit.path) {
                    if let ui = UIImage(contentsOfFile: hit.path) {
                        if let jpg = ui.jpegData(compressionQuality: 0.85) { return jpg }
                    }
                    if let raw = try? Data(contentsOf: hit) { return raw }
                }
            }
        }

        // Case B: URL string (e.g., "file:///...")
        if let url = URL(string: trimmed), url.isFileURL {
            if let d = loadAtAbsolutePath(url.path) { return d }
            if let raw = try? Data(contentsOf: url) { return raw }
        }

        // Case C: relative path previously stored (resolve against Documents directory)
        if !trimmed.isEmpty, !trimmed.contains(":"), !trimmed.hasPrefix("/") {
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let candidate = docs.appendingPathComponent(trimmed).path
                if let d = loadAtAbsolutePath(candidate) { return d }
            }
        }

        return nil
    }

    func stageData(_ data: Data, kind: AttachmentKind) {
        let id = UUID()
        // For staged videos (e.g. imported from the photo library), write a temporary
        // surrogate file so that VideoPosterView can resolve a real URL and generate
        // a poster frame while we are still in edit mode. This uses the same
        // extension mapping as the persisted attachments.
        if kind == .video {
            let ext: String = (kind == .image ? "jpg" : kind == .audio ? "m4a" : kind == .video ? "mov" : "dat")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString)
                .appendingPathExtension(ext)
            try? data.write(to: tempURL, options: .atomic)
        }
        stagedAttachments.append(StagedAttachment(id: id, data: data, kind: kind))
        // No auto-thumbnail: thumbnail is set only via explicit user intent (⭐).
    }

    func removeStagedAttachment(_ a: StagedAttachment) {
        // If this staged item corresponds to an existing Core Data Attachment, mark it for deletion on save.
        if existingAttachmentIDs.contains(a.id) {
            deletedExistingAttachmentIDs.insert(a.id)
        }

        stagedAttachments.removeAll { $0.id == a.id }
        existingAttachmentIDs.remove(a.id)
        if selectedThumbnailID == a.id {
            // No auto-reassign: removing the thumbnail clears it.
            selectedThumbnailID = nil
        }
        cleanupTempArtifacts_AESV_bestEffort(for: a.id, kind: a.kind)
    }


    func localFileSizeBytes(_ url: URL) -> Int64? {
        // Attempt resource values first (works for many URLs, including security-scoped ones if access is granted).
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = values.fileSize {
            return Int64(fileSize)
        }

        // Fallback to file attributes.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }

        return nil
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    // Preflight publish cap warning (do not block local attach).
                    let limit = Self.publishUploadLimitBytes
                    if let size = localFileSizeBytes(url), size > limit {
                        publishLimitAlertMessage = "This attachment is larger than 50MB and will stay local (it won’t publish)."
                        showPublishLimitAlert = true
                    }

                    let data = try Data(contentsOf: url)
                    let kind = kindForURL(url)
                    stageData(data, kind: kind)
                } catch { print("File import failed for \(url): \(error)") }
            }
        }
    }

    func kindForURL(_ url: URL) -> AttachmentKind {
        let ext = url.pathExtension.lowercased()
        if ["png","jpg","jpeg","heic","heif","gif","bmp","tiff","tif"].contains(ext) { return .image }
        if ["m4a","aac","mp3","wav","aiff","caf"].contains(ext) { return .audio }
        if ["mov","mp4","m4v","avi"].contains(ext) { return .video }
        if ext == "pdf" { return .pdf }
        return .file
    }
    // --- PATCH 8G-AESV: migrate staged privacy → persisted attachment keys ---
    // SEARCH-ANCHOR: func migratePrivacy_AESV(
    func migratePrivacy_AESV(
        fromStagedID stagedID: UUID,
        stagedURL: URL?,
        toNewID newID: UUID,
        newURL: URL?
    ) {
        // Read staged privacy (default=true → private unless explicitly included)
        let stagedIsPrivate = AttachmentPrivacy.isPrivate(id: stagedID, url: stagedURL)

        // Write onto persisted attachment keys so backend publish can see it
        if newID != stagedID {
            AttachmentPrivacy.setPrivate(id: newID, url: newURL, stagedIsPrivate)
        }

        // Keep AESV local cache coherent
        privacyMap = AttachmentPrivacy.currentMap()
    }
    // --- end PATCH 8G-AESV ---

    /// Adds only newly staged attachments (not those that originated from Core Data) and updates thumbnail flags for all.
    func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) {
        // Persist renamed audio stems from the viewer (if any)
        let audioNamesDict: [String: String] = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]

        // Determine chosen thumbnail (if any)
        let chosenThumbID = selectedThumbnailID        // NOTE: Do not force a thumbnail when user has cleared ⭐ (PRDV parity).
        // Feed/detail can still *display* a fallback thumb without persisting isThumbnail.
        // if chosenThumbID == nil, imageIDs.count == 1 { chosenThumbID = imageIDs.first }

        // Track rollback closures for files written during this commit attempt
        var rollbacks: [() -> Void] = []
        var createdAttachments: [Attachment] = []

        // 1) Add ONLY newly staged attachments (skip those that were preloaded from Core Data)
        for att in stagedAttachments where existingAttachmentIDs.contains(att.id) == false {
            do {
                let ext: String = {
                    if let surl = surrogateURL(for: att) {
                        let e = surl.pathExtension.lowercased()
                        if !e.isEmpty { return e }
                    }
                    return (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : att.kind == .pdf ? "pdf" : "dat")
                }()
                let suggestedName: String = {
                    switch att.kind {
                    case .audio:
                        // Use renamed audio stem from UserDefaults if provided, otherwise fallback to UUID.
                        let raw = audioNamesDict[att.id.uuidString] ?? ""
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? att.id.uuidString : trimmed
                    case .image, .video, .file, .pdf:
                        // Keep existing behavior for non-audio kinds: use UUID stem
                        return att.id.uuidString
                    }
                }()
                let result = try AttachmentStore.saveDataWithRollback(att.data, suggestedName: suggestedName, ext: ext)
                rollbacks.append(result.rollback)
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                let created = try AttachmentStore.addAttachment(
                    kind: att.kind,
                    filePath: result.path,
                    to: session,
                    isThumbnail: isThumb,
                    ctx: ctx
                )
                createdAttachments.append(created)

                // --- PATCH 8G-AESV: migrate privacy from staged → persisted ---
                let stagedURL = surrogateURL(for: att)
                let persistedURL = resolveStoredFileURL(at: result.path)
                if let newID = created.value(forKey: "id") as? UUID {
                    migratePrivacy_AESV(
                        fromStagedID: att.id,
                        stagedURL: stagedURL,
                        toNewID: newID,
                        newURL: persistedURL
                    )
                }
                // --- end PATCH ---

            } catch {
                // Roll back any files written so far and discard created (unsaved) attachments
                for rb in rollbacks { rb() }
                rollbacks.removeAll()
                for a in createdAttachments { ctx.delete(a) }
                createdAttachments.removeAll()
                print("Attachment commit failed: ", error)
                break
            }
        }

        // 2) Update thumbnail flags across ALL existing attachments to reflect selection
        do {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", session.objectID)
            let existing = try ctx.fetch(req)
            for a in existing {
                let id = (a.value(forKey: "id") as? UUID)
                let isThumb = (id != nil) && (id == chosenThumbID)
                a.setValue(isThumb, forKey: "isThumbnail")
            }
        } catch {
            print("Failed to update thumbnail flags: ", error)
        }

        // Clear the staging area after successful commit creation (actual persistence depends on context.save())
        UserDefaults.standard.removeObject(forKey: "stagedAudioNames_temp")
        stagedAttachments.removeAll()
        existingAttachmentIDs.removeAll()
    }

    // Added helpers for attachment viewer integration:

    func stagedIndexForAttachment_edit(_ target: StagedAttachment) -> Int {
        let images = stagedAttachments.filter { $0.kind == .image }
        let videos = stagedAttachments.filter { $0.kind == .video }
        let audios = stagedAttachments.filter { $0.kind == .audio }
        let combined: [StagedAttachment] = images + videos + audios
        return combined.firstIndex(where: { $0.id == target.id }) ?? -1
    }

    func ensureSurrogateFilesExistForViewer_edit() {
        for att in stagedAttachments {
            // Only create a surrogate when we don't already have a real on-disk URL (existing attachments).
            if existingAttachmentURLMap[att.id] == nil {
                _ = guaranteedSurrogateURL_edit(for: att)
            }
        }
    }

    func viewerURLArrays_edit() -> (images: [URL], videos: [URL], audios: [URL]) {
        let imageURLs: [URL] = stagedAttachments.filter { $0.kind == .image }.compactMap { viewerResolvedURL_edit(for: $0) }
        let videoURLs: [URL] = stagedAttachments.filter { $0.kind == .video }.compactMap { viewerResolvedURL_edit(for: $0) }
        let audioURLs: [URL] = stagedAttachments.filter { $0.kind == .audio }.compactMap { viewerResolvedURL_edit(for: $0) }
        return (imageURLs, videoURLs, audioURLs)
    }
    func formatClipDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    func audioDurationText_edit(for att: StagedAttachment) -> String? {
        guard let url = surrogateURL(for: att) else { return nil }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? att.data.write(to: url, options: .atomic)
        }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return formatClipDuration(seconds)
    }


    func ensureCameraAuthorized(onAuthorized: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            onAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? onAuthorized() : { self.showCameraDeniedAlert = true }() }
            }
        default:
            self.showCameraDeniedAlert = true
        }
    }
    
    @ViewBuilder
    func AttachmentTileContent(att: StagedAttachment) -> some View {
        switch att.kind {
        case .image:
            if let ui = UIImage(data: att.data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary)
            }
        case .audio:
            VStack(spacing: 6) {
                Image(systemName: "waveform").imageScale(.large).foregroundStyle(.secondary)
                // Use the same temporary names map seeded during review/timer if present
                let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                let persistedTitles = loadPersistedAudioTitles()
                let override = (persistedTitles[att.id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let staged = (namesDict[att.id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let caption = !override.isEmpty ? override : staged
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                }
            }
        case .video:
            ZStack {
                VideoPosterView(url: surrogateURL(for: att))
                    .allowsHitTesting(false)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        case .file, .pdf:
            Image(systemName: "doc").imageScale(.large).foregroundStyle(.secondary)
        }
    }

    func surrogateURL(for att: StagedAttachment) -> URL? {
        if let existing = existingSurrogateURL_edit(id: att.id, kind: att.kind) {
            return existing
        }
        let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : att.kind == .pdf ? "pdf" : "dat")
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(att.id.uuidString).\(ext)")
    }

    // MARK: - Trim Persistence Canonicalization (Byte-backed, no-hybrid)
    // Search token: TRIM_NOORPHANS_20260224_125814_TrimPersist_NoOrphans

    func kindScopedTmpExtensions_edit(for kind: AttachmentKind) -> [String] {
        switch kind {
        case .video:
            return ["mov", "mp4"]
        case .audio:
            return ["m4a"]
        case .image:
            return ["jpg"]
        case .file:
            return ["dat"]
        case .pdf:
            return ["pdf"]
        }
    }

    func existingSurrogateURL_edit(id: UUID, kind: AttachmentKind) -> URL? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        for ext in kindScopedTmpExtensions_edit(for: kind) {
            let url = tmp.appendingPathComponent("\(id.uuidString).\(ext)")
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func cleanupSurrogateSiblings_tmpOnly_edit(id: UUID, keepExt: String, kind: AttachmentKind) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let keep = keepExt.lowercased()
        for ext in kindScopedTmpExtensions_edit(for: kind) {
            let e = ext.lowercased()
            guard e != keep else { continue }
            let url = tmp.appendingPathComponent("\(id.uuidString).\(e)")
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    func protectedPersistedAttachmentPaths_edit(for session: Session?) -> Set<String> {
        guard let session else { return [] }
        var out: Set<String> = []
        if let set = session.attachments as? Set<Attachment> {
            for a in set {
                if let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                    out.insert(path)
                }
            }
        }
        // Also protect any currently-adopted URLs in existingAttachmentURLMap (cheap)
        for (_, url) in existingAttachmentURLMap {
            out.insert(url.resolvingSymlinksInPath().path)
        }
        return out
    }

    func bestEffortDeleteNewURLIfSafe_edit(_ newURL: URL, surrogateTarget: URL, protectedPaths: Set<String>) {
        let candidate = newURL.resolvingSymlinksInPath()
        let target = surrogateTarget.resolvingSymlinksInPath()
        guard candidate.path != target.path else { return }
        guard !protectedPaths.contains(candidate.path) else { return }
        try? FileManager.default.removeItem(at: candidate)
    }



    // Local filesystem hygiene hardening (AESV tmp artifacts)
    // - Surrogate URLs: tmp/<attachmentID>.(jpg|mov|m4a|dat)
    // - Audio viewer aliases: tmp/<attachmentID>.m4a (same naming contract)
    // Best-effort only: failures must not affect user-visible behavior.
    func cleanupTempArtifacts_AESV_bestEffort(for id: UUID, kind: AttachmentKind?) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory

        // Limit deletions to tmp only (defensive).
        func tryRemove(_ url: URL) {
            guard url.standardizedFileURL.path.hasPrefix(tmp.standardizedFileURL.path) else { return }
            if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
        }

        if let k = kind {
            let ext: String = (k == .image ? "jpg" : k == .audio ? "m4a" : k == .video ? "mov" : "dat")
            tryRemove(tmp.appendingPathComponent(id.uuidString).appendingPathExtension(ext))
            // For extra safety, remove the audio alias path (same as surrogate when kind == .audio; harmless otherwise).
            tryRemove(tmp.appendingPathComponent(id.uuidString).appendingPathExtension("m4a"))
        } else {
            // Unknown kind: attempt common media extensions (still confined to tmp).
            tryRemove(tmp.appendingPathComponent(id.uuidString).appendingPathExtension("jpg"))
            tryRemove(tmp.appendingPathComponent(id.uuidString).appendingPathExtension("mov"))
            tryRemove(tmp.appendingPathComponent(id.uuidString).appendingPathExtension("m4a"))
            tryRemove(tmp.appendingPathComponent(id.uuidString).appendingPathExtension("dat"))
        }
    }

    func cleanupAllTempArtifacts_AESV_bestEffort() {
        for att in stagedAttachments {
            cleanupTempArtifacts_AESV_bestEffort(for: att.id, kind: att.kind)
        }
    }

    func cancelAndCleanup_AESV_bestEffort() {
        cleanupAllTempArtifacts_AESV_bestEffort()
        dismiss()
    }



    // Step 6A — Viewer population hardening:
    // Ensure a real file exists at the surrogate URL before passing it into AttachmentViewerView.
    
    
    // Step 6D — Viewer alias URL for AESV audio rename contract:
    // AttachmentViewerView maps URL → UUID via URL stem. Existing persisted audio file names may not be UUIDs,
    // so we provide a stable temp alias named <att.id>.m4a that points to the real on-disk file.
    // This is INTERNAL ONLY and must not affect displayed titles.
    func viewerAliasURLForAudio_edit(for att: StagedAttachment) -> URL? {
        guard att.kind == .audio else { return viewerResolvedURL_edit(for: att) }
        guard let source = viewerResolvedURL_edit(for: att) else { return nil }

        let fm = FileManager.default
        let alias = FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension("m4a")

        // If alias already exists and is non-empty, reuse it.
        if fm.fileExists(atPath: alias.path) {
            if let attrs = try? fm.attributesOfItem(atPath: alias.path),
               let n = attrs[.size] as? NSNumber,
               n.intValue > 0 {
                return alias
            }
            try? fm.removeItem(at: alias)
        }

        // If the source is already the alias, we're done.
        if source.standardizedFileURL == alias.standardizedFileURL { return alias }

        // Best-effort copy to the alias path so the viewer URL stem remains the staged UUID.
        do {
            try fm.copyItem(at: source, to: alias)
            return alias
        } catch {
            // Fallback: allow playback from the real URL, but rename mapping may not work.
            return source
        }
    }

// Step 6C — Viewer URL resolution for AESV edit mode:
    // Prefer the persisted on-disk file URL for existing attachments; fall back to a guaranteed surrogate for staged bytes.
    func viewerResolvedURL_edit(for att: StagedAttachment) -> URL? {
        if let existing = existingAttachmentURLMap[att.id], FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        return guaranteedSurrogateURL_edit(for: att)
    }

func guaranteedSurrogateURL_edit(for att: StagedAttachment) -> URL? {
        guard let url = surrogateURL(for: att) else { return nil }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            switch att.kind {
            case .image, .video, .audio:
                do { try att.data.write(to: url, options: .atomic) } catch { return nil }
            case .file, .pdf:
                return nil
            }
        }
        return fm.fileExists(atPath: url.path) ? url : nil
    }


    // CHANGE-ID: 20251229_175900-canShareAESV-typecheckHelper
    // SCOPE: Policy — disable AttachmentViewer share when launched from AddEditSessionView (AESV) by passing canShare: false.
    @ViewBuilder
    func attachmentViewer_AESV(
        imageURLs: [URL],
        startIndex: Int,
        videoURLs: [URL],
        audioURLs: [URL],
        audioTitles: [String],
        req: AESVAttachmentViewerRequest
    ) -> some View {

        AttachmentViewerView(
                                    imageURLs: imageURLs,
                                    startIndex: startIndex,
                                    themeBackground: Color(.systemBackground),
                                    videoURLs: videoURLs,
                                    audioURLs: audioURLs,
                                    audioTitles: audioTitles,
                                    onDelete: { url in
                                        // Map by staged id from surrogate URL stem
                                        let stem = url.deletingPathExtension().lastPathComponent
                                        if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
                                            let removed = stagedAttachments.remove(at: idx)
                                            cleanupTempArtifacts_AESV_bestEffort(for: removed.id, kind: removed.kind)
                                            existingAttachmentIDs.remove(removed.id)
                                            if selectedThumbnailID == removed.id {
                                                // No auto-reassign: removing the thumbnail clears it.
                                                selectedThumbnailID = nil
                                            }
                                        }
                                    },
                                    titleForURL: { url, kind in
                                        let _ = attachmentTitlesRefreshTick
                                        let stem = url.deletingPathExtension().lastPathComponent
                                        switch kind {
                                        case .audio:
                                            let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                                            let persistedTitles = loadPersistedAudioTitles()
                                            let indexInCombined: Int? = {
                                                let all = imageURLs + videoURLs + audioURLs
                                                return all.firstIndex(where: { $0 == url })
                                            }()
                                            guard let idx = indexInCombined, idx >= 0, idx < req.viewerAttachmentIDs.count else {
                                                if let persisted = persistedTitles[stem] {
                                                    let t = persisted.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    return t.isEmpty ? nil : t
                                                }
                                                if let raw = namesDict[stem] {
                                                    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    return t.isEmpty ? nil : t
                                                }
                                                return nil
                                            }
                                            let attID = req.viewerAttachmentIDs[idx]
                                            if let persisted = persistedTitles[attID.uuidString] {
                                                let t = persisted.trimmingCharacters(in: .whitespacesAndNewlines)
                                                return t.isEmpty ? nil : t
                                            }
                                            if let raw = namesDict[attID.uuidString] {
                                                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                                return t.isEmpty ? nil : t
                                            }
                                            if let persisted = persistedTitles[stem] {
                                                let t = persisted.trimmingCharacters(in: .whitespacesAndNewlines)
                                                return t.isEmpty ? nil : t
                                            }
                                            if let raw = namesDict[stem] {
                                                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                                return t.isEmpty ? nil : t
                                            }
                                            return nil
                                        case .video:
                                            let persistedVideoTitles = loadPersistedVideoTitles()
                                            // Determine the index of this URL within the viewer's video section
                                            // The AttachmentViewerView provides (url, kind) but not index directly; infer index within the combined sequence we passed.
                                            // We built `req.viewerAttachmentIDs` to match the order of (imageURLs + videoURLs + audioURLs).
                                            let indexInCombined: Int? = {
                                                let all = imageURLs + videoURLs + audioURLs
                                                return all.firstIndex(where: { $0 == url })
                                            }()
                                            guard let idx = indexInCombined, idx >= 0, idx < req.viewerAttachmentIDs.count else { return nil }
                                            let attID = req.viewerAttachmentIDs[idx]
                                            
                                            if existingAttachmentIDs.contains(attID) {
                                                if let persisted = persistedVideoTitles[attID.uuidString] {
                                                    let t = persisted.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    return t.isEmpty ? nil : t
                                                }
                                                return nil
                                            } else {
                                                let videoDict = (UserDefaults.standard.dictionary(forKey: "stagedVideoTitles_temp") as? [String: String]) ?? [:]
                                                if let raw = videoDict[attID.uuidString] {
                                                    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    return t.isEmpty ? nil : t
                                                }
                                                return nil
                                            }
                                        case .image, .file, .pdf:
                                            return nil
                                        }
                                    }, onRename: { url, newTitle, kind in
                                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                        switch kind {
                                        case .audio:
                                            // Resolve attachment identity by viewer index → ID, then write to staged/persisted stores.
                                            // This avoids relying on URL stem being a UUID (it often isn't once filenames are user-named).
                                            let indexInCombined: Int? = {
                                                let all = imageURLs + videoURLs + audioURLs
                                                return all.firstIndex(where: { $0 == url })
                                            }()
                                            let ids = req.viewerAttachmentIDs
                                            guard let idx = indexInCombined, idx >= 0, idx < ids.count else { return }
                                            let attID = ids[idx]

                                            // Trim user input
                                            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

                                            // Always keep staged map in sync (used for unsaved items and local viewer titles)
                                            var staged = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                                            if trimmed.isEmpty { staged.removeValue(forKey: attID.uuidString) }
                                            else { staged[attID.uuidString] = trimmed }
                                            UserDefaults.standard.set(staged, forKey: "stagedAudioNames_temp")

                                            // For existing attachments, also persist under final attachment UUID so publish can round-trip display_name
                                            if existingAttachmentIDs.contains(attID) {
                                                var persisted = (UserDefaults.standard.dictionary(forKey: "persistedAudioTitles_v1") as? [String: String]) ?? [:]
                                                if trimmed.isEmpty { persisted.removeValue(forKey: attID.uuidString) }
                                                else { persisted[attID.uuidString] = trimmed }
                                                UserDefaults.standard.set(persisted, forKey: "persistedAudioTitles_v1")
                                            }

                                            attachmentTitlesRefreshTick &+= 1
                                        case .video:
                                            // Resolve attachment identity by viewer index → ID, then route to persisted or staged store only.
                                            let indexInCombined: Int? = {
                                                let all = imageURLs + videoURLs + audioURLs
                                                return all.firstIndex(where: { $0 == url })
                                            }()
                                            let ids = req.viewerAttachmentIDs
                                            if let idx = indexInCombined, idx >= 0, idx < ids.count {
                                                let attID = ids[idx]
                                                if existingAttachmentIDs.contains(attID) {
                                                    // Persisted: write/remove only in persistedVideoTitles_v1
                                                    var persisted = (UserDefaults.standard.dictionary(forKey: "persistedVideoTitles_v1") as? [String: String]) ?? [:]
                                                    if trimmed.isEmpty { persisted.removeValue(forKey: attID.uuidString) }
                                                    else { persisted[attID.uuidString] = trimmed }
                                                    UserDefaults.standard.set(persisted, forKey: "persistedVideoTitles_v1")
                                                    attachmentTitlesRefreshTick &+= 1
                                                } else {
                                                    // Staged (unsaved): write/remove only in stagedVideoTitles_temp
                                                    var videoDict = (UserDefaults.standard.dictionary(forKey: "stagedVideoTitles_temp") as? [String: String]) ?? [:]
                                                    if trimmed.isEmpty { videoDict.removeValue(forKey: attID.uuidString) }
                                                    else { videoDict[attID.uuidString] = trimmed }
                                                    UserDefaults.standard.set(videoDict, forKey: "stagedVideoTitles_temp")
                                                    attachmentTitlesRefreshTick &+= 1
                                                }
                                            }
                                            return
                                        case .image, .file, .pdf:
                                            return
                                        }
                                    },
                                    onFavourite: { url in
                                        // Resolve attachment identity by viewer index first, fallback to UUID-from-stem
                                        let all = imageURLs + videoURLs + audioURLs
                                        let attID: UUID? = {
                                            if let idx = all.firstIndex(where: { $0 == url }),
                                               idx >= 0,
                                               idx < req.viewerAttachmentIDs.count {
                                                return req.viewerAttachmentIDs[idx]
                                            }
                                            let stem = url.deletingPathExtension().lastPathComponent
                                            return UUID(uuidString: stem)
                                        }()
                                        guard let id = attID else { return }
                                        if let att = stagedAttachments.first(where: { $0.id == id }) {
                                            // PRDV parity: toggle ⭐ on/off from viewer.
                                            if selectedThumbnailID == att.id {
                                                // Toggle OFF
                                                selectedThumbnailID = nil
                                            } else {
                                                // ⭐ implies 👁 — starring auto-includes.
                                                let fileURL: URL? = surrogateURL(for: att)
                                                let privNow = isPrivate(id: att.id, url: fileURL)
                                                if privNow {
                                                    setPrivate(id: att.id, url: fileURL, false)
                                                }
                                                // Toggle ON
                                                selectedThumbnailID = att.id
                                            }
                                        }
                                    },
                                    isFavourite: { url in
                                        let all = imageURLs + videoURLs + audioURLs
                                        let attID: UUID? = {
                                            if let idx = all.firstIndex(where: { $0 == url }),
                                               idx >= 0,
                                               idx < req.viewerAttachmentIDs.count {
                                                return req.viewerAttachmentIDs[idx]
                                            }
                                            let stem = url.deletingPathExtension().lastPathComponent
                                            return UUID(uuidString: stem)
                                        }()
                                        guard let id = attID else { return false }
                                        guard stagedAttachments.contains(where: { $0.id == id }) else { return false }
                                        return selectedThumbnailID == id
                                    },
                                    onTogglePrivacy: { url in
    // Resolve attachment identity by viewer index first (matches imageURLs+videoURLs+audioURLs),
    // falling back to UUID-from-stem when possible.
    let attID: UUID? = {
        let all = imageURLs + videoURLs + audioURLs
        if let idx = all.firstIndex(where: { $0 == url }),
           idx >= 0,
           idx < req.viewerAttachmentIDs.count {
            return req.viewerAttachmentIDs[idx]
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem)
    }()
    guard let id = attID else { return }
    let priv = isPrivate(id: id, url: url)
    let newPriv = !priv
    if newPriv, selectedThumbnailID == id {
        // Making thumbnail private clears ⭐.
        selectedThumbnailID = nil
    }
    setPrivate(id: id, url: url, newPriv)
},
isPrivate: { url in
    let attID: UUID? = {
        let all = imageURLs + videoURLs + audioURLs
        if let idx = all.firstIndex(where: { $0 == url }),
           idx >= 0,
           idx < req.viewerAttachmentIDs.count {
            return req.viewerAttachmentIDs[idx]
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem)
    }()
    // Default is private when identity cannot be resolved.
    guard let id = attID else { return true }
    return isPrivate(id: id, url: url)
},

                                    onReplaceAttachment: { originalURL, newURL, kind in
                                        // Replace should preserve attachment identity.

                                        if let (attID, _) = existingAttachmentURLMap.first(where: { $0.value.standardizedFileURL == originalURL.standardizedFileURL }) {
                                            existingAttachmentURLMap[attID] = newURL
        
                                            // Persistence deferred to save() to avoid SessionDetailView dismissal.
                                            /*
                                            // Persist the new file path to Core Data so future loads resolve correctly.
                                            let req = NSFetchRequest<Attachment>(entityName: "Attachment")
                                            req.predicate = NSPredicate(format: "id == %@", attID as CVarArg)
                                            req.fetchLimit = 1
                                            if let hit = try? viewContext.fetch(req).first {
                                                hit.fileURL = newURL.path
                                                viewContext.processPendingChanges()
                                            }
        
                                            #if canImport(UIKit)
                                            if kind == .video {
                                                _ = AttachmentStore.generateVideoPoster(url: newURL)
                                            }
                                            #endif
                                            */
                                        } else {
                                            // Fallback: this may be a newly-staged (not-yet-persisted) item. Update staged bytes by id-stem.
                                            let stem = originalURL.deletingPathExtension().lastPathComponent
                                            if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
                                                let protectedPaths = protectedPersistedAttachmentPaths_edit(for: session)

                                                guard let data = try? Data(contentsOf: newURL) else { return }
                                                let old = stagedAttachments[idx]

                                                let extCandidate = newURL.pathExtension.lowercased()
                                                let ext: String
                                                if !extCandidate.isEmpty {
                                                    ext = extCandidate
                                                } else {
                                                    ext = (old.kind == .image ? "jpg" : old.kind == .audio ? "m4a" : old.kind == .video ? "mov" : old.kind == .pdf ? "pdf" : "dat")
                                                }

                                                let surrogateTarget = FileManager.default.temporaryDirectory.appendingPathComponent("\(old.id.uuidString).\(ext)")

                                                // Ordering: read bytes (above) → write surrogate successfully → update staged state → cleanup → delete newURL (if safe)
                                                do {
                                                    try data.write(to: surrogateTarget, options: .atomic)
                                                } catch {
                                                    return
                                                }

                                                stagedAttachments[idx] = StagedAttachment(id: old.id, data: data, kind: old.kind)

                                                cleanupSurrogateSiblings_tmpOnly_edit(id: old.id, keepExt: ext, kind: old.kind)
                                                bestEffortDeleteNewURLIfSafe_edit(newURL, surrogateTarget: surrogateTarget, protectedPaths: protectedPaths)
                                            }
                                        }
        
                                    },
                                    onSaveAsNewAttachment: { newURL, kind in
                                        let protectedPaths = protectedPersistedAttachmentPaths_edit(for: session)

                                        // Append a new staged item of provided kind after current index section-wise
                                        let newID = UUID()
                                        guard let data = try? Data(contentsOf: newURL) else { return }

                                        let extCandidate = newURL.pathExtension.lowercased()
                                        let ext: String
                                        if !extCandidate.isEmpty {
                                            ext = extCandidate
                                        } else {
                                            ext = (kind == .image ? "jpg" : kind == .audio ? "m4a" : kind == .video ? "mov" : "dat")
                                        }

                                        let surrogateTarget = FileManager.default.temporaryDirectory.appendingPathComponent("\(newID.uuidString).\(ext)")

                                        // Ordering: read bytes (above) → write surrogate successfully → insert staged state → cleanup → delete newURL (if safe)
                                        do {
                                            try data.write(to: surrogateTarget, options: .atomic)
                                        } catch {
                                            return
                                        }

                                        // Naming-only: for Audio "Save as new", retain the source title and append an incrementing suffix.
                                        /// This seeds stagedAudioNames_temp for the new staged UUID so both AESV inline list and AVV show the right name.
                                        if kind == .audio {
                                            if let req = viewerRequest,
                                               req.mode == .audio,
                                               req.startIndex >= 0,
                                               req.startIndex < req.viewerAttachmentIDs.count {
                                                let sourceID = req.viewerAttachmentIDs[req.startIndex]
                                                let sourceKey = sourceID.uuidString

                                                let namesKey = "stagedAudioNames_temp"
                                                var namesDict = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
                                                let persistedTitles = loadPersistedAudioTitles()

                                                let baseRaw: String? = {
                                                    if let p = persistedTitles[sourceKey] { return p }
                                                    if let s = namesDict[sourceKey] { return s }
                                                    return nil
                                                }()
                                                if let baseRaw {
                                                    let base = baseRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    if !base.isEmpty {
                                                        let existingTitles = Set(namesDict.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                                                        var n = 1
                                                        var candidate = "\(base)_\(n)"
                                                        while existingTitles.contains(candidate) {
                                                            n += 1
                                                            candidate = "\(base)_\(n)"
                                                        }
                                                        namesDict[newID.uuidString] = candidate
                                                        UserDefaults.standard.set(namesDict, forKey: namesKey)
                                                        attachmentTitlesRefreshTick &+= 1
                                                    }
                                                }
                                            }
                                        }


let newAtt = StagedAttachment(id: newID, data: data, kind: kind)

                                        #if canImport(UIKit)
                                        if kind == .video {
                                            _ = AttachmentStore.generateVideoPoster(url: surrogateTarget)
                                        }
                                        #endif

switch kind {
                                        case .image:
                                            if let splitIndex = stagedAttachments.firstIndex(where: { $0.kind != .image }) {
                                                stagedAttachments.insert(newAtt, at: splitIndex)
                                            } else { stagedAttachments.append(newAtt) }
                                        case .video:
                                            let lastVideoIndex = stagedAttachments.lastIndex(where: { $0.kind == .video })
                                            if let lastVideoIndex { stagedAttachments.insert(newAtt, at: lastVideoIndex + 1) }
                                            else if let lastImageIndex = stagedAttachments.lastIndex(where: { $0.kind == .image }) { stagedAttachments.insert(newAtt, at: lastImageIndex + 1) }
                                            else { stagedAttachments.append(newAtt) }
                                        case .audio:
                                            let lastAudioIndex = stagedAttachments.lastIndex(where: { $0.kind == .audio })
                                            if let lastAudioIndex { stagedAttachments.insert(newAtt, at: lastAudioIndex + 1) } else { stagedAttachments.append(newAtt) }
                                        case .file, .pdf:
                                            stagedAttachments.append(newAtt)
                                        }
                                        cleanupSurrogateSiblings_tmpOnly_edit(id: newID, keepExt: ext, kind: kind)
                                        bestEffortDeleteNewURLIfSafe_edit(newURL, surrogateTarget: surrogateTarget, protectedPaths: protectedPaths)

                                    },
                                    canShare: false,
                                    replaceStrategy: .deferred
                                )
    }
}
#if canImport(UIKit)
import AVKit
fileprivate struct VideoPosterView: View {
    let url: URL?
    @State private var poster: UIImage? = nil
    @State private var isPresenting = false

    var body: some View {
        ZStack {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "film")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { if await resolvedPlayableURL() != nil { isPresenting = true } }
        }
        .sheet(isPresented: $isPresenting) {
            TaskView { // lightweight wrapper to bridge async URL resolution into the sheet
                if let u = await resolvedPlayableURL() { VideoPlayerSheet_AE(url: u) }
            }
        }
        .task(id: url) {
            if poster == nil, let u = await resolvedPlayableURL() {
                await generatePoster(u)
            }
        }
    }

    // Prefer the surrogate temp URL if it exists on disk; otherwise fall back to the persisted file URL if available.
    func resolvedPlayableURL() async -> URL? {
        if let u = url, FileManager.default.fileExists(atPath: u.path) { return u }
        // Attempt to derive from staged id embedded in the surrogate path (..../<uuid>.mov)
        if let u = url, let id = UUID(uuidString: u.deletingPathExtension().lastPathComponent) {
            // Search Core Data for an Attachment with this id to get the persisted file path
            let ctx = PersistenceController.shared.container.viewContext
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.fetchLimit = 1
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let match = try? ctx.fetch(req).first, let stored = match.value(forKey: "fileURL") as? String, !stored.isEmpty {
                // Resolve to a real file URL on disk
                if let direct = URL(string: stored), direct.isFileURL, FileManager.default.fileExists(atPath: direct.path) { return direct }
                if FileManager.default.fileExists(atPath: stored) { return URL(fileURLWithPath: stored) }
                let filename = URL(fileURLWithPath: stored).lastPathComponent
                let fm = FileManager.default
                let dirs: [URL?] = [
                    fm.urls(for: .documentDirectory, in: .userDomainMask).first,
                    fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
                    fm.temporaryDirectory
                ]
                for base in dirs.compactMap({ $0 }) {
                    let candidate = base.appendingPathComponent(filename)
                    if fm.fileExists(atPath: candidate.path) { return candidate }
                }
            }
        }
        return url // last resort
    }

    func generatePoster(_ url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    self.poster = img
                    continuation.resume()
                }
            }
        }
    }
}

// Async-to-View bridge for sheet content
fileprivate struct TaskView<Content: View>: View {
    @ViewBuilder var content: () async -> Content
    @State private var built: Content? = nil
    var body: some View {
        Group { if let built { built } else { ProgressView() } }
            .task { built = await content() }
    }
}

fileprivate struct VideoPlayerSheet_AE: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.player?.isMuted = true
        return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
#endif


