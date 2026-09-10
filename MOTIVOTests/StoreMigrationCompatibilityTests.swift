//
//  StoreMigrationCompatibilityTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-6 — MIGRATION COMPATIBILITY AS RELEASE-TIME VERIFICATION.
//
//  `PersistenceController` traps if the store cannot load, and that is kept
//  deliberately: it is FAIL-CLOSED — the store file is never touched, so the
//  local journal survives. The realistic trigger is a model change that Core
//  Data cannot migrate by inference: 11 shipped model versions, no mapping
//  models. This test opens a store created from EVERY shipped version with the
//  model production actually loads, with production's migration options, so an
//  unmigratable change fails here instead of trapping on a member's device.
//
//  **LIMIT, STATED SO IT IS NOT OVERREAD:** the stores are EMPTY. This proves
//  the schema changes are inferable; it does NOT prove every populated-data
//  migration succeeds (e.g. an attribute made non-optional over existing nils).
//

import XCTest
import CoreData
@testable import Etudes

final class StoreMigrationCompatibilityTests: XCTestCase {

    private var momd: URL? { Bundle.main.url(forResource: "MOTIVO", withExtension: "momd") }

    private func shippedVersions() throws -> [URL] {
        guard let momd else { return [] }
        return try FileManager.default.contentsOfDirectory(at: momd, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mom" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testEveryShippedModelVersionMigratesToTheCurrentModel() throws {
        let versions = try shippedVersions()
        XCTAssertEqual(versions.count, 11,
                       "the shipped version inventory changed — review this test's coverage deliberately")

        for versionURL in versions {
            let name = versionURL.deletingPathExtension().lastPathComponent
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("C6-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let storeURL = dir.appendingPathComponent("MOTIVO.sqlite")

            // 1. A store as that version would have written it.
            guard let oldModel = NSManagedObjectModel(contentsOf: versionURL) else {
                XCTFail("\(name): model did not load"); continue
            }
            let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
            let oldStore = try oldCoordinator.addPersistentStore(type: .sqlite, at: storeURL)
            try oldCoordinator.remove(oldStore)

            // 2. Opened exactly as `PersistenceController.init` opens it.
            let container = NSPersistentContainer(name: "MOTIVO")
            let description = NSPersistentStoreDescription(url: storeURL)
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]

            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            XCTAssertNil(loadError, "\(name) → current model: \(String(describing: loadError))")

            if loadError == nil {
                let meta = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
                XCTAssertTrue(container.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: meta),
                              "\(name): migrated store is not compatible with the current model")
            }
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }
    }
}
