//
//  AppSettingsView.swift
//  MOTIVO
//
//  CHANGE-ID: 20251204-AppSettingsView-v2
//  SCOPE: Add "Show metronome controls" toggle to match drone toggle.
//

import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Global app UI toggles (UserDefaults-backed via AppStorage)
    @AppStorage("appSettings_showWelcomeSection") private var showWelcomeSection: Bool = true
    @AppStorage("appSettings_showDroneStrip") private var showDroneStrip: Bool = true
    @AppStorage("appSettings_showMetronomeStrip") private var showMetronomeStrip: Bool = true   // NEW

    var body: some View {
        NavigationStack {
            Form {
                // PROFILE SECTION
                Section(header: Text("Profile").sectionHeader()) {
                    Toggle(isOn: $showWelcomeSection) {
                        Text("Show Welcome Message")
                            .font(Theme.Text.body)
                    }
                }

                // SESSION TIMER SECTION
                Section(header: Text("Session Timer").sectionHeader()) {
                    Toggle(isOn: $showDroneStrip) {
                        Text("Show Drone")
                            .font(Theme.Text.body)
                    }

                    Toggle(isOn: $showMetronomeStrip) {        // NEW
                        Text("Show Metronome")
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
