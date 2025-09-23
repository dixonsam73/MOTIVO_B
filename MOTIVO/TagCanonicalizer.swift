////
//  TagCanonicalizer.swift
//  MOTIVO
//
//  Snapshot 7.5 → user-scoped helpers (explicit ownerUserID parameter)
//  Purpose: normalize, upsert, dedupe Tags per signed-in user without coupling to singletons.
//

import Foundation
import CoreData

enum TagCanonicalizer {

    // Normalize a free-form tag string into (key, display)
    // key: for case-insensitive matching; display: what we store/show
    static func normalize(_ raw: String) -> (key: String, display: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        return (key, trimmed)
    }

    /// Upserts a Tag by case-insensitive name **for a specific user**.
    /// - Parameters:
    ///   - ctx: NSManagedObjectContext
    ///   - raw: user-entered tag string
    ///   - ownerUserID: required current user id to scope the tag
    ///   - preferLatestDisplayCasing: if true and an existing tag is found with a different display casing,
    ///     we update the stored `name` to match the latest display casing. Default: false.
    /// - Returns: Tag (or nil if input trims to empty)
    @discardableResult
    static func upsert(
        in ctx: NSManagedObjectContext,
        name raw: String,
        ownerUserID: String,
        preferLatestDisplayCasing: Bool = false
    ) throws -> Tag? {
        let (key, display) = normalize(raw)
        guard !key.isEmpty else { return nil }

        let fr: NSFetchRequest<Tag> = Tag.fetchRequest()
        fr.fetchLimit = 1
        fr.predicate = NSPredicate(format: "(name =[c] %@) AND ownerUserID == %@", key, ownerUserID)

        if let existing = try ctx.fetch(fr).first {
            if preferLatestDisplayCasing, (existing.name ?? "") != display {
                existing.name = display
            }
            return existing
        } else {
            let t = Tag(context: ctx)
            // Required custom fields commonly used across the app
            if (t.value(forKey: "id") as? UUID) == nil { t.setValue(UUID(), forKey: "id") }
            t.name = display
            t.ownerUserID = ownerUserID
            return t
        }
    }

    /// Parse CSV of tags and upsert **for a specific user**.
    /// - Parameters:
    ///   - ctx: NSManagedObjectContext
    ///   - csv: comma-separated list like "jazz, arpeggios"
    ///   - ownerUserID: required user scope
    ///   - preferLatestDisplayCasing: see `upsert`
    /// - Returns: array of Tag objects (order follows CSV input)
    static func upsertCSV(
        in ctx: NSManagedObjectContext,
        csv: String,
        ownerUserID: String,
        preferLatestDisplayCasing: Bool = false
    ) throws -> [Tag] {
        let parts = csv
            .split(separator: ",")
            .map { String($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var results: [Tag] = []
        results.reserveCapacity(parts.count)

        for p in parts {
            if let t = try upsert(in: ctx, name: p, ownerUserID: ownerUserID, preferLatestDisplayCasing: preferLatestDisplayCasing) {
                results.append(t)
            }
        }
        return results
    }

    /// De-duplicate Tags **within a single user’s scope** by case-insensitive name.
    /// Keeps the first encountered tag as the "keeper", re-links all sessions to it, and deletes duplicates.
    /// - Parameters:
    ///   - ctx: NSManagedObjectContext
    ///   - ownerUserID: the user to operate on
    ///   - preferLatestDisplayCasing: if true, the keeper’s display casing will be updated to the “best”
    ///     (currently the first non-empty display seen among duplicates); tweak as needed.
    static func dedupe(
        in ctx: NSManagedObjectContext,
        ownerUserID: String,
        preferLatestDisplayCasing: Bool = false
    ) throws {
        let fr: NSFetchRequest<Tag> = Tag.fetchRequest()
        fr.predicate = NSPredicate(format: "ownerUserID == %@", ownerUserID)

        let tags = try ctx.fetch(fr)
        guard !tags.isEmpty else { return }

        var keeperForKey: [String: Tag] = [:]

        for tag in tags {
            let display = tag.name ?? ""
            let key = display.lowercased()
            guard !key.isEmpty else { continue }

            if let keeper = keeperForKey[key] {
                // Re-link sessions to keeper
                if let sessions = tag.sessions as? Set<Session> {
                    for s in sessions { keeper.addToSessions(s) }
                }
                // Optionally refine keeper’s display casing
                if preferLatestDisplayCasing, !display.isEmpty, keeper.name != display {
                    keeper.name = display
                }
                // Remove duplicate
                ctx.delete(tag)
            } else {
                keeperForKey[key] = tag
            }
        }

        if ctx.hasChanges {
            try ctx.save()
        }
    }
}
