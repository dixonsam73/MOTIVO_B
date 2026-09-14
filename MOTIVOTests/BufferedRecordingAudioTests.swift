import XCTest
@testable import Etudes

final class BufferedRecordingAudioTests: XCTestCase {
    func testRecoveredAudioPrecedesNewerSamplesWithoutRetiming() {
        let rig = AudioDeliveryRig()
        defer { rig.cancel() }
        rig.queue.sync {
            rig.delivery.receive(0.03)
            rig.delivery.receive(0.05)
            rig.ready = true
            rig.delivery.receive(0.07)
            XCTAssertEqual(rig.written, [0.03, 0.05, 0.07])
            XCTAssertTrue(rig.failures.isEmpty)
        }
    }
    func testRetryRecoversWithoutAnotherCaptureCallback() async {
        let rig = AudioDeliveryRig()
        defer { rig.cancel() }
        let recovered = expectation(description: "Pending audio recovered without new sample")
        rig.queue.sync {
            rig.onAppend = { recovered.fulfill() }
            rig.delivery.receive(0.12)
        }
        rig.queue.asyncAfter(deadline: .now() + 0.01) { rig.ready = true }
        await fulfillment(of: [recovered], timeout: 1)
        rig.queue.sync { XCTAssertEqual(rig.written, [0.12]) }
    }
    func testStopWaitsForQueuedAudioAndRejectsLaterCapture() async {
        let rig = AudioDeliveryRig()
        defer { rig.cancel() }
        let stopped = expectation(description: "Drain finished")
        rig.queue.sync {
            rig.delivery.receive(0.1)
            rig.delivery.receive(0.2)
            rig.delivery.finish { failure in
                XCTAssertNil(failure)
                XCTAssertEqual(rig.written, [0.1, 0.2])
                stopped.fulfill()
            }
            rig.delivery.receive(0.3)
        }
        rig.queue.asyncAfter(deadline: .now() + 0.01) { rig.ready = true }
        await fulfillment(of: [stopped], timeout: 1)
    }
    func testStopHasBoundedDeadlineWhenWriterNeverBecomesReady() async {
        let rig = AudioDeliveryRig(stallLimit: 0.03)
        defer { rig.cancel() }
        let stopped = expectation(description: "Stop timed out explicitly")
        rig.queue.sync {
            rig.delivery.receive(0.1)
            rig.delivery.finish { failure in
                XCTAssertEqual(failure, .finishTimeout)
                XCTAssertTrue(rig.written.isEmpty)
                stopped.fulfill()
            }
        }
        await fulfillment(of: [stopped], timeout: 1)
    }
    func testCapacityFailureIsReportedAndExistingQueueStillDrains() {
        let rig = AudioDeliveryRig(capacity: 2)
        defer { rig.cancel() }
        rig.queue.sync {
            rig.delivery.receive(0.1)
            rig.delivery.receive(0.2)
            rig.delivery.receive(0.3)
            XCTAssertEqual(rig.failures, [.capacity])
            rig.ready = true
            rig.delivery.finish { failure in
                XCTAssertEqual(failure, .capacity)
                XCTAssertEqual(rig.written, [0.1, 0.2])
            }
        }
    }
    func testFalseAppendIsNotReportedAsSuccessfulRecording() {
        let rig = AudioDeliveryRig()
        defer { rig.cancel() }
        rig.queue.sync {
            rig.ready = true
            rig.appendSucceeds = false
            rig.delivery.receive(0.1)
            rig.delivery.finish { failure in XCTAssertEqual(failure, .append) }
            XCTAssertEqual(rig.failures, [.append])
        }
    }
    func testFailedWriterCannotAcceptOrSuccessfullyFinishAudio() {
        let rig = AudioDeliveryRig()
        defer { rig.cancel() }
        rig.queue.sync {
            rig.delivery.receive(0.1)
            rig.writing = false
            rig.delivery.finish { failure in XCTAssertEqual(failure, .writer) }
            XCTAssertTrue(rig.written.isEmpty)
        }
    }
    func testLiveStallReportsFailureEvenWithoutNewSamples() async {
        let rig = AudioDeliveryRig(stallLimit: 0.03)
        defer { rig.cancel() }
        let failed = expectation(description: "Live stall detected")
        rig.queue.sync {
            rig.onFailure = { value in XCTAssertEqual(value, .stalled); failed.fulfill() }
            rig.delivery.receive(0.1)
        }
        await fulfillment(of: [failed], timeout: 1)
    }
    func testCancellationPreventsLateRetryOrFinishCallback() async {
        let rig = AudioDeliveryRig()
        let next = AudioDeliveryRig()
        defer { rig.cancel(); next.cancel() }
        rig.queue.sync {
            rig.delivery.receive(0.1)
            rig.delivery.finish { _ in XCTFail("Cancelled take finished") }
            rig.delivery.cancel()
            rig.ready = true
            rig.delivery.receive(0.2)
        }
        next.queue.sync {
            next.ready = true
            next.delivery.receive(0.01)
        }
        try? await Task.sleep(for: .milliseconds(40))
        rig.queue.sync { XCTAssertTrue(rig.written.isEmpty) }
        next.queue.sync { XCTAssertEqual(next.written, [0.01]) }
    }
    func testNegativeDuplicateAndOutOfOrderTimestampsFailInsteadOfBeingShifted() {
        for timestamps in [[-0.02], [0.1, 0.1], [0.2, 0.1], [Double.nan]] {
            let rig = AudioDeliveryRig()
            rig.queue.sync {
                rig.ready = true
                for timestamp in timestamps { rig.delivery.receive(timestamp) }
                XCTAssertEqual(rig.failures, [.timestamp])
            }
            rig.cancel()
        }
    }
}

private final class AudioDeliveryRig: @unchecked Sendable {
    let queue = DispatchQueue(label: "test.recording.audio.delivery")
    // All mutable state below is read/written exclusively on queue.
    var ready = false
    var writing = true
    var appendSucceeds = true
    var written: [Double] = []
    var failures: [RecordingAudioDeliveryFailure] = []
    var onAppend: (() -> Void)?
    var onFailure: ((RecordingAudioDeliveryFailure) -> Void)?
    var delivery: BufferedRecordingAudio<Double>!

    init(capacity: Int = 240, stallLimit: TimeInterval = 0.2) {
        delivery = BufferedRecordingAudio(queue: queue, capacity: capacity, retryInterval: 0.002,
            stallLimit: stallLimit,
            isWriting: { [weak self] in self?.writing == true },
            isReady: { [weak self] in self?.ready == true },
            append: { [weak self] value in
                guard let self, self.appendSucceeds else { return false }
                self.written.append(value); self.onAppend?(); return true
            }, timestamp: { $0 }, onFailure: { [weak self] value in
                self?.failures.append(value); self?.onFailure?(value)
            })
    }
    func cancel() { queue.sync { delivery.cancel() } }
}
