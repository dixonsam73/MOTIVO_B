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
    private var revisions: [UUID: Int] = [:]
    private var nextRevision = 0
    private var generation = 0
    private var activeFlush: Task<Void, Never>?
    private var activeFlushID: UUID?
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

    public struct PostPublishPayload: Codable, Identifiable {
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
          authorisedOmissions: [UUID]? = nil
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
          // DERIVED. See the `op` declaration above.
          self.op = isPublic ? .publish : .unshare
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

          let declared = try c.decodeIfPresent(PostOp.self, forKey: .op)
          op = (isPublic == false) ? .unshare : (declared ?? .publish)
      }
    }

    @Published public private(set) var items: [PostPublishPayload] = []
    private let fileURL: URL

    private init() {
        self.fileURL = SessionSyncQueue.makeFileURL()
        self.items = (try? Self.load(from: fileURL)) ?? []
        for item in items { noteNewIntent(item.id) }
    }

    // MARK: - Public API

    public func enqueue(_ payload: PostPublishPayload) {
        if let index = items.firstIndex(where: { $0.id == payload.id }) {
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
                noteNewIntent(payload.id)
                persist()
                BackendLogger.notice("Queue intent replaced • postID=\(payload.id.uuidString) • \(existing.op.rawValue)→\(payload.op.rawValue)")
                return
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
                authorisedOmissions: payload.authorisedOmissions ?? existing.authorisedOmissions
            )
            items[index] = merged
            noteNewIntent(payload.id)
            persist()
            BackendLogger.notice("Queue update • postID=\(payload.id.uuidString) • total=\(items.count)")
        } else {
            items.append(payload)
            noteNewIntent(payload.id)
            persist()
            BackendLogger.notice("Queue enqueue • postID=\(payload.id.uuidString) • total=\(items.count)")
        }
    }

    public func enqueue(postID: UUID) {
        guard items.contains(where: { $0.id == postID }) == false else { return }
        let payload = PostPublishPayload(id: postID, sessionID: nil, sessionTimestamp: nil, title: nil, durationSeconds: nil, activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil)
        enqueue(payload)
    }

    public func dequeue(postID: UUID) {
        items.removeAll { $0.id == postID }
        revisions.removeValue(forKey: postID)
        persist()
        BackendLogger.notice("Queue dequeue • postID=\(postID.uuidString) • total=\(items.count)")
    }

    public func clear() {
        items.removeAll()
        revisions.removeAll()
        persist()
        BackendLogger.notice("Queue cleared")
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
        if let running = activeFlush {
            flushAgain = true
            BackendLogger.notice("Flush joined the flush in progress")
            await running.value
            return
        }
        let flushGeneration = generation
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

        if mode == .backendPreview || mode == .backendConnected {
            let snapshot = items.map { (payload: $0, revision: revisions[$0.id] ?? 0) }
            for (payload, revision) in snapshot {
                // C-91. A reset since this flush began ends it here: nothing from
                // before the reset is sent, and nothing is acknowledged.
                guard flushGeneration == generation, !isFactoryResetting else {
                    NSLog("[SessionSyncQueue] flush stopped (superseded by factory reset)")
                    BackendLogger.notice("Flush stopped (superseded by factory reset)")
                    return
                }
                // C-87. Superseded before it was sent: the next pass sends the newer intent.
                guard revisions[payload.id] == revision else { continue }
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
                        self.acknowledge(payload.id, revision: revision, generation: flushGeneration)
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
                    self.acknowledge(payload.id, revision: revision, generation: flushGeneration)
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
                        self.acknowledge(payload.id, revision: revision, generation: flushGeneration)
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
    private func noteNewIntent(_ postID: UUID) {
        nextRevision += 1
        revisions[postID] = nextRevision
        if activeFlush != nil { flushAgain = true }
    }

    /// C-87 / C-91. Dequeue ONLY the intent that was actually sent, and only
    /// within the generation that sent it. A newer intent, or a reset, withholds
    /// the acknowledgement and the item stays queued.
    private func acknowledge(_ postID: UUID, revision: Int, generation flushGeneration: Int) {
        guard flushGeneration == generation, revisions[postID] == revision else {
            BackendLogger.notice("Acknowledgement withheld • postID=\(postID.uuidString) • superseded by a newer intent or a reset")
            return
        }
        dequeue(postID: postID)
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
    let url = Self.makeFileURL()
    do {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        NSLog("[SessionSyncQueue] wipeOnDiskForFactoryReset ok")
        BackendLogger.notice("wipeOnDiskForFactoryReset ok")
    } catch {
        NSLog("[SessionSyncQueue] wipeOnDiskForFactoryReset failed • %@", error.localizedDescription)
        BackendLogger.notice("wipeOnDiskForFactoryReset failed • \(error.localizedDescription)")
    }
}

private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            BackendLogger.notice("Queue persist error • \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) throws -> [PostPublishPayload] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        if let new = try? decoder.decode([PostPublishPayload].self, from: data) {
            return new
        }
        if let old = try? decoder.decode([UUID].self, from: data) {
            return old.map { uuid in
                PostPublishPayload(id: uuid, sessionID: nil, sessionTimestamp: nil, title: nil, durationSeconds: nil, activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil, notes: nil, areNotesPrivate: false)
            }
        }
        // If neither format matches, propagate a decoding error
        return try decoder.decode([PostPublishPayload].self, from: data)
    }

    /// C-16 — the non-throwing `URL.applicationSupportDirectory` names the same
    /// directory the old `try! url(for:…, create: true)` did, so queued
    /// publishes are found where they were written. A directory that cannot be
    /// created now surfaces as `persist()`'s logged write error instead of a
    /// crash at launch. Internal only so its path can be tested.
    static func makeFileURL() -> URL {
        let fm = FileManager.default
        let dir = URL.applicationSupportDirectory
            .appendingPathComponent("MOTIVO", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SessionSyncQueue_v1.json")
    }
}
