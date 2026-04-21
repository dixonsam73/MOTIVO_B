// CHANGE-ID: 20260421_184700_session_meta_card_tint_resolver_52c1
// SCOPE: Route SessionMetaCard owner-local tint through Theme.resolvedTint using the shared Tint Mode foundation. Preserve the same card surface, spacing, typography, and interaction. No UI or logic changes outside tint source resolution.

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

    @AppStorage("appSettings_tintMode") private var tintModeRawValue: String = Theme.TintMode.auto.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    private var sessionMetaTintMode: Theme.TintMode {
        Theme.TintMode(rawValue: tintModeRawValue) ?? .auto
    }

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

    private var effectiveActivityLabel: String? {
        Theme.ActivityTint.normalizedLabel(activityLabel)
    }

    private var activeInstrumentCount: Int {
        let distinct = Set(
            instruments.compactMap { instrument in
                Theme.InstrumentTint.normalizedLabel(instrument.name)
            }
        )
        return distinct.count
    }

    private var activeActivityCount: Int {
        effectiveActivityLabel == nil ? 0 : 1
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

    private var resolvedTint: Theme.ResolvedTint {
        Theme.resolvedTint(
            instrument: effectiveInstrumentLabel,
            activity: effectiveActivityLabel,
            tintMode: sessionMetaTintMode,
            activeInstrumentCount: activeInstrumentCount,
            activeActivityCount: activeActivityCount
        )
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
