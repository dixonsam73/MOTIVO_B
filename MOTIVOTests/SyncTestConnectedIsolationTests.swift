//
//  SyncTestConnectedIsolationTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage H, item 4: Connected isolation WITH a valid-looking Connected identity
//  present (Apple user id, Supabase access token, backend user id, Connected
//  mode, a configured base URL). The base URL is a loopback port nothing
//  listens on and a URLProtocol stub records and fails every request to it, so
//  no real Supabase profile can be touched. The real `AuthManager` and
//  `ProfileStore` are driven; `ProfileView` is not mounted, so the screen's
//  own `onChange` wiring is represented by the pure filter and policy it
//  consults. Device coverage is separate and had no identity at all.
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
    static var requests: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }
    static func reset() { lock.lock(); recorded = []; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host && request.url?.port == port
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.recorded.append(request.url!); Self.lock.unlock()
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
    private let backendID = "stage-h-uid-\(UUID().uuidString.prefix(8))"
    private var saved: [String: String?] = [:]
    private var savedDefaults: [String: Any?] = [:]
    private let keychainKeys = ["appleUserID", "supabaseAccessToken_v1", "supabaseRefreshToken_v1", "displayName"]
    private let defaultsKeys = ["backendMode_v1", "supabaseUserID_v1", "backendUserID_v1"]
    private var savedBaseURL: URL?
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
        UserDefaults.standard.set(backendID, forKey: "supabaseUserID_v1")
        UserDefaults.standard.set(backendID, forKey: "backendUserID_v1")
        URLProtocol.registerClass(StageHConnectedStub.self)
        StageHConnectedStub.reset()
        AuthManager.unitTestSuppressesPostSessionScheduling = true
        ConnectedWriteWitness.resetForTesting()
        JournalProfileMirror.onChange = nil
        UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.avatarSyncState_v1")
        ProfileStore.removeSyncedAvatar(for: appleID)
    }

    override func tearDownWithError() throws {
        ProfileStore.removeSyncedAvatar(for: appleID)
        UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.avatarSyncState_v1")
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

    private func serverAvatar(png: Data, stamp: Date) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.profileAvatar,
                         recordID: CKRecord.ID(recordName: JournalProfileSync.avatarName, zoneID: JournalRecordMapping.zoneID))
        let url = tempDir.appendingPathComponent("server-avatar.png")
        try! png.write(to: url)
        r[JournalRecordMapping.assetKey] = CKAsset(fileURL: url)
        r[JournalRecordMapping.fileHashKey] = JournalAssetHash.hash(of: url)! as CKRecordValue
        r["userModifiedAt"] = stamp as CKRecordValue
        return r
    }

    func testWithAnIdentityPresentImportsAndDisplayPublishNothingWhileADeliberateEditStillDoes() async throws {
        let auth = AuthManager(identityService: LocalStubIdentityService())
        XCTAssertTrue(auth.hasConnectedIdentity, "the fixture must look like a signed-in Connected member")
        XCTAssertTrue(auth.isConnected); XCTAssertTrue(auth.hasSupabaseAccessToken); XCTAssertTrue(BackendConfig.isConfigured)
        XCTAssertEqual(auth.backendUserID, backendID)
        let scope = JournalProfileScope(locationUserID: auth.backendUserID, avatarUserID: auth.currentUserID)

        // 1. The private sync imports profile text and an avatar.
        let profile = CKRecord(recordType: JournalSyncRecordType.profile,
                               recordID: CKRecord.ID(recordName: JournalProfileSync.profileName, zoneID: JournalRecordMapping.zoneID))
        profile["name"] = "Samuel Dixon" as CKRecordValue; profile["location"] = "London" as CKRecordValue
        profile[JournalRecordMapping.instrumentNameKey] = "" as CKRecordValue
        profile["userModifiedAt"] = Date(timeIntervalSince1970: 1_000) as CKRecordValue
        importerContext.performAndWait {
            _ = JournalProfileSync.applyProfile(profile, context: importerContext, scope: scope, store: store, importer: importer) { _ in }
        }
        let avatarOutcome = JournalProfileSync.applyAvatar(serverAvatar(png: pngData(0.5), stamp: Date(timeIntervalSince1970: 1_000)),
                                                           scope: scope, store: store) { _ in }
        XCTAssertEqual(avatarOutcome.applied, 1)
        XCTAssertEqual(ProfileStore.presentedLocation(for: auth.backendUserID), "London", "the screen's scope got the value")
        XCTAssertNotNil(ProfileStore.avatarImage(for: auth.currentUserID))
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "an imported avatar is not a pending Connected upload")

        // 2. What the app does next with an identity present: the avatar promotion
        //    (run on sign-in, app activation and every Profile appearance) and the
        //    directory hydration preconditions.
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "stage-h-import")
        XCTAssertEqual(StageHConnectedStub.requests.count, 0, "no avatar upload or directory request for an imported avatar")
        XCTAssertEqual(ConnectedWriteWitness.total, 0)

        // 3. Displaying and reopening Profile: the screen's onChange handlers consult
        //    the hydration filter for values the sync put on screen.
        var filter = ProfileSyncHydrationFilter()
        filter.noteHydrated("Samuel Dixon"); filter.noteHydrated("London")
        XCTAssertFalse(filter.shouldPublish("Samuel Dixon")); XCTAssertFalse(filter.shouldPublish("London"))
        XCTAssertTrue(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: auth.hasConnectedIdentity, isBackendConfigured: BackendConfig.isConfigured,
            hasAccessToken: auth.hasSupabaseAccessToken, backendUserID: auth.backendUserID),
            "the member COULD publish, which is why the filter and the marker matter")

        // 4. An unrelated local change afterwards: a session saved, the location
        //    rewritten with the same value (what Profile's close does).
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: container.viewContext)
        session.setValue(UUID(), forKey: "id"); session.setValue("T", forKey: "title"); session.setValue(Date(), forKey: "timestamp")
        try container.viewContext.save()
        ProfileStore.setLocation("London", for: auth.backendUserID)
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "stage-h-unrelated-save")
        XCTAssertEqual(StageHConnectedStub.requests.count, 0)
        XCTAssertEqual(ConnectedWriteWitness.total, 0)
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())

        // 5. Legitimate behaviour is untouched: the member's own avatar edit is
        //    promoted (attempted against the stub, which fails it, so the marker stays).
        ProfileStore.saveAvatarDerived(UIImage(data: pngData(0.9))!, for: nil)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload())
        await auth.syncPendingLocalAvatarToConnectedIfNeeded(reason: "stage-h-deliberate-edit")
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.avatarUpload), 1, "a deliberate edit attempts the upload")
        XCTAssertEqual(StageHConnectedStub.requests.count, 1)
        XCTAssertTrue(StageHConnectedStub.requests[0].path.contains("avatars"))
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload(), "the failed attempt keeps the marker for a retry")
        XCTAssertEqual(ConnectedWriteWitness.count(ConnectedWriteWitness.directoryUpsert), 0)
        // And a typed name is published by the screen's rule (the filter lets it through).
        XCTAssertTrue(filter.shouldPublish("Samuel D"))
    }
}
#endif
