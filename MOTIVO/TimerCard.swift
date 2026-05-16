// CHANGE-ID: 20260516_104500_timer_phase3_persistent_outgoing_controls
// SCOPE: Preserve outgoing timer controls during transitions so they fade away before the next control layout fades in, without changing timer behaviour or container architecture.

import SwiftUI

struct TimerCard: View {
    let elapsedLabel: String
    let elapsedSeconds: Int
    let isRunning: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void
    let onFinish: () -> Void

    private enum ControlMode: Equatable {
        case idle
        case running
        case paused
    }

    @State private var displayedControlMode: ControlMode = .idle
    @State private var outgoingControlMode: ControlMode?
    @State private var outgoingOpacity: Double = 0.0
    @State private var incomingOpacity: Double = 1.0
    @State private var isControlTransitionActive: Bool = false

    private var hasStarted: Bool {
        elapsedLabel != "00:00"
    }

    private var isPaused: Bool {
        !isRunning && hasStarted
    }

    private var currentControlMode: ControlMode {
        if isRunning {
            return .running
        } else if isPaused {
            return .paused
        } else {
            return .idle
        }
    }

    private var fadeOutAnimation: Animation {
        .easeInOut(duration: 0.78)
    }

    private var fadeInAnimation: Animation {
        .easeInOut(duration: 0.52)
    }
    
    private var timerFocusOpacity: Double {
        guard hasStarted else { return 0.0 }

        let progress = min(Double(elapsedSeconds) / 1800.0, 1.0)

        return 0.58 + (progress * 0.28)
    }

    private var timerFocusColor: Color {
        let progress = min(Double(elapsedSeconds) / 1800.0, 1.0)

        let red = 0.33 - (0.08 * progress)
        let green = 0.45 - (0.07 * progress)
        let blue = 0.58 - (0.06 * progress)

        return Color(red: red, green: green, blue: blue)
    }
    
    private func performControlTransition(
        to targetMode: ControlMode,
        action: @escaping () -> Void
    ) {
        guard !isControlTransitionActive else { return }

        isControlTransitionActive = true
        outgoingControlMode = displayedControlMode
        outgoingOpacity = 1.0
        incomingOpacity = 0.0

        action()

        withAnimation(fadeOutAnimation) {
            outgoingOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
            displayedControlMode = targetMode
            outgoingControlMode = nil

            withAnimation(fadeInAnimation) {
                incomingOpacity = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                isControlTransitionActive = false
            }
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.s) {
            Text(elapsedLabel)
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .foregroundStyle(
                    timerFocusColor
                        .opacity(timerFocusOpacity)
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
        .onAppear {
            displayedControlMode = currentControlMode
        }
        .onChange(of: currentControlMode) { _, newValue in
            guard !isControlTransitionActive else { return }
            displayedControlMode = newValue
            incomingOpacity = 1.0
            outgoingControlMode = nil
            outgoingOpacity = 0.0
        }
    }

    private var transportControls: some View {
        ZStack {
            if let outgoingControlMode {
                controlLayout(for: outgoingControlMode, isInteractive: false)
                    .opacity(outgoingOpacity)
            }

            controlLayout(for: displayedControlMode, isInteractive: !isControlTransitionActive)
                .opacity(incomingOpacity)
        }
    }

    @ViewBuilder
    private func controlLayout(
        for mode: ControlMode,
        isInteractive: Bool
    ) -> some View {
        switch mode {
        case .idle:
            HStack(spacing: Theme.Spacing.m) {
                Spacer(minLength: 0)

                controlSlot(
                    title: "Start",
                    background: Theme.Colors.primaryAction.opacity(0.14),
                    isInteractive: isInteractive,
                    action: {
                        performControlTransition(to: .running, action: onStart)
                    }
                )
                .frame(maxWidth: 180)

                Spacer(minLength: 0)
            }

        case .running:
            HStack(spacing: Theme.Spacing.m) {
                controlSlot(
                    title: "Pause",
                    background: Theme.Colors.primaryAction.opacity(0.14),
                    isInteractive: isInteractive,
                    action: {
                        performControlTransition(to: .paused, action: onPause)
                    }
                )

                controlSlot(
                    title: "Finish",
                    background: Color.red.opacity(0.12),
                    isInteractive: isInteractive,
                    action: {
                        performControlTransition(to: .paused, action: onFinish)
                    }
                )
            }
            .frame(maxWidth: 360)

        case .paused:
            HStack(spacing: Theme.Spacing.m) {
                controlSlot(
                    title: "Resume",
                    background: Theme.Colors.primaryAction.opacity(0.08),
                    isInteractive: isInteractive,
                    action: {
                        performControlTransition(to: .running, action: onStart)
                    }
                )

                controlSlot(
                    title: "Finish",
                    background: Color.red.opacity(0.12),
                    isInteractive: isInteractive,
                    action: {
                        performControlTransition(to: .paused, action: onFinish)
                    }
                )

                controlSlot(
                    title: "Reset",
                    background: Color.orange.opacity(0.12),
                    isInteractive: isInteractive,
                    action: {
                        performControlTransition(to: .idle, action: onReset)
                    }
                )
            }
        }
    }

    private func controlSlot(
        title: String,
        background: Color,
        isInteractive: Bool,
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
        )
        .foregroundStyle(Color.primary.opacity(0.72))
        .allowsHitTesting(isInteractive)
    }
}
