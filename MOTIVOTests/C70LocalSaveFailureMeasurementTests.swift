//
//  C70LocalSaveFailureMeasurementTests.swift
//  MOTIVOTests
//
//  C-70 REMAINING GAPS — MEASUREMENT ONLY (M1–M4), 20 September 2026.
//
//  These tests exist to ANSWER four questions that the C-70 scope refuses to
//  assert without evidence. They are NOT acceptance tests for a design, and no
//  application code has been changed. They model `ProfileView.save()`'s actual
//  shape: the managed object is MUTATED FIRST and `ctx.save()` is attempted
//  AFTERWARDS, so a failure leaves pending in-memory changes.
//
//  M1  does a FAILED `ctx.save()` post `NSManagedObjectContextDidSave`?
//  M2  after a failed save, does a re-fetch in the SAME context (what `load()`
//      does) return the pending in-memory edit, or the stored value?
//  M3  what does a re-fetch in a FRESH context on the same coordinator return?
//  M4  PROXY ONLY — store teardown and reopen from disk. THIS IS NOT A PROCESS
//      KILL and is labelled as such wherever it is reported.
//
//  Every store is a disposable on-disk store under a unique temporary
//  directory, torn down in `tearDown`. Nothing touches the app's real store.
//

import XCTest
import CoreData
@testable import Etudes

final class C70LocalSaveFailureMeasurementTests: XCTestCase {

    private var dir: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c70-measure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("Measure.sqlite")
    }

    override func tearDownWithError() throws {
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Harness

    private func open(readOnly: Bool = false) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MOTIVO")
        let d = NSPersistentStoreDescription(url: storeURL)
        d.shouldAddStoreAsynchronously = false
        if readOnly { d.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption) }
        container.persistentStoreDescriptions = [d]
        var loadError: Error?
        container.loadPersistentStores { _, e in loadError = e }
        if let loadError { throw loadError }
        return container
    }

    /// Exactly `ProfileView.load()`'s read: one Profile, no owner predicate.
    private func fetchName(_ ctx: NSManagedObjectContext) throws -> String? {
        let r = NSFetchRequest<NSManagedObject>(entityName: "Profile")
        r.fetchLimit = 1
        return try ctx.fetch(r).first?.value(forKey: "name") as? String
    }

    @discardableResult
    private func seed(_ ctx: NSManagedObjectContext, name: String) throws -> NSManagedObject {
        let p = NSEntityDescription.insertNewObject(forEntityName: "Profile", into: ctx)
        p.setValue(UUID(), forKey: "id")
        p.setValue(name, forKey: "name")
        p.setValue("Guitar", forKey: "primaryInstrument")
        p.setValue(false, forKey: "defaultPrivacy")
        try ctx.save()
        return p
    }

    /// Writes the raw findings to a durable host path as well as stdout, because
    /// `print` from a test process is not retrievable from the result bundle.
    /// The path is overridable so nothing is hard-coded to one machine.
    private func report(_ lines: [String]) {
        let text = "===== C70 MEASUREMENT =====\n"
            + lines.map { "  \($0)" }.joined(separator: "\n")
            + "\n===========================\n"
        print(text)
        // OPT-IN only. The default is this run's own temporary directory, so a
        // routine suite never appends to anyone's machine-specific path; set
        // `C70_MEASUREMENT_OUT` to collect the raw findings somewhere durable.
        // The attachment is the always-available copy.
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        attachment.name = "c70-measurement"
        add(attachment)
        if let dest = ProcessInfo.processInfo.environment["C70_MEASUREMENT_OUT"] {
            let url = URL(fileURLWithPath: dest)
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (existing + text).write(to: url, atomically: true, encoding: .utf8)
        } else {
            let url = dir.appendingPathComponent("c70-measurements-raw.txt")
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (existing + text).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - M1 + M2, validation failure

    func testM1_M2_validationFailure_didSaveAndSameContextRefetch() throws {
        let container = try open()
        let ctx = container.viewContext
        let p = try seed(ctx, name: "STORED")

        var didSaveCount = 0
        let obs = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: ctx, queue: nil
        ) { _ in didSaveCount += 1 }
        defer { NotificationCenter.default.removeObserver(obs) }

        // ProfileView.save()'s shape: mutate, THEN attempt the save.
        p.setValue("EDITED", forKey: "name")
        p.setValue(nil, forKey: "primaryInstrument")   // forces validation failure

        var saveFailed = false
        var errorText = "none"
        do { try ctx.save() } catch { saveFailed = true; errorText = "\(error)" }

        let sameCtxName = try fetchName(ctx)
        let hasChanges = ctx.hasChanges

        report([
            "M1/M2 — VALIDATION FAILURE",
            "save failed                 : \(saveFailed)",
            "error                       : \(errorText.prefix(120))",
            "M1 DidSave notifications    : \(didSaveCount)",
            "M2 same-context re-fetch    : \(sameCtxName ?? "nil")",
            "context.hasChanges after    : \(hasChanges)"
        ])

        XCTAssertTrue(saveFailed, "harness must actually fail the save")
    }

    // MARK: - M1 + M2 + M3 + M4, store-level failure (the realistic one)

    func testM1_M2_M3_M4_readOnlyStoreFailure() throws {
        // Seed and close, so the file exists with STORED committed.
        do {
            let seedContainer = try open()
            try seed(seedContainer.viewContext, name: "STORED")
            for s in seedContainer.persistentStoreCoordinator.persistentStores {
                try seedContainer.persistentStoreCoordinator.remove(s)
            }
        }

        // Reopen READ-ONLY: the object graph stays valid, the WRITE fails.
        let container = try open(readOnly: true)
        let ctx = container.viewContext

        var didSaveCount = 0
        let obs = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: ctx, queue: nil
        ) { _ in didSaveCount += 1 }
        defer { NotificationCenter.default.removeObserver(obs) }

        let r = NSFetchRequest<NSManagedObject>(entityName: "Profile")
        r.fetchLimit = 1
        let p = try XCTUnwrap(try ctx.fetch(r).first)

        p.setValue("EDITED", forKey: "name")           // valid value, unwritable store

        var saveFailed = false
        var errorText = "none"
        do { try ctx.save() } catch { saveFailed = true; errorText = "\(error)" }

        let sameCtxName = try fetchName(ctx)
        let hasChanges = ctx.hasChanges

        // M3 — fresh context, SAME coordinator.
        let fresh = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        fresh.persistentStoreCoordinator = container.persistentStoreCoordinator
        let freshName = try fetchName(fresh)

        // M4 PROXY — tear the store down and reopen from disk.
        // NOT A PROCESS KILL. In-process teardown only.
        for s in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(s)
        }
        let reopened = try open()
        let reopenedName = try fetchName(reopened.viewContext)

        report([
            "M1/M2/M3/M4 — READ-ONLY STORE (write fails, graph valid)",
            "save failed                 : \(saveFailed)",
            "error                       : \(errorText.prefix(120))",
            "M1 DidSave notifications    : \(didSaveCount)",
            "M2 same-context re-fetch    : \(sameCtxName ?? "nil")",
            "context.hasChanges after    : \(hasChanges)",
            "M3 fresh-context re-fetch   : \(freshName ?? "nil")",
            "M4 PROXY reopen-from-disk   : \(reopenedName ?? "nil")   [NOT a process kill]"
        ])

        XCTAssertTrue(saveFailed, "harness must actually fail the save")
    }

    // MARK: - M5, recovery: does a LATER successful save commit the pending edit?

    /// The recovery claim in the scope depends on this. A failed save leaves the
    /// edit pending (M2); the question is whether the NEXT successful
    /// `ctx.save()` — from this screen's retry, or from anywhere else sharing
    /// the same view context — commits it.
    func testM5_laterSuccessfulSaveCommitsThePendingEdit() throws {
        let container = try open()
        let ctx = container.viewContext
        let p = try seed(ctx, name: "STORED")

        // Fail once, exactly as ProfileView.save() would: mutate, then fail.
        p.setValue("EDITED", forKey: "name")
        p.setValue(nil, forKey: "primaryInstrument")
        var firstFailed = false
        do { try ctx.save() } catch { firstFailed = true }

        // Repair only the UNRELATED cause of failure; do not re-apply the name.
        p.setValue("Guitar", forKey: "primaryInstrument")

        var secondSucceeded = false
        do { try ctx.save(); secondSucceeded = true } catch { }

        // Committed? Read through a FRESH context, which sees only stored data.
        let fresh = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        fresh.persistentStoreCoordinator = container.persistentStoreCoordinator
        let committed = try fetchName(fresh)

        report([
            "M5 — RECOVERY BY A LATER SUCCESSFUL SAVE",
            "first save failed           : \(firstFailed)",
            "second save succeeded       : \(secondSucceeded)",
            "committed name (fresh ctx)  : \(committed ?? "nil")",
            "note                        : the name was NOT re-applied before the second save"
        ])

        XCTAssertTrue(firstFailed, "harness must actually fail the first save")
    }
}
