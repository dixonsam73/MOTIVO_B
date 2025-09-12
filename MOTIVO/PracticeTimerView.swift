//
//  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import Combine
import CoreData

struct PracticeTimerView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Presented as a sheet from ContentView
    @Binding var isPresented: Bool

    // Instruments (profile)
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?

    // Timer state
    @State private var isRunning = false
    @State private var startDate: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var ticker: AnyCancellable?

    // Review sheet
    @State private var showReviewSheet = false

    // Optional quick notes (kept for future; currently not passed forward)
    @State private var quickNotes: String = ""

    // Convenience flags
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Instrument selection
                Group {
                    if hasNoInstruments {
                        VStack(spacing: 6) {
                            Text("No instruments found")
                                .font(.headline)
                            Text("Add an instrument in your Profile to start timing practice.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    } else if hasOneInstrument {
                        HStack {
                            Text("Instrument")
                            Spacer()
                            Text(instruments.first?.name ?? "—")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    } else {
                        HStack {
                            Text("Instrument")
                            Spacer()
                            Picker("", selection: $instrument) {
                                ForEach(instruments, id: \.self) { inst in
                                    Text(inst.name ?? "").tag(inst as Instrument?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal)
                    }
                }

                // Timer display
                Text(formattedElapsed(elapsedSeconds))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()

                // Controls
                HStack(spacing: 16) {
                    Button(isRunning ? "Pause" : "Start") {
                        isRunning ? pause() : start()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hasNoInstruments || instrument == nil)

                    Button("Reset") { reset() }
                        .buttonStyle(.bordered)
                        .disabled(elapsedSeconds == 0 && !isRunning)

                    Button("Finish") { finish() }
                        .buttonStyle(.bordered)
                        .disabled(elapsedSeconds == 0 || instrument == nil)
                }

                // Optional quick notes
                VStack(alignment: .leading) {
                    Text("Quick Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $quickNotes)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Practice Timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                instruments = fetchInstruments()
                if hasOneInstrument {
                    instrument = instruments.first
                }
            }
            .sheet(isPresented: $showReviewSheet) {
                PostRecordDetailsView(
                    isPresented: $showReviewSheet,
                    timestamp: startDate ?? Date(),
                    durationSeconds: elapsedSeconds,
                    instrument: instrument,
                    onSaved: {
                        // Reset timer and close timer sheet after saving
                        reset()
                        isPresented = false
                    }
                )
                .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    // MARK: - Instruments

    private func fetchInstruments() -> [Instrument] {
        let req: NSFetchRequest<Instrument> = Instrument.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? viewContext.fetch(req)) ?? []
    }

    // MARK: - Timer controls

    private func start() {
        guard instrument != nil else { return }
        if startDate == nil { startDate = Date() }
        isRunning = true
        startTicker()
    }

    private func pause() {
        guard isRunning else { return }
        isRunning = false
        ticker?.cancel(); ticker = nil
    }

    private func reset() {
        pause()
        startDate = nil
        elapsedSeconds = 0
        quickNotes = ""
    }

    private func finish() {
        pause()
        showReviewSheet = true
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if isRunning { elapsedSeconds += 1 }
            }
    }

    private func formattedElapsed(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                      : String(format: "%02d:%02d", m, s)
    }
}
