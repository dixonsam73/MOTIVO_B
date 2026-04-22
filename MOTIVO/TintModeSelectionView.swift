import SwiftUI

struct TintModeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appSettings_tintMode") private var tintModeRaw: String = Theme.TintMode.auto.rawValue

    private var currentTintMode: Theme.TintMode {
        Theme.TintMode(rawValue: tintModeRaw) ?? .auto
    }

    var body: some View {
        Form {
            Section(header: Text("Tint Mode").sectionHeader()) {
                ForEach(Theme.TintMode.allCases) { mode in
                    tintModeRow(mode)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Back")
            }
        }
        .appBackground()
    }

    @ViewBuilder
    private func tintModeRow(_ mode: Theme.TintMode) -> some View {
        Button {
            guard currentTintMode != mode else { return }
            tintModeRaw = mode.rawValue
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Text(mode.displayName)
                    .font(Theme.Text.body)
                    .foregroundStyle(.primary)

                Spacer()

                if currentTintMode == mode {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
