//
//  PendingStartCoordinator.swift
//  MOTIVO
//
//  CHANGE-ID: 20260920_150000_C97_PendingStartCancellation
//  SCOPE: C-97 — cancellation of a recording start that is in flight. Pure, so the
//  ordering can be tested deterministically without real capture.
//  SEARCH-TOKEN: 20260920_150000_C97_PendingStartCancellation
//

import Foundation

/// C-97. A recording start is NOT a single moment. Between the Record tap and
/// `state == .recording` the recorder passes through six stages, and `state` is `.idle`
/// through all of them:
///
///   S0 arm                         main          isArmedToRecord = true, URL minted
///   S1 first frame -> setupWriter  writerQueue   THE OUTPUT FILE IS CREATED HERE
///   S2 cadence gate arms session   writerQueue   isStartingWriterSession = true
///   S3 startSession(atSourceTime:) sessionStartQueue   MAY BLOCK; holds its own writer
///   S4 continuation                writerQueue   writerSessionReady = true
///   S5 commit + main transition    writerQueue   -> DispatchQueue.main.async { state = .recording }
///   S6 the transition lands        main          state = .recording
///
/// So a disruption arriving in this window cannot be answered by clearing a flag. It has
/// to RACE FOR THE CLAIM and then finalise according to who won, and the finalisation
/// differs by stage because from S1 there is a real file on disk.
///
/// **`writerQueue` is the single linearization point.** It owns the writer, and both the
/// S1 claim and the S4 continuation already run there. Everything in this type is
/// `writerQueue`-only; main publishes a cancellation with one `async` and never reads it.
///
/// **A claim owns its URL immutably.** File effects select what to delete from
/// `claim.url`, never by re-reading the mutable `recordingURL`, so a cancellation can
/// never reach a reviewed take or a newer start.
struct PendingStartCoordinator {

    enum Stage: Equatable {
        case armed            // no writer yet, no file on disk
        case writerCreated    // setupWriter ran: a file exists at claim.url
        case sessionStarting  // startSession is in flight off-queue and cannot be stopped
        case sessionReady     // startSession returned; not yet committed
        case committed        // recordingStartTime set; the main transition is in flight
    }

    struct Claim: Equatable {
        let token: UUID
        let presentation: UUID
        /// Immutable. The only thing a file effect is ever allowed to act on.
        let url: URL
        var stage: Stage
    }

    /// What the canceller must do, decided on `writerQueue`.
    enum Resolution: Equatable {
        /// No live claim, or the token names something else. Do nothing.
        case noClaim
        /// Cancellation won before any file existed. Disarm; NO file effect.
        case cancelledBeforeWriter
        /// Cancellation won with a writer created. Cancel that writer, delete THIS url.
        case cancelledWithWriter(url: URL)
        /// `startSession` is in flight and cannot be stopped. The continuation finalises.
        case deferredUntilSessionReturns
        /// Startup already won. Do NOT cancel: hand off to the ordinary stop path so the
        /// take is preserved, and let the tracker adopt the disruption.
        case startupAlreadyWon
    }

    /// What an S4 continuation must do when `startSession` returns.
    enum Continuation: Equatable {
        /// The live claim, uncancelled: proceed with the ordinary session-ready path.
        case proceed
        /// The live claim, cancelled while blocked: finalise now, exactly once.
        case finaliseCancelled(url: URL)
        /// A RETIRED claim (superseded, or the recorder was dismissed and reopened while
        /// startSession was blocked). Clean up ITS OWN writer and url, exactly once, and
        /// touch no shared or UI state -- a newer claim may be live.
        case cleanUpRetired(url: URL)
        /// Already cleaned up. Do nothing (repeated cancellation, double delivery).
        case alreadySettled
    }

    private(set) var claim: Claim?
    private var pendingCancelToken: UUID?
    /// Claims that lost their place while `startSession` was blocked. Exactly-once by
    /// construction: the entry is removed when its continuation collects it.
    private var retired: [UUID: URL] = [:]

    /// C-97. What a sample buffer may do, decided by the claim and nothing else.
    enum FrameDisposition: Equatable {
        /// No claim on this queue yet (the arm block has not run) or the start is over.
        /// The frame must do NOTHING -- in particular it must not clear main's arm flags,
        /// which would kill a start that is about to be armed.
        case noClaim
        /// Proceed, writing to this claim's own immutable url.
        case proceed(token: UUID, url: URL)
    }

    var frameDisposition: FrameDisposition {
        guard let c = claim else { return .noClaim }
        return .proceed(token: c.token, url: c.url)
    }

    var currentToken: UUID? { claim?.token }
    var currentStage: Stage? { claim?.stage }
    var hasLiveClaim: Bool { claim != nil }
    var retiredCount: Int { retired.count }

    // MARK: - Stage transitions (writerQueue)

    /// Returns the url of a previous claim this arm ABANDONED, if it left a file behind
    /// and no continuation owns it. The caller must delete it: a claim replaced without
    /// cleanup leaks a partial capture file into Documents.
    @discardableResult
    mutating func arm(token: UUID, presentation: UUID, url: URL) -> URL? {
        var abandoned: URL?
        if let old = claim {
            switch old.stage {
            case .sessionStarting:
                // Its continuation owns the writer and the file; it cleans up, not us.
                retired[old.token] = old.url
            case .writerCreated, .sessionReady:
                abandoned = old.url
            case .armed, .committed:
                break
            }
        }
        claim = Claim(token: token, presentation: presentation, url: url, stage: .armed)
        pendingCancelToken = nil
        return abandoned
    }

    mutating func advance(_ token: UUID, to stage: Stage) {
        guard var c = claim, c.token == token else { return }
        c.stage = stage
        claim = c
    }

    /// The start failed on its own (writer setup threw, or the writer reported failure).
    /// Returns the url to clean up, if a file can exist.
    mutating func failed(_ token: UUID) -> URL? {
        guard let c = claim, c.token == token else { return nil }
        claim = nil
        pendingCancelToken = nil
        // `.armed` means setupWriter has not been entered. Every later stage may have
        // left a partial file at claim.url, including a THROWING setupWriter, because
        // AVAssetWriter can create the output file before it fails.
        return c.stage == .armed ? nil : c.url
    }

    /// The take is now the recorder's ordinary business; the claim is done.
    mutating func settle(_ token: UUID) {
        guard let c = claim, c.token == token else { return }
        claim = nil
        pendingCancelToken = nil
    }

    /// The presentation changed (dismiss, or reopen) while a claim was live.
    /// Returns the url of a claim that is now owned by an in-flight continuation, if
    /// any. The caller must NOT cancel that writer or delete that file itself: the
    /// continuation will, exactly once, and duplicating it races a live `startSession`.
    @discardableResult
    mutating func retireForPresentationChange() -> URL? {
        guard let c = claim else { return nil }
        var ownedByContinuation: URL?
        if c.stage == .sessionStarting {
            retired[c.token] = c.url
            ownedByContinuation = c.url
        }
        claim = nil
        pendingCancelToken = nil
        return ownedByContinuation
    }

    // MARK: - Cancellation (writerQueue)

    mutating func requestCancel(token: UUID) -> Resolution {
        guard let c = claim, c.token == token else { return .noClaim }
        switch c.stage {
        case .armed:
            claim = nil
            pendingCancelToken = nil
            return .cancelledBeforeWriter
        case .writerCreated, .sessionReady:
            claim = nil
            pendingCancelToken = nil
            return .cancelledWithWriter(url: c.url)
        case .sessionStarting:
            // Cannot be stopped: startSession is blocked off-queue holding its own
            // writer. The continuation is a mandatory participant, not an afterthought.
            pendingCancelToken = token
            return .deferredUntilSessionReturns
        case .committed:
            return .startupAlreadyWon
        }
    }

    // MARK: - The S4 continuation (writerQueue)

    mutating func sessionStartReturned(_ token: UUID) -> Continuation {
        if let c = claim, c.token == token {
            if pendingCancelToken == token {
                claim = nil
                pendingCancelToken = nil
                return .finaliseCancelled(url: c.url)
            }
            return .proceed
        }
        if let url = retired.removeValue(forKey: token) {
            return .cleanUpRetired(url: url)      // exactly once: the entry is gone
        }
        return .alreadySettled
    }

    /// A new presentation starts clean. Retired entries are NOT dropped: their
    /// continuations may still be blocked inside `startSession`.
    mutating func resetForNewPresentation() {
        retireForPresentationChange()
    }
}
