// CHANGE-ID: 20251230_6A-PublishService-SessionIDOverload
// SCOPE: Step 6A — add sessionID overload; make local-only default; remove heuristics
// CHANGE-ID: 20251230_6A-PublishService-PreviewBackend
// CHANGE-ID: 20251230_210900-PublishService-NSLogPreviewGate
// SCOPE: Step 7 — add explicit logs for preview gate + ensure flush is attempted
// SCOPE: Step 6A — backend preview wiring for publish/unpublish (non-blocking)
// CHANGE-ID: v7.12B-PublishService-DebugGlobal-20251112_133247
// SCOPE: Add DEBUG helper to read other owners' published sets
// PublishService.swift
// CHANGE-ID: 20251110_190650-PublishService_v712A-MainActor
// SCOPE: v7.12A — Social Pilot (local-only). Main-actor updates to avoid cross-thread publishes.
// SEARCH-TOKEN: PUBLISH-SVC-712A
// CHANGE-ID: 20260119_132532_Step12_NotesPublishParity
// SCOPE: Populate publish payload notes from Core Data via objectID (no UI changes)
// SEARCH-TOKEN: NOTES-PUBLISH-PARITY-20260119

import Foundation
import CoreData
import Combine

/// Local-only publishing registry for v7.12A (no backend).
/// Stores a set of published session identifiers (objectID URI strings) per user.
/// Main-actor isolated to ensure @Published changes are always delivered from the main thread.
@MainActor
final class PublishService: ObservableObject {
    static let shared = PublishService()

    /// Published set for any future UI/diagnostics.
    @Published private(set) var publishedURIs: Set<String> = []

    /// The current user scope key (e.g., user UUID). Provided by app layer; falls back to device-local.
    var ownerKey: String {
        UserDefaults.standard.string(forKey: "PublishService.ownerKey") ?? "local-device"
    }

    /// Storage key composed with current ownerKey.
    private var storeKey: String { "publishedSessions_v1::" + ownerKey }

    private init() {
        load()
        NSLog("[PublishService] init — loaded %d published items (owner=%@)", publishedURIs.count, ownerKey)
    }

    // MARK: - Public API

    /// Publish or unpublish based on `shouldPublish`.
    /// - Parameters:
    ///   - objectID: The saved Core Data object ID for the session.
    ///   - shouldPublish: If true, record as published; if false, remove from registry.
    func publishIfNeeded(objectID: NSManagedObjectID, shouldPublish: Bool) {
        let uri = objectID.uriRepresentation().absoluteString

        var set = publishedURIs
        let changed: Bool
        if shouldPublish {
            changed = set.insert(uri).inserted
        } else {
            changed = set.remove(uri) != nil
        }
        guard changed else { return }

        // Persist first, then publish new value (all on main actor).
        persist(set)
        publishedURIs = set

        NSLog("[PublishService] %@ session → %@", shouldPublish ? "Published" : "Unpublished", uri)
    }

    /// Overload with explicit sessionID for backend preview wiring.
    /// Performs the same local registry update, then (in preview) enqueues or deletes via backend using the provided sessionID.
    func publishIfNeeded(context: NSManagedObjectContext, objectID: NSManagedObjectID, sessionID: UUID, shouldPublish: Bool) {
        // Compatibility wrapper (Step 8F): forward to context-based overload using provided context.
        publishIfNeeded(
            usingContext: context,
            objectID: objectID,
            sessionID: sessionID,
            shouldPublish: shouldPublish
        )
    }

    func publishIfNeeded(objectID: NSManagedObjectID, sessionID: UUID, shouldPublish: Bool) {
        let ctx = PersistenceController.shared.container.viewContext
        publishIfNeeded(usingContext: ctx, objectID: objectID, sessionID: sessionID, shouldPublish: shouldPublish)
    }

    func publishIfNeeded(usingContext context: NSManagedObjectContext, objectID: NSManagedObjectID, sessionID: UUID, shouldPublish: Bool) {
        let uri = objectID.uriRepresentation().absoluteString

        var set = publishedURIs
        let changed: Bool
        if shouldPublish {
            changed = set.insert(uri).inserted
        } else {
            changed = set.remove(uri) != nil
        }

        if changed {
            // Persist first, then publish new value (all on main actor).
            persist(set)
            publishedURIs = set

            NSLog("[PublishService] %@ session → %@", shouldPublish ? "Published" : "Unpublished", uri)
        }

        Task { @MainActor in
            // Always attempt to enqueue for public sessions; flush behavior depends on mode.
            // Build payload from Core Data using KVC to avoid importing model types here.
            var payload: SessionSyncQueue.PostPublishPayload? = nil

            // Early exit for backendPreview when publishing: do not build/enqueue legacy payload here.
            // Still flush so payloads enqueued via publish(payload: ...) are sent.
            if BackendEnvironment.shared.mode == .backendPreview, shouldPublish {
                await SessionSyncQueue.shared.flushNow()
                NSLog("[PublishService] [8F] backendPreview publishIfNeeded skipped legacy enqueue → %@", sessionID.uuidString)
                return
            }

            if shouldPublish {
                NSLog("[PublishService] enqueue gate • mode=%@ • shouldPublish=%@ • changed=%@ • sessionID=%@", String(describing: BackendEnvironment.shared.mode), shouldPublish ? "true" : "false", changed ? "true" : "false", sessionID.uuidString)

                var sID: UUID? = nil
                var sTimestamp: Date? = nil
                var sTitle: String? = nil
                var sDuration: Int? = nil
                // Removed line per instructions:
                // if hasAttr("activityType"), let val = obj.value(forKey: "activityType") as? String { sActivityType = val }
                var sActivityType: String? = nil
                var sActivityDetail: String? = nil
                var sInstrumentLabel: String? = nil
                var sMood: Int? = nil
                var sEffort: Int? = nil

                // Resolve the managed object directly via provided context and extract fields best-effort.
                let viewContext = context
                do {
                    let obj = try viewContext.existingObject(with: objectID)
                    // [8F] Force materialization to capture latest values from caller's context.
                    viewContext.refresh(obj, mergeChanges: true)
                    NSLog("[PublishService] [8F] snapshot materialized for session → %@", sessionID.uuidString)
                    func hasAttr(_ name: String) -> Bool { (obj.entity.attributesByName[name] != nil) }

                    if hasAttr("id"), let val = obj.value(forKey: "id") as? UUID { sID = val }
                    if hasAttr("timestamp"), let val = obj.value(forKey: "timestamp") as? Date { sTimestamp = val }
                    if hasAttr("title"), let val = obj.value(forKey: "title") as? String { sTitle = val }
                    if hasAttr("durationSeconds") {
                        if let val = obj.value(forKey: "durationSeconds") as? Int { sDuration = val }
                        else if let val64 = obj.value(forKey: "durationSeconds") as? Int64 { sDuration = Int(val64) }
                    }
                    if hasAttr("activityDetail"), let val = obj.value(forKey: "activityDetail") as? String { sActivityDetail = val }
                    if hasAttr("userInstrumentLabel"), let val = obj.value(forKey: "userInstrumentLabel") as? String { sInstrumentLabel = val }
                    if hasAttr("mood") {
                        if let val = obj.value(forKey: "mood") as? Int { sMood = val }
                        else if let val16 = obj.value(forKey: "mood") as? Int16 { sMood = Int(val16) }
                    }
                    if hasAttr("effort") {
                        if let val = obj.value(forKey: "effort") as? Int { sEffort = val }
                        else if let val16 = obj.value(forKey: "effort") as? Int16 { sEffort = Int(val16) }
                    }
                } catch {
                    // Ignore extraction errors; fallback to minimal payload below.
                }

                let focusValue: Int? = { return sMood ?? sEffort }()
                let mappedEffort: Int? = focusValue
                let mappedMood: Int? = nil

                let p = SessionSyncQueue.PostPublishPayload(
                    id: sessionID,
                    sessionID: sID,
                    sessionTimestamp: sTimestamp,
                    title: sTitle,
                    durationSeconds: sDuration,
                    activityType: sActivityType,
                    activityDetail: sActivityDetail,
                    instrumentLabel: sInstrumentLabel,
                    mood: mappedMood,
                    effort: mappedEffort
                )
                payload = p

                NSLog("[PublishService][8F] LEGACY publishIfNeeded path used • sessionID=%@", sessionID.uuidString)
                if let payload = payload {
                    SessionSyncQueue.shared.enqueue(payload)
                } else {
                    SessionSyncQueue.shared.enqueue(postID: sessionID)
                }
            }

            // Flush now – will upload in backendPreview and skip in localSimulation per existing semantics.
            await SessionSyncQueue.shared.flushNow()

            // Preserve delete behavior in backend preview when unpublishing.
            let mode = BackendEnvironment.shared.mode
            let hasBaseURL = (NetworkManager.shared.baseURL != nil)
            let configured = BackendConfig.isConfigured
            if !shouldPublish, (mode == .backendPreview) && hasBaseURL && configured {
                let result = await BackendEnvironment.shared.publish.deletePost(sessionID)
                switch result {
                case .success:
                    NSLog("[PublishService] Preview deletePost success → %@", sessionID.uuidString)
                case .failure(let error):
                    NSLog("[PublishService] Preview deletePost failed → %@ | error=%@", sessionID.uuidString, String(describing: error))
                }
            }

            if shouldPublish && (BackendEnvironment.shared.mode == .backendPreview) {
                NSLog("[PublishService] Preview enqueue + flush for published session → %@", sessionID.uuidString)
            }
        }
    }

    public func publish(
        payload: SessionSyncQueue.PostPublishPayload,
        objectID: NSManagedObjectID,
        shouldPublish: Bool
    ) {
        let uri = objectID.uriRepresentation().absoluteString

        var set = publishedURIs
        let changed: Bool
        if shouldPublish {
            changed = set.insert(uri).inserted
        } else {
            changed = set.remove(uri) != nil
        }
        if changed {
            persist(set)
            publishedURIs = set
            NSLog("[PublishService] %@ session → %@", shouldPublish ? "Published" : "Unpublished", uri)
        }

        Task { @MainActor in
            if shouldPublish {
                // Step 12 parity: enrich payload with Core Data Session.notes + areNotesPrivate via objectID.
                // This avoids UI changes (views can keep constructing payload without notes).
                var resolvedNotes: String? = nil
                var resolvedAreNotesPrivate: Bool = false

                do {
                    let viewContext = PersistenceController.shared.container.viewContext
                    let obj = try viewContext.existingObject(with: objectID)
                    viewContext.refresh(obj, mergeChanges: true)

                    func hasAttr(_ name: String) -> Bool { (obj.entity.attributesByName[name] != nil) }
                    if hasAttr("notes"), let val = obj.value(forKey: "notes") as? String {
                        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        resolvedNotes = trimmed.isEmpty ? nil : trimmed
                    }
                    if hasAttr("areNotesPrivate"), let val = obj.value(forKey: "areNotesPrivate") as? Bool {
                        resolvedAreNotesPrivate = val
                    }
                } catch {
                    // If we can't resolve notes, proceed with the incoming payload unchanged.
                }

                let effectivePayload = SessionSyncQueue.PostPublishPayload(
                    id: payload.id,
                    sessionID: payload.sessionID,
                    sessionTimestamp: payload.sessionTimestamp,
                    title: payload.title,
                    durationSeconds: payload.durationSeconds,
                    activityType: payload.activityType,
                    activityDetail: payload.activityDetail,
                    instrumentLabel: payload.instrumentLabel,
                    mood: payload.mood,
                    effort: payload.effort,
                    notes: resolvedNotes,
                    areNotesPrivate: resolvedAreNotesPrivate
                )

                NSLog("[PublishService][8F] enqueue payload keys • postID=%@ title=%@ dur=%@ act=%@ mood=%@ effort=%@ notes=%@ notesPrivate=%@",
                      effectivePayload.id.uuidString,
                      effectivePayload.title ?? "nil",
                      effectivePayload.durationSeconds != nil ? String(effectivePayload.durationSeconds!) : "nil",
                      effectivePayload.activityType ?? "nil",
                      effectivePayload.mood != nil ? String(effectivePayload.mood!) : "nil",
                      effectivePayload.effort != nil ? String(effectivePayload.effort!) : "nil",
                      effectivePayload.notes != nil ? "present" : "nil",
                      effectivePayload.areNotesPrivate ? "true" : "false")

                SessionSyncQueue.shared.enqueue(effectivePayload)
            }


            await SessionSyncQueue.shared.flushNow()

            let mode = BackendEnvironment.shared.mode
            let hasBaseURL = (NetworkManager.shared.baseURL != nil)
            let configured = BackendConfig.isConfigured
            if !shouldPublish, (mode == .backendPreview) && hasBaseURL && configured {
                let result = await BackendEnvironment.shared.publish.deletePost(payload.id)
                switch result {
                case .success:
                    NSLog("[PublishService] Preview deletePost success → %@", payload.id.uuidString)
                case .failure(let error):
                    NSLog("[PublishService] Preview deletePost failed → %@ | error=%@", payload.id.uuidString, String(describing: error))
                }
            }

            if shouldPublish && (BackendEnvironment.shared.mode == .backendPreview) {
                NSLog("[PublishService] Preview enqueue + flush for published session → %@", payload.id.uuidString)
            }
        }
    }

    func publish(objectID: NSManagedObjectID) {
        publishIfNeeded(objectID: objectID, shouldPublish: true)
    }

    func unpublish(objectID: NSManagedObjectID) {
        publishIfNeeded(objectID: objectID, shouldPublish: false)
    }

    /// Read-only query.
    func isPublished(objectID: NSManagedObjectID) -> Bool {
        let uri = objectID.uriRepresentation().absoluteString
        return publishedURIs.contains(uri)
    }

    // MARK: - Persistence

    private func load() {
        if let arr = UserDefaults.standard.array(forKey: storeKey) as? [String] {
            publishedURIs = Set(arr)
        } else {
            publishedURIs = []
        }
    }

    private func persist(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: storeKey)
    }

    // MARK: - Owner Scope

    /// Update the owner scope key (e.g., on login). Triggers a reload.
    func setOwnerKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "PublishService.ownerKey")
        load()
        NSLog("[PublishService] owner scope changed → %@ | published=%d", key, publishedURIs.count)
    }
#if DEBUG
    /// DEBUG: Check if an objectID is published by a specific owner (reads that owner's store directly).
    func debugIsPublishedBy(owner: String, objectID: NSManagedObjectID) -> Bool {
        let key = "publishedSessions_v1::" + owner
        let arr = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        let uri = objectID.uriRepresentation().absoluteString
        return arr.contains(uri)
    }
#endif
}
