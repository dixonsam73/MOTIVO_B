// CHANGE-ID: 20260406_094200_Ensembles_LocalOnlyFeedFilters_3c8f
// SCOPE: Add local-only EnsembleStore for personal followed-user feed filters. Persists per active local user via UserDefaults JSON; no backend, privacy, or follow-graph changes.
// SEARCH-TOKEN: 20260406_094200_Ensembles_LocalOnlyFeedFilters_3c8f

import Foundation
import Combine

public struct Ensemble: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var memberUserIDs: [String]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        memberUserIDs: [String],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.memberUserIDs = memberUserIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
public final class EnsembleStore: ObservableObject {
    public static let shared = EnsembleStore()

    @Published private(set) public var ensembles: [Ensemble] = []

    private init() {
        load()
    }

    private var currentUserID: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"),
           !override.isEmpty {
            return override.lowercased()
        }
        #endif
        return ((try? PersistenceController.shared.currentUserID) ?? "local-device").lowercased()
    }

    private var storageKey: String {
        "EnsembleStore.items::\(currentUserID)"
    }

    private func normalizeName(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizeMemberUserIDs(_ ids: [String]) -> [String] {
        Array(Set(
            ids
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        ))
        .sorted()
    }

    public func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            ensembles = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([Ensemble].self, from: data)
            ensembles = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            ensembles = []
            NSLog("[EnsembleStore] load failed: %@", String(describing: error))
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(ensembles)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            NSLog("[EnsembleStore] save failed: %@", String(describing: error))
        }
    }

    public func ensemble(id: String?) -> Ensemble? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !id.isEmpty else { return nil }
        return ensembles.first(where: { $0.id == id })
    }

    public func memberUserIDs(for ensembleID: String?) -> Set<String> {
        guard let ensemble = ensemble(id: ensembleID) else { return [] }
        return Set(normalizeMemberUserIDs(ensemble.memberUserIDs))
    }

    @discardableResult
    public func create(name: String, memberUserIDs: [String]) -> Ensemble? {
        let normalizedName = normalizeName(name)
        let normalizedMembers = normalizeMemberUserIDs(memberUserIDs)
        guard !normalizedName.isEmpty, normalizedMembers.count >= 2 else { return nil }

        let ensemble = Ensemble(name: normalizedName, memberUserIDs: normalizedMembers)
        ensembles.append(ensemble)
        ensembles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
        return ensemble
    }

    @discardableResult
    public func update(id: String, name: String, memberUserIDs: [String]) -> Ensemble? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = normalizeName(name)
        let normalizedMembers = normalizeMemberUserIDs(memberUserIDs)
        guard !normalizedID.isEmpty, !normalizedName.isEmpty, normalizedMembers.count >= 2 else { return nil }
        guard let index = ensembles.firstIndex(where: { $0.id == normalizedID }) else { return nil }

        ensembles[index].name = normalizedName
        ensembles[index].memberUserIDs = normalizedMembers
        ensembles[index].updatedAt = Date()
        ensembles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
        return ensemble(id: normalizedID)
    }

    public func delete(id: String) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ensembles.removeAll { $0.id == normalizedID }
        save()
    }
}
