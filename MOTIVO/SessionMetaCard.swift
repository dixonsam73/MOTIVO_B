// CHANGE-ID: 20260417_195650_owner_instrument_tint_4b27
// SCOPE: Apply owner-local instrument tint to the existing SessionMetaCard surface only. No layout, typography, spacing, interaction, or logic changes outside card fill/stroke selection.

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

    private var resolvedFillColor: Color {
        Theme.InstrumentTint.surfaceFill(
            for: effectiveInstrumentLabel,
            ownerID: nil,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var resolvedStrokeColor: Color {
        Theme.InstrumentTint.cardStroke(
            for: effectiveInstrumentLabel,
            ownerID: nil,
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
