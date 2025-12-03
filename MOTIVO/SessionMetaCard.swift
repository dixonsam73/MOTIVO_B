// SessionMetaCard.swift
// Extracted from PracticeTimerView selectorsCard (no logic changes).

import SwiftUI
import CoreData

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
                Text("Session")
                    .sectionHeader()

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
                        .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
                }
            }
            .cardSurface()
        }
    }
}
