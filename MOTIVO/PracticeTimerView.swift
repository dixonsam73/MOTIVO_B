// CHANGE-ID: 20251124_213000-ptv-viewerRoutingAndHitTests
// SCOPE: Ensure audio rows win hit-testing over video tiles in attachments card
// CHANGE-ID: 20251012_202320-tasks-pad-a2
// SCOPE: Fix tasks pad placement; proper state; pass notesPrefill

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
import AVFoundation
import AVKit
import Darwin

private let recorderIcon = Color(red: 0.44, green: 0.50, blue: 0.57) // slate blue-grey ~ #6F7F91
private let tasksAccent  = Color(red: 0.66, green: 0.58, blue: 0.46) // warm neutral  ~ #A88B73

// SessionActivityType moved to SessionActivityType.swift

struct PracticeTimerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    // Presented as a sheet from ContentView
    @Binding var isPresented: Bool

    // Instruments (profile)
    @State var instruments: [Instrument] = []
    @State var instrument: Instrument?
    @State private var userActivities: [UserActivity] = []

    // Instrument wheel state (index into instruments array)
    @State var instrumentIndex: Int = 0

    // Activity state
    @State var activity: SessionActivityType = .practice
    @State var activityDetail: String = ""
    @State var activityChoice: String = "core:0" // "core:<raw>" or "custom:<name>"

    // Primary Activity (Stage 1 persisted)
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"
    @AppStorage("appSettings_showMetronomeStrip") private var showMetronomeStrip: Bool = true
    @AppStorage("appSettings_showDroneStrip") private var showDroneStrip: Bool = true

    // Wheel picker sheet toggles
    @State var showInstrumentSheet: Bool = false
    @State var showActivitySheet: Bool = false

    // Prefetch guard to avoid duplicate first-paint work
    @State private var didPrefetch: Bool = false

    // MARK: - Background-safe timer state (persisted)
    @State private var isRunning: Bool = false              // mirrored from persisted
    @State var startDate: Date? = nil               // start timestamp (persisted)
    @State private var accumulatedSeconds: Int = 0          // persisted running total (excludes current run segment)
    @State private var elapsedSeconds: Int = 0              // UI-only, recomputed each tick from persisted state
    @State private var ticker: AnyCancellable?

    // Used when presenting the review sheet so we pass a stable, final duration
    @State var finalizedDuration: Int = 0
    @State var finalizedStartDate: Date? = nil
    
    // Review sheet
    @State var showReviewSheet = false
    @State var didSaveFromReview: Bool = false
    @State var didCancelFromReview: Bool = false
    // === DRONE STATE (insert below existing @State vars) ===
    @State var droneIsOn: Bool = false
    @State var droneVolume: Double = 0.5
    @State var droneNoteIndex: Int = 24
    @State var droneFreq: Int = 440
    @State var showDroneVolumePopover: Bool = false

    // The chromatic list for the note wheel (A2 → A6 keeps wheels compact)
    private let droneNotes: [String] = [
        "A2","A#2","B2","C3","C#3","D3","D#3","E3","F3","F#3","G3","G#3",
        "A3","A#3","B3","C4","C#4","D4","D#4","E4","F4","F#4","G4","G#4",
        "A4","A#4","B4","C5","C#5","D5","D#5","E5","F5","F#5","G5","G#5",
        "A5","A#5","B5","C6","C#6","D6","D#6","E6","F6","F#6","G6","G#6",
        "A6"
    ]

    // Clean, minimal engine for soft sine-ish drone
    let audioServices = AudioServices.shared
    // Info-only recording helpers
    @State private var showAudioHelp = false
    @State private var showVideoHelp = false
    // MARK: - Metronome State

    @State var metronomeIsOn: Bool = false
    @State private var metronomeBPM: Int = 80
    @State private var metronomeAccentEvery: Int = 0   // 0 = no accent, 2–15 = every N beats
    @State private var metronomeVolume: Double = 0.7



    // Engine instance (local to PTV)
   
    // New audio recording and attachments state
    @State var showAudioRecorder: Bool = false
    @State var stagedAudio: [StagedAttachment] = []
    @State var audioPlayer: AVAudioPlayer? = nil
    @State var currentlyPlayingID: UUID? = nil
    @State var audioPlayerDelegate: AudioPlayerDelegateBridge? = nil
    @State var isAudioPlaying: Bool = false

    @State var audioTitles: [UUID: String] = [:]
    @State var audioAutoTitles: [UUID: String] = [:]
    @State var audioDurations: [UUID: Int] = [:]
    @FocusState private var focusedAudioTitleID: UUID?
    @State var audioTitleEditingBuffer: [UUID: String] = [:]
    @State var audioTitleDebounceWork: [UUID: DispatchWorkItem] = [:]
    @State var audioTitleDidImmediatePersist: Set<UUID> = []

    @State var audioObserversInstalled: Bool = false
    @State var wasPlayingBeforeInterruption_timer: Bool = false

    // Image capture state (mirrors AddEdit/PostRecord behavior)
    @State var stagedImages: [StagedAttachment] = []
    @State var selectedThumbnailID: UUID? = nil
    @State private var showCamera: Bool = false
    @State private var showCameraDeniedAlert: Bool = false

    // --- Inserted video recording and attachments state ---
    @State var showVideoRecorder: Bool = false
    @State var stagedVideos: [StagedAttachment] = []
    @State var videoThumbnails: [UUID: UIImage] = [:]
    // Remove old video player state:
    // @State private var showVideoPlayer: Bool = false
    // @State private var videoPlayerItem: AVPlayer? = nil

    // Attachment viewer routing state
    struct PTVViewerURL: Identifiable, Equatable {
        let id = UUID()
        let url: URL
    }
    @State private var attachmentViewer: PTVViewerURL? = nil

    // Add trimming state for audio/video clips
    @State var trimItem: StagedAttachment? = nil
    
    // Convenience flags
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    // Ephemeral media flag key added as per instructions
    let ephemeralMediaFlagKey = "ephemeralSessionHasMedia_v1"
    let currentSessionIDKey = "PracticeTimer.currentSessionID"

    // --- Tasks/Notes Pad State (v7.9A) ---
    @State private var showTasksPad: Bool = false
    struct TaskLine: Identifiable {
        let id: UUID = UUID()
        var text: String
        var isDone: Bool = false
    }
    @State private var taskLines: [TaskLine] = []
    @State private var autoTaskTexts: [UUID: String] = [:]

    // NEW: track explicit clears so we don't auto-refill
    @State private var userClearedTasksForCurrentContext: Bool = false
    // NEW: remember which activity's defaults we last loaded (for activity-change behaviour)
    @State private var lastDefaultsActivityRef: String? = nil

    @FocusState private var focusedTaskID: UUID?
    private let tasksDefaultsKey: String = "practiceTasks_v1"
    private let sessionDiscardedKey = "PracticeTimer.sessionDiscarded"
    // sessionActiveKey: true while a timer session is in-progress (even if paused). Used to distinguish fresh launch vs resume. We clear staging only when false.
    let sessionActiveKey = "PracticeTimer.sessionActive"

    // Unique per-process boot identifier to detect cold launches (force quit / crash relaunch)
    let sessionBootIDKey = "PracticeTimer.bootID"
    private var currentBootID: String { String(getpid()) }

    // BEGIN TASKS DEFAULTS PATCH

    /// Legacy v7.9-style global defaults loader (Practice only).
    /// Kept as a fallback for very old keys.
    private func loadDefaultTasksIfNeeded() {
        // Only ever applies to Practice
        guard activity == .practice else { return }

        // Only load when empty AND user hasn't explicitly cleared this context
        guard taskLines.isEmpty, !userClearedTasksForCurrentContext else { return }

        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: tasksDefaultsKey) else { return }

        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            print("[PracticeTimer] Loaded default tasks from legacy defaults key")
            let mapped = decoded.map { TaskLine(text: $0, isDone: false) }
            self.taskLines = mapped
            autoTaskTexts.removeAll()
            for line in mapped {
                autoTaskTexts[line.id] = line.text
            }

            // Treat this as the Practice template context
            lastDefaultsActivityRef = "core:0"
            userClearedTasksForCurrentContext = false
        }
    }

    /// Derive an activity reference string matching the Profile/TasksManager scheme.
    /// Prefers the explicit activityChoice (e.g. "core:0", "custom:Rehearsal"), falls back to primaryActivityRef,
    /// and finally to "core:0" (Practice) if malformed.
    private func currentActivityRefForTasks() -> String {
        let trimmedChoice = activityChoice.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedChoice.hasPrefix("core:") || trimmedChoice.hasPrefix("custom:") {
            return trimmedChoice
        }

        let trimmedPrimary = primaryActivityRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrimary.hasPrefix("core:") || trimmedPrimary.hasPrefix("custom:") {
            return trimmedPrimary
        }

        return "core:0"
    }

    /// Per-activity default tasks loader (core + custom).
    /// Uses keys:
    ///   tasks:  "practiceTasks_v1::<ownerScope>::<activityRef>"
    ///   toggle: "practiceTasks_autofill_enabled::<ownerScope>::<activityRef>"
    ///
    /// Also migrates old practice-only lists from "practiceTasks_v1::<ownerScope>" on first use.
    private func loadPracticeDefaultsIfNeeded() {
        let ownerScope: String = PersistenceController.shared.currentUserID ?? "device"
        let activityRef = currentActivityRefForTasks()
        let defaults = UserDefaults.standard

        // Decide whether we should block due to an explicit clear.
        // If the user cleared for this same activity, don't auto-refill.
        let clearedForSameActivity: Bool
        if let lastRef = lastDefaultsActivityRef {
            clearedForSameActivity = userClearedTasksForCurrentContext && (lastRef == activityRef)
        } else {
            clearedForSameActivity = userClearedTasksForCurrentContext
        }

        // Only proceed if we currently have no lines AND we're not blocked by a clear
        guard taskLines.isEmpty, !clearedForSameActivity else { return }

        let tasksKey = "practiceTasks_v1::\(ownerScope)::\(activityRef)"
        let toggleKey = "practiceTasks_autofill_enabled::\(ownerScope)::\(activityRef)"

        // Default ON when no explicit preference exists.
        let toggleValue: Bool
        if defaults.object(forKey: toggleKey) == nil {
            toggleValue = true
        } else {
            toggleValue = defaults.bool(forKey: toggleKey)
        }
        guard toggleValue else { return }

        // Helper to apply a loaded template and update tracking flags
        func applyTemplate(_ strings: [String]) {
            let mapped = strings.map { TaskLine(text: $0, isDone: false) }
            self.taskLines = mapped
            autoTaskTexts.removeAll()
            for line in mapped {
                autoTaskTexts[line.id] = line.text
            }
            lastDefaultsActivityRef = activityRef
            userClearedTasksForCurrentContext = false
        }

        // 1) Preferred path: per-activity template already exists.
        if let arr = defaults.array(forKey: tasksKey) as? [String] {
            applyTemplate(arr)
            return
        }

        // 2) Backwards-compat: if we're on Practice, migrate from legacy practice-only key.
        if activity == .practice {
            let legacyKey = "practiceTasks_v1::\(ownerScope)"
            if let legacyArr = defaults.array(forKey: legacyKey) as? [String] {
                applyTemplate(legacyArr)
                // Persist into the per-activity slot for next time.
                defaults.set(legacyArr, forKey: tasksKey)
            } else {
                // Very old global data path (no ownerScope).
                if let arr = defaults.array(forKey: "practiceTasks_v1") as? [String] {
                    applyTemplate(arr)
                    defaults.set(arr, forKey: tasksKey)
                }
            }
        }
    }

    // END TASKS DEFAULTS PATCH
    private func composeNotesString() -> String? {
        // Keep only non-empty lines (trimmed)
        let nonEmpty = taskLines
            .map { (done: $0.isDone, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }

        guard !nonEmpty.isEmpty else { return nil }

        return nonEmpty
            .map { ($0.done ? "✓" : "•") + " " + $0.text }
            .joined(separator: "\n")
    }
    // Returns a bulleted string of ONLY completed task lines, or nil if none.
    // Uses the same boolean flag that drives the checkbox in the task pad.
    func composeCompletedTasksNotesString() -> String? {
        let trimmedCompleted = taskLines
            .filter { $0.isDone }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedCompleted.isEmpty else { return nil }
        return trimmedCompleted.map { "• \($0)" }.joined(separator: "\n")
    }
    func resetTasksForNewSessionContext() {
        // Fresh context: allow presets to load again when pad opens
        taskLines.removeAll()
        autoTaskTexts.removeAll()
        userClearedTasksForCurrentContext = false
        lastDefaultsActivityRef = nil
        persistTasksSnapshot()
    }

    private func handleTaskReturn(for id: UUID) {
        guard let idx = taskLines.firstIndex(where: { $0.id == id }) else { return }

        // Mirror the old onSubmit behaviour: restore auto text if left empty
        let trimmed = taskLines[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let auto = autoTaskTexts[id] {
            taskLines[idx].text = auto
        } else {
            taskLines[idx].text = trimmed
        }

        // Create a new empty line directly after the current one
        let newLine = TaskLine(text: "")
        let insertIndex = taskLines.index(after: idx)
        taskLines.insert(newLine, at: insertIndex)

        // Persist once after the updates
        persistTasksSnapshot()

        // Move focus to the new line so the user can continue typing
        focusedTaskID = newLine.id
    }

    private func addEmptyTaskLine() {
        taskLines.append(TaskLine(text: ""))
        persistTasksSnapshot()
    }
    private func toggleDone(_ id: UUID) {
        if let idx = taskLines.firstIndex(where: { $0.id == id }) {
            taskLines[idx].isDone.toggle()
            persistTasksSnapshot()
        }
    }
    private func deleteLine(_ id: UUID) {
        taskLines.removeAll { $0.id == id }
        autoTaskTexts.removeValue(forKey: id)

        if taskLines.isEmpty {
            // User has effectively cleared the pad for this activity/context
            userClearedTasksForCurrentContext = true
            showTasksPad = false
        }

        persistTasksSnapshot()
    }

    private func clearAllTasks() {
        // Explicit "wipe this pad for now" – do not auto-refill until context changes
        userClearedTasksForCurrentContext = true
        taskLines.removeAll()
        autoTaskTexts.removeAll()
        persistTasksSnapshot()
    }
        var body: some View {
        NavigationStack {
            mainScrollView
        }
    }

    // MARK: - Cards (split to help the type-checker)

    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView {
            mainContent
        }
        .navigationTitle("Timer")
        .navigationBarTitleDisplayMode(.inline) // like Profile (centered, less shouty)
        .appBackground()
        // Single, unified prefetch path to avoid duplicate first-paint work
        .task {
            guard !didPrefetch else { return }
            didPrefetch = true

            // Detect cold launch by boot ID
            let lastBootID = UserDefaults.standard.string(forKey: sessionBootIDKey)
            if lastBootID != currentBootID {
                // Fresh process launch (cold start), force clean state
                stopAttachmentPlayback()
                clearPersistedStagedAttachments()
                clearAllStagingStoreRefs()
                clearPersistedTasks()
                purgeStagedTempFiles()
                stagedAudio.removeAll()
                audioTitles.removeAll()
                audioAutoTitles.removeAll()
                audioDurations.removeAll()
                stagedImages.removeAll()
                stagedVideos.removeAll()
                videoThumbnails.removeAll()
                selectedThumbnailID = nil
                clearPersistedTimer()
                resetUIOnly()
                UserDefaults.standard.set(false, forKey: sessionActiveKey)
                UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
                UserDefaults.standard.set(currentBootID, forKey: sessionBootIDKey)
            }

            // New sessionActiveKey logic: clear staging etc if no active session, to ensure clean state on fresh launch.
            let isActive = UserDefaults.standard.bool(forKey: sessionActiveKey)
            if !isActive {
                stopAttachmentPlayback()
                clearPersistedStagedAttachments()
                clearAllStagingStoreRefs()
                clearPersistedTasks()
                purgeStagedTempFiles()
                stagedAudio.removeAll()
                audioTitles.removeAll()
                audioAutoTitles.removeAll()
                audioDurations.removeAll()
                stagedImages.removeAll()
                stagedVideos.removeAll()
                videoThumbnails.removeAll()
                selectedThumbnailID = nil
                clearPersistedTimer()
                resetUIOnly()
                UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
                UserDefaults.standard.set(true, forKey: sessionActiveKey)
                // NEW: reset Notes / Tasks pad for this fresh session
                resetTasksForNewSessionContext()
            }

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
            do { try StagingStore.bootstrap() } catch { /* ignore */ }
        }
        .onAppear {
            // Always bootstrap the staging store before any hydration that depends on it
            do { try StagingStore.bootstrap() } catch { /* ignore */ }

            // Install willResignActive observer to commit title buffers immediately on app transition
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                commitAllAudioTitleBuffersAndPersist()
            }
            NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                handleAppTerminationCleanup()
            }

            // If last session was explicitly discarded, ensure staging store is empty before hydrating
            if UserDefaults.standard.bool(forKey: sessionDiscardedKey) {
                clearAllStagingStoreRefs()
                UserDefaults.standard.set(false, forKey: sessionDiscardedKey)
                UserDefaults.standard.set(false, forKey: sessionActiveKey)
                UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
            }

            // Safety net: if an editing buffer leaked from a previous instance, commit it now before hydrating
            if let fid = focusedAudioTitleID, let buffer = audioTitleEditingBuffer[fid] {
                persistAudioTitleImmediately(for: fid, bufferValue: buffer)
                audioTitleEditingBuffer.removeValue(forKey: fid)
            }

            // Ensure any pending title edits are committed before hydration
            commitAudioTitleEditingBuffers()
            // Hydrate timer and staged attachments from storage (UserDefaults + StagingStore)
            hydrateTimerFromStorage()

            // Determine persisted state after hydration
            let d = UserDefaults.standard
            let hasPersistedTimer = d.double(forKey: TimerDefaultsKey.startedAtEpoch.rawValue) > 0 || d.integer(forKey: TimerDefaultsKey.accumulated.rawValue) > 0 || d.bool(forKey: TimerDefaultsKey.isRunning.rawValue)
            let audioIDStrings = d.array(forKey: TimerDefaultsKey.stagedAudioIDs.rawValue) as? [String] ?? []
            let videoIDStrings = d.array(forKey: TimerDefaultsKey.stagedVideoIDs.rawValue) as? [String] ?? []
            let imageIDStrings = d.array(forKey: TimerDefaultsKey.stagedImageIDs.rawValue) as? [String] ?? []
            let audioIDs = audioIDStrings.compactMap(UUID.init)
            let videoIDs = videoIDStrings.compactMap(UUID.init)
            let imageIDs = imageIDStrings.compactMap(UUID.init)
            #if DEBUG
            print("[PracticeTimer] hydrate IDs defaults audio=\(audioIDs) video=\(videoIDs) image=\(imageIDs) store=\(StagingStore.list().map{ $0.id })")
            #endif
            let hasPersistedStagedIDs = (!audioIDStrings.isEmpty || !videoIDStrings.isEmpty || !imageIDStrings.isEmpty)

            // Also check the staging store to avoid clearing attachments that exist on disk

            startTicker()

            // Deterministic reconciliation with StagingStore to avoid visual disappearance
            do { try StagingStore.bootstrap() } catch { /* ignore */ }
            let storeRefs = StagingStore.list()
            let storeHas = !storeRefs.isEmpty
            let localEmpty = (stagedAudio.isEmpty && stagedImages.isEmpty && stagedVideos.isEmpty)
            // Build ID sets per kind for comparison
            let localAudioIDs = Set(stagedAudio.map { $0.id })
            let localVideoIDs = Set(stagedVideos.map { $0.id })
            let localImageIDs = Set(stagedImages.map { $0.id })
            let storeAudioIDs = Set(storeRefs.filter { $0.kind == .audio }.map { $0.id })
            let storeVideoIDs = Set(storeRefs.filter { $0.kind == .video }.map { $0.id })
            let storeImageIDs = Set(storeRefs.filter { $0.kind == .image }.map { $0.id })
            let idsDiffer = (localAudioIDs != storeAudioIDs) || (localVideoIDs != storeVideoIDs) || (localImageIDs != storeImageIDs)
            if (localEmpty && storeHas) || idsDiffer {
                mirrorFromStagingStore()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Ensure any leaked/debounced title edits are committed before hydration
                commitAllAudioTitleBuffersAndPersist()

                hydrateTimerFromStorage()
                startTicker()
                // Reconcile with StagingStore on resume to repopulate UI if needed
                do { try StagingStore.bootstrap() } catch { /* ignore */ }
                let storeRefs = StagingStore.list()
                let storeHas = !storeRefs.isEmpty
                let localEmpty = (stagedAudio.isEmpty && stagedImages.isEmpty && stagedVideos.isEmpty)
                let localAudioIDs = Set(stagedAudio.map { $0.id })
                let localVideoIDs = Set(stagedVideos.map { $0.id })
                let localImageIDs = Set(stagedImages.map { $0.id })
                let storeAudioIDs = Set(storeRefs.filter { $0.kind == .audio }.map { $0.id })
                let storeVideoIDs = Set(storeRefs.filter { $0.kind == .video }.map { $0.id })
                let storeImageIDs = Set(storeRefs.filter { $0.kind == .image }.map { $0.id })
                let idsDiffer = (localAudioIDs != storeAudioIDs) || (localVideoIDs != storeVideoIDs) || (localImageIDs != storeImageIDs)
                if (localEmpty && storeHas) || idsDiffer {
                    mirrorFromStagingStore()
                }
            case .inactive, .background:
                // Commit all buffered title edits before persisting snapshot
                commitAllAudioTitleBuffersAndPersist()

                do { try StagingStore.bootstrap() } catch { /* ignore */ }
                stopTicker()
                persistTimerSnapshotSafely(context: "scenePhase.background")
                UserDefaults.standard.synchronize()
                removeAudioObserversIfNeeded()
                purgeStagedTempFiles()
            @unknown default:
                break
            }
        }
        .onDisappear {
            // Remove willResignActive observer to avoid leaks
            NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)

            // Commit any in-progress audio title edit when leaving the view (covers in-app navigation without backgrounding)
            if let fid = focusedAudioTitleID, let buffer = audioTitleEditingBuffer[fid] {
                // Cancel pending debounce and persist immediately
                if let w = audioTitleDebounceWork[fid] { w.cancel() }
                audioTitleDebounceWork[fid] = nil
                persistAudioTitleImmediately(for: fid, bufferValue: buffer)
                audioTitleEditingBuffer.removeValue(forKey: fid)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Quit") {
                    #if DEBUG
                    StorageInspector.logSandboxUsage(tag: "Before Quit")
                    #endif
                    // Intentional discard: purge staged items associated with this live session
                    let __discardIDs: [UUID] = stagedAudio.map { $0.id } + stagedImages.map { $0.id } + stagedVideos.map { $0.id }
                    if !__discardIDs.isEmpty {
                        StagingStore.removeMany(ids: __discardIDs)
                        // Delete underlying files for these refs now
                        let refsToDelete = StagingStore.list()
                        StagingStore.deleteFiles(for: refsToDelete)
                        #if DEBUG
                        print("[PracticeTimer] quit — removed \(__discardIDs.count) staged items")
                        #endif
                    }
                    
                    // Purge temp surrogates while staged arrays still have IDs
                    purgeStagedTempFiles()
                    removeAllSessionTempSurrogates()

                    // Clear persisted and in-memory staged attachments and reset timer
                    stopAttachmentPlayback()
                    clearPersistedStagedAttachments()
                    clearAllStagingStoreRefs()
                    UserDefaults.standard.set(true, forKey: sessionDiscardedKey)
                    UserDefaults.standard.set(false, forKey: sessionActiveKey)
                    UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
                    clearPersistedTasks()
                    clearPersistedTimer()
                    resetUIOnly()
                    stagedAudio.removeAll()
                    audioTitles.removeAll()
                    audioAutoTitles.removeAll()
                    audioDurations.removeAll()
                    stagedImages.removeAll()
                    stagedVideos.removeAll()
                    videoThumbnails.removeAll()
                    selectedThumbnailID = nil
                    UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
                    #if DEBUG
                    StorageInspector.logSandboxUsage(tag: "After Quit")
                    #endif

                    // Additional full cleanup of staged and temporary media (post-UI state updates)
                    #if DEBUG
                    print("[EphemeralCleanup] Quit cleanup triggered")
                    #endif
                    // 1) Remove any remaining staging refs and files (best-effort, non-destructive to saved sessions)
                    do { try StagingStore.bootstrap() } catch { /* ignore */ }
                    let allRefs = StagingStore.list()
                    var removedRefCount = 0
                    if !allRefs.isEmpty {
                        // Remove refs from store metadata
                        for ref in allRefs {
                            StagingStore.remove(ref)
                            removedRefCount += 1
                        }
                        // Delete any associated files on disk
                        StagingStore.deleteFiles(for: allRefs)
                    }
                    #if DEBUG
                    print("[EphemeralCleanup] StagingStore refs removed: \(removedRefCount)")
                    #endif
                    // 2) Remove any temporary surrogate recorder files (audio/video/image) and posters
                    let fm = FileManager.default
                    var removedAudioTemps = 0
                    var removedImageTemps = 0
                    var removedVideoTemps = 0
                    var removedPosterTemps = 0
                    // Remove any temp audio surrogates
                    for att in stagedAudio {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent(att.id.uuidString)
                            .appendingPathExtension("m4a")
                        if (try? fm.removeItem(at: url)) != nil {
                            removedAudioTemps += 1
                        }
                    }
                    // Remove any temp image surrogates
                    for att in stagedImages {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent(att.id.uuidString)
                            .appendingPathExtension("jpg")
                        if (try? fm.removeItem(at: url)) != nil {
                            removedImageTemps += 1
                        }
                    }
                    // Remove any temp video surrogates
                    for att in stagedVideos {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent(att.id.uuidString)
                            .appendingPathExtension("mov")
                        if (try? fm.removeItem(at: url)) != nil {
                            removedVideoTemps += 1
                        }
                        // Also remove any poster files generated alongside
                        let poster = FileManager.default.temporaryDirectory
                            .appendingPathComponent("\(att.id.uuidString)_poster")
                            .appendingPathExtension("jpg")
                        if (try? fm.removeItem(at: poster)) != nil {
                            removedPosterTemps += 1
                        }
                    }
                    #if DEBUG
                    print("[EphemeralCleanup] Temp audio: \(removedAudioTemps) image: \(removedImageTemps) video: \(removedVideoTemps) posters: \(removedPosterTemps)")
                    #endif
                    // 3) Reset ephemeral media flag
                    UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
                    #if DEBUG
                    print("[EphemeralCleanup] Quit cleanup flag reset to false")
                    #endif
                    isPresented = false
                }
            }
        }
        .sheet(isPresented: $showInstrumentSheet) {
            instrumentPickerSheet
        }
        .sheet(isPresented: $showActivitySheet) {
            activityPickerSheet
        }
        .sheet(isPresented: $showReviewSheet) {
            reviewSheet
        }
        .onChange(of: showReviewSheet) { oldValue, newValue in
            // If the review sheet was closed and no save occurred, reset timer for next opening
            if oldValue == true && newValue == false && didSaveFromReview == false {
                if didCancelFromReview == true {
                    // Explicit chevron cancel: do nothing (preserve state)
                } else {
                    // Intentional discard: purge staged items associated with this live session
                    let __discardIDs: [UUID] = stagedAudio.map { $0.id } + stagedImages.map { $0.id } + stagedVideos.map { $0.id }
                    if !__discardIDs.isEmpty {
                        StagingStore.removeMany(ids: __discardIDs)
                    }
                    
                    let refsToDelete = StagingStore.list()
                    clearPersistedTimer()
                    clearPersistedStagedAttachments()
                    clearAllStagingStoreRefs()
                    UserDefaults.standard.set(true, forKey: sessionDiscardedKey)
                    UserDefaults.standard.set(false, forKey: sessionActiveKey)
                    clearPersistedTasks()
                    resetUIOnly()
                    stagedAudio.removeAll()
                    audioTitles.removeAll()
                    stagedImages.removeAll()
                    stagedVideos.removeAll()
                    videoThumbnails.removeAll()
                    selectedThumbnailID = nil
                    StagingStore.deleteFiles(for: refsToDelete)
                    purgeStagedTempFiles()
                    UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
                    UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
                }
                didCancelFromReview = false
            }
        }
        .onChange(of: activityChoice) { _, _ in
            // Clear current pad contents and auto-text mappings
            taskLines.removeAll()
            autoTaskTexts.removeAll()

            // Load the correct per-activity template (Practice, Rehearsal, Recording, etc.)
            loadPracticeDefaultsIfNeeded()

            // Persist snapshot so the pad survives suspends/resumes
            persistTasksSnapshot()
        }
        // Info sheets for recording help
        .sheet(isPresented: $showAudioHelp) {
            audioHelpSheet
        }
        .sheet(isPresented: $showVideoHelp) {
            videoHelpSheet
        }
        // Audio recorder sheet
        .sheet(isPresented: $showAudioRecorder) {
            audioRecorderSheet
        }
        // Attach .onChange OUTSIDE the sheet closure
        .onChange(of: showAudioRecorder) { oldValue, newValue in
            if newValue == true {
                audioServices.droneEngine.stop()
                droneIsOn = false
            }
        }
        // Video recorder fullScreenCover replacement
        .fullScreenCover(isPresented: $showVideoRecorder) {
            videoRecorderFullScreen
        }
        .onChange(of: showVideoRecorder) { _, newValue in
            if newValue {
                killDroneAndMetronome()
            }
        }
        .sheet(isPresented: $showCamera) {
            cameraSheet
        }
        .onChange(of: showCamera) { oldValue, newValue in
            if newValue == true {
                audioServices.droneEngine.stop()
                droneIsOn = false
            }
        }
        .fullScreenCover(item: $attachmentViewer) { payload in
            attachmentViewerView(for: payload)
        }
        .alert("Camera access denied",
               isPresented: $showCameraDeniedAlert,
               actions: {
                   Button("OK", role: .cancel) {}
                   Button("Open Settings") {
                       if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                   }
               },
               message: { Text("Enable camera access in Settings → Privacy → Camera to take photos.") })
        // QA:
        // - Long-press context menu "Trim" and inline trim buttons with scissors icon present on audio rows and video tiles
        // - Trim buttons have ultraThinMaterial background and padding for visibility
        // - Trim sheet opens with correct media type and URL
        // - Trim save actions correctly add or replace staged attachments with updated metadata
        // - No regressions in other UI or logic due to trim additions
        .sheet(item: $trimItem, onDismiss: { trimItem = nil }) { item in
            trimSheet(for: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Reconcile metronome running state with UI flag to avoid ghost instances
            if metronomeIsOn && (metronomeEngineIsActuallyRunning() == false) {
                metronomeIsOn = false
            }
            if !metronomeIsOn && (metronomeEngineIsActuallyRunning() == true) {
                audioServices.metronomeEngine.stop()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            sessionMetaSection
            droneSection
            metronomeSection
            timerSection
            mediaRecorderSection
            tasksPadSection
            attachmentsSection
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xl)
    }

    @ViewBuilder
    private var sessionMetaSection: some View {
        SessionMetaCard(
            instruments: instruments,
            instrument: $instrument,
            showInstrumentSheet: $showInstrumentSheet,
            showActivitySheet: $showActivitySheet,
            currentInstrumentName: currentInstrumentName(),
            activityLabel: activityDisplayName(for: activityChoice)
        )
    }

    @ViewBuilder
    private var droneSection: some View {
        if showDroneStrip {
            VStack(spacing: Theme.Spacing.s) {
                DroneControlStripCard(
                    droneIsOn: $droneIsOn,
                    droneVolume: $droneVolume,
                    droneNoteIndex: $droneNoteIndex,
                    droneFreq: $droneFreq,
                    showDroneVolumePopover: $showDroneVolumePopover,
                    droneNotes: droneNotes,
                    droneEngine: audioServices.droneEngine,
                    recorderIcon: recorderIcon
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .cardSurface()
        }
    }

    @ViewBuilder
    private var metronomeSection: some View {
        if showMetronomeStrip {
            VStack(spacing: Theme.Spacing.s) {
                MetronomeControlStripCard(
                    metronomeIsOn: $metronomeIsOn,
                    metronomeBPM: $metronomeBPM,
                    metronomeAccentEvery: $metronomeAccentEvery,
                    metronomeVolume: $metronomeVolume,
                    metronomeEngine: audioServices.metronomeEngine,
                    recorderIcon: recorderIcon
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .cardSurface()
        }
    }

    @ViewBuilder
    private var timerSection: some View {
        TimerCard(
            elapsedLabel: formattedElapsed(elapsedSeconds),
            isRunning: isRunning,
            onStart: { start() },
            onPause: { pause() },
            onReset: { reset() },
            onFinish: { finish() }
        )
    }

    @ViewBuilder
    private var mediaRecorderSection: some View {
        MediaRecorderRowCard(
            showAudioRecorder: $showAudioRecorder,
            showCamera: $showCamera,
            showVideoRecorder: $showVideoRecorder,
            droneIsOn: $droneIsOn,
            recorderIcon: recorderIcon,
            droneEngine: audioServices.droneEngine,
            stopAttachmentPlayback: stopAttachmentPlayback,
            ensureCameraAuthorized: ensureCameraAuthorized
        )
        .cardSurface()
    }

@ViewBuilder
private var tasksPadSection: some View {
    TasksPadCard(
        showTasksPad: $showTasksPad,
        taskLines: $taskLines,
        autoTaskTexts: $autoTaskTexts,
        focusedTaskID: $focusedTaskID,
        tasksAccent: tasksAccent,
        onToggleDone: { id in toggleDone(id) },
        onDeleteLine: { id in deleteLine(id) },
        onClearAll: { clearAllTasks() },
        onAddEmptyLine: { addEmptyTaskLine() },
        onHandleReturn: { id in handleTaskReturn(for: id) },
        onPersistSnapshot: { persistTasksSnapshot() },
        onExpand: {
            loadPracticeDefaultsIfNeeded()
            loadDefaultTasksIfNeeded()
            persistTasksSnapshot()
        }
    )
    .cardSurface()
}

    @ViewBuilder
    private var attachmentsSection: some View {
        if !stagedImages.isEmpty || !stagedAudio.isEmpty || !stagedVideos.isEmpty {
            AttachmentsCard(
                stagedImages: $stagedImages,
                stagedAudio: $stagedAudio,
                stagedVideos: $stagedVideos,
                selectedThumbnailID: $selectedThumbnailID,
                trimItem: $trimItem,
                audioTitleEditingBuffer: $audioTitleEditingBuffer,
                audioTitleDidImmediatePersist: $audioTitleDidImmediatePersist,
                audioTitles: $audioTitles,
                audioAutoTitles: audioAutoTitles,
                audioDurations: audioDurations,
                videoThumbnails: $videoThumbnails,
                stagedSizeWarning: stagedSizeWarning,
                currentlyPlayingID: currentlyPlayingID,
                isAudioPlaying: isAudioPlaying,
                recorderIcon: recorderIcon,
                focusedAudioTitleID: $focusedAudioTitleID,
                formattedClipDuration: formattedClipDuration,
                surrogateURL: surrogateURL(for:),
                onPersistStagedAttachments: { persistStagedAttachments() },
                onTogglePlay: { togglePlay($0) },
                onDeleteAudio: { deleteAudio($0) },
                onPersistAudioTitleImmediately: { id, buffer in
                    persistAudioTitleImmediately(for: id, bufferValue: buffer)
                },
                onScheduleDebouncedAudioTitlePersist: { id, buffer in
                    scheduleDebouncedAudioTitlePersist(for: id, bufferValue: buffer)
                },
                onPersistCommittedAudioTitle: { id in
                    persistCommittedAudioTitle(for: id)
                },
                onPlayVideo: { playVideo($0) }
            )
            .cardSurface()
        }
    }

    // MARK: - Sheet content helpers

    

    

    

    

    

    

    

    

    

    
// MARK: - Cards (split to help the type-checker)

   
   

    // MARK: - Helpers for wheel UI

    private func currentInstrumentName() -> String {
        if let inst = instrument { return inst.name ?? "Instrument" }
        if instruments.indices.contains(instrumentIndex) { return instruments[instrumentIndex].name ?? "Instrument" }
        return "Instrument"
    }

    func applyInstrumentIndex() {
        guard instruments.indices.contains(instrumentIndex) else { return }
        instrument = instruments[instrumentIndex]
    }

    func activityDisplayName(for choice: String) -> String {
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

    func applyChoice(_ choice: String) {
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

    func activityChoicesPinned() -> [String] {
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
    func start() {
        UserDefaults.standard.set(true, forKey: sessionActiveKey)
        // Seed a new session ID when starting a fresh session so PostRecordDetailsView can clear its drafts
        let ud = UserDefaults.standard
        if ud.string(forKey: currentSessionIDKey) == nil {
            ud.set(UUID().uuidString, forKey: currentSessionIDKey)
        }
        guard instrument != nil else { return }
        if !isRunning {
            if startDate == nil { startDate = Date() }

            // Persist the actual session start time for PostRecordDetailsView consumers
            let ud = UserDefaults.standard
            let startEpoch = startDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            // Prefer a per-session key when we have a session ID
            if let sid = ud.string(forKey: currentSessionIDKey), !sid.isEmpty {
                let perSessionKey = "PracticeTimer.currentSessionStartTimestamp.\(sid)"
                if ud.object(forKey: perSessionKey) == nil {
                    ud.set(startEpoch, forKey: perSessionKey)
                }
            }
            // Also set a global fallback if not already present (back-compat)
            if ud.object(forKey: "PracticeTimer.currentSessionStartTimestamp") == nil {
                ud.set(startEpoch, forKey: "PracticeTimer.currentSessionStartTimestamp")
            }

            isRunning = true
            persistTimerState()
        }
        startTicker()
        recomputeElapsedForUI()
    }

    private func pause() {
        killDroneAndMetronome()
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

    func reset() {
        pause()
        clearPersistedTimer()
        clearPersistedStagedAttachments()
        clearPersistedTasks()
        resetUIOnly()
        UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
    }

    private func finish() {
          // Resolve true start time in order: in-memory startDate, per-session key, global fallback
          let ud = UserDefaults.standard
          var resolvedStart: Date? = startDate
          if resolvedStart == nil {
              if let sid = ud.string(forKey: currentSessionIDKey), !sid.isEmpty {
                  let perSessionKey = "PracticeTimer.currentSessionStartTimestamp.\(sid)"
                  if ud.object(forKey: perSessionKey) != nil {
                      let epoch = ud.double(forKey: perSessionKey)
                      if epoch > 0 { resolvedStart = Date(timeIntervalSince1970: epoch) }
                  }
              }
          }
          if resolvedStart == nil {
              if ud.object(forKey: "PracticeTimer.currentSessionStartTimestamp") != nil {
                  let epoch = ud.double(forKey: "PracticeTimer.currentSessionStartTimestamp")
                  if epoch > 0 { resolvedStart = Date(timeIntervalSince1970: epoch) }
              }
          }
          finalizedStartDate = resolvedStart

          let total = trueElapsedSeconds()
          finalizedDuration = total
          pause()
          didSaveFromReview = false
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

    private func formattedAutoTitle(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyLLLdd_HH:mm"
        let s = df.string(from: date)
        return s.lowercased()
    }

    private func formattedClipDuration(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Persistence (UserDefaults)
    private enum TimerDefaultsKey: String {
        case startedAtEpoch = "PracticeTimer.startedAtEpoch"
        case accumulated = "PracticeTimer.accumulated"
        case isRunning = "PracticeTimer.isRunning"
        case activityRaw = "PracticeTimer.activityRaw"
        case activityDetail = "PracticeTimer.activityDetail"

        case stagedAudioIDs = "PracticeTimer.stagedAudioIDs"
        case stagedVideoIDs = "PracticeTimer.stagedVideoIDs"
        case stagedImageIDs = "PracticeTimer.stagedImageIDs"
        // Commented out to move audio metadata persistence to StagingStore
        // case audioTitles = "PracticeTimer.audioTitles"
        // case audioAutoTitles = "PracticeTimer.audioAutoTitles"
        // case audioDurations = "PracticeTimer.audioDurations"
        case selectedThumbnailID = "PracticeTimer.selectedThumbnailID"

        case taskLines = "PracticeTimer.taskLines"
        case autoTaskTexts = "PracticeTimer.autoTaskTexts"
        case showTasksPad = "PracticeTimer.showTasksPad"
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

        // Restore staged attachments by IDs via StagingStore (no raw bytes in defaults)
        let audioIDStrings = d.array(forKey: TimerDefaultsKey.stagedAudioIDs.rawValue) as? [String] ?? []
        let videoIDStrings = d.array(forKey: TimerDefaultsKey.stagedVideoIDs.rawValue) as? [String] ?? []
        let imageIDStrings = d.array(forKey: TimerDefaultsKey.stagedImageIDs.rawValue) as? [String] ?? []
        let audioIDs = audioIDStrings.compactMap(UUID.init)
        let videoIDs = videoIDStrings.compactMap(UUID.init)
        let imageIDs = imageIDStrings.compactMap(UUID.init)
        #if DEBUG
        print("[PracticeTimer] hydrate IDs defaults audio=\(audioIDs) video=\(videoIDs) image=\(imageIDs) store=\(StagingStore.list().map{ $0.id })")
        #endif

        let refs = StagingStore.list()
        var rebuiltAudio: [StagedAttachment] = []
        var rebuiltVideo: [StagedAttachment] = []
        var rebuiltImages: [StagedAttachment] = []
        var rebuiltThumbs: [UUID: UIImage] = [:]

        func loadData(for id: UUID) -> (Data, StagedAttachmentRef.Kind)? {
            guard let ref = refs.first(where: { $0.id == id }) else { return nil }
            let url = StagingStore.absoluteURL(for: ref)
            if let data = try? Data(contentsOf: url) { return (data, ref.kind) }
            return nil
        }

        for id in audioIDs {
            if let (data, kind) = loadData(for: id), kind == .audio {
                rebuiltAudio.append(StagedAttachment(id: id, data: data, kind: .audio))
            }
        }
        for id in videoIDs {
            if let (data, kind) = loadData(for: id), kind == .video {
                rebuiltVideo.append(StagedAttachment(id: id, data: data, kind: .video))
                if let thumb = generateVideoThumbnail(from: data, id: id) { rebuiltThumbs[id] = thumb }
            }
        }
        for id in imageIDs {
            if let (data, kind) = loadData(for: id), kind == .image {
                rebuiltImages.append(StagedAttachment(id: id, data: data, kind: .image))
            }
        }
        self.stagedAudio = rebuiltAudio
        self.stagedVideos = rebuiltVideo
        self.stagedImages = rebuiltImages
        self.videoThumbnails = rebuiltThumbs
        if rebuiltAudio.isEmpty && rebuiltVideo.isEmpty && rebuiltImages.isEmpty {
            self.selectedThumbnailID = nil
        }

        // Pull audio metadata from StagingStore (source of truth)
        do { try StagingStore.bootstrap() } catch { /* ignore */ }
        let refsList = StagingStore.list()
        for att in self.stagedAudio {
            if let ref = refsList.first(where: { $0.id == att.id }) {
                // Always keep auto title for fallback display
                if let auto = ref.audioAutoTitle, !auto.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    self.audioAutoTitles[att.id] = auto
                }
                // Prefer a non-empty user display title from store; otherwise keep existing in-memory title; finally fall back to auto
                let existingTitle = (self.audioTitles[att.id] ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let storeTitle = (ref.audioDisplayTitle ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !storeTitle.isEmpty {
                    self.audioTitles[att.id] = storeTitle
                } else if existingTitle.isEmpty {
                    // Only if we truly have no user title, fall back to auto
                    if let auto = self.audioAutoTitles[att.id], !auto.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                        self.audioTitles[att.id] = auto
                    }
                }
                if let d = ref.duration, d.isFinite { self.audioDurations[att.id] = max(0, Int(d.rounded())) }
            }
            // Backfill duration if missing by probing the data
            if self.audioDurations[att.id] == nil, let player = try? AVAudioPlayer(data: att.data) {
                let secs = max(0, Int(player.duration.rounded()))
                self.audioDurations[att.id] = secs
                StagingStore.updateAudioMetadata(id: att.id, title: nil, autoTitle: nil, duration: Double(secs))
            }
            #if DEBUG
            let tDebug = self.audioTitles[att.id] ?? ""
            let aDebug = self.audioAutoTitles[att.id] ?? ""
            print("[PracticeTimer] hydrate audio id=\(att.id) title=\(tDebug) auto=\(aDebug) dur=\(self.audioDurations[att.id] ?? -1)")
            #endif
        }

        // Restore task pad contents
        if let taskData = d.data(forKey: TimerDefaultsKey.taskLines.rawValue),
           let decoded = try? JSONDecoder().decode([SerializedTaskLine].self, from: taskData) {
            self.taskLines = decoded.map { TaskLine(text: $0.text, isDone: $0.isDone) }
            // Rebuild stable IDs by mapping original ids to new TaskLine ids in autoTaskTexts
            var remappedAuto: [UUID:String] = [:]
            if let autoData = d.data(forKey: TimerDefaultsKey.autoTaskTexts.rawValue),
               let decodedAuto = try? JSONDecoder().decode([UUID:String].self, from: autoData) {
                for (index, ser) in decoded.enumerated() where self.taskLines.indices.contains(index) {
                    let newID = self.taskLines[index].id
                    remappedAuto[newID] = decodedAuto[ser.id]
                }
            }
            self.autoTaskTexts = remappedAuto
        }
        self.showTasksPad = d.bool(forKey: TimerDefaultsKey.showTasksPad.rawValue)
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
        persistStagedAttachments()
        persistTasksSnapshot()
    }

    // Small safe persist wrapper for timer snapshot
    private func persistTimerSnapshotSafely(context: String) {
        persistTimerSnapshot()
        // Best-effort sync and log if it fails or if the system warns about large writes elsewhere
        let ok = UserDefaults.standard.synchronize()
        if !ok {
            print("[PracticeTimer] UserDefaults synchronize returned false during \(context)")
        }
    }

    func clearPersistedTimer() {
        let d = UserDefaults.standard
        d.removeObject(forKey: TimerDefaultsKey.startedAtEpoch.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.accumulated.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.isRunning.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.activityRaw.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.activityDetail.rawValue)
    }

    func resetUIOnly() {
        isRunning = false
        startDate = nil
        accumulatedSeconds = 0
        elapsedSeconds = 0
        activity = .practice
        activityDetail = ""
        activityChoice = "core:0"
    }

    private func syncActivityChoiceFromState() {
        if activityDetail.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            activityChoice = "core:\(activity.rawValue)"
        } else {
            activityChoice = "custom:\(activityDetail)"
        }
    }

    // MARK: - Persist task pad contents
    private struct SerializedTaskLine: Codable {
        let id: UUID
        let text: String
        let isDone: Bool
    }

    private func persistTasksSnapshot() {
        let d = UserDefaults.standard
        let encoder = JSONEncoder()
        let payload: [SerializedTaskLine] = taskLines.map { SerializedTaskLine(id: $0.id, text: $0.text, isDone: $0.isDone) }
        if let data = try? encoder.encode(payload) {
            d.set(data, forKey: TimerDefaultsKey.taskLines.rawValue)
        }
        if let auto = try? encoder.encode(autoTaskTexts) {
            d.set(auto, forKey: TimerDefaultsKey.autoTaskTexts.rawValue)
        }
        d.set(showTasksPad, forKey: TimerDefaultsKey.showTasksPad.rawValue)
    }

    func clearPersistedTasks() {
        let d = UserDefaults.standard
        d.removeObject(forKey: TimerDefaultsKey.taskLines.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.autoTaskTexts.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.showTasksPad.rawValue)
    }

    // Best-effort purge for surrogate temp files created for staged items
    private func purgeStagedTempFiles() {
        let fm = FileManager.default
        // Purge audio surrogates
        for att in stagedAudio {
            let ext = "m4a"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(att.id.uuidString)
                .appendingPathExtension(ext)
            try? fm.removeItem(at: url)
        }
        // Purge image surrogates
        for att in stagedImages {
            let ext = "jpg"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(att.id.uuidString)
                .appendingPathExtension(ext)
            try? fm.removeItem(at: url)
        }
        // Purge video surrogates
        for att in stagedVideos {
            let ext = "mov"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(att.id.uuidString)
                .appendingPathExtension(ext)
            try? fm.removeItem(at: url)
        }
        // Clear cached video thumbnails when purging staged items
        videoThumbnails.removeAll()
    }

    // Broad cleanup for any UUID-named temp surrogates created during a live session
    private func removeAllSessionTempSurrogates() {
        let fm = FileManager.default
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        // Match files like <UUID>.mov, <UUID>.m4a, <UUID>.jpg, <UUID>_poster.jpg
        let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(_poster)?\\.(mov|m4a|jpg)$"
        let uuidRegex = try? NSRegularExpression(pattern: pattern)
        var removed = 0
        for url in items {
            let name = url.lastPathComponent
            let range = NSRange(location: 0, length: name.utf16.count)
            if let re = uuidRegex, re.firstMatch(in: name, options: [], range: range) != nil {
                if (try? fm.removeItem(at: url)) != nil { removed += 1 }
            }
        }
        #if DEBUG
        if removed > 0 { print("[PracticeTimer] removeAllSessionTempSurrogates — removed temp files: \(removed)") }
        #endif
    }
    
    private var totalStagedBytesImagesAudio: Int {
        let imgs = stagedImages.reduce(0) { $0 + $1.data.count }
        let auds = stagedAudio.reduce(0) { $0 + $1.data.count }
        return imgs + auds
    }
    private var totalStagedBytesVideo: Int {
        stagedVideos.reduce(0) { $0 + $1.data.count }
    }
    private var stagedSizeWarning: String? {
        let nonVideoLimit = 100 * 1024 * 1024 // 100 MB (existing behavior)
        let videoLimit = 500 * 1024 * 1024     // 500 MB for videos
        var warnings: [String] = []
        if totalStagedBytesImagesAudio > nonVideoLimit {
            warnings.append("Large staging size for images/audio (~\(totalStagedBytesImagesAudio / (1024*1024)) MB). Consider saving or removing some items.")
        }
        if totalStagedBytesVideo > videoLimit {
            warnings.append("Large video staging size (~\(totalStagedBytesVideo / (1024*1024)) MB). Consider trimming or removing some items.")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    // MARK: - Persist staged attachments (unsaved session resilience)
    /*
    private struct SerializedAttachment: Codable {
        let id: UUID
        let data: Data
    }
    */
    // Removed SerializedAttachment struct as it's no longer used

    // -- Added per instructions: prune audio metadata to staged IDs --
    private func pruneAudioMetadataToStaged() {
        let valid = Set(stagedAudio.map { $0.id })
        audioTitles = audioTitles.filter { valid.contains($0.key) }
        audioAutoTitles = audioAutoTitles.filter { valid.contains($0.key) }
        audioDurations = audioDurations.filter { valid.contains($0.key) }
    }

    func persistStagedAttachments() {
        pruneAudioMetadataToStaged()
        
        let validAudioIDs = Set(stagedAudio.map { $0.id })
        #if DEBUG
        print("[PracticeTimer] persistStagedAttachments ids=\(validAudioIDs.map{ $0.uuidString })")
        #endif
        
        // Coalesce empty titles to auto-titles to preserve intended fallback
        for id in validAudioIDs {
            #if DEBUG
            let dur = audioDurations[id].map { Double($0) }
            print("[PracticeTimer] persist id=\(id) focused=\(focusedAudioTitleID == id) buffer=\(audioTitleEditingBuffer[id] ?? "") title=\((audioTitles[id] ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) auto=\(audioAutoTitles[id] ?? "") dur=\(String(describing: dur))")
            #endif

            let current = (audioTitles[id] ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if current.isEmpty, let auto = audioAutoTitles[id] {
                audioTitles[id] = auto
            }
        }
        
        let d = UserDefaults.standard
        // Persist arrays of IDs instead of raw Data blobs
        let audioIDs = stagedAudio.map { $0.id.uuidString }
        let videoIDs = stagedVideos.map { $0.id.uuidString }
        let imageIDs = stagedImages.map { $0.id.uuidString }
        d.set(audioIDs, forKey: TimerDefaultsKey.stagedAudioIDs.rawValue)
        d.set(videoIDs, forKey: TimerDefaultsKey.stagedVideoIDs.rawValue)
        d.set(imageIDs, forKey: TimerDefaultsKey.stagedImageIDs.rawValue)
        // Persist audio metadata to StagingStore, not UserDefaults
        // Edited per instructions below:
        for id in validAudioIDs {
            let dur = audioDurations[id].map { Double($0) }
            let auto = audioAutoTitles[id]
            let inMemoryTitle = (audioTitles[id] ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            // If this id is currently focused and has a buffer, prefer the buffered non-empty value; but never push an empty string
            if let fid = focusedAudioTitleID, fid == id, let buffer = audioTitleEditingBuffer[id] {
                let trimmed = buffer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // Do not clear a previously saved user title; only update auto/duration
                    StagingStore.updateAudioMetadata(id: id, title: nil, autoTitle: auto, duration: dur)
                } else {
                    StagingStore.updateAudioMetadata(id: id, title: trimmed, autoTitle: auto, duration: dur)
                }
            } else {
                // Outside of focus, only write a title if it is non-empty; otherwise pass nil so store keeps existing display title
                StagingStore.updateAudioMetadata(id: id, title: inMemoryTitle.isEmpty ? nil : inMemoryTitle, autoTitle: auto, duration: dur)
            }
        }
        // Commented out: removed writing large audio metadata dicts to UserDefaults
        /*
        if let titles = try? JSONEncoder().encode(audioTitles) {
            d.set(titles, forKey: TimerDefaultsKey.audioTitles.rawValue)
        }
        if let autos = try? JSONEncoder().encode(audioAutoTitles) {
            d.set(autos, forKey: TimerDefaultsKey.audioAutoTitles.rawValue)
        }
        if let durs = try? JSONEncoder().encode(audioDurations) {
            d.set(durs, forKey: TimerDefaultsKey.audioDurations.rawValue)
        }
        */
        d.set(selectedThumbnailID?.uuidString, forKey: TimerDefaultsKey.selectedThumbnailID.rawValue)
    }

    private func mirrorFromStagingStore() {
        // Read lightweight refs from the staging store and populate local staged arrays (non-destructive to other state)
        let refs = StagingStore.list()
        var images: [StagedAttachment] = []
        var audios: [StagedAttachment] = []
        var videos: [StagedAttachment] = []
        var thumbs: [UUID: UIImage] = [:]

        for ref in refs {
            let abs = StagingStore.absoluteURL(for: ref)
            if let data = try? Data(contentsOf: abs) {
                switch ref.kind {
                case .image:
                    images.append(StagedAttachment(id: ref.id, data: data, kind: .image))
                case .audio:
                    audios.append(StagedAttachment(id: ref.id, data: data, kind: .audio))
                case .video:
                    videos.append(StagedAttachment(id: ref.id, data: data, kind: .video))
                    // If a posterPath exists, try to load and cache it as thumbnail; else generate from data as current behavior
                    if let posterRel = ref.posterPath {
                        let posterURL = StagingStore.absoluteURL(forRelative: posterRel)
                        if let imgData = try? Data(contentsOf: posterURL), let ui = UIImage(data: imgData) {
                            thumbs[ref.id] = ui
                        }
                    } else {
                        if let thumb = generateVideoThumbnail(from: data, id: ref.id) { thumbs[ref.id] = thumb }
                    }
                }
            }
        }
        
        // Ensure a stable auto-title exists for each audio item using its createdAt if missing
        for ref in refs where ref.kind == .audio {
            let id = ref.id
            if self.audioAutoTitles[id] == nil {
                self.audioAutoTitles[id] = formattedAutoTitle(from: ref.createdAt)
            }
        }

        // Non-destructive merge of audio metadata from StagingStore
        let refsList = StagingStore.list()
        var newTitles: [UUID:String] = self.audioTitles
        var newAutos: [UUID:String] = self.audioAutoTitles
        var newDurs: [UUID:Int] = self.audioDurations
        for a in audios {
            if let ref = refsList.first(where: { $0.id == a.id }) {
                if let auto = ref.audioAutoTitle { newAutos[a.id] = auto }
                let currentTitle = (newTitles[a.id] ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let storeTitle = (ref.audioDisplayTitle ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // Prefer persisted user display title; if none, keep current in-memory; only then fall back to auto
                if !storeTitle.isEmpty {
                    newTitles[a.id] = storeTitle
                } else if currentTitle.isEmpty, let auto = newAutos[a.id], !auto.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    newTitles[a.id] = auto
                }
                if let d = ref.duration, d.isFinite { newDurs[a.id] = max(0, Int(d.rounded())) }
            }
            // Backfill duration if still missing
            if newDurs[a.id] == nil, let player = try? AVAudioPlayer(data: a.data) {
                let secs = max(0, Int(player.duration.rounded()))
                newDurs[a.id] = secs
                StagingStore.updateAudioMetadata(id: a.id, title: nil, autoTitle: nil, duration: Double(secs))
            }
            // Non-destructive coalescing: only fall back to auto if title truly absent
            let currentTitle = (newTitles[a.id] ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if currentTitle.isEmpty, let auto = newAutos[a.id], !auto.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                newTitles[a.id] = auto
            }
        }
        self.audioTitles = newTitles
        self.audioAutoTitles = newAutos
        self.audioDurations = newDurs

        #if DEBUG
        print("[PracticeTimer] mirrorFromStagingStore titles=\(self.audioTitles.map { $0.key.uuidString + ":" + $0.value })")
        #endif

        // Update local state
        self.stagedImages = images
        self.stagedAudio = audios
        self.stagedVideos = videos
        self.videoThumbnails = thumbs
        // Preserve existing selectedThumbnailID if still present; otherwise set to first image id
        if let sel = self.selectedThumbnailID, images.contains(where: { $0.id == sel }) {
            self.selectedThumbnailID = sel
        } else {
            self.selectedThumbnailID = images.first?.id
        }
        // Prune audio metadata to mirrored staged audio IDs to avoid losing titles on resume
        let validAudioIDs = Set(audios.map { $0.id })
        self.audioTitles = self.audioTitles.filter { validAudioIDs.contains($0.key) }
        self.audioAutoTitles = self.audioAutoTitles.filter { validAudioIDs.contains($0.key) }
        self.audioDurations = self.audioDurations.filter { validAudioIDs.contains($0.key) }
        // Removed the loop that forcibly coalesced empty titles to auto here, per instructions

        // Persist snapshot so timer resume remains consistent
        persistStagedAttachments()
    }

    func clearPersistedStagedAttachments() {
        let d = UserDefaults.standard
        d.removeObject(forKey: TimerDefaultsKey.stagedAudioIDs.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.stagedVideoIDs.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.stagedImageIDs.rawValue)
        // Commented out removing audio metadata from UserDefaults since persistence moved to StagingStore
        /*
        d.removeObject(forKey: TimerDefaultsKey.audioTitles.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.audioAutoTitles.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.audioDurations.rawValue)
        */
        d.removeObject(forKey: TimerDefaultsKey.selectedThumbnailID.rawValue)
    }

    // Remove ALL staged refs and files from the StagingStore (session discard)
    private func clearAllStagingStoreRefs() {
        let refs = StagingStore.list()
        for ref in refs { StagingStore.remove(ref) }
    }

    // MARK: - Audio attachment helpers

    func stageAudioURL(_ url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            // Clean up original file to avoid duplicates taking space
            try? FileManager.default.removeItem(at: url)
            let id = UUID()

            // Auto-generate title from recording date/time (using file's creation date if available, else now)
            let title: String
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let cdate = attrs[.creationDate] as? Date {
                title = formattedAutoTitle(from: cdate)
            } else {
                title = formattedAutoTitle(from: Date())
            }
            audioAutoTitles[id] = title
            audioTitles[id] = title
            #if DEBUG
            print("[PracticeTimer] stageAudioURL: seeded titles id=\(id) auto=\(title)")
            #endif

            // Compute duration from audio data
            var durationSeconds: Int = 0
            if let player = try? AVAudioPlayer(data: data) {
                durationSeconds = max(0, Int(player.duration.rounded()))
            }
            audioDurations[id] = durationSeconds

            stagedAudio.append(StagedAttachment(id: id, data: data, kind: .audio))
            if UserDefaults.standard.bool(forKey: ephemeralMediaFlagKey) == false {
                UserDefaults.standard.set(true, forKey: ephemeralMediaFlagKey)
            }
            persistStagedAttachments()

            // Double-write to staging store
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("m4a")
            try? data.write(to: tmp, options: .atomic)
            do {
                let ref = try await StagingStore.saveNew(from: tmp, kind: .audio, suggestedName: title, duration: Double(durationSeconds), poster: nil)
                // Ensure store metadata has the user-visible title
                StagingStore.updateAudioMetadata(id: ref.id, title: title, autoTitle: title, duration: Double(durationSeconds))
                // If StagingStore generated a different UUID, remap our local staged item and metadata to that UUID
                if ref.id != id {
                    #if DEBUG
                    print("[PracticeTimer] Remapping audio ID local=\(id) -> store=\(ref.id)")
                    #endif
                    // Update stagedAudio array: replace the element with new id preserving data
                    if let idx = self.stagedAudio.firstIndex(where: { $0.id == id }) {
                        let data = self.stagedAudio[idx].data
                        self.stagedAudio[idx] = StagedAttachment(id: ref.id, data: data, kind: .audio)
                    }
                    // Remap metadata dictionaries
                    let titleVal = self.audioTitles.removeValue(forKey: id)
                    if let titleVal = titleVal { self.audioTitles[ref.id] = titleVal }
                    let autoVal = self.audioAutoTitles.removeValue(forKey: id)
                    if let autoVal = autoVal { self.audioAutoTitles[ref.id] = autoVal }
                    let durVal = self.audioDurations.removeValue(forKey: id)
                    if let durVal = durVal { self.audioDurations[ref.id] = durVal }
                    // Persist updated ID arrays immediately so hydration will see the store id
                    self.persistStagedAttachments()
                }
            } catch {
                print("StagingStore saveNew (audio) failed: \(error)")
            }
        } catch {
            print("Failed to stage audio: \(error)")
        }
    }

    func stageVideoURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            // Clean up original file to avoid duplicates taking space
            try? FileManager.default.removeItem(at: url)
            let id = UUID()

            // Generate thumbnail from the video data and cache it
            if let thumb = generateVideoThumbnail(from: data, id: id) {
                videoThumbnails[id] = thumb
            }

            stagedVideos.append(StagedAttachment(id: id, data: data, kind: .video))
            if UserDefaults.standard.bool(forKey: ephemeralMediaFlagKey) == false {
                UserDefaults.standard.set(true, forKey: ephemeralMediaFlagKey)
            }
            persistStagedAttachments()

            // Double-write to staging store (with poster if generated)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("mov")
            try? data.write(to: tmp, options: .atomic)
            var posterURL: URL? = nil
            if let thumb = videoThumbnails[id], let jpg = thumb.jpegData(compressionQuality: 0.85) {
                let p = FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString)_poster").appendingPathExtension("jpg")
                try? jpg.write(to: p, options: .atomic)
                posterURL = p
            }
            let duration = AVAsset(url: tmp).duration.seconds
            Task {
                do {
                    let ref = try await StagingStore.saveNew(from: tmp, kind: .video, suggestedName: id.uuidString, duration: duration.isFinite ? duration : nil, poster: posterURL)
                    if ref.id != id {
                        #if DEBUG
                        print("[PracticeTimer] Remapping video ID local=\(id) -> store=\(ref.id)")
                        #endif
                        // Update stagedVideos array to use store id
                        if let idx = self.stagedVideos.firstIndex(where: { $0.id == id }) {
                            let data = self.stagedVideos[idx].data
                            self.stagedVideos[idx] = StagedAttachment(id: ref.id, data: data, kind: .video)
                        }
                        // Remap thumbnail cache
                        if let thumb = self.videoThumbnails.removeValue(forKey: id) {
                            self.videoThumbnails[ref.id] = thumb
                        }
                        // Update persisted IDs immediately
                        self.persistStagedAttachments()
                    }
                } catch {
                    print("StagingStore saveNew (video) failed: \(error)")
                }
            }
        } catch {
            print("Failed to stage video: \(error)")
        }
    }

    // Prepare and present a video player for a given staged video ID
    private func playVideo(_ id: UUID) {
        guard let att = stagedVideos.first(where: { $0.id == id }) else { return }
        // Ensure a temp surrogate exists for AttachmentViewerView
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("mov")
        do {
            try att.data.write(to: url, options: .atomic)
            attachmentViewer = PTVViewerURL(url: url)
        } catch {
            print("Failed to prepare video for viewer: \(error)")
        }
    }

    // Generate a thumbnail image for a video from raw Data by writing a temp file and using AVAssetImageGenerator
    private func generateVideoThumbnail(from data: Data, id: UUID) -> UIImage? {
        // Write to a temporary surrogate URL so AVAsset can read it
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("mov")
        do {
            try data.write(to: tmp, options: .atomic)
            let asset = AVAsset(url: tmp)
            let imgGen = AVAssetImageGenerator(asset: asset)
            imgGen.appliesPreferredTrackTransform = true
            imgGen.maximumSize = CGSize(width: 512, height: 512)
            // Choose a representative frame around 40% into the clip (fallback to 0.2s)
            let duration = asset.duration
            let durationSeconds = duration.isNumeric ? duration.seconds : 0
            let targetSeconds = durationSeconds > 0 ? min(max(durationSeconds * 0.4, 0.2), max(durationSeconds - 0.1, 0.2)) : 0.2
            let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)
            let cg = try imgGen.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cg)
        } catch {
            print("Thumbnail generation failed: \(error)")
            return nil
        }
    }

    

    // MARK: - Image attachment helpers (camera)
    func stageImage(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.8) {
            let id = UUID()
            stagedImages.append(StagedAttachment(id: id, data: data, kind: .image))
            // Auto-select first image as thumbnail
            let imageCount = stagedImages.count
            if imageCount == 1 { selectedThumbnailID = id }
            persistStagedAttachments()

            // Double-write to staging store
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
            try? data.write(to: tmp, options: .atomic)
            Task { _ = try? await StagingStore.saveNew(from: tmp, kind: .image, suggestedName: id.uuidString, duration: nil, poster: nil) }
        }
    }

    private func ensureCameraAuthorized(onAuthorized: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            onAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? onAuthorized() : { self.showCameraDeniedAlert = true }() }
            }
        default:
            self.showCameraDeniedAlert = true
        }
    }

    // Helper to get temporary surrogate URL for a staged attachment
    func surrogateURL(for att: StagedAttachment) -> URL? {
        let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
        return FileManager.default.temporaryDirectory.appendingPathComponent(att.id.uuidString).appendingPathExtension(ext)
    }
    
    private func commitAudioTitleEditingBuffers() {
        // For all buffered audio titles, commit them to audioTitles dictionary
        for (id, buffer) in audioTitleEditingBuffer {
            let trimmed = buffer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if trimmed.isEmpty {
                audioTitles[id] = audioAutoTitles[id] ?? ""
            } else {
                audioTitles[id] = buffer
            }
        }
        audioTitleEditingBuffer.removeAll()
    }

    // New helper to persist a single committed audio title to StagingStore
    private func persistCommittedAudioTitle(for id: UUID) {
        let title = (audioTitles[id] ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let auto = audioAutoTitles[id]
        let dur = audioDurations[id].map { Double($0) }
        StagingStore.updateAudioMetadata(id: id, title: title.isEmpty ? nil : title, autoTitle: auto, duration: dur)
    }
    
    private func persistAudioTitleImmediately(for id: UUID, bufferValue: String) {
        #if DEBUG
        print("[PracticeTimer] persistAudioTitleImmediately id=\(id) buffer=\(bufferValue)")
        #endif
        let trimmed = bufferValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        // Update in-memory title immediately so it survives quick navigation before focus loss
        if trimmed.isEmpty {
            audioTitles[id] = audioAutoTitles[id] ?? ""
        } else {
            audioTitles[id] = bufferValue
        }
        // Cancel any pending debounce for this id to avoid out-of-order writes
        if let w = audioTitleDebounceWork[id] { w.cancel() }
        audioTitleDebounceWork[id] = nil
        // Persist to StagingStore synchronously
        let dur = audioDurations[id].map { Double($0) }
        StagingStore.updateAudioMetadata(id: id, title: trimmed.isEmpty ? nil : bufferValue, autoTitle: audioAutoTitles[id], duration: dur)
        // Snapshot IDs/metadata for resilience
        persistStagedAttachments()
    }

    private func scheduleDebouncedAudioTitlePersist(for id: UUID, bufferValue: String) {
        #if DEBUG
        print("[PracticeTimer] scheduleDebouncedAudioTitlePersist id=\(id) buffer=\(bufferValue)")
        #endif
        // Cancel any existing work for this id
        if let w = audioTitleDebounceWork[id] { w.cancel() }
        let work = DispatchWorkItem {
            let trimmed = bufferValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            // Update in-memory title immediately so it survives quick navigation before focus loss
            if trimmed.isEmpty {
                self.audioTitles[id] = self.audioAutoTitles[id] ?? ""
            } else {
                self.audioTitles[id] = bufferValue
            }
            // Persist to StagingStore (source of truth)
            let dur = self.audioDurations[id].map { Double($0) }
            StagingStore.updateAudioMetadata(id: id, title: trimmed.isEmpty ? nil : bufferValue, autoTitle: self.audioAutoTitles[id], duration: dur)
            // Also persist staged IDs snapshot for resilience
            self.persistStagedAttachments()
        }
        audioTitleDebounceWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // New helper method as per instructions
    private func commitAllAudioTitleBuffersAndPersist() {
        #if DEBUG
        print("[PracticeTimer] commitAllAudioTitleBuffersAndPersist start focused=\(String(describing: focusedAudioTitleID)) buffers=\(audioTitleEditingBuffer.keys.map{ $0.uuidString })")
        #endif
        // Cancel all pending debounced work
        for (_, work) in audioTitleDebounceWork { work.cancel() }
        audioTitleDebounceWork.removeAll()
        // If there is a focused field, ensure its buffer is committed first
        // Edited per instructions below:
        if let fid = focusedAudioTitleID, let buffer = audioTitleEditingBuffer[fid] {
            let trimmed = buffer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            #if DEBUG
            print("[PracticeTimer] commit focused id=\(fid) trimmed=\(trimmed)")
            #endif
            if trimmed.isEmpty {
                // Keep UI fallback to auto, but do not clear persisted user title
                audioTitles[fid] = audioAutoTitles[fid] ?? ""
                // Persist only auto/duration without clearing user title
                let dur = audioDurations[fid].map { Double($0) }
                StagingStore.updateAudioMetadata(id: fid, title: nil, autoTitle: audioAutoTitles[fid], duration: dur)
            } else {
                audioTitles[fid] = buffer
                persistCommittedAudioTitle(for: fid)
            }
            audioTitleEditingBuffer.removeValue(forKey: fid)
        }
        // Commit all remaining buffered titles
        if !audioTitleEditingBuffer.isEmpty {
            let ids = Array(audioTitleEditingBuffer.keys)
            commitAudioTitleEditingBuffers()
            for id in ids { persistCommittedAudioTitle(for: id) }
        }
        // Persist after any change so state survives suspension
        persistStagedAttachments()
        #if DEBUG
        print("[PracticeTimer] commitAllAudioTitleBuffersAndPersist done")
        #endif
    }

    // MARK: - Trim helpers (extracted to reduce type-checking complexity)
    func handleTrimSaveAsNew(from newURL: URL, basedOn item: StagedAttachment) {
        if let data = try? Data(contentsOf: newURL) {
            let newID = UUID()
            let newItem = StagedAttachment(id: newID, data: data, kind: item.kind)
            if item.kind == .audio {
                stagedAudio.append(newItem)
                if let player = try? AVAudioPlayer(data: data) {
                    audioDurations[newID] = max(0, Int(player.duration.rounded()))
                }
                let title = formattedAutoTitle(from: Date())
                audioAutoTitles[newID] = title
                audioTitles[newID] = title
            } else {
                stagedVideos.append(newItem)
                if let thumb = generateVideoThumbnail(from: data, id: newID) {
                    videoThumbnails[newID] = thumb
                }
            }
            persistStagedAttachments()
            do {
                try FileManager.default.removeItem(at: newURL)
                #if DEBUG
                print("[Trim] onSaveAsNew cleaned temp at \(newURL.path)")
                #endif
            } catch {
                #if DEBUG
                print("[Trim] onSaveAsNew temp cleanup failed: \(error)")
                #endif
            }
        }
        trimItem = nil
    }

    func handleTrimReplaceOriginal(from newURL: URL, for item: StagedAttachment) {
        let refs = StagingStore.list()
        guard let ref = refs.first(where: { $0.id == item.id }) else {
            try? FileManager.default.removeItem(at: newURL)
            #if DEBUG
            print("[Trim] replaceOriginal aborted — missing staging ref; cleaned temp at \(newURL.path)")
            #endif
            return
        }
        let existingAbsURL = StagingStore.absoluteURL(for: ref)
        let existingPath = existingAbsURL.path
        #if DEBUG
        let origSize = AttachmentStore.fileSize(atPath: existingPath)
        let tmpSize = AttachmentStore.fileSize(atURL: newURL)
        print("[Trim] replaceOriginal begin\n  original=\(existingPath) size=\(origSize)\n  temp=\(newURL.path) size=\(tmpSize)")
        #endif

        // Replace in-place at the Staging path to avoid extra copies in Documents
        let fm = FileManager.default
        let finalURL = existingAbsURL

        // Remove existing file first (best-effort)
        _ = try? fm.removeItem(at: finalURL)

        // Move the trimmed temp over the original path atomically
         do {
            try fm.moveItem(at: newURL, to: finalURL)
            if let newData = try? Data(contentsOf: finalURL) {
                if item.kind == .audio {
                    if let idx = stagedAudio.firstIndex(where: { $0.id == item.id }) {
                        stagedAudio[idx] = StagedAttachment(id: item.id, data: newData, kind: .audio)
                    }
                    if let player = try? AVAudioPlayer(data: newData) {
                        let secs = max(0, Int(player.duration.rounded()))
                        audioDurations[item.id] = secs
                        StagingStore.updateAudioMetadata(id: item.id, title: nil, autoTitle: nil, duration: Double(secs))
                    }
                } else {
                    if let idx = stagedVideos.firstIndex(where: { $0.id == item.id }) {
                        stagedVideos[idx] = StagedAttachment(id: item.id, data: newData, kind: .video)
                    }
                    if let thumb = generateVideoThumbnail(from: newData, id: item.id) {
                        videoThumbnails[item.id] = thumb
                    }
                }
            }
            persistStagedAttachments()
            trimItem = nil
            #if DEBUG
            let finalSize = AttachmentStore.fileSize(atPath: finalURL.path)
            print("[Trim] replaceOriginal done (in-place)\n  final=\(finalURL.path) size=\(finalSize)")
            #endif
         } catch {
            try? FileManager.default.removeItem(at: newURL)
            #if DEBUG
            print("[Trim] replaceOriginal failed (in-place): \(error). Cleaned temp at \(newURL.path)")
            #endif
         }
    }

    // MARK: - App Termination Cleanup
    // Cleanup path for app swipe-away termination; mirrors explicit Quit when ephemeral media exists
    private func handleAppTerminationCleanup() {
        // Respect existing behavior: only discard if this was an unsaved, ephemeral session with media
        let hasEphemeral = UserDefaults.standard.bool(forKey: ephemeralMediaFlagKey)
        guard hasEphemeral else { return }

        #if DEBUG
        StorageInspector.logSandboxUsage(tag: "Before Terminate Cleanup")
        #endif

        // Remove staged refs/files for current live session
        let ids: [UUID] = stagedAudio.map { $0.id } + stagedImages.map { $0.id } + stagedVideos.map { $0.id }
        if !ids.isEmpty {
            StagingStore.removeMany(ids: ids)
            let refsToDelete = StagingStore.list()
            StagingStore.deleteFiles(for: refsToDelete)
            #if DEBUG
            print("[PracticeTimer] terminate — removed \(ids.count) staged items")
            #endif
        }

        // Purge temp surrogates before clearing arrays
        purgeStagedTempFiles()
        removeAllSessionTempSurrogates()

        // Clear persisted IDs/state similar to Quit
        stopAttachmentPlayback()
        clearPersistedStagedAttachments()
        clearAllStagingStoreRefs()
        UserDefaults.standard.set(true, forKey: sessionDiscardedKey)
        UserDefaults.standard.set(false, forKey: sessionActiveKey)
        UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
        clearPersistedTasks()
        clearPersistedTimer()
        resetUIOnly()
        stagedAudio.removeAll()
        audioTitles.removeAll()
        audioAutoTitles.removeAll()
        audioDurations.removeAll()
        stagedImages.removeAll()
        stagedVideos.removeAll()
        videoThumbnails.removeAll()
        selectedThumbnailID = nil
        UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)

        #if DEBUG
        StorageInspector.logSandboxUsage(tag: "After Terminate Cleanup")
        #endif
    }

    // MARK: - New helper: killDroneAndMetronome
    func killDroneAndMetronome() {
        if droneIsOn {
            audioServices.droneEngine.stop()
            droneIsOn = false
        }
        if metronomeIsOn {
            audioServices.metronomeEngine.stop()
            metronomeIsOn = false
        }
    }

    // MARK: - New helper: metronomeEngineIsActuallyRunning
    private func metronomeEngineIsActuallyRunning() -> Bool {
        // MetronomeEngine exposes isRunning; prefer that when available
        return audioServices.metronomeEngine.isRunning
    }
}
 
// MARK: - Local InfoSheetView (minimal)
// If a global InfoSheetView exists later, rename this to avoid collisions.
struct InfoSheetView: View {
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







