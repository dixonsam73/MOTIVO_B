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
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .foregroundStyle(
                    Color(red: 0.33, green: 0.45, blue: 0.58)
                        .opacity(hasStarted ? 0.82 : 0.0)
                )
                .monospacedDigit()
                .animation(
                    hasStarted
                        ? .easeOut(duration: 3.0)
                        : .easeOut(duration: 0.45),
                    value: hasStarted
                )
                .accessibilityHidden(!hasStarted)
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
                .background(Theme.Colors.primaryAction.opacity(0.14))
                .foregroundStyle(Color.primary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(Color.primary.opacity(0.70))
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
                .background(Theme.Colors.primaryAction.opacity(0.08))
                .foregroundStyle(Color.primary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.red.opacity(0.12))
                .foregroundStyle(Color.primary.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Reset") {
                    onReset()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(Color.primary.opacity(0.70))
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
                .background(Theme.Colors.primaryAction.opacity(0.14))
                .foregroundStyle(Color.primary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer(minLength: 0)
            }
        }
    }
}
