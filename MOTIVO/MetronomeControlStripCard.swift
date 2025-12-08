// MetronomeControlStripCard.swift
// Companion control strip for MetronomeEngine.
// UI parity with DroneControlStripCard: start/stop, BPM wheel, accent-every-N, volume overlay.

import SwiftUI

struct MetronomeControlStripCard: View {
    @Binding var metronomeIsOn: Bool
    @Binding var metronomeBPM: Int          // e.g. 20–400
    @Binding var metronomeAccentEvery: Int  // 0 = off, 1…N = accent every N beats
    @Binding var metronomeVolume: Double    // 0–1

    let metronomeEngine: MetronomeEngine
    let recorderIcon: Color

    @State private var showMetronomeVolumePopover = false

    // UI beat/animation state
    @State private var accentFlashIntensity: Double = 0.0
    @State private var metronomeSwingRight: Bool = false

    // Tap tempo state (dedicated Tap button)
    @State private var tapTempoTimestamps: [Date] = []

    private let bpmRange: ClosedRange<Int> = 20...400
    /// 0 = off, then 1…15 (covers practical subdivisions).
    private let accentValues: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

    // Tap tempo tuning
    private let tapTempoMaxInterval: TimeInterval = 2.0  // window for considering taps (seconds)
    private let tapTempoMinTaps: Int = 2                 // minimum taps to compute BPM

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Theme.Spacing.s) {

                // Start / Stop
                Button(action: toggleMetronome) {
                    MetronomeIcon(
                        isOn: metronomeIsOn,
                        swingRight: metronomeSwingRight,
                        color: recorderIcon
                    )
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

                // Tap tempo button
                Button(action: handleTapTempoTap) {
                    Text("Tap")
                        .font(Theme.Text.body)
                        .foregroundStyle(recorderIcon)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule(style: .continuous))
                .accessibilityLabel("Tap tempo")

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
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.orange.opacity(0.18 * accentFlashIntensity))
                        )
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
                            onChanged: { _ in
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
        .onAppear {
            // Ensure UI flag matches the real engine state on entry/return
            metronomeIsOn = metronomeEngine.isRunning

            metronomeEngine.onBeat = { isAccent in
                let beatDuration = 60.0 / Double(metronomeBPM)

                // Swing the arm every beat with spring/inertia (arm "mass")
                let response = max(0.12, min(beatDuration * 0.55, 0.35))
                withAnimation(
                    .spring(
                        response: response,
                        dampingFraction: 0.72,
                        blendDuration: 0.1
                    )
                ) {
                    metronomeSwingRight.toggle()
                }

                // Flash the accent bubble only on accented beats
                if isAccent {
                    accentFlashIntensity = 1.0
                    withAnimation(.linear(duration: beatDuration)) {
                        accentFlashIntensity = 0.0
                    }
                } else {
                    accentFlashIntensity = 0.0
                }
            }
        }
        .onDisappear {
            metronomeEngine.onBeat = nil
        }
    }

    // MARK: - Actions

    private func toggleMetronome() {
        // Use the engine as the source of truth, then sync the binding.
        let currentlyRunning = metronomeEngine.isRunning

        if currentlyRunning {
            metronomeEngine.stop()
            metronomeIsOn = false
        } else {
            metronomeEngine.start(
                bpm: metronomeBPM,
                accentEvery: metronomeAccentEvery,
                volume: metronomeVolume
            )
            metronomeIsOn = true
        }
    }

    /// Handle a tap-tempo tap (from the dedicated Tap button).
    private func handleTapTempoTap() {
        let now = Date()

        // Add this tap and keep only recent ones
        tapTempoTimestamps.append(now)
        tapTempoTimestamps = tapTempoTimestamps.filter {
            now.timeIntervalSince($0) <= tapTempoMaxInterval
        }

        guard tapTempoTimestamps.count >= tapTempoMinTaps else { return }

        // Compute average interval between taps
        let sorted = tapTempoTimestamps.sorted()
        let pairs = zip(sorted.dropFirst(), sorted)
        let intervals = pairs.map { $0.0.timeIntervalSince($0.1) }
        guard !intervals.isEmpty else { return }

        let total = intervals.reduce(0, +)
        guard total > 0 else { return }

        let averageInterval = total / Double(intervals.count)
        guard averageInterval > 0 else { return }

        let bpmDouble = 60.0 / averageInterval
        let clampedBPM = max(Double(bpmRange.lowerBound),
                             min(Double(bpmRange.upperBound), bpmDouble))
        let newBPM = Int(clampedBPM.rounded())

        metronomeBPM = newBPM

        if metronomeIsOn {
            metronomeEngine.update(
                bpm: metronomeBPM,
                accentEvery: metronomeAccentEvery,
                volume: metronomeVolume
            )
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
        if accentValues.contains(raw) { return raw }
        let positive = accentValues.filter { $0 > 0 }
        guard let nearest = positive.min(by: { abs($0 - raw) < abs($1 - raw) }) else {
            return 0
        }
        return nearest
    }
}

// MARK: - Custom Metronome Icon (Outlined Body + Swinging Arm)

private struct MetronomeIcon: View {
    let isOn: Bool
    let swingRight: Bool
    let color: Color

    var body: some View {
        ZStack {
            // Body: trapezoid with a small flat top (reads like a classic wooden metronome)
            Path { path in
                // Top edge (short, centered)
                path.move(to: CGPoint(x: 9, y: 3))    // top-left
                path.addLine(to: CGPoint(x: 15, y: 3)) // top-right

                // Down to base
                path.addLine(to: CGPoint(x: 18, y: 19)) // bottom-right
                path.addLine(to: CGPoint(x: 6, y: 19))  // bottom-left

                // Close back to top-left
                path.closeSubpath()
            }
            .stroke(color, lineWidth: 1.6)

            // Base
            Capsule(style: .continuous)
                .frame(width: 16, height: 3)
                .offset(y: 9)
                .foregroundStyle(color.opacity(0.9))

            // Arm (only thing that moves)
            Rectangle()
                .frame(width: 1.5, height: 14)
                .offset(y: 3)
                .rotationEffect(
                    .degrees(isOn ? (swingRight ? 16 : -16) : 0),
                    anchor: .bottom
                )
                .foregroundStyle(color)
        }
        .frame(width: 24, height: 24)
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
