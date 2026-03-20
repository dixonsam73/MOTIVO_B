// CHANGE-ID: 20260320_144800_static_paused_emphasis
// SCOPE: Keep button visuals intact while making paused state slightly stronger on Start and preserving active Reset/Finish after session start

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

            HStack(spacing: Theme.Spacing.m) {
                Button(isRunning ? "Pause" : "Start") {
                    isRunning ? onPause() : onStart()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.Colors.primaryAction.opacity(isPaused ? 0.10 : 0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Reset") {
                    onReset()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(hasStarted ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(hasStarted ? Color.red.opacity(0.18) : Color.secondary.opacity(0.12))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .cardSurface()
    }
}
