//
//  TimerCard.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 03/12/2025.
//
// TimerCard.swift
// Extracted from PracticeTimerView (start / pause / reset / finish UI).
// No logic changes; pure UI wrapper around timer controls.

import SwiftUI

struct TimerCard: View {
    let elapsedLabel: String
    let isRunning: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text(elapsedLabel)
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: Theme.Spacing.m) {
                Button(isRunning ? "Pause" : "Start") {
                    isRunning ? onPause() : onStart()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(height: 44)
                // Use primaryAction (original green) instead of accent
                .background(Theme.Colors.primaryAction.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Reset") {
                    onReset()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(height: 44)
                .background((isRunning ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12)))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if isRunning {
                    Button("Finish") {
                        onFinish()
                    }
                    .buttonStyle(.bordered)
                    .tint(.clear)
                    .frame(height: 44)
                    .background((isRunning ? Color.red.opacity(0.18) : Color.secondary.opacity(0.12)))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Button("Finish") {
                        onFinish()
                    }
                    .buttonStyle(.bordered)
                    .tint(.clear)
                    .frame(height: 44)
                    .background((isRunning ? Color.red.opacity(0.18) : Color.secondary.opacity(0.12)))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .cardSurface()
    }
}
