import Foundation
@MainActor struct Loader {
 typealias SavedTaskSet = SavedList
 typealias LegacySavedTaskSet = LegacySavedList
 let defaults: UserDefaults
 let globalTaskSetsKey: String
 func normalizedTaskTemplateLines(from items: [SavedListLine]) -> [SavedListLine] { items }
 func normalizedTaskTemplateLines(from items: [String]) -> [SavedListLine] { items.map { SavedListLine(text:$0) } }
 func defaultImportedTaskSetName(from items: [String]) -> String { "fallback" }
 func textItems(from items: [SavedListLine]) -> [String] { items.map(\.text) }
 func legacyTaskSetKeysForMigration() -> [String] { [] }
    func loadSavedTaskSets() -> [SavedTaskSet] {
        let defaults = self.defaults
        var merged: [SavedTaskSet] = []
        var mergeIdentity = SavedListMergeIdentity()

        func merge(_ sets: [SavedTaskSet]) {
            for set in sets {
                let trimmedName = set.sourceSendID == nil ? set.name.trimmingCharacters(in: .whitespacesAndNewlines) : set.name
                let normalizedItems = set.sourceSendID == nil ? normalizedTaskTemplateLines(from: set.items) : set.items
                let contentSignature = trimmedName.lowercased() + "||" + normalizedItems.map { $0.type.rawValue + ":" + $0.text.lowercased() }.joined(separator: "\u{241E}")

                guard mergeIdentity.include(set, contentSignature: contentSignature) else { continue }
                merged.append(SavedTaskSet(id: set.id, name: trimmedName.isEmpty ? defaultImportedTaskSetName(from: textItems(from: normalizedItems)) : trimmedName, items: normalizedItems, sourceSendID: set.sourceSendID))
            }
        }

        if let data = defaults.data(forKey: globalTaskSetsKey) {
            if let decoded = try? JSONDecoder().decode([SavedTaskSet].self, from: data) {
                merge(decoded)
            } else if let legacyDecoded = try? JSONDecoder().decode([LegacySavedTaskSet].self, from: data) {
                merge(legacyDecoded.map { SavedTaskSet(id: $0.id, name: $0.name, items: normalizedTaskTemplateLines(from: $0.items)) })
            }
        }

        let legacyKeys = legacyTaskSetKeysForMigration()
        for key in legacyKeys {
            guard let data = defaults.data(forKey: key) else { continue }

            if let decoded = try? JSONDecoder().decode([SavedTaskSet].self, from: data) {
                merge(decoded)
                continue
            }

            if let legacyDecoded = try? JSONDecoder().decode([LegacySavedTaskSet].self, from: data) {
                merge(legacyDecoded.map { SavedTaskSet(id: $0.id, name: $0.name, items: normalizedTaskTemplateLines(from: $0.items)) })
            }
        }

        if let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: globalTaskSetsKey)
        }

        return merged
    }

}
@main struct Probe {
 @MainActor static func main() throws {
 let suite="EtudesIndependentAudit."+UUID().uuidString
 let d=UserDefaults(suiteName:suite)!
 defer { d.removePersistentDomain(forName:suite) }
 let key=SavedListLibrary.key(ownerScope:"synthetic")
 let damaged=Data("[{broken".utf8)
 d.set(damaged,forKey:key)
 do { _ = try SavedListLibrary.read(ownerScope:"synthetic",defaults:d); print("unexpected read") }
 catch { print("LIST adoption reader correctly refuses damaged library") }
 let loader=Loader(defaults:d,globalTaskSetsKey:key)
 print("LIST screen loader returned:",loader.loadSavedTaskSets().count)
 print("LIST original bytes preserved:",d.data(forKey:key)==damaged)
 print("LIST replaced bytes:",String(data:d.data(forKey:key)!,encoding:.utf8)!)
 let good=[SavedList(id:UUID(),name:"Control",items:[SavedListLine(text:"Scale")])]
 d.set(try JSONEncoder().encode(good),forKey:key)
 print("LIST valid control preserved:",loader.loadSavedTaskSets()==good)
 }
}
