// MetronomeControlStripCard.swift
// Companion control strip for MetronomeEngine.
// UI parity with DroneControlStripCard: start/stop, BPM wheel, accent-every-N, volume overlay.

import SwiftUI

struct MetronomeControlStripCard: View {
    @Binding var metronomeIsOn: Bool
    @Binding var metronomeBPM: Int          // e.g. 40–220
    @Binding var metronomeAccentEvery: Int  // 0 = off, 2…N = accent every N beats
    @Binding var metronomeVolume: Double    // 0–1

    let metronomeEngine: MetronomeEngine
    let recorderIcon: Color

    @State private var showMetronomeVolumePopover = false

    private let bpmRange: ClosedRange<Int> = 40...220
    /// 0 = off, then 2…16 (you can tweak this list later).
    private let accentValues: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Theme.Spacing.s) {

                // Start / Stop
                Button(action: toggleMetronome) {
                    Image(systemName: metronomeIsOn ? "metronome.fill" : "metronome")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(recorderIcon)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .background(
                    Group {
                        if metronomeIsOn {
                            Color.clear
                                .overlay(
                                    Capsule(style: .continuous)
                                        .fill(Theme.Colors.primaryAction.opacity(0.18))
                                )
                        }
                    }
                )
                .clipShape(Capsule(style: .continuous))
                .accessibilityLabel(metronomeIsOn ? "Stop metronome" : "Start metronome")

                // BPM wheel
                Picker("", selection: $metronomeBPM) {
                    ForEach(bpmRange, id: \.self) { bpm in
                        Text("\(bpm)")
                            .font(Theme.Text.body)
                            .tag(bpm)
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
                .onChange(of: metronomeBPM) { newBPM in
                    let clamped = min(max(newBPM, bpmRange.lowerBound), bpmRange.upperBound)
                    if clamped != metronomeBPM {
                        metronomeBPM = clamped
                    }
                    if metronomeIsOn {
                        metronomeEngine.update(
                            bpm: metronomeBPM,
                            accentEvery: metronomeAccentEvery,
                            volume: metronomeVolume
                        )
                    }
                }
                .accessibilityLabel("Tempo in beats per minute")

                // Accent-every-N-beats wheel (0 = off)
                Picker("", selection: $metronomeAccentEvery) {
                    ForEach(accentValues, id: \.self) { value in
                        Text(accentLabel(for: value))
                            .font(.caption2)
                            .tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(width: 78, height: 56)   // match drone frequency wheel width
                .clipped()
                .tint(recorderIcon)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .onChange(of: metronomeAccentEvery) { rawValue in
                    let clamped = clampAccent(raw: rawValue)
                    if clamped != metronomeAccentEvery {
                        metronomeAccentEvery = clamped
                    }
                    if metronomeIsOn {
                        metronomeEngine.update(
                            bpm: metronomeBPM,
                            accentEvery: metronomeAccentEvery,
                            volume: metronomeVolume
                        )
                    }
                }
                .accessibilityLabel("Accent every N beats")

                // Volume button with anchored vertical slider overlay
                ZStack(alignment: .top) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showMetronomeVolumePopover.toggle()
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
                    .accessibilityLabel("Metronome volume")

                    if showMetronomeVolumePopover {
                        MetronomeVolumePopover(
                            value: $metronomeVolume,
                            onChanged: { newVal in
                                if metronomeIsOn {
                                    metronomeEngine.update(
                                        bpm: metronomeBPM,
                                        accentEvery: metronomeAccentEvery,
                                        volume: metronomeVolume
                                    )
                                }
                            },
                            onEditingEnded: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showMetronomeVolumePopover = false
                                }
                            }
                        )
                        .offset(y: -6)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)),
                                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom))
                            )
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Actions

    private func toggleMetronome() {
        metronomeIsOn.toggle()
        if metronomeIsOn {
            metronomeEngine.start(
                bpm: metronomeBPM,
                accentEvery: metronomeAccentEvery,
                volume: metronomeVolume
            )
        } else {
            metronomeEngine.stop()
        }
    }

    // MARK: - Helpers

    private func accentLabel(for value: Int) -> String {
        if value <= 0 {
            return "None"
        } else {
            return "Every \(value)"
        }
    }

    private func clampAccent(raw: Int) -> Int {
        if raw <= 0 { return 0 }
        // Ensure value is one of accentValues; fall back to nearest.
        if accentValues.contains(raw) { return raw }
        let positive = accentValues.filter { $0 > 0 }
        guard let nearest = positive.min(by: { abs($0 - raw) < abs($1 - raw) }) else {
            return 0
        }
        return nearest
    }
}

// MARK: - Volume popover

private struct MetronomeVolumePopover: View {
    @Binding var value: Double
    let onChanged: (Double) -> Void
    let onEditingEnded: () -> Void

    var body: some View {
        ZStack {
            // Vertical rail + endpoints
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

            // Interactive slider rotated vertically
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
            .tint(Theme.Colors.accent)
            .rotationEffect(.degrees(-90))
            .frame(width: 88, height: 32)
            .onChange(of: value) { newVal in
                // Clamp + notify
                let clamped = max(0.0, min(1.0, newVal))
                if clamped != value {
                    value = clamped
                }
                onChanged(clamped)
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
        .accessibilityLabel("Metronome volume")
        .accessibilityHint("Swipe up or down to adjust the metronome volume.")
    }
}
