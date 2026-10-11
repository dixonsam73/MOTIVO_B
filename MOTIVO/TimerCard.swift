// CHANGE-ID: 20260516_104500_timer_phase3_persistent_outgoing_controls
// SCOPE: Preserve outgoing timer controls during transitions so they fade away before the next control layout fades in, without changing timer behaviour or container architecture.

import SwiftUI

struct TimerCard: View {
    let elapsedLabel: String
    let elapsedSeconds: Int
    let isRunning: Bool
    /// The one shared "started since reset" check, owned by the timer. It is
    /// NOT derived from the label: a Start → Pause inside one second shows
    /// `00:00` and is still a practice attempt, so it must show paused controls.
    let hasStarted: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    /// Reset — the timer asks what to do (time only, or time and draft) in its
    /// own card, so this only requests. There is never a second control for it.
    let onResetTimer: () -> Void
    let onFinish: () -> Void
    /// True when attachments are staged: Reset opens the card, so it runs
    /// without the control transition and the controls follow the timer's
    /// state once something actually happens. Otherwise Reset is immediate and
    /// fades the controls back to idle.
    let resetRequiresConfirmation: Bool

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

    private var isPaused: Bool {
        !isRunning && hasStarted
    }

    /// The elapsed label's own visibility: it fades in with the first digit
    /// change, exactly as before, and is hidden at `00:00`. Decoupled from
    /// `hasStarted` so a fade begun at Start does not swallow the first digit.
    private var showsElapsed: Bool {
        elapsedLabel != "00:00"
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
        guard showsElapsed else { return 0.0 }

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
                    showsElapsed
                        ? .easeOut(duration: 3.0)
                        : .easeOut(duration: 0.45),
                    value: showsElapsed
                )
                .accessibilityHidden(!showsElapsed)
                .frame(maxWidth: .infinity, alignment: .center)

            transportControls
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .center)
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

                // "Start Timer", so a timed session reads differently from the
                // thought-capture state the recorder and Save thought live in.
                // Nothing else sits on this row: Reset appears once something
                // has started since the last reset.
                controlSlot(
                    title: "Start Timer",
                    background: Theme.Colors.primaryAction.opacity(0.14),
                    isInteractive: isInteractive,
                    action: {
                        performControlTransition(to: .running, action: onStart)
                    }
                )
                .frame(maxWidth: 220)

                Spacer(minLength: 0)
            }
            .offset(y: -34)

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

                controlSlot(
                    title: "Reset",
                    background: Color.orange.opacity(0.12),
                    isInteractive: isInteractive,
                    action: { requestReset() }
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
                    action: { requestReset() }
                )
            }
            .frame(maxWidth: 360)
        }
    }

    /// A Reset that opens the card runs without the control transition: the
    /// controls follow the timer's state once the member chooses, and a Cancel
    /// leaves them as they were. An immediate Reset fades back to idle.
    private func requestReset() {
        if resetRequiresConfirmation {
            onResetTimer()
        } else {
            performControlTransition(to: .idle, action: onResetTimer)
        }
    }

    private func controlSlot(
        title: String,
        background: Color,
        isInteractive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

/// The Reset card, as a modifier: `PracticeTimerView`'s body is at the
/// type-checker's limit, and another inline `.alert` does not compile.
///
/// Shown only when attachments are staged. It offers the two outcomes in one
/// place — reset the time and keep the draft, or reset and discard the draft
/// (named truthfully, C-84) — so there is never a second control on the timer
/// row. With no attachments, Reset simply resets; the time alone never asks.
struct TimerResetAlert: ViewModifier {
    @Binding var isPresented: Bool
    let summary: SessionDiscardSummary
    let onResetKeepingDraft: () -> Void
    let onResetDiscardingDraft: () -> Void

    static let title = "Reset the timer?"

    func body(content: Content) -> some View {
        content.alert(Self.title, isPresented: $isPresented) {
            Button(SessionDiscardSummary.keepTitle) { onResetKeepingDraft() }
            Button(SessionDiscardSummary.confirmTitle, role: .destructive) { onResetDiscardingDraft() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(summary.message ?? "")
        }
    }
}
