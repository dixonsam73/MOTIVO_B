//
//  C99StagingRefsConcurrencyTests.swift
//  MOTIVOTests
//
//  C-99 — CONCURRENT `StagingStore` OPERATIONS MUST NOT LOSE EACH OTHER'S
//  REFERENCE UPDATES (class A), AND A REPLACEMENT MUST NOT WRITE BACK A STALE
//  CALLER SNAPSHOT (class B).
//
//  FORCED OVERLAP. A Debug, hosted-test-only hook (`StagingStore.unitTestRefsHook`)
//  lets a background writer pause right after it has loaded the refs. The test then
//  runs a second operation and releases the first. This shows what an overlap DOES;
//  it says nothing about how often real interaction produces one.
//
//  SYNCHRONISATION.
//   - Every event goes into an `NSLock`-guarded log with a monotonic time.
//   - A paused writer waits on a semaphore with a 10 s timeout, so it always finishes.
//   - A GCD watcher releases it once the second operation has returned, or after 2 s
//     — so a correctly serialised store (where the second operation blocks) can never
//     deadlock the test. Watchers never touch the main actor.
//   - Validity (order witnesses) is checked BEFORE any behavioural assertion; an
//     invalid overlap throws `OverlapNotEstablished` and is not a result.
//
//  ISOLATION AND TEARDOWN. Each test uses its own `tmp/C99-<uuid>/Staging` through the
//  C-90 root override; the real store and the legacy defaults key are snapshotted
//  first and the key is cleared before any store read. `tearDown` joins every worker
//  AND watcher before it clears the hook, the override or the root. If they cannot be
//  joined, it leaves the hook and the isolated root in place, fails, and marks the
//  class unsafe so no later test runs.
//

import XCTest
@testable import Etudes

struct OverlapNotEstablished: Error, CustomStringConvertible {
    let reason: String
    var description: String { "C-99 OVERLAP NOT ESTABLISHED (not a product result): \(reason)" }
}

struct C99SetupError: Error, CustomStringConvertible {
    let reason: String
    var description: String { "C-99 setup could not arrange the case (not a product result): \(reason)" }
}

final class C99EventLog: @unchecked Sendable {
    enum Event: String {
        case aBarrierReached, aSaveCommitted, aReleasedByBReturned, aReleasedByWatcherTimeout
        case bStarted, bLoaded, bReturned, bPlaced, bCommitted
        case removalStarted, removalHookReached, removalHookWitnessTimeout, removalReturned
        case barrierTimeout, watcherFinished
    }

    private let lock = NSLock()
    private var entries: [(Event, UInt64)] = []

    func add(_ event: Event) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock(); entries.append((event, now)); lock.unlock()
    }

    func first(_ event: Event) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        return entries.first { $0.0 == event }?.1
    }

    func contains(_ event: Event) -> Bool { first(event) != nil }

    var summary: String {
        lock.lock(); defer { lock.unlock() }
        guard let t0 = entries.first?.1 else { return "[]" }
        return entries.map { "\($0.0.rawValue)@\(($0.1 - t0) / 1_000_000)ms" }.joined(separator: " → ")
    }
}

/// Configuration is immutable once created; coordination is semaphores and the log.
final class C99Barrier: @unchecked Sendable {
    let log: C99EventLog
    let blocking: UnitTestRefsPoint?
    let blockEvent: C99EventLog.Event
    let observe: [UnitTestRefsPoint: C99EventLog.Event]
    let commitWitness: UnitTestRefsPoint?
    let removalReleasesAndAwaitsCommit: Bool

    let reached = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let committed = DispatchSemaphore(value: 0)

    init(log: C99EventLog,
         blocking: UnitTestRefsPoint? = nil,
         blockEvent: C99EventLog.Event = .aBarrierReached,
         observe: [UnitTestRefsPoint: C99EventLog.Event] = [:],
         commitWitness: UnitTestRefsPoint? = nil,
         removalReleasesAndAwaitsCommit: Bool = false) {
        self.log = log
        self.blocking = blocking
        self.blockEvent = blockEvent
        self.observe = observe
        self.commitWitness = commitWitness
        self.removalReleasesAndAwaitsCommit = removalReleasesAndAwaitsCommit
    }

    /// Runs on whichever thread reached the point. Never touches the main actor.
    func handle(_ point: UnitTestRefsPoint) {
        if let event = observe[point] { log.add(event) }
        if let witness = commitWitness, point == witness { committed.signal() }
        if let blocking, point == blocking {
            log.add(blockEvent)
            reached.signal()
            if release.wait(timeout: .now() + 10) == .timedOut { log.add(.barrierTimeout) }
        }
        if removalReleasesAndAwaitsCommit, point == .removeManyFilesDeleted {
            log.add(.removalHookReached)
            release.signal()
            if committed.wait(timeout: .now() + 10) == .timedOut { log.add(.removalHookWitnessTimeout) }
        }
    }
}

@MainActor
final class C99StagingRefsConcurrencyTests: XCTestCase {

    private static var unsafeToProceed = false

    private let legacyKey = "stagedAttachments_v2"
    private let fm = FileManager.default

    private var realRefsURL: URL!
    private var realRefsExisted = false
    private var realRefsBytes: Data?
    private var legacyValue: Any?
    private var snapshotTaken = false

    private var container: URL!
    private var root: URL!
    private var ownedPaths: [URL] = []

    private var log = C99EventLog()
    private var barriers: [C99Barrier] = []
    private var workers: [Task<Void, Never>] = []   // mutated on the main actor only
    private var watchers = DispatchGroup()

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        guard !Self.unsafeToProceed else {
            throw C99SetupError(reason: "an earlier C-99 test could not join its workers; its isolated root is still in use")
        }
        guard UnitTestHost.isActive else {
            throw C99SetupError(reason: "UnitTestHost.isActive is false, so the override and hook would be ignored")
        }
        StagingStore.unitTestRefsHook = nil
        StagingStore.unitTestRootOverride = nil
        realRefsURL = StagingStore.baseURL.appendingPathComponent("staged.json")
        realRefsExisted = fm.fileExists(atPath: realRefsURL.path)
        realRefsBytes = realRefsExisted ? try Data(contentsOf: realRefsURL) : nil
        legacyValue = UserDefaults.standard.object(forKey: legacyKey)
        snapshotTaken = true
        UserDefaults.standard.removeObject(forKey: legacyKey)   // before any isolated store read

        log = C99EventLog()
        barriers = []
        workers = []
        watchers = DispatchGroup()

        container = fm.temporaryDirectory.appendingPathComponent("C99-\(UUID().uuidString)", isDirectory: true)
        root = container.appendingPathComponent("Staging", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        StagingStore.unitTestRootOverride = root
        guard StagingStore.baseURL.standardizedFileURL == root.standardizedFileURL else {
            throw C99SetupError(reason: "the root override was not honoured (\(StagingStore.baseURL.path))")
        }
    }

    override func tearDown() async throws {
        for b in barriers { b.release.signal(); b.release.signal(); b.committed.signal() }
        let workersDone = await joinedWorkers(within: 30)
        let watchersDone = await Self.joined(watchers, within: 10)

        let attachment = XCTAttachment(string: "C-99 event log: \(log.summary)")
        attachment.lifetime = .keepAlways
        add(attachment)

        guard workersDone && watchersDone else {
            Self.unsafeToProceed = true
            XCTFail("C-99: test-owned workers (\(workersDone)) or release watchers (\(watchersDone)) did not finish. The hook and the isolated root are LEFT IN PLACE so no worker can reach the real store. \(log.summary)")
            try await super.tearDown()
            return
        }

        StagingStore.unitTestRefsHook = nil
        StagingStore.unitTestRootOverride = nil
        barriers = []
        workers = []
        if let container { try? fm.removeItem(at: container) }
        for p in ownedPaths where fm.fileExists(atPath: p.path) { try? fm.removeItem(at: p) }
        ownedPaths = []

        if snapshotTaken {
            if let legacyValue {
                UserDefaults.standard.set(legacyValue, forKey: legacyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: legacyKey)
            }
            let now = UserDefaults.standard.object(forKey: legacyKey) as AnyObject?
            if let legacyValue {
                XCTAssertTrue(now?.isEqual(legacyValue) ?? false, "teardown: legacy defaults value restored exactly")
            } else {
                XCTAssertNil(now, "teardown: legacy defaults key absent, as before")
            }
            XCTAssertEqual(fm.fileExists(atPath: realRefsURL.path), realRefsExisted, "teardown: real staged.json existence unchanged")
            if let realRefsBytes {
                XCTAssertEqual(try? Data(contentsOf: realRefsURL), realRefsBytes, "teardown: real staged.json bytes unchanged")
            }
        }
        snapshotTaken = false
        try await super.tearDown()
    }

    // MARK: - Coordination helpers

    private func install(_ barrier: C99Barrier) {
        barriers.append(barrier)
        StagingStore.unitTestRefsHook = { point in barrier.handle(point) }
    }

    nonisolated private static func signalled(_ semaphore: DispatchSemaphore, within seconds: Double) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: semaphore.wait(timeout: .now() + seconds) == .success)
            }
        }
    }

    nonisolated private static func joined(_ group: DispatchGroup, within seconds: Double) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: group.wait(timeout: .now() + seconds) == .success)
            }
        }
    }

    /// Joins every test-owned worker without blocking the main actor.
    private func joinedWorkers(within seconds: Double) async -> Bool {
        let tasks = workers
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for t in tasks { await t.value }
            done.signal()
        }
        return await Self.signalled(done, within: seconds)
    }

    /// Releases A when B has returned, or after 2 s if B is blocked (a serialised store).
    private func startWatcher(_ barrier: C99Barrier, bReturned: DispatchSemaphore) {
        let log = self.log
        let group = watchers
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let returned = bReturned.wait(timeout: .now() + 2) == .success
            log.add(returned ? .aReleasedByBReturned : .aReleasedByWatcherTimeout)
            barrier.release.signal()
            log.add(.watcherFinished)
            group.leave()
        }
    }

    private func validateOverlap(requireBLoaded: Bool) throws {
        guard let reached = log.first(.aBarrierReached) else {
            throw OverlapNotEstablished(reason: "A never reached its barrier — \(log.summary)")
        }
        guard let started = log.first(.bStarted), reached < started else {
            throw OverlapNotEstablished(reason: "B did not start after A reached its barrier — \(log.summary)")
        }
        if requireBLoaded {
            guard let loaded = log.first(.bLoaded), loaded > reached else {
                throw OverlapNotEstablished(reason: "B did not load after A reached its barrier — \(log.summary)")
            }
        }
        guard !log.contains(.barrierTimeout) else {
            throw OverlapNotEstablished(reason: "A's barrier timed out — \(log.summary)")
        }
        guard log.contains(.watcherFinished) else {
            throw OverlapNotEstablished(reason: "the release watcher did not finish — \(log.summary)")
        }
    }

    private func validateX5() throws {
        guard let placed = log.first(.bPlaced), let started = log.first(.removalStarted), placed < started else {
            throw OverlapNotEstablished(reason: "X-5: B was not placed before the removal began — \(log.summary)")
        }
        guard let hook = log.first(.removalHookReached), let committed = log.first(.bCommitted),
              let returned = log.first(.removalReturned), hook < committed, committed < returned else {
            throw OverlapNotEstablished(reason: "X-5: B did not commit inside the removal hook before the removal returned — \(log.summary)")
        }
        guard !log.contains(.removalHookWitnessTimeout), !log.contains(.barrierTimeout) else {
            throw OverlapNotEstablished(reason: "X-5: a witness or barrier timed out — \(log.summary)")
        }
    }

    /// Release cause and the full ordered log, for every behavioural message.
    private var order: String {
        let cause = log.contains(.aReleasedByBReturned) ? "bReturned (pre-fix valid)"
            : log.contains(.aReleasedByWatcherTimeout) ? "watcherTimeout (B blocked)" : "n/a"
        return "releasedBy=\(cause) log=\(log.summary)"
    }

    // MARK: - Fixtures (direct reads; owned temporary sources)

    private var refsURL: URL { root.appendingPathComponent("staged.json") }

    private func refsOnDisk() throws -> [StagedAttachmentRef] {
        guard fm.fileExists(atPath: refsURL.path) else { return [] }
        return try JSONDecoder().decode([StagedAttachmentRef].self, from: Data(contentsOf: refsURL))
    }

    private func source(_ contents: String, ext: String) throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("c99-\(UUID().uuidString)").appendingPathExtension(ext)
        ownedPaths.append(url)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func bytes(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func name(_ id: UUID) -> String { "c99-\(id.uuidString)" }

    @discardableResult
    private func stage(_ id: UUID, _ contents: String, ext: String, kind: StagedAttachmentRef.Kind) async throws -> StagedAttachmentRef {
        try await StagingStore.saveNew(from: try source(contents, ext: ext), kind: kind, suggestedName: name(id), id: id)
    }

    private func mediaExists(_ ref: StagedAttachmentRef?) -> Bool {
        guard let ref else { return false }
        return fm.fileExists(atPath: StagingStore.absoluteURL(for: ref).path)
    }

    // MARK: - X-0

    func testX0_sequentialControl() async throws {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        install(C99Barrier(log: log))
        try await stage(a, "a", ext: "m4a", kind: .audio)
        try await stage(b, "b", ext: "mov", kind: .video)
        let rc = try await stage(c, "c", ext: "m4a", kind: .audio)
        let rd = try await stage(d, "d", ext: "m4a", kind: .audio)
        StagingStore.updateAudioMetadata(id: a, title: "renamed", autoTitle: nil, duration: nil)
        XCTAssertTrue(StagingStore.writePoster(for: b, jpeg: Data("poster".utf8)), "X-0: poster written")
        StagingStore.remove(rc)
        StagingStore.removeMany(ids: [d])

        let refs = try refsOnDisk()
        XCTAssertEqual(Set(refs.map(\.id)), [a, b], "X-0: exactly A and B remain")
        XCTAssertEqual(refs.first { $0.id == a }?.audioUserTitle, "renamed", "X-0: rename kept")
        let posterPath = refs.first { $0.id == b }?.posterPath
        XCTAssertNotNil(posterPath, "X-0: poster path recorded")
        if let posterPath { XCTAssertEqual(bytes(StagingStore.absoluteURL(forRelative: posterPath)), "poster", "X-0: poster bytes") }
        XCTAssertFalse(mediaExists(rc), "X-0: removed media gone")
        XCTAssertFalse(mediaExists(rd), "X-0: removeMany media gone")
    }

    // MARK: - X-1

    func testX1_saveNewOverlappingSaveNewKeepsBoth() async throws {
        let a = UUID(), b = UUID()
        let barrier = C99Barrier(log: log, blocking: .saveNewLoaded(a),
                                 observe: [.saveNewLoaded(b): .bLoaded, .saveNewCommitted(a): .aSaveCommitted])
        install(barrier)
        let srcA = try source("A", ext: "m4a"), srcB = try source("B", ext: "m4a")
        let nameA = name(a), nameB = name(b)

        workers.append(Task { _ = try? await StagingStore.saveNew(from: srcA, kind: .audio, suggestedName: nameA, id: a) })
        guard await Self.signalled(barrier.reached, within: 10) else {
            throw OverlapNotEstablished(reason: "A never reached its barrier — \(log.summary)")
        }
        let bReturned = DispatchSemaphore(value: 0)
        startWatcher(barrier, bReturned: bReturned)
        log.add(.bStarted)
        let bTask = Task { _ = try? await StagingStore.saveNew(from: srcB, kind: .audio, suggestedName: nameB, id: b) }
        workers.append(bTask)
        await bTask.value
        log.add(.bReturned)
        bReturned.signal()
        guard await joinedWorkers(within: 30), await Self.joined(watchers, within: 10) else {
            throw OverlapNotEstablished(reason: "workers or watcher did not finish — \(log.summary)")
        }
        try validateOverlap(requireBLoaded: true)

        let refs = try refsOnDisk()
        XCTAssertTrue(refs.contains { $0.id == a }, "X-1: A referenced — \(order)")
        XCTAssertTrue(refs.contains { $0.id == b }, "X-1: B referenced — \(order)")
        XCTAssertTrue(mediaExists(refs.first { $0.id == a }), "X-1: A media present — \(order)")
        XCTAssertTrue(mediaExists(refs.first { $0.id == b }), "X-1: B media present — \(order)")
    }

    // MARK: - X-2

    func testX2_saveNewOverlappingRemoveKeepsTheRemoval() async throws {
        let r = UUID(), a = UUID()
        let barrier = C99Barrier(log: log, blocking: .saveNewLoaded(a), observe: [.saveNewCommitted(a): .aSaveCommitted])
        install(barrier)
        let rr = try await stage(r, "removed", ext: "m4a", kind: .audio)
        let rMedia = StagingStore.absoluteURL(for: rr)
        let srcA = try source("A", ext: "m4a")
        let nameA = name(a)

        workers.append(Task { _ = try? await StagingStore.saveNew(from: srcA, kind: .audio, suggestedName: nameA, id: a) })
        guard await Self.signalled(barrier.reached, within: 10) else {
            throw OverlapNotEstablished(reason: "A never reached its barrier — \(log.summary)")
        }
        let bReturned = DispatchSemaphore(value: 0)
        startWatcher(barrier, bReturned: bReturned)
        log.add(.bStarted)
        StagingStore.remove(rr)
        log.add(.bReturned)
        bReturned.signal()
        guard await joinedWorkers(within: 30), await Self.joined(watchers, within: 10) else {
            throw OverlapNotEstablished(reason: "workers or watcher did not finish — \(log.summary)")
        }
        try validateOverlap(requireBLoaded: false)

        let refs = try refsOnDisk()
        XCTAssertFalse(refs.contains { $0.id == r }, "X-2: the removed item stays removed — \(order)")
        XCTAssertFalse(fm.fileExists(atPath: rMedia.path), "X-2: its media is gone — \(order)")
        XCTAssertTrue(refs.contains { $0.id == a }, "X-2: A referenced — \(order)")
    }

    // MARK: - X-3

    func testX3_saveNewOverlappingRenameKeepsTheTitle() async throws {
        let r = UUID(), a = UUID()
        let barrier = C99Barrier(log: log, blocking: .saveNewLoaded(a), observe: [.saveNewCommitted(a): .aSaveCommitted])
        install(barrier)
        try await stage(r, "recording", ext: "m4a", kind: .audio)
        let srcA = try source("A", ext: "m4a")
        let nameA = name(a)

        workers.append(Task { _ = try? await StagingStore.saveNew(from: srcA, kind: .audio, suggestedName: nameA, id: a) })
        guard await Self.signalled(barrier.reached, within: 10) else {
            throw OverlapNotEstablished(reason: "A never reached its barrier — \(log.summary)")
        }
        let bReturned = DispatchSemaphore(value: 0)
        startWatcher(barrier, bReturned: bReturned)
        log.add(.bStarted)
        StagingStore.updateAudioMetadata(id: r, title: "renamed", autoTitle: nil, duration: nil)
        log.add(.bReturned)
        bReturned.signal()
        guard await joinedWorkers(within: 30), await Self.joined(watchers, within: 10) else {
            throw OverlapNotEstablished(reason: "workers or watcher did not finish — \(log.summary)")
        }
        try validateOverlap(requireBLoaded: false)

        let refs = try refsOnDisk()
        XCTAssertEqual(refs.first { $0.id == r }?.audioUserTitle, "renamed", "X-3: the rename survives — \(order)")
        XCTAssertEqual(refs.first { $0.id == r }?.audioDisplayTitle, "renamed", "X-3: …as the displayed title — \(order)")
        XCTAssertTrue(refs.contains { $0.id == a }, "X-3: A referenced — \(order)")
    }

    // MARK: - X-4

    func testX4_replaceOverlappingSaveNewKeepsBoth() async throws {
        let o = UUID(), b = UUID()
        let barrier = C99Barrier(log: log, blocking: .replaceLoaded(o), observe: [.saveNewLoaded(b): .bLoaded])
        install(barrier)
        let original = try await stage(o, "original recording", ext: "mov", kind: .video)
        let trim = try source("trimmed mp4", ext: "mp4")
        let srcB = try source("B", ext: "m4a")
        let nameB = name(b)

        workers.append(Task { _ = try? await StagingStore.replace(original: original, with: trim) })
        guard await Self.signalled(barrier.reached, within: 10) else {
            throw OverlapNotEstablished(reason: "the replacement never reached its barrier — \(log.summary)")
        }
        let bReturned = DispatchSemaphore(value: 0)
        startWatcher(barrier, bReturned: bReturned)
        log.add(.bStarted)
        let bTask = Task { _ = try? await StagingStore.saveNew(from: srcB, kind: .audio, suggestedName: nameB, id: b) }
        workers.append(bTask)
        await bTask.value
        log.add(.bReturned)
        bReturned.signal()
        guard await joinedWorkers(within: 30), await Self.joined(watchers, within: 10) else {
            throw OverlapNotEstablished(reason: "workers or watcher did not finish — \(log.summary)")
        }
        try validateOverlap(requireBLoaded: true)

        let refs = try refsOnDisk()
        let replaced = refs.first { $0.id == o }
        XCTAssertEqual(replaced.map { URL(fileURLWithPath: $0.relativePath).pathExtension }, "mp4",
                       "X-4: the replacement is indexed — \(order)")
        if let replaced { XCTAssertEqual(bytes(StagingStore.absoluteURL(for: replaced)), "trimmed mp4", "X-4: with the trim's bytes — \(order)") }
        XCTAssertTrue(refs.contains { $0.id == b }, "X-4: B referenced — \(order)")
    }

    // MARK: - X-5

    func testX5_removeManyDoesNotSaveItsPreDeletionList() async throws {
        let r1 = UUID(), r2 = UUID(), b = UUID()
        let barrier = C99Barrier(log: log, blocking: .saveNewPlaced(b), blockEvent: .bPlaced,
                                 observe: [.saveNewCommitted(b): .bCommitted],
                                 commitWitness: .saveNewCommitted(b), removalReleasesAndAwaitsCommit: true)
        install(barrier)
        let ref1 = try await stage(r1, "one", ext: "m4a", kind: .audio)
        try await stage(r2, "two", ext: "m4a", kind: .audio)
        let r1Media = StagingStore.absoluteURL(for: ref1)
        let srcB = try source("B", ext: "m4a")
        let nameB = name(b)

        workers.append(Task { _ = try? await StagingStore.saveNew(from: srcB, kind: .audio, suggestedName: nameB, id: b) })
        guard await Self.signalled(barrier.reached, within: 10) else {
            throw OverlapNotEstablished(reason: "X-5: B never reached saveNewPlaced — \(log.summary)")
        }
        log.add(.removalStarted)
        StagingStore.removeMany(ids: [r1])
        log.add(.removalReturned)
        guard await joinedWorkers(within: 30) else {
            throw OverlapNotEstablished(reason: "X-5: workers did not finish — \(log.summary)")
        }
        try validateX5()

        let refs = try refsOnDisk()
        XCTAssertFalse(refs.contains { $0.id == r1 }, "X-5: R1 stays removed — log=\(log.summary)")
        XCTAssertFalse(fm.fileExists(atPath: r1Media.path), "X-5: R1's media is gone — log=\(log.summary)")
        XCTAssertTrue(refs.contains { $0.id == r2 }, "X-5: R2 still referenced — log=\(log.summary)")
        XCTAssertTrue(refs.contains { $0.id == b }, "X-5: B, committed during the removal, still referenced — log=\(log.summary)")
    }

    // MARK: - Y-1

    func testY1_extensionChangingReplaceKeepsACurrentRename() async throws {
        let r = UUID()
        try await stage(r, "take", ext: "m4a", kind: .audio)
        let snapshot = try XCTUnwrap(StagingStore.ref(withId: r), "Y-1 setup: the caller's snapshot")
        StagingStore.updateAudioMetadata(id: r, title: "renamed", autoTitle: nil, duration: nil)
        guard try refsOnDisk().first(where: { $0.id == r })?.audioUserTitle == "renamed" else {
            throw C99SetupError(reason: "Y-1: the rename did not persist before the replacement")
        }

        _ = try await StagingStore.replace(original: snapshot, with: try source("trimmed", ext: "caf"))

        let now = try XCTUnwrap(try refsOnDisk().first { $0.id == r }, "Y-1: the item is still indexed")
        XCTAssertEqual(URL(fileURLWithPath: now.relativePath).pathExtension, "caf", "Y-1: the path follows the replacement")
        XCTAssertEqual(bytes(StagingStore.absoluteURL(for: now)), "trimmed", "Y-1: with the new bytes")
        XCTAssertEqual(now.audioUserTitle, "renamed", "Y-1: a rename made after the caller's snapshot survives")
        XCTAssertEqual(now.audioDisplayTitle, "renamed", "Y-1: …as the displayed title")
    }

    // MARK: - Y-2

    func testY2_sameExtensionReplaceKeepsACurrentRename() async throws {
        let r = UUID()
        let staged = try await stage(r, "take one", ext: "m4a", kind: .audio)
        let snapshot = try XCTUnwrap(StagingStore.ref(withId: r), "Y-2 setup: the caller's snapshot")
        StagingStore.updateAudioMetadata(id: r, title: "renamed", autoTitle: nil, duration: nil)
        guard try refsOnDisk().first(where: { $0.id == r })?.audioUserTitle == "renamed" else {
            throw C99SetupError(reason: "Y-2: the rename did not persist before the replacement")
        }

        _ = try await StagingStore.replace(original: snapshot, with: try source("take two", ext: "m4a"))

        let now = try XCTUnwrap(try refsOnDisk().first { $0.id == r }, "Y-2: the item is still indexed")
        XCTAssertEqual(now.relativePath, staged.relativePath, "Y-2: same path")
        XCTAssertEqual(bytes(StagingStore.absoluteURL(for: now)), "take two", "Y-2: bytes replaced")
        XCTAssertEqual(now.audioUserTitle, "renamed", "Y-2: a rename made after the caller's snapshot survives")
        XCTAssertEqual(now.audioDisplayTitle, "renamed", "Y-2: …as the displayed title")
    }

    // MARK: - S-1 (structural corroboration only)

    /// NARROW: a comments-stripped text check of `StagingStore.swift`. It cannot prove the
    /// absence of re-entrancy, actor hops or deadlock through helpers — the report's manual
    /// call-graph review and the executable cases are the evidence.
    func testS1_refsLoadAndSaveSitInsideTheRefsCriticalSection() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO/StagingStore.swift")
        let s = C99Source.stripComments(try String(contentsOf: url, encoding: .utf8))

        var sections: [ClosedRange<Int>] = []
        for i in C99Source.find("withRefsLock {", in: s) {
            if let close = C99Source.matchBrace(s, open: i + "withRefsLock ".count) { sections.append(i...close) }
        }
        XCTAssertFalse(sections.isEmpty, "S-1: a refs critical section (withRefsLock { … }) exists")

        var loadBody: ClosedRange<Int>?
        if let def = C99Source.find("func loadRefs()", in: s).first,
           let open = (def..<s.count).first(where: { s[$0] == "{" }),
           let close = C99Source.matchBrace(s, open: open) {
            loadBody = open...close
        }

        var unlocked: [String] = []
        for token in ["loadRefs()", "saveRefs("] {
            for i in C99Source.find(token, in: s) {
                if C99Source.isPreceded(by: "func ", s, at: i) { continue }
                if let loadBody, loadBody.contains(i) { continue }
                if !sections.contains(where: { $0.contains(i) }) {
                    unlocked.append("\(token) near line \(C99Source.line(of: i, in: s))")
                }
            }
        }
        XCTAssertEqual(unlocked, [], "S-1: every refs load and save lies inside a withRefsLock section")

        for section in sections {
            let body = String(s[section])
            for forbidden in ["await", "MainActor", "DispatchQueue", "jpeg.write", "deleteFiles(", "removeItem("] where body.contains(forbidden) {
                XCTFail("S-1: a critical section near line \(C99Source.line(of: section.lowerBound, in: s)) contains \(forbidden)")
            }
            if body.dropFirst("withRefsLock {".count).contains("withRefsLock") {
                XCTFail("S-1: a critical section near line \(C99Source.line(of: section.lowerBound, in: s)) nests withRefsLock")
            }
        }
    }
}

/// A narrow text reader (comments removed, string literals skipped) — not a Swift parser.
private enum C99Source {
    static func stripComments(_ text: String) -> [Character] {
        let s = Array(text)
        var out: [Character] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if s[i] == "\"" {
                let end = endOfString(s, at: i)
                out.append(contentsOf: s[i..<end]); i = end
            } else if s[i] == "/", i + 1 < s.count, s[i + 1] == "/" {
                while i < s.count, s[i] != "\n" { i += 1 }
            } else if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" {
                var depth = 0
                while i < s.count {
                    if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" { depth += 1; i += 2; continue }
                    if s[i] == "*", i + 1 < s.count, s[i + 1] == "/" {
                        depth -= 1; i += 2
                        if depth == 0 { break }
                        continue
                    }
                    if s[i] == "\n" { out.append("\n") }
                    i += 1
                }
            } else {
                out.append(s[i]); i += 1
            }
        }
        return out
    }

    static func endOfString(_ s: [Character], at i: Int) -> Int {
        let triple = i + 2 < s.count && s[i + 1] == "\"" && s[i + 2] == "\""
        var j = i + (triple ? 3 : 1)
        while j < s.count {
            if s[j] == "\\" {
                if j + 1 < s.count, s[j + 1] == "(" {
                    var depth = 1; j += 2
                    while j < s.count, depth > 0 {
                        if s[j] == "\"" { j = endOfString(s, at: j); continue }
                        if s[j] == "(" { depth += 1 } else if s[j] == ")" { depth -= 1 }
                        j += 1
                    }
                    continue
                }
                j += 2; continue
            }
            if s[j] == "\"" {
                if !triple { return j + 1 }
                if j + 2 < s.count, s[j + 1] == "\"", s[j + 2] == "\"" { return j + 3 }
            }
            if !triple, s[j] == "\n" { return j }
            j += 1
        }
        return s.count
    }

    static func find(_ needle: String, in s: [Character]) -> [Int] {
        let n = Array(needle)
        var out: [Int] = []
        var i = 0
        while i + n.count <= s.count {
            if s[i] == "\"" { i = endOfString(s, at: i); continue }
            var k = 0
            while k < n.count, s[i + k] == n[k] { k += 1 }
            if k == n.count { out.append(i) }
            i += 1
        }
        return out
    }

    static func matchBrace(_ s: [Character], open: Int) -> Int? {
        guard open < s.count, s[open] == "{" else { return nil }
        var depth = 0
        var j = open
        while j < s.count {
            if s[j] == "\"" { j = endOfString(s, at: j); continue }
            if s[j] == "{" { depth += 1 } else if s[j] == "}" { depth -= 1; if depth == 0 { return j } }
            j += 1
        }
        return nil
    }

    static func isPreceded(by prefix: String, _ s: [Character], at i: Int) -> Bool {
        let p = Array(prefix)
        guard i >= p.count else { return false }
        return Array(s[(i - p.count)..<i]) == p
    }

    static func line(of index: Int, in s: [Character]) -> Int {
        s[0..<min(index, s.count)].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}
