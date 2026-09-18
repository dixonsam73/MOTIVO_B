//
//  SessionSyncQueueStore.swift
//  MOTIVO
//
//  PHASE 6 · BATCH 2 · UNIT 2a — THE QUEUE'S ON-DISK STORE.
//
//  P6-I-02. A queued intent used to carry no owner, in one installation-wide
//  file, which sign-out did not touch. The flush then stamped whoever was signed
//  in at that moment (`BackendShim.uploadPost`), so A's publish could upload as
//  B, to B's audience, with A's title, notes and media.
//
//  This unit does not fix the dispatch path — that is 2b. It makes the STORE
//  able to say whose an intent is, and refuses to hand over anything it cannot
//  attribute.
//
//  WHY THE FORMAT CHANGES. A `version` FIELD cannot protect a downgrade: the
//  previous loader decodes `[PostPublishPayload]` then `[UUID]`, and
//  `JSONDecoder` ignores unknown keys, so an older build would read a new file
//  and dispatch unowned work. A TOP-LEVEL OBJECT fails both of those decodes, so
//  an older build reading the v1 path finds the neutralised file and dispatches
//  nothing. The protection is the neutralised v1, not the envelope.
//
//  MIGRATION ORDER, validated in a disposable prototype before it was written
//  here (64 checks, and three counterexamples from review):
//
//      back up v1 verbatim -> verify -> neutralise v1 -> absorb -> write v2 -> read back
//
//  Neutralising BEFORE v2 exists is safe **because the verified immutable backup
//  is the recovery source**: a restart rebuilds v2 from the backups, never from
//  the emptied v1. An earlier design claimed this could not be done without
//  two-file atomicity; that was wrong.
//
//  VALIDATE WRITES NOTHING. Every inspection of existing state happens before any
//  mutation, so a refusal cannot leave the store half-migrated.
//
//  CRASH MODEL, STATED HONESTLY. Process interruption and I/O failure are
//  handled: a halt or an interrupted run is recoverable by re-running
//  `reconcile()`. **Power loss is NOT proven.** `Data.write(options:.atomic)`
//  renames without `fsync` of the file or its directory, and the recovery
//  argument REQUIRES THE VERIFIED BACKUP TO SURVIVE. If a neutralisation
//  survives and its backup does not, the work is lost. That is an assumption,
//  not something this code establishes.
//

import Foundation
import CryptoKit

// MARK: - Envelope

/// The v2 on-disk shape. A top-level object, deliberately.
public struct SessionSyncQueueEnvelope: Codable, Equatable {
    /// REQUIRED, never defaulted: an object without it must fail to decode
    /// rather than silently become "the supported version".
    public let formatVersion: Int

    /// Dispatchable work. Only ever items whose owner is known.
    public var items: [SessionSyncQueue.PostPublishPayload] = []

    /// Work whose owner cannot be established. **Never dispatchable**, never
    /// adopted by whoever is signed in, never deleted on a timer.
    public var quarantined: [SessionSyncQueue.PostPublishPayload] = []

    /// Backup content hashes already folded in, so absorption happens once.
    public var absorbed: [String] = []

    /// Backups whose bytes matched their name but decoded as no known shape.
    public var unreadableBackups: [String] = []

    /// P6-I-03 / C1. This install's stream id. OPTIONAL, so a store written
    /// before C1 decodes; the queue assigns one on first successful persist.
    public var installStream: UUID?

    /// P6-I-03 / C1. The handoff ledger: "owner|post" → the token of the latest
    /// saved choice the queue durably took. Ids only. Optional for the same reason.
    public var handedOff: [String: UUID]?

    public static let supported = 2
    public static func empty() -> Self { .init(formatVersion: supported) }
}

// MARK: - Outcome

public enum SessionSyncQueueReconcile: Equatable, Error {
    case ok
    case haltCorruptV2
    case haltUnsupportedVersion(Int)
    case haltBackupIntegrity(String)
    case haltBackupStoreUnusable
    case haltWriteFailed(String)
    case haltReadbackMismatch

    public var isOK: Bool { self == .ok }

    /// What the member is told. Deliberately factual: it does not promise that
    /// anything completes on its own, because after a halt nothing does.
    public var diagnostic: String {
        switch self {
        case .ok: return "ok"
        case .haltCorruptV2: return "queue file unreadable"
        case .haltUnsupportedVersion(let v): return "queue written by a newer version (\(v))"
        case .haltBackupIntegrity(let h): return "preserved copy failed its integrity check (\(h.prefix(8)))"
        case .haltBackupStoreUnusable: return "preserved copies unreadable"
        case .haltWriteFailed(let what): return "could not write \(what)"
        case .haltReadbackMismatch: return "written queue did not read back as written"
        }
    }
}

// MARK: - Store

/// Owns the queue's files. Knows nothing about flushing or networking.
@MainActor
final class SessionSyncQueueStore {

    private let root: URL
    let legacyURL: URL
    let currentURL: URL
    let backupDirectory: URL

    init(root: URL) {
        self.root = root
        self.legacyURL = root.appendingPathComponent("SessionSyncQueue_v1.json")
        self.currentURL = root.appendingPathComponent("SessionSyncQueue_v2.json")
        self.backupDirectory = root.appendingPathComponent("SessionSyncQueue_preserved", isDirectory: true)
    }

    // MARK: Validation — writes nothing

    private struct Validated {
        var envelope: SessionSyncQueueEnvelope
        var backups: [(hash: String, bytes: Data)]
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validate() -> Result<Validated, SessionSyncQueueReconcile> {
        let fm = FileManager.default

        var envelope = SessionSyncQueueEnvelope.empty()
        if fm.fileExists(atPath: currentURL.path) {
            guard let bytes = try? Data(contentsOf: currentURL) else { return .failure(.haltCorruptV2) }
            guard let decoded = try? JSONDecoder().decode(SessionSyncQueueEnvelope.self, from: bytes) else {
                // CORRUPT IS NOT EMPTY. The previous store did
                // `(try? load()) ?? []`, which turned an unreadable queue into
                // "no pending work" and lost it silently.
                return .failure(.haltCorruptV2)
            }
            guard decoded.formatVersion == SessionSyncQueueEnvelope.supported else {
                return .failure(.haltUnsupportedVersion(decoded.formatVersion))
            }
            envelope = decoded
        }

        var isDirectory: ObjCBool = false
        let backupsExist = fm.fileExists(atPath: backupDirectory.path, isDirectory: &isDirectory)
        if backupsExist && !isDirectory.boolValue { return .failure(.haltBackupStoreUnusable) }

        var entries: [URL] = []
        if backupsExist {
            guard let listed = try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil) else {
                // A failure to ENUMERATE must not become "there are no backups".
                return .failure(.haltBackupStoreUnusable)
            }
            entries = listed.filter { $0.pathExtension == "json" }
        }

        var backups: [(String, Data)] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.deletingPathExtension().lastPathComponent
            guard let bytes = try? Data(contentsOf: url) else { return .failure(.haltBackupIntegrity(name)) }
            // The NAME is the content hash, re-checked on EVERY run — including
            // the backup-only recovery path, where the original v1 no longer
            // exists to compare against.
            guard sha256(bytes) == name else { return .failure(.haltBackupIntegrity(name)) }
            backups.append((name, bytes))
        }

        return .success(Validated(envelope: envelope, backups: backups))
    }

    // MARK: Reconcile

    @discardableResult
    private func write(_ data: Data, to url: URL) -> Bool {
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }

    /// Brings the store to a consistent state and returns the dispatchable
    /// envelope, or a halt. Idempotent: safe to re-run after any interruption.
    func reconcile() -> (SessionSyncQueueReconcile, SessionSyncQueueEnvelope?) {
        let fm = FileManager.default

        let validated: Validated
        switch validate() {
        case .failure(let halt): return (halt, nil)
        case .success(let value): validated = value
        }
        var envelope = validated.envelope
        var backups = validated.backups

        // The legacy file is consulted on EVERY reconcile, not only when the
        // current file is missing. A non-empty v1 beside a valid v2 means an
        // older build ran and created new work, which must not be ignored.
        var legacyBytes: Data?
        if fm.fileExists(atPath: legacyURL.path) {
            guard let bytes = try? Data(contentsOf: legacyURL) else {
                return (.haltBackupIntegrity("legacy"), nil)
            }
            let decodesEmpty =
                (try? JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self, from: bytes))?.isEmpty == true
                || (try? JSONDecoder().decode([UUID].self, from: bytes))?.isEmpty == true
            if !bytes.isEmpty && !decodesEmpty { legacyBytes = bytes }
        }

        if let bytes = legacyBytes {
            if !fm.fileExists(atPath: backupDirectory.path) {
                guard (try? fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)) != nil else {
                    return (.haltWriteFailed("preserved directory"), nil)
                }
            }
            let hash = sha256(bytes)
            if let existing = backups.first(where: { $0.hash == hash }) {
                // Replay of an interrupted run. Reuse; never rewrite a backup.
                guard existing.bytes == bytes else { return (.haltBackupIntegrity(hash), nil) }
            } else {
                let backup = backupDirectory.appendingPathComponent("\(hash).json")
                guard write(bytes, to: backup) else { return (.haltWriteFailed("preserved copy"), nil) }
                guard let readBack = try? Data(contentsOf: backup), readBack == bytes else {
                    // v1 is NOT neutralised: the only copy is still the original.
                    return (.haltReadbackMismatch, nil)
                }
                backups.append((hash, bytes))
            }
            guard write(Data("[]".utf8), to: legacyURL) else {
                return (.haltWriteFailed("neutralise legacy"), nil)
            }
        }

        for backup in backups where !envelope.absorbed.contains(backup.hash) {
            if let items = try? JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self, from: backup.bytes) {
                envelope.quarantined.append(contentsOf: items)
            } else if let ids = try? JSONDecoder().decode([UUID].self, from: backup.bytes) {
                // The oldest shape on record: a bare array of post ids.
                envelope.quarantined.append(contentsOf: ids.map {
                    SessionSyncQueue.PostPublishPayload(id: $0, sessionID: nil, sessionTimestamp: nil,
                                                        title: nil, durationSeconds: nil, activityType: nil,
                                                        activityDetail: nil, instrumentLabel: nil,
                                                        mood: nil, effort: nil)
                })
            } else {
                envelope.unreadableBackups.append(backup.hash)
            }
            envelope.absorbed.append(backup.hash)
        }

        let intended = envelope
        guard let encoded = try? JSONEncoder().encode(intended) else {
            return (.haltWriteFailed("encode"), nil)
        }
        guard write(encoded, to: currentURL) else { return (.haltWriteFailed("queue file"), nil) }
        #if DEBUG
        if UnitTestHost.isActive { Self.unitTestCorruptAfterWrite?() }
        #endif
        guard let check = try? Data(contentsOf: currentURL),
              let decoded = try? JSONDecoder().decode(SessionSyncQueueEnvelope.self, from: check),
              decoded == intended else {
            return (.haltReadbackMismatch, nil)
        }

        return (.ok, intended)
    }

    /// Persists an envelope produced by a SUCCESSFUL reconcile. Returns false on
    /// any write or readback failure, which the caller must not treat as durable.
    func persist(_ envelope: SessionSyncQueueEnvelope) -> Bool {
        guard envelope.formatVersion == SessionSyncQueueEnvelope.supported else { return false }
        guard let encoded = try? JSONEncoder().encode(envelope), write(encoded, to: currentURL) else { return false }
        #if DEBUG
        if UnitTestHost.isActive { Self.unitTestCorruptAfterWrite?() }
        #endif
        guard let check = try? Data(contentsOf: currentURL),
              let decoded = try? JSONDecoder().decode(SessionSyncQueueEnvelope.self, from: check),
              decoded == envelope else { return false }
        return true
    }

    /// Factory reset. Removes every file this store owns, preserved copies too.
    func wipe() {
        let fm = FileManager.default
        for url in [currentURL, legacyURL] where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
        if fm.fileExists(atPath: backupDirectory.path) { try? fm.removeItem(at: backupDirectory) }
    }

    #if DEBUG
    /// P6-I-01 precedent. TEST-ONLY, hosted test runs only. Forces the next
    /// readback comparison to fail, so the mismatch branch is exercised
    /// deterministically rather than asserted from ordinary fields.
    nonisolated(unsafe) static var unitTestCorruptAfterWrite: (() -> Void)?
    #endif
}
