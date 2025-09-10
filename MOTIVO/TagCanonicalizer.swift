//
//  TagCanonicalizer.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 10/09/2025.
//

import Foundation
import CoreData

enum TagCanonicalizer {
    /// Returns a canonical key (lowercased + trimmed) and display name preserving user casing.
    static func normalize(_ raw: String) -> (key: String, display: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        return (key, trimmed)
    }

    /// Upserts Tag by case-insensitive name. Returns the Tag (or nil if blank).
    static func upsert(in ctx: NSManagedObjectContext, name raw: String) throws -> Tag? {
        let (key, display) = normalize(raw)
        guard !key.isEmpty else { return nil }

        let fr: NSFetchRequest<Tag> = Tag.fetchRequest()
        fr.fetchLimit = 1
        fr.predicate = NSPredicate(format: "(name =[c] %@)", key)

        if let existing = try ctx.fetch(fr).first {
            if existing.name != display { existing.name = display }
            return existing
        } else {
            let t = Tag(context: ctx)
            t.id = UUID()
            t.name = display
            return t
        }
    }

    /// De-duplicate Tags whose names collide case-insensitively. Keeps the first, re-links sessions.
    static func dedupe(in ctx: NSManagedObjectContext) throws {
        let fr: NSFetchRequest<Tag> = Tag.fetchRequest()
        let tags = try ctx.fetch(fr)
        var buckets: [String: Tag] = [:] // lowercased -> keeper

        for tag in tags {
            let key = (tag.name ?? "").lowercased()
            if key.isEmpty { continue }
            if let keeper = buckets[key] {
                if let sessions = tag.sessions as? Set<Session> {
                    for s in sessions { keeper.addToSessions(s) }
                }
                ctx.delete(tag)
            } else {
                buckets[key] = tag
            }
        }
        if ctx.hasChanges { try ctx.save() }
    }

    /// Parses a comma-separated tag string and returns upserted Tag objects.
    static func upsertCSV(in ctx: NSManagedObjectContext, csv: String) throws -> [Tag] {
        let parts = csv.split(separator: ",").map { String($0) }
        var results: [Tag] = []
        for p in parts {
            if let t = try upsert(in: ctx, name: p) { results.append(t) }
        }
        return results
    }
}
