//
//  Persistence.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import Foundation
import CoreData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    // Expose the container for environment(\.managedObjectContext)
    let container: NSPersistentContainer

    // Published from AuthManager via MOTIVOApp
    // When set, we attach stamping and run one-time backfill if needed.
    var currentUserID: String? {
        didSet {
            attachOwnerStamping()
            if let uid = currentUserID {
                Task { await runOneTimeBackfillIfNeeded(for: uid) }
            }
        }
    }

    // Observers (kept to avoid being deallocated)
    private var willSaveObserver: NSObjectProtocol?
    private var didSaveObserver: NSObjectProtocol?

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MOTIVO")

        // Lightweight migration
        if let desc = container.persistentStoreDescriptions.first {
            desc.shouldMigrateStoreAutomatically = true
            desc.shouldInferMappingModelAutomatically = true
            if inMemory {
                desc.url = URL(fileURLWithPath: "/dev/null")
            }
        }

        container.loadPersistentStores { [container] storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
            }

            // Optional diagnostics
            if let path = storeDescription.url?.path {
                print("Core Data store URL:", path)
            }
            do {
                let req: NSFetchRequest<Session> = Session.fetchRequest()
                let count = try container.viewContext.count(for: req)
                print("Session count at launch:", count)
            } catch {
                print("Session count at launch failed:", error.localizedDescription)
            }
        }

        // UI context configuration
        let ctx = container.viewContext
        ctx.automaticallyMergesChangesFromParent = true
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Ensure SwiftUI lists refresh immediately after saves (including self-saves)
        attachSaveBridge()
    }

    // MARK: - Stamping new objects with ownerUserID

    private func attachOwnerStamping() {
        // Remove any previous observer to avoid duplicates
        if let obs = willSaveObserver {
            NotificationCenter.default.removeObserver(obs)
            willSaveObserver = nil
        }

        let ctx = container.viewContext
        willSaveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: ctx,
            queue: nil
        ) { [weak self] note in
            guard
                let self,
                let uid = self.currentUserID,
                let context = note.object as? NSManagedObjectContext
            else { return }

            // Only stamp newly inserted objects
            let inserted = context.insertedObjects
            guard !inserted.isEmpty else { return }

            for obj in inserted {
                guard let entity = obj.entity.name else { continue }
                switch entity {
                case "Session", "Tag", "Attachment":
                    // If missing/blank, stamp the owner
                    let current = obj.value(forKey: "ownerUserID") as? String
                    if current == nil || current?.isEmpty == true {
                        obj.setValue(uid, forKey: "ownerUserID")
                    }
                    // For Attachment, inherit from session if present
                    if entity == "Attachment",
                       let session = obj.value(forKey: "session") as? NSManagedObject,
                       let sid = session.value(forKey: "ownerUserID") as? String,
                       !sid.isEmpty {
                        obj.setValue(sid, forKey: "ownerUserID")
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - One-time backfill after sign-in

    private func migratedFlagKey(for uid: String) -> String { "ownerUserIDMigratedFor_\(uid)" }
    private func hasMigrated(for uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: migratedFlagKey(for: uid))
    }
    private func setMigrated(for uid: String) {
        UserDefaults.standard.set(true, forKey: migratedFlagKey(for: uid))
    }

    /// Ensures all legacy rows have ownerUserID. Runs once per user.
    func runOneTimeBackfillIfNeeded(for uid: String) async {
        if hasMigrated(for: uid) { return }
        let ctx = container.viewContext

        do {
            try backfill(entity: "Session", ownerKey: "ownerUserID", in: ctx, uid: uid)
            try backfill(entity: "Tag", ownerKey: "ownerUserID", in: ctx, uid: uid)
            try backfill(entity: "Attachment", ownerKey: "ownerUserID", in: ctx, uid: uid)

            if ctx.hasChanges { try ctx.save() }
            setMigrated(for: uid)
            print("Owner backfill complete for user:", uid)
        } catch {
            print("Owner backfill failed:", error.localizedDescription)
        }
    }

    private func backfill(entity name: String, ownerKey: String, in ctx: NSManagedObjectContext, uid: String) throws {
        let req = NSFetchRequest<NSManagedObject>(entityName: name)
        req.predicate = NSPredicate(format: "%K == nil OR %K == %@", ownerKey, ownerKey, "")
        let rows = try ctx.fetch(req)
        for obj in rows {
            obj.setValue(uid, forKey: ownerKey)
        }
    }

    // MARK: - Save bridge (keeps SwiftUI in sync)

    private func attachSaveBridge() {
        if let obs = didSaveObserver {
            NotificationCenter.default.removeObserver(obs)
            didSaveObserver = nil
        }

        let viewContext = container.viewContext
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { note in
            guard let savingCtx = note.object as? NSManagedObjectContext else { return }
            if savingCtx !== viewContext {
                // Merge background/sibling context changes into the viewContext
                viewContext.perform {
                    viewContext.mergeChanges(fromContextDidSave: note)
                    viewContext.processPendingChanges()
                }
            } else {
                // Even on self-saves, nudge SwiftUI to refresh fetched results immediately
                viewContext.perform {
                    viewContext.processPendingChanges()
                }
            }
        }
    }
}
