//
//  ThoughtMediaSummary.swift
//  MOTIVO
//
//  A THOUGHT WITH NO WRITTEN HEADING IS NAMED BY ITS MEDIA.
//
//  A thought saved from the timer often has no notes, and the journal used to
//  show it as "Thought" and a date. When there is no written heading, the rows
//  show a heading only from a member-given recording title (the id-keyed local
//  title, C-47); a generated name such as `2026oct11_15:18` and a filename are
//  not headings. An unnamed thought has no heading: the month view carries one
//  quiet kind indicator on its date line, and the week view keeps its date,
//  preview and favourite control (Samuel, 2026-10-11). Counts stay where
//  several attachments make them useful. Written headings always win. No title
//  field is added and nothing is renamed.
//

import Foundation
import CoreData

struct ThoughtMediaSummary: Equatable {
    enum Kind: Equatable { case audio, video, image }

    /// A member-given name for the first attachment; nil when it has none (a
    /// generated recording name counts as none).
    let title: String?
    let kind: Kind
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
        return ThoughtMediaSummary(title: title(for: first, kind: firstKind),
                                   kind: firstKind,
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

    /// The member-given local title by id (audio and video), unless it is the
    /// timer's generated name. Filenames are never shown.
    static func title(for attachment: Attachment, kind: ThoughtMediaSummary.Kind) -> String? {
        guard kind != .image,
              let id = attachment.value(forKey: "id") as? UUID,
              let persisted = LocalAttachmentTitles.title(for: id, kind: kind == .audio ? .audio : .video),
              !isGeneratedName(persisted) else { return nil }
        return persisted
    }

    /// The timer's generated recording name (`yyyyLLLdd_HH:mm`, lower-cased,
    /// e.g. `2026oct11_15:18`). Pure, for the tests. Stored names are untouched;
    /// the journal just does not treat this as a heading.
    static func isGeneratedName(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 15,
              let underscore = s.firstIndex(of: "_"), s.distance(from: s.startIndex, to: underscore) == 9 else { return false }
        let year = s.prefix(4), mon = s.dropFirst(4).prefix(3), day = s.dropFirst(7).prefix(2)
        let time = s[s.index(after: underscore)...]
        return year.allSatisfy(\.isNumber) && day.allSatisfy(\.isNumber) && time.count == 5
            && time[time.index(time.startIndex, offsetBy: 2)] == ":" && time.filter(\.isNumber).count == 4
            && months.contains(String(mon).lowercased())
    }

    private static let months = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
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
