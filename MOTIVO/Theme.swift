// CHANGE-ID: 20260429_142200_Theme_ThreadTintMode
// SCOPE: Add Thread as a selectable tint mode and Auto fallback source while preserving existing Instrument/Activity tint behaviour.
//
//  Theme.swift
//  MOTIVO
//
//  v7.8 DesignLite — lightweight design tokens and tiny modifiers
//  - No behaviour changes; purely visual.
//  - Inspired by the Aulo mock: warm grouped background, soft cards, subtle stroke, single accent.
//
//  [ROLLBACK ANCHOR] v7.8 DesignLite — pre
//
import SwiftUI

// CHANGE-ID: 20260429_155500_Theme_ThreadTintSlots
// SCOPE: Theme.swift — add two restrained ThreadTint palette slots (slate, clay) and extend thread assignment order only; no tint logic/UI changes.
// SEARCH-TOKEN: 20260429_155500_Theme_ThreadTintSlots

import CoreData

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 12
        static let l:  CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        static let card: CGFloat = 16     // standard card padding
        static let section: CGFloat = 16  // vertical spacing between sections
        static let inline: CGFloat = 8    // inline spacing between elements
    }

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 12
    }

    enum Colors {
        static func background(_ scheme: ColorScheme) -> Color {
            scheme == .dark
            ? Color(red: 0.06, green: 0.06, blue: 0.07)
            : Color(red: 0.96, green: 0.95, blue: 0.92)
        }

        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : Color(red: 0.99, green: 0.99, blue: 0.97)
        }

        static func stroke(_ scheme: ColorScheme) -> Color {
            scheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
        }

        static func cardStroke(_ scheme: ColorScheme) -> Color {
            stroke(scheme)
        }

        static var accent: Color {
            Color(red: 0.32, green: 0.38, blue: 0.46)
        }

        static var primaryAction: Color {
            Color(red: 0.16, green: 0.38, blue: 0.29)
        }

        static var secondaryText: Color {
            Color.primary.opacity(0.55)
        }
    }

    enum Text {
        static var pageTitle: Font { .title3.weight(.semibold) }
        static var sectionHeader: Font { .subheadline.weight(.semibold) }
        static var body: Font { .subheadline }
        static var meta: Font { .footnote }
    }

    enum TintMode: String, CaseIterable, Identifiable {
        case auto
        case instrument
        case activity
        case thread
        case off

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .auto: return "Auto"
            case .instrument: return "Instrument"
            case .activity: return "Activity"
            case .thread: return "Thread"
            case .off: return "Off"
            }
        }
    }

    enum ResolvedTintSource: String {
        case instrument
        case activity
        case thread
        case off
    }

    struct ResolvedTint {
        let source: ResolvedTintSource
        let instrumentLabel: String?
        let activityLabel: String?
        let threadLabel: String?

        init(
            source: ResolvedTintSource,
            instrumentLabel: String?,
            activityLabel: String?,
            threadLabel: String? = nil
        ) {
            self.source = source
            self.instrumentLabel = instrumentLabel
            self.activityLabel = activityLabel
            self.threadLabel = threadLabel
        }

        var isDormant: Bool {
            source == .off
        }

        func fill(
            ownerID: String?,
            scheme: ColorScheme,
            strength: InstrumentTint.Strength,
            shouldAssignIfNeeded: Bool = true
        ) -> Color {
            switch source {
            case .instrument:
                return InstrumentTint.surfaceFill(
                    for: instrumentLabel,
                    ownerID: ownerID,
                    scheme: scheme,
                    strength: strength,
                    shouldAssignIfNeeded: shouldAssignIfNeeded
                )
            case .activity:
                return ActivityTint.surfaceFill(
                    for: activityLabel,
                    scheme: scheme,
                    strength: strength
                )
            case .thread:
                return ThreadTint.surfaceFill(
                    for: threadLabel,
                    ownerID: ownerID,
                    scheme: scheme,
                    strength: strength,
                    shouldAssignIfNeeded: shouldAssignIfNeeded
                )
            case .off:
                return Colors.surface(scheme)
            }
        }

        func stroke(
            ownerID: String?,
            scheme: ColorScheme,
            strength: InstrumentTint.Strength,
            shouldAssignIfNeeded: Bool = true
        ) -> Color {
            switch source {
            case .instrument:
                return InstrumentTint.cardStroke(
                    for: instrumentLabel,
                    ownerID: ownerID,
                    scheme: scheme,
                    strength: strength,
                    shouldAssignIfNeeded: shouldAssignIfNeeded
                )
            case .activity:
                return ActivityTint.cardStroke(
                    for: activityLabel,
                    scheme: scheme,
                    strength: strength
                )
            case .thread:
                return ThreadTint.cardStroke(
                    for: threadLabel,
                    ownerID: ownerID,
                    scheme: scheme,
                    strength: strength,
                    shouldAssignIfNeeded: shouldAssignIfNeeded
                )
            case .off:
                return Colors.cardStroke(scheme)
            }
        }

        func accent(
            ownerID: String?,
            scheme: ColorScheme,
            shouldAssignIfNeeded: Bool = true
        ) -> Color? {
            switch source {
            case .instrument:
                return InstrumentTint.visibleAccentColor(
                    for: instrumentLabel,
                    ownerID: ownerID,
                    scheme: scheme,
                    shouldAssignIfNeeded: shouldAssignIfNeeded
                )
            case .activity:
                return ActivityTint.visibleAccentColor(
                    for: activityLabel,
                    scheme: scheme
                )
            case .thread:
                return ThreadTint.visibleAccentColor(
                    for: threadLabel,
                    ownerID: ownerID,
                    scheme: scheme,
                    shouldAssignIfNeeded: shouldAssignIfNeeded
                )
            case .off:
                return nil
            }
        }
    }

    struct VariationSummary {
        let distinctCount: Int
        let topCount: Int
        let secondMostUsedCount: Int
        let totalCount: Int

        var hasMeaningfulVariation: Bool {
            secondMostUsedCount >= 2
        }
    }

    private static let autoTintSourceDefaultsKey = "appSettings_autoResolvedTintSource"

    static func normalizedDistinctCounts(_ rawCounts: [String: Int]) -> [String: Int] {
        rawCounts.reduce(into: [String: Int]()) { partial, entry in
            let trimmed = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, entry.value > 0 else { return }
            partial[trimmed, default: 0] += entry.value
        }
    }

    static func usageCounts<S: Sequence>(labels: S) -> [String: Int] where S.Element == String? {
        labels.reduce(into: [String: Int]()) { partial, label in
            guard let label else { return }
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            partial[trimmed, default: 0] += 1
        }
    }

    static func usageCounts<S: Sequence>(labels: S) -> [String: Int] where S.Element == String {
        labels.reduce(into: [String: Int]()) { partial, label in
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            partial[trimmed, default: 0] += 1
        }
    }

    static func variationSummary(from rawCounts: [String: Int]) -> VariationSummary {
        let counts = normalizedDistinctCounts(rawCounts)
        let sorted = counts.values.sorted(by: >)
        return VariationSummary(
            distinctCount: counts.count,
            topCount: sorted.first ?? 0,
            secondMostUsedCount: sorted.dropFirst().first ?? 0,
            totalCount: sorted.reduce(0, +)
        )
    }

    static func meaningfulInstrumentVariation(from counts: [String: Int]) -> Bool {
        variationSummary(from: counts).hasMeaningfulVariation
    }

    static func meaningfulActivityVariation(from counts: [String: Int]) -> Bool {
        let summary = variationSummary(from: counts)
        return summary.secondMostUsedCount >= 2 || summary.distinctCount >= 3
    }

    static func meaningfulThreadVariation(from counts: [String: Int]) -> Bool {
        variationSummary(from: counts).hasMeaningfulVariation
    }

    static func instrumentVariationStronglyOutweighsActivity(
        instrumentCounts: [String: Int],
        activityCounts: [String: Int]
    ) -> Bool {
        let instrumentSummary = variationSummary(from: instrumentCounts)
        let activitySummary = variationSummary(from: activityCounts)

        guard instrumentSummary.hasMeaningfulVariation else { return false }
        guard instrumentSummary.distinctCount >= 3 else { return false }
        guard instrumentSummary.secondMostUsedCount >= 3 else { return false }
        guard activitySummary.totalCount > 0 else { return true }

        let activityDominance = Double(activitySummary.topCount) / Double(activitySummary.totalCount)
        let instrumentSpreadClearlyStronger = instrumentSummary.secondMostUsedCount >= max(3, activitySummary.secondMostUsedCount * 3)

        return activityDominance >= 0.85 && instrumentSpreadClearlyStronger
    }

    static func storedAutoTintSource() -> ResolvedTintSource? {
        guard let rawValue = UserDefaults.standard.string(forKey: autoTintSourceDefaultsKey) else {
            return nil
        }
        return ResolvedTintSource(rawValue: rawValue)
    }

    static func setStoredAutoTintSource(_ source: ResolvedTintSource?) {
        let defaults = UserDefaults.standard
        if let source {
            defaults.set(source.rawValue, forKey: autoTintSourceDefaultsKey)
        } else {
            defaults.removeObject(forKey: autoTintSourceDefaultsKey)
        }
    }

    static func resolvedAutoTintSource(
        instrumentCounts: [String: Int],
        activityCounts: [String: Int],
        threadCounts: [String: Int] = [:],
        persistedSource: ResolvedTintSource? = nil,
        persistResult: Bool = true
    ) -> ResolvedTintSource {
        let instrumentMeaningful = meaningfulInstrumentVariation(from: instrumentCounts)
        let activityMeaningful = meaningfulActivityVariation(from: activityCounts)
        let threadMeaningful = meaningfulThreadVariation(from: threadCounts)
        let currentSource = persistedSource ?? storedAutoTintSource()

        let fallbackSource: ResolvedTintSource = threadMeaningful ? .thread : .off

        let resolved: ResolvedTintSource
        switch currentSource {
        case .instrument:
            if instrumentMeaningful {
                resolved = .instrument
            } else if activityMeaningful {
                resolved = .activity
            } else {
                resolved = fallbackSource
            }

        case .activity:
            if instrumentMeaningful && instrumentVariationStronglyOutweighsActivity(
                instrumentCounts: instrumentCounts,
                activityCounts: activityCounts
            ) {
                resolved = .instrument
            } else if activityMeaningful {
                resolved = .activity
            } else if instrumentMeaningful {
                resolved = .instrument
            } else {
                resolved = fallbackSource
            }

        case .thread:
            if threadMeaningful && !instrumentMeaningful && !activityMeaningful {
                resolved = .thread
            } else if instrumentMeaningful {
                resolved = .instrument
            } else if activityMeaningful {
                resolved = .activity
            } else {
                resolved = .off
            }

        case .off, .none:
            if instrumentMeaningful {
                resolved = .instrument
            } else if activityMeaningful {
                resolved = .activity
            } else {
                resolved = fallbackSource
            }
        }

        if persistResult {
            setStoredAutoTintSource(resolved)
        }
        return resolved
    }

    static func resolvedTintSource(
        tintMode: TintMode,
        activeInstrumentCount: Int,
        activeActivityCount: Int,
        activeThreadCount: Int = 0
    ) -> ResolvedTintSource {
        switch tintMode {
        case .off:
            return .off
        case .auto:
            if activeInstrumentCount > 1 {
                return .instrument
            }
            if activeInstrumentCount == 1 && activeActivityCount > 1 {
                return .activity
            }
            if activeInstrumentCount <= 1 && activeActivityCount <= 1 && activeThreadCount > 1 {
                return .thread
            }
            return .off
        case .instrument:
            return activeInstrumentCount > 1 ? .instrument : .off
        case .activity:
            return activeActivityCount > 1 ? .activity : .off
        case .thread:
            return activeThreadCount > 1 ? .thread : .off
        }
    }

    static func resolvedTintSource(
        tintMode: TintMode,
        instrumentCounts: [String: Int],
        activityCounts: [String: Int],
        threadCounts: [String: Int] = [:],
        persistedAutoSource: ResolvedTintSource? = nil,
        persistAutoSource: Bool = true
    ) -> ResolvedTintSource {
        switch tintMode {
        case .off:
            return .off
        case .instrument:
            return meaningfulInstrumentVariation(from: instrumentCounts) ? .instrument : .off
        case .activity:
            return meaningfulActivityVariation(from: activityCounts) ? .activity : .off
        case .thread:
            return meaningfulThreadVariation(from: threadCounts) ? .thread : .off
        case .auto:
            return resolvedAutoTintSource(
                instrumentCounts: instrumentCounts,
                activityCounts: activityCounts,
                threadCounts: threadCounts,
                persistedSource: persistedAutoSource,
                persistResult: persistAutoSource
            )
        }
    }

    static func resolvedTint(
        instrument: String?,
        activity: String?,
        thread: String? = nil,
        tintMode: TintMode,
        activeInstrumentCount: Int,
        activeActivityCount: Int,
        activeThreadCount: Int = 0
    ) -> ResolvedTint {
        let source = resolvedTintSource(
            tintMode: tintMode,
            activeInstrumentCount: activeInstrumentCount,
            activeActivityCount: activeActivityCount,
            activeThreadCount: activeThreadCount
        )

        return ResolvedTint(
            source: source,
            instrumentLabel: instrument,
            activityLabel: activity,
            threadLabel: thread
        )
    }

    static func resolvedTint(
        instrument: String?,
        activity: String?,
        thread: String? = nil,
        tintMode: TintMode,
        instrumentCounts: [String: Int],
        activityCounts: [String: Int],
        threadCounts: [String: Int] = [:],
        persistedAutoSource: ResolvedTintSource? = nil,
        persistAutoSource: Bool = true
    ) -> ResolvedTint {
        let source = resolvedTintSource(
            tintMode: tintMode,
            instrumentCounts: instrumentCounts,
            activityCounts: activityCounts,
            threadCounts: threadCounts,
            persistedAutoSource: persistedAutoSource,
            persistAutoSource: persistAutoSource
        )

        return ResolvedTint(
            source: source,
            instrumentLabel: instrument,
            activityLabel: activity,
            threadLabel: thread
        )
    }

    enum InstrumentTint {
        enum Slot: Int, CaseIterable {
            case neutralAnchor = 0
            case coolDeep = 1
            case rose = 2
            case apricot = 3
            case sage = 4
            case lavender = 5
        }

        enum Strength {
            case pickerStrong
            case cardMedium
            case cardMediumLight
            case cardLight
            case monthBar
        }

        private static let defaultsKeyPrefix = "theme.instrumentTint.slotMap.v1"
        private static let aliasMap: [String: String] = [
            "bass": "bass guitar",
            "vocals": "voice"
        ]

        static func normalizedLabel(_ label: String?) -> String? {
            guard let label else { return nil }
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let folded = trimmed
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()

            if let alias = aliasMap[folded] {
                return alias
            }
            return folded
        }

        static func slot(
            for instrumentLabel: String?,
            ownerID: String?,
            shouldAssignIfNeeded: Bool = true
        ) -> Slot? {
            guard let normalized = normalizedLabel(instrumentLabel) else { return nil }

            if isPrimaryInstrumentLabel(normalized, ownerID: ownerID) {
                return .coolDeep
            }

            let namespace = namespaceKey(ownerID: ownerID)
            var map = slotMap(ownerID: ownerID)

            if let existing = map[normalized], let slot = Slot(rawValue: existing) {
                return slot
            }

            guard shouldAssignIfNeeded else { return nil }

            let nextSlot = nextAvailableSlot(from: map)
            map[normalized] = nextSlot.rawValue
            UserDefaults.standard.set(map, forKey: namespace)
            return nextSlot
        }

        static func visibleSlot(
            for instrumentLabel: String?,
            ownerID: String?,
            shouldAssignIfNeeded: Bool = true
        ) -> Slot? {
            guard let normalized = normalizedLabel(instrumentLabel) else { return nil }
            guard let slot = slot(for: normalized, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return nil
            }

            let distinctCount = effectiveVisibleSlotCount(ownerID: ownerID)
            guard distinctCount > 1 else { return .neutralAnchor }

            if isPrimaryInstrumentLabel(normalized, ownerID: ownerID) {
                return .coolDeep
            }
            return slot
        }

        static func surfaceFill(
            for instrumentLabel: String?,
            ownerID: String?,
            scheme: ColorScheme,
            strength: Strength,
            shouldAssignIfNeeded: Bool = true
        ) -> Color {
            let base = Theme.Colors.surface(scheme)
            guard let slot = visibleSlot(for: instrumentLabel, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return base
            }
            guard slot != .neutralAnchor else {
                return base
            }
            return blendedSurface(base: base, overlay: paletteColor(for: slot, scheme: scheme), amount: blendAmount(for: strength, slot: slot, scheme: scheme))
        }

        static func cardStroke(
            for instrumentLabel: String?,
            ownerID: String?,
            scheme: ColorScheme,
            strength: Strength,
            shouldAssignIfNeeded: Bool = true
        ) -> Color {
            let baseStroke = Theme.Colors.cardStroke(scheme)
            guard let slot = visibleSlot(for: instrumentLabel, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return baseStroke
            }
            guard slot != .neutralAnchor else {
                return baseStroke
            }
            return blendedSurface(base: baseStroke, overlay: paletteColor(for: slot, scheme: scheme), amount: strokeBlendAmount(for: strength, scheme: scheme))
        }

        static func visibleAccentColor(
            for instrumentLabel: String?,
            ownerID: String?,
            scheme: ColorScheme,
            shouldAssignIfNeeded: Bool = true
        ) -> Color? {
            guard let slot = visibleSlot(for: instrumentLabel, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return nil
            }
            guard slot != .neutralAnchor else {
                return nil
            }
            return paletteColor(for: slot, scheme: scheme)
        }

        static func hasMultipleMappedInstruments(ownerID: String?) -> Bool {
            effectiveVisibleSlotCount(ownerID: ownerID) > 1
        }

        static func debugSlotMap(ownerID: String?) -> [String: Int] {
            slotMap(ownerID: ownerID)
        }

        private static func namespaceKey(ownerID: String?) -> String {
            let normalizedOwner = ownerID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let normalizedOwner, !normalizedOwner.isEmpty {
                return "\(defaultsKeyPrefix).\(normalizedOwner)"
            }
            return "\(defaultsKeyPrefix).__anonymous__"
        }

        private static func slotMap(ownerID: String?) -> [String: Int] {
            let namespace = namespaceKey(ownerID: ownerID)
            let rawMap = UserDefaults.standard.dictionary(forKey: namespace) as? [String: Int] ?? [:]
            let primaryLabel = normalizedPrimaryInstrumentLabel(ownerID: ownerID)
            let sanitized = sanitizedSlotMap(rawMap, primaryLabel: primaryLabel)
            if sanitized != rawMap {
                UserDefaults.standard.set(sanitized, forKey: namespace)
            }
            return sanitized
        }

        private static func sanitizedSlotMap(_ rawMap: [String: Int], primaryLabel: String?) -> [String: Int] {
            let orderedLabels = rawMap.keys.sorted { lhs, rhs in
                let leftValue = rawMap[lhs] ?? Int.max
                let rightValue = rawMap[rhs] ?? Int.max
                if leftValue != rightValue { return leftValue < rightValue }
                return lhs < rhs
            }

            var cleaned: [String: Int] = [:]
            var pending: [String] = []
            var usedVisibleSlots = Set<Int>()

            for label in orderedLabels {
                if label == primaryLabel { continue }
                guard let rawValue = rawMap[label], let slot = Slot(rawValue: rawValue) else { continue }

                switch slot {
                case .neutralAnchor, .coolDeep:
                    pending.append(label)
                case .rose, .apricot, .sage, .lavender:
                    if usedVisibleSlots.contains(slot.rawValue) {
                        pending.append(label)
                    } else {
                        cleaned[label] = slot.rawValue
                        usedVisibleSlots.insert(slot.rawValue)
                    }
                }
            }

            for label in pending {
                let nextSlot = nextAvailableSlot(from: cleaned)
                cleaned[label] = nextSlot.rawValue
            }

            return cleaned
        }

        private static func normalizedPrimaryInstrumentLabel(ownerID: String?) -> String? {
            let viewContext = PersistenceController.shared.container.viewContext
            let request = NSFetchRequest<NSManagedObject>(entityName: "Profile")
            request.fetchLimit = 1

            do {
                if let profile = try viewContext.fetch(request).first {
                    let name = profile.value(forKey: "primaryInstrument") as? String
                    return normalizedLabel(name)
                }
            } catch {
                return nil
            }

            return nil
        }

        private static func isPrimaryInstrumentLabel(_ normalizedLabel: String, ownerID: String?) -> Bool {
            normalizedLabel == normalizedPrimaryInstrumentLabel(ownerID: ownerID)
        }

        private static func effectiveVisibleSlotCount(ownerID: String?) -> Int {
            let mapCount = Set(slotMap(ownerID: ownerID).values).count
            let primaryCount = normalizedPrimaryInstrumentLabel(ownerID: ownerID) == nil ? 0 : 1
            return mapCount + primaryCount
        }

        private static let visibleAssignmentPriority: [Slot] = [
            .rose,
            .sage,
            .apricot,
            .lavender
        ]

        private static func nextAvailableSlot(from map: [String: Int]) -> Slot {
            let usedVisibleSlots = visibleAssignmentPriority.filter { usedSlot in
                Set(map.values).contains(usedSlot.rawValue)
            }

            for slot in visibleAssignmentPriority where !usedVisibleSlots.contains(slot) {
                return slot
            }

            let usedCount = usedVisibleSlots.count
            guard !visibleAssignmentPriority.isEmpty else { return .lavender }
            return visibleAssignmentPriority[usedCount % visibleAssignmentPriority.count]
        }

        private static func paletteColor(for slot: Slot, scheme: ColorScheme) -> Color {
            switch (slot, scheme) {
            case (.neutralAnchor, _):
                return Theme.Colors.surface(scheme)
            case (.coolDeep, .light):
                return Color(red: 0.70, green: 0.76, blue: 0.82)
            case (.coolDeep, .dark):
                return Color(red: 0.31, green: 0.37, blue: 0.43)
            case (.rose, .light):
                return Color(red: 0.89, green: 0.81, blue: 0.84)
            case (.rose, .dark):
                return Color(red: 0.43, green: 0.34, blue: 0.38)
            case (.apricot, .light):
                return Color(red: 0.90, green: 0.82, blue: 0.75)
            case (.apricot, .dark):
                return Color(red: 0.45, green: 0.36, blue: 0.30)
            case (.sage, .light):
                return Color(red: 0.79, green: 0.85, blue: 0.80)
            case (.sage, .dark):
                return Color(red: 0.33, green: 0.40, blue: 0.35)
            case (.lavender, .light):
                return Color(red: 0.84, green: 0.81, blue: 0.88)
            case (.lavender, .dark):
                return Color(red: 0.38, green: 0.34, blue: 0.43)
            }
        }

        private static func blendAmount(for strength: Strength, slot: Slot, scheme: ColorScheme) -> CGFloat {
            guard slot != .neutralAnchor else { return 0 }
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.42
            case (.pickerStrong, .dark): return 0.34
            case (.cardMedium, .light): return 0.32
            case (.cardMedium, .dark): return 0.24
            case (.cardMediumLight, .light): return 0.20
            case (.cardMediumLight, .dark): return 0.18
            case (.cardLight, .light): return 0.14
            case (.cardLight, .dark): return 0.14
            case (.monthBar, .light): return 0.24
            case (.monthBar, .dark): return 0.20
            }
        }

        private static func strokeBlendAmount(for strength: Strength, scheme: ColorScheme) -> CGFloat {
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.28
            case (.pickerStrong, .dark): return 0.24
            case (.cardMedium, .light): return 0.22
            case (.cardMedium, .dark): return 0.18
            case (.cardMediumLight, .light): return 0.14
            case (.cardMediumLight, .dark): return 0.13
            case (.cardLight, .light): return 0.10
            case (.cardLight, .dark): return 0.10
            case (.monthBar, .light): return 0.16
            case (.monthBar, .dark): return 0.14
            }
        }

        private static func blendedSurface(base: Color, overlay: Color, amount: CGFloat) -> Color {
            guard amount > 0 else { return base }

            #if canImport(UIKit)
            let baseUIColor = UIColor(base)
            let overlayUIColor = UIColor(overlay)
            return Color(uiColor: mix(base: baseUIColor, overlay: overlayUIColor, amount: amount))
            #elseif canImport(AppKit)
            let baseNSColor = NSColor(base)
            let overlayNSColor = NSColor(overlay)
            return Color(mix(base: baseNSColor, overlay: overlayNSColor, amount: amount))
            #else
            return overlay.opacity(amount)
            #endif
        }

        #if canImport(UIKit)
        private static func mix(base: UIColor, overlay: UIColor, amount: CGFloat) -> UIColor {
            let clamped = max(0, min(1, amount))
            var baseR: CGFloat = 0
            var baseG: CGFloat = 0
            var baseB: CGFloat = 0
            var baseA: CGFloat = 0
            var overlayR: CGFloat = 0
            var overlayG: CGFloat = 0
            var overlayB: CGFloat = 0
            var overlayA: CGFloat = 0

            guard base.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA),
                  overlay.getRed(&overlayR, green: &overlayG, blue: &overlayB, alpha: &overlayA) else {
                return base
            }

            return UIColor(
                red: baseR + (overlayR - baseR) * clamped,
                green: baseG + (overlayG - baseG) * clamped,
                blue: baseB + (overlayB - baseB) * clamped,
                alpha: baseA + (overlayA - baseA) * clamped
            )
        }
        #endif

        #if canImport(AppKit)
        private static func mix(base: NSColor, overlay: NSColor, amount: CGFloat) -> NSColor {
            let clamped = max(0, min(1, amount))
            guard let baseRGB = base.usingColorSpace(.deviceRGB),
                  let overlayRGB = overlay.usingColorSpace(.deviceRGB) else {
                return base
            }

            return NSColor(
                red: baseRGB.redComponent + (overlayRGB.redComponent - baseRGB.redComponent) * clamped,
                green: baseRGB.greenComponent + (overlayRGB.greenComponent - baseRGB.greenComponent) * clamped,
                blue: baseRGB.blueComponent + (overlayRGB.blueComponent - baseRGB.blueComponent) * clamped,
                alpha: baseRGB.alphaComponent + (overlayRGB.alphaComponent - baseRGB.alphaComponent) * clamped
            )
        }
        #endif
    }


    enum ThreadTint {
        enum Slot: Int, CaseIterable {
            case coolDeep = 1
            case rose = 2
            case apricot = 3
            case sage = 4
            case lavender = 5
            case slate = 6
            case clay = 7
        }

        private static let defaultsKeyPrefix = "theme.threadTint.slotMap.v1"

        static func normalizedLabel(_ label: String?) -> String? {
            guard let label else { return nil }
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            return trimmed
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
        }

        static func slot(
            for threadLabel: String?,
            ownerID: String?,
            shouldAssignIfNeeded: Bool = true
        ) -> Slot? {
            guard let normalized = normalizedLabel(threadLabel) else { return nil }

            let namespace = namespaceKey(ownerID: ownerID)
            var map = slotMap(ownerID: ownerID)

            if let existing = map[normalized], let slot = Slot(rawValue: existing) {
                return slot
            }

            guard shouldAssignIfNeeded else { return nil }

            let nextSlot = nextAvailableSlot(from: map)
            map[normalized] = nextSlot.rawValue
            UserDefaults.standard.set(map, forKey: namespace)
            return nextSlot
        }

        static func surfaceFill(
            for threadLabel: String?,
            ownerID: String?,
            scheme: ColorScheme,
            strength: InstrumentTint.Strength,
            shouldAssignIfNeeded: Bool = true
        ) -> Color {
            let base = Theme.Colors.surface(scheme)
            guard let slot = slot(for: threadLabel, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return base
            }
            return blendedSurface(base: base, overlay: paletteColor(for: slot, scheme: scheme), amount: blendAmount(for: strength, scheme: scheme))
        }

        static func cardStroke(
            for threadLabel: String?,
            ownerID: String?,
            scheme: ColorScheme,
            strength: InstrumentTint.Strength,
            shouldAssignIfNeeded: Bool = true
        ) -> Color {
            let baseStroke = Theme.Colors.cardStroke(scheme)
            guard let slot = slot(for: threadLabel, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return baseStroke
            }
            return blendedSurface(base: baseStroke, overlay: paletteColor(for: slot, scheme: scheme), amount: strokeBlendAmount(for: strength, scheme: scheme))
        }

        static func visibleAccentColor(
            for threadLabel: String?,
            ownerID: String?,
            scheme: ColorScheme,
            shouldAssignIfNeeded: Bool = true
        ) -> Color? {
            guard let slot = slot(for: threadLabel, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return nil
            }
            return paletteColor(for: slot, scheme: scheme)
        }

        static func debugSlotMap(ownerID: String?) -> [String: Int] {
            slotMap(ownerID: ownerID)
        }

        private static func namespaceKey(ownerID: String?) -> String {
            let normalizedOwner = ownerID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let normalizedOwner, !normalizedOwner.isEmpty {
                return "\(defaultsKeyPrefix).\(normalizedOwner)"
            }
            return "\(defaultsKeyPrefix).__anonymous__"
        }

        private static func slotMap(ownerID: String?) -> [String: Int] {
            let namespace = namespaceKey(ownerID: ownerID)
            let rawMap = UserDefaults.standard.dictionary(forKey: namespace) as? [String: Int] ?? [:]
            let sanitized = sanitizedSlotMap(rawMap)
            if sanitized != rawMap {
                UserDefaults.standard.set(sanitized, forKey: namespace)
            }
            return sanitized
        }

        private static func sanitizedSlotMap(_ rawMap: [String: Int]) -> [String: Int] {
            let orderedLabels = rawMap.keys.sorted { lhs, rhs in
                let leftValue = rawMap[lhs] ?? Int.max
                let rightValue = rawMap[rhs] ?? Int.max
                if leftValue != rightValue { return leftValue < rightValue }
                return lhs < rhs
            }

            var cleaned: [String: Int] = [:]
            var pending: [String] = []
            var usedVisibleSlots = Set<Int>()

            for label in orderedLabels {
                guard let rawValue = rawMap[label], let slot = Slot(rawValue: rawValue) else { continue }

                if usedVisibleSlots.contains(slot.rawValue) {
                    pending.append(label)
                } else {
                    cleaned[label] = slot.rawValue
                    usedVisibleSlots.insert(slot.rawValue)
                }
            }

            for label in pending {
                let nextSlot = nextAvailableSlot(from: cleaned)
                cleaned[label] = nextSlot.rawValue
            }

            return cleaned
        }

        private static let visibleAssignmentPriority: [Slot] = [
            .coolDeep,
            .rose,
            .sage,
            .apricot,
            .lavender,
            .slate,
            .clay
        ]

        private static func nextAvailableSlot(from map: [String: Int]) -> Slot {
            let usedVisibleSlots = visibleAssignmentPriority.filter { usedSlot in
                Set(map.values).contains(usedSlot.rawValue)
            }

            for slot in visibleAssignmentPriority where !usedVisibleSlots.contains(slot) {
                return slot
            }

            let usedCount = usedVisibleSlots.count
            guard !visibleAssignmentPriority.isEmpty else { return .lavender }
            return visibleAssignmentPriority[usedCount % visibleAssignmentPriority.count]
        }

        private static func paletteColor(for slot: Slot, scheme: ColorScheme) -> Color {
            switch (slot, scheme) {
            case (.coolDeep, .light):
                return Color(red: 0.70, green: 0.76, blue: 0.82)
            case (.coolDeep, .dark):
                return Color(red: 0.31, green: 0.37, blue: 0.43)
            case (.rose, .light):
                return Color(red: 0.89, green: 0.81, blue: 0.84)
            case (.rose, .dark):
                return Color(red: 0.43, green: 0.34, blue: 0.38)
            case (.apricot, .light):
                return Color(red: 0.90, green: 0.82, blue: 0.75)
            case (.apricot, .dark):
                return Color(red: 0.45, green: 0.36, blue: 0.30)
            case (.sage, .light):
                return Color(red: 0.79, green: 0.85, blue: 0.80)
            case (.sage, .dark):
                return Color(red: 0.33, green: 0.40, blue: 0.35)
            case (.lavender, .light):
                return Color(red: 0.84, green: 0.81, blue: 0.88)
            case (.lavender, .dark):
                return Color(red: 0.38, green: 0.34, blue: 0.43)
            case (.slate, .light):
                return Color(red: 0.78, green: 0.82, blue: 0.76)
            case (.slate, .dark):
                return Color(red: 0.34, green: 0.39, blue: 0.32)
            case (.clay, .light):
                return Color(red: 0.86, green: 0.78, blue: 0.72)
            case (.clay, .dark):
                return Color(red: 0.42, green: 0.34, blue: 0.29)
            }
        }

        private static func blendAmount(for strength: InstrumentTint.Strength, scheme: ColorScheme) -> CGFloat {
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.42
            case (.pickerStrong, .dark): return 0.34
            case (.cardMedium, .light): return 0.32
            case (.cardMedium, .dark): return 0.24
            case (.cardMediumLight, .light): return 0.20
            case (.cardMediumLight, .dark): return 0.18
            case (.cardLight, .light): return 0.14
            case (.cardLight, .dark): return 0.14
            case (.monthBar, .light): return 0.24
            case (.monthBar, .dark): return 0.20
            }
        }

        private static func strokeBlendAmount(for strength: InstrumentTint.Strength, scheme: ColorScheme) -> CGFloat {
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.28
            case (.pickerStrong, .dark): return 0.24
            case (.cardMedium, .light): return 0.22
            case (.cardMedium, .dark): return 0.18
            case (.cardMediumLight, .light): return 0.14
            case (.cardMediumLight, .dark): return 0.13
            case (.cardLight, .light): return 0.10
            case (.cardLight, .dark): return 0.10
            case (.monthBar, .light): return 0.16
            case (.monthBar, .dark): return 0.14
            }
        }

        private static func blendedSurface(base: Color, overlay: Color, amount: CGFloat) -> Color {
            guard amount > 0 else { return base }

            #if canImport(UIKit)
            let baseUIColor = UIColor(base)
            let overlayUIColor = UIColor(overlay)
            return Color(uiColor: mix(base: baseUIColor, overlay: overlayUIColor, amount: amount))
            #elseif canImport(AppKit)
            let baseNSColor = NSColor(base)
            let overlayNSColor = NSColor(overlay)
            return Color(mix(base: baseNSColor, overlay: overlayNSColor, amount: amount))
            #else
            return overlay.opacity(amount)
            #endif
        }

        #if canImport(UIKit)
        private static func mix(base: UIColor, overlay: UIColor, amount: CGFloat) -> UIColor {
            let clamped = max(0, min(1, amount))
            var baseR: CGFloat = 0
            var baseG: CGFloat = 0
            var baseB: CGFloat = 0
            var baseA: CGFloat = 0
            var overlayR: CGFloat = 0
            var overlayG: CGFloat = 0
            var overlayB: CGFloat = 0
            var overlayA: CGFloat = 0

            guard base.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA),
                  overlay.getRed(&overlayR, green: &overlayG, blue: &overlayB, alpha: &overlayA) else {
                return base
            }

            return UIColor(
                red: baseR + (overlayR - baseR) * clamped,
                green: baseG + (overlayG - baseG) * clamped,
                blue: baseB + (overlayB - baseB) * clamped,
                alpha: baseA + (overlayA - baseA) * clamped
            )
        }
        #endif

        #if canImport(AppKit)
        private static func mix(base: NSColor, overlay: NSColor, amount: CGFloat) -> NSColor {
            let clamped = max(0, min(1, amount))
            guard let baseRGB = base.usingColorSpace(.deviceRGB),
                  let overlayRGB = overlay.usingColorSpace(.deviceRGB) else {
                return base
            }

            return NSColor(
                red: baseRGB.redComponent + (overlayRGB.redComponent - baseRGB.redComponent) * clamped,
                green: baseRGB.greenComponent + (overlayRGB.greenComponent - baseRGB.greenComponent) * clamped,
                blue: baseRGB.blueComponent + (overlayRGB.blueComponent - baseRGB.blueComponent) * clamped,
                alpha: baseRGB.alphaComponent + (overlayRGB.alphaComponent - baseRGB.alphaComponent) * clamped
            )
        }
        #endif
    }

    enum ActivityTint {
        enum Slot {
            case practice
            case rehearsal
            case lesson
            case performance
            case recording
            case custom
        }

        private static let aliasMap: [String: String] = [
            "practise": "practice",
            "record": "recording",
            "recorded": "recording",
            "performance prep": "performance",
            "rehearse": "rehearsal",
            "lesson / coaching": "lesson",
            "coaching": "lesson"
        ]

        static func normalizedLabel(_ label: String?) -> String? {
            guard let label else { return nil }
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let folded = trimmed
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()

            if let alias = aliasMap[folded] {
                return alias
            }
            return folded
        }

        static func slot(for activityLabel: String?) -> Slot? {
            guard let normalized = normalizedLabel(activityLabel) else { return nil }

            switch normalized {
            case "practice":
                return .practice
            case "rehearsal":
                return .rehearsal
            case "lesson":
                return .lesson
            case "performance":
                return .performance
            case "recording":
                return .recording
            default:
                return .custom
            }
        }

        static func surfaceFill(
            for activityLabel: String?,
            scheme: ColorScheme,
            strength: InstrumentTint.Strength
        ) -> Color {
            let base = Theme.Colors.surface(scheme)
            guard let slot = slot(for: activityLabel) else {
                return base
            }

            return blendedSurface(
                base: base,
                overlay: paletteColor(for: slot, scheme: scheme),
                amount: blendAmount(for: strength, scheme: scheme)
            )
        }

        static func cardStroke(
            for activityLabel: String?,
            scheme: ColorScheme,
            strength: InstrumentTint.Strength
        ) -> Color {
            let baseStroke = Theme.Colors.cardStroke(scheme)
            guard let slot = slot(for: activityLabel) else {
                return baseStroke
            }

            return blendedSurface(
                base: baseStroke,
                overlay: paletteColor(for: slot, scheme: scheme),
                amount: strokeBlendAmount(for: strength, scheme: scheme)
            )
        }

        static func visibleAccentColor(
            for activityLabel: String?,
            scheme: ColorScheme
        ) -> Color? {
            guard let slot = slot(for: activityLabel) else { return nil }
            return paletteColor(for: slot, scheme: scheme)
        }

        private static func paletteColor(for slot: Slot, scheme: ColorScheme) -> Color {
            switch (slot, scheme) {
            case (.practice, .light):
                return Color(red: 0.70, green: 0.76, blue: 0.82)
            case (.practice, .dark):
                return Color(red: 0.31, green: 0.37, blue: 0.43)

            case (.rehearsal, .light):
                return Color(red: 0.79, green: 0.85, blue: 0.80)
            case (.rehearsal, .dark):
                return Color(red: 0.33, green: 0.40, blue: 0.35)

            case (.lesson, .light):
                return Color(red: 0.89, green: 0.81, blue: 0.84)
            case (.lesson, .dark):
                return Color(red: 0.43, green: 0.34, blue: 0.38)

            case (.performance, .light):
                return Color(red: 0.90, green: 0.82, blue: 0.75)
            case (.performance, .dark):
                return Color(red: 0.45, green: 0.36, blue: 0.30)

            case (.recording, .light):
                return Color(red: 0.84, green: 0.81, blue: 0.88)
            case (.recording, .dark):
                return Color(red: 0.38, green: 0.34, blue: 0.43)

            case (.custom, .light):
                return Color(red: 0.80, green: 0.84, blue: 0.88)
            case (.custom, .dark):
                return Color(red: 0.34, green: 0.39, blue: 0.44)
            }
        }

        private static func blendAmount(for strength: InstrumentTint.Strength, scheme: ColorScheme) -> CGFloat {
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.42
            case (.pickerStrong, .dark): return 0.34
            case (.cardMedium, .light): return 0.32
            case (.cardMedium, .dark): return 0.24
            case (.cardMediumLight, .light): return 0.20
            case (.cardMediumLight, .dark): return 0.18
            case (.cardLight, .light): return 0.14
            case (.cardLight, .dark): return 0.14
            case (.monthBar, .light): return 0.24
            case (.monthBar, .dark): return 0.20
            }
        }

        private static func strokeBlendAmount(for strength: InstrumentTint.Strength, scheme: ColorScheme) -> CGFloat {
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.28
            case (.pickerStrong, .dark): return 0.24
            case (.cardMedium, .light): return 0.22
            case (.cardMedium, .dark): return 0.18
            case (.cardMediumLight, .light): return 0.14
            case (.cardMediumLight, .dark): return 0.13
            case (.cardLight, .light): return 0.10
            case (.cardLight, .dark): return 0.10
            case (.monthBar, .light): return 0.16
            case (.monthBar, .dark): return 0.14
            }
        }

        private static func blendedSurface(base: Color, overlay: Color, amount: CGFloat) -> Color {
            guard amount > 0 else { return base }

            #if canImport(UIKit)
            let baseUIColor = UIColor(base)
            let overlayUIColor = UIColor(overlay)
            return Color(uiColor: mix(base: baseUIColor, overlay: overlayUIColor, amount: amount))
            #elseif canImport(AppKit)
            let baseNSColor = NSColor(base)
            let overlayNSColor = NSColor(overlay)
            return Color(mix(base: baseNSColor, overlay: overlayNSColor, amount: amount))
            #else
            return overlay.opacity(amount)
            #endif
        }

        #if canImport(UIKit)
        private static func mix(base: UIColor, overlay: UIColor, amount: CGFloat) -> UIColor {
            let clamped = max(0, min(1, amount))
            var baseR: CGFloat = 0
            var baseG: CGFloat = 0
            var baseB: CGFloat = 0
            var baseA: CGFloat = 0
            var overlayR: CGFloat = 0
            var overlayG: CGFloat = 0
            var overlayB: CGFloat = 0
            var overlayA: CGFloat = 0

            guard base.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA),
                  overlay.getRed(&overlayR, green: &overlayG, blue: &overlayB, alpha: &overlayA) else {
                return base
            }

            return UIColor(
                red: baseR + (overlayR - baseR) * clamped,
                green: baseG + (overlayG - baseG) * clamped,
                blue: baseB + (overlayB - baseB) * clamped,
                alpha: baseA + (overlayA - baseA) * clamped
            )
        }
        #endif

        #if canImport(AppKit)
        private static func mix(base: NSColor, overlay: NSColor, amount: CGFloat) -> NSColor {
            let clamped = max(0, min(1, amount))
            guard let baseRGB = base.usingColorSpace(.deviceRGB),
                  let overlayRGB = overlay.usingColorSpace(.deviceRGB) else {
                return base
            }

            return NSColor(
                red: baseRGB.redComponent + (overlayRGB.redComponent - baseRGB.redComponent) * clamped,
                green: baseRGB.greenComponent + (overlayRGB.greenComponent - baseRGB.greenComponent) * clamped,
                blue: baseRGB.blueComponent + (overlayRGB.blueComponent - baseRGB.blueComponent) * clamped,
                alpha: baseRGB.alphaComponent + (overlayRGB.alphaComponent - baseRGB.alphaComponent) * clamped
            )
        }
        #endif
    }
}

// MARK: - View modifiers

private struct SectionHeader: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .font(Theme.Text.sectionHeader)
            .kerning(0.2)
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.inline)
    }
}

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat? = nil
    var fillColor: Color? = nil
    var strokeColor: Color? = nil

    func body(content: Content) -> some View {
        let resolvedFill = fillColor ?? Theme.Colors.surface(scheme)
        let resolvedStroke = strokeColor ?? Theme.Colors.cardStroke(scheme)

        return content
            .padding(padding ?? Theme.Spacing.card)
            .background(resolvedFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(resolvedStroke, lineWidth: 1)
            )
    }
}

private struct CardSurfaceNonClipping: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat? = nil
    var fillColor: Color? = nil
    var strokeColor: Color? = nil

    func body(content: Content) -> some View {
        let resolvedFill = fillColor ?? Theme.Colors.surface(scheme)
        let resolvedStroke = strokeColor ?? Theme.Colors.cardStroke(scheme)

        return content
            .padding(padding ?? Theme.Spacing.card)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(resolvedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .stroke(resolvedStroke, lineWidth: 1)
                    )
            )
    }
}

private struct AppBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background(scheme).ignoresSafeArea())
    }
}

extension View {
    func sectionHeader() -> some View { modifier(SectionHeader()) }

    func cardSurface(padding: CGFloat? = nil) -> some View {
        modifier(CardSurface(padding: padding))
    }

    func cardSurface(
        padding: CGFloat? = nil,
        fillColor: Color,
        strokeColor: Color? = nil
    ) -> some View {
        modifier(CardSurface(padding: padding, fillColor: fillColor, strokeColor: strokeColor))
    }

    func cardSurfaceNonClipping(padding: CGFloat? = nil) -> some View {
        modifier(CardSurfaceNonClipping(padding: padding))
    }

    func cardSurfaceNonClipping(
        padding: CGFloat? = nil,
        fillColor: Color,
        strokeColor: Color? = nil
    ) -> some View {
        modifier(CardSurfaceNonClipping(padding: padding, fillColor: fillColor, strokeColor: strokeColor))
    }

    func appBackground() -> some View { modifier(AppBackground()) }
}

struct Theme_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Section").sectionHeader()
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Card Title").font(Theme.Text.pageTitle)
                Text("Body copy").font(Theme.Text.body).foregroundStyle(Theme.Colors.secondaryText)
            }
            .cardSurface()
        }
        .padding()
        .appBackground()
        .previewDisplayName("Theme — DesignLite")
    }
}

//  [ROLLBACK ANCHOR] v7.8 DesignLite — post
