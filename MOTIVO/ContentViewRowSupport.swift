// CHANGE-ID: 20260520_211500_ContentViewRowExtractionPass1
// SCOPE: Shared row support extracted from ContentView for row subsystem relocation only; no logic or UI changes.
// SEARCH-TOKEN: 20260520_211500_ContentViewRowExtractionPass1

import SwiftUI
import CoreData
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Photos)
import Photos
#endif

let FEED_IMAGE_VIDEO_THUMB: CGFloat = 88
let FEED_AUDIO_THUMB: CGFloat = 56
let FEED_THUMB_CORNER: CGFloat = 10

func isActiveUserFilter(_ candidateUserID: String?, activeUserFilterUserID: String?) -> Bool {
    let candidate = (candidateUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let active = (activeUserFilterUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !candidate.isEmpty && !active.isEmpty && candidate == active
}

func isActiveEnsembleMember(_ candidateUserID: String?, activeEnsembleMemberUserIDs: Set<String>) -> Bool {
    let candidate = (candidateUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !candidate.isEmpty && activeEnsembleMemberUserIDs.contains(candidate)
}

struct AttachmentCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .foregroundStyle(Theme.Colors.secondaryText.opacity(FeedJournalAlignmentUI.attachmentBadgeIconOpacity))
            Text("\(count)")
                .foregroundStyle(Theme.Colors.secondaryText.opacity(FeedJournalAlignmentUI.attachmentBadgeTextOpacity))
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(FeedJournalAlignmentUI.attachmentBadgeStrokeOpacity), lineWidth: 0.5))
        .padding(6)
        .accessibilityLabel("\(count) attachments")
    }
}

#if canImport(UIKit)
enum LocalAttachmentVideoPosterCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func cachedPoster(for attachment: Attachment, url: URL?) -> UIImage? {
        cache.object(forKey: cacheKey(for: attachment, url: url))
    }

    static func store(_ image: UIImage, for attachment: Attachment, url: URL?) {
        cache.setObject(image, forKey: cacheKey(for: attachment, url: url))
    }

    private static func cacheKey(for attachment: Attachment, url: URL?) -> NSString {
        if !attachment.objectID.isTemporaryID {
            return ("localVideoPoster|" + attachment.objectID.uriRepresentation().absoluteString) as NSString
        }
        if let url {
            return ("localVideoPoster|" + url.absoluteString) as NSString
        }
        return ("localVideoPoster|" + ObjectIdentifier(attachment).debugDescription) as NSString
    }
}
#endif

struct VideoOrIconTile: View {
    let attachment: Attachment
    @State private var poster: UIImage? = nil

    var body: some View {
        let kind = attachmentKind(attachment)
        ZStack(alignment: .center) {
            if kind == "video" {
                let url = attachmentFileURL(attachment)
                let displayPoster = poster ?? LocalAttachmentVideoPosterCache.cachedPoster(for: attachment, url: url)

                ZStack(alignment: .center) {
                    if let displayPoster {
                        Image(uiImage: displayPoster)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipped()
                    } else {
                        Image(systemName: "video")
                            .imageScale(.large)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .task {
                    if poster == nil, let url {
                        await loadPoster(url)
                    }
                }
            } else {
                Image(systemName: symbolName(for: kind))
                    .imageScale(.large)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(width: 64, height: 64)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func symbolName(for kind: String) -> String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "pdf":   return "doc.richtext"
        default:        return "doc"
        }
    }

    private func loadPoster(_ url: URL) async {
        if let cached = LocalAttachmentVideoPosterCache.cachedPoster(for: attachment, url: url) {
            poster = cached
            return
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    if let img {
                        LocalAttachmentVideoPosterCache.store(img, for: attachment, url: url)
                    }
                    self.poster = img
                    continuation.resume()
                }
            }
        }
    }
}

struct SingleAttachmentPreview: View {
    let attachment: Attachment
    @State private var poster: UIImage? = nil

    var body: some View {
        let kind = attachmentKind(attachment)
        let isAudio = (kind == "audio")
        let size: CGFloat = isAudio ? FEED_AUDIO_THUMB : FEED_IMAGE_VIDEO_THUMB
        ZStack(alignment: .center) {
            if kind == "image" {
                FeedRowAttachmentThumb(attachment: attachment)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous).stroke(.black.opacity(0.05), lineWidth: 1))
            } else if kind == "video" {
                let url = attachmentFileURL(attachment)
                let displayPoster = poster ?? LocalAttachmentVideoPosterCache.cachedPoster(for: attachment, url: url)

                ZStack(alignment: .center) {
                    if let displayPoster {
                        Image(uiImage: displayPoster)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                    } else {
                        Image(systemName: "video")
                            .imageScale(.large)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .task {
                    if poster == nil, let url { await loadPoster(url) }
                }
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous).stroke(.black.opacity(0.05), lineWidth: 1))
            } else {
                Image(systemName: symbolName(for: kind))
                    .imageScale(.large)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: size, height: size)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous).stroke(.black.opacity(0.05), lineWidth: 1))
            }
        }
        .accessibilityLabel("Attachment preview")
        .accessibilityIdentifier("row.attachmentPreview")
    }

    private func symbolName(for kind: String) -> String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "pdf":   return "doc.richtext"
        default:        return "doc"
        }
    }

    private func loadPoster(_ url: URL) async {
        if let cached = LocalAttachmentVideoPosterCache.cachedPoster(for: attachment, url: url) {
            poster = cached
            return
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    if let img {
                        LocalAttachmentVideoPosterCache.store(img, for: attachment, url: url)
                    }
                    self.poster = img
                    continuation.resume()
                }
            }
        }
    }
}

// PDF / audio / video icons
struct NonImageTile: View {
    let kind: String
    @State private var poster: UIImage? = nil
    @State private var triedLoad = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            Group {
                if kind == "video", let poster {
                    Image(uiImage: poster).resizable().scaledToFill()
                } else {
                    Image(systemName: symbolName)
                        .imageScale(.large)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .onAppear {
            // Best-effort: if this is a video, attempt to load poster from the first available video attachment's URL in context.
            guard !triedLoad, kind == "video" else { return }
            triedLoad = true
        }
    }
    private var symbolName: String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "pdf":   return "doc.richtext"
        default:        return "doc"
        }
    }
}

// MARK: - Image thumbnail (actual image if available)

struct FeedRowAttachmentThumb: View {
    @ObservedObject var attachment: Attachment
    #if canImport(UIKit)
    @StateObject private var loader: FeedRowAttachmentThumbLoader
    init(attachment: Attachment) {
        self._attachment = ObservedObject(initialValue: attachment)
        _loader = StateObject(wrappedValue: FeedRowAttachmentThumbLoader(attachment: attachment))
    }
    #endif

    var body: some View {
        #if canImport(UIKit)
        Group {
            if let ui = loader.image {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if loader.isFinished {
                // Finished but no image -> neutral photo placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            } else {
                // Loading
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                    ProgressView().progressViewStyle(.circular)
                }
            }
        }
        #else
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .padding(12)
            .foregroundStyle(Theme.Colors.secondaryText)
            .background(Color.secondary.opacity(0.08))
        #endif
    }
}
#if canImport(UIKit)
import UIKit

final class FeedRowAttachmentThumbLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isFinished: Bool = false

    private static let cache = NSCache<NSString, UIImage>()
    private let att: Attachment
    private let maxSide: CGFloat = 100 // small thumb

    init(attachment: Attachment) {
        self.att = attachment
        load()
    }

    private func load() {
        isFinished = false
        let key = att.objectID.uriRepresentation().absoluteString as NSString
        if let cached = Self.cache.object(forKey: key) {
            self.image = cached
            self.isFinished = true
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var ui: UIImage? = nil
            // Try inline first
            ui = attachmentImage(self.att)
            // Try file URL next
            if ui == nil, let url = attachmentFileURL(self.att) {
                if url.isFileURL {
                    ui = UIImage(contentsOfFile: url.path)
                }
            }
            // Try Photos asset (localIdentifier) synchronously for a tiny target
            if ui == nil {
                ui = attachmentPhotoLibraryImage(self.att, targetMax: self.maxSide)
            }
            var final: UIImage? = nil
            if let ui {
                final = self.downscale(ui, to: self.maxSide)
            }
            DispatchQueue.main.async {
                if let final {
                    Self.cache.setObject(final, forKey: key)
                    self.image = final
                }
                self.isFinished = true
            }
        }
    }

    private func downscale(_ img: UIImage, to max: CGFloat) -> UIImage? {
        let size = img.size
        guard size.width > 0 && size.height > 0 else { return img }
        let scale = min(max / size.width, max / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif



// MARK: - Favorite image selection

func pickFavoriteImage(from images: [Attachment]) -> Attachment? {
    // Prefer explicit favorite/primary/thumbnail flags if present
    for a in images {
        if isTrueFlag(a, keys: ["isThumbnail","thumbnail","isFavorite","favorite","isStarred","starred","isPrimary","isCover"]) {
            return a
        }
    }
    // Otherwise, first image
    return images.first
}

func pickFavoriteAttachment(from attachments: [Attachment]) -> Attachment? {
    // Prefer explicit favorite/primary/thumbnail flags if present across any kind
    for a in attachments {
        if isTrueFlag(a, keys: ["isThumbnail","thumbnail","isFavorite","favorite","isStarred","starred","isPrimary","isCover"]) {
            return a
        }
    }
    // Otherwise, prefer first image, else first attachment of any kind
    if let firstImage = attachments.first(where: { attachmentKind($0) == "image" }) { return firstImage }
    return attachments.first
}

func isTrueFlag(_ a: Attachment, keys: [String]) -> Bool {
    let props = a.entity.propertiesByName
    for k in keys where props[k] != nil {
        if let n = a.value(forKey: k) as? NSNumber { if n.boolValue { return true } }
        if let b = a.value(forKey: k) as? Bool, b { return true }
    }
    return false
}

// MARK: - Attachment helpers (KVC-safe + file URL + Photos fallback)

func attachmentKind(_ a: Attachment) -> String {
    let props = a.entity.propertiesByName
    func str(_ k: String) -> String? { props[k] != nil ? (a.value(forKey: k) as? String) : nil }

    // MIME-ish fields
    let typeStr = (str("type") ?? str("kind") ?? str("mimeType") ?? "").lowercased()
    if typeStr.contains("image") { return "image" }
    if typeStr.contains("video") { return "video" }
    if typeStr.contains("audio") { return "audio" }
    if typeStr.contains("pdf")   { return "pdf" }

    // URL/path
    let urlStr = (str("url") ?? str("fileURL") ?? str("path") ?? "").lowercased()
    if urlStr.hasSuffix(".png") || urlStr.hasSuffix(".jpg") || urlStr.hasSuffix(".jpeg") || urlStr.hasSuffix(".heic") { return "image" }
    if urlStr.hasSuffix(".mp4") || urlStr.hasSuffix(".mov") || urlStr.hasSuffix(".m4v") { return "video" }
    if urlStr.hasSuffix(".m4a") || urlStr.hasSuffix(".mp3") || urlStr.hasSuffix(".wav") { return "audio" }
    if urlStr.hasSuffix(".pdf") { return "pdf" }

    return "unknown"
}

func attachmentFileURL(_ a: Attachment) -> URL? {

    func fallbackByFilename(_ filename: String) -> URL? {
        let fm = FileManager.default
        let dirs: [URL?] = [
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: NSTemporaryDirectory())
        ]
        for d in dirs.compactMap({ $0 }) {
            let candidate = d.appendingPathComponent(filename)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
    let props = a.entity.propertiesByName

    // URL-typed properties
    let urlKeysURL = ["url", "fileURL", "pathURL", "localURL"]
    for k in urlKeysURL where props[k] != nil {
        if let u = a.value(forKey: k) as? URL {
            if u.isFileURL {
                if FileManager.default.fileExists(atPath: u.path) { return u }
                if let alt = fallbackByFilename(u.lastPathComponent) { return alt }
            } else {
                return u
            }
        }
    }

    // String-typed properties
    let urlKeysString = ["url", "fileURL", "path", "localPath", "filename"]
    for k in urlKeysString where props[k] != nil {
        if let sVal = a.value(forKey: k) as? String, !sVal.isEmpty {
            // If it's a file:// URL string
            if let u = URL(string: sVal), u.scheme?.hasPrefix("file") == true {
                if FileManager.default.fileExists(atPath: u.path) { return u }
                if let alt = fallbackByFilename(u.lastPathComponent) { return alt }
            }
            // Absolute path string
            if sVal.hasPrefix("/") {
                if FileManager.default.fileExists(atPath: sVal) { return URL(fileURLWithPath: sVal) }
                if let alt = fallbackByFilename(URL(fileURLWithPath: sVal).lastPathComponent) { return alt }
            }
            // Relative path or plain filename
            if let alt = fallbackByFilename(sVal) { return alt }
        }
    }

    // Bookmark data
    let bookmarkKeys = ["bookmark", "bookmarkData"]
    for k in bookmarkKeys where props[k] != nil {
        if let d = a.value(forKey: k) as? Data {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: d, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return u
            }
        }
    }

    return nil
}

#if canImport(UIKit)
import UIKit
func attachmentImage(_ a: Attachment) -> UIImage? {
    let props = a.entity.propertiesByName
    // inline data or transformables (expanded keys)
    let keys = ["thumbnail", "thumbnailData", "thumbData", "thumbnailSmall", "imageData", "image", "data", "preview", "previewData", "photoData"]
    for k in keys where props[k] != nil {
        if let d = a.value(forKey: k) as? Data, let img = UIImage(data: d) { return img }
        if let img = a.value(forKey: k) as? UIImage { return img }
    }
    return nil
}
#endif

#if canImport(Photos)
import Photos
func attachmentPhotoLibraryImage(_ a: Attachment, targetMax: CGFloat) -> UIImage? {
    let props = a.entity.propertiesByName
    func str(_ k: String) -> String? { props[k] != nil ? (a.value(forKey: k) as? String) : nil }
    guard let id = (str("phLocalIdentifier") ?? str("localIdentifier") ?? str("assetIdentifier")) else {
        return nil
    }
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
    guard let asset = assets.firstObject else { return nil }
    let manager = PHImageManager.default()
    let size = CGSize(width: targetMax, height: targetMax)
    let opts = PHImageRequestOptions()
    opts.isSynchronous = true
    opts.deliveryMode = .fastFormat
    opts.resizeMode = .fast
    var result: UIImage?
    manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: opts) { img, _ in
        result = img
    }
    return result
}
#else
func attachmentPhotoLibraryImage(_ a: Attachment, targetMax: CGFloat) -> UIImage? { nil }
#endif
// MARK: - Step 8C Backend Feed Row (read-only)


func splitThoughtLead(_ text: String) -> (lead: String, remainder: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ("", "")
    }

    let maxLeadCharacters = 42
    let preferredSeparators: [Character] = [":", "—", "."]

    for separator in preferredSeparators {
        if let separatorIndex = trimmed.firstIndex(of: separator) {
            let nextIndex = trimmed.index(after: separatorIndex)
            let leadCandidate = String(trimmed[..<nextIndex])
                .replacingOccurrences(of: " :", with: ":")
                .replacingOccurrences(of: " .", with: ".")
                .replacingOccurrences(of: " —", with: "—")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !leadCandidate.isEmpty && leadCandidate.count <= maxLeadCharacters {
                let remainderCandidate = String(trimmed[nextIndex...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if remainderCandidate.isEmpty {
                    return (leadCandidate, "")
                }

                return (leadCandidate, " " + remainderCandidate)
            }
        }
    }

    let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
    guard words.count > 5 else {
        return (trimmed, "")
    }

    let lead = words.prefix(5).joined(separator: " ")
    let remainder = words.dropFirst(5).joined(separator: " ")
    return (lead, " " + remainder)
}

enum ThoughtRowContext {
    case feed
    case journalWeek
}

enum BackendThoughtRules {
    static func isThought(post: BackendPost, model: BackendSessionViewModel) -> Bool {
        if post.isThought { return true }

        guard let duration = numericValue(named: ["durationSeconds", "duration_seconds", "duration"], in: post),
              abs(duration) < 0.0001 else {
            return false
        }

        let instrument = stringValue(named: ["instrumentLabel", "instrument_label"], in: post)
        let title = stringValue(named: ["title", "sessionTitle", "session_title"], in: post)
        let notes = stringValue(named: ["notes", "body", "text"], in: post)
        let hasContent = !notes.isEmpty || !model.attachmentRefs.isEmpty

        return instrument.isEmpty && title.isEmpty && hasContent
    }

    private static func stringValue(named names: [String], in value: Any) -> String {
        for name in names {
            if let raw = mirrorValue(named: name, in: value) {
                let unwrapped = unwrapOptional(raw) ?? raw
                if let string = unwrapped as? String {
                    return string.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return ""
    }

    private static func numericValue(named names: [String], in value: Any) -> Double? {
        for name in names {
            if let raw = mirrorValue(named: name, in: value) {
                let unwrapped = unwrapOptional(raw) ?? raw
                if let double = unwrapped as? Double { return double }
                if let int = unwrapped as? Int { return Double(int) }
                if let number = unwrapped as? NSNumber { return number.doubleValue }
            }
        }
        return nil
    }

    private static func mirrorValue(named name: String, in value: Any) -> Any? {
        Mirror(reflecting: value).children.first(where: { $0.label == name })?.value
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }
}

// Remote row layout stability: cache whether a post has attachments (and its chosen "fav" ref).
// This prevents a transient empty attachmentRefs render from collapsing the thumbnail lane and then re-expanding it.
final class RemotePostAttachmentMetaCache {
    struct Meta {
        let fav: BackendSessionViewModel.BackendAttachmentRef?
        let extraCount: Int
        let hasAny: Bool
    }

    static let shared = RemotePostAttachmentMetaCache()

    private let lock = NSLock()
    private var map: [UUID: Meta] = [:]

    func get(_ postID: UUID) -> Meta? {
        lock.lock(); defer { lock.unlock() }
        return map[postID]
    }

    func set(_ postID: UUID, _ meta: Meta) {
        lock.lock(); defer { lock.unlock() }
        map[postID] = meta
    }
}


// Mirror of SessionRow (read-only)




// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260214_103700_Etudes_ShareTo_InlineNav

struct ShareToFollowerSheet: View {
    let postID: UUID
    @Binding var isPresented: Bool

    @State private var isSharing: Bool = false
    @State private var errorLine: String? = nil

    @State private var directory: [String: DirectoryAccount] = [:]
    @State private var isDirectoryLoading: Bool = false

    private var followerIDs: [String] {
        Array(FollowStore.shared.followers)
    }

    private func normalized(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A–Z by display name (case/diacritic insensitive), with fallback:
    /// 1) displayName
    /// 2) handle (accountID)
    /// 3) stable internal ID (never rendered)
    private func sortKey(for userID: String) -> (String, String, String) {
        if let acct = directory[userID] {
            let name = normalized(acct.displayName)
            let handle = normalized(acct.accountID ?? "")
            let primary = !name.isEmpty ? name : (!handle.isEmpty ? handle : normalized(userID))
            return (primary, handle, normalized(userID))
        } else {
            // Directory missing: keep stable ordering but never render raw IDs.
            return ("", "", normalized(userID))
        }
    }

    private var followerIDsSorted: [String] {
        followerIDs.sorted { a, b in
            let ka = sortKey(for: a)
            let kb = sortKey(for: b)
            if ka.0 != kb.0 { return ka.0 < kb.0 }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return ka.2 < kb.2
        }
    }

    private func loadDirectoryIfNeeded() async {
        guard !isDirectoryLoading else { return }
        let ids = followerIDs
        guard !ids.isEmpty else { return }

        isDirectoryLoading = true
        defer { isDirectoryLoading = false }

        let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids)
        switch result {
        case .success(let map):
            directory = map
        case .failure:
            // UI-only polish: keep the picker functional, but never show raw IDs.
            directory = [:]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let errorLine {
                    Text(errorLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }

                if followerIDsSorted.isEmpty {
                    VStack(spacing: 8) {
                        Text("No approved followers yet.")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .padding(.top, 24)
                    Spacer()
                } else {
                    List {
                        ForEach(followerIDsSorted, id: \.self) { followerID in
                            Button(action: {
                                guard !isSharing else { return }
                                errorLine = nil
                                isSharing = true

                                Task {
                                    let result = await BackendEnvironment.shared.shares.sharePost(
                                        postID: postID,
                                        to: followerID
                                    )

                                    switch result {
                                    case .success(let outcome):
                                        switch outcome {
                                        case .shared:
                                            isPresented = false
                                        case .alreadyShared:
                                            errorLine = "Already shared."
                                            isSharing = false
                                        }
                                    case .failure:
                                        errorLine = "Couldn’t share right now."
                                        isSharing = false
                                    }
                                }
                            }) {
                                let acct = directory[followerID]
                                PeopleUserRow(
                                    userID: followerID,
                                    overrideDisplayName: acct?.displayName ?? "User",
                                    overrideSubtitle: acct?.accountID.map { "@\($0)" },
                                    overrideAvatarKey: acct?.avatarKey
                                ) {
                                    EmptyView()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isSharing)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .appBackground()
                }
            }
            .appBackground()
            .navigationTitle("Share to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.left")
                    }
                }
            }
.task {
                await loadDirectoryIfNeeded()
            }
        }
    }
}

final class RemoteSignedURLCache {
    static let shared = RemoteSignedURLCache()

    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    private var map: [String: Entry] = [:]
    private let lock = NSLock()

    /// Returns a cached URL only if it is still valid (not expired).
    func get(_ key: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = map[key] else { return nil }
        if Date() >= entry.expiresAt {
            map.removeValue(forKey: key)
            return nil
        }
        return entry.url
    }

    /// Stores a URL with an explicit TTL (seconds).
    func set(_ key: String, url: URL, ttlSeconds: Int) {
        lock.lock(); defer { lock.unlock() }
        map[key] = Entry(url: url, expiresAt: Date().addingTimeInterval(TimeInterval(ttlSeconds)))
    }
}

enum RemotePreviewCache {
    #if canImport(UIKit)
    static let imageThumbCache = NSCache<NSString, UIImage>()
    static let videoPosterCache = NSCache<NSString, UIImage>()
    #endif
}
struct RemoteAttachmentPreview: View {
    // FIX-D: persistent in-memory thumbnail cache (keyed by postID + bucket + path)
    // Goal: prevent placeholder flashes and eliminate any chance of cross-row/cross-owner thumbnail reuse.
    #if canImport(UIKit)
    // Shared caches (also written by feed prewarmer)
    // See RemotePreviewCache.
    #endif

    let ref: BackendSessionViewModel.BackendAttachmentRef
    let postID: UUID

    @State private var signedURL: URL? = nil
    #if canImport(UIKit)
    @State private var resolvedImage: UIImage? = nil
    @State private var videoPoster: UIImage? = nil
    #endif

    private var cacheKey: String {
        "feedThumb|" + postID.uuidString + "|" + ref.bucket + "|" + ref.path
    }

    var body: some View {
        let kind = ref.kind
        let isAudio = (kind == .audio)
        let size: CGFloat = isAudio ? FEED_AUDIO_THUMB : FEED_IMAGE_VIDEO_THUMB

        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
                .fill(Color.secondary.opacity(0.08))

            // IMAGE
            if kind == .image {
                #if canImport(UIKit)
                if let ui = resolvedImage ?? RemotePreviewCache.imageThumbCache.object(forKey: cacheKey as NSString) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    neutralPlaceholder(kind: kind)
                }
                #else
                neutralPlaceholder(kind: kind)
                #endif
            }

            // VIDEO
            else if kind == .video {
                #if canImport(UIKit)
                if let poster = videoPoster ?? RemotePreviewCache.videoPosterCache.object(forKey: cacheKey as NSString) {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    neutralPlaceholder(kind: kind)
                }
                #else
                neutralPlaceholder(kind: kind)
                #endif

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }

            // AUDIO / PDF / OTHER
            else {
                placeholderIcon(kind: kind)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
                .stroke(.black.opacity(0.05), lineWidth: 1)
        )
        .accessibilityLabel("Attachment preview")
        .accessibilityIdentifier("row.attachmentPreview")
        .onChange(of: cacheKey) { _, _ in
            // Defensive reset: if SwiftUI reuses the view instance across rows, never show stale media.
            signedURL = nil
            #if canImport(UIKit)
            resolvedImage = nil
            videoPoster = nil
            #endif
        }
        .task(id: cacheKey) {
            await loadSignedURLIfNeeded()
            #if canImport(UIKit)
            await loadImageThumbIfNeeded()
            await loadVideoPosterIfNeeded()
            #endif
        }
    }

    @ViewBuilder
    private func neutralPlaceholder(kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> some View {
        // Neutral, quiet placeholder: background is already rendered by the base RoundedRectangle.
        // We intentionally avoid system glyphs here to prevent a “broken icon → real thumbnail” swap on first hydration.
        EmptyView()
    }

    @ViewBuilder
    private func placeholderIcon(kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> some View {
        // For non-thumbnail-able types (audio/pdf/other), an icon is stable and not a hydration artifact.
        Image(systemName: iconName(for: kind))
            .imageScale(.large)
            .foregroundStyle(Theme.Colors.secondaryText)
    }

    private func loadSignedURLIfNeeded() async {
        guard (ref.kind == .image) || (ref.kind == .video) else { return }

        // Keep the signed URL cached separately (short TTL) so we don't hammer RPCs.
        if let cached = RemoteSignedURLCache.shared.get(cacheKey) {
            if signedURL != cached { signedURL = cached }
            return
        }

        let ttlSeconds = 300

        let result = await NetworkManager.shared.createSignedStorageObjectURL(
            bucket: ref.bucket,
            path: ref.path,
            expiresInSeconds: ttlSeconds
        )

        guard case .success(let url) = result else { return }
        RemoteSignedURLCache.shared.set(cacheKey, url: url, ttlSeconds: ttlSeconds)

        if signedURL != url { signedURL = url }
    }

    #if canImport(UIKit)
    private func loadImageThumbIfNeeded() async {
        guard ref.kind == .image else { return }

        // 1) Prefer immediate in-memory cache.
        if let cached = RemotePreviewCache.imageThumbCache.object(forKey: cacheKey as NSString) {
            if resolvedImage !== cached { resolvedImage = cached }
            return
        }

        // 2) Need a signed URL to fetch bytes.
        guard let url = signedURL else { return }

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            guard let ui = UIImage(data: data) else { return }

            RemotePreviewCache.imageThumbCache.setObject(ui, forKey: cacheKey as NSString)
            if resolvedImage !== ui { resolvedImage = ui }
        } catch {
            // Ignore transient failures — placeholder remains; next navigation/refresh will retry.
        }
    }

    private func loadVideoPosterIfNeeded() async {
        guard ref.kind == .video else { return }

        // 1) Prefer immediate in-memory cache.
        if let cached = RemotePreviewCache.videoPosterCache.object(forKey: cacheKey as NSString) {
            if videoPoster !== cached { videoPoster = cached }
            return
        }

        // 2) Need a signed URL to generate the poster.
        guard let url = signedURL else { return }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    if let img {
                        RemotePreviewCache.videoPosterCache.setObject(img, forKey: cacheKey as NSString)
                        self.videoPoster = img
                    }
                    continuation.resume()
                }
            }
        }
    }
    #endif

    private func iconName(for kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> String {
        switch kind {
        case .audio: return "waveform"
        case .video: return "video"
        case .image: return "photo"
        }
    }
}

enum ThreadLabelSanitizer {
    /// Trims, collapses internal whitespace, enforces max length, and returns nil for empty.
    static func sanitize(_ raw: String, maxLength: Int = 32) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collapsed = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }

        if collapsed.count <= maxLength {
            return collapsed
        } else {
            let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
            return String(collapsed[..<idx])
        }
    }
}

