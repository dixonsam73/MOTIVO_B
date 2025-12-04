// DroneControlStripCard.swift
// Extracted from PracticeTimerView as part of refactor step 1.
// Visual + interaction wrapper for the drone/tuning strip.
// No logic changes; all state and engine references come from PracticeTimerView.

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
                                ForEach(400...480, id: \.self) { f in
                                    Text("\(f) Hz")
                                        .font(.caption2)
                                        .tag(f)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.wheel)
                            .frame(width: 72, height: 56)   // wider so “440 Hz” stays on one line
                            .clipped()
                            .tint(recorderIcon)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )

                            .onChange(of: droneFreq) { _, newF in
                                // Clamp defensively to the picker’s valid range
                                let clamped = min(max(newF, 400), 480)
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

                            // Volume button (opens slider)
                            Button {
                                showDroneVolumePopover.toggle()
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(recorderIcon)
                                    .frame(width: 36, height: 36)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.bordered)
                            .popover(isPresented: $showDroneVolumePopover) {
                                VStack {
                                    Text("Drone volume")
                                        .font(Theme.Text.body)
                                    Slider(value: $droneVolume, in: 0...1, step: 0.01)
                                        .padding(.horizontal)
                                        .onChange(of: droneVolume) { _, newVal in
                                            if droneIsOn {
                                                droneEngine.updateVolume(newVal)
                                            }
                                        }
                                }
                                .padding()
                            }
                            .accessibilityLabel("Drone volume")
                            .accessibilityHint("Adjusts the volume of the tuning tone.")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
    }
}
