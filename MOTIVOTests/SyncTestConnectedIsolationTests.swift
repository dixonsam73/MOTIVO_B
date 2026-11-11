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
        UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.avatarSyncState_v1")
    }

    override func tearDownWithError() throws {
        JournalProfileMirror.onChange = nil
        ProfileStore.removeSyncedAvatar(for: appleID)
        UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.avatarSyncState_v1")
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
        await auth.publishProfileAppliedBySync()
        XCTAssertEqual(ConnectedWriteWitness.total, 0, "not before the first hydration (scheduling is off in this fixture)")
        auth.markDirectoryHydratedForTesting()
        await auth.publishProfileAppliedBySync()
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.avatarUpload), 1, "the avatar is published")
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.directoryUpsert), 1, "and so is the text, once")
        XCTAssertTrue(StageHConnectedStub.requests.contains { $0.path.contains("avatars") })
        XCTAssertTrue(try XCTUnwrap(upserts().last).contains("\"location\":\"Beta\""), "the imported location is what the publish carries")
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload(), "the stub failed the upload, so the marker stays for a retry")
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
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.avatarUpload), 2, "the failed upload was retried from the kept marker")

        // 4. A photo change arrives as a removal and then the new image (C-194).
        //    The removal is published; publishing it must not give this device a
        //    newer "removed" clock, or the image that follows would lose to it.
        mirrorEvents = 0
        let removedAt = Date(timeIntervalSince1970: 2_000)
        let removal = JournalProfileSync.applyAvatar(serverAvatar(png: nil, stamp: removedAt), scope: scope, store: store) { _ in }
        XCTAssertEqual(removal.applied, 1)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarDeletion())
        await auth.publishProfileAppliedBySync()
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.avatarDelete), 1, "the removal is published")
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
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.avatarUpload), 3, "the new image is published after the removal")
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
        await auth.publishProfileAppliedBySync()
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "solo")
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
