//
//  MOTIVOApp.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

@main
struct MOTIVOApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var auth = AuthManager()

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(auth)
                .onAppear { LegacyDefaultsPurge.runOnce() } // CHANGE-ID: 20251103_094600-legacy-defaults-purge-v1
                .onReceive(auth.$currentUserID.removeDuplicates()) { uid in
                    persistenceController.currentUserID = uid
                    if let id = uid {
                        Task { await persistenceController.runOneTimeBackfillIfNeeded(for: id) }
                    }
                }
        }
    }
}
