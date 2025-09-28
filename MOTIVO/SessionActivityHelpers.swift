
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

    // MARK: - Internal enum label mapper (no dependency on scattered enums)
    private static func enumLabel(for raw: Int16?) -> String {
        switch raw {
        case 0: return "Practice"
        case 1: return "Rehearsal"
        case 2: return "Recording"
        case 3: return "Lesson"
        case 4: return "Performance"
        default: return "Practice"
        }
    }
}

// MARK: - Small convenience
private extension String {
    func trimmedNonEmpty() -> String? {
        let v = trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
