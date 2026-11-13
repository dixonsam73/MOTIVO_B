//
//  SyncOffByDefaultTests.swift
//  MOTIVOTests — every configuration (Debug, Release, SyncTest).
//
//  THE PRIVATE SYNC IS OFF BY DEFAULT, AND OFF MEANS NOTHING RUNS.
//
//  The sync code compiles into every build since the main-build integration
//  (2026-11-04). The switch is the state file: with no file the coordinator
//  builds nothing — no state store, no `JournalSyncEngine` (the only place a
//  `CKContainer` is made), no push registration — and the profile and score
//  mirrors at the app's write points are inert. ONE thing runs with sync off
//  (C-197, 2026-11-13): every local edit keeps its clock, `userModifiedAt`,
//  written by the edit-stamp observer and by the metadata mirror, so an edit
//  made before sync is turned on is not lost to an older cloud copy. Nothing
//  is queued, sent or fetched. Normal local use (insert, edit, delete, the
//  metadata, profile and score hooks, the erase bracket) otherwise runs
//  unchanged. Two source guards keep the "only the engine touches CloudKit,
//  only the coordinator builds the engine" shape, and a configuration guard
//  keeps Debug and Release without the CloudKit container or push, so no
//  build but the isolated SyncTest one can sync.
//
//  The enable path (the switch is written, history before it is not read,
//  the next launch starts, off is the stage E unlink) is tested under
//  SYNCTEST, where the test host carries the entitlements the engine needs.
//

import XCTest
import CoreData
import CloudKit
@testable import Etudes

@MainActor
final class SyncOffByDefaultTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var tempDir: URL!
    private var stateURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("syncoff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // The app's store options (PersistenceController): history tracking on,
        // the app author on the view context.
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil, "store failed to load: \(String(describing: loadError))")
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // The app's layout: a directory the launch must NOT create.
        stateURL = tempDir.appendingPathComponent("SyncTest", isDirectory: true).appendingPathComponent("JournalSyncState.json")
    }

    override func tearDownWithError() throws {
        JournalMetadataMirror.container = nil
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    @discardableResult
    private func makeSession(_ ctx: NSManagedObjectContext, title: String = "T") -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(UUID(), forKey: "id")
        s.setValue(title, forKey: "title")
        s.setValue(Date(), forKey: "timestamp")
        return s
    }

    private func historyAuthors() -> [String?] {
        var authors: [String?] = []
        let ctx = container.newBackgroundContext()
        ctx.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            request.resultType = .transactionsOnly
            if let result = try? ctx.execute(request) as? NSPersistentHistoryResult,
               let transactions = result.result as? [NSPersistentHistoryTransaction] {
                authors = transactions.map(\.author)
            }
        }
        return authors
    }

    private func settle(_ seconds: TimeInterval = 0.3) {
        let exp = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 2)
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func swiftSources() -> [(path: String, text: String)] {
        let root = repoRoot.appendingPathComponent("MOTIVO")
        var out: [(String, String)] = []
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), text))
        }
        XCTAssertGreaterThan(out.count, 100, "the app's sources were not found from \(root.path)")
        return out
    }

    // MARK: off by default

    func testFreshInstallStartsNothing() {
        let c = JournalSyncCoordinator(stateFileURL: stateURL)
        var pushAsked = 0
        c.registerForPush = { pushAsked += 1 }

        XCTAssertFalse(c.startIfNeeded(persistence: container))
        XCTAssertFalse(c.startIfNeeded(persistence: container), "asking twice is still nothing")

        XCTAssertNil(c.engine, "no engine: the engine is the only place a CKContainer is made")
        XCTAssertNil(c.store)
        XCTAssertFalse(c.isInUse)
        XCTAssertFalse(c.isEnabled)
        XCTAssertEqual(pushAsked, 0, "no push registration without an engine")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.deletingLastPathComponent().path),
                       "a launch with sync off leaves no directory behind")
        XCTAssertEqual(c.status.phase, "Not started")
    }

    func testLocalUseIsUnchangedWithSyncOff() throws {
        let c = JournalSyncCoordinator(stateFileURL: stateURL)
        XCTAssertFalse(c.startIfNeeded(persistence: container))
        let ctx = container.viewContext

        // Insert, edit, delete through the app's own context.
        let session = makeSession(ctx)
        try ctx.save()
        session.setValue("edited", forKey: "title")
        try ctx.save()
        let edited = try XCTUnwrap(session.value(forKey: "userModifiedAt") as? Date, "C-197: an edit is clocked with sync off, by the launch alone")
        let id = try XCTUnwrap(session.value(forKey: "id") as? UUID)

        // Every hook the app's write points call, with sync off: the metadata
        // mirror moves its row's clock and nothing else; the others are inert.
        JournalMetadataMirror.sessionChanged(id)                 // favourite toggled
        JournalMetadataMirror.attachmentChanged(UUID())          // privacy / pages
        JournalMetadataMirror.titleChanged(UUID(), title: "x")   // audio/video title
        JournalProfileMirror.locationChanged()
        JournalProfileMirror.avatarChanged()
        JournalProfileMirror.avatarRemoved()
        JournalProfileMirror.primaryChosen()
        JournalProfileMirror.setEditingHold(true)
        JournalProfileMirror.setEditingHold(false)
        JournalScoreMirror.changed(.library)
        JournalScoreMirror.changed(.position)
        JournalScoreMirror.viewerClosed(UUID())
        settle()
        ctx.refreshAllObjects()
        XCTAssertGreaterThan(try XCTUnwrap(session.value(forKey: "userModifiedAt") as? Date), edited, "a favourite toggled with sync off moves the entry's clock")
        XCTAssertEqual(session.value(forKey: "title") as? String, "edited", "and changes nothing else on the row")
        XCTAssertEqual(Set(historyAuthors().map { $0 ?? "nil" }), [JournalSyncAuthor.app, JournalSyncAuthor.metadata],
                       "history holds the app's own transactions and the clock touch: no sync author")

        ctx.delete(session)
        try ctx.save()

        // The erase bracket proceeds and records nothing.
        XCTAssertTrue(c.beginLocalRemoval(reason: "test"), "with sync never used the erase is not refused")
        c.finishLocalRemoval()
        let done = expectation(description: "disable")
        Task { await c.disable(); done.fulfill() }
        wait(for: [done], timeout: 2)

        XCTAssertNil(c.engine)
        XCTAssertNil(c.store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testSetUpCardOffersSyncOnlyToABuildThatCanSync() {
        XCTAssertEqual(JournalRestoreOffer.decide(started: false, supported: false, unlinked: false, localCopyRemoved: false,
                                                  localRemovalInProgress: false, pausedReason: nil, initialFetchComplete: false,
                                                  lastCatchUp: nil, profileName: ""), .none)
        XCTAssertEqual(JournalRestoreOffer.decide(started: false, supported: true, unlinked: false, localCopyRemoved: false,
                                                  localRemovalInProgress: false, pausedReason: nil, initialFetchComplete: false,
                                                  lastCatchUp: nil, profileName: ""), .turnOn)
        // Once started, the stage E / C-151 decisions are unchanged.
        XCTAssertEqual(JournalRestoreOffer.decide(started: true, supported: true, unlinked: true, localCopyRemoved: true,
                                                  localRemovalInProgress: false, pausedReason: nil, initialFetchComplete: false,
                                                  lastCatchUp: nil, profileName: ""), .offer(localCopyRemoved: true))
        XCTAssertEqual(JournalRestoreOffer.decide(started: true, supported: true, unlinked: false, localCopyRemoved: false,
                                                  localRemovalInProgress: true, pausedReason: nil, initialFetchComplete: false,
                                                  lastCatchUp: nil, profileName: ""), .none)
    }

    // MARK: guards

    func testOnlyTheEngineTouchesCloudKitAndOnlyTheCoordinatorBuildsIt() {
        let sources = swiftSources()
        func files(containing needle: String) -> Set<String> {
            Set(sources.filter { $0.text.contains(needle) }.map(\.path))
        }
        XCTAssertEqual(files(containing: "CKContainer("), ["SyncTest/JournalSyncEngine.swift"],
                       "a CKContainer is made in the engine's init and nowhere else")
        XCTAssertEqual(files(containing: "CKSyncEngine("), ["SyncTest/JournalSyncEngine.swift"])
        XCTAssertEqual(files(containing: "JournalSyncEngine(containerIdentifier"), ["SyncTest/JournalSyncEngine.swift"],
                       "only the coordinator (in the engine's file) builds an engine, and it builds none without the state file")
        let registrations = sources.filter { $0.text.contains("registerForRemoteNotifications()") }
        XCTAssertEqual(Set(registrations.map(\.path)), ["MOTIVOApp.swift"])
        for file in registrations {
            for line in file.text.split(separator: "\n") where line.contains("registerForRemoteNotifications()") {
                XCTAssertTrue(line.contains("registerForPush"),
                              "push registration is handed to the coordinator, which calls it only once an engine exists: \(line)")
            }
        }
        // No compile-time condition is left in the app: whether a build can
        // sync is the container identifier its bundle carries (C-180).
        let conditions = sources.filter { $0.text.contains("#if SYNCTEST") }
        XCTAssertEqual(Set(conditions.map(\.path)), [], "SYNCTEST is a test-target condition only")
        XCTAssertEqual(files(containing: "Bundle.main.object(forInfoDictionaryKey: infoKey)"), ["SyncTest/JournalSyncEngine.swift"],
                       "the capability reads the identifier from the bundle in one place")
    }

    /// C-181: sync was used on this install, then the build lost the
    /// capability (the Release setting removed, or an older build restored),
    /// then the person erased the journal. The erase's batch deletes are in
    /// persistent history; a later build that can sync must read them as the
    /// recorded local removal, never as deletions to send.
    func testEraseAfterCapabilityWithdrawnIsRecordedAsLocalRemovalNotCloudDeletion() throws {
        let ctx = container.viewContext
        // Sync was on: the state file exists with a history token from then.
        let kept = makeSession(ctx, title: "synced earlier")
        try ctx.save()
        let keptID = try XCTUnwrap(kept.value(forKey: "id") as? UUID)
        let before = JournalSyncStateStore(fileURL: stateURL)
        XCTAssertTrue(before.update { st in
            st.historyToken = JournalSyncStateStore.encode(token: self.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil))
            st.initialFetchComplete = true
            st.lastKnownRecords[keptID.uuidString] = Data()
        })
        // The capability is gone: nothing starts, no engine, no store.
        let withdrawn = JournalSyncCoordinator(stateFileURL: stateURL, supportsSync: false)
        XCTAssertFalse(withdrawn.startIfNeeded(persistence: container))
        XCTAssertNil(withdrawn.engine)
        XCTAssertFalse(withdrawn.enable(persistence: container), "a build without the capability cannot turn sync on")
        // The erase, bracketed as LocalFactoryReset does it.
        XCTAssertTrue(withdrawn.beginLocalRemoval(reason: "test erase"))
        let removal = JournalSyncStateStore(fileURL: stateURL).state
        XCTAssertTrue(removal.localRemovalInProgress, "the marker is durable before the first row goes")
        ctx.delete(kept)
        try ctx.save()
        withdrawn.finishLocalRemoval()
        let after = JournalSyncStateStore(fileURL: stateURL).state
        XCTAssertFalse(after.localRemovalInProgress)
        XCTAssertTrue(after.localCopyRemoved)
        XCTAssertTrue(after.unlinked, "sync is off until explicitly re-enabled")
        XCTAssertTrue(after.outbox.isEmpty)
        XCTAssertTrue(after.lastKnownRecords.isEmpty, "server knowledge is forgotten, so nothing can be sent as a delete")
        // The capability is back: the history since the old token holds the
        // deletion, but the token was fast-forwarded past it.
        let restored = JournalSyncStateStore(fileURL: stateURL)
        let tracker = JournalChangeTracker(container: container, store: restored)
        let queued = tracker.processHistory()
        XCTAssertTrue(queued.isEmpty, "no deletion is queued from the erase: \(queued)")
        XCTAssertTrue(restored.state.outbox.isEmpty)
        // And a deletion made AFTER the erase, with sync still off, is the
        // person's own later edit, not sent either until re-enabled (unlinked).
        let later = makeSession(ctx, title: "after the erase")
        try ctx.save()
        ctx.delete(later)
        try ctx.save()
        XCTAssertTrue(JournalSyncStateStore(fileURL: stateURL).state.unlinked)

        // C-182: the set-up screen that follows the erase. Through the card's
        // own decision path, a build that cannot sync offers no restoration
        // (the remembered state is unlinked, which a capable build would
        // offer to restore), and the restore button's action builds nothing.
        var pushAsked = 0
        withdrawn.registerForPush = { pushAsked += 1 }
        XCTAssertNotNil(withdrawn.store, "the remembered state is open after the erase")
        XCTAssertEqual(SyncTestRestoreCard.currentOffer(profileName: "", pausedReason: nil, coordinator: withdrawn), JournalRestoreOffer.none)
        XCTAssertEqual(JournalRestoreOffer.decide(started: true, supported: false, unlinked: true, localCopyRemoved: true, localRemovalInProgress: false,
                                                  pausedReason: nil, initialFetchComplete: false, lastCatchUp: nil, profileName: ""), .none)
        withdrawn.reenable()
        XCTAssertNil(withdrawn.engine, "no engine: the engine is the only place a CKContainer or CKSyncEngine is made")
        XCTAssertFalse(withdrawn.enable(persistence: container))
        XCTAssertNil(withdrawn.engine)
        XCTAssertFalse(withdrawn.startIfNeeded(persistence: container))
        XCTAssertNil(withdrawn.engine)
        XCTAssertEqual(pushAsked, 0, "no push registration without an engine")
        XCTAssertTrue(JournalSyncStateStore(fileURL: stateURL).state.unlinked, "reenable on a build that cannot sync changes nothing")
        // The same state on a build that can sync is offered for restoration
        // (the card's decision with `supported: true`; an engine needs the
        // entitlements, so that half is the trial configuration's tests).
        XCTAssertEqual(JournalRestoreOffer.decide(started: true, supported: true, unlinked: true, localCopyRemoved: true, localRemovalInProgress: false,
                                                  pausedReason: nil, initialFetchComplete: false, lastCatchUp: nil, profileName: ""), .offer(localCopyRemoved: true))
    }

    func testDebugAndReleaseCarryNoCloudKitContainerOrPush() throws {
        let project = try String(contentsOf: repoRoot.appendingPathComponent("MOTIVO.xcodeproj/project.pbxproj"), encoding: .utf8)
        func targetConfiguration(bundleID: String) -> String {
            guard let idRange = project.range(of: "PRODUCT_BUNDLE_IDENTIFIER = \(bundleID);"),
                  let start = project.range(of: "buildSettings = {", options: .backwards, range: project.startIndex..<idRange.lowerBound),
                  let end = project.range(of: "};", range: idRange.upperBound..<project.endIndex) else { return "" }
            return String(project[start.lowerBound..<end.upperBound])
        }
        // The container is a build setting (`ETUDES_CLOUDKIT_CONTAINER`), read
        // by `JournalSyncCapability` from the bundle. A configuration that sets
        // it must carry the matching entitlements, push and background mode;
        // one that does not must carry none of them. Debug never sets it.
        func containerSetting(_ config: String) -> String? {
            guard let range = config.range(of: "ETUDES_CLOUDKIT_CONTAINER = ") else { return nil }
            return String(config[range.upperBound...].prefix { $0 != ";" }).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        func entitlementsFile(_ config: String) -> String? {
            guard let range = config.range(of: "CODE_SIGN_ENTITLEMENTS = ") else { return nil }
            return String(config[range.upperBound...].prefix { $0 != ";" }).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        let plist = try String(contentsOf: repoRoot.appendingPathComponent("MOTIVO/Info.plist"), encoding: .utf8)
        XCTAssertTrue(plist.contains("<string>$(ETUDES_CLOUDKIT_CONTAINER)</string>"), "Info.plist carries the container key, expanded per configuration")
        for bundleID in ["com.samueldixon.motivo.dev", "com.sdsongs.etudes"] {
            let config = targetConfiguration(bundleID: bundleID)
            XCTAssertFalse(config.isEmpty, "configuration for \(bundleID) not found")
            XCTAssertTrue(config.contains("INFOPLIST_FILE = MOTIVO/Info.plist;"), bundleID)
            XCTAssertFalse(config.contains("SYNCTEST"), "\(bundleID) must not compile as the trial build")
        }
        // Debug: the shared entitlements, no container, no push; never syncs.
        let debug = targetConfiguration(bundleID: "com.samueldixon.motivo.dev")
        XCTAssertEqual(entitlementsFile(debug), "MOTIVO/MOTIVO.entitlements")
        XCTAssertNil(containerSetting(debug), "Debug never syncs")
        let debugEntitlements = try String(contentsOf: repoRoot.appendingPathComponent("MOTIVO/MOTIVO.entitlements"), encoding: .utf8)
        XCTAssertFalse(debugEntitlements.lowercased().contains("icloud"), "the Debug entitlements carry no CloudKit container")
        XCTAssertFalse(debugEntitlements.contains("aps-environment"), "the Debug entitlements carry no push")
        // Release: whichever entitlements file it names must agree with its setting.
        let releaseConfig = targetConfiguration(bundleID: "com.sdsongs.etudes")
        let releaseFile = try XCTUnwrap(entitlementsFile(releaseConfig))
        let entitlements = try String(contentsOf: repoRoot.appendingPathComponent(releaseFile), encoding: .utf8)
        let release = containerSetting(releaseConfig)
        if let release {
            // Production enablement applied (docs/sync-trial/production-configuration.md).
            XCTAssertEqual(release, JournalSyncCapability.productionContainerIdentifier)
            XCTAssertNotEqual(releaseFile, "MOTIVO/MOTIVO.entitlements", "Release syncs through its own entitlements file; Debug keeps the shared one")
            XCTAssertTrue(entitlements.contains(release), "the Release entitlements must name the container the build setting names")
            XCTAssertTrue(entitlements.contains("aps-environment"), "the Release entitlements must carry push for the app-wake subscription")
            XCTAssertTrue(plist.contains("remote-notification"), "the Release Info.plist must carry the silent-push background mode")
            XCTAssertFalse(entitlements.contains(JournalSyncCapability.trialContainerIdentifier), "Release never names the trial container")
        } else {
            XCTAssertFalse(entitlements.lowercased().contains("icloud"), "the production entitlements carry no CloudKit container")
            XCTAssertFalse(entitlements.contains("aps-environment"), "the production entitlements carry no push")
            XCTAssertFalse(plist.contains("remote-notification"), "the production Info.plist has no silent-push background mode")
        }
        let trial = targetConfiguration(bundleID: "com.samueldixon.motivo.synctest")
        XCTAssertTrue(trial.contains("MOTIVO-SyncTest.entitlements"))
        XCTAssertTrue(trial.contains("Info-SyncTest.plist"))
        XCTAssertTrue(trial.contains("SYNCTEST"))
        XCTAssertEqual(containerSetting(trial), JournalSyncCapability.trialContainerIdentifier)
        let trialEntitlements = try String(contentsOf: repoRoot.appendingPathComponent("MOTIVO/MOTIVO-SyncTest.entitlements"), encoding: .utf8)
        XCTAssertTrue(trialEntitlements.contains(JournalSyncCapability.trialContainerIdentifier))
        XCTAssertFalse(trialEntitlements.contains("iCloud.com.sdsongs"), "the trial never names a production container")

        // What THIS build resolved at runtime from its own bundle, by the
        // configuration actually running (the hosted tests' Bundle.main is the
        // app): Debug stays disabled whatever Release is set to.
        switch Bundle.main.bundleIdentifier {
        case "com.samueldixon.motivo.synctest":
            XCTAssertEqual(JournalSyncCapability.containerIdentifier, JournalSyncCapability.trialContainerIdentifier)
            XCTAssertTrue(JournalSyncCapability.buildSupportsSync)
        case "com.samueldixon.motivo.dev":
            XCTAssertEqual(JournalSyncCapability.containerIdentifier, "", "Debug never carries a container, even after Release enablement")
            XCTAssertFalse(JournalSyncCapability.buildSupportsSync)
        case "com.sdsongs.etudes":
            XCTAssertEqual(JournalSyncCapability.containerIdentifier, release ?? "", "Release carries exactly the build setting's container, or none")
            XCTAssertEqual(JournalSyncCapability.buildSupportsSync, release != nil)
        default:
            XCTFail("unexpected test host \(Bundle.main.bundleIdentifier ?? "nil")")
        }
    }

    /// C-174: CloudKit traps ("Cannot await a call into CKSyncEngine from
    /// within a delegate callback … Try performing this in a detached Task")
    /// when `sendChanges` is reached from a task that was started inside one
    /// of the engine's delegate callbacks: an unstructured `Task { }` inherits
    /// the callback's context, and so does a task started further down that
    /// chain. The trap itself needs CloudKit and cannot be driven here; this
    /// guards the shape that prevents it. Every task that leads to a send, or
    /// to the reconcile and conflict work a callback starts, is DETACHED.
    func testEveryTaskThatCanReachASendIsDetachedFromTheDelegateCallbacks() throws {
        let engine = try XCTUnwrap(swiftSources().first { $0.path == "SyncTest/JournalSyncEngine.swift" }).text
        XCTAssertEqual(engine.components(separatedBy: "engine.sendChanges()").count - 1, 1, "sendChanges is called in one place, performSend")
        // No inheriting task starts a send, a reconcile or a deferred conflict on its own line…
        for line in engine.split(separator: "\n") where line.contains("Task {") {
            for call in ["performSend(", "reconcile(", "applyDeferredSendConflict("] {
                XCTAssertFalse(line.contains(call), "an inheriting task must not start \(call): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        // …nor in the two multi-line launches.
        func body(from start: String, to end: String) throws -> String {
            let a = try XCTUnwrap(engine.range(of: start), start)
            let b = try XCTUnwrap(engine.range(of: end, range: a.upperBound..<engine.endIndex), end)
            return String(engine[a.lowerBound..<b.lowerBound])
        }
        for (name, text) in [("scheduleManualSend", try body(from: "private func scheduleManualSend(", to: "enum SendDecision")),
                             ("the background send", try body(from: "UIApplication.didEnterBackgroundNotification", to: "installPathMonitorIfNeeded()"))] {
            XCTAssertTrue(text.contains("performSend("), "\(name) is where a send starts")
            XCTAssertTrue(text.contains("Task.detached"), "\(name) must start its send in a detached task")
            XCTAssertFalse(text.contains("Task {"), "\(name) must not use an inheriting task")
        }
        // The callbacks themselves start nothing that inherits and then awaits the engine.
        let callbacks = try body(from: "func handleEvent(_ event: CKSyncEngine.Event", to: "func nextRecordZoneChangeBatch(")
        XCTAssertTrue(callbacks.contains("Task.detached { await self.reconcile(trigger: \"engine account change\") }"),
                      "the account-change event, which is what started the task that trapped")
    }

    /// C-197: the record zone is "Journal". Only the trial build, on the trial
    /// container, can be given another name, for a device trial that must
    /// start from a zone that does not exist; Release and Debug cannot.
    func testTheZoneIsJournalAndOnlyTheTrialBuildCanBeGivenAnother() throws {
        let trial = JournalSyncCapability.trialContainerIdentifier
        XCTAssertEqual(JournalSyncCapability.zoneName(container: trial, trialZone: "JournalC197"), "JournalC197")
        for container in [JournalSyncCapability.productionContainerIdentifier, "", "iCloud.com.example.other"] {
            XCTAssertEqual(JournalSyncCapability.zoneName(container: container, trialZone: "JournalC197"), "Journal", "\(container): never another zone")
        }
        for unset in [nil, "", "  ", "$(ETUDES_CLOUDKIT_TRIAL_ZONE)", "two words", "a/b"] as [String?] {
            XCTAssertEqual(JournalSyncCapability.zoneName(container: trial, trialZone: unset), "Journal", "\(unset ?? "nil"): the default")
        }
        // The key is in the trial build's Info plist alone, and no configuration sets the build setting.
        let key = JournalSyncCapability.trialZoneInfoKey
        let plist = try String(contentsOf: repoRoot.appendingPathComponent("MOTIVO/Info.plist"), encoding: .utf8)
        XCTAssertFalse(plist.contains(key), "Release and Debug share Info.plist: it must not carry the trial zone key")
        let trialPlist = try String(contentsOf: repoRoot.appendingPathComponent("MOTIVO/Info-SyncTest.plist"), encoding: .utf8)
        XCTAssertTrue(trialPlist.contains("<key>\(key)</key>"))
        let project = try String(contentsOf: repoRoot.appendingPathComponent("MOTIVO.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertFalse(project.contains("ETUDES_CLOUDKIT_TRIAL_ZONE"), "the trial zone is given on the command line for one run, never committed to a configuration")
        let schemes = try FileManager.default.contentsOfDirectory(at: repoRoot.appendingPathComponent("MOTIVO.xcodeproj/xcshareddata/xcschemes"), includingPropertiesForKeys: nil)
        for scheme in schemes { XCTAssertFalse(try String(contentsOf: scheme, encoding: .utf8).contains("ETUDES_CLOUDKIT_TRIAL_ZONE"), scheme.lastPathComponent) }
        // What THIS build resolved: "Journal", whichever configuration is running the tests.
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: key).flatMap { ($0 as? String).flatMap { $0.isEmpty ? nil : $0 } }, "no trial zone in an ordinary build")
        XCTAssertEqual(JournalSyncCapability.zoneName, "Journal")
        XCTAssertEqual(JournalRecordMapping.zoneID.zoneName, "Journal")
        if Bundle.main.bundleIdentifier != "com.samueldixon.motivo.synctest" {
            XCTAssertNotEqual(JournalSyncCapability.containerIdentifier, trial, "only the trial build is on the trial container")
        }
    }

    #if SYNCTEST
    // MARK: the switch (SyncTest only: the engine needs the entitlements)

    func testEnableWritesTheSwitchFastForwardsHistoryAndTheNextLaunchStarts() throws {
        let ctx = container.viewContext
        // Made and deleted BEFORE the switch: never sync's business.
        let gone = makeSession(ctx, title: "before, deleted")
        try ctx.save()
        ctx.delete(gone)
        try ctx.save()
        // Exists at the switch: the bootstrap's job (at activation), not history's.
        makeSession(ctx, title: "before, kept")
        try ctx.save()

        let c = JournalSyncCoordinator(stateFileURL: stateURL)
        var pushAsked = 0
        c.registerForPush = { pushAsked += 1 }
        XCTAssertFalse(c.startIfNeeded(persistence: container))

        XCTAssertTrue(c.enable(persistence: container))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path), "the switch is the state file")
        XCTAssertTrue(c.isInUse)
        XCTAssertTrue(c.isEnabled)
        XCTAssertNotNil(c.engine)
        XCTAssertEqual(pushAsked, 1, "pushes are asked for once an engine exists")
        let store = try XCTUnwrap(c.store)
        XCTAssertNotNil(store.state.historyToken, "the token is at now")

        // Reading history from the stored token queues nothing from before the switch.
        let tracker = JournalChangeTracker(container: container, store: store)
        let queued = tracker.processHistory()
        XCTAssertTrue(queued.isEmpty, "history before the switch is not read: \(queued)")
        XCTAssertFalse(store.state.outbox.contains { $0.op == .delete }, "a deletion before the switch never goes up")

        XCTAssertTrue(c.enable(persistence: container), "enabling again is idempotent")
        XCTAssertEqual(pushAsked, 1)

        // The next launch: the file exists, so the coordinator starts.
        let next = JournalSyncCoordinator(stateFileURL: stateURL)
        XCTAssertTrue(next.startIfNeeded(persistence: container))
        XCTAssertTrue(next.isInUse)
        XCTAssertTrue(next.isEnabled)
    }

    func testOffIsTheUnlinkAndTheSwitchStays() throws {
        let c = JournalSyncCoordinator(stateFileURL: stateURL)
        XCTAssertTrue(c.enable(persistence: container))
        let engine = try XCTUnwrap(c.engine)
        let done = expectation(description: "disable")
        Task { await c.disable(); done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertTrue(c.isInUse, "off is remembered: the file stays")
        XCTAssertFalse(c.isEnabled)
        XCTAssertTrue(c.store?.state.unlinked ?? false)
        XCTAssertFalse(engine.currentDecision().allowed, "nothing is sent or fetched while off")
        XCTAssertNil(engine.engine, "no CKSyncEngine while off")

        // The next launch starts (the file exists) but stays off until enabled.
        let next = JournalSyncCoordinator(stateFileURL: stateURL)
        XCTAssertTrue(next.startIfNeeded(persistence: container))
        XCTAssertFalse(next.isEnabled)

        // On again: the stage E re-enable, not a second switch.
        XCTAssertTrue(c.enable(persistence: container))
        XCTAssertTrue(c.isEnabled)
        XCTAssertFalse(c.store?.state.unlinked ?? true)
    }
    #endif
}
