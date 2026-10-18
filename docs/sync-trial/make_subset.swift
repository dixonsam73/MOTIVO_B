// make_subset.swift — Checkpoint 2 of the private sync trial.
//
// Produces a representative subset of a copied Études container THROUGH CORE
// DATA, using the app's compiled model, so deleting an old Session cascades to
// its Attachments exactly as the app would. Works on a fresh copy; the
// downloaded original is never opened. Then removes Documents files no
// remaining Attachment references (Scores/ is kept untouched) and strips the
// device-specific scratch and Connected caches that must not travel.
//
// Usage: swift make_subset.swift <momd-path> <source-container> <subset-container> <cutoff YYYY-MM-DD>

import Foundation
import CoreData

let args = CommandLine.arguments
guard args.count == 5 else { fputs("usage: make_subset.swift <momd> <source> <subset> <cutoff>\n", stderr); exit(2) }
let momd = URL(fileURLWithPath: args[1])
let source = URL(fileURLWithPath: args[2])
let subset = URL(fileURLWithPath: args[3])
let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: "UTC")
guard let cutoff = formatter.date(from: args[4]) else { fputs("bad cutoff\n", stderr); exit(2) }
let fm = FileManager.default

// 1. Fresh copy of the parts that travel.
if fm.fileExists(atPath: subset.path) { try! fm.removeItem(at: subset) }
try! fm.createDirectory(at: subset.appendingPathComponent("Library"), withIntermediateDirectories: true)
for part in ["Documents", "Library/Application Support", "Library/Preferences"] {
    try! fm.copyItem(at: source.appendingPathComponent(part), to: subset.appendingPathComponent(part))
}

// 2. Strip what must not travel: scratch (staging, publish queue, timer),
//    Connected caches, received attachments, comments, and the backend ids in
//    UserDefaults. Attachment titles and the Scores index stay.
let support = subset.appendingPathComponent("Library/Application Support")
for scratch in ["MOTIVO", "ReceivedConnectedAttachments", "CommentsStore.json"] {
    try? fm.removeItem(at: support.appendingPathComponent(scratch))
}
let prefsDir = subset.appendingPathComponent("Library/Preferences")
for plist in (try? fm.contentsOfDirectory(at: prefsDir, includingPropertiesForKeys: nil)) ?? [] where plist.pathExtension == "plist" {
    guard var dict = NSDictionary(contentsOf: plist) as? [String: Any] else { continue }
    var removed: [String] = []
    for key in dict.keys where key == "backendUserID_v1" || key == "supabaseUserID_v1" || key == "PublishService.ownerKey"
        || key.hasPrefix("Debug.") || key.hasPrefix("PracticeTimer.") || key.hasPrefix("staged") {
        dict.removeValue(forKey: key); removed.append(key)
    }
    (dict as NSDictionary).write(to: plist, atomically: true)
    print("prefs \(plist.lastPathComponent): removed \(removed.sorted())")
}

// 3. Open the subset's store through Core Data with the app's model.
guard let model = NSManagedObjectModel(contentsOf: momd) else { fputs("model failed\n", stderr); exit(1) }
let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
let storeURL = support.appendingPathComponent("MOTIVO.sqlite")
let options: [String: Any] = [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
do { try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options) }
catch { fputs("store failed: \(error)\n", stderr); exit(1) }
let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
ctx.persistentStoreCoordinator = psc

func count(_ entity: String) -> Int { (try? ctx.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))) ?? 0 }
let before = (count("Session"), count("Attachment"))

// 4. Delete sessions before the cutoff; Session.attachments is Cascade.
let old = NSFetchRequest<NSManagedObject>(entityName: "Session")
old.predicate = NSPredicate(format: "timestamp < %@", cutoff as NSDate)
for session in try! ctx.fetch(old) { ctx.delete(session) }
try! ctx.save()
let after = (count("Session"), count("Attachment"))

// 5. Remove Documents files nothing references (Scores/ untouched).
let attachments = try! ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: "Attachment"))
let referenced = Set(attachments.compactMap { ($0.value(forKey: "fileURL") as? String).map { URL(fileURLWithPath: $0).lastPathComponent } })
let docs = subset.appendingPathComponent("Documents")
var removedFiles = 0, removedBytes: Int64 = 0
for item in (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? [] {
    if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
    if referenced.contains(item.lastPathComponent) { continue }
    removedBytes += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    try? fm.removeItem(at: item); removedFiles += 1
}

// 6. Leave the store checkpointed (no stale WAL) for the device.
try? psc.persistentStores.forEach { try psc.remove($0) }

print("sessions \(before.0) -> \(after.0); attachments \(before.1) -> \(after.1); removed \(removedFiles) unreferenced files (\(removedBytes / 1_000_000) MB); kept \(referenced.count) referenced files; cutoff \(args[4])")
