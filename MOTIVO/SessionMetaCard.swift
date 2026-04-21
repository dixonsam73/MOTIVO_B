// CHANGE-ID: 20260421_184700_session_meta_card_tint_resolver_52c1
// SCOPE: Make SessionMetaCard presentational-only for owner-local tint rendering. Tint meaning is resolved in PracticeTimerView and passed in. Preserve the same card surface, spacing, typography, and interaction.

import SwiftUI
import CoreData

private struct SessionMetaRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.82 : 1.0)
    }
}

struct SessionMetaCard: View {
    let instruments: [Instrument]
    @Binding var instrument: Instrument?
    @Binding var showInstrumentSheet: Bool
    @Binding var showActivitySheet: Bool
    let currentInstrumentName: String
    let activityLabel: String
    let resolvedTint: Theme.ResolvedTint

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }






    /// Matches the owner-local namespace path used by the owner Journal/detail surfaces.
    private var tintOwnerID: String? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        #endif

        if let authID = auth.currentUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !authID.isEmpty {
            return authID
        }

        if let persistenceID = PersistenceController.shared.currentUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !persistenceID.isEmpty {
            return persistenceID
        }

        return nil
    }


    private var resolvedFillColor: Color {
        resolvedTint.fill(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var resolvedStrokeColor: Color {
        resolvedTint.stroke(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    var body: some View {
        if hasNoInstruments {
            VStack(alignment: .center, spacing: Theme.Spacing.s) {
                Text("No instruments found")
                    .font(.headline)
                Text("Add an instrument in your Profile to start timing sessions.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.m)
            .cardSurface()
        } else {
            VStack(spacing: Theme.Spacing.m) {
                VStack(spacing: Theme.Spacing.s) {
                    if hasMultipleInstruments {
                        Button {
                            showInstrumentSheet = true
                        } label: {
                            HStack {
                                Text("Instrument")
                                Spacer()
                                Text(currentInstrumentName)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        .buttonStyle(SessionMetaRowButtonStyle())
                    } else if let only = instruments.first {
                        HStack {
                            Text("Instrument")
                            Spacer()
                            Text(only.name ?? "Instrument")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                if instrument == nil {
                                    instrument = only
                                }
                            }
                        }
                    }

                    Button {
                        showActivitySheet = true
                    } label: {
                        HStack {
                            Text("Activity")
                            Spacer()
                            Text(activityLabel)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(SessionMetaRowButtonStyle())
                }
            }
            .cardSurface(fillColor: resolvedFillColor, strokeColor: resolvedStrokeColor)
        }
    }
}
