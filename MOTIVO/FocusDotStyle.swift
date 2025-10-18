// FocusDotStyle.swift
// Centralized visual-only styling for Motivo's focus bar dots.
// This helper does not change layout, logic, or state — visuals only.
// The opacity ramp is purely visual (not data) and must preserve dark→light left→right in both color schemes.

import SwiftUI

public struct FocusDotStyle {
    // MARK: - Public constants

    /// Default total count of dots in the focus bar.
    public static let totalDefault: Int = 12

    /// A guaranteed-contrast hairline outline color.
    /// Uses the platform separator color to ensure visibility in both light and dark appearances.
    #if canImport(UIKit)
    public static let hairlineColor: Color = Color(UIColor.separator)
    #elseif canImport(AppKit)
    public static let hairlineColor: Color = Color(NSColor.separatorColor)
    #else
    // Fallback: a neutral gray if platform separator isn't available
    public static let hairlineColor: Color = Color.gray.opacity(0.5)
    #endif

    /// Hairline stroke width for dot outlines.
    public static let hairlineWidth: CGFloat = 1

    /// Stroke width for the selected/average ring.
    public static let ringWidth: CGFloat = 2

    // MARK: - Opacity ramp configuration
    // Left → Right should read Darker → Lighter in both schemes.
    // Expressed as black opacity for the dot fill.
    private static let lightStartOpacity: Double = 0.95 // leftmost (index 0)
    private static let lightEndOpacity: Double   = 0.15 // rightmost (index total-1)

    private static let darkStartOpacity: Double  = 0.72 // leftmost (index 0)
    private static let darkEndOpacity: Double    = 0.16 // rightmost (index total-1)

    // MARK: - Public API

    /// Returns the black opacity for the dot fill at a given index, using a linear interpolation
    /// from the scheme's start (leftmost/darkest) to end (rightmost/lightest) values.
    /// - Parameters:
    ///   - index: Zero-based index; 0 is leftmost (darkest).
    ///   - total: Total number of dots; defaults to `totalDefault`.
    ///   - colorScheme: The current color scheme (light or dark).
    /// - Returns: A Double in [0, 1] representing the opacity for `Color.black.opacity(...)`.
    public static func fillOpacity(index: Int, total: Int = totalDefault, colorScheme: ColorScheme) -> Double {
        // Guard against degenerate totals and out-of-range indices by clamping
        let clampedTotal = max(total, 1)
        let clampedIndex = max(0, min(index, clampedTotal - 1))

        let start: Double
        let end: Double
        switch colorScheme {
        case .light:
            start = lightStartOpacity
            end = lightEndOpacity
        case .dark:
            start = darkStartOpacity
            end = darkEndOpacity
        @unknown default:
            // Fallback to light scheme values for future schemes
            start = lightStartOpacity
            end = lightEndOpacity
        }

        // Map index in [0, total-1] to t in [0, 1]
        let denominator = max(Double(clampedTotal - 1), 1)
        let t = Double(clampedIndex) / denominator
        return lerp(start, end, t: t)
    }

    /// Returns the adaptive fill color for a dot at a given index.
    /// In Light Mode, uses black with descending opacity (dark→light left→right).
    /// In Dark Mode, uses white with ascending opacity (dark→light left→right).
    /// - Parameters:
    ///   - index: Zero-based index; 0 is leftmost (darkest).
    ///   - total: Total number of dots; defaults to `totalDefault`.
    ///   - colorScheme: The current color scheme (light or dark).
    /// - Returns: A `Color` with appropriate base (black/white) and adaptive opacity ramp.
    public static func fillColor(index: Int, total: Int = totalDefault, colorScheme: ColorScheme) -> Color {
        let opacity = fillOpacity(index: index, total: total, colorScheme: colorScheme)
        switch colorScheme {
        case .light:
            // Black base, higher opacity on the left → darker to lighter left→right
            return Color.black.opacity(opacity)
        case .dark:
            // White base, invert opacity so left is darkest (low white) and right is lightest (high white)
            let effective = 1 - opacity
            return Color.white.opacity(effective)
        @unknown default:
            return Color.black.opacity(opacity)
        }
    }

    /// Returns the adaptive color for the selected/average ring.
    /// - Parameter colorScheme: The current color scheme.
    /// - Returns: Black(0.85) in light mode, White(0.85) in dark mode.
    public static func ringColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.85)
        case .dark:
            return Color.white.opacity(0.85)
        @unknown default:
            return Color.black.opacity(0.85)
        }
    }

    /// Linear interpolation helper.
    /// - Parameters:
    ///   - a: Start value.
    ///   - b: End value.
    ///   - t: Interpolation factor in [0, 1]. Values are clamped.
    /// - Returns: Interpolated value between `a` and `b`.
    @inlinable
    public static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        let tt = min(max(t, 0), 1)
        return a + (b - a) * tt
    }
}

