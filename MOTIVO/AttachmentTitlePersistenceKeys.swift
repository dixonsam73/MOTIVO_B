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
}
