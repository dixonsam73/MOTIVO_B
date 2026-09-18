//
//  SessionSyncQueue.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-SessionSyncQueue-a9e1-fix2
//  SCOPE: v7.12D — Deferred local publish queue (no networking)
//  CHANGE-ID: 20251230-SessionSyncQueue-6A-wire-preview-upload
//  SCOPE: v7.12D — Step 6A minimal real-call wiring (preview only)
//  CHANGE-ID: 20251230_210900-SessionSyncQueue-NSLogFlush
//  SCOPE: Step 7 — Ensure flush path is visible in Xcode console and always attempts upload in Backend Preview
//
//  CHANGE-ID: 20260119_132532_Step12_NotesPublishParity
//  SCOPE: Include Session.notes in backend publish queue payload (no UI changes)
//  SEARCH-TOKEN: NOTES-PUBLISH-PARITY-20260119
//

// SEARCH-TOKEN: 20260122_113000_Phase142_QueueFlushConnected

// CHANGE-ID: 20260303_092100_DeleteAccountV2_Stage2_BackendConfig_QueueStop
// SCOPE: Delete Account v2 Stage 2 — add stop/wipe hooks and reset gate for flushNow (inactive unless invoked)
// SEARCH-TOKEN: 20260303_092100-DELETE-ACCOUNT-V2-STAGE2

// CHANGE-ID: 20260130_143500_PubPrivacyFinal
// SCOPE: Decouple publish vs share: always publish session-backed post; is_public reflects Share toggle; eliminate stub posts from Share OFF.
import Foundation

@MainActor
public final class SessionSyncQueue: ObservableObject {
    public static let shared = SessionSyncQueue()

    private var isFactoryResetting: Bool = false

    /// C-87 / C-91. ACKNOWLEDGEMENT IS OWNED BY THE INTENT THAT WAS SENT.
    ///
    /// `flushNow()` snapshots `items`, awaits the network, and used to dequeue
    /// BY POST ID on success -- so an older publish's acknowledgement removed
    /// the newer unshare that C-61's last-intent replacement had put in its
    /// place, and two overlapping flushes sent the same item twice and could
    /// complete out of the member's order.
    ///
    /// Three pieces, all in-memory and main-actor, none persisted:
    ///   - `revisions` -- every enqueue gives its post a new revision; a
    ///     success dequeues only if the item is STILL the revision it sent.
    ///   - single flight -- one flush runs at a time; a caller that arrives
    ///     mid-flush waits for it and asks for another pass (`flushAgain`), so
    ///     a newer intent is sent after the older one has finished.
    ///   - `generation` -- a factory reset starts a new generation, so a flush
    ///     from before the reset can neither acknowledge nor continue.
    ///
    /// P6-I-02. The key is (OWNER, POST), not the post alone. Two identities
    /// could otherwise merge into, supersede or acknowledge one another's intent
    /// for the same post id.
    struct QueueKey: Hashable {
        let owner: String?
        let postID: UUID
    }

    private var revisions: [QueueKey: Int] = [:]
    private var nextRevision = 0
    private var generation = 0
    private var activeFlush: Task<Void, Never>?
    private var activeFlushID: UUID?
    /// The generation the running flush belongs to, so a joining caller can tell
    /// whether that flush is still able to serve its request.
    private var activeFlushGeneration = 0
    private var flushAgain = false

    /// C-61 / P4-U2a-2. WHAT THIS QUEUE ITEM ASKS FOR.
    ///
    /// The queue used to mean exactly one thing -- "publish this" -- so an
    /// UNSHARE could only ever be an immediate, fire-and-forget network call
    /// with no durable intent behind it. Measured: an offline unshare left
    /// nothing on disk and nothing retried it, so the post stayed PUBLIC.
    ///
    /// `.unshare` gives the withdrawal the same durability the publish already
    /// had: persisted to the same file, drained by the same `flushNow`, retried
    /// by the same launch/foreground trigger. No parallel subsystem.
    public enum PostOp: String, Codable {
        case publish
        case unshare
    }

    public struct PostPublishPayload: Codable, Identifiable, Equatable {
      public let id: UUID            // == postID
      public let sessionID: UUID?
      public let sessionTimestamp: Date?
      public let title: String?
      public let durationSeconds: Int?
      public let activityType: String?
      public let activityDetail: String?
      public let instrumentLabel: String?
      public let mood: Int?
      public let effort: Int?

      // Visibility: true = share with approved followers; false = owner-only
      public let isPublic: Bool

      // Step 12 (beta parity): notes
      public let notes: String?
      public let areNotesPrivate: Bool

      /// UNIT 1 — DURABLE CONSENT. Attachment ids the member explicitly
      /// authorised omitting from THIS share, after being told before it was
      /// queued that they could not be included.
      ///
      /// **Optional with a `nil` default**, the `op` precedent (P4-U2a-2), so a
      /// legacy queue file decodes unchanged and an older build ignores the key
      /// — both directions measured in `QueuePayloadCompatibilityProbe`.
      ///
      /// **The attachment's persistent private-eye state is NEVER mutated to
      /// achieve an exclusion.** That would rewrite the member's stated intent
      /// and silently un-share it for good. The consent belongs to one publish,
      /// so it travels with the publish: a retry omits exactly what was
      /// authorised, and nothing else.
      public var authorisedOmissions: [UUID]? = nil

      /// C-61 / P4-U2c. DERIVED FROM `isPublic`, NEVER SUPPLIED BY A CALLER.
      ///
      /// `op` and `isPublic` are the SAME BIT and always were: `.publish` means
      /// the post must exist AND be visible -- a private post must not exist at
      /// all (invariant 2) -- and `.unshare` means it must not exist, so its
      /// visibility is meaningless. The forbidden state `.publish` +
      /// `isPublic == false` is exactly the case where two redundant fields
      /// disagree, and it would have reached `uploadPost`, writing a private row
      /// AND uploading its attachments.
      ///
      /// There is therefore no `op:` initialiser parameter. The contradiction is
      /// not merely unlikely, it does not compile. `init(from:)` below closes
      /// the same hole for a file on disk.
      public let op: PostOp

      /// P6-I-02 — WHOSE INTENT THIS IS.
      ///
      /// Captured SYNCHRONOUSLY at the member's action, before any deferred
      /// `Task`, and never re-derived at flush time. The defect this closes is
      /// that the owner used to be read when the flush ran
      /// (`BackendShim.uploadPost`), so a queue written by A and flushed while B
      /// was signed in uploaded A's work as B.
      ///
      /// **Optional with a `nil` default**, the `op` / `authorisedOmissions`
      /// precedent, so a legacy item decodes. `nil` means UNKNOWN PROVENANCE and
      /// is quarantined — never adopted by whoever happens to be signed in.
      public var ownerUserID: String? = nil

      public init(
          id: UUID,
          sessionID: UUID?,
          sessionTimestamp: Date?,
          title: String?,
          durationSeconds: Int?,
          activityType: String?,
          activityDetail: String?,
          instrumentLabel: String?,
          mood: Int?,
          effort: Int?,
          isPublic: Bool = true,
          notes: String? = nil,
          areNotesPrivate: Bool = false,
          authorisedOmissions: [UUID]? = nil,
          ownerUserID: String? = nil
      ) {
          self.id = id
          self.sessionID = sessionID
          self.sessionTimestamp = sessionTimestamp
          self.title = title
          self.durationSeconds = durationSeconds
          self.activityType = activityType
          self.activityDetail = activityDetail
          self.instrumentLabel = instrumentLabel
          self.mood = mood
          self.effort = effort
          self.isPublic = isPublic
          self.notes = notes
          self.areNotesPrivate = areNotesPrivate
          self.authorisedOmissions = authorisedOmissions
          self.ownerUserID = ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          // DERIVED. See the `op` declaration above.
          self.op = isPublic ? .publish : .unshare
      }

      /// P6-I-02. A copy bound to `owner`, for the capture site.
      public func withOwner(_ owner: String?) -> PostPublishPayload {
          var copy = self
          copy.ownerUserID = owner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          return copy
      }

      /// BACKWARD COMPATIBILITY IS THE WHOLE REASON THIS EXISTS. A synthesised
      /// `Codable` conformance treats `op` as required and would throw
      /// `keyNotFound` on every item written before P4-U2a-2 -- which
      /// `load(from:)` would then hand to its legacy `[UUID]` fallback, and
      /// failing that would propagate, silently discarding a queue of real
      /// pending publishes. Decoding it as optional-with-default is what keeps
      /// an existing file meaning exactly what it meant before.
      public init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          id = try c.decode(UUID.self, forKey: .id)
          sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
          sessionTimestamp = try c.decodeIfPresent(Date.self, forKey: .sessionTimestamp)
          title = try c.decodeIfPresent(String.self, forKey: .title)
          durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
          activityType = try c.decodeIfPresent(String.self, forKey: .activityType)
          activityDetail = try c.decodeIfPresent(String.self, forKey: .activityDetail)
          instrumentLabel = try c.decodeIfPresent(String.self, forKey: .instrumentLabel)
          mood = try c.decodeIfPresent(Int.self, forKey: .mood)
          effort = try c.decodeIfPresent(Int.self, forKey: .effort)
          isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? true
          notes = try c.decodeIfPresent(String.self, forKey: .notes)
          areNotesPrivate = try c.decodeIfPresent(Bool.self, forKey: .areNotesPrivate) ?? false
          // P4-U2c. NORMALISE, because removing the initialiser parameter
          // cannot police a file on disk -- a legacy queue file, or a
          // hand-edited one, can still assert the contradiction.
          //
          // A CONTRADICTION RESOLVES TO THE SAFE READING, NEVER TO "UPLOAD IT".
          //
          //   no op, isPublic true/absent -> .publish   (unchanged)
          //   no op, isPublic FALSE       -> .unshare   (migration, below)
          //   op present and agreeing      -> as written
          //   op publish + isPublic false  -> .unshare   (the contradiction)
          //
          // THE MIGRATION IS A DELIBERATE BEHAVIOUR CHANGE. A legacy item with
          // isPublic:false meant "publish this and demote it to private" -- the
          // pre-U2b Share-OFF behaviour. It now converges to DELETION instead,
          // which is the member's original Share-OFF intent under Phase 4's rule
          // that private content does not belong on Supabase, and is strictly
          // safer than leaving a private row. Decoding it as `.publish` would
          // either upload a private row or stick in the queue for ever.
          // UNIT 1b. This MUST be decoded explicitly: `authorisedOmissions`
          // carries a default, so a custom initialiser compiles happily without
          // touching it — and the member's consent would then be silently lost
          // on relaunch, re-prompting them or, worse, omitting nothing.
          authorisedOmissions = try c.decodeIfPresent([UUID].self, forKey: .authorisedOmissions)
          // P6-I-02. Absent means UNKNOWN, not "mine".
          ownerUserID = try c.decodeIfPresent(String.self, forKey: .ownerUserID)?
              .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

          let declared = try c.decodeIfPresent(PostOp.self, forKey: .op)
          op = (isPublic == false) ? .unshare : (declared ?? .publish)
      }
    }

    /// Attributable work, for EVERY owner. The dispatch boundary in `flushOnce`
    /// decides which of it may be sent now; an item belonging to an identity that
    /// is not current is HELD here, not discarded.
    @Published public private(set) var items: [PostPublishPayload] = []

    /// P6-I-02. Work whose owner cannot be established — a queue file written
    /// before this unit, or by an older build after a downgrade. **Never
    /// dispatched, never adopted, never deleted on a timer.** It leaves
    /// quarantine only through explicit owner reauthorisation, which is not built
    /// in this unit.
    @Published public private(set) var quarantined: [PostPublishPayload] = []

    /// The store's last whole-store result. **Dispatch depends on this being
    /// `.ok`**, not merely on a file decoding: after any halt the queue holds no
    /// dispatchable work and writes nothing, so a valid older file is neither
    /// dispatched nor overwritten.
    public private(set) var reconcileState: SessionSyncQueueReconcile = .ok

    private let store: SessionSyncQueueStore
    private var envelope: SessionSyncQueueEnvelope = .empty()

    /// True when a write failed and memory holds intent the disk does not. The
    /// member's newer action is NOT discarded; it simply cannot be dispatched or
    /// written until `attemptStoreRecovery()` succeeds.
    public private(set) var memoryDivergesFromDisk = false

    /// Whether memory has ever held a COMPLETE, successfully reconciled view of
    /// the store.
    ///
    /// This is what makes recovery decidable. When it is true, memory is
    /// everything disk had PLUS everything that happened since — including
    /// REMOVALS — so memory is authoritative and an older on-disk item must not
    /// come back. When it is false, the store was already halted when this
    /// process started, memory never saw what disk held, and recovery must take
    /// the union or work queued before this launch would be discarded.
    private var memoryIsAuthoritative = false

    private init() {
        self.store = SessionSyncQueueStore(root: SessionSyncQueue.storeRoot())
        reload()
    }

    /// Runs the store's whole-store reconciliation and adopts the result.
    ///
    /// There is deliberately NO `(try? load()) ?? []` here. A damaged store used
    /// to read as "no pending work", which silently discarded a member's queued
    /// publishes and owed withdrawals.
    private func reload() {
        let (state, envelope) = store.reconcile()
        reconcileState = state
        guard state.isOK, let envelope else {
            self.items = []
            self.quarantined = []
            memoryIsAuthoritative = false
            NSLog("[SessionSyncQueue] store halted • %@", state.diagnostic)
            BackendLogger.notice("Queue store halted • \(state.diagnostic)")
            return
        }
        // The same invariant on the way in: an item whose owner is absent or
        // empty is quarantined rather than admitted to the dispatchable set.
        // Nothing is discarded — it moves, it does not vanish.
        let (dispatchable, unowned) = partitionByProvenance(envelope.items)
        let held = envelope.quarantined + unowned
        var normalised = envelope
        normalised.items = dispatchable
        normalised.quarantined = held
        self.envelope = normalised
        self.items = dispatchable
        self.quarantined = held
        memoryIsAuthoritative = true
        for item in items { noteNewIntent(item) }
        if dispatchable.count != envelope.items.count {
            BackendLogger.notice("Queue load • \(envelope.items.count - dispatchable.count) item(s) moved to quarantine for unknown provenance")
        }
        if !quarantined.isEmpty {
            NSLog("[SessionSyncQueue] quarantined items held • count=%d", quarantined.count)
            BackendLogger.notice("Queue quarantine • held=\(quarantined.count) • not dispatchable")
        }
    }

    // MARK: - Public API

    /// Returns a copy bound to `owner`. Used at the capture site, so the rest of
    /// the publish path cannot forget to supply it.
    /// Empty and whitespace-only are the SAME as absent: unknown provenance.
    /// Normalising in one place stops `""` slipping into `items` and behaving
    /// like an owner that merges, clears and compares.
    static func normalisedOwner(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// THE DISPATCHABILITY INVARIANT, IN ONE PLACE. An item whose owner is
    /// absent or empty is held, never dispatchable. Load and recovery both go
    /// through this, so the two cannot drift: an earlier revision normalised on
    /// load only, and recovery could therefore adopt an unowned item straight
    /// into the dispatchable set.
    private func partitionByProvenance(_ raw: [PostPublishPayload]) -> (dispatchable: [PostPublishPayload], held: [PostPublishPayload]) {
        var dispatchable: [PostPublishPayload] = []
        var held: [PostPublishPayload] = []
        for item in raw {
            if let owner = Self.normalisedOwner(item.ownerUserID) {
                dispatchable.append(item.withOwner(owner))
            } else {
                held.append(item.withOwner(nil))
            }
        }
        return (dispatchable, held)
    }

    private func key(_ payload: PostPublishPayload) -> QueueKey {
        QueueKey(owner: payload.ownerUserID, postID: payload.id)
    }

    /// The identity the app is currently acting as, lowercased, or nil.
    static func currentOwner() -> String? { AuthManager.canonicalBackendUserID() }

    @discardableResult
    public func enqueue(_ payload: PostPublishPayload) -> Bool {
        // A halted store cannot make anything durable, but the member's newer
        // intent must not be thrown away either. It is retained in memory,
        // reported as NOT durable, and cannot be dispatched (the flush guard) or
        // written (the persist guard) until recovery succeeds.
        if !reconcileState.isOK {
            memoryDivergesFromDisk = true
            BackendLogger.notice("Enqueue not durable • store halted • \(reconcileState.diagnostic) • intent retained in memory only")
        }
        // P6-I-02. UNKNOWN PROVENANCE IS QUARANTINED, NEVER DISPATCHABLE.
        //
        // An earlier revision let a nil or empty owner into `items` and relied on
        // the flush filter to skip it. That is the wrong place: such an item
        // could still merge with, or be cleared alongside, real work. The
        // invariant is enforced HERE and at load, and nothing is lost.
        guard let normalisedOwner = Self.normalisedOwner(payload.ownerUserID) else {
            let held = payload.withOwner(nil)
            if !quarantined.contains(where: { $0.id == held.id }) { quarantined.append(held) }
            let durable = persist()
            BackendLogger.notice("Queue quarantined • unknown provenance • postID=\(payload.id.uuidString)")
            return durable
        }
        let payload = payload.withOwner(normalisedOwner)

        // Match within the SAME OWNER only.
        if let index = items.firstIndex(where: { $0.id == payload.id && $0.ownerUserID == payload.ownerUserID }) {
            // Merge with existing item: prefer new non-nil values, otherwise keep old
            let existing = items[index]

            // isPublic is non-optional, so stub payloads (created via enqueue(postID:)) default to true.
            // We must not let a stub overwrite an explicit saved false.
            let payloadHasMetadata =
                payload.sessionID != nil ||
                payload.sessionTimestamp != nil ||
                payload.title != nil ||
                payload.durationSeconds != nil ||
                payload.activityType != nil ||
                payload.activityDetail != nil ||
                payload.instrumentLabel != nil ||
                payload.mood != nil ||
                payload.effort != nil ||
                payload.notes != nil ||
                payload.areNotesPrivate != false

            // C-61 / P4-U2a-2. LAST INTENT WINS ACROSS OPERATIONS.
            //
            // The merge below was written when every item meant "publish", so
            // its only question was which VISIBILITY to keep. It cannot answer
            // "publish or unshare?", and letting it try would resolve a
            // re-share after a withdrawal -- or a withdrawal after a re-share --
            // by a rule written for a different question entirely.
            //
            // When the operation changes, the NEWER item replaces the older one
            // outright. Only when both items agree on the operation does the
            // original visibility merge still apply.
            if payload.op != existing.op {
                items[index] = payload
                noteNewIntent(payload)
                let durable = persist()
                BackendLogger.notice("Queue intent replaced • postID=\(payload.id.uuidString) • \(existing.op.rawValue)→\(payload.op.rawValue)")
                return durable
            }

            let mergedIsPublic: Bool = {
                if payload.isPublic == false { return false }          // explicit private always wins
                if payloadHasMetadata { return true }                 // explicit metadata payload can set public
                return existing.isPublic                              // stub should not change visibility
            }()

            let merged = PostPublishPayload(
                id: existing.id,
                sessionID: payload.sessionID ?? existing.sessionID,
                sessionTimestamp: payload.sessionTimestamp ?? existing.sessionTimestamp,
                title: payload.title ?? existing.title,
                durationSeconds: payload.durationSeconds ?? existing.durationSeconds,
                activityType: payload.activityType ?? existing.activityType,
                activityDetail: payload.activityDetail ?? existing.activityDetail,
                instrumentLabel: payload.instrumentLabel ?? existing.instrumentLabel,
                mood: payload.mood ?? existing.mood,
                effort: payload.effort ?? existing.effort,
                // `op` is derived from this, so the two can no longer be
                // recombined into a contradiction here either.
                isPublic: mergedIsPublic,
                notes: payload.notes ?? existing.notes,
                areNotesPrivate: (payload.notes != nil ? payload.areNotesPrivate : existing.areNotesPrivate),
                // C-82 — the member's "Share Without It" must survive the merge.
                // A newer consent replaces the older one; an update that says
                // nothing about consent keeps it.
                authorisedOmissions: payload.authorisedOmissions ?? existing.authorisedOmissions,
                ownerUserID: existing.ownerUserID
            )
            items[index] = merged
            noteNewIntent(merged)
            let durable = persist()
            BackendLogger.notice("Queue update • postID=\(payload.id.uuidString) • total=\(items.count)")
            return durable
        } else {
            items.append(payload)
            noteNewIntent(payload)
            let durable = persist()
            BackendLogger.notice("Queue enqueue • postID=\(payload.id.uuidString) • total=\(items.count)")
            return durable
        }
    }

    /// P6-I-02. PRESERVED SIGNATURE, but it can no longer create EXECUTABLE
    /// unowned work: with no owner supplied it captures the current one, and if
    /// there is none it refuses rather than queueing something unattributable.
    /// CONVENIENCE: captures the owner AT THIS CALL. Only safe where the call is
    /// already synchronous with the member's action.
    @discardableResult
    public func enqueue(postID: UUID) -> Bool {
        enqueue(postID: postID, capturedOwner: Self.currentOwner())
    }

    /// EXPLICIT: the owner was captured earlier, by the caller.
    ///
    /// A `nil` here means "captured, and it was unknown" — it must NEVER fall
    /// back to the current identity. An earlier revision wrote
    /// `ownerUserID ?? currentOwner()`, so an explicit nil captured before a
    /// deferred `Task` silently became whoever was signed in when it ran, which
    /// is precisely the defect.
    @discardableResult
    public func enqueue(postID: UUID, capturedOwner: String?) -> Bool {
        guard let owner = Self.normalisedOwner(capturedOwner) else {
            BackendLogger.notice("Enqueue refused • unknown provenance • postID=\(postID.uuidString)")
            return false
        }
        guard items.contains(where: { $0.id == postID && $0.ownerUserID == owner }) == false else { return true }
        let payload = PostPublishPayload(id: postID, sessionID: nil, sessionTimestamp: nil, title: nil,
                                         durationSeconds: nil, activityType: nil, activityDetail: nil,
                                         instrumentLabel: nil, mood: nil, effort: nil,
                                         ownerUserID: owner)
        return enqueue(payload)
    }

    /// P6-I-02. SCOPED TO THE CURRENT OWNER. The signature is unchanged, but an
    /// ownerless request can only safely mean "mine": removing every owner's
    /// item for a post id is exactly the cross-account interference this unit
    /// exists to stop.
    public func dequeue(postID: UUID) {
        let owner = Self.currentOwner()
        items.removeAll { $0.id == postID && $0.ownerUserID == owner }
        revisions.removeValue(forKey: QueueKey(owner: owner, postID: postID))
        persist()
        BackendLogger.notice("Queue dequeue • postID=\(postID.uuidString) • total=\(items.count)")
    }

    /// Clears DISPATCHABLE work only. Quarantined items are a member's
    /// unattributable work and are never removed by a routine clear.
    public func clear() {
        items.removeAll()
        revisions.removeAll()
        persist()
        BackendLogger.notice("Queue cleared")
    }

    /// P6-I-02. An identity change starts a new generation, so a flush already
    /// running can acknowledge nothing once the identity beneath it has changed.
    /// The queue itself is retained: a withdrawal is owed to the member and must
    /// survive signing out and back in.
    func noteIdentityChanged(reason: String) {
        generation += 1
        // THE IN-FLIGHT HANDLE IS DELIBERATELY RETAINED.
        //
        // An earlier revision set `activeFlush = nil` here. That does not stop
        // the request — it only loses the handle, so the next `flushNow()` saw
        // no active flush and started a SECOND one while A's was still
        // suspended. The generation check withholds the acknowledgement; it does
        // nothing about the concurrent request, so C-87's single flight was
        // regressed by the very call meant to protect it.
        //
        // `flushNow()` now drains whatever is running before starting anything,
        // and starts a fresh-generation pass afterwards so the wakeup a joining
        // caller asked for is not lost when the old flush stops early.
        NSLog("[SessionSyncQueue] identity changed • %@ • generation=%d", reason, generation)
        BackendLogger.notice("Queue identity changed • \(reason) • acknowledgements from the previous identity are void; any in-flight request is drained before the next flush")
    }

    /// Flush now. In Backend Preview: prints simulated upload logs and drains on success.
    /// In Local Simulation: logs and keeps items to reflect "waiting to publish".
    ///
    /// C-87. SINGLE FLIGHT. A call that arrives while a flush is running does
    /// not start a second one: it asks the running flush for another pass and
    /// waits for it, so an operation already in flight is never sent twice and
    /// a newer intent is sent only after the older operation has finished.
    public func flushNow() async {
        if isFactoryResetting {
            NSLog("[SessionSyncQueue] flushNow ignored (factory reset in progress)")
            BackendLogger.notice("Flush ignored (factory reset in progress)")
            return
        }
        // Drain whatever is running before starting anything. A flush from a
        // superseded generation stops at its next check WITHOUT honouring
        // `flushAgain`, so the joining caller's wakeup would be lost — hence the
        // loop and the generation comparison rather than a bare `return`.
        while let running = activeFlush {
            let runningGeneration = activeFlushGeneration
            flushAgain = true
            BackendLogger.notice("Flush joined the flush in progress")
            await running.value
            if runningGeneration == generation {
                // Same generation: it honoured the extra pass on our behalf.
                return
            }
            // Superseded: it drained without serving us. Loop, in case another
            // caller started one meanwhile, then start a fresh-generation flush.
        }
        let flushGeneration = generation
        activeFlushGeneration = flushGeneration
        let flushID = UUID()
        // The handle is released INSIDE the task, synchronously after its last
        // pass, so a caller arriving after that point starts a new flush rather
        // than waiting on one that has already decided to stop.
        activeFlush = Task { @MainActor in
            repeat {
                self.flushAgain = false
                await self.flushOnce(generation: flushGeneration)
            } while self.flushAgain && flushGeneration == self.generation && !self.isFactoryResetting
            if self.activeFlushID == flushID {
                self.activeFlush = nil
                self.activeFlushID = nil
            }
        }
        activeFlushID = flushID
        await activeFlush?.value
    }

    private func flushOnce(generation flushGeneration: Int) async {
        let mode = BackendEnvironment.shared.mode
        NSLog("[SessionSyncQueue] flushNow requested • mode=%@ • queued=%d", String(describing: mode), items.count)
        BackendLogger.notice("Flush requested • mode=\(String(describing: mode)) • queued=\(items.count)")

        // P6-I-02. DISPATCH DEPENDS ON A SUCCESSFUL WHOLE-STORE RECONCILIATION.
        guard reconcileState.isOK else {
            NSLog("[SessionSyncQueue] flush refused • store halted • %@", reconcileState.diagnostic)
            BackendLogger.notice("Flush refused • store halted • \(reconcileState.diagnostic)")
            return
        }

        if mode == .backendPreview || mode == .backendConnected {
            // THE DISPATCH BOUNDARY.
            //
            //   owner == current   -> dispatch
            //   owner != current   -> HELD. Retained, retried when its owner returns
            //   owner == nil       -> cannot occur here; unattributable work is
            //                         quarantined by the store and never reaches `items`
            //   no current owner   -> nothing dispatches
            //
            // Held is not an error: it is A's work waiting for A.
            let owner = Self.currentOwner()
            let dispatchable = items.filter { $0.ownerUserID != nil && $0.ownerUserID == owner }
            let held = items.count - dispatchable.count
            if held > 0 {
                BackendLogger.notice("Flush holding \(held) item(s) belonging to another identity")
            }
            let snapshot = dispatchable.map { (payload: $0, revision: revisions[key($0)] ?? 0) }
            for (payload, revision) in snapshot {
                // C-91. A reset since this flush began ends it here: nothing from
                // before the reset is sent, and nothing is acknowledged.
                guard flushGeneration == generation, !isFactoryResetting else {
                    NSLog("[SessionSyncQueue] flush stopped (superseded by factory reset)")
                    BackendLogger.notice("Flush stopped (superseded by factory reset)")
                    return
                }
                // THE HALT IS RE-CHECKED PER ITEM, NOT ONLY AT ENTRY. A write can
                // fail WHILE this flush is awaiting a request — an acknowledgement's
                // own persist is the likeliest one — and the entry guard has long
                // since passed. The remaining items of the snapshot would then be
                // dispatched from a store that is no longer a safe basis for
                // dispatch.
                guard reconcileState.isOK else {
                    NSLog("[SessionSyncQueue] flush stopped • store halted mid-flush • %@", reconcileState.diagnostic)
                    BackendLogger.notice("Flush stopped • store halted mid-flush • \(reconcileState.diagnostic) • \(items.count) item(s) retained")
                    return
                }
                // C-87. Superseded before it was sent: the next pass sends the newer intent.
                guard revisions[key(payload)] == revision else { continue }
                // C-61 / P4-U2a-2. An .unshare converges to REMOVAL and is
                // dequeued only once the row is confirmed absent; anything else
                // stays queued for the next launch/foreground flush. The
                // .publish path below is untouched.
                if payload.op == .unshare {
                    let unshare = await BackendEnvironment.shared.publish.unsharePost(payload.id)
                    switch unshare {
                    case .success:
                        NSLog("[SessionSyncQueue] unshare converged • postID=%@", payload.id.uuidString)
                        BackendLogger.notice("Unshare converged • postID=\(payload.id.uuidString)")
                        self.acknowledge(payload, revision: revision, generation: flushGeneration)
                    case .failure(let error):
                        // DELIBERATELY NO RETRY CAP AND NO BACKOFF. Abandoning
                        // an owed privacy withdrawal after N attempts is the
                        // wrong failure; the item stays until it converges.
                        NSLog("[SessionSyncQueue] unshare pending • postID=%@ • error=%@", payload.id.uuidString, String(describing: error))
                        BackendLogger.notice("Unshare pending • postID=\(payload.id.uuidString) • \(error.localizedDescription)")
                    }
                    continue
                }

                let result = await BackendEnvironment.shared.publish.uploadPost(payload)
                switch result {
                case .success:
                    NSLog("[SessionSyncQueue] upload success • postID=%@", payload.id.uuidString)
                    BackendLogger.notice("Preview upload success • postID=\(payload.id.uuidString)")
                    self.acknowledge(payload, revision: revision, generation: flushGeneration)
                case .failure(let error):
                    NSLog("[SessionSyncQueue] upload failed • postID=%@ • error=%@", payload.id.uuidString, error.localizedDescription)
                    BackendLogger.notice("Preview upload failed • postID=\(payload.id.uuidString) • error=\(error.localizedDescription)")

                    // Treat HTTP 409 (duplicate primary key) as success so the queue doesn't get stuck.
                    let isHTTP409Duplicate: Bool = {
                        // Check common error representations without importing or changing other modules.
                        // 1) URLError/URLResponse wrapped types that expose a code or statusCode in the description.
                        let desc = String(describing: error)
                        if desc.contains(" 409 ") || desc.contains("status code: 409") || desc.contains("HTTP 409") || desc.contains("Code=409") {
                            return true
                        }
                        // 2) Some backends include database constraint names in the message; match common Supabase duplicate key text.
                        if desc.localizedCaseInsensitiveContains("duplicate key") || desc.localizedCaseInsensitiveContains("posts_pkey") {
                            return true
                        }
                        // 3) Also check localizedDescription as a fallback.
                        let localized = error.localizedDescription
                        if localized.contains(" 409 ") || localized.localizedCaseInsensitiveContains("duplicate key") || localized.localizedCaseInsensitiveContains("posts_pkey") || localized.contains("HTTP 409") || localized.contains("status code: 409") || localized.contains("Code=409") {
                            return true
                        }
                        return false
                    }()

                    if isHTTP409Duplicate {
                        NSLog("[SessionSyncQueue] duplicate postID %@ — treating as success", payload.id.uuidString)
                        BackendLogger.notice("Duplicate post • treating as success • postID=\(payload.id.uuidString)")
                        self.acknowledge(payload, revision: revision, generation: flushGeneration)
                    } else {
                        // Preserve semantics: failures remain queued; no retries/timers added here.
                    }
                }
            }
            NSLog("[SessionSyncQueue] flushNow completed • remaining=%d", items.count)
            BackendLogger.notice("Flush completed • remaining=\(items.count)")
        } else {
            NSLog("[SessionSyncQueue] flushNow skipped (local-simulation) • remaining=%d", items.count)
            BackendLogger.notice("Flush skipped (local-simulation) • remaining=\(items.count)")
        }
    }


    /// C-87. Every change to a post's queued intent gets a new revision, and a
    /// flush in progress is asked for another pass so that intent is sent.
    private func noteNewIntent(_ payload: PostPublishPayload) {
        nextRevision += 1
        revisions[key(payload)] = nextRevision
        if activeFlush != nil { flushAgain = true }
    }

    /// C-87 / C-91. Dequeue ONLY the intent that was actually sent, and only
    /// within the generation that sent it. A newer intent, or a reset, withholds
    /// the acknowledgement and the item stays queued.
    private func acknowledge(_ item: PostPublishPayload, revision: Int, generation flushGeneration: Int) {
        let k = key(item)
        // A latched store cannot record the removal, and dispatch should already
        // have stopped. Withholding keeps memory and disk agreeing about what is
        // still owed rather than dropping the item on a promise it cannot keep.
        guard reconcileState.isOK else {
            BackendLogger.notice("Acknowledgement withheld • postID=\(item.id.uuidString) • store halted")
            return
        }
        guard flushGeneration == generation, revisions[k] == revision else {
            BackendLogger.notice("Acknowledgement withheld • postID=\(item.id.uuidString) • superseded by a newer intent or a reset")
            return
        }
        items.removeAll { $0.id == k.postID && $0.ownerUserID == k.owner }
        revisions.removeValue(forKey: k)
        persist()
        BackendLogger.notice("Queue dequeue • postID=\(k.postID.uuidString) • total=\(items.count)")
    }

    // MARK: - Persistence

    
// MARK: - Delete Account v2 (Local Factory Reset)

/// Prevents any further flush attempts and clears queued items in-memory (best-effort).
func stopForFactoryReset() {
    isFactoryResetting = true
    // C-91. A new generation: a flush already running stops at its next check
    // and can acknowledge nothing. It is detached so a flush after re-arming
    // never waits on it.
    generation += 1
    activeFlush = nil
    activeFlushID = nil
    flushAgain = false
    items.removeAll()
    quarantined.removeAll()
    revisions.removeAll()
    persist()
    NSLog("[SessionSyncQueue] stopForFactoryReset applied (items cleared)")
    BackendLogger.notice("stopForFactoryReset applied (items cleared)")
}

/// C-91. RE-ARMS the queue once the reset has finished. It used to stay disabled
/// for the rest of the process, so a member who reset and set Études up again
/// without relaunching could queue publishes that never flushed.
func resumeAfterFactoryReset() {
    isFactoryResetting = false
    NSLog("[SessionSyncQueue] resumeAfterFactoryReset applied (queue re-armed)")
    BackendLogger.notice("resumeAfterFactoryReset applied (queue re-armed)")
}

/// Deletes the on-disk queue file (best-effort). Safe to call multiple times.
func wipeOnDiskForFactoryReset() {
    // P6-I-02. The store owns every file now — current, legacy and the preserved
    // copies — and a factory reset removes all of them. Quarantined work is the
    // member's own and a reset is their explicit instruction to erase it.
    store.wipe()
    NSLog("[SessionSyncQueue] wipeOnDiskForFactoryReset ok")
    BackendLogger.notice("wipeOnDiskForFactoryReset ok")
}

/// P6-I-03 groundwork. **Reports whether the write is durable.** The previous
    /// implementation returned `Void` and swallowed its error, so a withdrawal
    /// the member had made could fail to reach disk while everything above it
    /// carried on as though it had.
    ///
    /// This unit only propagates the result to `enqueue`'s caller; acting on it
    /// in the publish flow is 2c.
    @discardableResult
    private func persist() -> Bool {
        // Once the store has halted, NOTHING writes through the normal path. An
        // earlier revision only logged a failed persist and left `reconcileState`
        // `.ok`, so a later flush still dispatched from memory and a later
        // enqueue overwrote the file the failed write had already damaged.
        guard reconcileState.isOK else { return false }
        envelope.items = items
        envelope.quarantined = quarantined
        guard store.persist(envelope) else {
            // LATCH. The queue on disk is not what is in memory, so the store is
            // no longer a safe basis for dispatch.
            reconcileState = .haltReadbackMismatch
            memoryDivergesFromDisk = true
            NSLog("[SessionSyncQueue] persist FAILED • store latched • dispatch refused")
            BackendLogger.notice("Queue persist FAILED • store latched • dispatch and further writes refused until recovery")
            return false
        }
        memoryDivergesFromDisk = false
        return true
    }

    /// EXPLICIT RECOVERY from a latched write failure.
    ///
    /// Re-runs the whole-store reconciliation and, if it succeeds, re-applies the
    /// intent held in memory — which is NEWER than anything on disk — before
    /// persisting. Nothing calls this automatically: retrying on every enqueue
    /// would hammer a broken store, and the surface that offers it to the member
    /// is out of this unit's scope.
    @discardableResult
    func attemptStoreRecovery() -> SessionSyncQueueReconcile {
        let retainedItems = items
        let retainedQuarantine = quarantined

        let (state, recovered) = store.reconcile()
        reconcileState = state
        guard state.isOK, var recovered else {
            BackendLogger.notice("Queue recovery failed • \(state.diagnostic) • in-memory intent retained")
            return state
        }

        // THE NEWER IN-MEMORY INTENT WINS — AND AN APPEND-WHAT-IS-MISSING UNION
        // DOES NOT ACHIEVE THAT.
        //
        // The earlier revision appended only retained items whose (owner, post)
        // key the file did not already carry, so for the SAME key the file won:
        // a publish persisted before the halt beat the withdrawal the member
        // made after it, which is the exact inversion this unit exists to
        // prevent. It also resurrected work memory had already acknowledged,
        // because an absent key read as "nothing to merge".
        //
        // When memory is authoritative it REPLACES the dispatchable set
        // outright: presence and ABSENCE are both intent. Only when memory never
        // saw the file — halted before this process could load it — is a union
        // correct, and then there are no in-memory removals to honour.
        if memoryIsAuthoritative {
            recovered.items = retainedItems
        } else {
            // MEMORY NEVER SAW THIS FILE, so unrelated work on it is real and is
            // kept — but where both hold the SAME (owner, post) key, memory is
            // still the newer of the two and must OVERRIDE. Appending only what
            // was missing left the older on-disk publish beating the withdrawal
            // the member made after the halt.
            var merged = recovered.items
            for item in retainedItems {
                if let index = merged.firstIndex(where: { $0.id == item.id && $0.ownerUserID == item.ownerUserID }) {
                    merged[index] = item
                } else {
                    merged.append(item)
                }
            }
            recovered.items = merged
        }
        for held in retainedQuarantine where !recovered.quarantined.contains(where: { $0.id == held.id }) {
            recovered.quarantined.append(held)
        }

        // The same invariant load applies: anything adopted from the file whose
        // owner cannot be established is quarantined, not dispatched.
        let (dispatchable, unowned) = partitionByProvenance(recovered.items)
        recovered.items = dispatchable
        for item in unowned where !recovered.quarantined.contains(where: { $0.id == item.id }) {
            recovered.quarantined.append(item)
        }

        envelope = recovered
        items = recovered.items
        quarantined = recovered.quarantined

        // WORK ADOPTED FROM THE FILE HAS NO REVISION, AND WITHOUT ONE IT NEVER
        // SENDS. The flush snapshot defaults a missing revision to 0 while the
        // per-item guard compares `revisions[key] == revision` — nil against 0 —
        // so such an item is skipped on every pass, for ever. Only keys that
        // have no revision get one, so an intent already registered, and any
        // in-flight comparison depending on it, is untouched.
        for item in items where revisions[key(item)] == nil {
            noteNewIntent(item)
        }
        guard store.persist(recovered) else {
            reconcileState = .haltReadbackMismatch
            memoryDivergesFromDisk = true
            return reconcileState
        }
        memoryDivergesFromDisk = false
        memoryIsAuthoritative = true
        BackendLogger.notice("Queue recovered • dispatchable=\(items.count) • quarantined=\(quarantined.count)")
        return .ok
    }

    #if DEBUG
    /// P6-I-01 precedent. TEST-ONLY, hosted test runs only.
    ///
    /// Reproduces the state a process starts in when the store was ALREADY
    /// halted at launch: nothing loaded, and memory therefore NOT a complete
    /// view of the store. It is established in `init` and there is no other
    /// route to it from a test, yet it is the branch where recovery has to merge
    /// rather than replace — so it is the branch most worth executing.
    func unitTestSimulateStartupHalt() {
        guard UnitTestHost.isActive else { return }
        reconcileState = .haltCorruptV2
        items = []
        quarantined = []
        revisions.removeAll()
        memoryIsAuthoritative = false
        memoryDivergesFromDisk = false
    }
    #endif

    /// P6-I-02. DECODING MOVED TO `SessionSyncQueueStore`, which validates the
    /// whole store before anything is dispatchable. The old two-shape decode is
    /// preserved there, for the preserved copies of legacy files.

    /// C-16 — the non-throwing `URL.applicationSupportDirectory` names the same
    /// directory the old `try! url(for:…, create: true)` did, so queued
    /// publishes are found where they were written. A directory that cannot be
    /// created now surfaces as `persist()`'s logged write error instead of a
    /// crash at launch. Internal only so its path can be tested.
    /// The directory both the legacy and the current queue file live in.
    static func storeRoot() -> URL {
        let fm = FileManager.default
        let dir = URL.applicationSupportDirectory.appendingPathComponent("MOTIVO", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The CURRENT queue file. `makeFileURL()` below still names the LEGACY file
    /// and keeps its exact meaning, because existing assertions pin that path.
    static func currentFileURL() -> URL {
        storeRoot().appendingPathComponent("SessionSyncQueue_v2.json")
    }

    static func makeFileURL() -> URL {
        let fm = FileManager.default
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("MOTIVO", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SessionSyncQueue_v1.json")
    }
}
