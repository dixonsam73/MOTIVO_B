//////
// //  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//  P0: Background-safe timer implementation (compute-on-resume; persisted state)
//  [ROLLBACK ANCHOR] v7.8 pre-hotfix — PracticeTimer first-use lag
//  [ROLLBACK ANCHOR] v7.8 Scope1 — primary-activity preselect applied (no migration)
//
import SwiftUI
import Combine
import CoreData

// SessionActivityType moved to SessionActivityType.swift

struct PracticeTimerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase

    // Presented as a sheet from ContentView
    @Binding var isPresented: Bool

    // Instruments (profile)
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var activity: SessionActivityType = .practice
    @State private var userActivities: [UserActivity] = []
    @State private var activityChoice: String = "core:0"
    @State private var activityDetail: String = ""

    // Primary Activity (Stage 1)
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

    // Prefetch guard to avoid duplicate first-paint work
    @State private var didPrefetch: Bool = false

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
                                    ForEach(SessionActivityType.allCases) { a in
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
                                    applyChoice(choice)
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
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .navigationTitle("Session Timer")
            // Single, unified prefetch path to avoid duplicate first-paint work
            .task {
                guard !didPrefetch else { return }
                didPrefetch = true

                // Perform lightweight data hydration after first frame via .task
                // Keep on the main actor because viewContext is main-queue bound.
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

                // Prefetch custom activities so the Activity menu is instant on first open
                loadUserActivities()

                // Apply Primary Activity if available
                applyPrimaryActivityRef()

                // Ensure the picker reflects current state
                syncActivityChoiceFromState()
            }
            .onAppear {
                // Hydrate persisted timer state and start UI ticker
                hydrateTimerFromStorage()
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
                    activityDetailPrefill: activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : activityDetail,
                    onSaved: {
                        // After saving, clear timer state and close timer sheet
                        clearPersistedTimer()
                        resetUIOnly()
                        isPresented = false
                    }
                )
            }
        }
    }

    // MARK: - Apply choices / primary

    private func applyChoice(_ choice: String) {
        if choice.hasPrefix("core:") {
            if let raw = Int(choice.split(separator: ":").last ?? "0") {
                activity = SessionActivityType(rawValue: Int16(raw)) ?? .practice
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

    private func applyPrimaryActivityRef() {
        let raw = primaryActivityRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("core:") {
            if let v = Int(raw.split(separator: ":").last ?? "0"),
               let t = SessionActivityType(rawValue: Int16(v)) {
                activity = t
                activityDetail = ""
                activityChoice = "core:\(v)"
                return
            }
        } else if raw.hasPrefix("custom:") {
            let name = String(raw.dropFirst("custom:".count))
            if userActivities.contains(where: { ($0.displayName ?? "") == name }) {
                activity = .practice
                activityDetail = name
                activityChoice = "custom:\(name)"
                return
            }
        }
        // Fallback to Practice
        activity = .practice
        activityDetail = ""
        activityChoice = "core:0"
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
            ud.set(now.timeIntervalSince1970, forKey: TimerDefaultsKey.startedAtEpoch.rawValue) // keep running from 'now'
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
