// CHANGE-ID: 20260610_1430_PDFPhase2A
// SCOPE: PDF Scores Phase 2A — metadata-only PDF page selection; staged-to-persisted UUID migration; selected-page viewer routing and display labels.
// SEARCH-TOKEN: 20260610_1430-PDF-PAGE-SELECTION
// CHANGE-ID: 20260607_203500_PRDV_PDFCaptionOutsideTile
// SCOPE: PRDV staged PDF captions sit outside clipped thumbnail tile; no viewer/persistence changes.
// SEARCH-TOKEN: 20260607_203500-PRDV-PDF-CAPTION-OUTSIDE-TILE
// CHANGE-ID: 20260607_1820_PDFViewerParity
// SCOPE: Include staged PDFs in PRDV visual viewer request so they open in PDFScoreView.
// SEARCH-TOKEN: 20260607_1820-PDF-VIEWER-PARITY
// CHANGE-ID: 20260609_201500_PRDV_PDFTitleEditing
// SCOPE: PRDV — route PDF score titles through existing AttachmentViewer rename metadata flow.
// SEARCH-TOKEN: 20260609_201500_PRDV_PDFTitleEditing
// CHANGE-ID: 20260607_1115_AttachmentDisplayName
// SCOPE: Attachment display names for imported PDFs/files; persist optional Attachment.displayName and use it in SessionDetailView.
// SEARCH-TOKEN: 20260607_1115-ATTACHMENT-DISPLAY-NAME
// CHANGE-ID: 20260605_181000_PRDV_AttachmentRequestNameFix
// SCOPE: PostRecordDetailsView+Attachments — extracted PRDV attachment viewer/plumbing only. No UI or logic changes.
// SEARCH-TOKEN: 20260605_181000_PRDV_AttachmentRequestNameFix

import SwiftUI
import CoreData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit
import AVKit

extension PostRecordDetailsView {
    @ViewBuilder
    func attachmentViewerCover(request: PRDVAttachmentViewerRequest) -> some View {
let imageURLs = (request.mode == .visual) ? request.imageURLs : []
let videoURLs = (request.mode == .visual) ? request.videoURLs : []
let audioURLs = (request.mode == .audio) ? request.audioURLs : []
let pdfURLs = (request.mode == .visual) ? request.pdfURLs : []

let combined: [URL] = {
    switch request.mode {
    case .visual:
        return imageURLs + videoURLs + pdfURLs
    case .audio:
        return audioURLs
    }
}()

let startIndex = min(max(request.startIndex, 0), max(combined.count - 1, 0))

let _ = attachmentTitlesRefreshTick
                let audioNamesKey = "stagedAudioNames_temp"
let audioNamesDict = (UserDefaults.standard.dictionary(forKey: audioNamesKey) as? [String: String]) ?? [:]

let videoTitlesKey = "stagedVideoTitles_temp"
let videoTitlesDict = (UserDefaults.standard.dictionary(forKey: videoTitlesKey) as? [String: String]) ?? [:]

AttachmentViewerView(
    imageURLs: imageURLs,
    startIndex: startIndex,
    themeBackground: Color(.systemBackground),
    videoURLs: videoURLs,
    audioURLs: audioURLs,
    pdfURLs: pdfURLs,
    pdfSelectedPagesForURL: { url in
        let stem = url.deletingPathExtension().lastPathComponent
        guard let id = UUID(uuidString: stem) else { return nil }
        return selectedPages(forPDFID: id)
    },
onDelete: { url in
    // Map surrogate URL back to staged attachment by matching staged id in the basename
    let stem = url.deletingPathExtension().lastPathComponent
    if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
        let removed = stagedAttachments[idx]
        // Use existing removal path
        removeStagedAttachment(removed)
        // If this was the current thumbnail, reassign or clear using existing logic
        if selectedThumbnailID == removed.id {
if let nextImage = stagedAttachments.first(where: { $0.kind == .image }) {
selectedThumbnailID = nextImage.id
} else {
selectedThumbnailID = nil
}
        }
        // Dismiss the viewer cleanly
        viewerRequest = nil
    }
},
    titleForURL: { url, kind in
        let stem = url.deletingPathExtension().lastPathComponent
        guard let id = UUID(uuidString: stem) else { return nil }

        switch kind {
        case .audio:
            if let raw = audioNamesDict[id.uuidString] {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? "Audio clip" : t
            }
            return "Audio clip"

        case .video:
            if let raw = videoTitlesDict[id.uuidString] {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return nil

        case .pdf:
            let displayNamesKey = "stagedAttachmentDisplayNames_temp"
            let displayNamesDict = (UserDefaults.standard.dictionary(forKey: displayNamesKey) as? [String: String]) ?? [:]
            if let raw = displayNamesDict[id.uuidString] {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
            let fileName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return fileName.isEmpty ? "PDF Document" : fileName

        case .image, .file:
            return nil
        }
    },
    onRename: { url, newTitle, kind in
        let stem = url.deletingPathExtension().lastPathComponent
        guard let id = UUID(uuidString: stem) else { return }

        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .audio:
            var dict = (UserDefaults.standard.dictionary(forKey: audioNamesKey) as? [String: String]) ?? [:]
            if trimmed.isEmpty { dict.removeValue(forKey: id.uuidString) }
            else { dict[id.uuidString] = trimmed }
            UserDefaults.standard.set(dict, forKey: audioNamesKey)
            attachmentTitlesRefreshTick &+= 1

        case .video:
            var dict = (UserDefaults.standard.dictionary(forKey: videoTitlesKey) as? [String: String]) ?? [:]
            if trimmed.isEmpty { dict.removeValue(forKey: id.uuidString) }
            else { dict[id.uuidString] = trimmed }
            UserDefaults.standard.set(dict, forKey: videoTitlesKey)
            attachmentTitlesRefreshTick &+= 1

        case .pdf:
            var dict = (UserDefaults.standard.dictionary(forKey: "stagedAttachmentDisplayNames_temp") as? [String: String]) ?? [:]
            if trimmed.isEmpty { dict.removeValue(forKey: id.uuidString) }
            else { dict[id.uuidString] = trimmed }
            UserDefaults.standard.set(dict, forKey: "stagedAttachmentDisplayNames_temp")
            attachmentTitlesRefreshTick &+= 1

        case .image, .file:
            break
        }
    },
    onFavourite: { url in
        let stem = url.deletingPathExtension().lastPathComponent
        if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
            toggleThumbnail(att)
        }
    },
    isFavourite: { url in
        let stem = url.deletingPathExtension().lastPathComponent
        if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
            return selectedThumbnailID == att.id
        }
        return false
    },
    onTogglePrivacy: { url in
    // Toggle "shown in post" state (default private) using ID-first key.
    let stem = url.deletingPathExtension().lastPathComponent
    if let staged = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
        let priv = isPrivate(id: staged.id, url: url)
        setPrivate(id: staged.id, url: url, !priv)
        return
    }
    // Fallback: if the URL stem is a UUID but we couldn't find it in stagedAttachments (should be rare), still toggle.
    if let id = UUID(uuidString: stem) {
        let priv = isPrivate(id: id, url: url)
        setPrivate(id: id, url: url, !priv)
    }
},
isPrivate: { url in
    let stem = url.deletingPathExtension().lastPathComponent
    if let staged = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
        return isPrivate(id: staged.id, url: url)
    }
    // Default private if unknown.
    if let id = UUID(uuidString: stem) {
        return isPrivate(id: id, url: url)
    }
    return true
},

    onReplaceAttachment: { originalURL, newURL, kind in
        replaceStagedAttachment(originalURL: originalURL, with: newURL, kind: kind)
    },
    onSaveAsNewAttachment: { newURL, kind in
        // Insert new item after the current one in its section
        insertNewStagedAttachment(after: combined[min(max(startIndex,0), max(combined.count-1,0))], newURL: newURL, kind: kind)
    },
    canShare: false
)
    }

    @ViewBuilder
    var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Attachments").sectionHeader()
            if !stagedAttachments.isEmpty {
                let nonAudio = stagedAttachments.filter { $0.kind != .audio }
                let audioOnly = stagedAttachments.filter { $0.kind == .audio }

                if !nonAudio.isEmpty {
                    let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(nonAudio) { att in
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    AttachmentThumbCell(
                                        att: att,
                                        isThumbnail: selectedThumbnailID == att.id,
                                        onMakeThumbnail: { toggleThumbnail(att) },
                                        onRemove: { removeStagedAttachment(att) },
                                        isPrivate: { id, url in
                                            return isPrivate(id: id, url: url)
                                        },
                                        setPrivate: { id, url, value in
                                            setPrivate(id: id, url: url, value)
                                        }
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                    // Step 3: Visual taps (images + videos + PDFs) present via viewerRequest only.
                                    // Ordering matches the PRDV visual grid (non-audio, non-generic-file attachments in stagedAttachments order).
                                    ensureSurrogateFilesExistForViewer()

                                    let visuals = stagedAttachments.filter { $0.kind != .audio && $0.kind != .file }

                                    let imageURLs: [URL] = visuals.compactMap { item in
                                        guard item.kind == .image else { return nil }
                                        return surrogateURL(for: item)
                                    }

                                    let videoURLs: [URL] = visuals.compactMap { item in
                                        guard item.kind == .video else { return nil }
                                        return surrogateURL(for: item)
                                    }

                                    let pdfURLs: [URL] = visuals.compactMap { item in
                                        guard item.kind == .pdf else { return nil }
                                        return surrogateURL(for: item)
                                    }

                                    let startIndex: Int = {
                                        switch att.kind {
                                        case .image:
                                            let idx = visuals.filter { $0.kind == .image }.firstIndex(where: { $0.id == att.id }) ?? 0
                                            return idx
                                        case .video:
                                            let idx = visuals.filter { $0.kind == .video }.firstIndex(where: { $0.id == att.id }) ?? 0
                                            return imageURLs.count + idx
                                        case .pdf:
                                            let idx = visuals.filter { $0.kind == .pdf }.firstIndex(where: { $0.id == att.id }) ?? 0
                                            return imageURLs.count + videoURLs.count + idx
                                        default:
                                            return 0
                                        }
                                    }()

                                    let orderedVisualIDs: [UUID] = {
                                        let imageIDs: [UUID] = visuals.compactMap { item in
                                            guard item.kind == .image else { return nil }
                                            return item.id
                                        }
                                        let videoIDs: [UUID] = visuals.compactMap { item in
                                            guard item.kind == .video else { return nil }
                                            return item.id
                                        }
                                        let pdfIDs: [UUID] = visuals.compactMap { item in
                                            guard item.kind == .pdf else { return nil }
                                            return item.id
                                        }
                                        return imageIDs + videoIDs + pdfIDs
                                    }()

                                    viewerRequest = PRDVAttachmentViewerRequest(
                                        mode: .visual,
                                        startIndex: startIndex,
                                        imageURLs: imageURLs,
                                        videoURLs: videoURLs,
                                        audioURLs: [],
                                        pdfURLs: pdfURLs,
                                        viewerAttachmentIDs: orderedVisualIDs
                                    )
                                    }
                                }

                                if let caption = stagedAttachmentDisplayName(for: att) {
                                    Text(caption)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 128, alignment: .leading)
                                }

                                if att.kind == .pdf {
                                    Text(PDFSelectedPagesFormatter.summary(for: selectedPages(forPDFID: att.id)))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 128, alignment: .leading)

                                    Button("Select pages") {
                                        let pageCount = PDFSelectedPagesStore.pageCount(for: att.data)
                                        pdfPageSelectionRequest = PDFPageSelectionRequest(id: att.id, pageCount: pageCount)
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, -Theme.Spacing.s)
                }

                if !audioOnly.isEmpty {
                    // Use the same temporary title map as PracticeTimerView (keyed by staged id UUID string)
                    let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(audioOnly) { att in
                            let rawDisplay = namesDict[att.id.uuidString] ?? ""
                            let trimmedDisplay = rawDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
                            let title = trimmedDisplay.isEmpty ? "Audio clip" : trimmedDisplay

                            let url = surrogateURL(for: att)
                            let durationText: String? = {
                                guard let url = url else { return nil }
                                let fm = FileManager.default
                                if !fm.fileExists(atPath: url.path) {
                                    try? att.data.write(to: url, options: .atomic)
                                }
                                let asset = AVURLAsset(url: url)
                                let seconds = CMTimeGetSeconds(asset.duration)
                                guard seconds.isFinite, seconds > 0 else { return nil }
                                return formatClipDuration(seconds)
                            }()

                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    ensureSurrogateFilesExistForViewer()

                                    let audioItems: [(UUID, URL)] = audioOnly.compactMap { item in
                                        guard let url = surrogateURL(for: item) else { return nil }
                                        return (item.id, url)
                                    }
                                    let audioURLs: [URL] = audioItems.map { $0.1 }
                                    let startIndex = audioItems.firstIndex(where: { $0.0 == att.id }) ?? 0

                                    viewerRequest = PRDVAttachmentViewerRequest(
                                        mode: .audio,
                                        startIndex: startIndex,
                                        imageURLs: [],
                                        videoURLs: [],
                                        audioURLs: audioURLs,
                                        pdfURLs: []
                                    )
                                } label: {
                                    HStack(spacing: 8) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 16, weight: .semibold))
                                        .opacity(0.85)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title)
                                            .font(.footnote)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)

                                        if let durationText {
                                            Text(durationText)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Open audio clip \(title)")

                                Spacer(minLength: 8)

                                VStack(spacing: 6) {
                                    // Star (use audio clip as session thumbnail)
                                    Button {
                                        toggleThumbnail(att)
                                    } label: {
                                        Image(systemName: selectedThumbnailID == att.id ? "star.fill" : "star")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(selectedThumbnailID == att.id ? "Unset as thumbnail" : "Set as thumbnail")

                                    // Privacy toggle
                                    let privURL = url
                                    Button {
                                        let current = isPrivate(id: att.id, url: privURL)
                                        setPrivate(id: att.id, url: privURL, !current)
                                    } label: {
                                        let current = isPrivate(id: att.id, url: privURL)
                                        Image(systemName: current ? "eye.slash" : "eye")
                                            .font(.system(size: 16, weight: .semibold))
                                            .opacity(selectedThumbnailID == att.id ? 0 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isPrivate(id: att.id, url: privURL) ? "Mark attachment public" : "Mark attachment private")

                                    // Delete
                                    Button(role: .destructive) {
                                        removeStagedAttachment(att)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete attachment")
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let index = stagedIndexForAttachment(att)
                                if index >= 0 {
                                    viewerStartIndex = index
                                    ensureSurrogateFilesExistForViewer()
                                    isShowingAttachmentViewer = true
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if let warn = stagedSizeWarning {
                Text(warn)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.top, 4)
            }
        }
        .sheet(item: $pdfPageSelectionRequest) { request in
            PDFPageSelectionSheet(
                pageCount: request.pageCount,
                selectedPages: Binding(
                    get: { selectedPages(forPDFID: request.id) },
                    set: { setSelectedPages($0, forPDFID: request.id) }
                )
            )
        }
    }


    func selectedPages(forPDFID id: UUID) -> [Int]? {
        if let staged = stagedAttachments.first(where: { $0.id == id }) {
            return PDFSelectedPagesStore.sanitized(staged.selectedPages ?? PDFSelectedPagesStore.pages(for: id))
        }
        return PDFSelectedPagesStore.pages(for: id)
    }

    func setSelectedPages(_ pages: [Int]?, forPDFID id: UUID) {
        let sanitized = PDFSelectedPagesStore.sanitized(pages)
        if let idx = stagedAttachments.firstIndex(where: { $0.id == id }) {
            stagedAttachments[idx].selectedPages = sanitized
        }
        PDFSelectedPagesStore.setPages(sanitized, for: id)
    }


    func surrogateURL(for att: StagedAttachment) -> URL? {
        // Surrogate URLs live in tmp and must preserve the most recently written extension
        // for this staged UUID (video: mov/mp4; audio: m4a; image: jpg).
        if let existing = existingSurrogateURL_tmpOnly(id: att.id, kind: att.kind) {
            return existing
        }
        let ext = defaultSurrogateExtension(for: att.kind)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension(ext)
    }

    func defaultSurrogateExtension(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "jpg"
        case .audio: return "m4a"
        case .video: return "mov"
        case .file:  return "dat"
        case .pdf:   return "pdf"
        }
    }

    func kindScopedTmpExtensions_tmpOnly(for kind: AttachmentKind) -> [String] {
        switch kind {
        case .image: return ["jpg"]
        case .audio: return ["m4a"]
        case .video: return ["mov", "mp4"]
        case .file:  return ["dat"]
        case .pdf:   return ["pdf"]
        }
    }

    func existingSurrogateURL_tmpOnly(id: UUID, kind: AttachmentKind) -> URL? {
        let tmp = FileManager.default.temporaryDirectory
        for ext in kindScopedTmpExtensions_tmpOnly(for: kind) {
            let u = tmp.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    func cleanupSurrogateSiblings_tmpOnly(id: UUID, keepExt: String, kind: AttachmentKind) {
        let tmp = FileManager.default.temporaryDirectory
        for ext in kindScopedTmpExtensions_tmpOnly(for: kind) where ext.lowercased() != keepExt.lowercased() {
            let u = tmp.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: u)
        }
    }

    func isPathReferencedInCoreData(_ path: String) -> Bool {
        // Safety constraint: never delete a URL that is already referenced by any Attachment.fileURL.
        // Cheap check: exact match on stored fileURL string.
        let req = NSFetchRequest<NSManagedObject>(entityName: "Attachment")
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "fileURL == %@", path)
        do {
            let hits = try viewContext.fetch(req)
            return !hits.isEmpty
        } catch {
            return false
        }
    }

    func bestEffortDeleteNewURLIfSafe(newURL: URL, surrogateTarget: URL) {
        // Safety constraint:
        // - only delete after surrogate write succeeded (caller responsibility)
        // - never delete if it equals surrogate target
        // - never delete if Core Data already references this path as Attachment.fileURL
        let candidate = newURL.resolvingSymlinksInPath()
        let surrogate = surrogateTarget.resolvingSymlinksInPath()
        if candidate.path == surrogate.path { return }
        if isPathReferencedInCoreData(candidate.path) { return }
        try? FileManager.default.removeItem(at: candidate)
    }


    // CHANGE-ID: 20260105_prdv_star_toggle_sync
    // SCOPE: PRDV attachments card star toggle must be bidirectional and consistent with AttachmentViewerView.
    func toggleThumbnail(_ att: StagedAttachment) {
        guard let url = surrogateURL(for: att) else { return }
        if selectedThumbnailID == att.id {
            selectedThumbnailID = nil
            return
        }
        // ⭐ implies 👁 (thumbnail implies included)
        if isPrivate(id: att.id, url: url) {
            setPrivate(id: att.id, url: url, false)
        }
        selectedThumbnailID = att.id
    }


    func stageData(_ data: Data, kind: AttachmentKind, displayName: String? = nil) {
        let id = UUID()

        let finalData: Data
        if kind == .image {
            finalData = clampImageDataIfNeeded(data, maxDimension: 2048, jpegQuality: 0.8)
        } else {
            finalData = data
        }

        stagedAttachments.append(StagedAttachment(id: id, data: finalData, kind: kind))

        if kind == .file || kind == .pdf {
            let trimmed = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let displayNamesKey = "stagedAttachmentDisplayNames_temp"
                var displayNames = (UserDefaults.standard.dictionary(forKey: displayNamesKey) as? [String: String]) ?? [:]
                displayNames[id.uuidString] = trimmed
                UserDefaults.standard.set(displayNames, forKey: displayNamesKey)
            }
        }

        if kind == .image {
            let imageCount = stagedAttachments.filter { $0.kind == .image }.count
            if imageCount == 1 { selectedThumbnailID = id }
        }
    }

    func clampImageDataIfNeeded(_ data: Data, maxDimension: CGFloat, jpegQuality: CGFloat) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxDimension, longest > 0 else { return data }

        let scale = maxDimension / longest
        let newSize = CGSize(width: max(1, floor(w * scale)), height: max(1, floor(h * scale)))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // pixel-accurate output
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: jpegQuality) ?? data
    }


    func removeStagedAttachment(_ a: StagedAttachment) {
        PDFSelectedPagesStore.setPages(nil, for: a.id)
        stagedAttachments.removeAll { $0.id == a.id }
        if selectedThumbnailID == a.id {
            selectedThumbnailID = stagedAttachments.first(where: { $0.kind == .image })?.id
        }
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let kind = kindForURL(url)
                    let displayName = userFacingDisplayName(for: url)
                    stageData(data, kind: kind, displayName: displayName)
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

    func userFacingDisplayName(for url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
        let trimmedStem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStem.isEmpty { return trimmedStem }

        let fallback = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    func stagedAttachmentDisplayName(for att: StagedAttachment) -> String? {
        guard att.kind == .pdf else { return nil }

        let displayNamesKey = "stagedAttachmentDisplayNames_temp"
        let displayNamesDict = (UserDefaults.standard.dictionary(forKey: displayNamesKey) as? [String: String]) ?? [:]
        let trimmed = (displayNamesDict[att.id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }


    func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) {
        let chosenThumbID = selectedThumbnailID
        // Ensure thumbnail implies included (staged privacy) before migration/commit
        if let tid = chosenThumbID, let thumb = stagedAttachments.first(where: { $0.id == tid }) {
            setPrivate(id: tid, url: surrogateURL(for: thumb), false)
        }

        // Map staged UUID → final Attachment UUID (used to persist isThumbnail correctly)
        var stagedToFinalID: [UUID: UUID] = [:]
        

        // Map staged UUID → final file URL (used to persist privacy on final keys)
        var stagedToFinalURL: [UUID: URL] = [:]
let namesKey = "stagedAudioNames_temp"
        let namesDict = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        let displayNamesKey = "stagedAttachmentDisplayNames_temp"
        let displayNamesDict = (UserDefaults.standard.dictionary(forKey: displayNamesKey) as? [String: String]) ?? [:]

        // Read staged video titles captured during timer flow and define persisted store key
        let stagedVideoTitlesKey = "stagedVideoTitles_temp"
        let stagedVideoTitles: [String: String] = (UserDefaults.standard.dictionary(forKey: stagedVideoTitlesKey) as? [String: String]) ?? [:]
        let persistedVideoTitlesKey = "persistedVideoTitles_v1"
        let persistedAudioTitlesKey = "persistedAudioTitles_v1"

        // Track rollback closures for files written during this commit attempt
        var rollbacks: [() -> Void] = []
        var createdAttachments: [Attachment] = []

        // 1) Write files using rollback-safe API and create Attachment objects
        for att in stagedAttachments {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : att.kind == .pdf ? "pdf" : "dat")
                let baseName: String
                if let custom = namesDict[att.id.uuidString], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    baseName = custom
                } else {
                    baseName = att.id.uuidString
                }
                let result = try AttachmentStore.saveDataWithRollback(att.data, suggestedName: baseName, ext: ext)
                rollbacks.append(result.rollback)

                let displayName = displayNamesDict[att.id.uuidString]
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                let created: Attachment = try AttachmentStore.addAttachment(kind: att.kind, filePath: result.path, to: session, isThumbnail: isThumb, displayName: displayName, ctx: ctx)
                if let finalID = (created.value(forKey: "id") as? UUID) {
                    stagedToFinalID[att.id] = finalID
                    PDFSelectedPagesStore.migratePages(from: att.id, stagedPages: att.selectedPages, to: finalID)
                }


                // Attempt to migrate privacy from staged keys (ID/Temp URL) to final keys (ID/File URL)
                let finalURL = URL(fileURLWithPath: result.path)
                
                stagedToFinalURL[att.id] = finalURL
let stagedURL = surrogateURL(for: att)
                migratePrivacy(fromStagedID: att.id, stagedURL: stagedURL, toNewID: (created.value(forKey: "id") as? UUID), newURL: finalURL)
                // Persist any staged AUDIO title so publish pipeline can round-trip it (remote display_name)
                if att.kind == .audio {
                    let stagedKey = att.id.uuidString
                    if let stagedTitleRaw = namesDict[stagedKey] {
                        let trimmed = stagedTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if let finalID = created.value(forKey: "id") as? UUID {
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
                                persisted[finalID.uuidString] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedAudioTitlesKey)
                            } else {
                                // Fallback (should be rare): key by saved filename stem
                                let stem = URL(fileURLWithPath: result.path).deletingPathExtension().lastPathComponent
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
                                persisted[stem] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedAudioTitlesKey)
                            }
                        }
                    }
                }
                // Persist any staged video title so SessionDetailView can surface it later
                if att.kind == .video {
                    let stagedKey = att.id.uuidString
                    if let stagedTitleRaw = stagedVideoTitles[stagedKey] {
                        let trimmed = stagedTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            // Store under the final attachment UUID (preferred) if available; else fall back to file path stem
                            if let finalID = created.value(forKey: "id") as? UUID {
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedVideoTitlesKey) as? [String: String]) ?? [:]
                                persisted[finalID.uuidString] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedVideoTitlesKey)
                            } else {
                                // Fallback: use the created file path stem as a last resort
                                let stem = URL(fileURLWithPath: result.path).deletingPathExtension().lastPathComponent
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedVideoTitlesKey) as? [String: String]) ?? [:]
                                persisted[stem] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedVideoTitlesKey)
                            }
                        }
                    }
                }

                createdAttachments.append(created)
            } catch {
                // If any write/add fails mid-loop, best-effort rollback files written so far and clear created objects from the context
                for rb in rollbacks { rb() }
                rollbacks.removeAll()
                // Delete any created attachments from the context (unsaved yet)
                for a in createdAttachments { ctx.delete(a) }
                createdAttachments.removeAll()
                print("Attachment commit failed: ", error)
                break
            }
        }

        // Resolve staged thumbnail UUID to final Attachment UUID
        let chosenFinalThumbID: UUID? = chosenThumbID.flatMap { stagedToFinalID[$0] }


        

        // Persist inclusion on FINAL keys for the chosen thumbnail attachment (ContentView relies on final URL keys)
        if let stagedID = chosenThumbID,
           let finalID = chosenFinalThumbID,
           let finalURL = stagedToFinalURL[stagedID] {
            setPrivate(id: finalID, url: finalURL, false)
        }
// 2) Update thumbnail flags across ALL attachments in this session to reflect selection
        do {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", session.objectID)
            let existing = try ctx.fetch(req)
            for a in existing {
                let id = (a.value(forKey: "id") as? UUID)
                let isThumb = (id != nil) && (id == chosenFinalThumbID)
                a.setValue(isThumb, forKey: "isThumbnail")
            }
        } catch {
            // If thumbnail update fails before save, it will be covered by context save error handling outside.
            print("Failed to update thumbnail flags: ", error)
        }

        // Note: Do not save the context here; caller will attempt save and handle rollback of files on failure.
        UserDefaults.standard.removeObject(forKey: namesKey)
        UserDefaults.standard.removeObject(forKey: displayNamesKey)
        UserDefaults.standard.removeObject(forKey: stagedVideoTitlesKey)
    }

    func stagedIndexForAttachment(_ target: StagedAttachment) -> Int {
        let images = stagedAttachments.filter { $0.kind == .image }
        let videos = stagedAttachments.filter { $0.kind == .video }
        let audios = stagedAttachments.filter { $0.kind == .audio }
        let combined: [StagedAttachment] = images + videos + audios
        return combined.firstIndex(where: { $0.id == target.id }) ?? -1
    }

    func ensureSurrogateFilesExistForViewer() {
        let fm = FileManager.default
        for att in stagedAttachments {
            guard let url = surrogateURL(for: att) else { continue }
            if !fm.fileExists(atPath: url.path) {
                switch att.kind {
                case .image, .video, .audio, .pdf:
                    // Write the staged bytes to the surrogate temp URL so the viewer can load by URL
                    try? att.data.write(to: url, options: .atomic)
                case .file:
                    // Generic files are not displayed in the full-screen media viewer
                    break
                }
            }
        }
    }

    func viewerURLArrays() -> (images: [URL], videos: [URL], audios: [URL], pdfs: [URL]) {
        let imageURLs: [URL] = stagedAttachments.filter { $0.kind == .image }.compactMap { surrogateURL(for: $0) }
        let videoURLs: [URL] = stagedAttachments.filter { $0.kind == .video }.compactMap { surrogateURL(for: $0) }
        let audioURLs: [URL] = stagedAttachments.filter { $0.kind == .audio }.compactMap { surrogateURL(for: $0) }
        let pdfURLs: [URL] = stagedAttachments.filter { $0.kind == .pdf }.compactMap { surrogateURL(for: $0) }
        return (imageURLs, videoURLs, audioURLs, pdfURLs)
    }

    func replaceStagedAttachment(originalURL: URL, with newURL: URL, kind: AttachmentKind) {
        // Match by surrogate URL basename (staged id)
        let stem = originalURL.deletingPathExtension().lastPathComponent
        guard let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) else { return }

        // Replace bytes by reading from newURL; keep id stable (and keep kind stable from the existing staged item).
        guard let data = try? Data(contentsOf: newURL) else { return }
        var att = stagedAttachments[idx]
        att = StagedAttachment(id: att.id, data: data, kind: att.kind)
        stagedAttachments[idx] = att

        // Surrogate extension must follow the source/export type.
        let ext = {
            let e = newURL.pathExtension.lowercased()
            return e.isEmpty ? defaultSurrogateExtension(for: att.kind) : e
        }()
        let surrogateTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension(ext)

        // Write the staged bytes to the surrogate temp URL so the viewer can load by URL.
        do {
            try att.data.write(to: surrogateTarget, options: .atomic)
            // tmp-only sibling cleanup (kind-scoped)
            cleanupSurrogateSiblings_tmpOnly(id: att.id, keepExt: ext, kind: att.kind)
            // Best-effort delete newURL after surrogate write succeeds (even if in Documents),
            // but only if safe (not surrogate target, not referenced by Core Data).
            bestEffortDeleteNewURLIfSafe(newURL: newURL, surrogateTarget: surrogateTarget)
        } catch {
            // Preserve prior behavior: fail silently on write errors.
        }
    }

    func insertNewStagedAttachment(after originalURL: URL, newURL: URL, kind: AttachmentKind) {
        // Insert a new staged item of the provided kind, with a new UUID
        let newID = UUID()
        let data = (try? Data(contentsOf: newURL)) ?? Data()
        let newAtt = StagedAttachment(id: newID, data: data, kind: kind)

        // Compute gallery ordering position: after the tapped item within its section
        let images = stagedAttachments.filter { $0.kind == .image }
        let videos = stagedAttachments.filter { $0.kind == .video }
        let audios = stagedAttachments.filter { $0.kind == .audio }
        let combined: [StagedAttachment] = images + videos + audios
        let stem = originalURL.deletingPathExtension().lastPathComponent
        let currentIndex = combined.firstIndex(where: { $0.id.uuidString == stem }) ?? (combined.count - 1)

        switch kind {
        case .image:
            // Append to end of images
            if let splitIndex = stagedAttachments.firstIndex(where: { $0.kind != .image }) {
                stagedAttachments.insert(newAtt, at: splitIndex)
            } else {
                stagedAttachments.append(newAtt)
            }

        case .video:
            // Insert after current video within videos section
            let videosOnly = stagedAttachments.enumerated().filter { $0.element.kind == .video }
            let currentVideoIndexInVideos: Int? = {
                if combined.indices.contains(currentIndex) {
                    let currentItem = combined[currentIndex]
                    if currentItem.kind == .video {
                        return videosOnly.firstIndex(where: { $0.element.id == currentItem.id })
                    }
                }
                return nil
            }()
            if let cv = currentVideoIndexInVideos {
                let insertAt = videosOnly[cv].offset + 1
                stagedAttachments.insert(newAtt, at: insertAt)
            } else {
                // Append after all images and existing videos
                let lastVideoIndex = stagedAttachments.lastIndex(where: { $0.kind == .video })
                if let lastVideoIndex {
                    stagedAttachments.insert(newAtt, at: lastVideoIndex + 1)
                } else {
                    // If no videos yet, insert after images
                    let lastImageIndex = stagedAttachments.lastIndex(where: { $0.kind == .image })
                    if let lastImageIndex {
                        stagedAttachments.insert(newAtt, at: lastImageIndex + 1)
                    } else {
                        stagedAttachments.append(newAtt)
                    }
                }
            }

        case .audio:
            // Insert after current audio within audios section
            let audiosOnly = stagedAttachments.enumerated().filter { $0.element.kind == .audio }
            let currentAudioIndexInAudios: Int? = {
                if combined.indices.contains(currentIndex) {
                    let currentItem = combined[currentIndex]
                    if currentItem.kind == .audio {
                        return audiosOnly.firstIndex(where: { $0.element.id == currentItem.id })
                    }
                }
                return nil
            }()
            if let ca = currentAudioIndexInAudios {
                let insertAt = audiosOnly[ca].offset + 1
                stagedAttachments.insert(newAtt, at: insertAt)
            } else {
                stagedAttachments.append(newAtt)
            }

        case .file, .pdf:
            stagedAttachments.append(newAtt)
        }

        // Naming: for audio Save-as-New, retain the source title (user or auto) and append an edit suffix.
        if kind == .audio {
            let audioNamesKey = "stagedAudioNames_temp"
            var dict = (UserDefaults.standard.dictionary(forKey: audioNamesKey) as? [String: String]) ?? [:]

            let sourceStem = originalURL.deletingPathExtension().lastPathComponent
            if let sourceID = UUID(uuidString: sourceStem),
               let rawBase = dict[sourceID.uuidString] {
                let base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
                if !base.isEmpty {
                    // Find next available suffix among existing titles matching base or base_<n>.
                    var maxN = 0
                    for (_, v) in dict {
                        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t == base { maxN = max(maxN, 0); continue }
                        if t.hasPrefix(base + "_") {
                            let suffix = String(t.dropFirst((base + "_").count))
                            if let n = Int(suffix) { maxN = max(maxN, n) }
                        }
                    }
                    let nextN = maxN + 1
                    dict[newID.uuidString] = base + "_\(nextN)"
                    UserDefaults.standard.set(dict, forKey: audioNamesKey)
                    attachmentTitlesRefreshTick &+= 1
                }
            }
        }

        // Surrogate extension must follow the source/export type.
        let ext = {
            let e = newURL.pathExtension.lowercased()
            return e.isEmpty ? defaultSurrogateExtension(for: newAtt.kind) : e
        }()
        let surrogateTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent(newAtt.id.uuidString)
            .appendingPathExtension(ext)

        // Seed surrogate immediately for new staged item (video + audio).
        do {
            try newAtt.data.write(to: surrogateTarget, options: .atomic)
            // tmp-only sibling cleanup (kind-scoped)
            cleanupSurrogateSiblings_tmpOnly(id: newAtt.id, keepExt: ext, kind: newAtt.kind)
            // Best-effort delete newURL after surrogate write succeeds (even if in Documents),
            // but only if safe (not surrogate target, not referenced by Core Data).
            bestEffortDeleteNewURLIfSafe(newURL: newURL, surrogateTarget: surrogateTarget)
        } catch {
            // Fail silently.
        }
    }

}


fileprivate func formatClipDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

fileprivate struct AttachmentThumbCell: View {
    let att: StagedAttachment
    let isThumbnail: Bool
    let onMakeThumbnail: () -> Void
    let onRemove: () -> Void
    let isPrivate: (_ id: UUID?, _ url: URL?) -> Bool
    let setPrivate: (_ id: UUID?, _ url: URL?, _ value: Bool) -> Void

    @State private var videoPoster: UIImage? = nil
    @State private var pdfThumbnail: UIImage? = nil
    @State private var isPresentingVideo = false
    @State private var audioDuration: Double? = nil

    private let tile: CGFloat = 128

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .topLeading) {
                thumbContent
                    .frame(width: tile, height: tile)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }

            // Right-side vertical control column: Star, Privacy, Delete
            VStack(spacing: 6) {
                // Star (thumbnail selection for images, audio, and video)
                if att.kind == .image || att.kind == .audio || att.kind == .video {
                    Text(isThumbnail ? "★" : "☆")
                        .font(.system(size: 16))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .onTapGesture { onMakeThumbnail() }
                        .accessibilityLabel(isThumbnail ? "Thumbnail (selected)" : "Set as Thumbnail")
                }

                // Privacy toggle (ID-first, URL fallback)
                let priv = isPrivate(att.id, resolvedURL)
                Button {
                    setPrivate(att.id, resolvedURL, !priv)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: priv ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .opacity(isThumbnail ? 0 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(priv ? "Mark attachment shared" : "Mark attachment private")

                // Delete
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete attachment")
            }
            .padding(6)
        }
        .contextMenu {
            if att.kind == .image || att.kind == .audio || att.kind == .video {
                Button("Set as Thumbnail") { onMakeThumbnail() }
            }
            Button(role: .destructive) { onRemove() } label: { Text("Remove") }
        }
    }

    private var resolvedURL: URL? {
        // Use a stable, surrogate URL in Caches/Temp using the staged id and an extension by kind.
        let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : att.kind == .pdf ? "pdf" : "dat")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension(ext)
    }

    @ViewBuilder
    private var thumbContent: some View {
        switch att.kind {
        case .image:
            if let ui = UIImage(data: att.data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder(system: "photo")
            }
        case .audio:
            let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
            let rawDisplay = namesDict[att.id.uuidString] ?? ""
            let trimmedDisplay = rawDisplay.trimmingCharacters(in: .whitespacesAndNewlines)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .opacity(0.85)

                    VStack(alignment: .leading, spacing: 2) {
                        if !trimmedDisplay.isEmpty {
                            Text(trimmedDisplay)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("Audio clip")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let secs = audioDuration {
                            Text(formatClipDuration(secs))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onAppear {
                // Ensure a temp surrogate exists for the staged audio so inline players/viewers can resolve it after navigation
                if let url = resolvedURL, !FileManager.default.fileExists(atPath: url.path) {
                    try? att.data.write(to: url, options: .atomic)
                }

                // Lazily compute audio duration once
                if audioDuration == nil, let url = resolvedURL {
                    let asset = AVURLAsset(url: url)
                    let seconds = CMTimeGetSeconds(asset.duration)
                    if seconds.isFinite && seconds > 0 {
                        audioDuration = seconds
                    }
                }
            }

        case .video:
            ZStack {
                if let poster = videoPoster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(system: "film")
                        .task(id: resolvedURL) {
                            guard let url = resolvedURL else { return }
                            // Ensure a temp surrogate exists for the staged video so we can generate a poster
                            if !FileManager.default.fileExists(atPath: url.path) {
                                try? att.data.write(to: url, options: .atomic)
                            }
                            await generatePosterIfNeeded(for: url)
                        }
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .onAppear {
                if let url = resolvedURL, !FileManager.default.fileExists(atPath: url.path) {
                    try? att.data.write(to: url, options: .atomic)
                }
            }
        case .file:
            placeholder(system: "doc")
        case .pdf:
            Group {
                if let thumbnail = pdfThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(system: "doc")
                }
            }
            .task(id: att.id) {
                await generatePDFThumbnailIfNeeded()
            }
        }
    }

    private func placeholder(system: String) -> some View {
        Image(systemName: system)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(24)
    }


    private func generatePDFThumbnailIfNeeded() async {
        if pdfThumbnail != nil { return }
        let cacheKey = att.id.uuidString
        let data = att.data
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                #if canImport(UIKit)
                let img = AttachmentStore.generatePDFThumbnail(data: data, cacheKey: cacheKey)
                #else
                let img: UIImage? = nil
                #endif
                DispatchQueue.main.async {
                    self.pdfThumbnail = img
                    continuation.resume()
                }
            }
        }
    }

    private func generatePosterIfNeeded(for url: URL) async {
        if videoPoster != nil { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                #if canImport(UIKit)
                let img = AttachmentStore.generateVideoPoster(url: url)
                #else
                let img: UIImage? = nil
                #endif
                DispatchQueue.main.async {
                    self.videoPoster = img
                    continuation.resume()
                }
            }
        }
    }
}

#if canImport(UIKit)
fileprivate struct VideoPlayerSheet: UIViewControllerRepresentable {
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
