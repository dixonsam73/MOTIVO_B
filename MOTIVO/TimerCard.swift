// CHANGE-ID: 20260326_134500_stage21_running_state_priority
// SCOPE: Preserve TimerCard styling while prioritising isRunning for immediate transport-state feedback

import SwiftUI

struct TimerCard: View {
    let elapsedLabel: String
    let isRunning: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void
    let onFinish: () -> Void

    private var hasStarted: Bool {
        elapsedLabel != "00:00"
    }

    private var isPaused: Bool {
        !isRunning && hasStarted
    }

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text(elapsedLabel)
                .font(.system(size: 50, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.85))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)

            transportControls
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .cardSurface()
    }

    @ViewBuilder
    private var transportControls: some View {
        if isRunning {
            HStack(spacing: Theme.Spacing.m) {
                Button("Pause") {
                    onPause()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.Colors.primaryAction.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.red.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else if isPaused {
            HStack(spacing: Theme.Spacing.m) {
                Button("Resume") {
                    onStart()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.Colors.primaryAction.opacity(0.10))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.red.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Reset") {
                    onReset()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.orange.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else {
            HStack {
                Spacer(minLength: 0)

                Button("Start") {
                    onStart()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: 260, minHeight: 44)
                .background(Theme.Colors.primaryAction.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer(minLength: 0)
            }
        }
    }
}
