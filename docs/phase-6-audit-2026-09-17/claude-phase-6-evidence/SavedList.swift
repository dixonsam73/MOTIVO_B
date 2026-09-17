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

    static func read(ownerScope: String, defaults: UserDefaults = .standard) throws -> [SavedList] {
        let storageKey = key(ownerScope: ownerScope)
        guard defaults.object(forKey: storageKey) != nil else { return [] }
        guard let data = defaults.data(forKey: storageKey) else { throw ConnectedListError.damagedLibrary }
        if let lists = try? JSONDecoder().decode([SavedList].self, from: data) { return lists }
        if let legacy = try? JSONDecoder().decode([LegacySavedList].self, from: data) {
            return legacy.map { SavedList(id: $0.id, name: $0.name, items: $0.items.map { SavedListLine(text: $0) }) }
        }
        throw ConnectedListError.damagedLibrary
    }

    static func adopt(_ payload: ConnectedListPayload, sourceSendID: UUID, ownerScope: String,
                      defaults: UserDefaults = .standard) throws -> SavedList {
        // Validate even when invoked without the file-decoding path.
        _ = try payload.encoded()
        var lists = try read(ownerScope: ownerScope, defaults: defaults)
        if let existing = lists.first(where: { $0.sourceSendID == sourceSendID }) { return existing }
        let copy = SavedList(id: UUID(), name: payload.name, items: payload.items.map {
            SavedListLine(text: $0.text, type: $0.type == .header ? .context : .task)
        }, sourceSendID: sourceSendID)
        lists.append(copy)
        defaults.set(try JSONEncoder().encode(lists), forKey: key(ownerScope: ownerScope))
        return copy
    }

    /// Adopted lists live only in v2. Mirroring them into a legacy context would
    /// resurrect a deleted copy when that context is opened later.
    static func legacyMirror(_ lists: [SavedList]) -> [SavedList] {
        lists.filter { $0.sourceSendID == nil }
    }
}

/// Existing migration deduplication applies to legacy/local templates only.
/// Received copies use local identity, never a content signature.
struct SavedListMergeIdentity {
    private var ids = Set<UUID>()
    private var signatures = Set<String>()

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
