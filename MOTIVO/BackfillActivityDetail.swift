
import Foundation
import CoreData

/// Diagnostic + optional backfill for historical Sessions where `activityDetail` was left empty
/// by the old manual entry flow. This file is **NO-OP** unless you call its `run(...)` functions.
/// Safe to keep in the project; does not run automatically.
enum BackfillActivityDetail {

    /// Returns the number of sessions with an empty or nil `activityDetail`.
    static func countNeedingBackfill(in context: NSManagedObjectContext) throws -> Int {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Session")
        req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "activityDetail == nil"),
            NSPredicate(format: "activityDetail == ''")
        ])
        return try context.count(for: req)
    }

    /// Backfill strategy A (most conservative): do nothing (diagnostic only).
    /// You can call this just to log counts.
    static func logDiagnostics(in context: NSManagedObjectContext) {
        do {
            let count = try countNeedingBackfill(in: context)
            print("BackfillActivityDetail: \(count) sessions have empty activityDetail.")
        } catch {
            print("BackfillActivityDetail diagnostics failed: \(error)")
        }
    }

    /// Backfill strategy B (opt-in): copy `userActivityLabel` into `activityDetail` **only when detail is empty**.
    /// This is reversible and only fills blanks; it never overwrites non-empty descriptions.
    /// Call explicitly from a maintenance screen or debug action.
    static func copyLabelIntoEmptyDetail(in context: NSManagedObjectContext) throws -> Int {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Session")
        req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "activityDetail == nil"),
            NSPredicate(format: "activityDetail == ''")
        ])
        let items = try context.fetch(req)
        var changed = 0
        for s in items {
            let label = (s.value(forKey: "userActivityLabel") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !label.isEmpty {
                s.setValue(label, forKey: "activityDetail")
                changed += 1
            }
        }
        if context.hasChanges {
            try context.save()
        }
        return changed
    }
}
