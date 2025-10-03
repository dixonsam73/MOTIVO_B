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

enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 12
        static let l:  CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
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
        // Evergreen accent (can be tailored later)
        static var accent: Color {
            Color(red: 0.16, green: 0.38, blue: 0.29)            // deep green
        }
        static var secondaryText: Color {
            Color.primary.opacity(0.55)
        }
    }
}

// MARK: - View modifiers

private struct SectionHeader: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Theme.Spacing.xs)
    }
}

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat? = nil
    func body(content: Content) -> some View {
        content
            .padding(padding ?? Theme.Spacing.l)
            .background(Theme.Colors.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.stroke(scheme), lineWidth: 1)
            )
            .shadow(color: scheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct AppBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background(scheme))
    }
}

extension View {
    func sectionHeader() -> some View { modifier(SectionHeader()) }
    func cardSurface(padding: CGFloat? = nil) -> some View { modifier(CardSurface(padding: padding)) }
    func appBackground() -> some View { modifier(AppBackground()) }
}

struct Theme_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Section").sectionHeader()
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Card Title").font(.headline)
                Text("Body copy").foregroundStyle(Theme.Colors.secondaryText)
            }
            .cardSurface()
        }
        .padding()
        .appBackground()
        .previewDisplayName("Theme — DesignLite")
    }
}

//  [ROLLBACK ANCHOR] v7.8 DesignLite — post
