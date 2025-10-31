//
//  Persistence.swift
//  MOTIVO
//
//  [ROLLBACK ANCHOR] v7.8 Maintenance — pre-context-niceties (no name/undo tweaks)
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

        // v7.8 Maintenance: clearer debugging + avoid unused undo stack work
        container.viewContext.name = "viewContext"
        container.viewContext.undoManager = nil
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
    @MainActor
    func runOneTimeBackfillIfNeeded(for userID: String) async {
        // Use a persistent flag so we only run once per user on this device
        let key = "backfill_userInstruments_done_\(userID)"
        if UserDefaults.standard.bool(forKey: key) { return }

        let ctx = container.viewContext

        // Verify owner context is configured for customs (mirrors write path expectations)
        self.currentUserID = self.currentUserID ?? userID

        // Fetch local Profile (single) and its Instruments
        let pReq: NSFetchRequest<Profile> = Profile.fetchRequest()
        pReq.fetchLimit = 1

        let iReq: NSFetchRequest<Instrument> = Instrument.fetchRequest()
        iReq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let profile = try ctx.fetch(pReq).first
            let instruments = try ctx.fetch(iReq)
            // Map only instruments that belong to the local Profile if available
            let filtered: [Instrument]
            if let profile {
                filtered = instruments.filter { $0.profile == profile }
            } else {
                filtered = instruments
            }

            for inst in filtered {
                let raw = (inst.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                do {
                    _ = try fetchOrCreateUserInstrument(
                        named: raw,
                        mapTo: inst,
                        visibleOnProfile: true,
                        in: ctx
                    )
                } catch {
                    // Continue; best-effort backfill
                    print("Backfill UserInstrument failed for \(raw): \(error)")
                }
            }
            try ctx.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            print("Backfill error: \(error)")
        }
    }
}

//  [ROLLBACK ANCHOR] v7.8 Maintenance — post-context-niceties (viewContext named; undo disabled)

