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

    @Binding var isPresented: Bool

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default
    ) private var instruments: FetchedResults<Instrument>

    @State private var isRunning = false
    @State private var startDate: Date? = nil
    @State private var elapsedSeconds = 0
    @State private var ticker: AnyCancellable? = nil

    @State private var selectedInstrument: Instrument? = nil
    @State private var quickNotes = ""

    @State private var showReviewSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack {
                    Text("Instrument"); Spacer()
                    Menu {
                        Button("Select…") { selectedInstrument = nil }
                        Divider()
                        ForEach(instruments, id: \.objectID) { inst in
                            Button { selectedInstrument = inst } label: {
                                HStack { Text(inst.name ?? "(Unnamed)"); if selectedInstrument?.objectID == inst.objectID { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: { Text(selectedInstrument?.name ?? "Select").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Text(formattedElapsed(elapsedSeconds))
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.top, 8)

                HStack(spacing: 16) {
                    if isRunning {
                        Button { pause() } label: { Label("Pause", systemImage: "pause.circle.fill").font(.title2) }
                    } else {
                        if elapsedSeconds == 0 {
                            Button { start() } label: { Label("Start", systemImage: "play.circle.fill").font(.title2) }
                        } else {
                            Button { resume() } label: { Label("Resume", systemImage: "play.circle.fill").font(.title2) }
                        }
                    }
                    Button(role: .destructive) { reset() } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise.circle.fill").font(.title3)
                    }
                    .disabled(elapsedSeconds == 0 && !isRunning)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Notes").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $quickNotes)
                        .frame(minHeight: 100)
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1) }
                }
                .padding(.horizontal)

                Spacer()

                Button { finish() } label: {
                    Text("Finish & Review")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .disabled(elapsedSeconds == 0 || selectedInstrument == nil)
            }
            .padding(.vertical, 16)
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .sheet(isPresented: $showReviewSheet) {
                PostRecordDetailsView(
                    isPresented: $showReviewSheet,
                    timestamp: startDate ?? Date(),
                    durationSeconds: elapsedSeconds,
                    instrument: selectedInstrument,
                    onSaved: { isPresented = false } // close parent AFTER the review saves
                )
            }
            .onAppear {
                if selectedInstrument == nil, let first = instruments.first { selectedInstrument = first }
            }
            .onDisappear {
                ticker?.cancel(); ticker = nil
            }
        }
    }

    private func start() { guard !isRunning else { return }; startDate = Date(); isRunning = true; startTicker() }
    private func resume() { guard !isRunning else { return }; isRunning = true; startTicker() }
    private func pause() { guard isRunning else { return }; isRunning = false; ticker?.cancel(); ticker = nil }
    private func reset() { pause(); startDate = nil; elapsedSeconds = 0; quickNotes = "" }
    private func finish() { pause(); showReviewSheet = true }
    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect().sink { _ in
            if isRunning { elapsedSeconds += 1 }
        }
    }
    private func formattedElapsed(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
