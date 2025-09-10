//
//  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct PracticeTimerView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // Instruments
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var instruments: FetchedResults<Instrument>

    // Timer state
    @StateObject private var recovery = TimerStateRecovery.shared
    @State private var startedAt: Date?
    @State private var isRunning: Bool = false

    // Live ticking
    @State private var now = Date()
    private let uiTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Selection
    @State private var selectedInstrument: String = ""

    // Notes
    @State private var quickNotes: String = ""

    // Routing
    @State private var showDetailsSheet: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {

                // Instrument picker (header removed)
                Picker("Instrument", selection: $selectedInstrument) {
                    Text("—").tag("")
                    ForEach(instrumentNames, id: \.self) { ins in
                        Text(ins).tag(ins)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                // Timer readout
                Text(formatElapsed(recovery.elapsedSeconds(now: now)))
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                // Controls
                HStack(spacing: 20) {
                    if isRunning {
                        Button {
                            pause()
                        } label: {
                            Label("Pause", systemImage: "pause.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.title2)
                        }
                    } else {
                        Button {
                            startOrResume()
                        } label: {
                            Label(startedAt == nil ? "Start" : "Resume", systemImage: "play.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.title2)
                        }
                    }

                    Button {
                        finish()
                    } label: {
                        Label("Finish", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.title2)
                    }
                    .disabled(recovery.elapsedSeconds(now: now) == 0)
                }

                // Quick notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $quickNotes)
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .navigationTitle("Practice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            adoptPrimaryInstrumentIfNeeded()
            adoptRecoveredState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            recovery.scenePhaseDidChange(newPhase)
        }
        .onReceive(uiTimer) { _ in
            if isRunning { now = Date() }
        }
        .sheet(isPresented: $showDetailsSheet) {
            PostRecordDetailsView(
                proposedTitle: proposedTitle,
                startedAt: startedAt ?? Date(),
                durationSeconds: recovery.elapsedSeconds(now: now),
                notes: quickNotes,
                instrumentName: selectedInstrument,
                onSaved: {
                    recovery.clear()
                    startedAt = nil
                    isRunning = false
                    quickNotes = ""
                    dismiss()
                }
            )
        }
    }

    // MARK: - Derived

    private var instrumentNames: [String] {
        instruments
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var proposedTitle: String {
        let ins = selectedInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        return ins.isEmpty ? "Practice Session" : "\(ins) Practice"
    }

    // MARK: - Actions

    private func startOrResume() {
        if startedAt == nil { startedAt = Date() }
        recovery.start(resumeFrom: recovery.elapsedSeconds(now: now))
        isRunning = true
        now = Date()
    }

    private func pause() {
        recovery.pause()
        isRunning = false
    }

    private func finish() {
        if isRunning { pause() }
        showDetailsSheet = true
    }

    private func adoptPrimaryInstrumentIfNeeded() {
        guard selectedInstrument.isEmpty else { return }
        let fr: NSFetchRequest<Profile> = Profile.fetchRequest()
        fr.fetchLimit = 1
        let primary = (try? ctx.fetch(fr).first?.primaryInstrument) ?? ""
        if !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedInstrument = primary
        } else if let first = instrumentNames.first {
            selectedInstrument = first
        } else {
            selectedInstrument = ""
        }
    }

    private func adoptRecoveredState() {
        let snap = recovery.snapshot
        switch snap.mode {
        case .idle:
            isRunning = false
        case .paused:
            isRunning = false
            if startedAt == nil { startedAt = Date() }
        case .running:
            isRunning = true
            if startedAt == nil { startedAt = Date() }
            now = Date()
        }
    }
}

// MARK: - Formatter
private func formatElapsed(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%02d:%02d", m, s)
    }
}
