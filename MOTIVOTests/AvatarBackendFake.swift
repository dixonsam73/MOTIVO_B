//
//  AvatarBackendFake.swift
//  MOTIVOTests
//
//  The Connected profile's avatar in memory: the stored images BY NAME, one
//  reference, and the version the server stamps on every reference write. It
//  behaves as the real services were seen to on the local stack (2026-11-12,
//  supabase/tests/b48/rehearse.sh): a name can be stored once and never
//  overwritten; a conditional write that matches no row changes nothing; a
//  reference outside the member's own folder is refused; a delete of a name
//  that is not there reports it gone. And it lets a test stop one device at a
//  named operation while another acts, lose a response, or deliver a write
//  late, so an interleaving is an ordered script, not a matter of timing.
//

import XCTest
import UIKit
@testable import Etudes

/// A point one task waits at until the test lets it go on.
@MainActor
final class AvatarTestGate {
    private var arrived = false
    private var opened = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called by the task being held: "I am here", then wait.
    func arrive() async {
        arrived = true
        arrivalWaiters.forEach { $0.resume() }; arrivalWaiters = []
        if !opened { await withCheckedContinuation { openWaiters.append($0) } }
    }
    /// Called by the test: wait until the held task is at the gate.
    func waitUntilArrived() async {
        if !arrived { await withCheckedContinuation { arrivalWaiters.append($0) } }
    }
    func open() {
        opened = true
        openWaiters.forEach { $0.resume() }; openWaiters = []
    }
}

@MainActor
final class FakeAvatarBackend: AvatarBackend {
    let userID: String
    var rowExists = true
    /// The reference: `account_directory.avatar_key`.
    private(set) var key: String?
    /// Every stored image, by its name in the bucket.
    private(set) var objects: [String: UIImage] = [:]
    private(set) var versionCount = 0
    var uploadsFail = false
    var deletesFail = false
    /// The next reference write by THIS device is made, and its answer lost.
    var nextSetKeyLosesItsResponse = false
    /// The next reference write by THIS device gets no answer and has NOT been
    /// made yet: it is still on its way, and arrives when the test says so.
    var nextSetKeyIsDelayed = false
    private var delayedWrite: (() -> Void)?
    /// The next upload by THIS device is stored, and its answer lost.
    var nextUploadLosesItsResponse = false
    /// Every operation that reached the backend, in order, each named with the device that made it.
    private(set) var log: [String] = []
    /// Every delete that reached the server, in order: who sent it, and for which name.
    private(set) var deletions: [(device: String, name: String)] = []
    var deleted: [String] { deletions.map(\.name) }
    /// One-shot: runs right after THIS device's next probe has read the backend.
    var afterNextProbe: (() async -> Void)?
    /// One-shot, per device and operation ("this.deleteObject", "other.setKey"...): the next such call waits here first.
    var gates: [String: AvatarTestGate] = [:]

    var legacyName: String { AvatarObjectName.legacy(userID: userID) }
    /// The image the reference names, if it is stored.
    var referenced: UIImage? { key.flatMap { objects[$0] } }
    /// Stored images the reference does not name.
    var unreferenced: [String] { objects.keys.filter { $0 != key }.sorted() }

    var version: String? {
        versionCount == 0 ? nil : String(format: "2026-11-12T10:%02d:%02d.000%03d+00:00", versionCount / 3600, (versionCount / 60) % 60, versionCount % 1000)
    }

    /// `picture`: a photo already published BY AN OLDER BUILD, under the fixed name.
    init(picture: UIImage? = nil, userID: String = "fake") {
        self.userID = userID
        if let picture { objects[legacyName] = picture; key = legacyName; versionCount = 1 }
    }

    func count(_ entry: String) -> Int { log.filter { $0 == entry }.count }
    func entries(by device: String) -> [String] { log.filter { $0.hasPrefix(device + ": ") } }

    private func hold(_ who: String, _ operation: String) async {
        if let gate = gates.removeValue(forKey: "\(who).\(operation)") { await gate.arrive() }
    }

    fileprivate func probe(_ who: String, withImage: Bool) async -> AvatarBackendProbe? {
        log.append("\(who): probe")
        let result = AvatarBackendProbe(rowExists: rowExists, avatarKey: rowExists ? key : nil, avatarVersion: rowExists ? version : nil,
                                        image: (withImage && rowExists) ? referenced : nil)
        if who == "this", let hook = afterNextProbe { afterNextProbe = nil; await hook() }
        return result
    }

    fileprivate func upload(_ who: String, jpeg: Data, key name: String) async -> Bool {
        await hold(who, "upload")
        guard !uploadsFail, let image = UIImage(data: jpeg) else { log.append("\(who): upload FAILED"); return false }
        // The INSERT policy: the old fixed name or a per-upload name, own folder only.
        guard AvatarObjectName.isOwn(name, userID: userID) else { log.append("\(who): upload REFUSED NAME"); return false }
        // Create only: a per-upload name is never overwritten (no UPDATE policy reaches it).
        guard objects[name] == nil else { log.append("\(who): upload DUPLICATE"); return false }
        objects[name] = image
        log.append("\(who): upload")
        if who == "this", nextUploadLosesItsResponse { nextUploadLosesItsResponse = false; return false }
        return true
    }

    fileprivate func deleteObject(_ who: String, key name: String) async -> Bool {
        await hold(who, "deleteObject")
        guard !deletesFail else { log.append("\(who): deleteObject FAILED"); return false }
        guard AvatarObjectName.isOwn(name, userID: userID) else { log.append("\(who): deleteObject REFUSED NAME"); return false }
        objects[name] = nil          // a name that is not there: "not found", which the app reads as gone
        deletions.append((who, name))
        log.append("\(who): deleteObject")
        return true
    }

    private func apply(_ who: String, _ newKey: String?, ifVersionIs expected: String) -> AvatarKeyWrite {
        guard rowExists else { log.append("\(who): setKey NO ROW"); return .notMatched }
        if OwnAvatarSync.normalized(expected) != (version ?? "") {
            log.append("\(who): setKey REFUSED")
            return .notMatched
        }
        // The CHECK (B-48): NULL, or a name in the row's own folder.
        if let newKey, !AvatarObjectName.isOwn(newKey, userID: userID) { log.append("\(who): setKey REFUSED CHECK"); return .failed }
        self.key = newKey
        versionCount += 1
        log.append("\(who): setKey \(newKey == nil ? "nil" : "path")")
        return .written(version: version)
    }

    fileprivate func setKey(_ who: String, _ key: String?, ifVersionIs expected: String) async -> AvatarKeyWrite {
        await hold(who, "setKey")
        if who == "this", nextSetKeyIsDelayed {
            nextSetKeyIsDelayed = false
            delayedWrite = { [weak self] in _ = self?.apply(who, key, ifVersionIs: expected) }
            log.append("\(who): setKey SENT, NO ANSWER")
            return .failed
        }
        let result = apply(who, key, ifVersionIs: expected)
        if who == "this", nextSetKeyLosesItsResponse, case .written = result {
            nextSetKeyLosesItsResponse = false
            log.append("\(who): setKey ANSWER LOST")
            return .failed
        }
        return result
    }

    /// The write that was sent and got no answer reaches the server now.
    func deliverTheDelayedWrite() { delayedWrite?(); delayedWrite = nil }

    // This device.
    func probe(userID: String, withImage: Bool) async -> AvatarBackendProbe? { await probe("this", withImage: withImage) }
    func upload(jpeg: Data, key: String) async -> Bool { await upload("this", jpeg: jpeg, key: key) }
    func deleteObject(key: String) async -> Bool { await deleteObject("this", key: key) }
    func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite { await setKey("this", key, ifVersionIs: expected) }

    /// The same backend as another of the owner's devices sees it, with that
    /// device's own record of its work.
    var otherDevice: AvatarBackend { other }
    private lazy var other = OtherDevice(backend: self)
    private(set) lazy var otherLedger = AvatarWorkLedger(userID: userID, fileURL: nil)

    /// Another device's whole publication, with the app's own algorithm.
    func otherDevicePublishes(_ picture: UIImage) async -> AvatarPublication.Outcome {
        await AvatarPublication.publish(jpeg: picture.jpegData(compressionQuality: 0.9)!, userID: userID, backend: otherDevice, ledger: otherLedger)
    }

    /// AN OLDER BUILD (TestFlight 1912): one fixed name, overwritten in place,
    /// and a reference write with no condition.
    func anOldBuildPublishes(_ picture: UIImage) {
        objects[legacyName] = picture
        key = legacyName
        versionCount += 1
        log.append("old: upload"); log.append("old: setKey path")
    }
    /// An older build removing the photo: it deletes only the fixed name
    /// (C-33's order: the image, then the reference), whatever the reference named.
    func anOldBuildRemoves() {
        objects[legacyName] = nil
        key = nil
        versionCount += 1
        log.append("old: deleteObject"); log.append("old: setKey nil")
    }
    /// Sets the reference directly, as a row written before the server checked it could hold.
    func setReferenceForTesting(_ value: String?) {
        key = value
        versionCount += 1
    }

    @MainActor
    private final class OtherDevice: AvatarBackend {
        let backend: FakeAvatarBackend
        init(backend: FakeAvatarBackend) { self.backend = backend }
        func probe(userID: String, withImage: Bool) async -> AvatarBackendProbe? { await backend.probe("other", withImage: withImage) }
        func upload(jpeg: Data, key: String) async -> Bool { await backend.upload("other", jpeg: jpeg, key: key) }
        func deleteObject(key: String) async -> Bool { await backend.deleteObject("other", key: key) }
        func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite { await backend.setKey("other", key, ifVersionIs: expected) }
    }
}
