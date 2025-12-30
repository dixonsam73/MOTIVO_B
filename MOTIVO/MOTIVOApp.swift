//
//  MOTIVOApp.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData
import Foundation

// CHANGE-ID: 20251203_BackendIdentityHandshakeStep5
// SCOPE: Step 5 — Inject LocalStubIdentityService into AuthManager (no behaviour/UI changes)

// CHANGE-ID: 20251230_Step7_BackendConfigApplyAtLaunch
// SCOPE: Step 7 — Apply BackendConfig at app launch so NetworkManager.baseURL/authToken are configured before backend services select simulated vs HTTP

@main
struct MOTIVOApp: App {
    let persistenceController = PersistenceController.shared
    private let identityService: IdentityService
    @StateObject private var auth: AuthManager
    private let ephemeralMediaFlagKey = "ephemeralSessionHasMedia_v1"

    init() {
        // Step 7: ensure live HTTP configuration is applied before any backend services initialize
        BackendConfig.apply()
        let identityService = LocalStubIdentityService()
        self.identityService = identityService
        _auth = StateObject(wrappedValue: AuthManager(identityService: identityService))

        // [ROLLBACK ANCHOR] v7.8 pre-hotfix — launch stall (profile-id backfill)

        // Backfill: ensure all Profile rows have a non-nil UUID `id`
        let ctx = persistenceController.container.viewContext
        ctx.perform {
            let req = NSFetchRequest<NSManagedObject>(entityName: "Profile")
            req.predicate = NSPredicate(format: "id == nil")
            if let rows = try? ctx.fetch(req), !rows.isEmpty {
                for row in rows {
                    row.setValue(UUID(), forKey: "id")
                }
                do { try ctx.save() } catch {
                    // Non-fatal: we’ll also set IDs when creating a new Profile in ProfileView
                }
            }
        }

        LegacyDefaultsPurge.runOnce()

        // Migrate oversized PracticeTimer.stagedVideo from UserDefaults to file store (no-op if already migrated)
        _ = PracticeTimerStore.loadStagedVideo()

        cleanupEphemeralMediaIfNeeded()

        #if DEBUG
        logBigDefaults()
        #endif
    }

    #if DEBUG
    private func logBigDefaults(threshold: Int = 3_000_000) {
        let d = UserDefaults.standard.dictionaryRepresentation()
        for (key, value) in d {
            if let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0), data.count >= threshold {
                print("[App] Large UserDefaults key: \(key) size: \(data.count) bytes")
            }
        }
    }
    #endif

    private func cleanupEphemeralMediaIfNeeded() {
        let d = UserDefaults.standard
        guard d.bool(forKey: ephemeralMediaFlagKey) == true else { return }

        #if DEBUG
        print("[EphemeralCleanup] Launch cleanup triggered")
        #endif

        // Best-effort: ensure staging area exists so list/remove works
        do { try StagingStore.bootstrap() } catch { /* ignore */ }
        // Remove all staged refs and files
        let refs = StagingStore.list()
        var removedRefCount = 0
        if !refs.isEmpty {
            for ref in refs { StagingStore.remove(ref); removedRefCount += 1 }
            StagingStore.deleteFiles(for: refs)
            #if DEBUG
            print("[EphemeralCleanup] StagingStore refs removed: \(removedRefCount)")
            #endif
        }
        // Remove any temporary surrogate recorder files and posters matching known patterns
        let fm = FileManager.default
        let tmp = FileManager.default.temporaryDirectory
        // We remove files with our known extensions and naming patterns: <UUID>.m4a, <UUID>.jpg, <UUID>.mov, and <UUID>_poster.jpg
        if let urls = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            var removedTempCount = 0
            for url in urls {
                let name = url.lastPathComponent.lowercased()
                if name.hasSuffix(".m4a") || name.hasSuffix(".jpg") || name.hasSuffix(".mov") {
                    // Only remove files that look like our surrogates: UUID-based names, optionally with _poster suffix
                    let base = url.deletingPathExtension().lastPathComponent
                    let core = base.replacingOccurrences(of: "_poster", with: "")
                    if UUID(uuidString: core) != nil {
                        try? fm.removeItem(at: url)
                        removedTempCount += 1
                    }
                }
            }
            #if DEBUG
            print("[EphemeralCleanup] Temp files removed: \(removedTempCount)")
            #endif
        }
        // Reset flag
        d.set(false, forKey: ephemeralMediaFlagKey)
        #if DEBUG
        print("[EphemeralCleanup] Flag reset to false")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(auth)
                .onAppear {
                    // Ensure staging area exists early and exclude from backups
                    try? StagingStore.bootstrap()
                }
                .onReceive(auth.$currentUserID.removeDuplicates()) { uid in
                    persistenceController.currentUserID = uid
                    if let id = uid {
                        Task { await persistenceController.runOneTimeBackfillIfNeeded(for: id) }
                    }
                }
        }
    }
}
