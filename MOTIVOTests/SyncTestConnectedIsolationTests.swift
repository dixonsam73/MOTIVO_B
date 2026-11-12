//
//  SyncTestConnectedIsolationTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  ONE SHARED PROFILE (C-192, policy change of 2026-11-11) WITH a
//  valid-looking Connected identity present (Apple user id, Supabase access
//  token, backend user id, Connected mode, a configured base URL), and with
//  none. Until that date this file showed the opposite rule, "an import
//  publishes nothing"; the two fields disagreed on the device (the location
//  was published, the avatar was not) and Samuel decided for one profile.
//
//  The base URL is a loopback port nothing listens on and a URLProtocol stub
//  records and fails every request to it, so no real Supabase profile can be
//  touched and every publish here is an ATTEMPT. The real `AuthManager` and
//  `ProfileStore` are driven; `ProfileView` is not mounted. What reaches the
//  backend is the device run.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
import UIKit
@testable import Etudes

/// Records every request to the fixture's host and fails it at the transport.
final class StageHConnectedStub: URLProtocol {
    static let host = "127.0.0.1"
    static let port = 9
    static let lock = NSLock()
    nonisolated(unsafe) static var recorded: [URL] = []
    nonisolated(unsafe) static var recordedBodies: [String] = []
    static var requests: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }
    /// "METHOD path body", one per request, for the payload a publish carried.
    static var bodies: [String] { lock.lock(); defer { lock.unlock() }; return recordedBodies }
    static func reset() { lock.lock(); recorded = []; recordedBodies = []; lock.unlock() }

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data.prefix(4_096), as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable, data.count < 4_096 {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host && request.url?.port == port
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let line = "\(request.httpMethod ?? "?") \(request.url!.path) \(Self.body(of: request))"
        Self.lock.lock(); Self.recorded.append(request.url!); Self.recordedBodies.append(line); Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
    }
    override func stopLoading() {}
}

/// A flag two threads may touch in the read-back overlap tests.
private final class OverlapFlags: @unchecked Sendable {
    var importFinishedInsideTheWindow = false
}

@MainActor
final class SyncTestConnectedIsolationTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var importerContext: NSManagedObjectContext!
    private var importer: JournalImporter!
    private let appleID = "stage-h-apple-\(UUID().uuidString.prefix(8))"
    /// A random UUID: a bound request is sent only when the token's subject is
    /// a UUID equal to the backend user. It names nobody; the host is the stub.
    private let backendID = UUID().uuidString.lowercased()
    private var saved: [String: String?] = [:]
    private var savedDefaults: [String: Any?] = [:]
    private let keychainKeys = ["appleUserID", "supabaseAccessToken_v1", "supabaseRefreshToken_v1", "displayName"]
    private let defaultsKeys = ["backendMode_v1", "supabaseUserID_v1", "backendUserID_v1"]
    private var savedBaseURL: URL?
    private var savedLocalLocation: Any?
    private var savedToken: String?

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-h4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil)
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        importerContext = ctx
        importer = JournalImporter(context: ctx, store: store, customOwner: "local:TEST")

        // Snapshot, then arrange the identity.
        for k in keychainKeys { saved[k] = Keychain.get(k) }
        for k in defaultsKeys { savedDefaults[k] = UserDefaults.standard.object(forKey: k) }
        savedBaseURL = BackendConfig.apiBaseURL; savedToken = BackendConfig.apiToken
        let base = URL(string: "http://\(StageHConnectedStub.host):\(StageHConnectedStub.port)")!
        setBackendMode(.backendConnected)
        BackendConfig.apiBaseURL = base
        BackendConfig.apiToken = "stage-h-anon"
        NetworkManager.shared.configure(baseURL: base, authToken: "stage-h-anon")
        Keychain.set(appleID, for: "appleUserID")
        Keychain.set("stage-h.fake.access", for: "supabaseAccessToken_v1")
        Keychain.set("stage-h.fake.refresh", for: "supabaseRefreshToken_v1")
        Keychain.set("Stage H Member", for: "displayName")
        UserDefaults.standard.set(backendID, forKey: "supabaseUserID_v1")
        UserDefaults.standard.set(backendID, forKey: "backendUserID_v1")
        URLProtocol.registerClass(StageHConnectedStub.self)
        StageHConnectedStub.reset()
        AuthManager.unitTestSuppressesPostSessionScheduling = true
        ConnectedWriteWitness.resetForTesting()
        JournalProfileMirror.onChange = nil
        savedLocalLocation = UserDefaults.standard.object(forKey: "profile.__local_etudes_profile__.location")
        UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.location")
        ProfileStore.removeSyncedAvatar(for: appleID)
        ProfileStore.clearPendingLocalAvatarSync()
        removeAvatarWorkFile()
    }

    /// The device's record of avatar storage work is a file per backend user.
    private func removeAvatarWorkFile() {
        if let url = ProfileStore.avatarWorkFileURL(forBackendUser: backendID) { try? FileManager.default.removeItem(at: url) }
    }

    override func tearDownWithError() throws {
        JournalProfileMirror.onChange = nil
        JournalProfileMirror.removalClock = nil
        ProfileStore.removeSyncedAvatar(for: appleID)
        ProfileStore.clearPendingLocalAvatarSync()
        removeAvatarWorkFile()
        if let savedLocalLocation { UserDefaults.standard.set(savedLocalLocation, forKey: "profile.__local_etudes_profile__.location") }
        else { UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.location") }
        UserDefaults.standard.removeObject(forKey: "profile.\(backendID).location")
        UserDefaults.standard.removeObject(forKey: "profile.\(backendID).ownAvatarAppliedVersion_v1")
        URLProtocol.unregisterClass(StageHConnectedStub.self)
        AuthManager.unitTestSuppressesPostSessionScheduling = false
        for k in keychainKeys { if let v = saved[k] ?? nil { Keychain.set(v, for: k) } else { Keychain.delete(k) } }
        for k in defaultsKeys {
            if let v = savedDefaults[k] ?? nil { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) }
        }
        BackendConfig.apiBaseURL = savedBaseURL; BackendConfig.apiToken = savedToken
        NetworkManager.shared.configure(baseURL: savedBaseURL, authToken: savedToken)
        NetworkManager.shared.setBearerToken(nil)
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func pngData(_ shade: CGFloat) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { ctx in
            UIColor(white: shade, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }.pngData()!
    }

    private func serverAvatar(png: Data?, stamp: Date) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.profileAvatar,
                         recordID: CKRecord.ID(recordName: JournalProfileSync.avatarName, zoneID: JournalRecordMapping.zoneID))
        if let png {
            let url = tempDir.appendingPathComponent("server-avatar-\(UUID().uuidString.prefix(6)).png")
            try! png.write(to: url)
            r[JournalRecordMapping.assetKey] = CKAsset(fileURL: url)
            r[JournalRecordMapping.fileHashKey] = JournalAssetHash.hash(of: url)! as CKRecordValue
        } else {
            r[JournalRecordMapping.fileHashKey] = "" as CKRecordValue
        }
        r["userModifiedAt"] = stamp as CKRecordValue
        return r
    }

    private func serverProfile(location: String, stamp: Date) -> CKRecord {
        let profile = CKRecord(recordType: JournalSyncRecordType.profile,
                               recordID: CKRecord.ID(recordName: JournalProfileSync.profileName, zoneID: JournalRecordMapping.zoneID))
        profile["name"] = "Samuel Dixon" as CKRecordValue; profile["location"] = location as CKRecordValue
        profile[JournalRecordMapping.instrumentNameKey] = "" as CKRecordValue
        profile["userModifiedAt"] = stamp as CKRecordValue
        return profile
    }

    private func importProfile(_ record: CKRecord, scope: JournalProfileScope) {
        importerContext.performAndWait {
            _ = JournalProfileSync.applyProfile(record, context: importerContext, scope: scope, store: store, importer: importer) { _ in }
        }
    }

    private func fakeAccessToken(subject: String) -> String {
        func part(_ json: String) -> String {
            Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return part("{\"alg\":\"none\"}") + "." + part("{\"sub\":\"\(subject)\",\"exp\":4102444800}") + ".stage-h"
    }

    private func upserts() -> [String] { StageHConnectedStub.bodies.filter { $0.contains("account_directory") && !$0.hasPrefix("GET") } }
    private func avatarURL() -> URL { ProfileStore.avatarDerivedURL(for: appleID)! }

    /// The device cases of 2026-11-11, as attempts against the stub: an imported
    /// location and an imported avatar are BOTH published, a removal is, a
    /// deliberate edit afterwards is what the next publish carries, and nothing
    /// the publish does is seen by the sync as a new edit (the loop).
    func testWithAnIdentityAnImportedLocationAndAvatarAreBothPublishedOnceAndADeliberateEditSurvives() async throws {
        // A directory write is sent only AS its owner: the token's subject must
        // be the backend user, so this case holds an unsigned token that says so.
        Keychain.set(fakeAccessToken(subject: backendID), for: "supabaseAccessToken_v1")
        let auth = AuthManager(identityService: LocalStubIdentityService())
        XCTAssertTrue(auth.hasConnectedIdentity, "the fixture must look like a signed-in Connected member")
        XCTAssertTrue(auth.isConnected); XCTAssertTrue(auth.hasSupabaseAccessToken); XCTAssertTrue(BackendConfig.isConfigured)
        XCTAssertEqual(auth.backendUserID, backendID)
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        // What the engine would hear from the stores, were the publish to write them.
        var mirrorEvents = 0
        JournalProfileMirror.onChange = { _ in mirrorEvents += 1 }

        // 1. The private sync imports a location and an avatar made on another device.
        let png = pngData(0.5)
        importProfile(serverProfile(location: "Beta", stamp: Date(timeIntervalSince1970: 1_000)), scope: scope)
        let avatarOutcome = JournalProfileSync.applyAvatar(serverAvatar(png: png, stamp: Date(timeIntervalSince1970: 1_000)),
                                                           scope: scope, store: store) { _ in }
        XCTAssertEqual(avatarOutcome.applied, 1)
        XCTAssertEqual(ProfileStore.presentedLocation(for: auth.backendUserID), "Beta")
        XCTAssertEqual(ProfileStore.location(for: nil), "Beta", "both keys, so no older value is left to be published")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload(), "the imported avatar is marked for the Connected profile")
        XCTAssertEqual(mirrorEvents, 0, "an import is not a local edit")
        XCTAssertEqual(ConnectedWriteWitness.total, 0, "the import itself contacts nothing")

        // 2. What the engine calls after the import. Before the identity's first
        //    directory hydration it only asks for that hydration (which publishes
        //    in the order the first row needs); afterwards it publishes itself.
        //    The avatar goes to a backend in memory; the text to the stub.
        let backend = FakeAvatarBackend(userID: backendID)
        auth.avatarBackend = backend
        await auth.publishProfileAppliedBySync()
        XCTAssertEqual(ConnectedWriteWitness.total, 0, "not before the first hydration (scheduling is off in this fixture)")
        XCTAssertTrue(backend.log.isEmpty)
        auth.markDirectoryHydratedForTesting()
        await auth.publishProfileAppliedBySync()
        XCTAssertEqual(backend.count("this: upload"), 1, "the avatar is published")
        XCTAssertTrue(AvatarObjectName.isPerUpload(try XCTUnwrap(backend.key), userID: backendID), "under a name of its own")
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced), try XCTUnwrap(UIImage(data: png))))
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.directoryUpsert), 1, "and so is the text, once")
        XCTAssertTrue(try XCTUnwrap(upserts().last).contains("\"location\":\"Beta\""), "the imported location is what the publish carries")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "published, so nothing is waiting")
        // No loop: the publish wrote nothing the sync scans.
        XCTAssertEqual(try Data(contentsOf: avatarURL()), png, "the identity's file is still the imported bytes, not a re-encode")
        XCTAssertEqual(mirrorEvents, 0, "nothing the publish did is a new edit for the sync to send")
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: backendID), "Beta")

        // 3. A deliberate edit on this device (what the Profile screen commits),
        //    then the background publish that used to put the old value back.
        ProfileStore.commitLocation("Gamma", for: auth.backendUserID)
        XCTAssertEqual(mirrorEvents, 2, "a real edit IS sent by the sync (both keys changed)")
        await auth.publishProfileAppliedBySync()
        XCTAssertTrue(try XCTUnwrap(upserts().last).contains("\"location\":\"Gamma\""), "C-193: the typed value, not the imported one")
        XCTAssertEqual(ProfileStore.presentedLocation(for: auth.backendUserID), "Gamma")
        XCTAssertEqual(backend.count("this: upload"), 1, "the avatar was not published again")

        // 4. A photo change arrives as a removal and then the new image (C-194).
        //    The removal is published; publishing it must not give this device a
        //    newer "removed" clock, or the image that follows would lose to it.
        mirrorEvents = 0
        let removedAt = Date(timeIntervalSince1970: 2_000)
        let removal = JournalProfileSync.applyAvatar(serverAvatar(png: nil, stamp: removedAt), scope: scope, store: store) { _ in }
        XCTAssertEqual(removal.applied, 1)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion())
        // The profile still shows the picture this removal removes (third pass: `AvatarRemovalGuard`).
        await auth.publishProfileAppliedBySync()
        XCTAssertEqual(backend.count("this: deleteObject"), 1, "the removal is published")
        XCTAssertNil(backend.key); XCTAssertTrue(backend.objects.isEmpty, "the image the reference held is deleted, by its name")
        XCTAssertEqual(mirrorEvents, 0, "publishing a removal already applied is not a removal")
        XCTAssertEqual(store.state.avatarRemovedAt, removedAt)
        let next = pngData(0.8)
        let replaced = JournalProfileSync.applyAvatar(serverAvatar(png: next, stamp: Date(timeIntervalSince1970: 2_001)),
                                                      scope: scope, store: store) { _ in }
        XCTAssertEqual(replaced.applied, 1, "the new image is taken")
        XCTAssertTrue(replaced.resend.isEmpty, "and this device does not send its removal back over it")
        XCTAssertEqual(try Data(contentsOf: avatarURL()), next)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload(), "the marker follows the latest state")
        await auth.publishProfileAppliedBySync()
        XCTAssertEqual(backend.count("this: upload"), 2, "the new image is published after the removal")
        XCTAssertNotNil(backend.key); XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced), try XCTUnwrap(UIImage(data: next))))
        XCTAssertEqual(backend.objects.count, 1, "one stored image, the one the reference names")
        XCTAssertEqual(mirrorEvents, 0)
    }

    // MARK: Reading the Connected avatar back (second pass)

    private func photo(_ seed: UInt64) -> UIImage {
        var state = seed
        func next() -> CGFloat { state = state &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((state >> 33) % 1000) / 1000 }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { ctx in
            UIColor(red: next(), green: next(), blue: next(), alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            for _ in 0..<24 {
                UIColor(red: next(), green: next(), blue: next(), alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: next() * 256, y: next() * 256, width: next() * 128, height: next() * 128))
            }
        }
    }

    private func clearReadBackState() {
        for suffix in ["ownAvatarAppliedVersion_v1", "ownAvatarSeenVersion_v1", "ownAvatarSeenAt_v1"] {
            UserDefaults.standard.removeObject(forKey: "profile.\(appleID).\(suffix)")
        }
    }

    /// With sync ON: another of the owner's devices publishing the picture this
    /// device already holds is an echo (nothing written, nothing sent on), and
    /// a real replacement or removal made on a Connected device whose sync is
    /// off is followed once it has stood, and then travels through the sync.
    func testWithSyncOnAnEchoWritesNothingAndARealChangeIsFollowedOnceItHasStood() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        clearReadBackState()
        let held = photo(1)
        let heldPNG = try XCTUnwrap(held.pngData())
        XCTAssertTrue(ProfileStore.writeSyncedAvatar(pngData: heldPNG, for: appleID, modifiedAt: Date(timeIntervalSince1970: 1_000)))
        ProfileStore.clearPendingLocalAvatarSync()            // published earlier; nothing pending
        let v1 = "2026-11-11T19:00:00+00:00", v2 = "2026-11-11T19:05:00+00:00", v3 = "2026-11-11T19:10:00+00:00", v4 = "2026-11-11T19:20:00+00:00"
        ProfileStore.setOwnAvatarAppliedVersion(v1, for: appleID)
        var mirrorEvents = 0
        JournalProfileMirror.onChange = { _ in mirrorEvents += 1 }
        let key = "users/\(backendID)/avatar.jpg"
        // What the other device's publication of the SAME picture looks like when fetched.
        let echo = try XCTUnwrap(UIImage(data: try XCTUnwrap(held.jpegData(compressionQuality: 0.9))))

        // 1. Two Connected devices with sync on: the sibling's publication.
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: v2, syncIsOn: true) { _, _ in echo }
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v2, "recorded as held")
        XCTAssertEqual(try Data(contentsOf: avatarURL()), heldPNG, "the file is untouched: no re-encode")
        XCTAssertEqual(mirrorEvents, 0, "nothing for the sync to send, so nothing for the sibling to publish again")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "and nothing marked for publication")
        // The same version again, and an older row, do nothing at all.
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: v2, syncIsOn: true) { _, _ in XCTFail("no download for a version already held"); return nil }
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v1, syncIsOn: true) { _, _ in nil }
        XCTAssertEqual(try Data(contentsOf: avatarURL()), heldPNG, "a stale 'no avatar' row removes nothing")

        // 2. The sibling's momentary removal (a photo change that reached it as a
        //    removal and then the image): seen, waited on, never applied.
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v3, syncIsOn: true) { _, _ in nil }
        XCTAssertNotNil(ProfileStore.avatarImage(for: appleID), "not removed on first sight")
        XCTAssertEqual(ProfileStore.ownAvatarBackendChangeSeen(for: appleID)?.version, v3)
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v2)
        XCTAssertEqual(mirrorEvents, 0)
        //    ...and then its publication of the image: an echo again.
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: v4, syncIsOn: true) { _, _ in echo }
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v4)
        XCTAssertNil(ProfileStore.ownAvatarBackendChangeSeen(for: appleID), "nothing is waited on any more")
        XCTAssertEqual(try Data(contentsOf: avatarURL()), heldPNG)
        XCTAssertEqual(mirrorEvents, 0, "no unintended removal, no repeated publication")

        // 3. A real replacement from a Connected device whose sync is off.
        let v5 = "2026-11-11T19:30:00+00:00"
        let replacement = photo(2)
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: v5, syncIsOn: true) { _, _ in replacement }
        XCTAssertEqual(try Data(contentsOf: avatarURL()), heldPNG, "waits: a sibling's older upload would look the same for a moment")
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v4)
        // ...still standing after the interval (the first sighting is moved back).
        ProfileStore.setOwnAvatarBackendChangeSeen(.init(version: v5, at: Date().addingTimeInterval(-OwnAvatarSync.settleInterval - 1)), for: appleID)
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: v5, syncIsOn: true) { _, _ in replacement }
        let now = try XCTUnwrap(ProfileStore.avatarImage(for: appleID))
        XCTAssertTrue(OwnAvatarSync.samePicture(now, replacement), "the replacement is this device's avatar")
        XCTAssertFalse(OwnAvatarSync.samePicture(now, held))
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v5)
        XCTAssertGreaterThan(mirrorEvents, 0, "and the sync carries it to the owner's other devices")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "this device does not publish it back")

        // 4. A real removal from that device: waits, then applies and travels.
        mirrorEvents = 0
        let v6 = "2026-11-11T19:40:00+00:00"
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v6, syncIsOn: true) { _, _ in nil }
        XCTAssertNotNil(ProfileStore.avatarImage(for: appleID))
        ProfileStore.setOwnAvatarBackendChangeSeen(.init(version: v6, at: Date().addingTimeInterval(-OwnAvatarSync.settleInterval - 1)), for: appleID)
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v6, syncIsOn: true) { _, _ in nil }
        XCTAssertNil(ProfileStore.avatarImage(for: appleID), "removed here")
        XCTAssertNil(ProfileStore.avatarImage(for: nil))
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v6)
        XCTAssertGreaterThan(mirrorEvents, 0, "and the removal travels through the sync")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())
        // The removal once more (its echo from the sibling that then publishes it): nothing.
        mirrorEvents = 0
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: "2026-11-11T19:41:00+00:00", syncIsOn: true) { _, _ in nil }
        XCTAssertEqual(mirrorEvents, 0)
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), "2026-11-11T19:41:00+00:00")
    }

    /// Unsent edits are kept, a publication during the download is not
    /// overwritten, and with sync off a real change is followed at once.
    func testAnUnsentEditAndAPublicationDuringTheDownloadAreNeverOverwritten() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        clearReadBackState()
        let held = photo(1)
        let heldPNG = try XCTUnwrap(held.pngData())
        let key = "users/\(backendID)/avatar.jpg"
        let v1 = "2026-11-11T19:00:00+00:00", v2 = "2026-11-11T19:05:00+00:00", v3 = "2026-11-11T19:06:00+00:00"
        // An unsent edit: the marker is set (the import or the editor set it).
        XCTAssertTrue(ProfileStore.writeSyncedAvatar(pngData: heldPNG, for: appleID, modifiedAt: Date()))
        ProfileStore.setOwnAvatarAppliedVersion(v1, for: appleID)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload())
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: v2, syncIsOn: false) { _, _ in XCTFail("no download while an edit is unsent"); return nil }
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v2, syncIsOn: false) { _, _ in nil }
        XCTAssertEqual(try Data(contentsOf: avatarURL()), heldPNG, "an unsent edit is kept against a replacement and a removal")
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v1)
        // This device publishes while the download is in flight.
        ProfileStore.clearPendingLocalAvatarSync()
        let appleID = self.appleID
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: v2, syncIsOn: false) { _, _ in
            ProfileStore.noteOwnAvatarPublished(version: v3, for: appleID)
            return self.photo(2)
        }
        XCTAssertEqual(try Data(contentsOf: avatarURL()), heldPNG, "the older picture does not replace what was just published")
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v3)
        // With sync off a real change is followed without a wait.
        await auth.syncOwnAvatarFromBackend(avatarKey: key, avatarVersion: "2026-11-11T19:10:00+00:00", syncIsOn: false) { _, _ in self.photo(3) }
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(ProfileStore.avatarImage(for: appleID)), photo(3)))
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: "2026-11-11T19:11:00+00:00", syncIsOn: false) { _, _ in nil }
        XCTAssertNil(ProfileStore.avatarImage(for: appleID))
    }

    // MARK: Third pass — removals that must not last, and an atomic read-back

    private func journalAvatar(_ png: Data?, stamp: Date, scope: JournalProfileScope, pending: Bool? = nil) -> JournalProfileSync.Outcome {
        JournalProfileSync.applyAvatar(serverAvatar(png: png, stamp: stamp), scope: scope, store: store, localPending: pending) { _ in }
    }

    private func scanProfile(_ scope: JournalProfileScope) -> [String] {
        var names: [String] = []
        importerContext.performAndWait {
            names = JournalProfileSync.scan(context: importerContext, scope: scope, store: store).map(\.recordName)
        }
        return names
    }

    /// ISSUE 1a, as Codex stated it. Another of the owner's devices publishes a
    /// removal the journal carried; this device's journal is behind, so it
    /// still holds the old photo. The replacement was chosen ten minutes ago
    /// but reaches the journal late, after the two-minute wait has run out and
    /// this device has applied the backend removal. Before the fix the applied
    /// removal was clocked "now", newer than the replacement, so this device
    /// kept "no photo" and sent that over the replacement: a lasting deletion.
    func testAReplacementDelayedBeyondTheWaitStillWinsOverABackendRemoval() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        clearReadBackState()
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        JournalProfileMirror.onChange = { [store] event in JournalProfileSync.noteMirrorEvent(event, store: store!) }
        JournalProfileMirror.removalClock = { [store] in store!.state.avatarRemovedAt }
        auth.syncIsOnOverrideForTesting = true
        let oldPNG = try XCTUnwrap(photo(1).pngData()), newPNG = try XCTUnwrap(photo(2).pngData())
        let chosenOld = Date().addingTimeInterval(-3_600), chosenNew = Date().addingTimeInterval(-600)
        XCTAssertEqual(journalAvatar(oldPNG, stamp: chosenOld, scope: scope).applied, 1)      // held through the journal
        ProfileStore.clearPendingLocalAvatarSync()                                             // and published earlier
        let v1 = "2026-11-11T19:00:00+00:00", v2 = "2026-11-11T19:30:00+00:00"
        ProfileStore.setOwnAvatarAppliedVersion(v1, for: appleID)

        // The backend removal, seen and still standing after the wait.
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v2, syncIsOn: true) { _, _ in nil }
        XCTAssertNotNil(ProfileStore.avatarImage(for: appleID), "not on first sight")
        ProfileStore.setOwnAvatarBackendChangeSeen(.init(version: v2, at: Date().addingTimeInterval(-OwnAvatarSync.settleInterval - 1)), for: appleID)
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v2, syncIsOn: true) { _, _ in nil }
        XCTAssertNil(ProfileStore.avatarImage(for: appleID), "applied once it has stood")
        XCTAssertEqual(scanProfile(scope), [JournalProfileSync.avatarName], "and the sync has this device's removal to send")

        // The delayed replacement arrives (the send of our removal is rejected by it).
        let outcome = journalAvatar(newPNG, stamp: chosenNew, scope: scope, pending: true)
        XCTAssertEqual(outcome.applied, 1, "the replacement is taken")
        XCTAssertTrue(outcome.resend.isEmpty, "this device does not send its removal over it")
        XCTAssertEqual(try Data(contentsOf: avatarURL()), newPNG, "the photo is back, byte for byte")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload(), "and it will be published")
        XCTAssertLessThan(try XCTUnwrap(store.state.avatarRemovedAt), chosenNew,
                          "a removal read back from the backend is clocked just after the photo it removed, never 'now'")
    }

    /// The same rule for a replacement read back: it displaces only the photo
    /// this device held, never a newer one the journal brings later.
    func testAPictureReadBackFromTheBackendNeverOutranksANewerJournalPhoto() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        clearReadBackState()
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        JournalProfileMirror.onChange = { [store] event in JournalProfileSync.noteMirrorEvent(event, store: store!) }
        JournalProfileMirror.removalClock = { [store] in store!.state.avatarRemovedAt }
        auth.syncIsOnOverrideForTesting = true
        let heldPNG = try XCTUnwrap(photo(1).pngData()), laterPNG = try XCTUnwrap(photo(3).pngData())
        let chosenHeld = Date().addingTimeInterval(-3_600), chosenLater = Date().addingTimeInterval(-600)
        XCTAssertEqual(journalAvatar(heldPNG, stamp: chosenHeld, scope: scope).applied, 1)
        ProfileStore.clearPendingLocalAvatarSync()
        let v1 = "2026-11-11T19:00:00+00:00", v2 = "2026-11-11T19:30:00+00:00"
        ProfileStore.setOwnAvatarAppliedVersion(v1, for: appleID)
        ProfileStore.setOwnAvatarBackendChangeSeen(.init(version: v2, at: Date().addingTimeInterval(-OwnAvatarSync.settleInterval - 1)), for: appleID)
        await auth.syncOwnAvatarFromBackend(avatarKey: "users/\(backendID)/avatar.jpg", avatarVersion: v2, syncIsOn: true) { _, _ in self.photo(2) }
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(ProfileStore.avatarImage(for: appleID)), photo(2)), "the real replacement is applied")
        let stamp = try XCTUnwrap(JournalAssetHash.stamp(of: avatarURL())).mtime
        XCTAssertGreaterThan(stamp, chosenHeld.timeIntervalSince1970, "it outranks the photo it replaced")
        XCTAssertLessThan(stamp, chosenHeld.timeIntervalSince1970 + 1, "by a hair, not by 'now'")
        XCTAssertEqual(scanProfile(scope), [JournalProfileSync.avatarName])
        let outcome = journalAvatar(laterPNG, stamp: chosenLater, scope: scope, pending: true)
        XCTAssertEqual(outcome.applied, 1); XCTAssertTrue(outcome.resend.isEmpty)
        XCTAssertEqual(try Data(contentsOf: avatarURL()), laterPNG, "a newer journal photo arriving late still wins")
    }

    /// ISSUE 1b. The device that holds the NEW photo has published it. This
    /// device is the other one: it imported the journal's removal of the OLD
    /// photo and has it waiting. Publishing that removal would delete the new
    /// photo from the Connected profile, and the holder would then apply the
    /// removal and send it to every device. A removal is published only when
    /// the Connected profile still shows the picture it removes.
    func testARemovalIsNotPublishedOverAPhotoItDoesNotRemove() async throws {
        Keychain.set(fakeAccessToken(subject: backendID), for: "supabaseAccessToken_v1")
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        clearReadBackState()
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        JournalProfileMirror.onChange = { [store] event in JournalProfileSync.noteMirrorEvent(event, store: store!) }
        JournalProfileMirror.removalClock = { [store] in store!.state.avatarRemovedAt }
        auth.syncIsOnOverrideForTesting = true
        let oldPNG = try XCTUnwrap(photo(1).pngData())
        let chosenOld = Date().addingTimeInterval(-3_600), removed = Date().addingTimeInterval(-1_800), chosenNew = Date().addingTimeInterval(-600)
        XCTAssertEqual(journalAvatar(oldPNG, stamp: chosenOld, scope: scope).applied, 1)
        ProfileStore.clearPendingLocalAvatarSync()
        XCTAssertEqual(journalAvatar(nil, stamp: removed, scope: scope).applied, 1)            // the journal's removal of the old photo
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion())

        // The Connected profile shows a DIFFERENT photo (the holder published the new one).
        let backend = FakeAvatarBackend(picture: photo(2), userID: backendID)
        auth.avatarBackend = backend
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "third-pass")
        XCTAssertEqual(backend.count("this: deleteObject"), 0, "the object is not deleted")
        XCTAssertEqual(backend.entries(by: "this").filter { $0.contains("setKey") }, [], "and the key is not cleared")
        XCTAssertNotNil(backend.key); XCTAssertNotNil(backend.referenced)
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "the removal is withdrawn, not retried")
        // Instead the photo the profile shows comes to this device, clocked just
        // after the removal it undoes, so the journal's own copy of the new
        // photo (chosen later than the removal) still wins when it arrives.
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(ProfileStore.avatarImage(for: appleID)), photo(2)))
        let stamp = try XCTUnwrap(JournalAssetHash.stamp(of: avatarURL())).mtime
        XCTAssertGreaterThan(stamp, removed.timeIntervalSince1970); XCTAssertLessThan(stamp, removed.timeIntervalSince1970 + 1)
        XCTAssertLessThan(stamp, chosenNew.timeIntervalSince1970)

        // The ordinary case is unchanged: the profile still shows the picture
        // this removal removes, so the removal is published.
        XCTAssertEqual(journalAvatar(oldPNG, stamp: Date().addingTimeInterval(-300), scope: scope).applied, 1)
        ProfileStore.clearPendingLocalAvatarSync()
        XCTAssertEqual(journalAvatar(nil, stamp: Date().addingTimeInterval(-200), scope: scope).applied, 1)
        let published = try XCTUnwrap(UIImage(data: try XCTUnwrap(photo(1).jpegData(compressionQuality: 0.9))))
        let same = FakeAvatarBackend(picture: published, userID: backendID)
        auth.avatarBackend = same
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "third-pass")
        XCTAssertEqual(same.count("this: deleteObject"), 1, "the removal of the picture the profile shows is published")
        XCTAssertNil(same.key); XCTAssertTrue(same.objects.isEmpty)
    }

    /// ISSUE 2. The read-back has decided to write; an iCloud import of a newer
    /// photo arrives on the sync's thread at exactly that moment. Before the
    /// fix the check and the write were separate steps, so the import landed
    /// between them and the read-back then overwrote it with the older backend
    /// picture. Under the avatar lock the import waits and is the later write.
    func testAnImportArrivingAsTheReadBackWritesIsNotOverwritten() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState(); ProfileStore.testHookBeforeBackendAvatarWrite = nil }
        clearReadBackState()
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        let heldPNG = try XCTUnwrap(photo(1).pngData()), importedPNG = try XCTUnwrap(photo(3).pngData())
        XCTAssertEqual(journalAvatar(heldPNG, stamp: Date().addingTimeInterval(-3_600), scope: scope).applied, 1)
        ProfileStore.clearPendingLocalAvatarSync()
        let v1 = "2026-11-11T19:00:00+00:00", v2 = "2026-11-11T19:30:00+00:00"
        ProfileStore.setOwnAvatarAppliedVersion(v1, for: appleID)
        ProfileStore.setOwnAvatarBackendChangeSeen(.init(version: v2, at: Date().addingTimeInterval(-OwnAvatarSync.settleInterval - 1)), for: appleID)

        let record = serverAvatar(png: importedPNG, stamp: Date().addingTimeInterval(-60))
        let importDone = DispatchSemaphore(value: 0)
        let flags = OverlapFlags()
        let store = self.store!
        ProfileStore.testHookBeforeBackendAvatarWrite = {
            // The sync's thread imports now. Give it time to finish if nothing stops it.
            DispatchQueue.global().async {
                _ = JournalProfileSync.applyAvatar(record, scope: scope, store: store) { _ in }
                importDone.signal()
            }
            flags.importFinishedInsideTheWindow = importDone.wait(timeout: .now() + 0.4) == .success
            if flags.importFinishedInsideTheWindow { importDone.signal() }
        }
        await auth.syncOwnAvatarFromBackend(avatarKey: "users/\(backendID)/avatar.jpg", avatarVersion: v2, syncIsOn: true) { _, _ in self.photo(2) }
        ProfileStore.testHookBeforeBackendAvatarWrite = nil
        XCTAssertEqual(importDone.wait(timeout: .now() + 5), .success)

        XCTAssertFalse(flags.importFinishedInsideTheWindow, "the import could not land between the read-back's check and its write")
        XCTAssertEqual(try Data(contentsOf: avatarURL()), importedPNG, "the newer import is what the device holds")
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(ProfileStore.avatarDerivedURL(for: nil))), importedPNG)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload(), "and it is marked for publication")
    }

    /// The same window for a removal read back from the backend.
    func testAnImportArrivingAsTheReadBackRemovesIsNotDeleted() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState(); ProfileStore.testHookBeforeBackendAvatarWrite = nil }
        clearReadBackState()
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        let heldPNG = try XCTUnwrap(photo(1).pngData()), importedPNG = try XCTUnwrap(photo(3).pngData())
        XCTAssertEqual(journalAvatar(heldPNG, stamp: Date().addingTimeInterval(-3_600), scope: scope).applied, 1)
        ProfileStore.clearPendingLocalAvatarSync()
        let v1 = "2026-11-11T19:00:00+00:00", v2 = "2026-11-11T19:30:00+00:00"
        ProfileStore.setOwnAvatarAppliedVersion(v1, for: appleID)
        ProfileStore.setOwnAvatarBackendChangeSeen(.init(version: v2, at: Date().addingTimeInterval(-OwnAvatarSync.settleInterval - 1)), for: appleID)
        let record = serverAvatar(png: importedPNG, stamp: Date().addingTimeInterval(-60))
        let importDone = DispatchSemaphore(value: 0)
        let flags = OverlapFlags()
        let store = self.store!
        ProfileStore.testHookBeforeBackendAvatarWrite = {
            DispatchQueue.global().async {
                _ = JournalProfileSync.applyAvatar(record, scope: scope, store: store) { _ in }
                importDone.signal()
            }
            flags.importFinishedInsideTheWindow = importDone.wait(timeout: .now() + 0.4) == .success
            if flags.importFinishedInsideTheWindow { importDone.signal() }
        }
        await auth.syncOwnAvatarFromBackend(avatarKey: nil, avatarVersion: v2, syncIsOn: true) { _, _ in nil }
        ProfileStore.testHookBeforeBackendAvatarWrite = nil
        XCTAssertEqual(importDone.wait(timeout: .now() + 5), .success)
        XCTAssertFalse(flags.importFinishedInsideTheWindow)
        XCTAssertEqual(try Data(contentsOf: avatarURL()), importedPNG, "the newer import survives the removal that was already under way")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload())
    }

    /// And the plain order, with no overlap: an import that lands while the
    /// backend picture is still downloading makes the read-back stand down.
    func testAnImportDuringTheDownloadMakesTheReadBackStandDown() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        clearReadBackState()
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        let heldPNG = try XCTUnwrap(photo(1).pngData()), importedPNG = try XCTUnwrap(photo(3).pngData())
        XCTAssertEqual(journalAvatar(heldPNG, stamp: Date().addingTimeInterval(-3_600), scope: scope).applied, 1)
        ProfileStore.clearPendingLocalAvatarSync()
        let v1 = "2026-11-11T19:00:00+00:00", v2 = "2026-11-11T19:30:00+00:00"
        ProfileStore.setOwnAvatarAppliedVersion(v1, for: appleID)
        ProfileStore.setOwnAvatarBackendChangeSeen(.init(version: v2, at: Date().addingTimeInterval(-OwnAvatarSync.settleInterval - 1)), for: appleID)
        await auth.syncOwnAvatarFromBackend(avatarKey: "users/\(backendID)/avatar.jpg", avatarVersion: v2, syncIsOn: true) { _, _ in
            _ = self.journalAvatar(importedPNG, stamp: Date().addingTimeInterval(-60), scope: scope)
            // Even with the marker gone again (published meanwhile), the avatar has changed since the read-back began.
            ProfileStore.clearPendingLocalAvatarSync()
            return self.photo(2)
        }
        XCTAssertEqual(try Data(contentsOf: avatarURL()), importedPNG, "the read-back did not write over what arrived meanwhile")
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), v1, "and recorded nothing about a state it did not apply")
    }

    // MARK: Fourth pass — an outdated removal against a newer publication

    /// This device held photo 1 through the journal and published it; the
    /// journal's removal of photo 1 is waiting to be published.
    private func arrangeAWaitingRemovalOfPhotoOne(_ auth: AuthManager) throws {
        clearReadBackState()
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        JournalProfileMirror.onChange = { [store] event in JournalProfileSync.noteMirrorEvent(event, store: store!) }
        JournalProfileMirror.removalClock = { [store] in store!.state.avatarRemovedAt }
        auth.syncIsOnOverrideForTesting = true
        XCTAssertEqual(journalAvatar(try XCTUnwrap(photo(1).pngData()), stamp: Date().addingTimeInterval(-3_600), scope: scope).applied, 1)
        ProfileStore.clearPendingLocalAvatarSync()
        XCTAssertEqual(journalAvatar(nil, stamp: Date().addingTimeInterval(-1_800), scope: scope).applied, 1)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion())
    }

    private func asPublished(_ picture: UIImage) throws -> UIImage {
        try XCTUnwrap(UIImage(data: try XCTUnwrap(picture.jpegData(compressionQuality: 0.9))))
    }

    /// THE RACE Codex named. This device checks: the profile still shows photo 1,
    /// the picture its waiting removal removes. Then, before it deletes
    /// anything, another of the owner's devices publishes photo 2 (the image
    /// and the reference). Before the fourth pass the removal went on: it
    /// deleted the stored image, which was now photo 2, and cleared the
    /// reference to it. (Photo 1 here was published by an older build, under
    /// the fixed name; the other device runs this build.)
    func testAPhotoPublishedBetweenTheRemovalCheckAndTheDeletionIsNotErased() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        try arrangeAWaitingRemovalOfPhotoOne(auth)
        let backend = FakeAvatarBackend(picture: try asPublished(photo(1)), userID: backendID)
        auth.avatarBackend = backend
        backend.afterNextProbe = { _ = await backend.otherDevicePublishes(self.photo(2)) }     // after the check, before the deletion

        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "fourth-pass")

        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced, "the stored image was erased"), photo(2)), "the newer photo is still stored")
        XCTAssertTrue(AvatarObjectName.isPerUpload(try XCTUnwrap(backend.key), userID: backendID), "and the directory still refers to it")
        XCTAssertEqual(backend.count("this: deleteObject"), 0, "the outdated removal deleted nothing")
        XCTAssertEqual(backend.deleted, [backend.legacyName], "the publishing device deleted the image it displaced, and only that")
        XCTAssertEqual(backend.count("this: setKey nil"), 0, "and cleared nothing")
        XCTAssertEqual(backend.count("this: setKey REFUSED"), 1, "the server refused its write: the reference had been written since the check")
        // The removal is not about the photo the profile now shows: it is withdrawn, and that photo comes here.
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(ProfileStore.avatarImage(for: appleID)), photo(2)))
    }

    /// The same race caught half way: the other device's IMAGE has been stored
    /// after this device's check, its REFERENCE write has not landed yet. This
    /// device cannot tell (the reference is unchanged), so its removal goes
    /// through: it clears the reference and deletes the image the reference
    /// HELD, by its name. The other device's image has its own name and is not
    /// touched. Its reference write is then refused, because the row has been
    /// written since it read it; it stores its image again under another name,
    /// publishes that, and deletes the one it could not publish.
    func testAnImageStoredAfterTheCheckWhoseReferenceHasNotLandedIsStoredAgain() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        try arrangeAWaitingRemovalOfPhotoOne(auth)
        let backend = FakeAvatarBackend(picture: try asPublished(photo(1)), userID: backendID)
        auth.avatarBackend = backend
        let held = AvatarTestGate()
        backend.gates["other.setKey"] = held
        var other: Task<AvatarPublication.Outcome, Never>?
        backend.afterNextProbe = {
            other = Task { @MainActor in await backend.otherDevicePublishes(self.photo(2)) }
            await held.waitUntilArrived()                     // its image is stored; its reference write is held
        }

        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "fourth-pass")
        held.open()
        let outcome = await try XCTUnwrap(other).value

        guard case .published = outcome else { return XCTFail("the other device did not finish publishing: \(outcome)") }
        XCTAssertEqual(backend.count("other: setKey REFUSED"), 1, "its reference write was refused: a removal had been written since it read the row")
        XCTAssertEqual(backend.count("other: upload"), 2, "so it stored its image again")
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced, "the directory points at an image that does not exist"), photo(2)))
        XCTAssertEqual(backend.entries(by: "this").filter { $0.contains("deleteObject") }, ["this: deleteObject"])
        XCTAssertEqual(backend.deleted.first, backend.legacyName, "this device deleted exactly the image its removal displaced")
        XCTAssertEqual(backend.objects.count, 1, "and the other device deleted the image it could not publish: one image is stored, the one referenced")
    }

    /// The other branch of a removal: the reference is already clear when this
    /// device looks. Nothing on the server is this removal's to delete (it
    /// displaced nothing), so it deletes nothing, and a photo another device
    /// publishes at that moment is untouched. With one fixed name this branch
    /// deleted "the leftover image", which by then was the new photo.
    func testARemovalThatFindsTheReferenceClearDeletesNothingOnTheServer() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        try arrangeAWaitingRemovalOfPhotoOne(auth)
        let backend = FakeAvatarBackend(picture: try asPublished(photo(1)), userID: backendID)
        _ = await backend.otherDevice.setKey(nil, userID: backendID, ifVersionIs: backend.version ?? "")   // reference cleared earlier; the image was left
        XCTAssertNil(backend.key); XCTAssertEqual(backend.unreferenced, [backend.legacyName])
        auth.avatarBackend = backend
        backend.afterNextProbe = { _ = await backend.otherDevicePublishes(self.photo(2)) }

        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "fourth-pass")

        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced, "the stored image was erased"), photo(2)))
        XCTAssertEqual(backend.count("this: deleteObject"), 0)
        XCTAssertEqual(backend.entries(by: "this").filter { $0.contains("setKey") }, [], "and writes no reference")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "the removal is done: the profile showed no photo when it looked")
    }

    /// With no race the removal still goes through, in the new order: the
    /// reference first (conditionally), then the image. If the image cannot be
    /// deleted the removal keeps waiting and finishes at the next attempt.
    func testARemovalClearsTheReferenceThenTheImageAndFinishesAnInterruptedDelete() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        try arrangeAWaitingRemovalOfPhotoOne(auth)
        let backend = FakeAvatarBackend(picture: try asPublished(photo(1)), userID: backendID)
        auth.avatarBackend = backend
        backend.deletesFail = true
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "fourth-pass")
        XCTAssertEqual(backend.entries(by: "this").suffix(2), ["this: setKey nil", "this: deleteObject FAILED"], "the reference, then the image")
        XCTAssertNil(backend.key); XCTAssertEqual(backend.unreferenced, [backend.legacyName])
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion(), "the image is still there, so the removal is still waiting")
        XCTAssertTrue(auth.avatarLedger(for: backendID).owesDeletion(of: backend.legacyName), "and the failed delete is on record, by name")
        backend.deletesFail = false
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "fourth-pass, again")
        XCTAssertTrue(backend.objects.isEmpty, "the leftover image is deleted at the next attempt")
        XCTAssertEqual(backend.entries(by: "this").filter { $0.contains("setKey") }, ["this: setKey nil"], "with no second reference write")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())
        XCTAssertEqual(ProfileStore.ownAvatarAppliedVersion(for: appleID), backend.version, "and the standing version is recorded")
    }

    /// A backend whose profile shows photo 1, published with this build's
    /// algorithm (a per-upload name) by a device that takes no further part:
    /// nobody but the device under test will clear that image up.
    private func backendShowingPhotoOnePublishedByThisBuild() async throws -> (FakeAvatarBackend, String) {
        let backend = FakeAvatarBackend(userID: backendID)
        let jpeg = try XCTUnwrap(photo(1).jpegData(compressionQuality: 0.9))
        let outcome = await AvatarPublication.publish(jpeg: jpeg, userID: backendID, backend: backend.otherDevice,
                                                      ledger: AvatarWorkLedger(userID: backendID, fileURL: nil))
        guard case .published(let key, _) = outcome else { throw XCTSkip("fixture: \(outcome)") }
        return (backend, key)
    }

    /// THE RACE THIS CHANGE CLOSES (2026-11-12), the one the fourth pass could
    /// not: the removal's reference write is accepted, and its ONE delete
    /// request is then outstanding for longer than another device's whole
    /// publication, refused write and repeat included. With one fixed name the
    /// delete, when it arrived, removed the new photo. Now it names the image
    /// the removal displaced, and can remove nothing else.
    func testARemovalsDeleteThatArrivesAfterAnotherDevicesWholePublicationDeletesOnlyTheOldImage() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        try arrangeAWaitingRemovalOfPhotoOne(auth)
        let (backend, first) = try await backendShowingPhotoOnePublishedByThisBuild()
        auth.avatarBackend = backend
        // The other device starts publishing photo 2 after this device's check:
        // it reads the row, stores its image, and is held before its reference write.
        let otherHeld = AvatarTestGate()
        backend.gates["other.setKey"] = otherHeld
        var other: Task<AvatarPublication.Outcome, Never>?
        backend.afterNextProbe = {
            other = Task { @MainActor in await backend.otherDevicePublishes(self.photo(2)) }
            await otherHeld.waitUntilArrived()
        }
        // This device's delete of photo 1's image is held in flight.
        let deleteHeld = AvatarTestGate()
        backend.gates["this.deleteObject"] = deleteHeld
        let removal = Task { @MainActor in await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "delayed delete") }
        await deleteHeld.waitUntilArrived()
        XCTAssertEqual(backend.count("this: setKey nil"), 1, "the removal's reference write was accepted")
        XCTAssertNil(backend.key)
        // The other device: refused (a removal has been written since it read), then its whole publication again.
        otherHeld.open()
        let outcome = await try XCTUnwrap(other).value
        guard case .published(let second, _) = outcome else { return XCTFail("the other device did not publish: \(outcome)") }
        XCTAssertEqual(backend.count("other: setKey REFUSED"), 1); XCTAssertEqual(backend.count("other: upload"), 3, "photo 1, then photo 2 twice")
        XCTAssertEqual(backend.key, second)
        XCTAssertNotNil(backend.objects[first], "this device's delete has still not arrived")

        deleteHeld.open()                                           // it arrives now
        await removal.value

        XCTAssertEqual(backend.key, second, "the reference to the new photo is untouched")
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced, "the newer photo was erased"), photo(2)))
        XCTAssertEqual(Array(backend.objects.keys), [second], "one image is stored: the late delete took photo 1's and nothing else")
        XCTAssertEqual(backend.deletions.filter { $0.device == "this" }.map(\.name), [first], "this device deleted exactly the name its removal displaced")
        XCTAssertFalse(backend.deletions.contains { $0.name == second }, "nobody deleted the newer photo")
    }

    /// The removal's reference write is MADE and its answer LOST. This device
    /// does not know the outcome, so it deletes nothing and keeps waiting. At
    /// the next attempt a read of the row shows the reference cleared at a
    /// later version: the image it held is deleted, by the name on record.
    func testARemovalWhoseReferenceWriteWasMadeWithItsAnswerLostDeletesTheImageOnlyOnceAReadShowsIt() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        try arrangeAWaitingRemovalOfPhotoOne(auth)
        let (backend, first) = try await backendShowingPhotoOnePublishedByThisBuild()
        auth.avatarBackend = backend
        backend.nextSetKeyLosesItsResponse = true
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "answer lost")
        XCTAssertNil(backend.key, "the server did clear the reference")
        XCTAssertNotNil(backend.objects[first], "but on an unknown outcome nothing is deleted")
        XCTAssertTrue(backend.deletions.isEmpty)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion(), "and the removal keeps waiting")
        // A relaunch in between: the name is in the file, not in memory.
        let relaunched = AuthManager(identityService: LocalStubIdentityService())
        relaunched.syncIsOnOverrideForTesting = true
        relaunched.avatarBackend = backend
        await relaunched.syncPendingLocalAvatarToConnectedIfNeeded(reason: "next attempt")
        XCTAssertTrue(backend.objects.isEmpty, "the image is deleted once a read shows it displaced")
        XCTAssertEqual(backend.deletions.map(\.name), [first])
        XCTAssertEqual(backend.entries(by: "this").filter { $0.contains("setKey") }, ["this: setKey nil", "this: setKey ANSWER LOST"], "with no second reference write")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())
    }

    /// The removal's reference write is SENT, UNANSWERED AND NOT YET MADE.
    /// Another device publishes a new photo meanwhile. The late write then
    /// arrives and the server refuses it. Nothing of the new photo is touched,
    /// before or after; this device withdraws the removal and takes the photo.
    func testARemovalWhoseReferenceWriteArrivesAfterANewerPublicationIsRefusedAndTouchesNothing() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        try arrangeAWaitingRemovalOfPhotoOne(auth)
        let (backend, first) = try await backendShowingPhotoOnePublishedByThisBuild()
        auth.avatarBackend = backend
        backend.nextSetKeyIsDelayed = true
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "no answer")
        XCTAssertEqual(backend.key, first, "the write has not reached the server")
        XCTAssertTrue(backend.deletions.isEmpty, "nothing is deleted on an unknown outcome")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion())
        guard case .published(let second, _) = await backend.otherDevicePublishes(photo(2)) else { return XCTFail() }
        backend.deliverTheDelayedWrite()                            // the removal's write arrives late
        XCTAssertEqual(backend.count("this: setKey REFUSED"), 1, "the server refuses it: the reference has been written since")
        XCTAssertEqual(backend.key, second)
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "next attempt")
        XCTAssertEqual(backend.key, second)
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced), photo(2)))
        XCTAssertEqual(Array(backend.objects.keys), [second])
        XCTAssertFalse(backend.deletions.contains { $0.name == second })
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "the removal is withdrawn: the profile shows a photo it is not about")
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(ProfileStore.avatarImage(for: appleID)), photo(2)))
    }

    /// A delete this device could not make is on record in a file. After a
    /// relaunch, the first read of the owner's row makes it: only as that
    /// owner, and never for the image the row names.
    func testTheFirstReadOfTheRowAfterARelaunchMakesADeleteAnEarlierRunCouldNot() async throws {
        Keychain.set(fakeAccessToken(subject: backendID), for: "supabaseAccessToken_v1")
        let first = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        let backend = FakeAvatarBackend(picture: photo(1), userID: backendID)
        first.avatarBackend = backend
        backend.deletesFail = true
        let jpeg = try XCTUnwrap(photo(2).jpegData(compressionQuality: 0.9))
        let outcome = await AvatarPublication.publish(jpeg: jpeg, userID: backendID, backend: backend, ledger: first.avatarLedger(for: backendID))
        guard case .published(let key, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(backend.unreferenced, [backend.legacyName], "the displaced image could not be deleted")
        backend.deletesFail = false

        let relaunched = AuthManager(identityService: LocalStubIdentityService())      // a new process: the record is read from the file
        relaunched.avatarBackend = backend
        XCTAssertTrue(relaunched.avatarLedger(for: backendID).owesDeletion(of: backend.legacyName))
        await relaunched.settleAvatarWork(owner: UUID().uuidString.lowercased(), key: backend.key, version: backend.version)
        XCTAssertEqual(backend.unreferenced, [backend.legacyName], "not as anybody else")
        await relaunched.settleAvatarWork(owner: backendID, key: backend.key, version: backend.version)
        XCTAssertEqual(Array(backend.objects.keys), [key], "the owed delete is made; the photo the row names stays")
        XCTAssertFalse(relaunched.avatarLedger(for: backendID).owesDeletion)
        // And the directory hydration is where the app does it.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("MOTIVO/AuthManager.swift"), encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: "self.settleAvatarWork(owner: userID, key: row.avatarKey, version: row.avatarVersion)").count - 1, 1)
    }

    /// The network adapter sends the condition PostgREST needs, in a form that
    /// survives the URL (a "+" in a query is read as a space).
    func testTheConditionalReferenceWriteIsSentAsAFilterOnTheVersion() async throws {
        XCTAssertEqual(AccountDirectoryService.avatarVersionFilter(ifVersionIs: "2026-11-12T11:55:05.496451+00:00"),
                       URLQueryItem(name: "avatar_version", value: "eq.2026-11-12T11:55:05.496451Z"))
        XCTAssertEqual(AccountDirectoryService.avatarVersionFilter(ifVersionIs: ""), URLQueryItem(name: "avatar_version", value: "is.null"))
        XCTAssertEqual(AccountDirectoryService.avatarVersionFilter(ifVersionIs: "  "), URLQueryItem(name: "avatar_version", value: "is.null"))
        XCTAssertNil(AccountDirectoryService.avatarVersionFilter(ifVersionIs: "2026-11-12T12:55:05+01:00"), "an offset that cannot be written safely: the write is not attempted")
        Keychain.set(fakeAccessToken(subject: backendID), for: "supabaseAccessToken_v1")
        _ = AuthManager(identityService: LocalStubIdentityService())
        let outcome = await NetworkAvatarBackend().setKey(nil, userID: backendID, ifVersionIs: "2026-11-12T11:55:05.496451+00:00")
        XCTAssertEqual(outcome, .failed, "the stub fails the request")
        let sent = try XCTUnwrap(StageHConnectedStub.requests.last { $0.path.contains("account_directory") })
        let query = try XCTUnwrap(sent.query)
        XCTAssertTrue(query.contains("avatar_version=eq.2026-11-12T11:55:05.496451Z"), query)
        XCTAssertTrue(query.contains("user_id=eq.\(backendID)"), query)
        XCTAssertFalse(query.contains("+"), "no plus sign reaches the server")
    }

    /// Device A, 2026-11-11 21:13, build 1920: at a fresh join the waiting photo
    /// was uploaded before any directory row existed, the row was then created
    /// by a writer that did not promote it, and it stayed unattached. Now any
    /// evidenced write to the owner's row attaches it.
    func testAWaitingPhotoIsPromotedWhenTheOwnersRowIsEvidenced() async throws {
        Keychain.set(fakeAccessToken(subject: backendID), for: "supabaseAccessToken_v1")
        let auth = AuthManager(identityService: LocalStubIdentityService())
        defer { clearReadBackState() }
        XCTAssertTrue(ProfileStore.writeSyncedAvatar(pngData: try XCTUnwrap(photo(1).pngData()), for: appleID, modifiedAt: Date()))
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload())
        let backend = FakeAvatarBackend(userID: backendID)
        backend.rowExists = false
        auth.avatarBackend = backend
        // No row yet: nothing is stored and the photo keeps waiting.
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "before the row")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload())
        XCTAssertNil(backend.key)
        // Somebody else's row, or no row named: nothing.
        backend.rowExists = true
        let before = backend.log.count
        await auth.directoryRowWasEvidenced(owner: UUID().uuidString.lowercased())
        await auth.directoryRowWasEvidenced(owner: nil)
        XCTAssertEqual(backend.log.count, before)
        // This owner's row: the photo is published and attached.
        await auth.directoryRowWasEvidenced(owner: backendID)
        XCTAssertNotNil(backend.key); XCTAssertNotNil(backend.referenced)
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())
        // The announcement itself reaches the account.
        XCTAssertTrue(ProfileStore.writeSyncedAvatar(pngData: try XCTUnwrap(photo(2).pngData()), for: appleID, modifiedAt: Date()))
        NotificationCenter.default.post(name: AccountDirectoryService.ownRowAppliedNotification, object: nil, userInfo: ["owner": backendID])
        let reached = expectation(description: "the announcement published the waiting photo")
        Task { @MainActor in
            for _ in 0..<50 where ProfileStore.hasPendingLocalAvatarSync() { try? await Task.sleep(nanoseconds: 50_000_000) }
            reached.fulfill()
        }
        await fulfillment(of: [reached], timeout: 5)
        XCTAssertTrue(OwnAvatarSync.samePicture(try XCTUnwrap(backend.referenced), photo(2)))
        XCTAssertEqual(backend.objects.count, 1, "the photo it replaced was deleted by its name")
        // With nothing waiting, an evidenced row starts nothing.
        let quiet = backend.log.count
        await auth.directoryRowWasEvidenced(owner: backendID)
        XCTAssertEqual(backend.log.count, quiet)
    }

    /// "A Solo device itself must not gain Connected credentials or publish
    /// directly to Supabase": the same import with no token and Solo mode.
    func testWithNoIdentityTheSameImportPublishesNothingAndKeepsTheMarker() async throws {
        Keychain.delete("supabaseAccessToken_v1"); Keychain.delete("supabaseRefreshToken_v1")
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        UserDefaults.standard.removeObject(forKey: "backendUserID_v1")
        setBackendMode(.localSimulation)
        let auth = AuthManager(identityService: LocalStubIdentityService())
        XCTAssertFalse(auth.hasConnectedIdentity); XCTAssertFalse(auth.hasSupabaseAccessToken)
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)
        importProfile(serverProfile(location: "Beta", stamp: Date(timeIntervalSince1970: 1_000)), scope: scope)
        _ = JournalProfileSync.applyAvatar(serverAvatar(png: pngData(0.5), stamp: Date(timeIntervalSince1970: 1_000)), scope: scope, store: store) { _ in }
        let backend = FakeAvatarBackend(userID: backendID)
        auth.avatarBackend = backend
        await auth.publishProfileAppliedBySync()
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "solo")
        XCTAssertTrue(backend.log.isEmpty, "the avatar backend was not even looked at")
        XCTAssertEqual(StageHConnectedStub.requests.count, 0, "nothing was sent anywhere")
        XCTAssertEqual(ConnectedWriteWitness.total, 0)
        XCTAssertFalse(auth.hasConnectedIdentity, "and the device gained no identity")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload(), "held for a later join, like an avatar chosen in Solo")
        XCTAssertEqual(ProfileStore.location(for: nil), "Beta")
    }

    /// The engine calls the publish after every import that changed the profile,
    /// from both places an import is applied.
    func testTheEngineAsksForThePublishAfterEveryProfileImport() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("MOTIVO/SyncTest/JournalSyncEngine.swift"), encoding: .utf8)
        XCTAssertEqual(source.components(separatedBy: "JournalProfileSync.didApplyNotification").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: "auth?.publishProfileAppliedBySync()").count - 1, 2,
                       "the ordinary import and the rejected-send import both publish")
    }
}
#endif
