import Foundation
import CoreData

// MARK: - Single-source activity helpers (safe, additive)
enum SessionActivity {
    // Activity name for headers/rows: prefer user's custom label, else enum label.
    static func name(for session: NSManagedObject) -> String {
        if let label = (session.value(forKey: "userActivityLabel") as? String)?.trimmedNonEmpty() {
            return label
        }
        // Fall back to enum label derived from persisted raw value.
        let raw = session.value(forKey: "activityType") as? Int16
        return enumLabel(for: raw)
    }

    // Activity description (user-typed). Empty string if not present.
    static func description(for session: NSManagedObject) -> String {
        return (session.value(forKey: "activityDetail") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // Header title: "<Instrument> : <ActivityName>"
    static func headerTitle(for session: NSManagedObject) -> String {
        let instrumentName = (session.value(forKeyPath: "instrument.name") as? String)?.trimmedNonEmpty() ?? "Instrument"
        return "\(instrumentName) : \(name(for: session))"
    }

    // Crumb line: "N min • <Instrument> • <ActivityName>"
    static func crumbLine(for session: NSManagedObject) -> String {
        let mins = Int(((session.value(forKey: "durationSeconds") as? Int64) ?? 0) / 60)
        let instrumentName = (session.value(forKeyPath: "instrument.name") as? String)?.trimmedNonEmpty() ?? ""
        let activity = name(for: session)
        return [mins > 0 ? "\(mins) min" : nil,
                instrumentName.isEmpty ? nil : instrumentName,
                activity].compactMap { $0 }.joined(separator: " • ")
    }

    // MARK: - NEW: Defaults & Feed title/subtitle helpers (P3)
    // Friendly generated description like "Morning Practice" based on timestamp and activity.
    static func defaultDescription(for session: NSManagedObject) -> String {
        let ts = (session.value(forKey: "timestamp") as? Date) ?? Date()
        let activityLabel = name(for: session) // this already resolves custom label if present
        let part = dayPart(for: ts)
        return "\(part) \(activityLabel)"
    }

    // True if the current description equals what defaultDescription(for:) would produce.
    static func isUsingDefaultDescription(for session: NSManagedObject) -> Bool {
        let desc = description(for: session).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else { return false }
        return desc.caseInsensitiveCompare(defaultDescription(for: session)) == .orderedSame
    }

    // Feed title according to rules.
    // D empty → Instrument + Activity
    // D == Default → Default description
    // D custom → Custom description
    static func feedTitle(for session: NSManagedObject) -> String {
        let d = description(for: session).trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return headerTitle(for: session) }
        if isUsingDefaultDescription(for: session) { return d }
        return d // custom
    }

    // Feed subtitle according to rules.
    // D empty → Time, Date
    // D == Default → Instrument, Time, Date
    // D custom → Instrument, Activity, Time, Date
    static func feedSubtitle(for session: NSManagedObject) -> String {
        let instrumentName = (session.value(forKeyPath: "instrument.name") as? String)?.trimmedNonEmpty() ?? "Instrument"
        let activityLabel = name(for: session)
        let ts = (session.value(forKey: "timestamp") as? Date) ?? Date()

        let (timeStr, dateStr) = timeAndDateStrings(for: ts)

        let d = description(for: session).trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty {
            return [timeStr, dateStr].joined(separator: ", ")
        } else if isUsingDefaultDescription(for: session) {
            return [instrumentName, timeStr, dateStr].joined(separator: ", ")
        } else {
            return [instrumentName, activityLabel, timeStr, dateStr].joined(separator: ", ")
        }
    }

    // MARK: - Internal enum label mapper (no dependency on scattered enums)
    private static func enumLabel(for raw: Int16?) -> String {
        switch raw {
        case 0: return "Practice"
        case 1: return "Rehearsal"
        case 2: return "Recording"
        case 3: return "Lesson"
        case 4: return "Performance"
        case 5: return "Writing"
        default: return "Practice"
        }
    }

    private static func dayPart(for date: Date) -> String {
        // Local time components
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour], from: date)
        let hour = comps.hour ?? 0
        switch hour {
        case 0...4: return "Late Night"
        case 5...11: return "Morning"
        case 12...17: return "Afternoon"
        default: return "Evening" // 18...23
        }
    }

    private static func timeAndDateStrings(for date: Date) -> (String, String) {
        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return (timeFormatter.string(from: date), dateFormatter.string(from: date))
    }
}

// MARK: - Small convenience
private extension String {
    func trimmedNonEmpty() -> String? {
        let v = trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
