//
//  Persistence.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // Preview seed data (template)
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do { try viewContext.save() }
        catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MOTIVO")

        // Enable lightweight migration (prevents silent resets on minor model changes)
        if let desc = container.persistentStoreDescriptions.first {
            desc.shouldMigrateStoreAutomatically = true
            desc.shouldInferMappingModelAutomatically = true
        }

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { [container] storeDescription, error in
            // Log store URL and Session count at launch (diagnostic)
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

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy   // <<< ADDED
    }
}
