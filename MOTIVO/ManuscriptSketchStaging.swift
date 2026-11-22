//
//  ManuscriptSketchStaging.swift
//  MOTIVO
//
//  Writing a Timer sketch into the staging store, in order, and releasing
//  its recovery copy only when that is safe.
//
//  The write is asynchronous, and the sketch can be reopened, saved again
//  or binned while it is still pending. Three things must hold whatever the
//  timing (found in review, 2026-11-22):
//
//  1. AN OLDER WRITE NEVER CLEARS NEWER RECOVERY. A reopened sketch writes
//     its recovery copy under the same key. When a save is handed over, the
//     copy as it is then is noted (`recoveryStamp`); after the write, the
//     copy is removed only if it is still exactly that one. Strokes drawn
//     since, or a later save, have changed it, and it stays.
//  2. AN OLDER WRITE NEVER REPLACES A LATER SAVED VERSION. Writes for one
//     sketch run one after another, in the order the saves were made, and
//     one that a later save has overtaken before it began is not made.
//  3. A BINNED SKETCH STAYS BINNED. A write still pending when the sketch
//     is discarded is not made; one already under way is undone when it
//     lands. Its recovery copy is dropped, as the bin always did.
//
//  If a write fails nothing is cleared: the recovery copy goes on
//  protecting the drawing and is offered back the next time a sketch is
//  started.
//
//  The Timer page and the review page both stage through here (the review
//  page through the Timer, `ReviewSketchStaging`).
//

import Foundation
import CryptoKit

/// A short fingerprint of some bytes: equal bytes, equal fingerprint, and
/// different bytes of the same length a different one. For telling two
/// versions of one sketch apart where a length cannot.
enum ContentFingerprint {
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class ManuscriptSketchStaging {

    /// What the queue needs from the staging store and the recovery copies.
    struct Store {
        /// Writes the sketch's PDF as the staged file for `id`, replacing
        /// the one there if there is one.
        var write: @MainActor (_ id: UUID, _ data: Data) async throws -> Void
        /// Removes the staged file for `id`, if there is one.
        var remove: @MainActor (_ id: UUID) -> Void
        /// What identifies the recovery copy under `key` as it is now; nil
        /// if there is none.
        var recoveryStamp: @MainActor (_ key: String) -> String?
        var clearRecovery: @MainActor (_ key: String) -> Void
    }

    static let shared = ManuscriptSketchStaging(store: .live)

    private let store: Store
    /// The number of the latest save (or discard) of each sketch.
    private var latest: [UUID: Int] = [:]
    private var discarded: Set<UUID> = []
    /// The last write queued for each sketch: the next one waits for it.
    private var tails: [UUID: Task<Void, Never>] = [:]
    private var pending: [UUID: Int] = [:]

    init(store: Store) {
        self.store = store
    }

    /// The pad's Save has handed over `data` for the sketch `id`, and its
    /// recovery copy is under `recoveryKey`. `busy` is told when this sketch
    /// starts and stops having writes outstanding.
    func land(id: UUID, data: Data, recoveryKey: String, busy: @escaping (Bool) -> Void = { _ in }) {
        let generation = (latest[id] ?? 0) + 1
        latest[id] = generation
        // The copy this save handed over, before anything else can touch it.
        let handedOver = store.recoveryStamp(recoveryKey)
        let previous = tails[id]

        pending[id, default: 0] += 1
        if pending[id] == 1 { busy(true) }

        let task = Task { @MainActor in
            await previous?.value
            defer {
                pending[id, default: 1] -= 1
                if pending[id] == 0 {
                    pending[id] = nil
                    tails[id] = nil
                    discarded.remove(id)
                    busy(false)
                }
            }

            if discarded.contains(id) {
                store.clearRecovery(recoveryKey)
                return
            }
            // A later save has overtaken this one: that save writes.
            guard latest[id] == generation else { return }

            do {
                try await store.write(id, data)
            } catch {
                // Not staged: the recovery copy goes on protecting it.
                return
            }

            if discarded.contains(id) {
                // Binned while the write was under way.
                store.remove(id)
                store.clearRecovery(recoveryKey)
                return
            }
            // The staged file now holds this save. Its recovery copy goes
            // only if it is still the one this save handed over.
            if store.recoveryStamp(recoveryKey) == handedOver {
                store.clearRecovery(recoveryKey)
            }
        }
        tails[id] = task
    }

    /// The sketch was removed on purpose (its bin, a saved session, a
    /// confirmed discard). Writes outstanding for it must not bring it back.
    func discard(_ id: UUID) {
        guard pending[id] != nil else { return }
        discarded.insert(id)
        latest[id] = (latest[id] ?? 0) + 1
    }

    /// Returns once every write queued so far has finished.
    func settled() async {
        while let task = tails.values.first {
            await task.value
        }
    }
}

extension ManuscriptSketchStaging.Store {

    /// The staging store and the recovery copies on this device.
    static let live = ManuscriptSketchStaging.Store(
        write: { id, data in
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("sketch-" + UUID().uuidString)
                .appendingPathExtension("pdf")
            try data.write(to: tmp, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tmp) }
            // Under ITS id (as C-89 does for a photo), replacing the staged
            // file if there is one.
            if let existing = StagingStore.ref(withId: id), existing.kind == .sketch {
                _ = try await StagingStore.replace(original: existing, with: tmp)
            } else {
                _ = try await StagingStore.saveNew(from: tmp, kind: .sketch, suggestedName: id.uuidString,
                                                   duration: nil, poster: nil, id: id)
            }
        },
        remove: { id in
            if let ref = StagingStore.ref(withId: id), ref.kind == .sketch { StagingStore.remove(ref) }
        },
        recoveryStamp: { ManuscriptSketchRecovery.stamp(key: $0) },
        clearRecovery: { ManuscriptSketchRecovery.clear(key: $0) }
    )
}
