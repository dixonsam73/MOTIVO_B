//
//  ThoughtMediaSummary.swift
//  MOTIVO
//
//  A THOUGHT WITH NO WRITTEN HEADING IS NAMED BY ITS MEDIA.
//
//  A thought saved from the timer often has no notes, and the journal used to
//  show it as "Thought" and a date. When there is no written heading, the rows
//  show the first attachment's existing name — the id-keyed local title (C-47)
//  for audio and video, otherwise a readable file stem for audio — with a quiet
//  kind indicator, the duration for audio and video, and a count when there
//  are several. With no name at all the symbol stands alone: no "Video" next
//  to a video icon (Samuel, 2026-10-11), and a UUID filename is never shown.
//  Written headings always win. No title field is added and nothing is renamed.
//

import Foundation
import AVFoundation
import CoreData

struct ThoughtMediaSummary: Equatable {
    enum Kind: Equatable { case audio, video, image }

    /// The first attachment's name; nil when it has none, and the kind symbol
    /// stands alone.
    let title: String?
    let kind: Kind
    /// "0:11" for audio and video, or nil when unknown.
    let durationText: String?
    /// How many media attachments the thought has, all kinds.
    let count: Int
    /// Whether the attachments are all of one kind.
    let uniformKind: Bool

    var systemImage: String {
        switch kind {
        case .audio: return "waveform"
        case .video: return "video"
        case .image: return "photo"
        }
    }

    /// Spoken prefix for accessibility.
    var spokenKind: String {
        switch kind {
        case .audio: return "Recording"
        case .video: return "Video"
        case .image: return "Photo"
        }
    }

    /// "2 recordings", "3 videos", "4 photos", "3 attachments" when mixed; nil for one.
    var countText: String? {
        guard count > 1 else { return nil }
        guard uniformKind else { return "\(count) attachments" }
        switch kind {
        case .audio: return "\(count) recordings"
        case .video: return "\(count) videos"
        case .image: return "\(count) photos"
        }
    }
}

@MainActor
enum ThoughtMediaSummaryBuilder {

    /// The summary for a session, or nil when it has no audio, video or photo.
    static func summary(for session: Session) -> ThoughtMediaSummary? {
        let media: [(Attachment, ThoughtMediaSummary.Kind)] = ((session.attachments as? Set<Attachment>).map { Array($0) } ?? [])
            .compactMap { a in kind(of: a).map { (a, $0) } }
            .sorted { a, b in
                let da = a.0.value(forKey: "createdAt") as? Date ?? .distantPast
                let db = b.0.value(forKey: "createdAt") as? Date ?? .distantPast
                return da < db
            }
        guard let (first, firstKind) = media.first else { return nil }
        let url = attachmentFileURL(first)
        let duration = (firstKind == .image) ? nil : url.flatMap { durationText(for: $0) }
        return ThoughtMediaSummary(title: title(for: first, kind: firstKind, url: url),
                                   kind: firstKind,
                                   durationText: duration,
                                   count: media.count,
                                   uniformKind: media.allSatisfy { $0.1 == firstKind })
    }

    static func kind(of attachment: Attachment) -> ThoughtMediaSummary.Kind? {
        switch attachmentKind(attachment) {
        case "audio": return .audio
        case "video": return .video
        case "image": return .image
        default: return nil
        }
    }

    // MARK: - Name

    /// The persisted local title by id (audio and video), then — for audio only,
    /// whose stem is the name the member saw — a readable file stem, else nil.
    /// A UUID stem is a filename, not a name.
    static func title(for attachment: Attachment, kind: ThoughtMediaSummary.Kind, url: URL?) -> String? {
        if kind != .image,
           let id = attachment.value(forKey: "id") as? UUID,
           let persisted = LocalAttachmentTitles.title(for: id, kind: kind == .audio ? .audio : .video) {
            return persisted
        }
        if kind == .audio, let stem = url?.deletingPathExtension().lastPathComponent,
           let readable = readableName(fromStem: stem) {
            return readable
        }
        return nil
    }

    /// Pure, for the tests: a stem that is a UUID, or blank, is not a name.
    static func readableName(fromStem stem: String) -> String? {
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, UUID(uuidString: trimmed) == nil else { return nil }
        return trimmed
    }

    // MARK: - Duration

    private static let durationCache = NSCache<NSString, NSNumber>()

    static func durationText(for url: URL) -> String? {
        let key = url.path as NSString
        let seconds: Double
        if let cached = durationCache.object(forKey: key) {
            seconds = cached.doubleValue
        } else {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let value = CMTimeGetSeconds(AVURLAsset(url: url).duration)
            guard value.isFinite, value > 0 else { return nil }
            durationCache.setObject(NSNumber(value: value), forKey: key)
            seconds = value
        }
        return format(seconds: seconds)
    }

    /// "0:11", "12:05", "1:02:03" — the clip format the editors already use.
    static func format(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// The id-keyed local title stores, read the way `SessionDetailView` reads
/// them: the shared store, with the current identity's namespaced store
/// winning where both hold the same id.
@MainActor
enum LocalAttachmentTitles {
    static func title(for attachmentID: UUID, kind: AttachmentTitlePersistenceKeys.Kind,
                      defaults: UserDefaults = .standard) -> String? {
        let raw = titles(kind: kind, defaults: defaults)[attachmentID.uuidString] ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func titles(kind: AttachmentTitlePersistenceKeys.Kind, defaults: UserDefaults = .standard) -> [String: String] {
        let legacy = (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: kind)) as? [String: String]) ?? [:]
        guard let userID = namespaceUserID() else { return legacy }
        let namespaced = (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.namespacedKey(for: kind, userID: userID)) as? [String: String]) ?? [:]
        return legacy.merging(namespaced) { _, namespacedValue in namespacedValue }
    }

    private static func namespaceUserID() -> String? {
        if BackendEnvironment.shared.isConnected,
           let connected = AttachmentTitlePersistenceKeys.normalize(AuthManager.canonicalBackendUserID()) {
            return connected
        }
        return AttachmentTitlePersistenceKeys.normalize(PersistenceController.shared.currentUserID)
    }
}
