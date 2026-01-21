//
//  BackendModeSection.swift
//  MOTIVO
//
//  CHANGE-ID: 20260121_115020_P13D1_BACKENDMODESECTION_6c3a
//  SCOPE: Phase 13D — add BackendConnected mode; keep BackendPreview debug-only
//
//  Usage: Insert `BackendModeSection()` inside your DebugViewerView content.
//

import SwiftUI

public struct BackendModeSection: View {
    @AppStorage(BackendKeys.modeKey) private var modeRaw: String = BackendMode.localSimulation.rawValue

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend Mode").font(.headline)

            Picker("Backend Mode", selection: Binding(
                get: { BackendMode(rawValue: modeRaw) ?? .localSimulation },
                set: { newValue in
                    modeRaw = newValue.rawValue
                    setBackendMode(newValue)
                })
            ) {
                Text("Local").tag(BackendMode.localSimulation)
                Text("Connected").tag(BackendMode.backendConnected)
                Text("Preview").tag(BackendMode.backendPreview)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(statusColor)

                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var statusColor: Color {
        switch BackendMode(rawValue: modeRaw) ?? .localSimulation {
        case .localSimulation:
            return .green
        case .backendConnected:
            return .blue
        case .backendPreview:
            return .yellow
        }
    }

    private var statusLine: String {
        switch BackendMode(rawValue: modeRaw) ?? .localSimulation {
        case .localSimulation:
            return "Local data only. No network calls. Behaviour unchanged."
        case .backendConnected:
            return "Shipping-connected: UI backed by Supabase (no debug/preview surfaces)."
        case .backendPreview:
            return "Debug preview: diagnostic UI and logs. Not representative of shipping UI."
        }
    }
}
