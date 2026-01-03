//  AttachmentPrivacy.swift
//  MOTIVO
//
//  Centralized helpers for attachment privacy state.
//  Uses a JSON file in Application Support as the single source of truth with ID-first, URL-fallback keys.

// CHANGE-ID: 20260103_203738
// SCOPE: Default attachments to owner-only: empty/missing map entry => private; reset map key to v2

import Foundation

public enum AttachmentPrivacy {
    public static let mapKey = "attachmentPrivacyMap_v2"

    private static let queue = DispatchQueue(label: "AttachmentPrivacy.fileQueue", qos: .userInitiated)
    private static var cache: [String: Bool]?
    private static var legacyPurged = false

    private static let _earlyPurge: Void = { LegacyDefaultsPurge.runOnce() }()

#if DEBUG
    private static var didLogBigDefaults = false
    private static func logBigDefaults(threshold: Int = 3_000_000) {
        let d = UserDefaults.standard.dictionaryRepresentation()
        for (key, value) in d {
            if let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0), data.count >= threshold {
                print("[AttachmentPrivacy] Large UserDefaults key: \(key) size: \(data.count) bytes")
            }
        }
    }
#endif

    @inline(__always)
    public static func privacyKey(id: UUID?, url: URL?) -> String? {
        if let id { return "id://\(id.uuidString)" }
        if let url { return url.absoluteString }
        return nil
    }

    @inline(__always)
    public static func currentMap() -> [String: Bool] {
        queue.sync {
            _ = _earlyPurge
#if DEBUG
            if !didLogBigDefaults {
                didLogBigDefaults = true
                logBigDefaults()
            }
#endif
            if !legacyPurged {
                LegacyDefaultsPurge.runOnce()
                legacyPurged = true
            }
            if let cache = cache {
                return cache
            }
            let loaded = loadMap()
            cache = loaded
            return loaded
        }
    }

    @inline(__always)
    public static func isPrivate(id: UUID?, url: URL?) -> Bool {
        guard let key = privacyKey(id: id, url: url) else { return true }
        let map = currentMap()
        return map[key] ?? true
    }

    @inline(__always)
    public static func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        queue.sync {
            var map = cache ?? loadMap()
            map[key] = value
            saveMap(map)
            cache = map
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }
    }

    @inline(__always)
    public static func toggle(id: UUID?, url: URL?) {
        let current = isPrivate(id: id, url: url)
        setPrivate(id: id, url: url, !current)
    }

    // MARK: - Private Helpers

    private static func applicationSupportDirectory() -> URL? {
        do {
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            guard let appSupportURL = urls.first else { return nil }
            let directory = appSupportURL.appendingPathComponent("MOTIVO", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    private static func fileURL() -> URL? {
        applicationSupportDirectory()?.appendingPathComponent("AttachmentPrivacy.json")
    }

    private static func loadMap() -> [String: Bool] {
        guard let url = fileURL() else { return [:] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: Bool].self, from: data)
            return decoded
        } catch {
            return [:]
        }
    }

    private static func saveMap(_ map: [String: Bool]) {
        guard let url = fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(map)
            try data.write(to: url, options: .atomic)
        } catch {
            // silently ignore write errors
        }
    }
}
