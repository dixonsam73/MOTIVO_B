//
//  AvatarBackendFake.swift
//  MOTIVOTests
//
//  The Connected profile's avatar in memory: one stored image, one reference,
//  and the version the server stamps on every reference write. It refuses a
//  conditional write exactly as PostgREST does (no row matches the filter),
//  and it lets a test stop one device at a named operation while another
//  device acts, so an interleaving is an ordered script, not a matter of timing.
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
    static let path = "users/fake/avatar.jpg"
    var rowExists = true
    var key: String?
    var object: UIImage?
    private(set) var versionCount = 0
    var uploadsFail = false
    var deletesFail = false
    /// Every operation that reached the backend, in order, each named with the device that made it.
    private(set) var log: [String] = []
    /// One-shot: runs right after THIS device's next probe has read the backend.
    var afterNextProbe: (() async -> Void)?
    /// One-shot, per device and operation ("this.deleteObject", "other.setKey"...): the next such call waits here first.
    var gates: [String: AvatarTestGate] = [:]

    var version: String? {
        versionCount == 0 ? nil : String(format: "2026-11-12T10:%02d:%02d+00:00", versionCount / 60, versionCount % 60)
    }

    init(picture: UIImage? = nil) {
        if let picture { object = picture; key = Self.path; versionCount = 1 }
    }

    func count(_ entry: String) -> Int { log.filter { $0 == entry }.count }
    func entries(by device: String) -> [String] { log.filter { $0.hasPrefix(device + ": ") } }

    private func hold(_ who: String, _ operation: String) async {
        if let gate = gates.removeValue(forKey: "\(who).\(operation)") { await gate.arrive() }
    }

    fileprivate func probe(_ who: String, withImage: Bool) async -> AvatarBackendProbe? {
        log.append("\(who): probe")
        let result = AvatarBackendProbe(rowExists: rowExists, avatarKey: rowExists ? key : nil, avatarVersion: rowExists ? version : nil,
                                        image: (withImage && rowExists && key != nil) ? object : nil)
        if who == "this", let hook = afterNextProbe { afterNextProbe = nil; await hook() }
        return result
    }

    fileprivate func upload(_ who: String, jpeg: Data) async -> String? {
        await hold(who, "upload")
        guard !uploadsFail, let image = UIImage(data: jpeg) else { log.append("\(who): upload FAILED"); return nil }
        object = image
        log.append("\(who): upload")
        return Self.path
    }

    fileprivate func deleteObject(_ who: String) async -> Bool {
        await hold(who, "deleteObject")
        guard !deletesFail else { log.append("\(who): deleteObject FAILED"); return false }
        object = nil
        log.append("\(who): deleteObject")
        return true
    }

    fileprivate func setKey(_ who: String, _ key: String?, ifVersionIs expected: String) async -> AvatarKeyWrite {
        await hold(who, "setKey")
        guard rowExists else { log.append("\(who): setKey NO ROW"); return .notMatched }
        if OwnAvatarSync.normalized(expected) != (version ?? "") {
            log.append("\(who): setKey REFUSED")
            return .notMatched
        }
        self.key = key
        versionCount += 1
        log.append("\(who): setKey \(key == nil ? "nil" : "path")")
        return .written(version: version)
    }

    // This device.
    func probe(userID: String, withImage: Bool) async -> AvatarBackendProbe? { await probe("this", withImage: withImage) }
    func upload(jpeg: Data, userID: String) async -> String? { await upload("this", jpeg: jpeg) }
    func deleteObject(userID: String) async -> Bool { await deleteObject("this") }
    func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite { await setKey("this", key, ifVersionIs: expected) }

    /// The same backend as another of the owner's devices sees it.
    var otherDevice: AvatarBackend { OtherDevice(backend: self) }

    /// Another device's whole publication, with the app's own algorithm.
    func otherDevicePublishes(_ picture: UIImage) async -> AvatarPublication.Outcome {
        await AvatarPublication.publish(jpeg: picture.jpegData(compressionQuality: 0.9)!, userID: "fake", backend: otherDevice)
    }

    @MainActor
    private final class OtherDevice: AvatarBackend {
        let backend: FakeAvatarBackend
        init(backend: FakeAvatarBackend) { self.backend = backend }
        func probe(userID: String, withImage: Bool) async -> AvatarBackendProbe? { await backend.probe("other", withImage: withImage) }
        func upload(jpeg: Data, userID: String) async -> String? { await backend.upload("other", jpeg: jpeg) }
        func deleteObject(userID: String) async -> Bool { await backend.deleteObject("other") }
        func setKey(_ key: String?, userID: String, ifVersionIs expected: String) async -> AvatarKeyWrite { await backend.setKey("other", key, ifVersionIs: expected) }
    }
}
