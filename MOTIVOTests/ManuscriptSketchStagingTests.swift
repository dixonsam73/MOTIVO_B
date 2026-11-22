import XCTest
import PencilKit
@testable import Etudes

/// The queue that writes a Timer sketch into the staging store. These run
/// the real queue and the real recovery copies against a staging store whose
/// writes can be held back, so the orderings that matter are made to happen.
@MainActor
final class ManuscriptSketchStagingTests: XCTestCase {

    /// A staging store whose writes wait until they are let go.
    @MainActor
    private final class HeldStore {
        var staged: [UUID: Data] = [:]
        var writes: [Data] = []
        var hold = false
        var fail = false
        private var held: [CheckedContinuation<Void, Never>] = []

        var heldCount: Int { held.count }

        func write(_ id: UUID, _ data: Data) async throws {
            if hold { await withCheckedContinuation { held.append($0) } }
            if fail { throw CocoaError(.fileWriteUnknown) }
            writes.append(data)
            staged[id] = data
        }

        /// Lets the oldest held write finish.
        func releaseOne() {
            guard !held.isEmpty else { return }
            held.removeFirst().resume()
        }

        func waitUntilHeld(_ count: Int) async {
            for _ in 0..<10_000 where held.count < count { await Task.yield() }
        }
    }

    private var store: HeldStore!
    private var queue: ManuscriptSketchStaging!
    private var keys: [String] = []

    override func setUp() async throws {
        let store = HeldStore()
        self.store = store
        queue = ManuscriptSketchStaging(store: .init(
            write: { id, data in try await store.write(id, data) },
            remove: { id in store.staged[id] = nil },
            recoveryStamp: { ManuscriptSketchRecovery.stamp(key: $0) },
            clearRecovery: { ManuscriptSketchRecovery.clear(key: $0) }))
    }

    override func tearDown() async throws {
        ManuscriptSketchRecovery.clear(keys: keys)
        keys = []
    }

    private func newKey() -> String {
        let key = "stagingtest-" + UUID().uuidString
        keys.append(key)
        return key
    }

    private func sketch(strokes: Int) -> ManuscriptSketch {
        let made = (0..<strokes).map { index -> PKStroke in
            let y = CGFloat(40 + index * 30)
            let points = [CGPoint(x: 40, y: y), CGPoint(x: 200, y: y)].map {
                PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: 2, height: 2),
                              opacity: 1, force: 1, azimuth: 0, altitude: 0)
            }
            return PKStroke(ink: PKInk(.monoline, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        return ManuscriptSketch(paper: ManuscriptPaper(kind: .plain, clef: .none), drawing: PKDrawing(strokes: made))
    }

    /// The pad's Save: the recovery copy, marked handed over, then the queue.
    private func save(_ sketch: ManuscriptSketch, as data: String, id: UUID, key: String) {
        XCTAssertTrue(ManuscriptSketchRecovery.handOver(sketch, opening: .reopening(key: key, attachment: nil, held: false)))
        queue.land(id: id, data: Data(data.utf8), recoveryKey: key)
    }

    // MARK: - The ordinary case

    func testOnceTheSketchIsStagedItsRecoveryCopyIsReleased() async {
        let id = UUID(), key = newKey()
        save(sketch(strokes: 1), as: "first", id: id, key: key)
        await queue.settled()
        XCTAssertEqual(store.staged[id], Data("first".utf8))
        XCTAssertNil(ManuscriptSketchRecovery.copy(key: key), "the staged file is the durable copy now")
    }

    // MARK: - The review finding

    /// Save an edit, hold its staging back, reopen and draw more, then let
    /// the earlier staging finish. The strokes drawn since exist only in the
    /// recovery copy, so it must still be there.
    func testAnEarlierStagingDoesNotClearRecoveryWrittenSinceItsSave() async throws {
        let id = UUID(), key = newKey()
        store.hold = true
        save(sketch(strokes: 1), as: "first", id: id, key: key)
        await store.waitUntilHeld(1)

        // Reopened from its tile and drawn on: the pad keeps its copy under
        // the same key, as `ManuscriptPadView.keepNow` does.
        ManuscriptSketchRecovery.keep(sketch(strokes: 2), key: key)

        store.releaseOne()
        await queue.settled()

        XCTAssertEqual(store.staged[id], Data("first".utf8), "the earlier save did land")
        let copy = try XCTUnwrap(ManuscriptSketchRecovery.copy(key: key),
                                 "the newer strokes are only here; an app stopped now would lose them otherwise")
        XCTAssertEqual(copy.sketch.drawing.strokes.count, 2)
        XCTAssertFalse(copy.handedOver)
    }

    /// The same drawing kept again is still a write made since the save: the
    /// stamp is of the copy as written, not of the drawing.
    func testTheStampChangesWheneverTheCopyIsWrittenAgain() throws {
        let key = newKey()
        let drawing = sketch(strokes: 1)
        ManuscriptSketchRecovery.keep(drawing, key: key, handedOver: true)
        let handedOver = try XCTUnwrap(ManuscriptSketchRecovery.stamp(key: key))
        XCTAssertEqual(ManuscriptSketchRecovery.stamp(key: key), handedOver, "unchanged until written again")
        ManuscriptSketchRecovery.keep(drawing, key: key)
        XCTAssertNotEqual(ManuscriptSketchRecovery.stamp(key: key), handedOver)
        ManuscriptSketchRecovery.clear(key: key)
        XCTAssertNil(ManuscriptSketchRecovery.stamp(key: key))
    }

    // MARK: - Two saves of one sketch

    /// Save, then save again while the first write is still under way. The
    /// later version is the one left staged, and only its completion
    /// releases the recovery copy.
    func testAnEarlierStagingDoesNotReplaceALaterSavedVersion() async throws {
        let id = UUID(), key = newKey()
        store.hold = true
        save(sketch(strokes: 1), as: "first", id: id, key: key)
        await store.waitUntilHeld(1)
        save(sketch(strokes: 2), as: "second", id: id, key: key)

        store.releaseOne()                       // the first write finishes late
        await store.waitUntilHeld(1)             // and only then does the second begin
        XCTAssertEqual(store.writes, [Data("first".utf8)])
        XCTAssertEqual(try XCTUnwrap(ManuscriptSketchRecovery.copy(key: key)).sketch.drawing.strokes.count, 2,
                       "the first write must not release the second save's copy")

        store.releaseOne()
        await queue.settled()
        XCTAssertEqual(store.writes, [Data("first".utf8), Data("second".utf8)], "in the order they were saved")
        XCTAssertEqual(store.staged[id], Data("second".utf8))
        XCTAssertNil(ManuscriptSketchRecovery.copy(key: key))
    }

    /// A save overtaken before its write began is not written at all.
    func testASaveOvertakenBeforeItBeganIsNotWritten() async {
        let id = UUID(), key = newKey()
        store.hold = true
        save(sketch(strokes: 1), as: "first", id: id, key: key)
        await store.waitUntilHeld(1)
        save(sketch(strokes: 2), as: "second", id: id, key: key)
        save(sketch(strokes: 3), as: "third", id: id, key: key)

        store.releaseOne()
        await store.waitUntilHeld(1)
        store.releaseOne()
        await queue.settled()

        XCTAssertEqual(store.writes, [Data("first".utf8), Data("third".utf8)])
        XCTAssertEqual(store.staged[id], Data("third".utf8))
        XCTAssertNil(ManuscriptSketchRecovery.copy(key: key))
    }

    // MARK: - Failure

    func testAFailedStagingKeepsTheRecoveryCopy() async throws {
        let id = UUID(), key = newKey()
        store.fail = true
        save(sketch(strokes: 2), as: "first", id: id, key: key)
        await queue.settled()
        XCTAssertNil(store.staged[id])
        let copy = try XCTUnwrap(ManuscriptSketchRecovery.copy(key: key))
        XCTAssertEqual(copy.sketch.drawing.strokes.count, 2)
        XCTAssertTrue(copy.handedOver)
    }

    // MARK: - The bin

    /// Binned while its write is under way: the write is undone when it
    /// lands, and no copy is left to offer back.
    func testASketchBinnedWhileItsWriteIsUnderWayStaysBinned() async {
        let id = UUID(), key = newKey()
        store.hold = true
        save(sketch(strokes: 1), as: "first", id: id, key: key)
        await store.waitUntilHeld(1)

        queue.discard(id)
        store.releaseOne()
        await queue.settled()

        XCTAssertNil(store.staged[id])
        XCTAssertNil(ManuscriptSketchRecovery.copy(key: key))
    }

    /// Binned with a write still waiting its turn: that write is never made.
    func testAWriteWaitingItsTurnIsNotMadeAfterTheBin() async {
        let id = UUID(), key = newKey()
        store.hold = true
        save(sketch(strokes: 1), as: "first", id: id, key: key)
        await store.waitUntilHeld(1)
        save(sketch(strokes: 2), as: "second", id: id, key: key)

        queue.discard(id)
        store.releaseOne()
        await queue.settled()

        XCTAssertEqual(store.writes, [Data("first".utf8)])
        XCTAssertNil(store.staged[id])
        XCTAssertNil(ManuscriptSketchRecovery.copy(key: key))
    }

    /// Another sketch is not held up or disturbed by any of this.
    func testSketchesDoNotWaitForOneAnother() async {
        let slow = UUID(), slowKey = newKey()
        store.hold = true
        save(sketch(strokes: 1), as: "slow", id: slow, key: slowKey)
        await store.waitUntilHeld(1)

        let other = UUID(), otherKey = newKey()
        save(sketch(strokes: 1), as: "other", id: other, key: otherKey)
        await store.waitUntilHeld(2)
        XCTAssertEqual(store.heldCount, 2, "the second sketch's write began without waiting for the first")

        store.releaseOne()
        store.releaseOne()
        await queue.settled()
        XCTAssertEqual(store.staged[slow], Data("slow".utf8))
        XCTAssertEqual(store.staged[other], Data("other".utf8))
    }

    /// The page shows "Preparing…" while a sketch has writes outstanding:
    /// told once when they start and once when the last has finished.
    func testThePageIsToldWhenASketchStartsAndStopsBeingWritten() async {
        let id = UUID(), key = newKey()
        var told: [Bool] = []
        store.hold = true
        ManuscriptSketchRecovery.handOver(sketch(strokes: 1), opening: .reopening(key: key, attachment: nil, held: false))
        queue.land(id: id, data: Data("first".utf8), recoveryKey: key) { told.append($0) }
        await store.waitUntilHeld(1)
        ManuscriptSketchRecovery.handOver(sketch(strokes: 2), opening: .reopening(key: key, attachment: nil, held: false))
        queue.land(id: id, data: Data("second".utf8), recoveryKey: key) { told.append($0) }
        XCTAssertEqual(told, [true])

        store.releaseOne()
        await store.waitUntilHeld(1)
        XCTAssertEqual(told, [true], "still being written")
        store.releaseOne()
        await queue.settled()
        XCTAssertEqual(told, [true, false])
    }
}
