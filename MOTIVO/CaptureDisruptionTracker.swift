import Foundation

/// C-97 part (2). How the video recorder responds when capture is disrupted: a
/// capture-session runtime error, a capture-session interruption, or an audio-session
/// media-services reset. Pure, so its event sequences are testable without real capture.
///
/// Rules, from Apple's documentation and the approved scope:
/// - A reset or runtime error invalidates capture. Capture is torn down and is NOT
///   restarted automatically ("Your app shouldn't restart its media playback, recording,
///   or processing until initiated by user action" — AVAudioSession
///   mediaServicesWereResetNotification). The member is told to close and reopen the
///   recorder, the existing path that rebuilds the session.
/// - An interruption stops an active take. Its end never restarts capture (recovery is
///   close and reopen) and never stops or fails a take.
/// - A take is always finalised through the existing stop path first. Tear-down waits for
///   the writer; the "kept" message is only given after verified successful finalisation.
struct CaptureDisruptionTracker: Equatable {
    enum Event: Equatable {
        case captureRuntimeError
        case captureInterruptionBegan
        case captureInterruptionEnded
        case audioServicesReset
    }

    enum TakeState: Equatable { case none, recording, startPending, finishing, underReview }

    struct Snapshot: Equatable {
        var isCurrentSession: Bool
        var take: TakeState
        var isAppActive: Bool
        var isShowingLivePreview: Bool
    }

    enum Action: Equatable {
        /// C-97: ask `writerQueue` to race the in-flight start. Its resolution comes back
        /// through `pendingStartCancelled` or `adoptDisruptedStartedTake`.
        case requestPendingStartCancel
        case stopActiveTake
        case tearDownCapture
        /// Pause review playback and clear any automatic playback resume (Apple: no
        /// automatic restart after a reset). The take and its file are untouched.
        case inhibitPlaybackResume
        case showMessage(String)
    }

    static let keptMessage = "Recording stopped because the camera or microphone became unavailable. The part recorded before that has been kept."
    static let reopenSuffix = "Close and reopen the recorder to record again."
    static let reopenMessage = "The camera or microphone was reset by the system. Close and reopen the recorder to continue."
    static let reviewReopenMessage = "The camera or microphone was reset by the system. Save or discard this recording, then close and reopen the recorder to record again."

    private(set) var isInterrupted = false
    private(set) var awaitingReopen = false          // capture torn down (or will be) until the recorder is reopened
    private(set) var takeDisrupted = false           // the active take was stopped by a disruption
    private(set) var tearDownAfterFinish = false     // tear-down deferred until the writer completes

    mutating func handle(_ event: Event, _ s: Snapshot) -> [Action] {
        guard s.isCurrentSession else { return [] }
        switch event {
        case .captureRuntimeError, .audioServicesReset:
            if awaitingReopen { return [] }          // repeated resets coalesce
            awaitingReopen = true
            switch s.take {
            case .recording:
                takeDisrupted = true
                tearDownAfterFinish = true
                return [.stopActiveTake]
            case .finishing:
                tearDownAfterFinish = true
                return []
            case .startPending:
                // C-97: the start is now CANCELLED through PendingStartCoordinator, on
                // writerQueue, which owns the writer. Nothing is decided here, because
                // the answer depends on a race this type cannot see: the start may have
                // already committed. No message and no tear-down yet -- both are ordered
                // AFTER the resolution, by `pendingStartCancelled` or
                // `adoptDisruptedStartedTake` below.
                return [.requestPendingStartCancel]
            case .underReview:
                return [.inhibitPlaybackResume, .tearDownCapture, .showMessage(Self.reviewReopenMessage)]
            case .none:
                return [.inhibitPlaybackResume, .tearDownCapture, .showMessage(Self.reopenMessage)]
            }
        case .captureInterruptionBegan:
            isInterrupted = true
            switch s.take {
            case .recording:
                takeDisrupted = true
                return [.stopActiveTake]
            case .startPending:
                return [.requestPendingStartCancel]
            case .finishing, .underReview, .none:
                return []
            }
        case .captureInterruptionEnded:
            // No automatic capture restart (narrowed): recovery is close and reopen.
            isInterrupted = false
            return []
        }
    }

    /// C-97, the cancellation WON: the start never became a take. Capture is dead, so
    /// this produces the tear-down and message the `.none` branch would have produced --
    /// but only now, after the resolution, never before it.
    mutating func pendingStartCancelled() -> [Action] {
        guard awaitingReopen else { return [] }   // an interruption cancelled it, not a reset
        return [.inhibitPlaybackResume, .tearDownCapture, .showMessage(Self.reopenMessage)]
    }

    /// C-97, STARTUP WON: by the time the cancellation reached `writerQueue` the start had
    /// already committed, so there is a real take. Adopt exactly the state this tracker
    /// would hold had the event arrived one moment later, with `take == .recording` --
    /// otherwise `writerFinished` produces neither the tear-down nor the kept message,
    /// and the take is stopped with no explanation.
    ///
    /// The ORIGINATING EVENT decides, because a reset tears capture down afterwards and an
    /// interruption does not.
    mutating func adoptDisruptedStartedTake(from event: Event) -> [Action] {
        switch event {
        case .captureRuntimeError, .audioServicesReset:
            takeDisrupted = true
            tearDownAfterFinish = true
            return [.stopActiveTake]
        case .captureInterruptionBegan:
            takeDisrupted = true
            return [.stopActiveTake]
        case .captureInterruptionEnded:
            return []
        }
    }

    /// Called once the existing stop path has finished with the writer.
    /// `existingMessage` is any stronger message the stop path already set.
    mutating func writerFinished(succeeded: Bool, keptFileExists: Bool, existingMessage: String?) -> [Action] {
        let wasDisrupted = takeDisrupted
        takeDisrupted = false
        var actions: [Action] = []
        let reopen = tearDownAfterFinish
        if tearDownAfterFinish {
            tearDownAfterFinish = false
            actions.append(.tearDownCapture)
        }
        guard wasDisrupted || reopen else { return actions }

        var message: String?
        if let existingMessage, !existingMessage.isEmpty {
            message = existingMessage                          // stronger audio/writer message wins
        } else if wasDisrupted, succeeded, keptFileExists {
            message = Self.keptMessage
        }
        if reopen {
            message = message.map { $0 + " " + Self.reopenSuffix } ?? Self.reopenMessage
        }
        if let message { actions.append(.showMessage(message)) }
        return actions
    }

    /// After a reset or runtime error, new capture (Record, flip) is refused until the
    /// recorder is closed and reopened (`reset()`, a new presentation).
    var blocksNewCapture: Bool { awaitingReopen }

    /// Re-checked when a queued capture action actually runs, not only when it was decided.
    /// `sameGeneration` is false once the recorder was dismissed or reopened since.
    static func mayExecute(_ action: Action, sameGeneration: Bool, _ s: Snapshot, awaitingReopen: Bool) -> Bool {
        guard sameGeneration, s.isCurrentSession else { return false }
        switch action {
        case .tearDownCapture:
            return s.take == .none || s.take == .underReview
        case .stopActiveTake, .inhibitPlaybackResume, .showMessage, .requestPendingStartCancel:
            return true
        }
    }

    /// A new presentation (the recorder reopened) starts clean.
    mutating func reset() { self = CaptureDisruptionTracker() }
}
