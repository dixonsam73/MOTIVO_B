//
//  JournalSyncStatusSummary.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  WHAT THE PROFILE SCREEN SAYS ABOUT SYNC, in plain words, derived from the
//  state file's fields and a few live facts (the engine's phase, whether the
//  network path is satisfied, the first fetch's progress). PURE: the engine's
//  rules are untouched; this only reads what they leave behind.
//
//  The one rule of the wording: "Up to date" is said only when nothing waits
//  — no outbox entry, no file to send or receive, no restoration in
//  progress — so a running engine with failing sends never reads as "done".
//

import Foundation

/// The first complete fetch, as it goes: records are read first, then the
/// files that are new here, then everything is added to this device.
struct JournalRestoreProgress: Equatable {
    var recordsFetched = 0
    var filesFetched = 0
    /// nil until the records pass has finished and the files to fetch are known.
    var filesTotal: Int?
    var applying = false

    var text: String {
        if applying { return "Adding \(recordsFetched) record\(recordsFetched == 1 ? "" : "s") to this device…" }
        if let filesTotal {
            return filesTotal == 0 ? "\(recordsFetched) records read; no files to download"
                                   : "Downloading files: \(filesFetched) of \(filesTotal)"
        }
        return "Reading your journal: \(recordsFetched) record\(recordsFetched == 1 ? "" : "s") so far"
    }
}

/// Everything the summary is derived from. Built by the engine's
/// `refreshCounts` from the state file and the live status.
struct JournalSyncStatusFacts: Equatable {
    var inUse = true
    var unlinked = false
    var localRemovalInProgress = false
    var phase = "Running"
    var pausedReason: String?
    var online = true
    var initialFetchComplete = true
    var restore: JournalRestoreProgress?
    var outbox: [JournalSyncPendingChange] = []
    /// Record names whose file this device still needs (held or not fetched).
    var awaitingMedia: [String] = []
    /// Bytes of the files that wait: `mediaWaitingUpload` for held media, and
    /// the hashed size of a file whose record is queued ("size|mtime|hash").
    var mediaWaitingUpload: [String: Int64] = [:]
    var fileStampCache: [String: String] = [:]
    var mediaHold: JournalMediaGate.Hold = .none
    var storageFullSummary: String?
    /// The last transient send failure (network, rate limit…) since the last
    /// accepted send; nil once something went up.
    var lastTransientFailure: String?
    var lastCatchUp: String?
    var lastFetchAt: Date?
}

/// What waits in the outbox, counted the way a person thinks of it.
struct JournalSyncPendingCounts: Equatable {
    var entries = 0
    var files = 0
    var otherChanges = 0
    var deletions = 0
    /// Known only when every waiting file has a size on record.
    var bytes: Int64?

    var isEmpty: Bool { entries == 0 && files == 0 && otherChanges == 0 && deletions == 0 }

    static func count(outbox: [JournalSyncPendingChange], mediaWaitingUpload: [String: Int64], fileStampCache: [String: String]) -> JournalSyncPendingCounts {
        var c = JournalSyncPendingCounts()
        var bytes: Int64 = 0
        var allKnown = true
        for change in outbox {
            if change.op == .delete { c.deletions += 1; continue }
            if JournalAssetPolicy.carriesFile(recordType: change.recordType), !change.assetFree {
                c.files += 1
                if let held = mediaWaitingUpload[change.recordName] {
                    bytes += held
                } else if let entry = fileStampCache[change.recordName], let size = Int64(entry.split(separator: "|").first ?? "") {
                    bytes += size
                } else {
                    allKnown = false
                }
            } else if change.recordType == JournalSyncRecordType.session {
                c.entries += 1
            } else {
                c.otherChanges += 1
            }
        }
        c.bytes = (c.files > 0 && allKnown) ? bytes : nil
        return c
    }

    /// "3 entries, 4 files (35 MB) and 2 other changes" — only the parts that are non-zero.
    var text: String {
        var parts: [String] = []
        if entries > 0 { parts.append("\(entries) \(entries == 1 ? "entry" : "entries")") }
        if files > 0 {
            var f = "\(files) file\(files == 1 ? "" : "s")"
            if let bytes { f += " (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))" }
            parts.append(f)
        }
        if otherChanges > 0 { parts.append("\(otherChanges) other change\(otherChanges == 1 ? "" : "s")") }
        if deletions > 0 { parts.append("\(deletions) deletion\(deletions == 1 ? "" : "s")") }
        switch parts.count {
        case 0: return "nothing"
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        }
    }
}

struct JournalSyncStatusSummary: Equatable {
    enum Kind: Equatable {
        case off, removing, restoring, checking, waiting, paused, offline, mediaHeld, uploading, downloading, upToDate
        /// Needs the person: signed out, a different account, storage full.
        case attention
    }
    var kind: Kind
    /// One short line for the Status row.
    var headline: String
    /// One or two plain sentences under it, or nil.
    var detail: String?
    /// What the person can do about it, or nil.
    var action: String?

    static let differentAccountMarker = "different iCloud account"
    static let signedOutMarker = "Signed out of iCloud"
    static let waitingMarker = "Waiting for iCloud"

    static func derive(_ f: JournalSyncStatusFacts, now: Date = Date()) -> JournalSyncStatusSummary {
        guard f.inUse else { return .init(kind: .off, headline: "Off") }
        if f.localRemovalInProgress { return .init(kind: .removing, headline: "Removing Études data from this device…") }
        if f.unlinked { return .init(kind: .off, headline: "Off", detail: "This device keeps everything it has; nothing is sent or received. What was uploaded stays in iCloud.") }
        let pending = JournalSyncPendingCounts.count(outbox: f.outbox, mediaWaitingUpload: f.mediaWaitingUpload, fileStampCache: f.fileStampCache)
        let kept = "Your journal and any changes stay on this device"
        if let reason = f.pausedReason, !reason.isEmpty {
            if reason.contains(differentAccountMarker) {
                return .init(kind: .attention, headline: "Linked to a different iCloud account",
                             detail: "This journal syncs with the iCloud account it was first turned on with. Nothing is uploaded or downloaded while this device is signed in to another one; \(kept.lowercased()).",
                             action: "Sign in to that iCloud account in Settings to continue syncing.")
            }
            if reason.hasPrefix(signedOutMarker) {
                return .init(kind: .attention, headline: "Signed out of iCloud",
                             detail: "\(kept), and are sent once iCloud is back.",
                             action: "Sign in to iCloud in Settings, and check that Études is allowed to use iCloud.")
            }
            if reason.hasPrefix(waitingMarker) {
                return .init(kind: .waiting, headline: "Waiting for iCloud", detail: "Checking your iCloud account. \(kept).")
            }
            return .init(kind: .paused, headline: "Paused", detail: reason)
        }
        if let full = f.storageFullSummary {
            return .init(kind: .attention, headline: "iCloud storage is full", detail: full,
                         action: "Free up iCloud storage, or buy more in Settings. Nothing is removed from this device.")
        }
        if !f.initialFetchComplete {
            var detail: String
            if !f.online {
                detail = "Waiting for a connection. Restoring continues when iCloud is reachable; you can keep using Études meanwhile."
            } else if let failure = f.lastCatchUp, failure.hasPrefix("Delta catch-up failed") {
                let sentence = failure.hasSuffix(".") ? String(failure.dropLast()) : failure
                detail = "\(sentence). It is tried again automatically."
            } else {
                detail = (f.restore ?? JournalRestoreProgress()).text
            }
            return .init(kind: .restoring, headline: "Restoring from iCloud", detail: detail)
        }
        if !f.online {
            let detail = pending.isEmpty
                ? "Everything on this device is in iCloud. Changes you make now are sent when the connection returns."
                : "Still to upload: \(pending.text). Sent when the connection returns."
            return .init(kind: .offline, headline: "Offline", detail: detail)
        }
        if f.mediaHold.holds, pending.files > 0 || !f.awaitingMedia.isEmpty {
            var waiting: [String] = []
            if pending.files > 0 { waiting.append("\(pending.files) file\(pending.files == 1 ? "" : "s")\(pending.bytes.map { " (\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)))" } ?? "") to send") }
            if !f.awaitingMedia.isEmpty { waiting.append("\(f.awaitingMedia.count) to receive") }
            switch f.mediaHold {
            case .lowDataMode:
                return .init(kind: .mediaHeld, headline: "Media paused by Low Data Mode",
                             detail: "\(waiting.joined(separator: ", ")). Text and settings still sync.",
                             action: "Turn off Low Data Mode in Settings to continue.")
            default:
                return .init(kind: .mediaHeld, headline: "Waiting for Wi-Fi",
                             detail: "\(waiting.joined(separator: ", ")). Text and settings still sync.",
                             action: "Turn on Media over mobile data below to send and receive them now.")
            }
        }
        if !pending.isEmpty {
            var detail = "Still to upload: \(pending.text)."
            if let failure = f.lastTransientFailure { detail += " Last attempt failed (\(failure)); trying again." }
            return .init(kind: .uploading, headline: "Uploading", detail: detail)
        }
        if !f.awaitingMedia.isEmpty {
            return .init(kind: .downloading, headline: "Downloading",
                         detail: "\(f.awaitingMedia.count) file\(f.awaitingMedia.count == 1 ? "" : "s") still to receive.")
        }
        if f.phase == "Checking iCloud account" {
            return .init(kind: .checking, headline: "Checking iCloud account")
        }
        var detail = "Everything on this device is in iCloud."
        if let at = f.lastFetchAt {
            let fm = DateFormatter()
            fm.dateFormat = Calendar.current.isDate(at, inSameDayAs: now) ? "HH:mm" : "d MMM HH:mm"
            detail += " Last checked \(fm.string(from: at))."
        }
        return .init(kind: .upToDate, headline: "Up to date", detail: detail)
    }
}
