//  AttachmentPrivacy.swift
//  MOTIVO
//
//  Centralized helpers for attachment privacy state.
//  Uses UserDefaults as the single source of truth with ID-first, URL-fallback keys.

import Foundation

public enum AttachmentPrivacy {
    public static let mapKey = "attachmentPrivacyMap_v1"

    @inline(__always)
    public static func privacyKey(id: UUID?, url: URL?) -> String? {
        if let id { return "id://\(id.uuidString)" }
        if let url { return url.absoluteString }
        return nil
    }

    @inline(__always)
    public static func currentMap() -> [String: Bool] {
        (UserDefaults.standard.dictionary(forKey: mapKey) as? [String: Bool]) ?? [:]
    }

    @inline(__always)
    public static func isPrivate(id: UUID?, url: URL?) -> Bool {
        guard let key = privacyKey(id: id, url: url) else { return false }
        let map = currentMap()
        return map[key] ?? false
    }

    @inline(__always)
    public static func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        var map = currentMap()
        map[key] = value
        UserDefaults.standard.set(map, forKey: mapKey)
        // Post a change notification so listeners can refresh their local caches if needed.
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
    }

    @inline(__always)
    public static func toggle(id: UUID?, url: URL?) {
        let current = isPrivate(id: id, url: url)
        setPrivate(id: id, url: url, !current)
    }
}
