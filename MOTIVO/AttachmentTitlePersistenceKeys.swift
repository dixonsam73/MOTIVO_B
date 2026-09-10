import Foundation

enum AttachmentTitlePersistenceKeys {
    static let legacyAudioTitlesKey = "persistedAudioTitles_v1"
    static let legacyVideoTitlesKey = "persistedVideoTitles_v1"

    static let audioPrefix = "persistedAudioTitles_v1:"
    static let videoPrefix = "persistedVideoTitles_v1:"

    enum Kind {
        case audio
        case video
    }

    static func normalize(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }

    static func audioNamespacedKey(for userID: String) -> String {
        audioPrefix + normalize(userID)!
    }

    static func videoNamespacedKey(for userID: String) -> String {
        videoPrefix + normalize(userID)!
    }

    static func namespacedKey(for kind: Kind, userID: String) -> String {
        switch kind {
        case .audio: return audioNamespacedKey(for: userID)
        case .video: return videoNamespacedKey(for: userID)
        }
    }

    static func legacyKey(for kind: Kind) -> String {
        switch kind {
        case .audio: return legacyAudioTitlesKey
        case .video: return legacyVideoTitlesKey
        }
    }

    // MARK: - C-47 — the one place an attachment title is written

    /// **Attachment titles are local Journal data.** They are written to the
    /// SHARED (unscoped) store, keyed by the attachment's unique id — never by
    /// filename — so they persist with no Connected identity and survive
    /// sign-out. Factory reset still removes them.
    ///
    /// The readers merge per-identity OVER shared, so an older per-identity
    /// value for this attachment would hide the new one. This removes THAT ONE
    /// attachment's entry from every per-identity store of the kind; nothing
    /// else is touched and nothing is migrated.
    ///
    /// An empty title removes it everywhere.
    static func writeLocalTitle(_ title: String?,
                                kind: Kind,
                                attachmentID: UUID,
                                defaults: UserDefaults = .standard) {
        let id = attachmentID.uuidString
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let sharedKey = legacyKey(for: kind)
        var shared = (defaults.dictionary(forKey: sharedKey) as? [String: String]) ?? [:]
        if trimmed.isEmpty {
            shared.removeValue(forKey: id)
        } else {
            shared[id] = trimmed
        }
        defaults.set(shared, forKey: sharedKey)

        let prefix = (kind == .audio) ? audioPrefix : videoPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            guard var scoped = defaults.dictionary(forKey: key) as? [String: String],
                  scoped[id] != nil else { continue }
            scoped.removeValue(forKey: id)
            defaults.set(scoped, forKey: key)
        }
    }
}
