//
//  StatsHelper.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 13/10/2025.
//
// CHANGE-ID: 20251013_184800-v79C
// SCOPE: Add segmented stats header (Week/Month/Year/Total) to Your Sessions card
// =============================================

import Foundation
import CoreData

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month, year, total
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .total: return "Total"
        }
    }
}

struct SessionStats {
    let count: Int
    let seconds: Int
}

enum StatsHelper {
    static func dateBounds(for range: StatsRange, now: Date = Date(), cal: Calendar = .current) -> (start: Date?, end: Date?) {
        switch range {
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
            return (start, end)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        case .year:
            let comps = cal.dateComponents([.year], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        case .total:
            return (nil, nil)
        }
    }
    
    static func fetchStats(in ctx: NSManagedObjectContext, range: StatsRange) throws -> SessionStats {
        let (start, end) = dateBounds(for: range)
        let req = NSFetchRequest<NSManagedObject>(entityName: "Session")
        var preds: [NSPredicate] = []
        if let s = start { preds.append(NSPredicate(format: "timestamp >= %@", s as NSDate)) }
        if let e = end { preds.append(NSPredicate(format: "timestamp < %@", e as NSDate)) }
        if !preds.isEmpty { req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds) }
        let objs = try ctx.fetch(req)
        let count = objs.count
        let seconds = objs.reduce(0) { $0 + ( $1.value(forKey: "durationSeconds") as? Int ?? 0 ) }
        return SessionStats(count: count, seconds: seconds)
    }
    
    static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: TimeInterval(seconds)) ?? "0m"
    }
}
