import SwiftUI
import UIKit

struct FocusCircleView: View {
    static let baseFocusColor = Color(red: 0.33, green: 0.45, blue: 0.58)

    private static let lowFocusColor = Color(red: 0.45, green: 0.50, blue: 0.56)
    private static let highFocusColor = Color(red: 0.25, green: 0.38, blue: 0.52)
    private static let useFocusColorModulation = true

    let storedFocusValue: Int?
    let normalizedOverride: CGFloat?
    let size: CGFloat

    init(storedFocusValue: Int?, size: CGFloat = 30) {
        self.storedFocusValue = storedFocusValue
        self.normalizedOverride = nil
        self.size = size
    }

    init(normalizedFocus: CGFloat?, size: CGFloat = 30) {
        self.storedFocusValue = nil
        if let normalizedFocus {
            self.normalizedOverride = max(0, min(1, normalizedFocus))
        } else {
            self.normalizedOverride = nil
        }
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        renderColor.opacity(renderOpacity),
                        renderColor.opacity(renderEdgeOpacity)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.52
                )
            )
            .frame(width: size, height: size)
            .scaleEffect(renderScale)
            .blur(radius: renderBlur)
            .accessibilityLabel("Focus")
            .accessibilityValue(accessibilityValue)
    }

    static func visualFocusValue(forStoredFocusValue storedValue: Int?) -> Int? {
        guard let storedValue else { return nil }

        switch storedValue {
        case 0...4:
            return storedValue + 1
        case 5:
            return nil
        case 6...10:
            return storedValue
        case 11:
            return 10
        default:
            return nil
        }
    }

    static func storedFocusValue(forVisualFocusValue visualValue: Int) -> Int {
        let clampedVisual = max(1, min(10, visualValue))

        switch clampedVisual {
        case 1...5:
            return clampedVisual - 1
        case 6...9:
            return clampedVisual
        default:
            return 11
        }
    }

    private var normalizedFocus: CGFloat? {
        if let normalizedOverride { return normalizedOverride }
        guard let visualValue = Self.visualFocusValue(forStoredFocusValue: storedFocusValue) else { return nil }
        return CGFloat(visualValue - 1) / 9.0
    }

    private var resolvedFocus: CGFloat {
        normalizedFocus ?? 0.0
    }

    private var renderColor: Color {
        guard Self.useFocusColorModulation else {
            return Self.baseFocusColor
        }

        guard normalizedFocus != nil else {
            return Self.lowFocusColor
        }

        let colorProgress = pow(resolvedFocus, 0.85)
        return Self.mixColor(Self.lowFocusColor, Self.highFocusColor, colorProgress)
    }

    private var renderBlur: CGFloat {
        guard normalizedFocus != nil else { return 3.8 }
        let clarity = pow(resolvedFocus, 0.66)
        return Self.lerp(3.8, 0.0, clarity)
    }

    private var renderOpacity: Double {
        guard normalizedFocus != nil else { return 0.24 }
        let density = pow(resolvedFocus, 0.78)
        return Double(Self.lerp(0.36, 0.84, density))
    }

    private var renderEdgeOpacity: Double {
        guard normalizedFocus != nil else { return 0.20 }
        let edgeDensity = pow(resolvedFocus, 0.74)
        return Double(Self.lerp(0.26, 0.70, edgeDensity))
    }

    private var renderScale: CGFloat {
        guard normalizedFocus != nil else { return 1.035 }
        let scaleProgress = pow(resolvedFocus, 0.86)
        return Self.lerp(1.035, 0.97, scaleProgress)
    }

    private var accessibilityValue: String {
        if let visualValue = Self.visualFocusValue(forStoredFocusValue: storedFocusValue) {
            return "\(visualValue) of 10"
        }
        return "Unset"
    }

    private static func lerp(_ start: CGFloat, _ end: CGFloat, _ t: CGFloat) -> CGFloat {
        start + (end - start) * t
    }

    private static func mixColor(_ start: Color, _ end: Color, _ t: CGFloat) -> Color {
        let clamped = max(0, min(1, t))

        let startUIColor = UIColor(start)
        let endUIColor = UIColor(end)

        var sr: CGFloat = 0
        var sg: CGFloat = 0
        var sb: CGFloat = 0
        var sa: CGFloat = 0

        var er: CGFloat = 0
        var eg: CGFloat = 0
        var eb: CGFloat = 0
        var ea: CGFloat = 0

        startUIColor.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        endUIColor.getRed(&er, green: &eg, blue: &eb, alpha: &ea)

        return Color(
            red: Double(lerp(sr, er, clamped)),
            green: Double(lerp(sg, eg, clamped)),
            blue: Double(lerp(sb, eb, clamped)),
            opacity: Double(lerp(sa, ea, clamped))
        )
    }
}
