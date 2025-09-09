//
//  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct PracticeTimerView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var instruments: FetchedResults<Instrument>

    @FetchRequest(entity: Profile.entity(), sortDescriptors: [])
    private var profiles: FetchedResults<Profile>

    // Form state
    @State private var selectedInstrument: String = ""
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var didAutoSetTitle: Bool = true

    // Timing (clock-true)
    @State private var hasStarted: Bool = false
    @State private var isRunning: Bool = false
    @State private var startedAt: Date = Date()
    @State private var elapsedDisplay: Int = 0
    @State private var totalPausedSeconds: Int = 0
    @State private var pauseBeganAt: Date? = nil

    // UI flags
    @State private var showingDiscardAlert: Bool = false
    @State private var showingInstruments: Bool = false
    @State private var showingDetails: Bool = false
    @State private var finishedDuration: Int = 0

    // Foreground ticker
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                SetupSection(
                    instrumentList: instrumentList(),
                    selectedInstrument: $selectedInstrument,
                    title: $title,
                    isRunning: isRunning,
                    manageInstruments: { showingInstruments = true },
                    onSelectedInstrumentChange: { newValue in
                        if didAutoSetTitle { title = defaultTitle(for: newValue) }
                    },
                    onTitleChange: { newValue in
                        let def = defaultTitle(for: selectedInstrument)
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed != def { didAutoSetTitle = false }
                    },
                    startedAt: $startedAt
                )

                RecordingSection(
                    hasStarted: hasStarted,
                    isRunning: isRunning,
                    elapsedText: formatted(elapsedDisplay),
                    onStart: start,
                    onPause: pause,
                    onResume: resume,
                    onFinish: finish
                )

                NotesSection(notes: $notes)
            }
            .navigationTitle("Record Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { handleClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isRunning { PulsingDot().accessibilityLabel("Recording in progress") }
                }
            }
            .sheet(isPresented: $showingInstruments) {
                InstrumentListView().environment(\.managedObjectContext, moc)
            }
            .sheet(isPresented: $showingDetails) {
                // Pass a callback so Save closes BOTH sheets
                PostRecordDetailsView(
                    proposedTitle: titleIfEmptyDefault(),
                    startedAt: startedAt,
                    durationSeconds: finishedDuration,
                    existingNotes: notes,
                    onSaved: {
                        // Close details sheet and the timer itself
                        showingDetails = false
                        resetTiming()
                        dismiss()
                    }
                )
                .environment(\.managedObjectContext, moc)
            }
            .onAppear {
                seedDefaultsFromProfile()
                resetTiming()
            }
            .onReceive(ticker) { _ in
                if isRunning { elapsedDisplay = clockElapsedNow() }
            }
            .onChange(of: scenePhase) { _ in
                if hasStarted && isRunning { elapsedDisplay = clockElapsedNow() }
            }
            .alert("Discard this recording?", isPresented: $showingDiscardAlert) {
                Button("Discard", role: .destructive) {
                    resetTiming()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your elapsed time will be lost.")
            }
        }
    }

    // MARK: - Derived data

    private func instrumentList() -> [String] {
        var names: [String] = instruments.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
        names = names.filter { !$0.isEmpty }
        if names.isEmpty {
            let primary = profiles.first?.primaryInstrument?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return primary.isEmpty ? ["Practice"] : [primary]
        }
        return names
    }

    // MARK: - Flow actions

    private func seedDefaultsFromProfile() {
        let list = instrumentList()
        selectedInstrument = list.first ?? "Practice"
        title = defaultTitle(for: selectedInstrument)
        didAutoSetTitle = true
    }

    private func handleClose() {
        let hasData = elapsedDisplay > 0 || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !notes.isEmpty
        if hasStarted && hasData {
            showingDiscardAlert = true
        } else {
            dismiss()
        }
    }

    private func start() {
        hasStarted = true
        isRunning = true
        startedAt = Date()
        elapsedDisplay = 0
        totalPausedSeconds = 0
        pauseBeganAt = nil
        if didAutoSetTitle { title = defaultTitle(for: selectedInstrument) }
    }

    private func pause() {
        guard hasStarted, isRunning else { return }
        isRunning = false
        pauseBeganAt = Date()
        elapsedDisplay = clockElapsedNow()
    }

    private func resume() {
        guard hasStarted, !isRunning else { return }
        if let pauseStart = pauseBeganAt {
            let delta = Int(Date().timeIntervalSince(pauseStart))
            if delta > 0 { totalPausedSeconds += delta }
        }
        pauseBeganAt = nil
        isRunning = true
        elapsedDisplay = clockElapsedNow()
    }

    private func finish() {
        guard hasStarted else { return }

        // Normalize pause state so elapsed is stable
        if let pauseStart = pauseBeganAt {
            let delta = Int(Date().timeIntervalSince(pauseStart))
            if delta > 0 { totalPausedSeconds += delta }
            pauseBeganAt = nil
        }
        isRunning = false
        elapsedDisplay = clockElapsedNow()
        finishedDuration = max(elapsedDisplay, clockElapsedNow())

        // Open details; it will handle saving & dismissing
        showingDetails = true
    }

    // MARK: - Timing (clock-true)

    private func clockElapsedNow() -> Int {
        let now = Date()
        var paused = totalPausedSeconds
        if let pauseStart = pauseBeganAt {
            let add = Int(now.timeIntervalSince(pauseStart))
            if add > 0 { paused += add }
        }
        let span = Int(now.timeIntervalSince(startedAt))
        return max(0, span - paused)
    }

    private func resetTiming() {
        hasStarted = false
        isRunning = false
        startedAt = Date()
        elapsedDisplay = 0
        totalPausedSeconds = 0
        pauseBeganAt = nil
        notes = ""
        // keep title/instrument for next run
    }

    // MARK: - Titles / formatting

    private func defaultTitle(for instrument: String) -> String {
        let inst = instrument.trimmingCharacters(in: .whitespacesAndNewlines)
        return (inst.isEmpty || inst.lowercased() == "practice") ? "Practice Session" : "\(inst) Practice"
    }

    private func titleIfEmptyDefault() -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? defaultTitle(for: selectedInstrument) : t
    }

    private func formatted(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Tiny subviews

private struct SetupSection: View {
    let instrumentList: [String]
    @Binding var selectedInstrument: String
    @Binding var title: String
    let isRunning: Bool
    let manageInstruments: () -> Void
    let onSelectedInstrumentChange: (String) -> Void
    let onTitleChange: (String) -> Void
    @Binding var startedAt: Date

    var body: some View {
        Section("Setup") {
            HStack {
                Picker("Instrument", selection: $selectedInstrument) {
                    ForEach(instrumentList, id: \.self) { inst in
                        Text(inst).tag(inst)
                    }
                }
                Button(action: manageInstruments) {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Manage Instruments")
            }
            .onChange(of: selectedInstrument) { _, newValue in
                onSelectedInstrumentChange(newValue)
            }

            TextField("Title", text: $title)
                .textInputAutocapitalization(.words)
                .onChange(of: title) { _, newValue in
                    onTitleChange(newValue)
                }

            DatePicker("Started", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                .disabled(isRunning)
        }
    }
}

private struct RecordingSection: View {
    let hasStarted: Bool
    let isRunning: Bool
    let elapsedText: String
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Text(elapsedText)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    if hasStarted {
                        if isRunning {
                            HStack(spacing: 16) {
                                Button(action: onPause) { Label("Pause", systemImage: "pause.fill") }
                                    .buttonStyle(.bordered)
                                Button(action: onFinish) { Label("Finish", systemImage: "stop.fill") }
                                    .buttonStyle(.borderedProminent).tint(.red)
                            }
                        } else {
                            HStack(spacing: 16) {
                                Button(action: onResume) { Label("Resume", systemImage: "play.fill") }
                                    .buttonStyle(.bordered)
                                Button(action: onFinish) { Label("Finish", systemImage: "stop.fill") }
                                    .buttonStyle(.borderedProminent).tint(.red)
                            }
                        }
                    } else {
                        Button(action: onStart) {
                            Label("Start Recording", systemImage: "record.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
        } header: {
            Text("Recording")
        } footer: {
            Text("Finish to review and save. Accurate even if you switch apps or lock your device.")
        }
    }
}

private struct NotesSection: View {
    @Binding var notes: String
    var body: some View {
        Section("Notes") {
            TextField("What did you practice?", text: $notes, axis: .vertical)
                .lineLimit(4...8)
        }
    }
}

private struct PulsingDot: View {
    @State private var animate: Bool = false
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .scaleEffect(animate ? 1.2 : 0.9)
            .opacity(animate ? 1.0 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }
}
