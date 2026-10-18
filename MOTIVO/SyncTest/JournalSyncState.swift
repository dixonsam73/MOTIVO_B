//
//  JournalSyncState.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  THE TRIAL'S DURABLE STATE, IN ONE ATOMICALLY WRITTEN FILE.
//
//  Everything the sync trial must not lose if the app dies lives here: the
//  engine's own state serialization, the persistent-history token, whether the
//  existing journal has been queued for its first upload, the outbox of local
//  changes not yet accepted by CloudKit, the last server copy of each record
//  (its change tag), attachments held until their session arrives, the
//  conflict log and a diagnostics log.
//
//  Writing the outbox and the history token in the SAME write is what makes
//  the ordering rule trivial: the token can never be ahead of the pending work
//  it accounts for, because both land in one atomic replace or neither does.
//

#if SYNCTEST
import Foundation
import CloudKit
import CoreData

enum JournalSyncAuthor {
    /// The view context and every app-side background context. Anything that
    /// is NOT `sync` counts as a local change (contexts with no author too).
    static let app = "app"
    /// The import context only. Its transactions never re-enter the outbox.
    static let sync = "sync"
}

struct JournalSyncPendingChange: Codable, Hashable {
    enum Op: String, Codable { case save, delete }
    let recordName: String
    let recordType: String
    let op: Op
}

struct JournalSyncConflict: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let recordName: String
    let recordType: String
    /// "server" or "local"
    let winner: String
    let localUserModifiedAt: Date?
    let serverUserModifiedAt: Date?
    let losingTitle: String?
    let losingNotes: String?
}

struct JournalSyncLogEntry: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let text: String
}

/// An attachment record that arrived before its session. The asset file is
/// copied out of CloudKit's temporary location so it survives until the
/// session lands.
struct JournalSyncHeldAttachment: Codable {
    let recordData: Data
    let sessionRecordName: String
    let heldFilePath: String?
}

struct JournalSyncPersistedState: Codable {
    var engineState: CKSyncEngine.State.Serialization?
    var historyToken: Data?
    var bootstrapQueued = false
    var boundUserRecordName: String?
    var outbox: [JournalSyncPendingChange] = []
    var lastKnownRecords: [String: Data] = [:]
    var awaitingParent: [String: JournalSyncHeldAttachment] = [:]
    var conflicts: [JournalSyncConflict] = []
    var log: [JournalSyncLogEntry] = []
    var bytesSent: Int64 = 0
    var bytesReceived: Int64 = 0
    var recordsSent = 0
    var recordsReceived = 0
}

/// Thread-safe owner of `JournalSyncPersistedState`. Every mutation goes
/// through `update`, which rewrites the file atomically before returning.
final class JournalSyncStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private var current: JournalSyncPersistedState
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(JournalSyncPersistedState.self, from: data) {
            current = decoded
        } else {
            current = JournalSyncPersistedState()
        }
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncTest", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("JournalSyncState.json", isDirectory: false)
    }

    /// Where held asset files wait for their session.
    static func holdingDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncTest/Held", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var state: JournalSyncPersistedState {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Mutates and persists. Returns whether the write succeeded; on failure
    /// the in-memory state is rolled back so memory never runs ahead of disk.
    @discardableResult
    func update(_ body: (inout JournalSyncPersistedState) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var next = current
        body(&next)
        if next.log.count > 400 { next.log.removeFirst(next.log.count - 400) }
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: fileURL, options: [.atomic])
            current = next
            return true
        } catch {
            return false
        }
    }

    func log(_ text: String) {
        update { $0.log.append(JournalSyncLogEntry(at: Date(), text: text)) }
    }

    // MARK: history token helpers

    static func encode(token: NSPersistentHistoryToken?) -> Data? {
        guard let token else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func decodeToken(_ data: Data?) -> NSPersistentHistoryToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    // MARK: record helpers

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        return archiver.encodedData
    }

    static func recordFromSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }

    static func encodeWholeRecord(_ record: CKRecord) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
    }

    static func decodeWholeRecord(_ data: Data) -> CKRecord? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data)
    }
}
#endif
