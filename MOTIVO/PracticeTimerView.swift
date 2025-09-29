//////
// //  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//  P0: Background-safe timer implementation (compute-on-resume; persisted state)
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
    @Environment(\.scenePhase) private var scenePhase

    // Presented as a sheet from ContentView
    @Binding var isPresented: Bool

    // Instruments (profile)
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var activity: ActivityType = .practice
    @State private var userActivities: [UserActivity] = []
    @State private var activityChoice: String = "core:0"
    @State private var activityDetail: String = ""

    // MARK: - Background-safe timer state (persisted)
    @State private var isRunning: Bool = false              // mirrored from persisted
    @State private var startDate: Date? = nil               // start timestamp (persisted)
    @State private var accumulatedSeconds: Int = 0          // persisted running total (excludes current run segment)
    @State private var elapsedSeconds: Int = 0              // UI-only, recomputed each tick from persisted state
    @State private var ticker: AnyCancellable?

    // Used when presenting the review sheet so we pass a stable, final duration
    @State private var finalizedDuration: Int = 0

    // Review sheet
    @State private var showReviewSheet = false

    // Info sheets for prebuilt-in recording guidance
    @State private var showAudioHelp = false
    @State private var showVideoHelp = false

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
                        .disabled((elapsedSeconds == 0) && !isRunning)

                    Button("Finish") { finish() }
                        .buttonStyle(.bordered)
                        .disabled((elapsedSeconds == 0) || instrument == nil)
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
            .onAppear {
                instruments = fetchInstruments()
                // Auto-select primary instrument if available (preserve existing behaviour)
                if instrument == nil {
                    if let primaryName = fetchPrimaryInstrumentName(),
                       let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                        instrument = match
                    } else if hasOneInstrument {
                        instrument = instruments.first
                    }
                }
                // Hydrate persisted timer state and start UI ticker
                hydrateTimerFromStorage()
                syncActivityChoiceFromState()
                startTicker() // drives UI only; true elapsed is recomputed each tick
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    // Recompute elapsed on resume to catch up time spent in background
                    hydrateTimerFromStorage()
                    // ensure ticker is running for UI updates
                    startTicker()
                case .inactive, .background:
                    // Cancel UI ticker to avoid wasted cycles (elapsed is recomputed on resume)
                    stopTicker()
                    // Persist a checkpoint so state is always current
                    persistTimerSnapshot()
                @unknown default:
                    break
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .sheet(isPresented: $showReviewSheet) {
                PostRecordDetailsView(
                    isPresented: $showReviewSheet,
                    timestamp: startDate ?? Date(),
                    durationSeconds: finalizedDuration,
                    instrument: instrument,
                    activityTypeRaw: activity.rawValue,
                    activityDetailPrefill: activityDetail.isEmpty ? nil : activityDetail,
                    onSaved: {
                        // After saving, clear timer state and close timer sheet
                        clearPersistedTimer()
                        resetUIOnly()
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

    // MARK: - Background-safe timer controls
    private func start() {
        guard instrument != nil else { return }
        // If not already running, set a start timestamp
        if !isRunning {
            if startDate == nil { startDate = Date() }
            isRunning = true
            // persist
            persistTimerState()
        }
        startTicker()
        recomputeElapsedForUI()
    }

    private func pause() {
        guard isRunning else { return }
        // Fold current segment into accumulated, then stop running
        let now = Date()
        if let started = startDate {
            let delta = max(0, Int(now.timeIntervalSince(started)))
            accumulatedSeconds += delta
        }
        startDate = nil
        isRunning = false
        persistTimerState()
        stopTicker()
        recomputeElapsedForUI()
    }

    private func reset() {
        pause()
        clearPersistedTimer()
        resetUIOnly()
    }

    private func finish() {
        // Capture final duration first
        let total = trueElapsedSeconds()
        finalizedDuration = total
        // Pause the timer and persist snapshot
        pause()
        // Present review
        showReviewSheet = true
    }

    // MARK: - UI ticker
    private func startTicker() {
        stopTicker()
        ticker = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                recomputeElapsedForUI()
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func recomputeElapsedForUI() {
        elapsedSeconds = trueElapsedSeconds()
    }

    // MARK: - Elapsed calculation (truth)
    private func trueElapsedSeconds() -> Int {
        let base = accumulatedSeconds
        if isRunning, let started = startDate {
            let now = Date()
            let delta = max(0, Int(now.timeIntervalSince(started)))
            return base + delta
        } else {
            return base
        }
    }

    private func formattedElapsed(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                      : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Persistence (UserDefaults)
    private enum TimerDefaultsKey: String {
        case startedAtEpoch = "PracticeTimer.startedAtEpoch"
        case accumulated = "PracticeTimer.accumulatedSeconds"
        case running = "PracticeTimer.isRunning"
    }

    private func hydrateTimerFromStorage() {
        let ud = UserDefaults.standard
        let isRun = ud.bool(forKey: TimerDefaultsKey.running.rawValue)
        let acc = ud.integer(forKey: TimerDefaultsKey.accumulated.rawValue)

        var start: Date? = nil
        let epoch = ud.double(forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        if epoch > 0 {
            start = Date(timeIntervalSince1970: epoch)
        }

        // Assign to state
        self.isRunning = isRun
        self.accumulatedSeconds = max(0, acc)
        self.startDate = start

        // Recompute UI
        recomputeElapsedForUI()
    }

    private func persistTimerState() {
        let ud = UserDefaults.standard
        ud.set(isRunning, forKey: TimerDefaultsKey.running.rawValue)
        ud.set(accumulatedSeconds, forKey: TimerDefaultsKey.accumulated.rawValue)
        if let start = startDate {
            ud.set(start.timeIntervalSince1970, forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        } else {
            ud.removeObject(forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        }
    }

    private func persistTimerSnapshot() {
        // Ensure current delta is represented in persisted values (without changing run state)
        if isRunning, let started = startDate {
            let now = Date()
            let delta = max(0, Int(now.timeIntervalSince(started)))
            let newAccum = accumulatedSeconds + delta
            let ud = UserDefaults.standard
            ud.set(isRunning, forKey: TimerDefaultsKey.running.rawValue)
            ud.set(newAccum, forKey: TimerDefaultsKey.accumulated.rawValue)
            ud.set(now.timeIntervalSince1970, forKey: TimerDefaultsKey.startedAtEpoch.rawValue) // keep running from 'now' to avoid double counting on long sleeps
        } else {
            persistTimerState()
        }
    }

    private func clearPersistedTimer() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: TimerDefaultsKey.running.rawValue)
        ud.removeObject(forKey: TimerDefaultsKey.accumulated.rawValue)
        ud.removeObject(forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        // Also clear mirrors
        isRunning = false
        accumulatedSeconds = 0
        startDate = nil
        recomputeElapsedForUI()
    }

    private func resetUIOnly() {
        elapsedSeconds = 0
        finalizedDuration = 0
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
