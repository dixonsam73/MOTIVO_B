//
//  JournalScoreSync.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  SCORES LIBRARY ↔ CLOUDKIT (stage I): the whole library, including
//  documents no journal entry refers to. The library stays where it is (one
//  JSON index in UserDefaults, PDFs in Documents/Scores); sync adds state-file
//  entries only.
//
//  Three records per item, all named from the item's id:
//    `Score`         "score-<id>"           the PDF as a CKAsset with its
//                                           SHA-256, file name, page count,
//                                           creation date, C-5 source id and
//                                           the title at creation. Written
//                                           once; a library PDF never changes.
//    `ScoreMeta`     "score-<id>-meta"      title, favourite, cover page, clock.
//    `ScorePosition` "score-<id>-position"  last viewed page, its own clock,
//                                           so a page turn can never displace
//                                           a rename (whole-record conflicts).
//  A rename, favourite or cover change queues the meta record alone, which
//  carries no file and makes the receiver fetch none (stage G's separation).
//
//  Change detection is a fingerprint scan (as for Lists and the profile): the
//  store's write points call `JournalScoreMirror`; the engine scans after a
//  3 s pause for metadata and a 10 s idle pause, the viewer's close or the
//  app going to the background for positions. The first scan is the
//  transition: every existing item is queued with its file, its metadata
//  without a clock (a real edit anywhere beats it) and its position likewise.
//
//  Combining libraries: union by id. Ids and file names are UUIDs minted at
//  import, so two libraries are disjoint and nothing is merged, whatever the
//  titles or the bytes. The same id on both devices (a restored copy) meets
//  through the existing rule: newer clock wins the whole meta record, ties to
//  the server, the displaced values in the conflict log; a differing FILE for
//  the same id takes the server's and keeps the local one as a displaced copy.
//  A repeated import of the same id updates the one item, never a second.
//
//  A damaged index (C-139) is reported once, sends nothing and infers no
//  deletion. Device-local, never synced: the currently open score and the
//  last-opened date.
//

#if SYNCTEST
import Foundation
import CloudKit
import CryptoKit

extension JournalSyncRecordType {
    static let score = "Score"
    static let scoreMeta = "ScoreMeta"
    static let scorePosition = "ScorePosition"
    static let scoreTypes: Set<String> = [score, scoreMeta, scorePosition]
    static let scorePrefix = "score-"
    static let scoreMetaSuffix = "-meta"
    static let scorePositionSuffix = "-position"

    static func scoreName(for id: String) -> String { scorePrefix + id }
    static func scoreMetaName(for id: String) -> String { scorePrefix + id + scoreMetaSuffix }
    static func scorePositionName(for id: String) -> String { scorePrefix + id + scorePositionSuffix }
    static func isScoreRecordName(_ name: String) -> Bool { name.hasPrefix(scorePrefix) }

    enum ScoreRecordKind { case content, meta, position }

    /// (item id, kind) for any of the three names; nil for other names.
    static func scoreRecord(fromName name: String) -> (id: String, kind: ScoreRecordKind)? {
        guard name.hasPrefix(scorePrefix) else { return nil }
        let rest = String(name.dropFirst(scorePrefix.count))
        if rest.hasSuffix(scoreMetaSuffix) { return (String(rest.dropLast(scoreMetaSuffix.count)), .meta) }
        if rest.hasSuffix(scorePositionSuffix) { return (String(rest.dropLast(scorePositionSuffix.count)), .position) }
        return (rest, .content)
    }

    static func scoreType(for kind: ScoreRecordKind) -> String {
        switch kind {
        case .content: return score
        case .meta: return scoreMeta
        case .position: return scorePosition
        }
    }
}

enum JournalScoreKeys {
    static let fileName = "fileName"
    static let pageCount = "pageCount"
    static let createdAt = "createdAt"
    static let sourceAttachmentID = "sourceAttachmentID"
    /// The title when the item was made, on the content record so a receiver
    /// that gets the file before the meta record has a name to show.
    static let initialTitle = "initialTitle"
    static let title = "title"
    static let isFavourite = "isFavourite"
    static let thumbnailPage = "thumbnailPage"
    static let lastViewedPage = "lastViewedPage"
    static let stamp = "userModifiedAt"
    static var all: [String] { [fileName, pageCount, createdAt, sourceAttachmentID, initialTitle, title, isFavourite, thumbnailPage, lastViewedPage, stamp] }
}

/// The store's write points call this (SYNCTEST only). Installed by the engine.
enum JournalScoreMirror {
    nonisolated(unsafe) static var suppressed = false
    nonisolated(unsafe) static var onChange: ((ScoreLibraryChange) -> Void)?
    nonisolated(unsafe) static var onViewerClosed: (() -> Void)?

    static func changed(_ change: ScoreLibraryChange) { guard !suppressed else { return }; onChange?(change) }
    static func viewerClosed() { onViewerClosed?() }
}

/// PURE pieces of the stage: fingerprints and the position rule.
enum JournalScoreValues {
    private static let separator = "\u{1F}"

    /// What the meta record carries. The last-opened date and the currently
    /// open score are device-local and never part of it.
    static func metaFingerprint(title: String, isFavourite: Bool, thumbnailPage: Int) -> String {
        ["v1", title, isFavourite ? "1" : "0", String(thumbnailPage)].joined(separator: separator)
    }

    static func metaFingerprint(_ item: ScoreLibraryItem) -> String {
        metaFingerprint(title: item.title, isFavourite: item.isFavourite, thumbnailPage: item.thumbnailPage)
    }

    static func clamp(page: Int, pageCount: Int) -> Int { min(max(page, 1), max(pageCount, 1)) }

    enum PositionOutcome: Equatable { case same, takeServer, keepLocal }

    /// The newer clock wins; no clock counts as the distant past; ties to the server.
    static func decidePosition(localPage: Int?, localStamp: Date?, serverPage: Int?, serverStamp: Date?) -> PositionOutcome {
        if localPage == serverPage { return .same }
        switch JournalConflictRule.decide(localUserModifiedAt: localStamp, serverUserModifiedAt: serverStamp) {
        case .server: return .takeServer
        case .local: return .keepLocal
        }
    }
}

/// Reads the library snapshot, scans for changes, builds and applies records.
enum JournalScoreSync {
    static let displacedDirectoryName = "SyncTest/DisplacedScores"

    // MARK: Scan (local changes → outbox)

    /// Compares the library with what was last sent or received and queues what
    /// changed, recording fingerprints, clocks and the outbox in one write.
    /// `positions` includes reading positions (their own cadence). A damaged
    /// index sends nothing and infers no deletion.
    @discardableResult
    static func scan(snapshot: ScoreLibrarySnapshot, store: JournalSyncStateStore, positions: Bool, now: Date = Date(),
                     log: (String) -> Void = { _ in }) -> [JournalSyncPendingChange] {
        let st = store.state
        guard !st.localRemovalInProgress else { return [] }
        if snapshot.indexDamaged {
            if !st.scoreIndexDamagedNoted {
                store.update { $0.scoreIndexDamagedNoted = true }
                log("Scores: the library index could not be read; nothing is sent and no deletion is inferred (C-139)")
            }
            return []
        }
        let transition = !st.scoreScanDone
        var pending: [JournalSyncPendingChange] = []
        var fingerprints = st.scoreFingerprints
        var stamps = st.scoreStamps
        var positionsKnown = st.scorePositions
        var positionStamps = st.scorePositionStamps
        var present = Set<String>()
        var sentFiles = 0

        for item in snapshot.items {
            let id = item.id.uuidString
            present.insert(id)
            let contentName = JournalSyncRecordType.scoreName(for: id)
            let metaName = JournalSyncRecordType.scoreMetaName(for: id)
            let fp = JournalScoreValues.metaFingerprint(item)
            if let known = fingerprints[id] {
                if known != fp {
                    stamps[id] = now
                    fingerprints[id] = fp
                    pending.append(.init(recordName: metaName, recordType: JournalSyncRecordType.scoreMeta, op: .save, metadataEdit: true))
                }
            } else {
                // First sight of this item. At the transition it predates sync:
                // sent without a clock. Later it is new here: an edit.
                fingerprints[id] = fp
                if st.assetHashes[contentName] == nil, !st.outbox.contains(where: { $0.recordName == contentName }) {
                    pending.append(.init(recordName: contentName, recordType: JournalSyncRecordType.score, op: .save))
                    sentFiles += 1
                }
                if transition {
                    pending.append(.init(recordName: metaName, recordType: JournalSyncRecordType.scoreMeta, op: .save, metadataOnly: true))
                } else {
                    stamps[id] = now
                    pending.append(.init(recordName: metaName, recordType: JournalSyncRecordType.scoreMeta, op: .save, metadataEdit: true))
                }
            }
            if positions, let page = item.lastViewedPage {
                let positionName = JournalSyncRecordType.scorePositionName(for: id)
                if let known = positionsKnown[id] {
                    if known != page {
                        positionStamps[id] = now
                        positionsKnown[id] = page
                        pending.append(.init(recordName: positionName, recordType: JournalSyncRecordType.scorePosition, op: .save, metadataEdit: true))
                    }
                } else {
                    positionsKnown[id] = page
                    if transition {
                        pending.append(.init(recordName: positionName, recordType: JournalSyncRecordType.scorePosition, op: .save, metadataOnly: true))
                    } else {
                        positionStamps[id] = now
                        pending.append(.init(recordName: positionName, recordType: JournalSyncRecordType.scorePosition, op: .save, metadataEdit: true))
                    }
                }
            }
        }
        var deleted = 0
        for id in st.scoreFingerprints.keys where !present.contains(id) {
            deleted += 1
            fingerprints.removeValue(forKey: id)
            stamps.removeValue(forKey: id)
            positionsKnown.removeValue(forKey: id)
            positionStamps.removeValue(forKey: id)
            pending.append(.init(recordName: JournalSyncRecordType.scoreName(for: id), recordType: JournalSyncRecordType.score, op: .delete))
            pending.append(.init(recordName: JournalSyncRecordType.scoreMetaName(for: id), recordType: JournalSyncRecordType.scoreMeta, op: .delete))
            pending.append(.init(recordName: JournalSyncRecordType.scorePositionName(for: id), recordType: JournalSyncRecordType.scorePosition, op: .delete))
        }
        let changed = !pending.isEmpty || transition || fingerprints != st.scoreFingerprints || positionsKnown != st.scorePositions
        guard changed else { return [] }
        let ok = store.update { s in
            JournalChangeTracker.merge(pending, into: &s.outbox)
            s.scoreFingerprints = fingerprints
            s.scoreStamps = stamps
            s.scorePositions = positionsKnown
            s.scorePositionStamps = positionStamps
            s.scoreScanDone = true
            for id in st.scoreFingerprints.keys where !present.contains(id) {
                for name in [JournalSyncRecordType.scoreName(for: id), JournalSyncRecordType.scoreMetaName(for: id),
                             JournalSyncRecordType.scorePositionName(for: id)] {
                    s.assetHashes.removeValue(forKey: name)
                    s.fileStampCache.removeValue(forKey: name)
                }
            }
        }
        if ok, transition {
            log("Scores transition: \(snapshot.items.count) item(s) queued, \(sentFiles) with a file, metadata and positions without a clock")
        } else if ok, deleted > 0 {
            log("Scores: \(deleted) item(s) deleted here; deletions queued")
        }
        return ok ? pending : []
    }

    // MARK: Records (library → CKRecord)

    /// The outgoing record for any of the three names, or nil when there is
    /// nothing to send (the caller drops the pending change). The file goes
    /// only when the server has none or a different hash (stage D).
    static func record(for name: String, snapshot: ScoreLibrarySnapshot, store: JournalSyncStateStore,
                       log: (String) -> Void = { _ in }) -> CKRecord? {
        guard let parsed = JournalSyncRecordType.scoreRecord(fromName: name),
              let uuid = UUID(uuidString: parsed.id),
              let item = snapshot.items.first(where: { $0.id == uuid }) else { return nil }
        let type = JournalSyncRecordType.scoreType(for: parsed.kind)
        let base = store.state.lastKnownRecords[name].flatMap(JournalSyncStateStore.recordFromSystemFields)
        let record = (base?.recordType == type ? base : nil)
            ?? CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: JournalRecordMapping.zoneID))
        switch parsed.kind {
        case .content:
            let url = snapshot.url(for: item)
            guard FileManager.default.fileExists(atPath: url.path) else {
                log("Score \(parsed.id.prefix(8))… has no file here; not sent")
                return nil
            }
            var localHash: String?
            if let cached = JournalAssetHash.cachedHash(of: url, cache: store.state.fileStampCache[name]) {
                localHash = cached.hash
                store.update { $0.fileStampCache[name] = cached.entry }
            }
            let include = JournalAssetPolicy.includeAsset(hasServerCopy: base != nil, serverHash: store.state.assetHashes[name], localHash: localHash)
            if include {
                record[JournalRecordMapping.assetKey] = CKAsset(fileURL: url)
                record[JournalRecordMapping.fileHashKey] = localHash.map { $0 as CKRecordValue }
            }
            record[JournalRecordMapping.fileExtKey] = url.pathExtension as CKRecordValue
            record[JournalScoreKeys.fileName] = item.fileName as CKRecordValue
            record[JournalScoreKeys.pageCount] = NSNumber(value: item.pageCount)
            record[JournalScoreKeys.createdAt] = item.createdAt as CKRecordValue
            record[JournalScoreKeys.sourceAttachmentID] = item.sourceAttachmentID.map { $0.uuidString as CKRecordValue }
            if record[JournalScoreKeys.initialTitle] == nil { record[JournalScoreKeys.initialTitle] = item.title as CKRecordValue }
        case .meta:
            record[JournalScoreKeys.title] = item.title as CKRecordValue
            record[JournalScoreKeys.isFavourite] = NSNumber(value: item.isFavourite)
            record[JournalScoreKeys.thumbnailPage] = NSNumber(value: item.thumbnailPage)
            record[JournalScoreKeys.stamp] = store.state.scoreStamps[parsed.id].map { $0 as CKRecordValue }
        case .position:
            guard let page = item.lastViewedPage else { return nil }
            record[JournalScoreKeys.lastViewedPage] = NSNumber(value: page)
            record[JournalScoreKeys.stamp] = store.state.scorePositionStamps[parsed.id].map { $0 as CKRecordValue }
        }
        return record
    }

    // MARK: Import (CKRecord → library)

    struct Outcome {
        var applied = 0
        var held = 0
        var bytesWritten: Int64 = 0
        var assetBytes: Int64 = 0
        var resend: [JournalSyncPendingChange] = []
        /// Names whose pending save the import settled (the engine's own list must drop them too).
        var settled: [String] = []
    }

    /// Applies a batch: content first (so held metadata lands on the item),
    /// then meta, then positions. Must run on the main actor (the store's).
    @MainActor
    static func apply(_ records: [CKRecord], store: JournalSyncStateStore, library: ScoreLibraryStore,
                      localPending: Bool? = nil, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let order: [String: Int] = [JournalSyncRecordType.score: 0, JournalSyncRecordType.scoreMeta: 1, JournalSyncRecordType.scorePosition: 2]
        for record in records.sorted(by: { (order[$0.recordType] ?? 3) < (order[$1.recordType] ?? 3) }) {
            let one: Outcome
            switch record.recordType {
            case JournalSyncRecordType.score: one = applyContent(record, store: store, library: library, localPending: localPending, log: log)
            case JournalSyncRecordType.scoreMeta: one = applyMeta(record, store: store, library: library, localPending: localPending, log: log)
            case JournalSyncRecordType.scorePosition: one = applyPosition(record, store: store, library: library, localPending: localPending, log: log)
            default: continue
            }
            outcome.applied += one.applied; outcome.held += one.held
            outcome.bytesWritten += one.bytesWritten; outcome.assetBytes += one.assetBytes
            outcome.resend += one.resend; outcome.settled += one.settled
        }
        return outcome
    }

    private static func isPending(_ name: String, store: JournalSyncStateStore, override: Bool?) -> (pending: Bool, transition: Bool) {
        if let override { return (override, store.state.outbox.first { $0.recordName == name && $0.op == .save }?.metadataOnly ?? false) }
        guard let change = store.state.outbox.first(where: { $0.recordName == name && $0.op == .save }) else { return (false, false) }
        return (true, change.metadataOnly)
    }

    private static func hold(_ record: CKRecord, store: JournalSyncStateStore, log: (String) -> Void) -> Outcome {
        let name = record.recordID.recordName
        if let data = JournalSyncStateStore.encodeWholeRecord(record) {
            store.update { $0.awaitingScore[name] = data }
            log("Holding \(name) until its score arrives")
        }
        var outcome = Outcome(); outcome.held = 1
        return outcome
    }

    @MainActor
    static func applyContent(_ record: CKRecord, store: JournalSyncStateStore, library: ScoreLibraryStore,
                             localPending: Bool? = nil, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let name = record.recordID.recordName
        guard let parsed = JournalSyncRecordType.scoreRecord(fromName: name), let uuid = UUID(uuidString: parsed.id) else { return outcome }
        if library.indexDamaged {
            log("Score \(parsed.id.prefix(8))… not applied: the library index could not be read (C-139)")
            return outcome
        }
        let asset = record[JournalRecordMapping.assetKey] as? CKAsset
        let sourceURL = asset?.fileURL
        if let sourceURL { outcome.assetBytes = JournalAssetHash.stamp(of: sourceURL)?.size ?? 0 }
        let serverHash = record[JournalRecordMapping.fileHashKey] as? String
        let fileName = (record[JournalScoreKeys.fileName] as? String) ?? "\(parsed.id).pdf"
        let snapshot = library.snapshot()

        if let item = snapshot.items.first(where: { $0.id == uuid }) {
            // The same id here: a repeated import, our own copy, or a restored copy.
            let url = snapshot.url(for: item)
            let known = store.state.assetHashes[name]
            var localHash: String?
            if FileManager.default.fileExists(atPath: url.path),
               let cached = JournalAssetHash.cachedHash(of: url, cache: store.state.fileStampCache[name]) {
                localHash = cached.hash
                store.update { $0.fileStampCache[name] = cached.entry }
            }
            if localHash == nil {
                // Index entry without a file: the server's file fills it in.
                if let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) {
                    if copy(sourceURL, to: url, log: log) {
                        outcome.bytesWritten = JournalAssetHash.stamp(of: url)?.size ?? 0
                        log("Score \(parsed.id.prefix(8))…: missing file restored from the other device")
                    }
                } else {
                    log("Score \(parsed.id.prefix(8))… has no file here and the record carried none; waiting for a fetch that does")
                    return outcome
                }
            } else if let serverHash, serverHash != localHash, known != serverHash || known == nil {
                // A different file for the same id. Ties go to the server; the
                // local file is kept as a displaced copy, restorable by hand.
                guard let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
                    log("Score \(parsed.id.prefix(8))…: the server's file differs but the record carried none; waiting for a fetch that does")
                    return outcome
                }
                keepDisplaced(url, hash: localHash ?? "", recordName: name, store: store)
                if copy(sourceURL, to: url, log: log) {
                    outcome.bytesWritten = JournalAssetHash.stamp(of: url)?.size ?? 0
                    store.update { $0.fileStampCache.removeValue(forKey: name) }
                    log("Score \(parsed.id.prefix(8))…: a different file for the same id; the server's kept, the local one set aside")
                }
            }
            outcome.applied = 1
            store.update { s in
                if let hash = serverHash ?? localHash { s.assetHashes[name] = hash }
                s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                s.outbox.removeAll { $0.recordName == name && $0.op == .save }
                s.awaitingScore.removeValue(forKey: name)
            }
            outcome.settled.append(name)
        } else {
            // New here: the file first, then the index entry.
            guard let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
                return hold(record, store: store, log: log)
            }
            let destination = snapshot.directory.appendingPathComponent(fileName, isDirectory: false)
            try? FileManager.default.createDirectory(at: snapshot.directory, withIntermediateDirectories: true)
            guard copy(sourceURL, to: destination, log: log) else { return outcome }
            BackupPolicy.include(destination)
            outcome.bytesWritten = JournalAssetHash.stamp(of: destination)?.size ?? 0
            let pageCount = max((record[JournalScoreKeys.pageCount] as? NSNumber)?.intValue ?? PDFSelectedPagesStore.pageCount(for: destination), 1)
            // Held metadata and position land with the item.
            let metaName = JournalSyncRecordType.scoreMetaName(for: parsed.id)
            let positionName = JournalSyncRecordType.scorePositionName(for: parsed.id)
            let heldMeta = store.state.awaitingScore[metaName].flatMap(JournalSyncStateStore.decodeWholeRecord)
            let heldPosition = store.state.awaitingScore[positionName].flatMap(JournalSyncStateStore.decodeWholeRecord)
            let title = (heldMeta?[JournalScoreKeys.title] as? String) ?? (record[JournalScoreKeys.initialTitle] as? String) ?? "Untitled Score"
            let item = ScoreLibraryItem(
                id: uuid,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Score" : title,
                fileName: fileName,
                pageCount: pageCount,
                thumbnailPage: (heldMeta?[JournalScoreKeys.thumbnailPage] as? NSNumber)?.intValue ?? 1,
                isFavourite: (heldMeta?[JournalScoreKeys.isFavourite] as? NSNumber)?.boolValue ?? false,
                createdAt: (record[JournalScoreKeys.createdAt] as? Date) ?? Date(),
                lastOpenedAt: nil,
                lastViewedPage: (heldPosition?[JournalScoreKeys.lastViewedPage] as? NSNumber).map { JournalScoreValues.clamp(page: $0.intValue, pageCount: pageCount) },
                sourceAttachmentID: (record[JournalScoreKeys.sourceAttachmentID] as? String).flatMap(UUID.init(uuidString:))
            )
            guard library.applyImported(item) else {
                log("Score \(parsed.id.prefix(8))…: the index could not be written; file kept, record not applied")
                return outcome
            }
            outcome.applied = 1 + (heldMeta == nil ? 0 : 1) + (heldPosition == nil ? 0 : 1)
            let hash = serverHash ?? JournalAssetHash.hash(of: destination)
            store.update { s in
                if let hash { s.assetHashes[name] = hash }
                s.fileStampCache.removeValue(forKey: name)
                s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                s.scoreFingerprints[parsed.id] = JournalScoreValues.metaFingerprint(item)
                s.scoreScanDone = true
                if let heldMeta {
                    s.lastKnownRecords[metaName] = JournalSyncStateStore.encodeSystemFields(heldMeta)
                    if let stamp = heldMeta[JournalScoreKeys.stamp] as? Date { s.scoreStamps[parsed.id] = stamp }
                }
                if let heldPosition, let page = item.lastViewedPage {
                    s.lastKnownRecords[positionName] = JournalSyncStateStore.encodeSystemFields(heldPosition)
                    s.scorePositions[parsed.id] = page
                    if let stamp = heldPosition[JournalScoreKeys.stamp] as? Date { s.scorePositionStamps[parsed.id] = stamp }
                }
                s.awaitingScore.removeValue(forKey: name)
                s.awaitingScore.removeValue(forKey: metaName)
                s.awaitingScore.removeValue(forKey: positionName)
            }
            log("Score \(parsed.id.prefix(8))… “\(item.title)” from the other device (\(outcome.bytesWritten) bytes)\(heldMeta == nil ? "" : ", held metadata applied")")
        }
        return outcome
    }

    @MainActor
    static func applyMeta(_ record: CKRecord, store: JournalSyncStateStore, library: ScoreLibraryStore,
                          localPending: Bool? = nil, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let name = record.recordID.recordName
        guard let parsed = JournalSyncRecordType.scoreRecord(fromName: name), let uuid = UUID(uuidString: parsed.id) else { return outcome }
        guard let item = library.items.first(where: { $0.id == uuid }) else { return hold(record, store: store, log: log) }
        let st = store.state
        let (pending, transitionCopy) = isPending(name, store: store, override: localPending)
        let serverTitle = (record[JournalScoreKeys.title] as? String) ?? item.title
        let serverFavourite = (record[JournalScoreKeys.isFavourite] as? NSNumber)?.boolValue ?? item.isFavourite
        let serverCover = (record[JournalScoreKeys.thumbnailPage] as? NSNumber)?.intValue ?? item.thumbnailPage
        let serverStamp = record[JournalScoreKeys.stamp] as? Date
        let localStamp = st.scoreStamps[parsed.id]
        let localFP = JournalScoreValues.metaFingerprint(item)
        let serverFP = JournalScoreValues.metaFingerprint(title: serverTitle, isFavourite: serverFavourite, thumbnailPage: serverCover)

        if localFP == serverFP {
            store.update { s in
                s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                s.scoreFingerprints[parsed.id] = localFP
                if !pending || transitionCopy { s.scoreStamps[parsed.id] = serverStamp; s.outbox.removeAll { $0.recordName == name && $0.op == .save } }
                s.awaitingScore.removeValue(forKey: name)
            }
            if !pending || transitionCopy { outcome.settled.append(name) }
            return outcome
        }
        let winner: JournalConflictWinner = transitionCopy ? .server
            : JournalConflictRule.decide(localUserModifiedAt: localStamp, serverUserModifiedAt: serverStamp)
        switch winner {
        case .local:
            // Kept; sent again on top of the server's change tag.
            store.update { s in
                s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                s.conflicts.append(JournalSyncConflict(at: Date(), recordName: name, recordType: JournalSyncRecordType.scoreMeta, winner: "local",
                                                       localUserModifiedAt: localStamp, serverUserModifiedAt: serverStamp,
                                                       losingTitle: "displaced (other device): " + describe(title: serverTitle, favourite: serverFavourite, cover: serverCover),
                                                       losingNotes: nil))
            }
            if !pending {
                let change = JournalSyncPendingChange(recordName: name, recordType: JournalSyncRecordType.scoreMeta, op: .save, metadataEdit: true)
                outcome.resend.append(change)
                store.update { JournalChangeTracker.merge([change], into: &$0.outbox) }
            }
            log("Score metadata \(parsed.id.prefix(8))…: local newer; kept and resent")
        case .server:
            JournalScoreMirror.suppressed = true
            let ok = library.applyImportedMetadata(id: uuid, title: serverTitle, isFavourite: serverFavourite, thumbnailPage: serverCover)
            JournalScoreMirror.suppressed = false
            guard ok else { log("Score metadata \(parsed.id.prefix(8))…: the index could not be written"); return outcome }
            outcome.applied = 1
            store.update { s in
                s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                s.scoreFingerprints[parsed.id] = serverFP
                s.scoreStamps[parsed.id] = serverStamp
                s.outbox.removeAll { $0.recordName == name && $0.op == .save }
                s.awaitingScore.removeValue(forKey: name)
                s.conflicts.append(JournalSyncConflict(at: Date(), recordName: name, recordType: JournalSyncRecordType.scoreMeta, winner: "server",
                                                       localUserModifiedAt: localStamp, serverUserModifiedAt: serverStamp,
                                                       losingTitle: "displaced (this device): " + describe(title: item.title, favourite: item.isFavourite, cover: item.thumbnailPage),
                                                       losingNotes: nil))
            }
            outcome.settled.append(name)
            log("Score metadata \(parsed.id.prefix(8))…: \(transitionCopy ? "transition copy met a real one; server" : (localStamp == nil && serverStamp == nil ? "no clock on either side; server" : "server newer")) → \(describe(title: serverTitle, favourite: serverFavourite, cover: serverCover))")
        }
        return outcome
    }

    @MainActor
    static func applyPosition(_ record: CKRecord, store: JournalSyncStateStore, library: ScoreLibraryStore,
                              localPending: Bool? = nil, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let name = record.recordID.recordName
        guard let parsed = JournalSyncRecordType.scoreRecord(fromName: name), let uuid = UUID(uuidString: parsed.id) else { return outcome }
        guard let item = library.items.first(where: { $0.id == uuid }) else { return hold(record, store: store, log: log) }
        let st = store.state
        let (pending, transitionCopy) = isPending(name, store: store, override: localPending)
        let serverPage = (record[JournalScoreKeys.lastViewedPage] as? NSNumber).map { JournalScoreValues.clamp(page: $0.intValue, pageCount: item.pageCount) }
        let serverStamp = record[JournalScoreKeys.stamp] as? Date
        let decision = transitionCopy ? .takeServer
            : JournalScoreValues.decidePosition(localPage: item.lastViewedPage, localStamp: st.scorePositionStamps[parsed.id],
                                                serverPage: serverPage, serverStamp: serverStamp)
        switch decision {
        case .same:
            store.update { s in
                s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                if let serverPage { s.scorePositions[parsed.id] = serverPage }
                if !pending || transitionCopy { s.scorePositionStamps[parsed.id] = serverStamp; s.outbox.removeAll { $0.recordName == name && $0.op == .save } }
                s.awaitingScore.removeValue(forKey: name)
            }
            if !pending || transitionCopy { outcome.settled.append(name) }
        case .keepLocal:
            store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
            if !pending {
                let change = JournalSyncPendingChange(recordName: name, recordType: JournalSyncRecordType.scorePosition, op: .save, metadataEdit: true)
                outcome.resend.append(change)
                store.update { JournalChangeTracker.merge([change], into: &$0.outbox) }
            }
            log("Score position \(parsed.id.prefix(8))…: local newer; kept")
        case .takeServer:
            guard let serverPage else { return outcome }
            JournalScoreMirror.suppressed = true
            let applied = library.applyImportedPosition(id: uuid, page: serverPage)
            JournalScoreMirror.suppressed = false
            guard let applied else { return outcome }
            outcome.applied = 1
            let displaced = item.lastViewedPage != nil && item.lastViewedPage != applied
            store.update { s in
                s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                s.scorePositions[parsed.id] = applied
                s.scorePositionStamps[parsed.id] = serverStamp
                s.outbox.removeAll { $0.recordName == name && $0.op == .save }
                s.awaitingScore.removeValue(forKey: name)
                if displaced { s.scorePositionsDisplaced += 1 }
            }
            outcome.settled.append(name)
            log("Score position \(parsed.id.prefix(8))…: page \(applied) from the other device\(displaced ? " (local page \(item.lastViewedPage ?? 0) displaced)" : "")")
        }
        return outcome
    }

    /// Remote deletions. A deleted content record removes the item (the file
    /// stays while a journal attachment refers to it, C-138); a meta or
    /// position deletion alone is forgotten, the item stays.
    @MainActor
    @discardableResult
    static func applyDeletions(_ names: [String], store: JournalSyncStateStore, library: ScoreLibraryStore, log: (String) -> Void) -> Int {
        var removed = 0
        for name in names {
            guard let parsed = JournalSyncRecordType.scoreRecord(fromName: name) else { continue }
            if parsed.kind == .content, let uuid = UUID(uuidString: parsed.id) {
                if library.indexDamaged {
                    log("Score deletion \(parsed.id.prefix(8))… not applied: the library index could not be read (C-139)")
                } else {
                    JournalScoreMirror.suppressed = true
                    if library.removeImported(id: uuid) { removed += 1 }
                    JournalScoreMirror.suppressed = false
                }
                store.update { s in
                    s.scoreFingerprints.removeValue(forKey: parsed.id)
                    s.scoreStamps.removeValue(forKey: parsed.id)
                    s.scorePositions.removeValue(forKey: parsed.id)
                    s.scorePositionStamps.removeValue(forKey: parsed.id)
                    for n in [name, JournalSyncRecordType.scoreMetaName(for: parsed.id), JournalSyncRecordType.scorePositionName(for: parsed.id)] {
                        s.lastKnownRecords.removeValue(forKey: n)
                        s.awaitingScore.removeValue(forKey: n)
                        s.assetHashes.removeValue(forKey: n)
                        s.fileStampCache.removeValue(forKey: n)
                        s.outbox.removeAll { $0.recordName == n }
                    }
                }
            } else {
                store.update { s in
                    s.lastKnownRecords.removeValue(forKey: name)
                    s.awaitingScore.removeValue(forKey: name)
                    s.outbox.removeAll { $0.recordName == name }
                }
            }
        }
        return removed
    }

    /// Diagnostics: forget what was exchanged and send the library again
    /// (clocks kept; existing items go up as at the transition). Nothing
    /// local is changed.
    static func rerunTransition(store: JournalSyncStateStore) {
        store.update { s in
            let names = s.assetHashes.keys.filter(JournalSyncRecordType.isScoreRecordName)
            for name in names { s.assetHashes.removeValue(forKey: name) }
            s.scoreFingerprints.removeAll()
            s.scorePositions.removeAll()
            s.scoreScanDone = false
            s.scoreIndexDamagedNoted = false
            s.log.append(.init(at: Date(), text: "Scores transition re-run requested"))
        }
    }

    // MARK: Helpers

    static func describe(title: String, favourite: Bool, cover: Int) -> String {
        "“\(title)” · \(favourite ? "favourite" : "not favourite") · cover page \(cover)"
    }

    private static func copy(_ source: URL, to destination: URL, log: (String) -> Void) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            log("Could not write \(destination.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    static func displacedDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(displacedDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The local file that lost to the server's, kept by hash (the five most recent).
    static func keepDisplaced(_ url: URL, hash: String, recordName: String, store: JournalSyncStateStore) {
        let dir = displacedDirectory()
        let target = dir.appendingPathComponent("\(hash.isEmpty ? UUID().uuidString : hash).pdf", isDirectory: false)
        if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: url, to: target) }
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { (JournalAssetHash.stamp(of: $0)?.mtime ?? 0) > (JournalAssetHash.stamp(of: $1)?.mtime ?? 0) }
        for old in files.dropFirst(5) { try? FileManager.default.removeItem(at: old) }
        store.update { $0.conflicts.append(JournalSyncConflict(at: Date(), recordName: recordName, recordType: JournalSyncRecordType.score, winner: "server",
                                                               localUserModifiedAt: nil, serverUserModifiedAt: nil,
                                                               losingTitle: "displaced score file kept: \(hash.prefix(12))…", losingNotes: nil)) }
    }

    static func displacedScores() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: displacedDirectory(), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func clearDisplacedScores() {
        for url in displacedScores() { try? FileManager.default.removeItem(at: url) }
    }
}
#endif
