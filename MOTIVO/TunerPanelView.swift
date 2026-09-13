import SwiftUI
import UIKit

/// Tuner content only. The Timer owns the existing card transition and its animation transaction.
struct TunerPanelView: View {
    let state: TunerDisplayState
    let availability: TunerAvailability
    @Binding var referenceA4: Int
    let indicatorColor: Color
    let retry: () -> Void
    @State private var showsReference = false
    @ScaledMetric(relativeTo: .largeTitle) private var noteSize: CGFloat = 32
    @ScaledMetric(relativeTo: .title3) private var octaveSize: CGFloat = 22

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    referenceLabel.fixedSize().hidden().accessibilityHidden(true)
                    Spacer(minLength: 0)
                    noteReading.fixedSize()
                    Spacer(minLength: 0)
                    referenceButton.fixedSize()
                }
                VStack(spacing: 4) {
                    noteReading
                    referenceButton
                }.frame(maxWidth: .infinity)
            }
            .popover(isPresented: $showsReference) { referencePicker }

            VStack(spacing: 4) {
                GeometryReader { proxy in
                    let travel = max(proxy.size.width - 20, 1)
                    let marker = (state.indicatorOffset + 1) * travel / 2 + 10
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.16)).frame(height: 4)
                        Capsule()
                            .fill(Theme.Colors.primaryAction.opacity(state.hasSignal && state.isInTune ? 0.22 : 0.09))
                            .frame(width: travel * 12 / 100, height: 8)
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(Color.secondary.opacity(0.55))
                            .frame(width: 1, height: 14).frame(maxWidth: .infinity)
                        if state.hasSignal {
                            Rectangle().fill(state.isInTune ? Theme.Colors.primaryAction : indicatorColor)
                                .frame(width: 2, height: 22).offset(x: marker - 1)
                        }
                    }
                    .frame(height: 22)
                }
                .frame(height: 22)
                HStack {
                    Text("Flat")
                    Spacer()
                    Text("Sharp")
                }
                .font(.caption2)
                .foregroundStyle(Theme.Colors.secondaryText)
            }
            .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(statusLine).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 12)
                    Text(frequencyLine).monospacedDigit().fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusLine)
                    Text(frequencyLine).monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Theme.Text.meta)
            .foregroundStyle(Theme.Colors.secondaryText)
            .accessibilityHidden(true) // included in the single coherent pitch reading above

            if availability == .permissionDenied {
                Text("Allow microphone access in Settings to use the tuner.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(.bordered)
            } else if case .unavailable(let failure) = availability {
                Text(failure.explanation).font(.caption).foregroundStyle(.secondary)
                Button("Try again", action: retry).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var noteReading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(noteParts.name)
                .font(.system(size: noteSize, weight: .medium, design: .rounded))
            Text(noteParts.octave)
                .font(.system(size: octaveSize, weight: .regular, design: .rounded))
        }
        .foregroundStyle(noteColor)
        .frame(minHeight: noteSize * 1.2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tuner")
        .accessibilityValue(spokenReading)
    }

    private var referenceLabel: some View {
        HStack(spacing: 4) {
            Text("A4 = \(referenceA4) Hz")
            Image(systemName: "chevron.down").font(.caption2)
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var referenceButton: some View {
        Button { showsReference = true } label: { referenceLabel }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.secondaryText)
            .accessibilityLabel("Concert pitch")
            .accessibilityValue("A four, \(referenceA4) hertz")
            .accessibilityHint("Changes the tuning reference for the tuner and Drone.")
    }

    private var referencePicker: some View {
        VStack(spacing: 8) {
            Text("Concert pitch").font(.headline)
            Picker("A4 frequency", selection: $referenceA4) {
                ForEach(392...460, id: \.self) { value in
                    Text("\(value) Hz").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 180, height: 140)
            Text("Shared with the Drone")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }

    private var noteParts: (name: String, octave: String) {
        guard let note = state.noteName, let boundary = note.firstIndex(where: { $0.isNumber || $0 == "-" }) else {
            return (state.noteName ?? "—", "")
        }
        return (String(note[..<boundary]), String(note[boundary...]))
    }

    private var noteColor: Color {
        guard state.hasSignal else { return Theme.Colors.secondaryText }
        return state.isInTune ? Theme.Colors.primaryAction : Color.primary.opacity(0.8)
    }

    private var statusLine: String {
        switch availability {
        case .starting: return "Starting…"
        case .requestingPermission: return "Allow microphone access"
        case .permissionDenied: return "Microphone access is off"
        case .unavailable: return "Tuner unavailable"
        case .stopped, .listening:
            guard state.hasSignal, let cents = state.cents else {
                return state.noteName == nil ? "Play a note" : "Listening…"
            }
            if state.isInTune { return "In tune" }
            return cents < 0 ? "\(abs(cents)) cents flat" : "\(cents) cents sharp"
        }
    }

    private var frequencyLine: String {
        guard state.hasSignal, let frequency = state.frequencyHz else { return "— Hz" }
        return String(format: "%.1f Hz", frequency)
    }

    private var spokenReading: String {
        guard state.hasSignal, let note = state.spokenNote else {
            if let note = state.spokenNote { return "Last note, \(note). \(statusLine)" }
            return statusLine
        }
        return "\(note), \(statusLine), \(frequencyLine.replacingOccurrences(of: "Hz", with: "hertz"))"
    }
}
