//
//  AppSettingsView.swift
//  MOTIVO
//
//  CHANGE-ID: 20251204-AppSettingsView-v1
//  SCOPE: Lightweight app settings surface for small global UI toggles.
//  - Mirrors InstrumentListView / ActivityListView layout and theming.
//  - Currently controls visibility of Profile welcome section and Session Timer drone strip.
//

import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Global app UI toggles (UserDefaults-backed via AppStorage)
    @AppStorage("appSettings_showWelcomeSection") private var showWelcomeSection: Bool = true
    @AppStorage("appSettings_showDroneStrip") private var showDroneStrip: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Profile").sectionHeader()) {
                    Toggle(isOn: $showWelcomeSection) {
                        Text("Show welcome message")
                            .font(Theme.Text.body)
                    }
                }

                Section(header: Text("Session Timer").sectionHeader()) {
                    Toggle(isOn: $showDroneStrip) {
                        Text("Show drone controls")
                            .font(Theme.Text.body)
                    }
                }
            }
            .navigationTitle("App Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("App Settings")
                        .font(Theme.Text.pageTitle)
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Text("Close")
                            .font(Theme.Text.body)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .appBackground()
        }
    }
}
