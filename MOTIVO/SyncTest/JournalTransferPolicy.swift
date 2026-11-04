//
//  JournalTransferPolicy.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  MEDIA OVER MOBILE DATA (stage J). Attachment, score and avatar files travel
//  over Wi-Fi unless the person allows mobile data on this device; text and
//  metadata sync whatever the link. The preference is per device.
//
//  The rule (Samuel, 2026-10-28): with the option OFF, media waits on a
//  cellular-only link and on a link iOS reports as expensive (a personal
//  hotspot); with the option ON, both carry media. Low Data Mode
//  (`isConstrained`, which the person can set per Wi-Fi network as well as
//  for mobile data) pauses media WHATEVER the option says: it is the person's
//  own system-wide request, and "allow mobile data" never overrides it.
//
//  Uploads: an outgoing record that would carry a file is left in the outbox
//  while media is held and sent when it is not. Downloads: CKSyncEngine
//  fetches every asset with its record and offers no way to leave files out,
//  so the engine never fetches (C-149, 2026-11-03): the app fetches records
//  itself through the asset-free delta catch-up (stage G) on a push, the
//  foreground, a 75 s poll while active and activation, and fetches a file
//  by name only where it is new here; while media is held such records wait
//  by name and are imported with their file once media is allowed again.
//  Pushes arrive through the app's own silent-push subscription.
//

import Foundation
import Network

/// PURE. Whether media transfers wait right now, and why.
enum JournalMediaGate {
    /// What iOS says about the current path, reduced to what the rule uses.
    struct Link: Equatable {
        /// Mobile data with no Wi-Fi or wired interface available.
        var cellularOnly = false
        /// iOS calls the path expensive: a personal hotspot, in practice.
        var expensive = false
        /// Low Data Mode is on for this connection.
        var constrained = false
    }

    enum Hold: String, Equatable {
        case none
        /// Mobile data or a hotspot, and the option is off: waits for Wi-Fi.
        case mobileData
        /// Low Data Mode: paused until it is off, whatever the option.
        case lowDataMode

        var holds: Bool { self != .none }

        /// Short reason for status lines.
        var reason: String? {
            switch self {
            case .none: return nil
            case .mobileData: return "media waits for Wi-Fi"
            case .lowDataMode: return "media paused by Low Data Mode"
            }
        }
    }

    static func hold(link: Link, allowMobileData: Bool) -> Hold {
        if link.constrained { return .lowDataMode }
        if (link.cellularOnly || link.expensive) && !allowMobileData { return .mobileData }
        return .none
    }

    static func link(path: NWPath) -> Link {
        Link(cellularOnly: path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet),
             expensive: path.isExpensive,
             constrained: path.isConstrained)
    }

    /// Whether moving from one hold to another releases what waited: only
    /// from held to allowed. The engine is never rebuilt for a hold change
    /// (C-149); a change of reason alone is a status change.
    static func releaseNeeded(from previous: Hold, to next: Hold) -> Bool {
        previous.holds && !next.holds
    }
}

/// The per-device choice. Read by the engine on every path change and when
/// the toggle moves; never synced.
enum JournalMediaPreference {
    static let defaultsKey = "syncTest_mediaOverMobileData_v1"
    static let changedNotification = Notification.Name("JournalMediaPreference.changed")

    static func allowsMobileData(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func setAllowsMobileData(_ allowed: Bool, defaults: UserDefaults = .standard) {
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

    /// "Media waiting for Wi-Fi: 2 to send (35 MB), 1 to receive", or with
    /// Low Data Mode "Media paused by Low Data Mode: …"; nil when nothing
    /// waits. Something can wait after the hold has lifted (the release is in
    /// progress), so the wording without a hold is "Media still to transfer".
    static func summary(uploads: [String: Int64], downloads: [String], hold: JournalMediaGate.Hold = .mobileData) -> String? {
        guard !uploads.isEmpty || !downloads.isEmpty else { return nil }
        var parts: [String] = []
        if !uploads.isEmpty {
            let bytes = ByteCountFormatter.string(fromByteCount: uploads.values.reduce(0, +), countStyle: .file)
            parts.append("\(uploads.count) to send (\(bytes))")
        }
        if !downloads.isEmpty { parts.append("\(downloads.count) to receive") }
        let head: String
        switch hold {
        case .mobileData: head = "Media waiting for Wi-Fi"
        case .lowDataMode: head = "Media paused by Low Data Mode"
        case .none: head = "Media still to transfer"
        }
        return head + ": " + parts.joined(separator: ", ")
    }
}

/// PURE. One delta catch-up at a time: a request that lands during a run
/// marks one more run after it, so a push and a foreground a second apart
/// (device, 2026-11-03: the same seven records imported twice) fetch once.
struct JournalCatchUpSerial: Equatable {
    private(set) var running = false
    private var queued = false
    /// True when the caller should run now; false when a run is in progress
    /// and will go again when it finishes.
    mutating func begin() -> Bool {
        if running { queued = true; return false }
        running = true
        return true
    }
    /// Whether another run was requested meanwhile.
    mutating func end() -> Bool {
        running = false
        let again = queued
        queued = false
        return again
    }
}
