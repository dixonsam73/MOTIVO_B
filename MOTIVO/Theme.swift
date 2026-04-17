// CHANGE-ID: 20260417_194800_theme_tint_foundation_a1f4
// SCOPE: Add stable owner-local instrument tint palette, UserDefaults slot mapping, and card surface overloads without changing existing default visuals.
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
        // standard card corner radius
        static let card: CGFloat = 16
        // control corner radius
        static let control: CGFloat = 12
    }

    enum Colors {
        // Warm, paper-like grouped background (light); near-black grouped (dark)
        static func background(_ scheme: ColorScheme) -> Color {
            scheme == .dark
            ? Color(red: 0.06, green: 0.06, blue: 0.07)           // ~#0F0F12
            : Color(red: 0.96, green: 0.95, blue: 0.92)           // warm sand ~#F5F2EA
        }
        // Subtle surface for cards
        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)           // ~#1F1F22
            : Color(red: 0.99, green: 0.99, blue: 0.97)           // off-white ~#FEFEF7
        }
        // Hairline stroke
        static func stroke(_ scheme: ColorScheme) -> Color {
            scheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
        }
        // Subtle 1pt divider for cards
        static func cardStroke(_ scheme: ColorScheme) -> Color {
            stroke(scheme)
        }

        static var accent: Color {
            // Slate blue-grey accent for UI chrome
            Color(red: 0.32, green: 0.38, blue: 0.46)
        }

        static var primaryAction: Color {
            // Original timer green for key actions
            Color(red: 0.16, green: 0.38, blue: 0.29)
        }
        static var secondaryText: Color {
            Color.primary.opacity(0.55)
        }
    }

    enum Text {
        // Page title style
        static var pageTitle: Font { .title3.weight(.semibold) }
        // Section header style (with subtle letter spacing ~0.2)
        static var sectionHeader: Font { .subheadline.weight(.semibold) }
        // Body copy (~15 pt)
        static var body: Font { .subheadline }
        // Meta text (uses secondary color via modifier; font size only here)
        static var meta: Font { .footnote }
    }

    enum InstrumentTint {
        enum Slot: Int, CaseIterable {
            case neutralAnchor = 0
            case coolDeep = 1
            case warmOrganic = 2
            case softWarmLight = 3
            case coolLight = 4
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
            guard let slot = slot(for: instrumentLabel, ownerID: ownerID, shouldAssignIfNeeded: shouldAssignIfNeeded) else {
                return nil
            }
            let map = slotMap(ownerID: ownerID)
            let distinctCount = Set(map.values).count
            guard distinctCount > 1 else { return .neutralAnchor }
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

        static func hasMultipleMappedInstruments(ownerID: String?) -> Bool {
            Set(slotMap(ownerID: ownerID).values).count > 1
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
            return UserDefaults.standard.dictionary(forKey: namespace) as? [String: Int] ?? [:]
        }

        private static func nextAvailableSlot(from map: [String: Int]) -> Slot {
            let used = Set(map.values)
            for slot in Slot.allCases where !used.contains(slot.rawValue) {
                return slot
            }
            return .coolLight
        }

        private static func paletteColor(for slot: Slot, scheme: ColorScheme) -> Color {
            switch (slot, scheme) {
            case (.neutralAnchor, _):
                return Theme.Colors.surface(scheme)
            case (.coolDeep, .light):
                return Color(red: 0.73, green: 0.78, blue: 0.83)
            case (.coolDeep, .dark):
                return Color(red: 0.31, green: 0.36, blue: 0.42)
            case (.warmOrganic, .light):
                return Color(red: 0.90, green: 0.82, blue: 0.72)
            case (.warmOrganic, .dark):
                return Color(red: 0.40, green: 0.35, blue: 0.30)
            case (.softWarmLight, .light):
                return Color(red: 0.90, green: 0.84, blue: 0.85)
            case (.softWarmLight, .dark):
                return Color(red: 0.42, green: 0.34, blue: 0.36)
            case (.coolLight, .light):
                return Color(red: 0.84, green: 0.87, blue: 0.88)
            case (.coolLight, .dark):
                return Color(red: 0.35, green: 0.39, blue: 0.41)
            }
        }

        private static func blendAmount(for strength: Strength, slot: Slot, scheme: ColorScheme) -> CGFloat {
            guard slot != .neutralAnchor else { return 0 }
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.46
            case (.pickerStrong, .dark): return 0.36
            case (.cardMedium, .light): return 0.28
            case (.cardMedium, .dark): return 0.23
            case (.cardMediumLight, .light): return 0.25
            case (.cardMediumLight, .dark): return 0.19
            case (.cardLight, .light): return 0.17
            case (.cardLight, .dark): return 0.15
            case (.monthBar, .light): return 0.30
            case (.monthBar, .dark): return 0.24
            }
        }

        private static func strokeBlendAmount(for strength: Strength, scheme: ColorScheme) -> CGFloat {
            switch (strength, scheme) {
            case (.pickerStrong, .light): return 0.32
            case (.pickerStrong, .dark): return 0.26
            case (.cardMedium, .light): return 0.20
            case (.cardMedium, .dark): return 0.17
            case (.cardMediumLight, .light): return 0.16
            case (.cardMediumLight, .dark): return 0.14
            case (.cardLight, .light): return 0.12
            case (.cardLight, .dark): return 0.11
            case (.monthBar, .light): return 0.20
            case (.monthBar, .dark): return 0.16
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
            // NOTE: no clipShape here – the rounded rect is purely visual
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

    // New: card surface that does NOT clip its children (for popovers/overlays)
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
