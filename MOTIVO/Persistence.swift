//
//  Persistence.swift
//  MOTIVO
//

import Foundation
import CoreData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// Current signed-in user ID (set from MOTIVOApp)
    var currentUserID: String?

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MOTIVO")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        // Merge policy & context niceties
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}

// MARK: - Author-Scoped Custom Directories & Normalization

extension PersistenceController {
    /// Used to scope custom directories (UserInstrument/UserActivity) to the owner.
    var ownerIDForCustoms: String? { currentUserID }

    /// Normalize names for dedupe/search (case + diacritic-insensitive; whitespace-collapsing).
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let collapsed = lowered
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    // MARK: UserInstrument helpers

    @discardableResult
    func fetchOrCreateUserInstrument(
        named name: String,
        mapTo core: Instrument? = nil,
        visibleOnProfile: Bool = true,
        in ctx: NSManagedObjectContext? = nil
    ) throws -> UserInstrument {
        guard let owner = ownerIDForCustoms else {
            throw NSError(domain: "Persistence", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Missing ownerUserID"])
        }
        let ctx = ctx ?? container.viewContext
        let norm = Self.normalized(name)

        let fr: NSFetchRequest<UserInstrument> = UserInstrument.fetchRequest()
        fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ownerUserID == %@", owner),
            NSPredicate(format: "normalizedName == %@", norm)
        ])
        fr.fetchLimit = 1

        if let existing = try ctx.fetch(fr).first {
            if let core, existing.coreInstrument != core { existing.coreInstrument = core }
            if existing.isVisibleOnProfile != visibleOnProfile {
                existing.isVisibleOnProfile = visibleOnProfile
            }
            return existing
        }

        let ui = UserInstrument(context: ctx)
        ui.id = UUID()
        ui.ownerUserID = owner
        ui.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.normalizedName = norm
        ui.isVisibleOnProfile = visibleOnProfile
        ui.displayOrder = 0
        ui.coreInstrument = core
        return ui
    }

    func fetchUserInstruments(includeHidden: Bool = true,
                              in ctx: NSManagedObjectContext? = nil) throws -> [UserInstrument] {
        guard let owner = ownerIDForCustoms else { return [] }
        let ctx = ctx ?? container.viewContext
        let fr: NSFetchRequest<UserInstrument> = UserInstrument.fetchRequest()
        var preds: [NSPredicate] = [NSPredicate(format: "ownerUserID == %@", owner)]
        if !includeHidden {
            preds.append(NSPredicate(format: "isVisibleOnProfile == YES"))
        }
        fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        fr.sortDescriptors = [
            NSSortDescriptor(key: "isVisibleOnProfile", ascending: false),
            NSSortDescriptor(key: "displayOrder", ascending: true),
            NSSortDescriptor(key: "displayName", ascending: true)
        ]
        return try ctx.fetch(fr)
    }

    // MARK: UserActivity helpers

    @discardableResult
    func fetchOrCreateUserActivity(
        named name: String,
        mapTo coreActivityCode: Int16? = nil,
        in ctx: NSManagedObjectContext? = nil
    ) throws -> UserActivity {
        guard let owner = ownerIDForCustoms else {
            throw NSError(domain: "Persistence", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Missing ownerUserID"])
        }
        let ctx = ctx ?? container.viewContext
        let norm = Self.normalized(name)

        let fr: NSFetchRequest<UserActivity> = UserActivity.fetchRequest()
        fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ownerUserID == %@", owner),
            NSPredicate(format: "normalizedName == %@", norm)
        ])
        fr.fetchLimit = 1

        if let existing = try ctx.fetch(fr).first {
            if let core = coreActivityCode {
                if existing.coreActivityCode != core { existing.coreActivityCode = core }
            } else {
                existing.setValue(nil, forKey: "coreActivityCode")
            }
            return existing
        }

        let ua = UserActivity(context: ctx)
        ua.id = UUID()
        ua.ownerUserID = owner
        ua.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        ua.normalizedName = norm
        if let code = coreActivityCode { ua.coreActivityCode = code }
        return ua
    }

    func fetchUserActivities(in ctx: NSManagedObjectContext? = nil) throws -> [UserActivity] {
        guard let owner = ownerIDForCustoms else { return [] }
        let ctx = ctx ?? container.viewContext
        let fr: NSFetchRequest<UserActivity> = UserActivity.fetchRequest()
        fr.predicate = NSPredicate(format: "ownerUserID == %@", owner)
        fr.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
        return try ctx.fetch(fr)
    }
}


// MARK: - Backfill shim (async variant)
extension PersistenceController {
    /// Called once after migration to backfill data for a specific user ID.
    /// Currently a no-op so the app compiles and runs.
    @MainActor
    func runOneTimeBackfillIfNeeded(for userID: String) async {
        // TODO: add real backfill logic if required
        return
    }
}
