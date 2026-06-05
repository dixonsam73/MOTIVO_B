// CHANGE-ID: 20260605_190500_PRDV_StateStripExtract
// SCOPE: PostRecordDetailsView — Focus/state strip extraction only. No UI or logic changes.
// SEARCH-TOKEN: 20260605_190500_PRDV_StateStripExtract

import SwiftUI
import UIKit

extension PostRecordDetailsView {
    func storedFocusValue(forVisualFocusValue visualValue: Int) -> Int {
        FocusCircleView.storedFocusValue(forVisualFocusValue: visualValue)
    }

    func visualFocusValue(forStoredFocusValue storedValue: Int?) -> Int? {
        FocusCircleView.visualFocusValue(forStoredFocusValue: storedValue)
    }

    func updateFocusFromTrack(locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }

        let clampedX = max(0, min(locationX, width))
        let progress = clampedX / width
        let visualValue = visualFocusValue(forProgress: progress)
        let storedValue = storedFocusValue(forVisualFocusValue: visualValue)

        liveFocusProgress = progress
        selectedDotIndex = storedValue

        if lastHapticDot != visualValue {
            lastHapticDot = visualValue
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }

    func visualFocusValue(forProgress progress: CGFloat) -> Int {
        max(1, min(focusSnapCount, Int(round(progress * CGFloat(focusSnapCount - 1))) + 1))
    }

    func progressForVisualFocusValue(_ visualValue: Int?) -> CGFloat? {
        guard let visualValue else { return nil }
        return CGFloat(max(1, min(focusSnapCount, visualValue)) - 1) / CGFloat(focusSnapCount - 1)
    }

    func settleFocusTrackAfterDrag() {
        let snappedProgress = progressForVisualFocusValue(visualFocusValue(forStoredFocusValue: selectedDotIndex))
        withAnimation(.easeOut(duration: 0.16)) {
            liveFocusProgress = snappedProgress
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            liveFocusProgress = nil
        }
    }


    @ViewBuilder
    var stateStripCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Focus").sectionHeader()

            VStack(spacing: Theme.Spacing.s) {
                FocusCircleView(normalizedFocus: liveFocusProgress ?? progressForVisualFocusValue(visualFocusValue(forStoredFocusValue: selectedDotIndex)), size: 74)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)

                GeometryReader { geo in
                    let width = geo.size.width
                    let visualValue = visualFocusValue(forStoredFocusValue: selectedDotIndex)
                    let progress = liveFocusProgress ?? progressForVisualFocusValue(visualValue)
                    let knobSize: CGFloat = 18
                    let knobX = progress.map { min(max($0 * width, knobSize * 0.5), width - knobSize * 0.5) }

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(FocusCircleView.baseFocusColor.opacity(0.08))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity)

                        if let progress {
                            Capsule()
                                .fill(FocusCircleView.baseFocusColor.opacity(0.105))
                                .frame(width: max(0, width * progress), height: 5)
                        }

                        if let knobX {
                            Circle()
                                .fill(FocusCircleView.baseFocusColor.opacity(0.34))
                                .overlay(
                                    Circle()
                                        .stroke(FocusCircleView.baseFocusColor.opacity(0.15), lineWidth: 1)
                                )
                                .frame(width: knobSize, height: knobSize)
                                .position(x: knobX, y: 18)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateFocusFromTrack(locationX: value.location.x, width: width)
                            }
                            .onEnded { _ in
                                settleFocusTrackAfterDrag()
                                lastHapticDot = nil
                            }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Focus")
                    .accessibilityValue(visualValue.map { "\($0) of 10" } ?? "Unset")
                    .accessibilityAdjustableAction { direction in
                        let currentVisual = visualFocusValue(forStoredFocusValue: selectedDotIndex) ?? 5
                        let nextVisual: Int
                        switch direction {
                        case .increment:
                            nextVisual = min(focusSnapCount, currentVisual + 1)
                        case .decrement:
                            nextVisual = max(1, currentVisual - 1)
                        @unknown default:
                            return
                        }
                        selectedDotIndex = storedFocusValue(forVisualFocusValue: nextVisual)
                        liveFocusProgress = progressForVisualFocusValue(nextVisual)
                    }
                }
                .frame(height: 36)

                HStack {
                    Text("Unfocused")
                    Spacer()
                    Text("Focused")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(0.72)
            }
        }
        .cardSurface(padding: Theme.Spacing.m)
    }
}
