//
//  AvatarBackend.swift
//  MOTIVO
//
//  The Connected profile's avatar as the account publishes it: the stored
//  image (`avatars/users/<uid>/avatar.jpg`) and the directory row's reference
//  to it (`avatar_key`, with the server's `avatar_version`). One small seam so
//  the ORDER of the writes, which is where the races are, can be tested with a
//  backend in memory. The app's implementation is the network.
//

import Foundation
#if canImport(UIKit)
import UIKit

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
    /// No row matched: there is no row, or (for a conditional write) the
    /// reference has been written by someone else since `expected` was read.
    case notMatched
    case failed
}

@MainActor
protocol AvatarBackend: AnyObject {
    func probe(userID: String, withImage: Bool) async -> AvatarBackendProbe?
    /// Stores the image; returns its key, or nil if it was not stored.
    func upload(jpeg: Data, userID: String) async -> String?
    /// True when the stored image is known to be gone.
    func deleteObject(userID: String) async -> Bool
    /// Writes the reference ONLY IF the row's `avatar_version` is still
    /// `expected` ("" = never stamped). One statement on the server: the check
    /// and the write cannot be separated by another device's write.
    func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite
}

/// Publishing a picture: store the image, then point the reference at it.
///
/// THE REFERENCE WRITE IS CONDITIONAL (fourth pass, 2026-11-12). The image has
/// one fixed name, so another device's removal can delete what this device has
/// just stored, in the moment before this device writes the reference; an
/// unconditional write then leaves the directory pointing at nothing. The
/// write is made on the version read BEFORE storing the image. If the server
/// refuses it, the reference has been written since (a removal, or another
/// publication), so whatever was stored may be gone or replaced: read again,
/// store again, write again. A few rounds at most; the caller keeps its
/// pending marker if they are not enough.
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
    static func publish(jpeg: Data, userID: String, backend: AvatarBackend) async -> Outcome {
        for _ in 0..<rounds {
            guard let probe = await backend.probe(userID: userID, withImage: false) else { return .couldNotRead }
            guard probe.rowExists else { return .noRow }
            guard let key = await backend.upload(jpeg: jpeg, userID: userID) else { return .uploadFailed }
            switch await backend.setKey(key, userID: userID, ifVersionIs: OwnAvatarSync.normalized(probe.avatarVersion)) {
            case .written(let version): return .published(key: key, version: version)
            case .notMatched: continue
            case .failed: return .referenceFailed
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

    func upload(jpeg: Data, userID: String) async -> String? {
        guard case .success(let key) = await NetworkManager.shared.uploadAvatarJPEG(data: jpeg, backendUserID: userID) else { return nil }
        return key
    }

    func deleteObject(userID: String) async -> Bool {
        AuthManager.avatarObjectIsAbsent(after: await NetworkManager.shared.deleteAvatarObject(backendUserID: userID))
    }

    func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite {
        switch await AccountDirectoryService.shared.updateSelfAvatarKey(userID: userID, avatarKey: key, ifVersionIs: expected) {
        case .success(let version): return .written(version: version)
        case .failure(let error): return error is AccountDirectoryService.AvatarKeyNoRowMatched ? .notMatched : .failed
        }
    }
}
#endif
