//
//  AvatarBackend.swift
//  MOTIVO
//
//  The Connected profile's avatar as the account publishes it: the stored
//  image (`avatars/users/<uid>/avatar-<32 hex>.jpg`, a NAME PER UPLOAD) and the
//  directory row's reference to it (`avatar_key`, with the server's
//  `avatar_version`). One small seam so the ORDER of the writes, which is where
//  the races are, can be tested with a backend in memory. The app's
//  implementation is the network.
//
//  WHY A NAME PER UPLOAD (2026-11-12, with B-48). The image had one fixed name,
//  `users/<uid>/avatar.jpg`. Storage has no conditional delete, so a delete
//  could not say WHICH image it meant, and a delete that arrived late removed a
//  newer photo another device had stored under the same name. Now every upload
//  has its own name, an image is written once and never overwritten, and every
//  delete names the exact image it means. A delayed delete can only delete the
//  old image. The old fixed name stays valid on the server, is read wherever a
//  reference still holds it, and is never written by this build.
//

import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit

/// The names an avatar image can have in the `avatars` bucket. The server's
/// policies and the CHECK on `account_directory.avatar_key` accept exactly
/// these two forms, in the member's own folder (B-48).
enum AvatarObjectName {
    private static func folder(_ userID: String) -> String {
        "users/\(userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())/"
    }
    /// The one fixed name every build before this one wrote.
    static func legacy(userID: String) -> String { folder(userID) + "avatar.jpg" }
    /// A new name, for one upload.
    static func make(userID: String) -> String {
        folder(userID) + "avatar-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + ".jpg"
    }
    static func isPerUpload(_ key: String, userID: String) -> Bool {
        let prefix = folder(userID) + "avatar-"
        guard key.hasPrefix(prefix), key.hasSuffix(".jpg") else { return false }
        let hex = key.dropFirst(prefix.count).dropLast(4)
        return hex.count == 32 && hex.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
    /// An avatar of THIS member: the only names this device ever deletes.
    static func isOwn(_ key: String, userID: String) -> Bool {
        !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (key == legacy(userID: userID) || isPerUpload(key, userID: userID))
    }
}

/// What the backend shows for the owner's avatar: the row, and the picture if
/// one was asked for and exists. `rowExists` false = no directory row yet.
struct AvatarBackendProbe {
    var rowExists: Bool
    var avatarKey: String?
    var avatarVersion: String?
    var image: UIImage?
}

/// The outcome of writing the reference.
enum AvatarKeyWrite: Equatable {
    /// The server returned the row, with the version it stamped.
    case written(version: String?)
    /// The server answered and no row matched: there is no row, or (for a
    /// conditional write) the reference has been written by someone else
    /// since `expected` was read.
    case notMatched
    /// NO ANSWER THAT SETTLES IT. The write may have been made (its response
    /// lost), may still arrive, or may never have left. Nothing may be deleted
    /// on the strength of this.
    case failed
}

@MainActor
protocol AvatarBackend: AnyObject {
    func probe(userID: String, withImage: Bool) async -> AvatarBackendProbe?
    /// Stores the image under exactly `key`, which must not exist yet; true
    /// when the server confirmed it. Never overwrites.
    func upload(jpeg: Data, key: String) async -> Bool
    /// Deletes exactly `key`. True when that image is known to be gone.
    func deleteObject(key: String) async -> Bool
    /// Writes the reference ONLY IF the row's `avatar_version` is still
    /// `expected` ("" = never stamped). One statement on the server: the check
    /// and the write cannot be separated by another device's write.
    func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite
}

/// What this device still owes the member's avatar folder on the server, kept
/// in a file so it survives the app stopping at any point.
///
/// EVERY NAME HAS AT MOST ONE REFERENCE WRITE THAT CONCERNS IT, EVER, and that
/// write is conditional on one `avatar_version`:
///   - for an image THIS DEVICE stored, the write that points the reference AT
///     it (a repeat stores the image again under a new name; a name is never
///     pointed at twice);
///   - for an image the reference HELD (stored by any device), the write of
///     this device that takes the reference AWAY from it.
/// `writeExpected` is that version, recorded BEFORE the write is sent.
///
/// THE ONE RULE FOR DELETING (`resolve`). A name may be deleted only when a
/// read of the row shows a version STRICTLY NEWER than `writeExpected` and a
/// reference that is not that name. Then, whichever happened, the image is
/// finished with: a write that pointed at it can no longer be accepted (the
/// version it was conditional on has passed) or was accepted and has since
/// been displaced; an image the reference held has been displaced, by this
/// device or another. A per-upload name is never pointed at again, so this is
/// permanent. Until a read shows that, the outcome of the write is UNKNOWN
/// (pending, failed, or made with its response lost) and the image is kept.
/// "Strictly newer" also makes an outdated read harmless: it can only show a
/// version that is not newer, so it can only delay a deletion.
///
/// Two exceptions, both the safe way: an image this device began storing and
/// sent NO reference write for (the upload failed, or the app stopped before
/// the write) is abandoned as soon as no publication in this process is still
/// working on it; and no name is ever deleted while the row read for the
/// decision names it.
///
/// Deletion work that failed stays in the file and is tried again at the next
/// publication, removal, or first read of the row after launch.
@MainActor
final class AvatarWorkLedger {
    struct Entry: Codable, Equatable {
        var name: String
        var writeExpected: String?
        /// This device stored it (or began to). False: the reference held it.
        var mine: Bool
        /// SHA-256 of the bytes this device stored, to recognise its own
        /// publication when the write was made and its response lost.
        var digest: String?
        /// The rule has been met: only the deletion is still owed.
        var dead: Bool = false
    }

    let userID: String
    private let fileURL: URL?
    private(set) var entries: [String: Entry] = [:]
    /// Names a publication in THIS process is working on right now. Never
    /// written to the file: after a relaunch nothing is in flight.
    private var inFlight: Set<String> = []

    /// `fileURL` nil = memory only (tests of the algorithm on its own).
    init(userID: String, fileURL: URL?) {
        self.userID = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            for entry in stored where AvatarObjectName.isOwn(entry.name, userID: self.userID) { entries[entry.name] = entry }
        }
    }

    private func save() {
        guard let fileURL else { return }
        let list = entries.values.sorted { $0.name < $1.name }
        if list.isEmpty { try? FileManager.default.removeItem(at: fileURL); return }
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Before the upload request: the name exists in the record first, so an
    /// image stored by a request the app did not live to hear about is known.
    func begin(name: String, digest: String) {
        entries[name] = Entry(name: name, writeExpected: nil, mine: true, digest: digest)
        inFlight.insert(name)
        save()
    }

    /// Before the reference write that points at `name` (nil: the write clears
    /// the reference) and takes it away from `displacing`. Returns the name
    /// newly put on record as "held by the reference", if this call did so.
    @discardableResult
    func willWrite(pointingAt name: String?, displacing: String?, expected: String) -> String? {
        if let name, var entry = entries[name] {
            entry.writeExpected = expected
            entries[name] = entry
        }
        var recorded: String?
        // Only an avatar of this member is ever queued for deletion, whatever
        // the row says (B-48: the reference was unchecked text).
        if let old = displacing?.trimmingCharacters(in: .whitespacesAndNewlines), !old.isEmpty, old != name,
           AvatarObjectName.isOwn(old, userID: userID), entries[old] == nil {
            entries[old] = Entry(name: old, writeExpected: expected, mine: false, digest: nil)
            recorded = old
        }
        save()
        return recorded
    }

    /// THE SERVER ANSWERED AND REFUSED the write (no row matched). That is a
    /// definite outcome, unlike no answer at all:
    ///   - the image this device stored for that write (`name`) can never be
    ///     pointed at now, so only its deletion is owed;
    ///   - the image the reference held was NOT displaced by this write. If
    ///     this very attempt put it on record (`recorded`, from `willWrite`),
    ///     it comes off again: whoever did displace it deletes it. If an
    ///     EARLIER attempt of this device put it there, it stays, because that
    ///     attempt's write may be the one that displaced it.
    func writeWasRefused(pointingAt name: String?, recorded: String?) {
        if let name, entries[name]?.mine == true { entries[name]?.dead = true }
        if let recorded, entries[recorded]?.mine == false, entries[recorded]?.dead == false { entries[recorded] = nil }
        save()
    }

    /// The publication working on `name` has returned, whatever its outcome.
    func end(name: String) { inFlight.remove(name) }

    /// True when the row's reference is an image this device stored with
    /// these bytes: its reference write was made, even if the response never
    /// arrived.
    func isOwnPublication(key: String?, digest: String) -> Bool {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), let entry = entries[key] else { return false }
        return entry.mine && entry.writeExpected != nil && entry.digest == digest
    }

    var owesDeletion: Bool { entries.values.contains { $0.dead } }
    func owesDeletion(of name: String) -> Bool { entries[name]?.dead == true }

    /// Applies the rule to one read of the row. Changes the record only.
    func resolve(rowExists: Bool, key: String?, version: String?) {
        let reference = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for (name, entry) in entries {
            if rowExists, name == reference {
                // The row names it: alive, whatever was thought.
                if entry.mine {
                    // This device's own image stays on record while it is the
                    // photo, so it is cleaned up if a build that deletes
                    // nothing displaces it later.
                    if entry.dead { entries[name]?.dead = false }
                } else if entry.dead || Self.isStrictlyNewer(version, than: entry.writeExpected ?? "") {
                    // An image the reference held and still (or again) names
                    // at a LATER version: this device's write that would have
                    // displaced it can no longer be accepted, so nothing is
                    // owed. At the SAME version that write may still arrive:
                    // the name stays on record.
                    entries[name] = nil
                }
                continue
            }
            if entry.dead { continue }
            guard let expected = entry.writeExpected else {
                if entry.mine, !inFlight.contains(name) { entries[name]?.dead = true }
                continue
            }
            if rowExists, Self.isStrictlyNewer(version, than: expected) { entries[name]?.dead = true }
        }
        save()
    }

    /// One read of the row, then every deletion that read allows. Nothing a
    /// publication in this process is working on is touched.
    func settle(rowExists: Bool, key: String?, version: String?, backend: AvatarBackend) async {
        resolve(rowExists: rowExists, key: key, version: version)
        let reference = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for name in entries.values.filter({ $0.dead }).map(\.name).sorted() {
            guard entries[name]?.dead == true, !inFlight.contains(name), name != reference else { continue }
            if await backend.deleteObject(key: name) {
                entries[name] = nil
                save()
            }
        }
    }

    /// `avatar_version` is the server's clock to the microsecond. Compared as
    /// (whole second, microseconds), exactly; anything unreadable is NOT newer.
    static func isStrictlyNewer(_ version: String?, than expected: String) -> Bool {
        guard let a = stamp(version) else { return false }
        let old = OwnAvatarSync.normalized(expected)
        if old.isEmpty { return true }          // "never stamped": any stamp is newer
        guard let b = stamp(old) else { return false }
        return a.second > b.second || (a.second == b.second && a.micro > b.micro)
    }

    private static func stamp(_ version: String?) -> (second: Date, micro: Int)? {
        let v = OwnAvatarSync.normalized(version)
        guard !v.isEmpty else { return nil }
        var base = v
        var micro = 0
        if let dot = v.firstIndex(of: ".") {
            let after = v[v.index(after: dot)...]
            let digits = after.prefix { $0.isNumber }
            micro = Int(String(digits.prefix(6)).padding(toLength: 6, withPad: "0", startingAt: 0)) ?? 0
            base = String(v[..<dot]) + String(after.dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let second = formatter.date(from: base) else { return nil }
        return (second, micro)
    }
}

/// Publishing a picture: store the image under a new name, point the reference
/// at it, delete the image the reference named before.
///
/// THE REFERENCE WRITE IS CONDITIONAL (fourth pass, 2026-11-12) on the version
/// read BEFORE storing the image. If the server refuses it, the reference has
/// been written since: read again, store again UNDER ANOTHER NEW NAME, write
/// again. A few rounds at most; the caller keeps its pending marker if they
/// are not enough.
///
/// WHAT IS DELETED, AND WHEN (`AvatarWorkLedger`). Two different things:
///   - the exact image the reference named before, once the server has
///     ACCEPTED the write that displaced it. Another device may have stored
///     it; it is deleted by its name, so nothing newer can be hit;
///   - an image THIS device stored and whose reference write can no longer be
///     accepted, or was never sent.
/// An image whose reference write is pending, failed, or was made with its
/// response lost is never deleted: the record keeps it until a read of the
/// row settles which it was. A failed delete stays on record and is retried.
enum AvatarPublication {
    enum Outcome: Equatable {
        case published(key: String, version: String?)
        /// There is no directory row to point at the image yet. Nothing was stored.
        case noRow
        /// The row could not be read. Nothing was stored.
        case couldNotRead
        case uploadFailed
        case referenceFailed
    }

    static let rounds = 3

    @MainActor
    static func publish(jpeg: Data, userID: String, backend: AvatarBackend, ledger: AvatarWorkLedger) async -> Outcome {
        let digest = AvatarWorkLedger.digest(jpeg)
        for _ in 0..<rounds {
            guard let probe = await backend.probe(userID: userID, withImage: false) else { return .couldNotRead }
            guard probe.rowExists else { return .noRow }
            await ledger.settle(rowExists: true, key: probe.avatarKey, version: probe.avatarVersion, backend: backend)
            // An earlier attempt's write for these very bytes was made after
            // all (its response was lost): that IS the publication.
            if ledger.isOwnPublication(key: probe.avatarKey, digest: digest),
               let key = probe.avatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return .published(key: key, version: probe.avatarVersion)
            }
            let name = AvatarObjectName.make(userID: userID)
            ledger.begin(name: name, digest: digest)
            guard await backend.upload(jpeg: jpeg, key: name) else {
                ledger.end(name: name)      // no write was sent for it: abandoned, deleted at the next settle
                return .uploadFailed
            }
            let expected = OwnAvatarSync.normalized(probe.avatarVersion)
            let recorded = ledger.willWrite(pointingAt: name, displacing: probe.avatarKey, expected: expected)
            let write = await backend.setKey(name, userID: userID, ifVersionIs: expected)
            ledger.end(name: name)
            switch write {
            case .written(let version):
                // The server's own answer is the read: the image the reference
                // named before is displaced, and is deleted by its exact name.
                await ledger.settle(rowExists: true, key: name, version: version, backend: backend)
                return .published(key: name, version: version)
            case .notMatched:
                // Refused for certain: `name` is deleted at the next settle
                // (the top of the next round, or the next time this runs).
                ledger.writeWasRefused(pointingAt: name, recorded: recorded)
                continue
            case .failed:
                return .referenceFailed     // unknown outcome: `name` is kept until a read settles it
            }
        }
        return .referenceFailed
    }
}

@MainActor
final class NetworkAvatarBackend: AvatarBackend {
    func probe(userID: String, withImage: Bool) async -> AvatarBackendProbe? {
        guard case .success(let row) = await AccountDirectoryService.shared.fetchSelfRow(userID: userID) else { return nil }
        guard let row else { return AvatarBackendProbe(rowExists: false, avatarKey: nil, avatarVersion: nil, image: nil) }
        let key = row.avatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var image: UIImage?
        if withImage, !key.isEmpty {
            await RemoteAvatarPipeline.invalidateAvatarCaches(avatarKey: key)
            image = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: key, version: row.avatarVersion)
        }
        return AvatarBackendProbe(rowExists: true, avatarKey: row.avatarKey, avatarVersion: row.avatarVersion, image: image)
    }

    func upload(jpeg: Data, key: String) async -> Bool {
        if case .success = await NetworkManager.shared.uploadAvatarJPEG(data: jpeg, objectKey: key) { return true }
        return false
    }

    func deleteObject(key: String) async -> Bool {
        let gone = AuthManager.avatarObjectIsAbsent(after: await NetworkManager.shared.deleteAvatarObject(objectKey: key))
        if gone { await RemoteAvatarPipeline.invalidateAvatarCaches(avatarKey: key) }
        return gone
    }

    func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite {
        switch await AccountDirectoryService.shared.updateSelfAvatarKey(userID: userID, avatarKey: key, ifVersionIs: expected) {
        case .success(let version): return .written(version: version)
        case .failure(let error): return error is AccountDirectoryService.AvatarKeyNoRowMatched ? .notMatched : .failed
        }
    }
}
#endif
