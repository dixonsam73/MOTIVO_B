//
//  C90StagingMetadataWriteFailureTests.swift
//  MOTIVOTests
//
//  C-90 — A FAILED `staged.json` WRITE MUST NOT BE REPORTED AS SUCCESS, AND MUST
//  NEVER COST THE LAST VALID ORIGINAL.
//
//  ISOLATION. Every test runs against its own store root, `tmp/C90-<uuid>/Staging`,
//  through `StagingStore.unitTestRootOverride` (Debug + hosted test process only).
//  The hosted app does not build the timer screen (`MOTIVOApp`, C-90), so its launch
//  cleanup cannot reach this store. The real simulator store and the legacy
//  `stagedAttachments_v2` defaults key are snapshotted before the redirect, the key
//  is cleared before any isolated call, and both are restored and checked.
//
//  FAULT. The isolated root is made read-only (0555), so the atomic write of
//  `staged.json` inside it fails, while today's day folder (0755) still accepts media.
//  F-0 / F-M establish that with DIRECT file probes and throw `FaultNotEstablished`
//  out of the test before any scored operation. A control failure is not a result.
//
//  Every store call is awaited; the tests run sequentially.
//

import XCTest
@testable import Etudes

struct FaultNotEstablished: Error, CustomStringConvertible {
    let reason: String
    var description: String { "C-90 FAULT NOT ESTABLISHED (not a product result): \(reason)" }
}

struct C90SetupError: Error, CustomStringConvertible {
    let reason: String
    var description: String { "C-90 setup could not arrange the case (not a product result): \(reason)" }
}

@MainActor
final class C90StagingMetadataWriteFailureTests: XCTestCase {

    private let legacyKey = "stagedAttachments_v2"
    private let fm = FileManager.default

    // Snapshot of the real store, taken before the redirect.
    private var realRefsURL: URL!
    private var realRefsExisted = false
    private var realRefsBytes: Data?
    private var legacyValue: Any?
    private var snapshotTaken = false

    // The isolated store.
    private var container: URL!
    private var root: URL!
    private var faultOn = false
    private var ownedPaths: [URL] = []

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        guard UnitTestHost.isActive else {
            throw C90SetupError(reason: "UnitTestHost.isActive is false, so the root override would be ignored")
        }
        StagingStore.unitTestRootOverride = nil
        realRefsURL = StagingStore.baseURL.appendingPathComponent("staged.json")
        realRefsExisted = fm.fileExists(atPath: realRefsURL.path)
        realRefsBytes = realRefsExisted ? try Data(contentsOf: realRefsURL) : nil
        legacyValue = UserDefaults.standard.object(forKey: legacyKey)
        snapshotTaken = true

        // Clear the legacy key BEFORE any isolated-store call can read it.
        UserDefaults.standard.removeObject(forKey: legacyKey)

        container = fm.temporaryDirectory.appendingPathComponent("C90-\(UUID().uuidString)", isDirectory: true)
        root = container.appendingPathComponent("Staging", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        StagingStore.unitTestRootOverride = root
        guard StagingStore.baseURL.standardizedFileURL == root.standardizedFileURL else {
            throw C90SetupError(reason: "the override was not honoured (baseURL = \(StagingStore.baseURL.path))")
        }
    }

    override func tearDown() async throws {
        // 1. Permissions first, so the isolated store can be removed.
        if let root, fm.fileExists(atPath: root.path) {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            let mode = (try? fm.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int) ?? -1
            XCTAssertEqual(mode, 0o755, "teardown: isolated root mode restored")
        }
        faultOn = false
        // 2. Every test's store work is awaited, so nothing is running on the store queue now.
        StagingStore.unitTestRootOverride = nil
        // 3. The isolated store, then owned temporary sources.
        if let container { try? fm.removeItem(at: container) }
        for p in ownedPaths where fm.fileExists(atPath: p.path) { try? fm.removeItem(at: p) }
        ownedPaths = []

        if snapshotTaken {
            // 4. The legacy key, exactly.
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
            // 5. The real store was never touched.
            XCTAssertEqual(fm.fileExists(atPath: realRefsURL.path), realRefsExisted, "teardown: real staged.json existence unchanged")
            if let realRefsBytes {
                XCTAssertEqual(try? Data(contentsOf: realRefsURL), realRefsBytes, "teardown: real staged.json bytes unchanged")
            }
        }
        snapshotTaken = false
        try await super.tearDown()
    }

    // MARK: - Fault and controls

    private var dayFolder: URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return root.appendingPathComponent(f.string(from: Date()), isDirectory: true)
    }

    private var refsURL: URL { root.appendingPathComponent("staged.json") }

    private func ensureDayFolder() throws {
        try fm.createDirectory(at: dayFolder, withIntermediateDirectories: true)
    }

    private func applyFault() throws {
        try ensureDayFolder()
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        faultOn = true
    }

    private func removeFault() throws {
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        faultOn = false
    }

    /// Direct probes only — never `StagingStore`. Throws out of the test if the fault
    /// is not what it claims to be.
    private func establishProbes() throws {
        guard faultOn else { throw FaultNotEstablished(reason: "the fault was not applied") }
        let rootProbe = root.appendingPathComponent(".c90-probe-\(UUID().uuidString)")
        var refused = false
        do { try Data("probe".utf8).write(to: rootProbe, options: .atomic) } catch { refused = true }
        if !refused {
            try? fm.removeItem(at: rootProbe)
            throw FaultNotEstablished(reason: "an atomic write into the read-only store root SUCCEEDED")
        }
        let dayProbe = dayFolder.appendingPathComponent(".c90-probe-\(UUID().uuidString)")
        do {
            try Data("probe".utf8).write(to: dayProbe, options: .atomic)
            try fm.removeItem(at: dayProbe)
        } catch {
            throw FaultNotEstablished(reason: "the day folder did not accept a write: \(error)")
        }
    }

    /// F-0: an ordinary ref already exists; the root refuses a write; the day folder
    /// accepts one; `staged.json` still decodes by direct read.
    private func establishF0() throws {
        try establishProbes()
        do {
            guard !(try refsOnDisk()).isEmpty else {
                throw FaultNotEstablished(reason: "no existing ref is readable from staged.json")
            }
        } catch let e as FaultNotEstablished {
            throw e
        } catch {
            throw FaultNotEstablished(reason: "staged.json did not decode by direct read: \(error)")
        }
    }

    /// F-M: no `staged.json`, no legacy key, the fault established — all BEFORE the key
    /// is written and before the one scored `list()`.
    private func establishFM() throws {
        guard !fm.fileExists(atPath: refsURL.path) else {
            throw FaultNotEstablished(reason: "staged.json already exists in the isolated root")
        }
        guard UserDefaults.standard.object(forKey: legacyKey) == nil else {
            throw FaultNotEstablished(reason: "the legacy key is present before the case arranged it")
        }
        try establishProbes()
    }

    // MARK: - Fixtures (direct reads; owned temporary sources)

    private func refsOnDisk() throws -> [StagedAttachmentRef] {
        guard fm.fileExists(atPath: refsURL.path) else { return [] }
        return try JSONDecoder().decode([StagedAttachmentRef].self, from: Data(contentsOf: refsURL))
    }

    private func source(_ contents: String, ext: String) throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("c90-\(UUID().uuidString)").appendingPathExtension(ext)
        ownedPaths.append(url)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func bytes(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// An ordinary ref, so F-0 has something to read.
    @discardableResult
    private func anchor() async throws -> StagedAttachmentRef {
        try await StagingStore.saveNew(from: try source("anchor", ext: "m4a"), kind: .audio,
                                       suggestedName: "c90-anchor-\(UUID().uuidString)")
    }

    private func isDestinationExists(_ error: Error?) -> Bool {
        if case .destinationExists? = error as? StagingStoreError { return true }
        return false
    }

    // MARK: - I-1

    func testI1_overrideIsHonouredAndTheRealStoreIsUntouched() async throws {
        XCTAssertEqual(StagingStore.baseURL.standardizedFileURL, root.standardizedFileURL, "I-1: baseURL is the isolated root")
        let id = UUID()
        let ref = try await StagingStore.saveNew(from: try source("isolated", ext: "m4a"), kind: .audio,
                                                 suggestedName: "c90-\(id.uuidString)", id: id)
        let abs = StagingStore.absoluteURL(for: ref).standardizedFileURL.path
        XCTAssertTrue(abs.hasPrefix(root.standardizedFileURL.path + "/"), "I-1: the media landed in the isolated store — \(abs)")
        XCTAssertTrue(fm.fileExists(atPath: abs), "I-1: …and exists")
        XCTAssertTrue(try refsOnDisk().contains { $0.id == id }, "I-1: …and is referenced there")
        XCTAssertEqual(fm.fileExists(atPath: realRefsURL.path), realRefsExisted, "I-1: real staged.json existence unchanged")
        if let realRefsBytes { XCTAssertEqual(try? Data(contentsOf: realRefsURL), realRefsBytes, "I-1: real staged.json bytes unchanged") }
    }

    // MARK: - I-2

    func testI2_isolationIsLimitedToTheHostedTestProcess() throws {
        let store = try code("MOTIVO/StagingStore.swift")
        let decl = try XCTUnwrap(store.range(of: "nonisolated(unsafe) static var unitTestRootOverride: URL?"),
                                 "I-2: the override declaration exists")
        XCTAssertTrue(insideDebugBlock(store, at: decl.lowerBound), "I-2: the override is declared only under #if DEBUG")
        let guardLine = try XCTUnwrap(store.range(of: "if UnitTestHost.isActive, let root = unitTestRootOverride { return root }"),
                                      "I-2: baseURL reads the override only when UnitTestHost.isActive")
        XCTAssertTrue(insideDebugBlock(store, at: guardLine.lowerBound), "I-2: …and only under #if DEBUG")
        XCTAssertEqual(store.components(separatedBy: "unitTestRootOverride").count - 1, 2,
                       "I-2: the override is declared once and read once, nowhere else in the store")

        let app = try code("MOTIVO/MOTIVOApp.swift")
        let timer = try XCTUnwrap(app.range(of: "case .timer:"), "I-2: the timer route exists")
        let content = try XCTUnwrap(app.range(of: "case .content:", range: timer.upperBound..<app.endIndex))
        let branch = String(app[timer.upperBound..<content.lowerBound])
        let gate = branch.range(of: "if UnitTestHost.isActive {")
        let clear = branch.range(of: "Color.clear")
        let other = branch.range(of: "} else {")
        let timerView = branch.range(of: "PracticeTimerView(")
        XCTAssertNotNil(gate, "I-2: the .timer route is gated by UnitTestHost.isActive")
        if let gate, let clear, let other, let timerView {
            XCTAssertTrue(gate.upperBound <= clear.lowerBound && clear.upperBound <= other.lowerBound && other.upperBound <= timerView.lowerBound,
                          "I-2: the hosted test process shows Color.clear; every other launch builds PracticeTimerView")
        } else {
            XCTFail("I-2: gate shape not found — \(branch)")
        }
    }

    // MARK: - R-1

    func testR1_extensionChangingReplaceUnderTheFaultKeepsTheOriginal() async throws {
        let id = UUID()
        let original = try await StagingStore.saveNew(from: try source("original recording", ext: "mov"), kind: .video,
                                                      suggestedName: "c90-\(id.uuidString)", id: id)
        let originalURL = StagingStore.absoluteURL(for: original)
        let target = originalURL.deletingPathExtension().appendingPathExtension("mp4")
        let trim = try source("trimmed mp4", ext: "mp4")

        try applyFault()
        try establishF0()

        var thrown: Error?
        do { _ = try await StagingStore.replace(original: original, with: trim) } catch { thrown = error }

        let refPath = try refsOnDisk().first { $0.id == id }?.relativePath
        let observed = "thrown=\(String(describing: thrown)) originalBytes=\(bytes(originalURL) ?? "nil") refPath=\(refPath ?? "nil") mp4Present=\(fm.fileExists(atPath: target.path)) trimAtSource=\(bytes(trim) ?? "nil")"
        XCTAssertNotNil(thrown, "R-1: a failed metadata write must be reported — \(observed)")
        XCTAssertEqual(bytes(originalURL), "original recording", "R-1: the original keeps its bytes — \(observed)")
        XCTAssertEqual(refPath, original.relativePath, "R-1: the on-disk ref still names the original — \(observed)")
        XCTAssertFalse(fm.fileExists(atPath: target.path), "R-1: no .mp4 is left in the store — \(observed)")
        XCTAssertEqual(bytes(trim), "trimmed mp4", "R-1: the trim is back at its source — \(observed)")
    }

    // MARK: - R-2

    func testR2_replaceRecoversAfterTheFaultIsRemoved() async throws {
        let id = UUID()
        let original = try await StagingStore.saveNew(from: try source("original recording", ext: "mov"), kind: .video,
                                                      suggestedName: "c90-\(id.uuidString)", id: id)
        let originalURL = StagingStore.absoluteURL(for: original)
        let trim = try source("trimmed mp4", ext: "mp4")

        try applyFault()
        try establishF0()
        _ = try? await StagingStore.replace(original: original, with: trim)
        try removeFault()

        let trimPresentBeforeRetry = fm.fileExists(atPath: trim.path)
        let updated: StagedAttachmentRef
        do {
            updated = try await StagingStore.replace(original: original, with: trim)
        } catch {
            XCTFail("R-2: the retry after removing the fault failed — \(error); trim at source before retry=\(trimPresentBeforeRetry)")
            return
        }
        let newURL = StagingStore.absoluteURL(for: updated)
        let mine = try refsOnDisk().filter { $0.id == id }
        XCTAssertEqual(mine.count, 1, "R-2: exactly one ref for the recording")
        XCTAssertEqual(mine.first?.relativePath, updated.relativePath, "R-2: the ref names the replacement")
        XCTAssertEqual(newURL.pathExtension, "mp4", "R-2: named for what it contains")
        XCTAssertEqual(bytes(newURL), "trimmed mp4", "R-2: with the trim's bytes")
        XCTAssertFalse(fm.fileExists(atPath: originalURL.path), "R-2: the original container is gone only after success")
        StagingStore.cleanupAbandoned()
        XCTAssertEqual(try refsOnDisk().first { $0.id == id }?.relativePath, updated.relativePath, "R-2: cleanup keeps the ref")
        XCTAssertTrue(fm.fileExists(atPath: newURL.path), "R-2: …and the file")
    }

    // MARK: - R-3

    func testR3_extensionChangingReplaceSucceedsWithoutAFault() async throws {
        let id = UUID()
        let original = try await StagingStore.saveNew(from: try source("original recording", ext: "mov"), kind: .video,
                                                      suggestedName: "c90-\(id.uuidString)", id: id)
        let originalURL = StagingStore.absoluteURL(for: original)
        let updated = try await StagingStore.replace(original: original, with: try source("trimmed mp4", ext: "mp4"))
        let newURL = StagingStore.absoluteURL(for: updated)
        XCTAssertEqual(try refsOnDisk().first { $0.id == id }?.relativePath, updated.relativePath, "R-3: ref names the replacement")
        XCTAssertEqual(bytes(newURL), "trimmed mp4", "R-3: new bytes")
        XCTAssertEqual(newURL.pathExtension, "mp4", "R-3: new container")
        XCTAssertFalse(fm.fileExists(atPath: originalURL.path), "R-3: original container removed")
    }

    // MARK: - R-4

    func testR4_sameExtensionReplaceUnderTheFaultKeepsItsPath() async throws {
        let id = UUID()
        let original = try await StagingStore.saveNew(from: try source("take one", ext: "m4a"), kind: .audio,
                                                      suggestedName: "c90-\(id.uuidString)", id: id)
        let url = StagingStore.absoluteURL(for: original)
        let take = try source("take two", ext: "m4a")

        try applyFault()
        try establishF0()

        let updated = try await StagingStore.replace(original: original, with: take)
        XCTAssertEqual(updated.relativePath, original.relativePath, "R-4: same path")
        XCTAssertEqual(bytes(url), "take two", "R-4: bytes replaced")
        XCTAssertEqual(try refsOnDisk().first { $0.id == id }?.relativePath, original.relativePath,
                       "R-4: the on-disk ref still names a file that exists — no original lost on this branch")
    }

    // MARK: - R-5

    func testR5_replaceRefusesAnExistingDestination() async throws {
        let id = UUID()
        let base = "c90-\(id.uuidString)"
        let original = try await StagingStore.saveNew(from: try source("original recording", ext: "mov"), kind: .video,
                                                      suggestedName: base, id: id)
        let originalURL = StagingStore.absoluteURL(for: original)
        let target = originalURL.deletingPathExtension().appendingPathExtension("mp4")

        let otherID = UUID()
        let other = try await StagingStore.saveNew(from: try source("another item", ext: "mp4"), kind: .video,
                                                   suggestedName: base, id: otherID)
        guard StagingStore.absoluteURL(for: other).standardizedFileURL == target.standardizedFileURL else {
            throw C90SetupError(reason: "the other item did not land on <stem>.mp4 (\(other.relativePath))")
        }
        let trim = try source("trimmed mp4", ext: "mp4")

        var thrown: Error?
        do { _ = try await StagingStore.replace(original: original, with: trim) } catch { thrown = error }

        let refs = try refsOnDisk()
        let observed = "thrown=\(String(describing: thrown)) otherBytes=\(bytes(target) ?? "nil") originalBytes=\(bytes(originalURL) ?? "nil")"
        XCTAssertTrue(isDestinationExists(thrown), "R-5: an existing destination is refused — \(observed)")
        XCTAssertEqual(bytes(target), "another item", "R-5: the other item's bytes are untouched — \(observed)")
        XCTAssertEqual(refs.first { $0.id == otherID }?.relativePath, other.relativePath, "R-5: …and its ref — \(observed)")
        XCTAssertEqual(bytes(originalURL), "original recording", "R-5: the original is intact — \(observed)")
        XCTAssertEqual(refs.first { $0.id == id }?.relativePath, original.relativePath, "R-5: …and its ref — \(observed)")
        XCTAssertEqual(bytes(trim), "trimmed mp4", "R-5: the trim is untouched at its source — \(observed)")
    }

    // MARK: - N-1

    func testN1_saveNewWithPosterUnderTheFaultLeavesNothingAndRestoresTheSource() async throws {
        try await anchor()
        let id = UUID()
        let base = "c90-\(id.uuidString)"
        let media = try source("new video", ext: "mov")
        let poster = try source("new poster", ext: "jpg")

        try applyFault()
        try establishF0()

        var thrown: Error?
        do {
            _ = try await StagingStore.saveNew(from: media, kind: .video, suggestedName: base, duration: 1, poster: poster, id: id)
        } catch { thrown = error }

        let stagedMedia = dayFolder.appendingPathComponent(base).appendingPathExtension("mov")
        let stagedPoster = dayFolder.appendingPathComponent("\(base)_poster").appendingPathExtension("jpg")
        let observed = "thrown=\(String(describing: thrown)) stagedMedia=\(fm.fileExists(atPath: stagedMedia.path)) stagedPoster=\(fm.fileExists(atPath: stagedPoster.path)) sourceMedia=\(bytes(media) ?? "nil")"
        XCTAssertNotNil(thrown, "N-1: a failed metadata write must be reported — \(observed)")
        XCTAssertFalse(try refsOnDisk().contains { $0.id == id }, "N-1: no ref for the id — \(observed)")
        XCTAssertFalse(fm.fileExists(atPath: stagedMedia.path), "N-1: no staged media from this call remains — \(observed)")
        XCTAssertFalse(fm.fileExists(atPath: stagedPoster.path), "N-1: no newly created poster remains — \(observed)")
        XCTAssertEqual(bytes(media), "new video", "N-1: the source media is back at its path — \(observed)")
        XCTAssertEqual(bytes(poster), "new poster", "N-1: the poster source is intact — \(observed)")
    }

    // MARK: - N-2

    func testN2_saveNewRecoversAfterTheFaultIsRemoved() async throws {
        try await anchor()
        let id = UUID()
        let base = "c90-\(id.uuidString)"
        let media = try source("new video", ext: "mov")
        let poster = try source("new poster", ext: "jpg")

        try applyFault()
        try establishF0()
        _ = try? await StagingStore.saveNew(from: media, kind: .video, suggestedName: base, duration: 1, poster: poster, id: id)
        try removeFault()

        let mediaPresentBeforeRetry = fm.fileExists(atPath: media.path)
        let ref: StagedAttachmentRef
        do {
            ref = try await StagingStore.saveNew(from: media, kind: .video, suggestedName: base, duration: 1, poster: poster, id: id)
        } catch {
            XCTFail("N-2: the retry after removing the fault failed — \(error); source media before retry=\(mediaPresentBeforeRetry)")
            return
        }
        XCTAssertEqual(try refsOnDisk().filter { $0.id == id }.count, 1, "N-2: exactly one ref")
        XCTAssertEqual(bytes(StagingStore.absoluteURL(for: ref)), "new video", "N-2: media staged")
        let posterPath = try XCTUnwrap(ref.posterPath, "N-2: the ref names its poster")
        XCTAssertEqual(bytes(StagingStore.absoluteURL(forRelative: posterPath)), "new poster", "N-2: poster staged")
    }

    // MARK: - N-3

    func testN3_saveNewWithPosterSucceedsWithoutAFault() async throws {
        let id = UUID()
        let poster = try source("poster", ext: "jpg")
        let ref = try await StagingStore.saveNew(from: try source("video", ext: "mov"), kind: .video,
                                                 suggestedName: "c90-\(id.uuidString)", duration: 1, poster: poster, id: id)
        XCTAssertEqual(try refsOnDisk().first { $0.id == id }?.relativePath, ref.relativePath, "N-3: ref written")
        XCTAssertEqual(bytes(StagingStore.absoluteURL(for: ref)), "video", "N-3: media staged")
        let posterPath = try XCTUnwrap(ref.posterPath, "N-3: poster named")
        XCTAssertEqual(bytes(StagingStore.absoluteURL(forRelative: posterPath)), "poster", "N-3: poster staged")
        XCTAssertEqual(bytes(poster), "poster", "N-3: the poster source is copied, not moved")
    }

    // MARK: - N-4

    func testN4_saveNewRefusesAnExistingFinalMediaDestination() async throws {
        let id = UUID()
        let base = "c90-\(id.uuidString)"
        try ensureDayFolder()
        let first = dayFolder.appendingPathComponent(base).appendingPathExtension("m4a")
        let collision = dayFolder.appendingPathComponent("\(base)-\(id.uuidString)").appendingPathExtension("m4a")
        try Data("existing A".utf8).write(to: first)
        try Data("existing B".utf8).write(to: collision)
        let media = try source("new recording", ext: "m4a")

        var thrown: Error?
        do { _ = try await StagingStore.saveNew(from: media, kind: .audio, suggestedName: base, id: id) } catch { thrown = error }

        let observed = "thrown=\(String(describing: thrown)) A=\(bytes(first) ?? "nil") B=\(bytes(collision) ?? "nil") source=\(bytes(media) ?? "nil")"
        XCTAssertTrue(isDestinationExists(thrown), "N-4: the final media destination is refused — \(observed)")
        XCTAssertEqual(bytes(first), "existing A", "N-4: first existing file untouched — \(observed)")
        XCTAssertEqual(bytes(collision), "existing B", "N-4: collision-named existing file untouched — \(observed)")
        XCTAssertEqual(bytes(media), "new recording", "N-4: the source is untouched — \(observed)")
        XCTAssertFalse(try refsOnDisk().contains { $0.id == id }, "N-4: no ref for the id — \(observed)")
    }

    // MARK: - N-5

    func testN5_saveNewRefusesAnExistingReferencedPosterDestination() async throws {
        let id = UUID()
        let base = "c90-\(id.uuidString)"
        let otherID = UUID()
        let other = try await StagingStore.saveNew(from: try source("other video", ext: "mp4"), kind: .video,
                                                   suggestedName: base, duration: 1, poster: try source("other poster", ext: "jpg"), id: otherID)
        let otherPosterPath = try XCTUnwrap(other.posterPath, "N-5 setup: the other item names its poster")
        let otherPoster = StagingStore.absoluteURL(forRelative: otherPosterPath)
        guard otherPoster.lastPathComponent == "\(base)_poster.jpg" else {
            throw C90SetupError(reason: "the other poster is not at <base>_poster.jpg (\(otherPosterPath))")
        }
        let media = try source("new video", ext: "mov")
        let newPoster = try source("new poster", ext: "jpg")

        var thrown: Error?
        do {
            _ = try await StagingStore.saveNew(from: media, kind: .video, suggestedName: base, duration: 1, poster: newPoster, id: id)
        } catch { thrown = error }

        let stagedMedia = dayFolder.appendingPathComponent(base).appendingPathExtension("mov")
        let refs = try refsOnDisk()
        let observed = "thrown=\(String(describing: thrown)) otherPoster=\(bytes(otherPoster) ?? "nil") stagedMedia=\(fm.fileExists(atPath: stagedMedia.path)) source=\(bytes(media) ?? "nil")"
        XCTAssertTrue(isDestinationExists(thrown), "N-5: an existing poster destination is refused — \(observed)")
        XCTAssertEqual(bytes(otherPoster), "other poster", "N-5: the other item's referenced poster bytes are untouched — \(observed)")
        XCTAssertEqual(refs.first { $0.id == otherID }?.posterPath, otherPosterPath, "N-5: …and its ref — \(observed)")
        XCTAssertFalse(refs.contains { $0.id == id }, "N-5: no ref for the new id — \(observed)")
        XCTAssertFalse(fm.fileExists(atPath: stagedMedia.path), "N-5: no media staged — \(observed)")
        XCTAssertEqual(bytes(media), "new video", "N-5: the source is untouched — \(observed)")
    }

    // MARK: - N-6

    func testN6_posterCopyFailureRestoresTheSourceAndStagesNothing() async throws {
        let id = UUID()
        let base = "c90-\(id.uuidString)"
        let media = try source("new video", ext: "mov")
        let missingPoster = fm.temporaryDirectory.appendingPathComponent("c90-missing-\(UUID().uuidString)").appendingPathExtension("jpg")

        var thrown: Error?
        do {
            _ = try await StagingStore.saveNew(from: media, kind: .video, suggestedName: base, duration: 1, poster: missingPoster, id: id)
        } catch { thrown = error }

        let stagedMedia = dayFolder.appendingPathComponent(base).appendingPathExtension("mov")
        let observed = "thrown=\(String(describing: thrown)) stagedMedia=\(fm.fileExists(atPath: stagedMedia.path)) source=\(bytes(media) ?? "nil")"
        XCTAssertNotNil(thrown, "N-6: the poster copy failure is reported — \(observed)")
        XCTAssertEqual(bytes(media), "new video", "N-6: the source media is back at its path — \(observed)")
        XCTAssertFalse(fm.fileExists(atPath: stagedMedia.path), "N-6: no staged media remains — \(observed)")
        XCTAssertFalse(try refsOnDisk().contains { $0.id == id }, "N-6: no ref — \(observed)")
    }

    // MARK: - P-1

    func testP1_writePosterUnderTheFaultReportsFailureForANewPoster() async throws {
        let id = UUID()
        let ref = try await StagingStore.saveNew(from: try source("video", ext: "mov"), kind: .video,
                                                 suggestedName: "c90-\(id.uuidString)", id: id)
        XCTAssertNil(ref.posterPath, "P-1 setup: no poster yet")
        let media = StagingStore.absoluteURL(for: ref)
        let expectedPoster = media.deletingLastPathComponent()
            .appendingPathComponent(media.deletingPathExtension().lastPathComponent + "_poster").appendingPathExtension("jpg")

        try applyFault()
        try establishF0()

        let reported = StagingStore.writePoster(for: id, jpeg: Data("new poster".utf8))
        XCTAssertFalse(reported, "P-1: writePoster must report the failed metadata write")
        XCTAssertNil(try refsOnDisk().first { $0.id == id }?.posterPath, "P-1: metadata unchanged — the ref names no poster")
        XCTAssertEqual(bytes(expectedPoster), "new poster",
                       "P-1 DOCUMENTED: the new poster file was written and is unreferenced; false does not promise rollback")
    }

    // MARK: - P-2

    func testP2_writePosterUnderTheFaultReportsFailureForAReferencedPoster() async throws {
        let id = UUID()
        let ref = try await StagingStore.saveNew(from: try source("video", ext: "mov"), kind: .video,
                                                 suggestedName: "c90-\(id.uuidString)", duration: 1,
                                                 poster: try source("old poster", ext: "jpg"), id: id)
        let posterPath = try XCTUnwrap(ref.posterPath, "P-2 setup: the ref names a poster")
        let posterURL = StagingStore.absoluteURL(forRelative: posterPath)

        try applyFault()
        try establishF0()

        let reported = StagingStore.writePoster(for: id, jpeg: Data("new poster".utf8))
        XCTAssertFalse(reported, "P-2: writePoster must report the failed metadata write")
        XCTAssertEqual(try refsOnDisk().first { $0.id == id }?.posterPath, posterPath, "P-2: metadata unchanged — same poster path")
        XCTAssertEqual(bytes(posterURL), "new poster",
                       "P-2 DOCUMENTED: the referenced poster's bytes are the new ones — not rolled back, and not promised")
    }

    // MARK: - M-1

    func testM1_failedMigrationKeepsTheLegacyKeyAndReturnsItsRefs() throws {
        try applyFault()
        try establishFM()

        let legacy = legacyRef()
        UserDefaults.standard.set(try JSONEncoder().encode([legacy]), forKey: legacyKey)

        let returned = StagingStore.list()   // the single scored migration
        let keyAfter = UserDefaults.standard.data(forKey: legacyKey)
        let fileAfter = fm.fileExists(atPath: refsURL.path)

        let observed = "returned=\(returned.map(\.id)) keyPresent=\(keyAfter != nil) stagedJSON=\(fileAfter)"
        XCTAssertEqual(returned.map(\.id), [legacy.id], "M-1: the decoded legacy refs are returned — \(observed)")
        XCTAssertNotNil(keyAfter, "M-1: the legacy key is kept when its migration could not be written — \(observed)")
        XCTAssertFalse(fileAfter, "M-1: no staged.json was written — \(observed)")
    }

    // MARK: - M-2

    func testM2_migrationRecoversAfterTheFaultWithoutReseeding() throws {
        try applyFault()
        try establishFM()

        let legacy = legacyRef()
        UserDefaults.standard.set(try JSONEncoder().encode([legacy]), forKey: legacyKey)
        _ = StagingStore.list()   // the failed migration, as in M-1
        let keyAfterFailure = UserDefaults.standard.data(forKey: legacyKey) != nil

        try removeFault()
        let recovered = StagingStore.list()   // NO reseed

        let observed = "keyAfterFailure=\(keyAfterFailure) recovered=\(recovered.map(\.id)) keyNow=\(UserDefaults.standard.data(forKey: legacyKey) != nil) stagedJSON=\(fm.fileExists(atPath: refsURL.path))"
        XCTAssertEqual(recovered.map(\.id), [legacy.id], "M-2: recovery returns the legacy ref without reseeding — \(observed)")
        XCTAssertEqual(try refsOnDisk().map(\.id), [legacy.id], "M-2: staged.json now holds it — \(observed)")
        XCTAssertNil(UserDefaults.standard.data(forKey: legacyKey), "M-2: the key is removed only after the successful write — \(observed)")
    }

    private func legacyRef() -> StagedAttachmentRef {
        StagedAttachmentRef(id: UUID(), kind: .audio, relativePath: "2020-01-01/c90-legacy.m4a",
                            createdAt: Date(timeIntervalSince1970: 1_700_000_000), duration: 3, posterPath: nil,
                            audioUserTitle: nil, audioAutoTitle: "c90 legacy", audioDisplayTitle: "c90 legacy")
    }

    // MARK: - Source helpers (comments removed; string literals kept)

    private func code(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative)
        return C90Source.stripComments(try String(contentsOf: url, encoding: .utf8))
    }

    /// True when `index` lies after an `#if DEBUG` whose matching `#endif` comes after it.
    private func insideDebugBlock(_ s: String, at index: String.Index) -> Bool {
        let before = s[s.startIndex..<index]
        guard let open = before.range(of: "#if DEBUG", options: .backwards) else { return false }
        return s[open.upperBound..<index].range(of: "#endif") == nil
            && s[index..<s.endIndex].range(of: "#endif") != nil
    }
}

private enum C90Source {
    /// Removes `//` and nested `/* */` comments outside `"…"` / `"""…"""` literals.
    static func stripComments(_ text: String) -> String {
        let s = Array(text)
        var out: [Character] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if s[i] == "\"" {
                let triple = i + 2 < s.count && s[i + 1] == "\"" && s[i + 2] == "\""
                var j = i + (triple ? 3 : 1)
                while j < s.count {
                    if s[j] == "\\" { j += 2; continue }
                    if s[j] == "\"" {
                        if !triple { j += 1; break }
                        if j + 2 < s.count, s[j + 1] == "\"", s[j + 2] == "\"" { j += 3; break }
                    }
                    if !triple, s[j] == "\n" { break }
                    j += 1
                }
                out.append(contentsOf: s[i..<min(j, s.count)]); i = j
            } else if s[i] == "/", i + 1 < s.count, s[i + 1] == "/" {
                while i < s.count, s[i] != "\n" { i += 1 }
            } else if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" {
                var depth = 0
                while i < s.count {
                    if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" { depth += 1; i += 2; continue }
                    if s[i] == "*", i + 1 < s.count, s[i + 1] == "/" { depth -= 1; i += 2; if depth == 0 { break }; continue }
                    i += 1
                }
            } else {
                out.append(s[i]); i += 1
            }
        }
        return String(out)
    }
}
