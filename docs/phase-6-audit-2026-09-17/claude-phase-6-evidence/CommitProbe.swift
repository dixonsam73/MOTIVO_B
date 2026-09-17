import Foundation
import CoreData
@objc(ProbeSession) class Session: NSManagedObject {}
@objc(ProbeAttachment) class Attachment: NSManagedObject {
 class func fetchRequest() -> NSFetchRequest<Attachment> { NSFetchRequest(entityName:"Attachment") }
}
enum AttachmentKind { case image,audio,video }
struct StagedAttachment { let id:UUID;let data:Data;let kind:AttachmentKind;var selectedPages:[Int]?=nil }
enum AttachmentImportPolicy { static func fileExtension(for att:StagedAttachment)->String { "m4a" } }
enum PDFSelectedPagesStore { static func migratePages(from:UUID,stagedPages:[Int]?,to:UUID) {} }
enum AttachmentTitlePersistenceKeys { static func writeLocalTitle(_ title:String,kind:AttachmentKind,attachmentID:UUID) {} }
enum AttachmentStore {
 static func saveDataWithRollback(_ data:Data,suggestedName:String,ext:String) throws -> (path:String,rollback:()->Void) {
 // Deliberately fail the filesystem write by targeting an existing directory.
 let url=URL(fileURLWithPath:"/private/tmp/etudes-phase6-audit/commit-write-blocker")
 try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
 try data.write(to:url,options:.atomic)
 return (url.path,{})
 }
 static func addAttachment(kind:AttachmentKind,filePath:String,to:Session,isThumbnail:Bool,displayName:String?,ctx:NSManagedObjectContext) throws -> Attachment {
 Attachment(entity:ctx.persistentStoreCoordinator!.managedObjectModel.entitiesByName["Attachment"]!,insertInto:ctx)
 }
}
@MainActor final class Editor {
 var selectedThumbnailID:UUID?=nil
 var stagedAttachments:[StagedAttachment]=[]
 let probeDefaults:UserDefaults
 init(_ d:UserDefaults){probeDefaults=d}
 func setPrivate(id:UUID,url:URL?,_ flag:Bool) {}
 func surrogateURL(for att:StagedAttachment)->URL? { nil }
 func migratePrivacy(fromStagedID:UUID,stagedURL:URL?,toNewID:UUID?,newURL:URL) {}
    func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) -> [UUID: UUID] {
        let chosenThumbID = selectedThumbnailID
        // Ensure thumbnail implies included (staged privacy) before migration/commit
        if let tid = chosenThumbID, let thumb = stagedAttachments.first(where: { $0.id == tid }) {
            setPrivate(id: tid, url: surrogateURL(for: thumb), false)
        }

        // Map staged UUID → final Attachment UUID (used to persist isThumbnail correctly)
        var stagedToFinalID: [UUID: UUID] = [:]
        

        // Map staged UUID → final file URL (used to persist privacy on final keys)
        var stagedToFinalURL: [UUID: URL] = [:]
let namesKey = "stagedAudioNames_temp"
        let namesDict = (probeDefaults.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        let displayNamesKey = "stagedAttachmentDisplayNames_temp"
        let displayNamesDict = (probeDefaults.dictionary(forKey: displayNamesKey) as? [String: String]) ?? [:]

        // Read staged video titles captured during timer flow and define persisted store key
        let stagedVideoTitlesKey = "stagedVideoTitles_temp"
        let stagedVideoTitles: [String: String] = (probeDefaults.dictionary(forKey: stagedVideoTitlesKey) as? [String: String]) ?? [:]
        let persistedVideoTitlesKey = "persistedVideoTitles_v1"
        let persistedAudioTitlesKey = "persistedAudioTitles_v1"

        // Track rollback closures for files written during this commit attempt
        var rollbacks: [() -> Void] = []
        var createdAttachments: [Attachment] = []

        // 1) Write files using rollback-safe API and create Attachment objects
        for att in stagedAttachments {
            do {
                // C-77 — THE PERSISTED EXTENSION MUST DESCRIBE THE BYTES.
                // This site fabricated it from the kind, so an imported WAV
                // was written as `.m4a` and AVFoundation could not open it.
                let ext: String = AttachmentImportPolicy.fileExtension(for: att)
                let baseName: String
                if let custom = namesDict[att.id.uuidString], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    baseName = custom
                } else {
                    baseName = att.id.uuidString
                }
                let result = try AttachmentStore.saveDataWithRollback(att.data, suggestedName: baseName, ext: ext)
                rollbacks.append(result.rollback)

                let displayName = displayNamesDict[att.id.uuidString]
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                let created: Attachment = try AttachmentStore.addAttachment(kind: att.kind, filePath: result.path, to: session, isThumbnail: isThumb, displayName: displayName, ctx: ctx)
                if let finalID = (created.value(forKey: "id") as? UUID) {
                    stagedToFinalID[att.id] = finalID
                    PDFSelectedPagesStore.migratePages(from: att.id, stagedPages: att.selectedPages, to: finalID)
                }


                // Attempt to migrate privacy from staged keys (ID/Temp URL) to final keys (ID/File URL)
                let finalURL = URL(fileURLWithPath: result.path)
                
                stagedToFinalURL[att.id] = finalURL
let stagedURL = surrogateURL(for: att)
                migratePrivacy(fromStagedID: att.id, stagedURL: stagedURL, toNewID: (created.value(forKey: "id") as? UUID), newURL: finalURL)
                // Persist any staged AUDIO title so publish pipeline can round-trip it (remote display_name)
                if att.kind == .audio {
                    let stagedKey = att.id.uuidString
                    if let stagedTitleRaw = namesDict[stagedKey] {
                        let trimmed = stagedTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if let finalID = created.value(forKey: "id") as? UUID {
                                // C-47 — the shared, id-keyed writer.
                                AttachmentTitlePersistenceKeys.writeLocalTitle(trimmed, kind: .audio, attachmentID: finalID)
                            } else {
                                // Fallback (should be rare): key by saved filename stem
                                let stem = URL(fileURLWithPath: result.path).deletingPathExtension().lastPathComponent
                                var persisted = (probeDefaults.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
                                persisted[stem] = trimmed
                                probeDefaults.set(persisted, forKey: persistedAudioTitlesKey)
                            }
                        }
                    }
                }
                // Persist any staged video title so SessionDetailView can surface it later
                if att.kind == .video {
                    let stagedKey = att.id.uuidString
                    if let stagedTitleRaw = stagedVideoTitles[stagedKey] {
                        let trimmed = stagedTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            // Store under the final attachment UUID (preferred) if available; else fall back to file path stem
                            if let finalID = created.value(forKey: "id") as? UUID {
                                // C-47 — the shared, id-keyed writer.
                                AttachmentTitlePersistenceKeys.writeLocalTitle(trimmed, kind: .video, attachmentID: finalID)
                            } else {
                                // Fallback: use the created file path stem as a last resort
                                let stem = URL(fileURLWithPath: result.path).deletingPathExtension().lastPathComponent
                                var persisted = (probeDefaults.dictionary(forKey: persistedVideoTitlesKey) as? [String: String]) ?? [:]
                                persisted[stem] = trimmed
                                probeDefaults.set(persisted, forKey: persistedVideoTitlesKey)
                            }
                        }
                    }
                }

                createdAttachments.append(created)
            } catch {
                // If any write/add fails mid-loop, best-effort rollback files written so far and clear created objects from the context
                for rb in rollbacks { rb() }
                rollbacks.removeAll()
                // Delete any created attachments from the context (unsaved yet)
                for a in createdAttachments { ctx.delete(a) }
                createdAttachments.removeAll()
                print("Attachment commit failed: ", error)
                break
            }
        }

        // Resolve staged thumbnail UUID to final Attachment UUID
        let chosenFinalThumbID: UUID? = chosenThumbID.flatMap { stagedToFinalID[$0] }


        

        // Persist inclusion on FINAL keys for the chosen thumbnail attachment (ContentView relies on final URL keys)
        if let stagedID = chosenThumbID,
           let finalID = chosenFinalThumbID,
           let finalURL = stagedToFinalURL[stagedID] {
            setPrivate(id: finalID, url: finalURL, false)
        }
// 2) Update thumbnail flags across ALL attachments in this session to reflect selection
        do {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", session.objectID)
            let existing = try ctx.fetch(req)
            for a in existing {
                let id = (a.value(forKey: "id") as? UUID)
                let isThumb = (id != nil) && (id == chosenFinalThumbID)
                a.setValue(isThumb, forKey: "isThumbnail")
            }
        } catch {
            // If thumbnail update fails before save, it will be covered by context save error handling outside.
            print("Failed to update thumbnail flags: ", error)
        }

        // Note: Do not save the context here; caller will attempt save and handle rollback of files on failure.
        probeDefaults.removeObject(forKey: namesKey)
        probeDefaults.removeObject(forKey: displayNamesKey)
        probeDefaults.removeObject(forKey: stagedVideoTitlesKey)
        return stagedToFinalID
    }

}
enum BackupPolicy { static func exclude(_ url:URL){} }
@main struct Probe {
 @MainActor static func main() async throws {
 let suite="EtudesCommitProbe."+UUID().uuidString;let d=UserDefaults(suiteName:suite)!
 defer { d.removePersistentDomain(forName:suite) }
 let model=NSManagedObjectModel()
 let sessionEntity=NSEntityDescription();sessionEntity.name="Session";sessionEntity.managedObjectClassName=NSStringFromClass(Session.self)
 let attachmentEntity=NSEntityDescription();attachmentEntity.name="Attachment";attachmentEntity.managedObjectClassName=NSStringFromClass(Attachment.self)
 let relation=NSRelationshipDescription();relation.name="session";relation.destinationEntity=sessionEntity;relation.minCount=0;relation.maxCount=1;relation.isOptional=true
 attachmentEntity.properties=[relation];model.entities=[sessionEntity,attachmentEntity]
 let psc=NSPersistentStoreCoordinator(managedObjectModel:model);try psc.addPersistentStore(ofType:NSInMemoryStoreType,configurationName:nil,at:nil)
 let ctx=NSManagedObjectContext(concurrencyType:.mainQueueConcurrencyType);ctx.persistentStoreCoordinator=psc
 let session=Session(entity:sessionEntity,insertInto:ctx)
 let source=URL(fileURLWithPath:"/private/tmp/etudes-phase6-audit/synthetic-recording.m4a");try Data("synthetic recording bytes".utf8).write(to:source)
 let ref=try await StagingStore.saveNew(from:source,kind:.audio)
 let original=StagingStore.absoluteURL(for:ref)
 let editor=Editor(d);editor.stagedAttachments=[StagedAttachment(id:ref.id,data:try Data(contentsOf:original),kind:.audio)]
 let map=editor.commitStagedAttachments(to:session,ctx:ctx)
 try ctx.save()
 print("COMMIT failed attachment write returned normally; session saved; mapping count",map.count)
 print("COMMIT staged original before success cleanup",FileManager.default.fileExists(atPath:original.path))
 // Exact caller cleanup expression from PostRecordDetailsView:1929-1931.
 let consumedIDs:[UUID]=editor.stagedAttachments.map{$0.id}
 StagingStore.removeMany(ids:consumedIDs)
 print("COMMIT staged original after success cleanup",FileManager.default.fileExists(atPath:original.path))
 print("COMMIT saved attachment count",try ctx.count(for:NSFetchRequest<NSFetchRequestResult>(entityName:"Attachment")))
 }
}
