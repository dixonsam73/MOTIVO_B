// CHANGE-ID: 20260320_095800_PressedRowAffordance
// SCOPE: Affordance-only refinement — add subtle pressed-state feedback to tappable Instrument and Activity rows in SessionMetaCard. No layout, typography, spacing, or logic changes.

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

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

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
                            instrument = only
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
            .cardSurface()
        }
    }
}
