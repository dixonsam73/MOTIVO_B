//
//  BackendModeSection.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-BackendModeSection-d4aa
//  SCOPE: v7.12C — drop-in UI for DebugViewer
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
                Text("Local Simulation").tag(BackendMode.localSimulation)
                Text("Backend (Supabase)").tag(BackendMode.backendPreview)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Circle().frame(width: 8, height: 8)
                    .foregroundStyle((BackendMode(rawValue: modeRaw) ?? .localSimulation) == .backendPreview ? Color.yellow : Color.green)
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

    private var statusLine: String {
        switch BackendMode(rawValue: modeRaw) ?? .localSimulation {
        case .localSimulation:
            return "Local data only. No network calls. Behaviour unchanged."
        case .backendPreview:
            return "Simulated API logs enabled. No real network or schema changes."
        }
    }
}
