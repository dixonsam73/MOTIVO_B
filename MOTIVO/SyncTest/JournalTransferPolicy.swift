//
//  JournalTransferPolicy.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  MEDIA OVER MOBILE DATA (stage J). Attachment, score and avatar files travel
//  over Wi-Fi unless the person allows mobile data on this device; text and
//  metadata sync whatever the link. The preference is per device.
//
//  Uploads: an outgoing record that would carry a file is left in the outbox
//  while the link is metered ("waiting for Wi-Fi") and sent when it is not.
//  Downloads: CKSyncEngine fetches every asset with its record and offers no
//  way to leave files out, so while the link is metered the engine is built
//  WITHOUT automatic sync and the app fetches records itself through the
//  asset-free delta catch-up (stage G); a record whose file this device
//  needs is held by name, imported with its file once the link is not
//  metered or the option is on. Pushes while the app drives its own fetches
//  arrive through the app's own silent-push subscription. "Metered" is a
//  cellular-only path, a path iOS reports as expensive (a personal hotspot),
//  or Low Data Mode.
//

#if SYNCTEST
import Foundation
import Network

/// PURE. Whether media transfers wait right now.
enum JournalMediaGate {
    static func isMetered(cellular: Bool, expensive: Bool, constrained: Bool) -> Bool {
        cellular || expensive || constrained
    }

    static func waitsForWiFi(metered: Bool, allowCellular: Bool) -> Bool {
        metered && !allowCellular
    }

    /// What iOS says about a path, reduced to the three flags the rule uses.
    static func metered(path: NWPath) -> Bool {
        let cellularOnly = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet)
        return isMetered(cellular: cellularOnly, expensive: path.isExpensive, constrained: path.isConstrained)
    }
}

/// The per-device choice. Read by the engine on every path change and when
/// the toggle moves; never synced.
enum JournalMediaPreference {
    static let defaultsKey = "syncTest_mediaOverMobileData_v1"
    static let changedNotification = Notification.Name("JournalMediaPreference.changed")

    static func allowsCellular(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func setAllowsCellular(_ allowed: Bool, defaults: UserDefaults = .standard) {
        defaults.set(allowed, forKey: defaultsKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}

/// PURE. Bookkeeping for what waits.
enum JournalMediaHold {
    /// Record names whose file this device still needs, in the order they
    /// were first held; a name is held once.
    static func adding(_ names: [String], to held: [String]) -> [String] {
        var out = held
        for name in names where !out.contains(name) { out.append(name) }
        return out
    }

    static func summary(uploads: [String: Int64], downloads: [String]) -> String? {
        guard !uploads.isEmpty || !downloads.isEmpty else { return nil }
        var parts: [String] = []
        if !uploads.isEmpty {
            let bytes = ByteCountFormatter.string(fromByteCount: uploads.values.reduce(0, +), countStyle: .file)
            parts.append("\(uploads.count) to send (\(bytes))")
        }
        if !downloads.isEmpty { parts.append("\(downloads.count) to receive") }
        return "Media waiting for Wi-Fi: " + parts.joined(separator: ", ")
    }
}
#endif
