//////
// //  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import Combine
import CoreData


fileprivate enum ActivityType: Int16, CaseIterable, Identifiable {
    case practice = 0, rehearsal = 1, recording = 2, lesson = 3, performance = 4
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .practice: return "Practice"
        case .rehearsal: return "Rehearsal"
        case .recording: return "Recording"
        case .lesson: return "Lesson"
        case .performance: return "Performance"
        }
    }
}



struct PracticeTimerView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Presented as a sheet from ContentView
    @Binding var isPresented: Bool

    // Instruments (profile)
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var activity: ActivityType = .practice
    @State private var userActivities: [UserActivity] = []
    @State private var activityChoice: String = "core:0"
    @State private var activityDetail: String = ""

    // Timer state
    @State private var isRunning = false
    @State private var startDate: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var ticker: AnyCancellable?

    // Review sheet
    @State private var showReviewSheet = false

    // Info sheets for prebuilt-in recording guidance
    @State private var showAudioHelp = false
    @State private var showVideoHelp = false

    // Quick notes
    

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
                            Text("Add an instrument in your Profile to start timing sessions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        VStack(spacing: 8) {
                           

                            if hasMultipleInstruments {
                                Picker("Instrument", selection: $instrument) {
                                    ForEach(instruments, id: \.self) { inst in
                                        Text(inst.name ?? "Instrument").tag(inst as Instrument?)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else if let only = instruments.first {
                                HStack {
                                    Text(only.name ?? "Instrument")
                                        .font(.headline)
                                    Spacer()
                                }
                                .onAppear { instrument = only }
                            }

                        // Activity
                        Section {
                           
                            Picker("Activity", selection: $activityChoice) {
                                ForEach(ActivityType.allCases) { a in
                                    Text(a.label).tag("core:\(a.rawValue)")
                                }
                                if !userActivities.isEmpty {
                                    Text("— Your Activities —").disabled(true)
                                    ForEach(userActivities.compactMap { $0.displayName }, id: \.self) { name in
                                        Text(name).tag("custom:\(name)")
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: activityChoice) { choice in
                                if choice.hasPrefix("core:") {
                                    if let raw = Int(choice.split(separator: ":").last ?? "0") {
                                        activity = ActivityType(rawValue: Int16(raw)) ?? .practice
                                    } else {
                                        activity = .practice
                                    }
                                    activityDetail = ""
                                } else if choice.hasPrefix("custom:") {
                                    let name = String(choice.dropFirst("custom:".count))
                                    activity = .practice
                                    activityDetail = name
                                }
                            }
                        }
                        .padding(.horizontal)

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

                // Recording icons (info-only, prebuilt-ins)
                VStack(spacing: 12) {
                    Divider().padding(.horizontal)
                    HStack(spacing: 24) {
                        Button { showAudioHelp = true } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Record audio help")
                        .accessibilityHint("Opens instructions for using your device’s app to capture audio.")

                        Button { showVideoHelp = true } label: {
                            Image(systemName: "video.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Record video help")
                        .accessibilityHint("Opens instructions for using your device’s app to capture video.")
                    }
                }

                                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .navigationTitle("Session Timer")
            .task { loadUserActivities() }
            .onAppear { syncActivityChoiceFromState() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .onAppear {
                instruments = fetchInstruments()

                // NEW: auto-select primary instrument if available (even when multiple exist)
                if instrument == nil {
                    if let primaryName = fetchPrimaryInstrumentName(),
                       let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                        instrument = match
                    } else if hasOneInstrument {
                        instrument = instruments.first
                    }
                }
            }
            .sheet(isPresented: $showReviewSheet) {
                PostRecordDetailsView(
                    isPresented: $showReviewSheet,
                    timestamp: startDate ?? Date(),
                    durationSeconds: elapsedSeconds,
                    instrument: instrument,
                    activityTypeRaw: activity.rawValue,
                    activityDetailPrefill: activityDetail.isEmpty ? nil : activityDetail,
                    onSaved: {
                        // Reset timer and close timer sheet after saving
                        reset()
                        isPresented = false
                    }
                )
            }
            .sheet(isPresented: $showAudioHelp) {
                InfoSheetView(
                    title: "Quick audio takes (for now)",
                    bullets: [
                        "Open Voice Memos to record.",
                        "Share to Files when done.",
                        "Back here, use Add Attachment to include it."
                    ],
                    primaryCTA: nil
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showVideoHelp) {
                InfoSheetView(
                    title: "Quick video clips (for now)",
                    bullets: [
                        "Open Camera → Video to record.",
                        "Save to Photos or Files.",
                        "Back here, use Add Attachment to include it."
                    ],
                    primaryCTA: nil
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Actions & fetches

    private func fetchInstruments() -> [Instrument] {
        let req: NSFetchRequest<Instrument> = Instrument.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? viewContext.fetch(req)) ?? []
    }

    private func fetchPrimaryInstrumentName() -> String? {
        let req: NSFetchRequest<Profile> = Profile.fetchRequest()
        req.fetchLimit = 1
        if let profile = try? viewContext.fetch(req).first {
            let name = profile.primaryInstrument?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name?.isEmpty == false) ? name : nil
        }
        return nil
    }

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

    // MARK: - Custom activities (load & sync)
    private func loadUserActivities() {
        do {
            userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext)
        } catch {
            userActivities = []
        }
    }

    private func syncActivityChoiceFromState() {
        if !activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityChoice = "custom:\(activityDetail)"
        } else {
            activityChoice = "core:\(activity.rawValue)"
        }
    }
}

private struct InfoSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let bullets: [String]
    let primaryCTA: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bullets.enumerated()), id: \.0) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(line) }
                }
            }
            HStack { Spacer(); Button("Got it") { dismiss() }.buttonStyle(.borderedProminent) }
        }
        .padding()
    }
}
