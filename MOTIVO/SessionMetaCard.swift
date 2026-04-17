// CHANGE-ID: 20260417_214700_owner_local_tint_namespace_fix_91ac
// SCOPE: Align SessionMetaCard owner-local instrument tint resolution with ContentView/SessionDetailView by using the local owner namespace for tint slot mapping only. No layout, typography, spacing, interaction, or logic changes outside card fill/stroke selection.

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

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    private var effectiveInstrumentLabel: String? {
        if let selectedName = instrument?.name,
           let normalized = Theme.InstrumentTint.normalizedLabel(selectedName) {
            return normalized
        }

        if hasMultipleInstruments,
           let normalized = Theme.InstrumentTint.normalizedLabel(currentInstrumentName) {
            return normalized
        }

        if let onlyName = instruments.first?.name,
           let normalized = Theme.InstrumentTint.normalizedLabel(onlyName) {
            return normalized
        }

        return nil
    }

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
        Theme.InstrumentTint.surfaceFill(
            for: effectiveInstrumentLabel,
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var resolvedStrokeColor: Color {
        Theme.InstrumentTint.cardStroke(
            for: effectiveInstrumentLabel,
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
