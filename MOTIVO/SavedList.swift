import Foundation

// Persisted raw values and defaults keys are intentionally unchanged.
enum TaskLineType: String, Codable {
    case task
    case context
}

struct SavedListLine: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var type: TaskLineType

    init(id: UUID = UUID(), text: String, type: TaskLineType = .task) {
        self.id = id
        self.text = text
        self.type = type
    }

    private enum CodingKeys: String, CodingKey { case id, text, type }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try values.decode(String.self, forKey: .text)
        type = try values.decodeIfPresent(TaskLineType.self, forKey: .type) ?? .task
    }
}

struct SavedList: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var items: [SavedListLine]
    // Local provenance only; never sent to another member or reported to the sender.
    var sourceSendID: UUID? = nil
}

struct LegacySavedList: Codable {
    let id: UUID
    var name: String
    var items: [String]
}

/// Immutable v1 transport. Local IDs, provenance and completion are not wire fields.
struct ConnectedListPayload: Codable, Equatable {
    static let mimeType = "application/vnd.etudes.list+json"
    static let maxBytes = 128 * 1024
    static let maxItems = 500

    enum LineType: String, Codable { case header, item }
    struct Line: Codable, Equatable {
        let text: String
        let type: LineType
    }

    let version: Int
    let name: String
    let items: [Line]

    init(list: SavedList) {
        version = 1
        name = list.name
        items = list.items.map { Line(text: $0.text, type: $0.type == .context ? .header : .item) }
    }

    func validated() throws -> Self {
        guard version == 1 else { throw ConnectedListError.unsupportedVersion }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 200, !items.isEmpty, items.count <= Self.maxItems,
              items.allSatisfy({ $0.text.count <= 4000 }) else {
            throw ConnectedListError.invalidList
        }
        return self
    }

    func encoded() throws -> Data {
        let data = try JSONEncoder().encode(validated())
        guard data.count <= Self.maxBytes else { throw ConnectedListError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maxBytes else { throw ConnectedListError.tooLarge }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}

enum ConnectedListError: LocalizedError {
    case unsupportedVersion, invalidList, tooLarge, damagedLibrary

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This list needs a newer version of Études."
        case .invalidList: return "This list could not be opened."
        case .tooLarge: return "This list is too large to send or open."
        case .damagedLibrary: return "Your saved lists could not be read. Nothing has been replaced."
        }
    }
}

/// Uses the existing owner-scoped library key. No network or Scores integration.
@MainActor
enum SavedListLibrary {
    static func key(ownerScope: String) -> String { "practiceTasks_saved_sets_v2::" + ownerScope }

    /// P6-I-04 / F-1. What the library is, as read. A read NEVER writes over
    /// anything it could not read.
    enum State: Equatable {
        case lists([SavedList])
        /// The canonical value is present but unreadable (wrong type or undecodable),
        /// or a legacy value that migration still needs is. Nothing is replaced, and
        /// the library must not be mutated until it is readable.
        case damaged
    }

    /// The canonical value after the one-time legacy migration. The migrated state
    /// and the lists are ONE stored value, written in one `set`, so neither can exist
    /// without the other: there is no separate marker that could be lost, or land,
    /// independently of the data. A bare array (either list shape) is the
    /// pre-migration form and is still read. Builds older than this one cannot read
    /// the envelope.
    struct Envelope: Codable, Equatable {
        static let currentVersion = 3
        let version: Int
        let lists: [SavedList]
    }

    enum Stored: Equatable {
        case absent
        case unmigrated([SavedList])
        case migrated([SavedList])
        case damaged
    }

    /// Classifies the canonical value without writing. An envelope with a version this
    /// build does not know is damaged (never overwritten), not an empty library.
    static func stored(ownerScope: String, defaults: UserDefaults) -> Stored {
        let storageKey = key(ownerScope: ownerScope)
        guard defaults.object(forKey: storageKey) != nil else { return .absent }
        guard let data = defaults.data(forKey: storageKey) else { return .damaged }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return envelope.version == Envelope.currentVersion ? .migrated(envelope.lists) : .damaged
        }
        return decode(data).map(Stored.unmigrated) ?? .damaged
    }

    private static func write(_ lists: [SavedList], ownerScope: String, defaults: UserDefaults) throws {
        let envelope = Envelope(version: Envelope.currentVersion, lists: lists)
        defaults.set(try JSONEncoder().encode(envelope), forKey: key(ownerScope: ownerScope))
    }

    /// EVERY legacy per-context library key of THIS owner — independent of which
    /// screen or context opens first, including deleted instruments or activities.
    /// The `::` boundary keeps owners isolated.
    static func legacyKeys(ownerScope: String, defaults: UserDefaults) -> [String] {
        let prefix = "practiceTasks_v1::" + ownerScope + "::"
        return defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix("::saved_sets_v1") }
            .sorted()
    }

    static func decode(_ data: Data) -> [SavedList]? {
        if let lists = try? JSONDecoder().decode([SavedList].self, from: data) { return lists }
        if let legacy = try? JSONDecoder().decode([LegacySavedList].self, from: data) {
            return legacy.map { SavedList(id: $0.id, name: $0.name, items: $0.items.map { SavedListLine(text: $0) }) }
        }
        return nil
    }

    /// Reads the library, first completing the one-time owner-wide migration of
    /// legacy keys if it has not run. Canonical entries are kept VERBATIM — never
    /// re-normalised or de-duplicated, so intentional duplicate copies survive;
    /// de-duplication applies only to imported legacy candidates. Once migrated,
    /// legacy keys are never read again (so a deleted List cannot come back), and
    /// they are left in place, not deleted.
    static func load(ownerScope: String, defaults: UserDefaults = .standard) -> State {
        let canonical: [SavedList]
        switch stored(ownerScope: ownerScope, defaults: defaults) {
        case .damaged: return .damaged
        case .migrated(let lists): return .lists(lists)
        case .unmigrated(let lists): canonical = lists
        case .absent: canonical = []
        }

        var candidates: [SavedList] = []
        for legacyKey in legacyKeys(ownerScope: ownerScope, defaults: defaults) {
            // A legacy value that cannot be read blocks migration: its content may be
            // the only copy, so nothing is marked migrated and nothing is replaced.
            guard let data = defaults.data(forKey: legacyKey), let lists = decode(data) else { return .damaged }
            candidates.append(contentsOf: lists)
        }

        var identity = SavedListMergeIdentity()
        for list in canonical { identity.seed(list, contentSignature: importSignature(list)) }
        var result = canonical
        for candidate in candidates where candidate.sourceSendID == nil {
            let imported = normalisedImport(candidate)
            if identity.include(imported, contentSignature: importSignature(imported)) { result.append(imported) }
        }
        // One write carries both the lists and the migrated state.
        do { try write(result, ownerScope: ownerScope, defaults: defaults) } catch { return .damaged }
        return .lists(result)
    }

    static func read(ownerScope: String, defaults: UserDefaults = .standard) throws -> [SavedList] {
        guard case .lists(let lists) = load(ownerScope: ownerScope, defaults: defaults) else {
            throw ConnectedListError.damagedLibrary
        }
        return lists
    }

    /// Applies a screen's edit to a FRESH load rather than writing its possibly
    /// stale array: ids the screen removed from its snapshot are deleted; ids the
    /// screen added are appended; ids that were in the snapshot but are no longer in
    /// the library were deleted elsewhere and are NOT reintroduced; entries the screen
    /// did not change keep the library's current value (a newer edit elsewhere wins);
    /// entries the screen never saw (for example an adoption) are kept. Refuses a
    /// damaged library.
    @discardableResult
    static func commit(snapshot: [SavedList], updated: [SavedList], ownerScope: String,
                       defaults: UserDefaults = .standard) throws -> [SavedList] {
        guard case .lists(let fresh) = load(ownerScope: ownerScope, defaults: defaults) else {
            throw ConnectedListError.damagedLibrary
        }
        let before = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let updatedIDs = Set(updated.map(\.id))
        var result: [SavedList] = updated.compactMap { list in
            guard let seen = before[list.id] else { return list }        // added by this screen
            guard let latest = current[list.id] else { return nil }      // deleted elsewhere
            return list == seen ? latest : list                          // unchanged here: keep newer value
        }
        result.append(contentsOf: fresh.filter { before[$0.id] == nil && !updatedIDs.contains($0.id) })
        try write(result, ownerScope: ownerScope, defaults: defaults)
        return result
    }

    private static func normalisedImport(_ list: SavedList) -> SavedList {
        let items = list.items.compactMap { line -> SavedListLine? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : SavedListLine(id: line.id, text: text, type: line.type)
        }
        let trimmed = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? String(items.first?.text.prefix(40) ?? "List") : trimmed
        return SavedList(id: list.id, name: name, items: items, sourceSendID: nil)
    }

    private static func importSignature(_ list: SavedList) -> String {
        list.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "||"
            + list.items.map { $0.type.rawValue + ":" + $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .joined(separator: "\u{241E}")
    }

    static func adopt(_ payload: ConnectedListPayload, sourceSendID: UUID, ownerScope: String,
                      defaults: UserDefaults = .standard) throws -> SavedList {
        // Validate even when invoked without the file-decoding path.
        _ = try payload.encoded()
        let lists = try read(ownerScope: ownerScope, defaults: defaults)
        if let existing = lists.first(where: { $0.sourceSendID == sourceSendID }) { return existing }
        let copy = SavedList(id: UUID(), name: payload.name, items: payload.items.map {
            SavedListLine(text: $0.text, type: $0.type == .header ? .context : .task)
        }, sourceSendID: sourceSendID)
        try commit(snapshot: lists, updated: lists + [copy], ownerScope: ownerScope, defaults: defaults)
        return copy
    }
}

/// Existing migration deduplication applies to legacy/local templates only.
/// Received copies use local identity, never a content signature.
struct SavedListMergeIdentity {
    private var ids = Set<UUID>()
    private var signatures = Set<String>()

    /// Registers an existing canonical entry WITHOUT filtering it, so imports are
    /// checked against it while canonical duplicates are all kept.
    mutating func seed(_ list: SavedList, contentSignature: String) {
        ids.insert(list.id)
        if list.sourceSendID == nil { signatures.insert(contentSignature) }
    }

    mutating func include(_ list: SavedList, contentSignature: String) -> Bool {
        guard !ids.contains(list.id) else { return false }
        if list.sourceSendID == nil {
            guard !signatures.contains(contentSignature) else { return false }
            signatures.insert(contentSignature)
        }
        ids.insert(list.id)
        return true
    }
}
