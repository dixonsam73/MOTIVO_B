// DroneControlStripCard.swift
// Extracted from PracticeTimerView as part of refactor step 1.
// Visual + interaction wrapper for the drone/tuning strip.
// No logic changes; all state and engine references come from PracticeTimerView.
// CHANGE-ID: 20251204-DroneVolumeInlinePopover-B2
// SCOPE: Refine inline volume slider overlay — smaller glass panel, endpoint markers,
//         and auto-dismiss on interaction end.

import SwiftUI

struct DroneControlStripCard: View {
    @Binding var droneIsOn: Bool
    @Binding var droneVolume: Double
    @Binding var droneNoteIndex: Int
    @Binding var droneFreq: Int
    @Binding var showDroneVolumePopover: Bool

    let droneNotes: [String]
    let droneEngine: DroneEngine
    let recorderIcon: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Theme.Spacing.s) {

                // Start / Stop button
                Button(action: {
                    droneIsOn.toggle()
                    if droneIsOn {
                        let note = droneNotes[droneNoteIndex]
                        let base = Double(droneFreq)   // A4 reference from the wheel
                        let freq = DroneEngine.frequency(for: note, baseA4: base)
                        droneEngine.start(frequency: freq, volume: droneVolume)
                    } else {
                        droneEngine.stop()
                    }
                }) {
                    Image(systemName: "tuningfork")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(recorderIcon)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .background(
                    Group {
                        if droneIsOn {
                            // Fill the entire bordered button area
                            Color.clear
                                .overlay(
                                    Capsule(style: .continuous)
                                        .fill(Theme.Colors.primaryAction.opacity(0.18))
                                )
                        }
                    }
                )
                .clipShape(Capsule(style: .continuous))
                .accessibilityLabel(droneIsOn ? "Stop drone" : "Start drone")
                .accessibilityHint("Plays a continuous tuning tone for this session.")

                // Note wheel (A2–A6), in a bubble
                Picker("", selection: $droneNoteIndex) {
                    ForEach(droneNotes.indices, id: \.self) { i in
                        Text(droneNotes[i])
                            .font(Theme.Text.body)
                            .tag(i)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(width: 56, height: 56)
                .clipped()
                .tint(recorderIcon)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .onChange(of: droneNoteIndex) { _, newIndex in
                    let note = droneNotes[newIndex]
                    let base = Double(droneFreq)   // current A4 reference
                    let playFreq = DroneEngine.frequency(for: note, baseA4: base)
                    if droneIsOn {
                        droneEngine.update(frequency: playFreq)
                    }
                }

                // Frequency wheel (Hz) — A4 reference only, in a bubble
                Picker("", selection: $droneFreq) {
                    ForEach(392...460, id: \.self) { f in
                        Text("\(f) Hz")
                            .font(.caption2)
                            .tag(f)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(width: 78, height: 56)   // wider so “440 Hz” stays on one line
                .clipped()
                .tint(recorderIcon)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .onChange(of: droneFreq) { _, newF in
                    // Clamp defensively to the picker’s valid range
                    let clamped = min(max(newF, 392), 460)
                    if clamped != droneFreq {
                        droneFreq = clamped
                    }

                    let note = droneNotes[droneNoteIndex]
                    let base = Double(clamped)   // new A4 reference
                    let playFreq = DroneEngine.frequency(for: note, baseA4: base)
                    if droneIsOn {
                        droneEngine.update(frequency: playFreq)
                    }
                }

                // Volume button with anchored vertical slider overlay (as an overlay to avoid resizing the row)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showDroneVolumePopover.toggle()
                    }
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(recorderIcon)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Drone volume")
                .accessibilityHint("Adjusts the volume of the tuning tone.")
                .overlay(alignment: .top) {
                    if showDroneVolumePopover {
                        DroneVolumePopover(
                            value: $droneVolume,
                            onChanged: { newVal in
                                if droneIsOn {
                                    droneEngine.updateVolume(newVal)
                                }
                            },
                            onEditingEnded: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showDroneVolumePopover = false
                                }
                            }
                        )
                        .offset(y: -24)   // match the metronome centering
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)),
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom))
                            )
                        )
                        .zIndex(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct DroneVolumePopover: View {
    @Binding var value: Double
    let onChanged: (Double) -> Void
    let onEditingEnded: () -> Void

    var body: some View {
        ZStack {
            // Custom vertical rail with subtle endpoints
            VStack {
                Circle()
                    .fill(Theme.Colors.secondaryText.opacity(0.4))
                    .frame(width: 4, height: 4)

                Spacer(minLength: 0)

                Capsule()
                    .fill(Theme.Colors.secondaryText.opacity(0.25))
                    .frame(width: 3, height: 72)

                Spacer(minLength: 0)

                Circle()
                    .fill(Theme.Colors.secondaryText.opacity(0.4))
                    .frame(width: 4, height: 4)
            }
            .frame(width: 18, height: 88)

            // Actual interactive slider, rotated vertically and kept compact
            Slider(
                value: $value,
                in: 0...1,
                step: 0.01,
                onEditingChanged: { editing in
                    if !editing {
                        onEditingEnded()
                    }
                }
            )
            .tint(Theme.Colors.accent) // Motivo accent, no iOS blue
            .rotationEffect(.degrees(-90))
            .frame(width: 88, height: 32)
            .onChange(of: value) { _, newVal in
                onChanged(newVal)
            }
            .contentShape(Rectangle())
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(radius: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drone volume")
        .accessibilityHint("Swipe up or down to adjust the tuning tone volume.")
    }
}
