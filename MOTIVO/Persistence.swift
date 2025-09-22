///
//  Persistence.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import CoreData
import Foundation

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    // Current signed-in user (AuthManager owns the truth; App sets this on changes)
    // When set, we attach stamping observers and run one-time backfill if needed.
    var currentUserID: String? {
        didSet {
            attachOwnerStamping()
            if let uid = currentUserID {
                Task { await self.runOneTimeBackfillIfNeeded(for: uid) }
            }
        }
    }

    let container: NSPersistentContainer
    private var willSaveObserver: NSObjectProtocol?

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MOTIVO")

        // Enable lightweight migration
        if let desc = container.persistentStoreDescriptions.first {
            desc.shouldMigrateStoreAutomatically = true
            desc.shouldInferMappingModelAutomatically = true
        }

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { [container] storeDescription, error in
            // Diagnostics
            print("Core Data store URL:", storeDescription.url?.path ?? "nil")
            do {
                let req: NSFetchRequest<Session> = Session.fetchRequest()
                let count = try container.viewContext.count(for: req)
                print("Session count at launch:", count)
            } catch {
                print("Session count at launch failed:", error.localizedDescription)
            }

            if let error = error as NSError? {
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
            }
        }

        // Merge policy & merges
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Owner stamping on insert

    /// Observes context will-save and stamps `ownerUserID` on newly inserted objects
    /// for Session, Tag, and Attachment when a user is signed in.
    private func attachOwnerStamping() {
        // Remove previous observer if any
        if let obs = willSaveObserver {
            NotificationCenter.default.removeObserver(obs)
            willSaveObserver = nil
        }

        guard let ctx = container.viewContext as NSManagedObjectContext? else { return }

        willSaveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: ctx,
            queue: nil
        ) { [weak self] note in
            guard let self, let uid = self.currentUserID else { return }
            guard let context = note.object as? NSManagedObjectContext else { return }

            // Only act on inserts
            let inserted = context.insertedObjects
            if inserted.isEmpty { return }

            for obj in inserted {
                guard let entityName = obj.entity.name else { continue }
                switch entityName {
                case "Session", "Tag", "Attachment":
                    // Only set if not already set
                    if (obj.value(forKey: "ownerUserID") as? String)?.isEmpty ?? true {
                        obj.setValue(uid, forKey: "ownerUserID")
                    }
                    // For Attachment specifically, inherit from its session if present
                    if entityName == "Attachment",
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

    // MARK: - One-time backfill for legacy rows

    /// Backfills missing ownerUserID for existing rows (first run per user).
    private func migratedFlagKey(for uid: String) -> String { "ownerUserIDMigratedFor_\(uid)" }

    private func hasMigrated(for uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: migratedFlagKey(for: uid))
    }

    private func setMigrated(for uid: String) {
        UserDefaults.standard.set(true, forKey: migratedFlagKey(for: uid))
    }

    /// Runs once per user after we know the `currentUserID`.
    func runOneTimeBackfillIfNeeded(for uid: String) async {
        if hasMigrated(for: uid) { return }
        let ctx = container.viewContext

        do {
            // For each entity, set ownerUserID where nil or blank.
            try backfill(entity: "Session", ownerKey: "ownerUserID", in: ctx, uid: uid)
            try backfill(entity: "Tag",      ownerKey: "ownerUserID", in: ctx, uid: uid)
            try backfill(entity: "Attachment", ownerKey: "ownerUserID", in: ctx, uid: uid)

            if ctx.hasChanges { try ctx.save() }
            setMigrated(for: uid)
            print("Owner backfill complete for user:", uid)
        } catch {
            // Non-fatal: we simply log. You can surface a one-time alert if desired.
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
}
