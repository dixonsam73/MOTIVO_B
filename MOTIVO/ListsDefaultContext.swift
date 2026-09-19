import Foundation

/// Lists default: an EXPLICIT choice per (instrument, activity), whatever the number
/// of instruments. Nothing is inherited, assigned or transferred between contexts —
/// not on opening the Lists manager, switching, or adding/removing instruments.
///
/// One context is `(owner, activity, instrument?)`. With an instrument its keys are the
/// `…::inst:<uuid>` keys; with none (no instrument exists, or signed out) they are the
/// activity-only keys. Activity-only settings written while instruments existed have no
/// recorded instrument, so they are kept as they are and never applied to one.
///
/// Used by BOTH the Lists manager and the practice timer, so they read the same keys
/// in the same order.
struct ListsDefaultContext: Equatable {
    let ownerScope: String
    let activityRef: String
    let instrumentID: UUID?

    private var suffix: String { instrumentID.map { "::inst:" + $0.uuidString } ?? "" }
    var tasksKey: String { "practiceTasks_v1::" + ownerScope + "::" + activityRef + suffix }
    var autofillKey: String { "practiceTasks_autofill_enabled::" + ownerScope + "::" + activityRef + suffix }
    var defaultIDKey: String { tasksKey + "::default_set_id_v1" }

    enum Resolution: Equatable {
        /// The context's flag is explicitly false: nothing is applied.
        case off
        /// A default List assigned to this context, with at least one non-blank line.
        case list(SavedList)
        /// This context's own typed preset.
        case typed([SavedListLine])
        /// A legacy `[String]` preset for this context (applied even when empty).
        case legacyArray([String])
        case none
    }

    /// The timer's typed-preset contract: `text` required, `type` optional (missing or
    /// null means `.task`), an unknown `type` fails the decode.
    private struct PresetLine: Decodable {
        let text: String
        let type: TaskLineType?
    }

    /// Read only. THIS context's settings only, in the order the timer applies them.
    func resolve(defaults: UserDefaults, lists: [SavedList]) -> Resolution {
        if defaults.object(forKey: autofillKey) != nil, defaults.bool(forKey: autofillKey) == false {
            return .off
        }
        if let raw = defaults.string(forKey: defaultIDKey),
           let id = UUID(uuidString: raw),
           let list = lists.first(where: { $0.id == id }),
           list.items.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return .list(list)
        }
        if let data = defaults.data(forKey: tasksKey),
           let lines = try? JSONDecoder().decode([PresetLine].self, from: data), !lines.isEmpty {
            return .typed(lines.map { SavedListLine(text: $0.text, type: $0.type ?? .task) })
        }
        if let array = defaults.array(forKey: tasksKey) as? [String] {
            return .legacyArray(array)
        }
        return .none
    }

    /// An explicit select (`listID`) or deselect (`nil`) in the Lists manager, for THIS
    /// context only: the assignment, the context's preset snapshot, and its flag.
    func recordExplicitChoice(listID: UUID?, presetData: Data?, defaults: UserDefaults) {
        if let listID {
            defaults.set(listID.uuidString, forKey: defaultIDKey)
        } else {
            defaults.removeObject(forKey: defaultIDKey)
        }
        if let presetData { defaults.set(presetData, forKey: tasksKey) }
        defaults.set(listID != nil, forKey: autofillKey)
    }

    /// Which instrument's settings the Lists manager shows: the current explicit
    /// selection while it still exists; otherwise the profile's primary instrument
    /// (trimmed, case-insensitive name, as the timer matches it); otherwise the first.
    /// `nil` only when there are no instruments. Choosing what to SHOW writes nothing.
    static func effectiveInstrument(selected: UUID?, available: [(id: UUID, name: String)],
                                    primaryName: String?) -> UUID? {
        if let selected, available.contains(where: { $0.id == selected }) { return selected }
        if let primary = primaryName?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty,
           let match = available.first(where: { $0.name.caseInsensitiveCompare(primary) == .orderedSame }) {
            return match.id
        }
        return available.first?.id
    }
}
