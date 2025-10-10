//////
//  PracticeTimerView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//  P0: Background-safe timer implementation (compute-on-resume; persisted state)
//  [ROLLBACK ANCHOR] v7.8 pre-hotfix — PracticeTimer first-use lag
//  [ROLLBACK ANCHOR] v7.8 Scope1 — primary-activity preselect applied (no migration)
//  [ROLLBACK ANCHOR] v7.8 Scope2 — pre-wheel-pickers (used .menu pickers)
//  [ROLLBACK ANCHOR] v7.8 Stage2 — pre (before Primary pinned-first)
//  [ROLLBACK ANCHOR] v7.8 DesignLite — pre (before visual polish)
//
//  Scope 2 + Stage 2: Wheel pickers + Primary pinned-first in Activity sheet.
//  v7.8 DesignLite: visual polish only (cards/background/spacing).
//
import SwiftUI
import Combine
import CoreData

// SessionActivityType moved to SessionActivityType.swift

struct PracticeTimerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    // Presented as a sheet from ContentView
    @Binding var isPresented: Bool

    // Instruments (profile)
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var userActivities: [UserActivity] = []

    // Instrument wheel state (index into instruments array)
    @State private var instrumentIndex: Int = 0

    // Activity state
    @State private var activity: SessionActivityType = .practice
    @State private var activityDetail: String = ""
    @State private var activityChoice: String = "core:0" // "core:<raw>" or "custom:<name>"

    // Primary Activity (Stage 1 persisted)
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

    // Wheel picker sheet toggles
    @State private var showInstrumentSheet: Bool = false
    @State private var showActivitySheet: Bool = false

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

    // Info-only recording helpers
    @State private var showAudioHelp = false
    @State private var showVideoHelp = false

    // Convenience flags
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    selectorsCard()
                    timerCard()

                    // ---------- Recording helpers (moved below timer) ----------
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            Button { showAudioHelp = true } label: {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(Text("Record audio help"))
                            .accessibilityHint(Text("Opens instructions for using your device’s app to capture audio."))

                            Button { showVideoHelp = true } label: {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(Text("Record video help"))
                            .accessibilityHint(Text("Opens instructions for using your device’s app to capture video."))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .cardSurface()
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline) // like Profile (centered, less shouty)
            .appBackground()
            // Single, unified prefetch path to avoid duplicate first-paint work
            .task {
                guard !didPrefetch else { return }
                didPrefetch = true

                instruments = fetchInstruments()
                if instrument == nil {
                    if let primaryName = fetchPrimaryInstrumentName(),
                       let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                        instrument = match
                        if let idx = instruments.firstIndex(of: match) { instrumentIndex = idx }
                    } else if hasOneInstrument {
                        instrument = instruments.first
                        instrumentIndex = 0
                    } else if hasMultipleInstruments {
                        instrumentIndex = 0 // safe default
                        instrument = instruments.first
                    }
                } else if let current = instrument,
                          let idx = instruments.firstIndex(of: current) {
                    instrumentIndex = idx
                }

                loadUserActivities()
                applyPrimaryActivityRef()
                syncActivityChoiceFromState()
            }
            .onAppear {
                hydrateTimerFromStorage()
                startTicker()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    hydrateTimerFromStorage()
                    startTicker()
                case .inactive, .background:
                    stopTicker()
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
            .sheet(isPresented: $showInstrumentSheet) {
                NavigationView {
                    VStack {
                        Picker("Instrument", selection: $instrumentIndex) {
                            ForEach(instruments.indices, id: \.self) { i in
                                Text(instruments[i].name ?? "Instrument").tag(i)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                    }
                    .navigationTitle("Instrument")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                applyInstrumentIndex()
                                showInstrumentSheet = false
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showInstrumentSheet = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showActivitySheet) {
                NavigationView {
                    VStack {
                        Picker("Activity", selection: $activityChoice) {
                            ForEach(activityChoicesPinned(), id: \.self) { choice in
                                Text(activityDisplayName(for: choice)).tag(choice)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                        .onChange(of: activityChoice) { _, choice in
                            applyChoice(choice)
                        }
                    }
                    .navigationTitle("Activity")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showActivitySheet = false }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showActivitySheet = false }
                        }
                    }
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
                        clearPersistedTimer()
                        resetUIOnly()
                        isPresented = false
                    }
                )
            }
            // Info sheets for recording help
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

    // MARK: - Cards (split to help the type-checker)

    @ViewBuilder
    private func selectorsCard() -> some View {
        if hasNoInstruments {
            VStack(alignment: .center, spacing: Theme.Spacing.s) {
                Text("No instruments found")
                    .font(.headline)
                Text("Add an instrument in your Profile to start timing sessions.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .cardSurface()
        } else {
            VStack(spacing: Theme.Spacing.m) {
                Text("Session").sectionHeader()
                VStack(spacing: Theme.Spacing.s) {
                    if hasMultipleInstruments {
                        Button {
                            if let current = instrument,
                               let idx = instruments.firstIndex(of: current) {
                                instrumentIndex = idx
                            }
                            showInstrumentSheet = true
                        } label: {
                            HStack {
                                Text("Instrument")
                                Spacer()
                                Text(currentInstrumentName())
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    } else if let only = instruments.first {
                        HStack {
                            Text("Instrument")
                            Spacer()
                            Text(only.name ?? "Instrument")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .onAppear { instrument = only }
                    }

                    Button { showActivitySheet = true } label: {
                        HStack {
                            Text("Activity")
                            Spacer()
                            Text(activityDisplayName(for: activityChoice))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardSurface()
        }
    }

    @ViewBuilder
    private func timerCard() -> some View {
        VStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text(formattedElapsed(elapsedSeconds))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: Theme.Spacing.m) {
                Button(isRunning ? "Pause" : "Start") {
                    isRunning ? pause() : start()
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
                .disabled(hasNoInstruments || instrument == nil)

                Button("Reset") { reset() }
                    .buttonStyle(.bordered)
                    .disabled((elapsedSeconds == 0) && !isRunning)

                if isRunning {
                    Button("Finish") { finish() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled((elapsedSeconds == 0) || instrument == nil)
                } else {
                    Button("Finish") { finish() }
                        .buttonStyle(.bordered)
                        .disabled((elapsedSeconds == 0) || instrument == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .cardSurface()
    }

    // MARK: - Helpers for wheel UI

    private func currentInstrumentName() -> String {
        if let inst = instrument { return inst.name ?? "Instrument" }
        if instruments.indices.contains(instrumentIndex) { return instruments[instrumentIndex].name ?? "Instrument" }
        return "Instrument"
    }

    private func applyInstrumentIndex() {
        guard instruments.indices.contains(instrumentIndex) else { return }
        instrument = instruments[instrumentIndex]
    }

    private func activityDisplayName(for choice: String) -> String {
        if choice.hasPrefix("core:") {
            if let raw = Int(choice.split(separator: ":").last ?? "0"),
               let t = SessionActivityType(rawValue: Int16(raw)) {
                return t.label
            }
            return SessionActivityType.practice.label
        } else if choice.hasPrefix("custom:") {
            return String(choice.dropFirst("custom:".count))
        }
        return SessionActivityType.practice.label
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
        persistTimerState()
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
        activity = .practice
        activityDetail = ""
        activityChoice = "core:0"
    }

    private func activityChoicesPinned() -> [String] {
        let core: [String] = SessionActivityType.allCases.map { "core:\($0.rawValue)" }
        let customs: [String] = userActivities.compactMap { ua in
            let n = (ua.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "custom:\(n)"
        }

        let primary = normalizedPrimary()
        var result: [String] = []

        if let p = primary { result.append(p) }
        for c in core where !result.contains(c) { result.append(c) }
        for cu in customs where !result.contains(cu) { result.append(cu) }
        return result
    }

    private func normalizedPrimary() -> String? {
        let raw = primaryActivityRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("core:") {
            if let v = Int(raw.split(separator: ":").last ?? "0"),
               SessionActivityType(rawValue: Int16(v)) != nil {
                return "core:\(v)"
            }
            return "core:0"
        } else if raw.hasPrefix("custom:") {
            let name = String(raw.dropFirst("custom:".count))
            if userActivities.contains(where: { ($0.displayName ?? "") == name }) {
                return "custom:\(name)"
            }
            return "core:0"
        } else {
            return "core:0"
        }
    }

    // MARK: - Data fetches

    private func loadUserActivities() {
        do {
            userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext)
        } catch {
            userActivities = []
        }
    }

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
        if !isRunning {
            if startDate == nil { startDate = Date() }
            isRunning = true
            persistTimerState()
        }
        startTicker()
        recomputeElapsedForUI()
    }

    private func pause() {
        guard isRunning else { return }
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
        let total = trueElapsedSeconds()
        finalizedDuration = total
        pause()
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
        case accumulated = "PracticeTimer.accumulated"
        case isRunning = "PracticeTimer.isRunning"
        case activityRaw = "PracticeTimer.activityRaw"
        case activityDetail = "PracticeTimer.activityDetail"
    }

    private func hydrateTimerFromStorage() {
        let d = UserDefaults.standard
        let started = d.double(forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        startDate = started > 0 ? Date(timeIntervalSince1970: started) : nil
        accumulatedSeconds = d.integer(forKey: TimerDefaultsKey.accumulated.rawValue)
        isRunning = d.bool(forKey: TimerDefaultsKey.isRunning.rawValue)
        let raw = Int16(d.integer(forKey: TimerDefaultsKey.activityRaw.rawValue))
        activity = SessionActivityType(rawValue: raw) ?? .practice
        activityDetail = d.string(forKey: TimerDefaultsKey.activityDetail.rawValue) ?? ""
        syncActivityChoiceFromState()
    }

    private func persistTimerState() {
        let d = UserDefaults.standard
        d.set(startDate?.timeIntervalSince1970 ?? 0, forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        d.set(accumulatedSeconds, forKey: TimerDefaultsKey.accumulated.rawValue)
        d.set(isRunning, forKey: TimerDefaultsKey.isRunning.rawValue)
        d.set(Int(activity.rawValue), forKey: TimerDefaultsKey.activityRaw.rawValue)
        d.set(activityDetail, forKey: TimerDefaultsKey.activityDetail.rawValue)
    }

    private func persistTimerSnapshot() {
        persistTimerState()
    }

    private func clearPersistedTimer() {
        let d = UserDefaults.standard
        d.removeObject(forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.accumulated.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.isRunning.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.activityRaw.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.activityDetail.rawValue)
    }

    private func resetUIOnly() {
        isRunning = false
        startDate = nil
        accumulatedSeconds = 0
        elapsedSeconds = 0
        activity = .practice
        activityDetail = ""
        activityChoice = "core:0"
    }

    private func syncActivityChoiceFromState() {
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityChoice = "core:\(activity.rawValue)"
        } else {
            activityChoice = "custom:\(activityDetail)"
        }
    }
}

// MARK: - Local InfoSheetView (minimal)
// If a global InfoSheetView exists later, rename this to avoid collisions.
fileprivate struct InfoSheetView: View {
    let title: String
    let bullets: [String]
    let primaryCTA: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(bullets, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text("•").font(.headline)
                        Text(item)
                    }
                }
            }
            if let cta = primaryCTA {
                Button("Continue") { cta() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .appBackground()
    }
}

//  [ROLLBACK ANCHOR] v7.8 DesignLite — post



