//
//  LegalLinks.swift
//  MOTIVO
//
//  The public privacy policy and terms, hosted on the website. Apple requires
//  both to be reachable in the app (5.1.1) and on the subscription purchase
//  screen (3.1.2).
//

import SwiftUI

enum LegalLinks {
    static let privacyPolicy = URL(string: "https://etudes.app/privacy")!
    static let termsOfUse = URL(string: "https://etudes.app/terms")!
}

/// "Terms of Use · Privacy Policy", quietly, for the foot of a purchase screen.
struct LegalLinksFooter: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Link("Terms of Use", destination: LegalLinks.termsOfUse)
            Text("·").accessibilityHidden(true)
            Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
        }
        .font(Theme.Text.meta)
        .foregroundStyle(Theme.Colors.secondaryText)
        .frame(maxWidth: .infinity)
    }
}
