//
//  AgeRangeProbeRow.swift
//  MOTIVO
//
//  TEMPORARY — UK age-confirmation check, 2026-10-15.
//
//  Shows exactly what Apple's Declared Age Range returns on this device, including
//  how the age was set (`ageRangeDeclaration`). Question it answers: does Apple's
//  UK "Confirmed 18+" (Settings → Personal Information → Age Confirmation) reach
//  apps as `.confirmed`? Shown only on screen; nothing is stored or sent.
//
//  REMOVE once the question is answered, and verify the removal is a pure
//  deletion (this file plus the one line in ProfileView's build-info footer).
//

import SwiftUI
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

struct AgeRangeProbeRow: View {
    #if canImport(DeclaredAgeRange)
    @Environment(\.requestAgeRange) private var requestAgeRange
    #endif
    @State private var result: String?

    var body: some View {
        VStack(spacing: 6) {
            Button("Age check readout (temporary)") {
                Task { await run() }
            }
            .font(Theme.Text.meta)
            if let result {
                Text(result)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func run() async {
        #if canImport(DeclaredAgeRange)
        do {
            let response = try await requestAgeRange(ageGates: 18)
            switch response {
            case .declinedSharing:
                result = "Declined sharing"
            case .sharing(let range):
                let lower = range.lowerBound.map(String.init) ?? "none"
                let upper = range.upperBound.map(String.init) ?? "none"
                let how = range.ageRangeDeclaration.map { String(describing: $0) } ?? "not provided"
                result = "Range: \(lower) to \(upper) · Set by: \(how)"
            @unknown default:
                result = "Unrecognised response"
            }
        } catch {
            result = "Error: \(error)"
        }
        #else
        result = "Declared Age Range isn't available on this build"
        #endif
    }
}
