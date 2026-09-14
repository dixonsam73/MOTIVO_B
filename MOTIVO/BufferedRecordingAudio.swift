import Foundation

enum RecordingAudioDeliveryFailure: Error, Equatable {
    case capacity, append, writer, stalled, finishTimeout, timestamp
}

/// Post-start audio delivery for a single writer. Every method runs on its writer
/// queue. A weak, cancellable retry drains a push source even if no more samples arrive.
/// No work from this object participates in capture warmup or choosing the A/V origin.
final class BufferedRecordingAudio<Sample>: @unchecked Sendable {
    private let queue: DispatchQueue
    private let capacity: Int
    private let retryInterval: TimeInterval
    private let stallLimit: TimeInterval
    private let isWriting: () -> Bool
    private let isReady: () -> Bool
    private let append: (Sample) -> Bool
    private let timestamp: (Sample) -> Double
    private let onFailure: (RecordingAudioDeliveryFailure) -> Void
    private var pending: [Sample] = []
    private var lastTimestamp: Double?
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var retry: DispatchWorkItem?
    private var retryID: UUID?
    private var failure: RecordingAudioDeliveryFailure?
    private var finishing = false
    private var closed = false
    private var deadline: TimeInterval?
    private var completion: ((RecordingAudioDeliveryFailure?) -> Void)?

    init(queue: DispatchQueue, capacity: Int = 240, retryInterval: TimeInterval = 0.01,
         stallLimit: TimeInterval = 2, isWriting: @escaping () -> Bool,
         isReady: @escaping () -> Bool, append: @escaping (Sample) -> Bool,
         timestamp: @escaping (Sample) -> Double,
         onFailure: @escaping (RecordingAudioDeliveryFailure) -> Void) {
        precondition(capacity > 0 && retryInterval > 0 && stallLimit > 0)
        self.queue = queue; self.capacity = capacity
        self.retryInterval = retryInterval; self.stallLimit = stallLimit
        self.isWriting = isWriting; self.isReady = isReady; self.append = append
        self.timestamp = timestamp; self.onFailure = onFailure
    }

    func receive(_ sample: Sample) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !closed, !finishing, failure == nil else { return }
        let pts = timestamp(sample)
        guard pts.isFinite, pts >= 0, lastTimestamp.map({ pts > $0 }) ?? true else {
            report(.timestamp); return
        }
        drain()
        guard !closed, failure == nil else { return }
        guard pending.count < capacity else { report(.capacity); return }
        if pending.isEmpty { lastProgress = ProcessInfo.processInfo.systemUptime }
        pending.append(sample)
        lastTimestamp = pts
        drain()
    }

    func finish(_ completion: @escaping (RecordingAudioDeliveryFailure?) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !closed, !finishing else { return }
        finishing = true
        self.completion = completion
        deadline = ProcessInfo.processInfo.systemUptime + stallLimit
        drain()
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(queue))
        closed = true
        retry?.cancel(); retry = nil
        retryID = nil
        completion = nil
        pending.removeAll()
    }

    private func report(_ value: RecordingAudioDeliveryFailure) {
        guard failure == nil else { return }
        failure = value
        onFailure(value)
    }

    private func drain() {
        guard !closed else { return }
        if !isWriting() {
            pending.removeAll()
            report(.writer)
        } else {
            while !pending.isEmpty, isReady() {
                let sample = pending.removeFirst()
                guard append(sample) else {
                    pending.removeAll()
                    report(.append)
                    break
                }
                lastProgress = ProcessInfo.processInfo.systemUptime
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if !pending.isEmpty {
            if let deadline, now >= deadline {
                pending.removeAll()
                report(.finishTimeout)
            } else if !finishing, now - lastProgress >= stallLimit {
                report(.stalled)
            }
        }
        if pending.isEmpty {
            retry?.cancel(); retry = nil
            retryID = nil
            if finishing {
                closed = true
                let callback = completion; completion = nil
                callback?(failure)
            }
        } else {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retry == nil, !closed else { return }
        let id = UUID()
        retryID = id
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.closed, self.retryID == id else { return }
            self.retry = nil
            self.retryID = nil
            self.drain()
        }
        retry = item
        queue.asyncAfter(deadline: .now() + retryInterval, execute: item)
    }
}
