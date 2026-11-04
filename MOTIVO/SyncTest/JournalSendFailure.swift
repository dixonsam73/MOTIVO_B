//
//  JournalSendFailure.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  WHAT A FAILED SAVE MEANS, AND ICLOUD STORAGE FULL.
//
//  CKSyncEngine retries transient errors itself (network, rate limit, zone
//  busy, authentication) and keeps those changes pending. Everything else it
//  drops from its pending list and leaves to the app. `quotaExceeded` — the
//  person's iCloud storage is full — is one of those: the save is refused,
//  the engine forgets the change, and nothing goes up until space exists.
//
//  The rule (Samuel, 2026-11-03): nothing is dropped from the outbox or the
//  journal; held media keeps waiting; the status says the storage is full and
//  what waits; retries are controlled (no tight loop: a retry on the next
//  change, push, poll or foreground, at most every few minutes, logged once
//  per episode, not per attempt); once space is available the pending work
//  goes up once, in order, without duplicates. The outbox is the durable
//  record of what waits (a save leaves it only when the server accepts it),
//  so a retry re-adds the outbox to the engine and sends.
//

import Foundation
import CloudKit

/// PURE. What the app does with one failed record save.
enum JournalSendFailure {
    enum Action: Equatable {
        /// `serverRecordChanged`: apply the trial's conflict rule, resend if ours wins.
        case resolveConflict
        /// `zoneNotFound`: queue the zone again and resend.
        case recreateZone
        /// `unknownItem`: the server no longer has it; resend as a new record.
        case resendAsNew
        /// Transient: the engine keeps the change and retries it.
        case engineRetries
        /// `quotaExceeded`: iCloud storage is full; the engine drops the change
        /// and the app retries from the outbox on its own cadence.
        case storageFull
        /// Anything else: logged; the outbox keeps the change for the next activation.
        case unexpected
    }

    static func action(for code: CKError.Code) -> Action {
        switch code {
        case .serverRecordChanged: return .resolveConflict
        case .zoneNotFound: return .recreateZone
        case .unknownItem: return .resendAsNew
        case .quotaExceeded: return .storageFull
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .notAuthenticated, .accountTemporarilyUnavailable:
            return .engineRetries
        default: return .unexpected
        }
    }
}

/// PURE. B2 (2026-11-03): what an accepted save does to the outbox. The entry
/// leaves only when nothing merged into it after the batch was built; a later
/// revision stays and is sent again with its current values.
enum JournalOutboxSettle {
    static func settle(name: String, sentRevision: Int?, outbox: [JournalSyncPendingChange]) -> (outbox: [JournalSyncPendingChange], keptNewer: Bool) {
        guard let i = outbox.firstIndex(where: { $0.recordName == name && $0.op == .save }) else { return (outbox, false) }
        if let sentRevision, outbox[i].revision > sentRevision { return (outbox, true) }
        var out = outbox
        out.remove(at: i)
        return (out, false)
    }
}

/// PURE. One storage-full episode: from the first refused save to the first
/// accepted one. The engine keeps it in the state file so the status is right
/// at the next launch and the diagnostics can show when it began.
enum JournalStorageFull {
    struct Episode: Codable, Equatable {
        /// When the first save of this episode was refused.
        var began: Date
        /// Failed attempts in this episode (at least 1).
        var attempts: Int
        var lastFailureAt: Date
        /// The Journal zone itself could not be created, so it is queued again
        /// with the records at the next attempt.
        var zoneSaveFailed: Bool = false
        /// Begun by the diagnostics switch, not by the server.
        var simulated: Bool = false
    }

    static func isStorageFull(_ code: CKError.Code) -> Bool { code == .quotaExceeded }

    /// The floor between attempts, and the ceiling of the backoff.
    static let minimumRetryInterval: TimeInterval = 2 * 60
    static let maximumRetryInterval: TimeInterval = 15 * 60

    /// Records one refused attempt. `began` is true when this starts the
    /// episode, which is the one moment the engine logs.
    static func noting(failureAt now: Date, zone: Bool, simulated: Bool, in episode: Episode?) -> (episode: Episode, began: Bool) {
        if var episode {
            episode.attempts += 1
            episode.lastFailureAt = now
            episode.zoneSaveFailed = episode.zoneSaveFailed || zone
            return (episode, false)
        }
        return (Episode(began: now, attempts: 1, lastFailureAt: now, zoneSaveFailed: zone, simulated: simulated), true)
    }

    /// After n refused attempts: 2, 4, 8 minutes, then every 15.
    static func retryInterval(attempts: Int) -> TimeInterval {
        guard attempts >= 1 else { return minimumRetryInterval }
        return min(maximumRetryInterval, minimumRetryInterval * pow(2, Double(attempts - 1)))
    }

    /// When the next attempt is allowed. A user-driven trigger (the app
    /// coming to the foreground, a local change, activation, a tap) waits only
    /// the floor; an automatic one (push, poll, a release) follows the backoff.
    static func nextRetryAt(_ episode: Episode, userDriven: Bool) -> Date {
        episode.lastFailureAt.addingTimeInterval(userDriven ? minimumRetryInterval : retryInterval(attempts: episode.attempts))
    }

    /// Whether a send may be attempted now. No episode: always.
    static func retryDue(_ episode: Episode?, now: Date, userDriven: Bool) -> Bool {
        guard let episode else { return true }
        return now >= nextRetryAt(episode, userDriven: userDriven)
    }

    /// Whether a sent batch ends the episode. A saved record proves there is
    /// space. A deletion can succeed while the storage is full, and a zone
    /// save is tiny, so either counts only when no save is left waiting.
    static func recovered(savedRecords: Int, savedZones: Int, deletedRecords: Int, quotaFailures: Int, savesStillPending: Int) -> Bool {
        guard quotaFailures == 0 else { return false }
        if savedRecords > 0 { return true }
        return (savedZones > 0 || deletedRecords > 0) && savesStillPending == 0
    }

    /// The person-facing line. "iCloud storage is full (since 14:02): 7 changes
    /// waiting, 2 with media. They are sent when space is available; nothing
    /// is removed from this device."
    static func summary(episode: Episode, pendingSaves: Int, pendingDeletes: Int, mediaFiles: Int, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDate(episode.began, inSameDayAs: now) ? "HH:mm" : "d MMM HH:mm"
        let waiting = pendingSaves + pendingDeletes
        var text = "iCloud storage is full (since \(f.string(from: episode.began))\(episode.simulated ? ", simulated" : "")): "
        if waiting == 0 {
            text += "nothing waiting."
        } else {
            text += "\(waiting) change\(waiting == 1 ? "" : "s") waiting"
            if mediaFiles > 0 { text += ", \(mediaFiles) with media" }
            text += ". \(waiting == 1 ? "It is" : "They are") sent when space is available; nothing is removed from this device."
        }
        return text
    }

    /// The diagnostics-only simulation is bounded: nil or past means off.
    static func simulationActive(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now < until
    }
}
