// CHANGE-ID: 20260516_101800_timer_phase3_motion_language
// SCOPE: Calm transport-state recomposition using stable spatial layout, softer opacity transitions, and unified button geometry without changing timer behaviour or container architecture.

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

    private var controlAnimation: Animation {
        .easeInOut(duration: 0.52)
    }
    
    @State private var isStartingTransition: Bool = false
    
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

    private var transportControls: some View {
        Group {

            if isRunning {

                HStack(spacing: Theme.Spacing.m) {

                    controlSlot(
                        title: "Pause",
                        isVisible: !isStartingTransition,
                        background: Theme.Colors.primaryAction.opacity(0.14),
                        action: onPause
                    )

                    controlSlot(
                        title: "Finish",
                        isVisible: !isStartingTransition,
                        background: Color.red.opacity(0.12),
                        action: onFinish
                    )
                }
                .frame(maxWidth: 360)

            } else if isPaused {

                HStack(spacing: Theme.Spacing.m) {

                    controlSlot(
                        title: "Resume",
                        isVisible: !isStartingTransition,
                        background: Theme.Colors.primaryAction.opacity(0.08),
                        action: onStart
                    )

                    controlSlot(
                        title: "Finish",
                        isVisible: !isStartingTransition,
                        background: Color.red.opacity(0.12),
                        action: onFinish
                    )

                    controlSlot(
                        title: "Reset",
                        isVisible: !isStartingTransition,
                        background: Color.orange.opacity(0.12),
                        action: onReset
                    )
                }

            } else {

                HStack(spacing: Theme.Spacing.m) {

                    Spacer(minLength: 0)

                    controlSlot(
                        title: "Start",
                        isVisible: !isStartingTransition,
                        background: Theme.Colors.primaryAction.opacity(0.14),
                        action: {
                            isStartingTransition = true
                            onStart()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                                isStartingTransition = false
                            }
                        }
                    )
                    .frame(maxWidth: 180)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func controlSlot(
        title: String,
        isVisible: Bool,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {

        Button(title) {
            action()
        }
        .buttonStyle(.bordered)
        .tint(.clear)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background)
                .opacity(isVisible ? 1.0 : 0.0)
        )
        .foregroundStyle(
            Color.primary.opacity(isVisible ? 0.72 : 0.0)
        )
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: isVisible ? 0 : 4)
        .allowsHitTesting(isVisible)
        .animation(controlAnimation, value: isVisible)
    }
}
