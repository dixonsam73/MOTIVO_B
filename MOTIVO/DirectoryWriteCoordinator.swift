//
//  DirectoryWriteCoordinator.swift
//  MOTIVO
//
//  PHASE 6 · C-70 — ONE DIRECTORY WRITE AT A TIME, AND ONE IDENTITY CLOCK.
//
//  **WHY SERIALISATION AND NOT RESPONSE FILTERING.** Dropping a stale response
//  keeps a late answer from being applied locally. It does nothing whatever
//  about two writes already in flight arriving at the server in either order —
//  by then both have been sent, and the last one to land wins on the server
//  regardless of which the client believes in. Only dispatching one at a time
//  prevents that, so this type exists to make the ordering guarantee real
//  rather than asserted.
//
//  **AND WHAT IT STILL DOES NOT GUARANTEE — read this before relying on it.**
//  This is a CLIENT DISPATCH guarantee. It is not universal server ordering:
//
//    * a timeout or a cancellation can end the client's wait while the server
//      write it started is still running, so the next dispatch can overlap it
//      **without any process death being involved**;
//    * another device's writes interleave arbitrarily and nothing here sees them;
//    * a write already dispatched when the process is killed may land after a
//      later launch has published a newer value.
//
//  Those three are residuals, recorded rather than defended against.
//
//  **AN ACTIVE WRITE IS NEVER CANCELLED TO MAKE ROOM FOR A NEWER EDIT.** A
//  cancelled request does not un-send itself; it only stops us learning what it
//  did, which converts a known outcome into an unknown one.
//

import Foundation

/// The freshness token, readable and writable SYNCHRONOUSLY from any isolation
/// domain.
///
/// **This exists because a `@MainActor` guard cannot protect an `actor`'s
/// mutation.** `await cache.applyIfNewer(...)` suspends between the guard and
/// the mutation, and the main actor is free to run a newer submission — or an
/// identity transition — inside that window. A check taken before the
/// suspension therefore describes the state the mutation was SCHEDULED in,
/// never the state it RUNS in.
///
/// Comparing against previously APPLIED receipts does not close it either: if
/// the newer write has not applied anything yet, there is nothing for the older
/// one to lose to, and it proceeds.
///
/// A lock-protected box is the isolation-safe answer. The coordinator
/// invalidates it synchronously at submission and at every identity
/// transition, and the cache validates it synchronously inside the same
/// segment as the mutation, so no suspension can separate the two.
public final class DirectoryWriteValidity: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var newestSeq: [String: Int] = [:]

    public init() {}

    func noteSubmission(owner: String, seq: Int) {
        lock.lock(); defer { lock.unlock() }
        if let existing = newestSeq[owner], existing >= seq { return }
        newestSeq[owner] = seq
    }

    func noteIdentityTransition() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        newestSeq.removeAll()
    }

    /// Is a write with this generation and sequence still the current intent
    /// for `owner`?
    ///
    /// **Advisory only.** It answers for the instant the lock was held and the
    /// answer can be false by the time the caller acts on it, so it is fit for
    /// skipping work early and NOT for guarding a mutation. Use `withCurrent`
    /// for that.
    public func isCurrent(owner: String, generation: Int, seq: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return isCurrentLocked(owner: owner, generation: generation, seq: seq)
    }

    private func isCurrentLocked(owner: String, generation: Int, seq: Int) -> Bool {
        guard self.generation == generation else { return false }
        if let newest = newestSeq[owner], newest > seq { return false }
        return true
    }

    /// Run `body` **while still holding the lock** that `noteSubmission` and
    /// `noteIdentityTransition` must take, and only if the write is current.
    /// Returns whether it ran.
    ///
    /// **Checking and then mutating is not enough, even with no `await`
    /// between them.** `isCurrent` releases the lock before it returns, and the
    /// caller's next instruction runs on a different thread from the main
    /// actor: an invalidation can land in that window, and the mutation then
    /// commits a value that was current when it was tested and stale when it
    /// was written. Nothing about "the same synchronous segment" helps, because
    /// the two are in different isolation domains and are genuinely concurrent.
    ///
    /// `body` must be short, must not `await`, and must not re-enter this type
    /// — it runs under a non-recursive lock. Its only job is the assignment.
    @discardableResult
    public func withCurrent(owner: String, generation: Int, seq: Int, _ body: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard isCurrentLocked(owner: owner, generation: generation, seq: seq) else { return false }
        body()
        return true
    }

    #if DEBUG
    func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        generation = 0
        newestSeq.removeAll()
    }
    #endif
}

/// One write's outcome together with the tokens a CALLER needs to decide
/// whether its own effects — messages, latches, adoption — are still current.
///
/// The outcome alone cannot answer that. A write can be applied on the server
/// and simultaneously be stale locally, because the member edited again or
/// switched identity while it was in flight; the writer withholds its own
/// effects in that case, and without these tokens the caller would go on to
/// post a message, latch a skip token, or adopt a generated handle for a
/// screen that has moved on.
public struct DirectoryWriteResult {
    public let outcome: DirectoryWriteOutcome
    public let seq: Int
    public let generation: Int

    public var isApplied: Bool { outcome.isApplied }
}

@MainActor
public final class DirectoryWriteCoordinator {

    public static let shared = DirectoryWriteCoordinator()
    init() {}

    // MARK: - Identity clock

    /// Bumped on every real identity transition.
    ///
    /// **Owner equality alone cannot replace this, and A→B→A is why.** A write
    /// bound to A, outlived by a switch to B and a switch back to A, finds the
    /// owner equal and the token subject equal and is nonetheless stale — its
    /// effects belong to a session whose local state has since been torn down
    /// and rehydrated. `SessionSyncQueue.journalDeleteBinding` captures a
    /// generation for exactly this reason, and `NetworkManager.boundRequest`
    /// records the same case in its own comments.
    public private(set) var identityGeneration: Int = 0

    /// Shared with the cache actor so the same decision can be taken on either
    /// side of a suspension.
    public let validity = DirectoryWriteValidity()

    /// Called synchronously from the identity transition itself, never lazily
    /// when a write next happens to arrive.
    public func noteIdentityTransition() {
        identityGeneration &+= 1
        // Pending intent belongs to the identity that submitted it.
        latestProfileEdit.removeAll()
        latestSubmittedSeq.removeAll()
        validity.noteIdentityTransition()
    }

    // MARK: - FIFO dispatch

    private var tail: Task<Void, Never>?
    private var seqCounter: Int = 0
    private var latestProfileEdit: [String: (seq: Int, keys: Set<String>)] = [:]
    /// The newest sequence SUBMITTED for an owner, of any kind.
    ///
    /// Distinct from dispatch order and that is the point: FIFO stops two
    /// writes being in flight at once, but it does not stop A — already in
    /// flight — from completing after B was submitted and merging values B is
    /// about to replace. A receipt that is stale against local intent is not
    /// applied, even though the request that produced it was perfectly valid.
    private var latestSubmittedSeq: [String: Int] = [:]

    /// Run `work` after every previously submitted write has finished.
    private func serialize<T>(_ work: @escaping @MainActor () async -> T) async -> T {
        let predecessor = tail
        let task = Task { @MainActor () -> T in
            if let predecessor { _ = await predecessor.value }
            return await work()
        }
        tail = Task { @MainActor in _ = await task.value }
        return await task.value
    }

    /// Submit one write. Returns when it has resolved — **every caller resolves
    /// a typed outcome and none can hang**, including one that is superseded
    /// before it is ever dispatched.
    ///
    /// `payloadKeys` are the keys the request would actually carry, and they are
    /// what makes suppression safe (see `isSuperseded`).
    /// `capturedGeneration` may be supplied by a caller that captured the epoch
    /// BEFORE an earlier suspension of its own — generation does, because it
    /// reads the directory row before it decides to write.
    public func submit(kind: DirectoryWriteKind,
                       owner: String,
                       payloadKeys: Set<String>,
                       capturedGeneration: Int? = nil,
                       work: @escaping @MainActor (Int, Int) async -> DirectoryWriteOutcome) async -> DirectoryWriteOutcome {
        let normalisedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        seqCounter &+= 1
        let mySeq = seqCounter
        latestSubmittedSeq[normalisedOwner] = mySeq
        // Synchronous, and BEFORE any suspension: a write already in flight
        // must be able to see this one from inside the cache actor.
        validity.noteSubmission(owner: normalisedOwner, seq: mySeq)
        if kind == .profileEdit {
            latestProfileEdit[normalisedOwner] = (mySeq, payloadKeys)
        }
        let generation = capturedGeneration ?? identityGeneration

        return await serialize { [weak self] in
            guard let self else { return .superseded }
            if self.identityGeneration != generation { return .supersededIdentity }
            if self.isSuperseded(kind: kind, owner: normalisedOwner, seq: mySeq, keys: payloadKeys) {
                return .superseded
            }
            return await work(mySeq, generation)
        }
    }

    /// Stale-intent suppression, deliberately narrow.
    ///
    /// **Only a full-profile edit may supersede an earlier full-profile edit,
    /// and only when the newer one carries a SUPERSET of the older one's keys.**
    /// Both halves are load-bearing:
    ///
    ///   * a handle-only `.generation` write must never be discarded by a
    ///     profile edit, nor a profile edit by a generation — they carry
    ///     different intent, and neither subsumes the other;
    ///   * a newer edit that OMITS a key the older one supplied does not
    ///     subsume it. `upsertSelfRow` omits a blank or invalid `account_id` to
    ///     preserve an existing handle, so "newer" does not imply "carries at
    ///     least as much". Suppressing on sequence alone would silently drop an
    ///     explicitly supplied field.
    func isSuperseded(kind: DirectoryWriteKind, owner: String, seq: Int, keys: Set<String>) -> Bool {
        guard kind == .profileEdit else { return false }
        guard let latest = latestProfileEdit[owner], latest.seq > seq else { return false }
        return latest.keys.isSuperset(of: keys)
    }

    // MARK: - Effect gating

    /// May a completed write apply its effects — cache, feed, UI, fingerprint?
    ///
    /// **Called immediately before the mutation, after every suspension.** A
    /// check taken before an `await` establishes nothing about the state on the
    /// other side of it.
    /// `seq` is the submitting write's sequence. Effects are refused once a
    /// NEWER write for the same owner has been submitted, whether or not it has
    /// dispatched — otherwise A, in flight when B was submitted, would publish
    /// values B is about to replace.
    public func mayApplyEffects(owner: String, capturedGeneration: Int, seq: Int) -> Bool {
        guard identityGeneration == capturedGeneration else { return false }
        guard !LocalFactoryReset.isInProgress else { return false }
        let normalised = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard validity.isCurrent(owner: normalised, generation: capturedGeneration, seq: seq) else { return false }
        let current = AuthManager.canonicalBackendUserID()?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return current == normalised
    }

    /// The transport gate for one bound write. Captures the generation by value.
    public func binding(owner: String, capturedGeneration: Int? = nil) -> OperationBinding? {
        let normalised = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let capturedGeneration = capturedGeneration ?? identityGeneration
        return OperationBinding(expectedOwner: normalised, isStillCurrent: { [weak self] in
            guard let self else { return false }
            return self.identityGeneration == capturedGeneration
                && !LocalFactoryReset.isInProgress
                && AuthManager.canonicalBackendUserID()?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalised
        })
    }

    #if DEBUG
    /// Test seam only: how many writes have been SUBMITTED (registered), which
    /// is not the same as dispatched. A test that needs a write to be queued
    /// before it releases another must wait for this rather than assume a child
    /// task has already run.
    var submissionCountForTesting: Int { seqCounter }

    /// Test seam only.
    func resetForTesting() {
        tail = nil
        seqCounter = 0
        latestProfileEdit.removeAll()
        latestSubmittedSeq.removeAll()
        identityGeneration = 0
        validity.resetForTesting()
    }
    #endif
}
