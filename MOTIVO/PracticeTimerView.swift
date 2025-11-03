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
    @State private var didSaveFromReview: Bool = false

    // Info-only recording helpers
    @State private var showAudioHelp = false
    @State private var showVideoHelp = false

    // New audio recording and attachments state
    @State private var showAudioRecorder: Bool = false
    @State private var stagedAudio: [StagedAttachment] = []
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var currentlyPlayingID: UUID? = nil
    @State private var audioPlayerDelegate: AudioPlayerDelegateBridge? = nil
    @State private var isAudioPlaying: Bool = false

    // Added state for audio titles and focus
    @State private var audioTitles: [UUID: String] = [:]
    @State private var audioAutoTitles: [UUID: String] = [:]
    @State private var audioDurations: [UUID: Int] = [:]
    @FocusState private var focusedAudioTitleID: UUID?

    // Audio observer and interruption flags
    @State private var audioObserversInstalled: Bool = false
    @State private var wasPlayingBeforeInterruption_timer: Bool = false

    // Image capture state (mirrors AddEdit/PostRecord behavior)
    @State private var stagedImages: [StagedAttachment] = []
    @State private var selectedThumbnailID: UUID? = nil
    @State private var showCamera: Bool = false
    @State private var showCameraDeniedAlert: Bool = false

    // --- Inserted video recording and attachments state ---
    @State private var showVideoRecorder: Bool = false
    @State private var stagedVideos: [StagedAttachment] = []
    @State private var videoThumbnails: [UUID: UIImage] = [:]
    @State private var showVideoPlayer: Bool = false
    @State private var videoPlayerItem: AVPlayer? = nil

    // Add trimming state for audio/video clips
    @State private var trimItem: StagedAttachment? = nil
    @State private var isTrimPresented: Bool = false

    // Convenience flags
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }


    // --- Tasks/Notes Pad State (v7.9A) ---
    @State private var showTasksPad: Bool = false
    struct TaskLine: Identifiable {
        let id: UUID = UUID()
        var text: String
        var isDone: Bool = false
    }
    @State private var taskLines: [TaskLine] = []
    @State private var autoTaskTexts: [UUID: String] = [:]
    @FocusState private var focusedTaskID: UUID?
    private let tasksDefaultsKey: String = "practiceTasks_v1"

    private func loadDefaultTasksIfNeeded() {
        guard activity == .practice, taskLines.isEmpty else { return }
        if let defaults = UserDefaults.standard.array(forKey: tasksDefaultsKey) as? [String] {
            let mapped = defaults.map { TaskLine(text: $0, isDone: false) }
            self.taskLines = mapped
            // Store auto-texts for restore behavior
            for line in mapped {
                autoTaskTexts[line.id] = line.text
            }
        }
    }
    private func loadPracticeDefaultsIfNeeded() {
        // Determine owner scope using current user ID from PersistenceController; fallback to device
        let ownerScope: String = PersistenceController.shared.currentUserID ?? "device"
        let tasksKey = "practiceTasks_v1::\(ownerScope)"
        let toggleKey = "practiceTasks_autofill_enabled::\(ownerScope)"

        // Only proceed if practice activity, no existing lines, and autofill toggle is enabled
        guard activity == .practice,
              taskLines.isEmpty,
              UserDefaults.standard.bool(forKey: toggleKey) == true else { return }

        if let arr = UserDefaults.standard.array(forKey: tasksKey) as? [String] {
            let mapped = arr.map { TaskLine(text: $0, isDone: false) }
            self.taskLines = mapped
            for line in mapped {
                autoTaskTexts[line.id] = line.text
            }
        }
    }
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
    private func composeCompletedTasksNotesString() -> String? {
        let trimmedCompleted = taskLines
            .filter { $0.isDone }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedCompleted.isEmpty else { return nil }
        return trimmedCompleted.map { "• \($0)" }.joined(separator: "\n")
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
        if taskLines.isEmpty { showTasksPad = false }
        persistTasksSnapshot()
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    selectorsCard()
                    timerCard()

                    // ---------- Recording helpers (moved below timer) ----------
                    VStack(spacing: 12) {
                        HStack(spacing: Theme.Spacing.m) {
                            Button {
                                stopAttachmentPlayback()
                                showAudioRecorder = true
                            } label: {
                                Image(systemName: "mic.fill")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(recorderIcon)
                                    .frame(width: 48, height: 48)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(Text("Record audio help"))
                            .accessibilityHint(Text("Opens instructions for using your device’s app to capture audio."))

                            // New: Take Photo button (camera) inserted between mic and video
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    ensureCameraAuthorized { showCamera = true }
                                } label: {
                                    Image(systemName: "camera.fill")
                                        .symbolRenderingMode(.monochrome)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(recorderIcon)
                                        .frame(width: 48, height: 48)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(Text("Take photo"))
                                .accessibilityHint(Text("Opens the camera to take a photo."))
                            }

                            Button {
                                stopAttachmentPlayback()
                                showVideoRecorder = true
                            } label: {
                                Image(systemName: "video.fill")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(recorderIcon)
                                    .frame(width: 48, height: 48)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(Text("Record video"))
                            .accessibilityHint(Text("Opens the camera to record a video."))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .cardSurface()

                    // --- Tasks/Notes Pad (v7.9A) ---
                    Group {
                        if showTasksPad {
                            VStack(alignment: .leading, spacing: 8) {
                                // Centered header to align with rest of page
                                HStack(alignment: .firstTextBaseline) {
                                    Spacer(minLength: 0)
                                    Text("Notes / Tasks")
                                        .sectionHeader()
                                    Spacer(minLength: 0)
                                    Button(action: { showTasksPad = false }) {
                                        Text("Close")
                                            .font(Theme.Text.body)
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .stroke(Theme.Colors.secondaryText.opacity(0.12), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Capsule())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                ForEach($taskLines) { $line in
                                    HStack(spacing: 8) {
                                        Button { line.isDone.toggle(); persistTasksSnapshot() } label: {
                                            Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(tasksAccent)
                                        }
                                        TextField("Task", text: $line.text)
                                            .textFieldStyle(.plain)
                                            .disableAutocorrection(true)
                                            .focused($focusedTaskID, equals: line.id)
                                            .onTapGesture {
                                                focusedTaskID = line.id
                                            }
                                            .onSubmit {
                                                // If user leaves it empty, restore auto text if available
                                                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                                if trimmed.isEmpty, let auto = autoTaskTexts[line.id] {
                                                    line.text = auto
                                                }
                                                persistTasksSnapshot()
                                            }
                                            .onChange(of: focusedTaskID) { _, newFocus in
                                                if newFocus == line.id {
                                                    // If current equals auto text, clear to start fresh
                                                    if let auto = autoTaskTexts[line.id], line.text == auto {
                                                        line.text = ""
                                                    }
                                                    persistTasksSnapshot()
                                                }
                                            }

                                        Spacer(minLength: 8)

                                        Button(role: .destructive) {
                                            deleteLine(line.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.primary.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Button(action: { addEmptyTaskLine() }) {
                                    HStack { Image(systemName: "plus"); Text("Add line") }
                                        .foregroundStyle(tasksAccent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        } else {
                            Button(action: {
                                showTasksPad = true
                                loadPracticeDefaultsIfNeeded()
                                loadDefaultTasksIfNeeded()
                                persistTasksSnapshot()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                    Text("Notes / Tasks").sectionHeader()
                                }
                                .foregroundStyle(tasksAccent)
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                        }
                    }
                    .cardSurface()

                    // --- Attachments card (images + audio + videos) ---
                    if !stagedImages.isEmpty || !stagedAudio.isEmpty || !stagedVideos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Attachments").sectionHeader()

                            // Images grid
                            if !stagedImages.isEmpty {
                                let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(stagedImages, id: \.id) { att in
                                        ZStack(alignment: .topTrailing) {
                                            if let ui = UIImage(data: att.data) {
                                                Image(uiImage: ui)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 128, height: 128)
                                                    .background(Color.secondary.opacity(0.08))
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                                    )
                                            } else {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .fill(Color.secondary.opacity(0.08))
                                                    Image(systemName: "photo")
                                                        .imageScale(.large)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .frame(width: 128, height: 128)
                                            }

                                            // Controls: star to set thumbnail, delete
                                            VStack(spacing: 6) {
                                                Text(selectedThumbnailID == att.id ? "★" : "☆")
                                                    .font(.system(size: 16))
                                                    .padding(8)
                                                    .background(.ultraThinMaterial, in: Circle())
                                                    .onTapGesture { selectedThumbnailID = att.id }

                                                Button {
                                                    stagedImages.removeAll { $0.id == att.id }
                                                    if selectedThumbnailID == att.id {
                                                        selectedThumbnailID = stagedImages.first?.id
                                                    }
                                                    persistStagedAttachments()
                                                    // Mirror delete to staging store
                                                    if let ref = StagingStore.list().first(where: { $0.id == att.id }) { StagingStore.remove(ref) }
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .padding(8)
                                                        .background(.ultraThinMaterial, in: Circle())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(6)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            // Audio list
                            ForEach(stagedAudio, id: \.id) { att in
                                HStack(spacing: 12) {
                                    Button(action: { togglePlay(att.id) }) {
                                        Image(systemName: (currentlyPlayingID == att.id && isAudioPlaying) ? "pause.fill" : "play.fill")
                                    }
                                    .buttonStyle(.bordered)

                                    TextField("Title", text: Binding(
                                        get: { audioTitles[att.id] ?? "" },
                                        set: { audioTitles[att.id] = $0 }
                                    ))
                                    .textFieldStyle(.plain)
                                    .disableAutocorrection(true)
                                    .focused($focusedAudioTitleID, equals: att.id)
                                    .onTapGesture { focusedAudioTitleID = att.id }
                                    .onSubmit {
                                        let current = (audioTitles[att.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                        if current.isEmpty { audioTitles[att.id] = audioAutoTitles[att.id] ?? "" }
                                    }
                                    .onChange(of: focusedAudioTitleID) { _, newFocus in
                                        if newFocus == att.id {
                                            if (audioTitles[att.id] ?? "") == (audioAutoTitles[att.id] ?? "") {
                                                audioTitles[att.id] = ""
                                            }
                                        }
                                    }

                                    if let secs = audioDurations[att.id] {
                                        Text(formattedClipDuration(secs))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                            .font(.subheadline)
                                    }

                                    Spacer(minLength: 8)

                                    // Inline Trim Button
                                    Button(action: {
                                        if let url = surrogateURL(for: att) {
                                            try? att.data.write(to: url, options: .atomic)
                                            trimItem = att
                                            isTrimPresented = true
                                        }
                                    }) {
                                        Image(systemName: "scissors")
                                            .font(.system(size: 16, weight: .semibold))
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Trim audio")
                                    .accessibilityHint("Open the trim editor for this audio clip")

                                    Button(role: .destructive, action: { deleteAudio(att.id) }) {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contextMenu {
                                    Button("Trim", systemImage: "scissors") {
                                        if let url = surrogateURL(for: att) {
                                            try? att.data.write(to: url, options: .atomic)
                                            trimItem = att
                                            isTrimPresented = true
                                        }
                                    }
                                }
                            }
                            
                            // Videos grid (placeholder thumbs)
                            if !stagedVideos.isEmpty {
                                let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(stagedVideos, id: \.id) { att in
                                        ZStack(alignment: .topTrailing) {
                                            GeometryReader { geo in
                                                let side = geo.size.width
                                                ZStack {
                                                    if let thumb = videoThumbnails[att.id] {
                                                        Image(uiImage: thumb)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: side, height: side)
                                                            .clipped()
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .fill(Color.secondary.opacity(0.08))
                                                        Image(systemName: "film")
                                                            .imageScale(.large)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    // Center play overlay button
                                                    Button(action: { playVideo(att.id) }) {
                                                        ZStack {
                                                            Circle()
                                                                .fill(.ultraThinMaterial)
                                                                .frame(width: 44, height: 44)
                                                            Image(systemName: "play.fill")
                                                                .font(.system(size: 18, weight: .semibold))
                                                                .foregroundStyle(.primary)
                                                        }
                                                    }
                                                }
                                                .frame(width: side, height: side)
                                                .background(Color.secondary.opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                                )
                                            }
                                            .contextMenu {
                                                Button("Trim", systemImage: "scissors") {
                                                    if let url = surrogateURL(for: att) {
                                                        try? att.data.write(to: url, options: .atomic)
                                                        trimItem = att
                                                        isTrimPresented = true
                                                    }
                                                }
                                            }
                                            // Trim button above delete
                                            VStack(spacing: 6) {
                                                Button {
                                                    if let url = surrogateURL(for: att) {
                                                        try? att.data.write(to: url, options: .atomic)
                                                        trimItem = att
                                                        isTrimPresented = true
                                                    }
                                                } label: {
                                                    Image(systemName: "scissors")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .padding(8)
                                                        .background(.ultraThinMaterial, in: Circle())
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Trim video")
                                                .accessibilityHint("Open the trim editor for this video clip")

                                                Button {
                                                    // Remove surrogate temp file best-effort
                                                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(att.id.uuidString).appendingPathExtension("mov")
                                                    try? FileManager.default.removeItem(at: tmp)
                                                    stagedVideos.removeAll { $0.id == att.id }
                                                    videoThumbnails.removeValue(forKey: att.id)
                                                    persistStagedAttachments()
                                                    // Mirror delete to staging store
                                                    if let ref = StagingStore.list().first(where: { $0.id == att.id }) { StagingStore.remove(ref) }
                                                } label: {
                                                    Image(systemName: "trash")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .padding(8)
                                                        .background(.ultraThinMaterial, in: Circle())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(6)
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            if let warn = stagedSizeWarning {
                                Text(warn)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                    .padding(.top, 4)
                            }
                        }
                        .cardSurface()
                    }
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
                do { try StagingStore.bootstrap() } catch { /* ignore */ }
                mirrorFromStagingStore()
                hydrateTimerFromStorage()
                startTicker()
                persistStagedAttachments()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    hydrateTimerFromStorage()
                    startTicker()
                case .inactive, .background:
                    stopTicker()
                    persistTimerSnapshot()
                    removeAudioObserversIfNeeded()
                    purgeStagedTempFiles()
                    do { try StagingStore.bootstrap() } catch { /* ignore */ }
                @unknown default:
                    break
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Quit") {
                        // Clear persisted and in-memory staged attachments and reset timer
                        stopAttachmentPlayback()
                        clearPersistedStagedAttachments()
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
                        purgeStagedTempFiles()
                        isPresented = false
                    }
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
                    notesPrefill: composeCompletedTasksNotesString(),
                    prefillAttachments: (stagedImages + stagedAudio + stagedVideos),
                    prefillAttachmentNames: audioTitles,
                    onSaved: {
                        didSaveFromReview = true
                        clearPersistedTimer()
                        clearPersistedStagedAttachments()
                        clearPersistedTasks()
                        resetUIOnly()
                        stagedAudio.removeAll()
                        audioTitles.removeAll()
                        stagedImages.removeAll()
                        stagedVideos.removeAll()
                        videoThumbnails.removeAll()
                        selectedThumbnailID = nil
                        isPresented = false
                    }
                )
            }
            .onChange(of: showReviewSheet) { oldValue, newValue in
                // If the review sheet was closed and no save occurred, reset timer for next opening
                if oldValue == true && newValue == false && didSaveFromReview == false {
                    clearPersistedTimer()
                    clearPersistedStagedAttachments()
                    clearPersistedTasks()
                    resetUIOnly()
                    stagedAudio.removeAll()
                    audioTitles.removeAll()
                    stagedImages.removeAll()
                    stagedVideos.removeAll()
                    videoThumbnails.removeAll()
                    selectedThumbnailID = nil
                    purgeStagedTempFiles()
                }
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
            // Audio recorder sheet
            .sheet(isPresented: $showAudioRecorder) {
                AudioRecorderView { url in
                    stageAudioURL(url)
                    showAudioRecorder = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            // Video recorder fullScreenCover replacement
            .fullScreenCover(isPresented: $showVideoRecorder) {
                NavigationStack {
                    VideoRecorderView { url in
                        stageVideoURL(url)
                        showVideoRecorder = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showVideoRecorder = false }
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { image in
                    stageImage(image)
                }
            }
            .sheet(isPresented: $showVideoPlayer, onDismiss: {
                videoPlayerItem?.pause()
                videoPlayerItem = nil
            }) {
                if let player = videoPlayerItem {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                        .ignoresSafeArea()
                } else {
                    Text("Unable to play video")
                        .padding()
                }
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
            .sheet(isPresented: $isTrimPresented, onDismiss: { trimItem = nil }) {
                if let item = trimItem, let url = surrogateURL(for: item) {
                    MediaTrimView(assetURL: url, mediaType: (item.kind == .audio ? .audio : .video),
                                  onCancel: {
                                      isTrimPresented = false
                                      trimItem = nil
                                  },
                                  onSaveAsNew: { newURL in
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
                                      }
                                      isTrimPresented = false
                                      trimItem = nil
                                  },
                                  onReplaceOriginal: { newURL in
                                      if let data = try? Data(contentsOf: newURL) {
                                          if item.kind == .audio {
                                              if let idx = stagedAudio.firstIndex(where: { $0.id == item.id }) {
                                                  stagedAudio[idx] = StagedAttachment(id: item.id, data: data, kind: .audio)
                                                  if let player = try? AVAudioPlayer(data: data) {
                                                      audioDurations[item.id] = max(0, Int(player.duration.rounded()))
                                                  }
                                              }
                                          } else {
                                              if let idx = stagedVideos.firstIndex(where: { $0.id == item.id }) {
                                                  stagedVideos[idx] = StagedAttachment(id: item.id, data: data, kind: .video)
                                                  if let thumb = generateVideoThumbnail(from: data, id: item.id) {
                                                      videoThumbnails[item.id] = thumb
                                                  }
                                              }
                                          }
                                          persistStagedAttachments()
                                      }
                                      isTrimPresented = false
                                      trimItem = nil
                                  })
                    .accessibilityLabel("Trim media")
                    .accessibilityHint("Edit start and end of the clip")
                } else {
                    Text("Unable to open trimmer").padding()
                }
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
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: Theme.Spacing.m) {
                Button(isRunning ? "Pause" : "Start") {
                    isRunning ? pause() : start()
                }
                .buttonStyle(.bordered)
                .tint(.clear)
                .frame(height: 44)
                .background(Theme.Colors.accent.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Reset") { reset() }
                    .buttonStyle(.bordered)
                    .tint(.clear)
                    .frame(height: 44)
                    .background((isRunning ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12)))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if isRunning {
                    Button("Finish") { finish() }
                        .buttonStyle(.bordered)
                        .tint(.clear)
                        .frame(height: 44)
                        .background((isRunning ? Color.red.opacity(0.18) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Button("Finish") { finish() }
                        .buttonStyle(.bordered)
                        .tint(.clear)
                        .frame(height: 44)
                        .background((isRunning ? Color.red.opacity(0.18) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        clearPersistedStagedAttachments()
        clearPersistedTasks()
        resetUIOnly()
    }

    private func finish() {
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

        case stagedAudio = "PracticeTimer.stagedAudio"
        case stagedVideo = "PracticeTimer.stagedVideo"
        case stagedImages = "PracticeTimer.stagedImages"
        case audioTitles = "PracticeTimer.audioTitles"
        case audioAutoTitles = "PracticeTimer.audioAutoTitles"
        case audioDurations = "PracticeTimer.audioDurations"
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
        
        // Restore staged attachments and related metadata
        if let audArray = d.array(forKey: TimerDefaultsKey.stagedAudio.rawValue) as? [Data] {
            // Each Data blob is a serialized StagedAttachment with id + kind + data; fall back to treating as raw data list if decoding fails
            var rebuilt: [StagedAttachment] = []
            for blob in audArray {
                if let obj = try? JSONDecoder().decode(SerializedAttachment.self, from: blob) {
                    rebuilt.append(StagedAttachment(id: obj.id, data: obj.data, kind: .audio))
                } else {
                    // Back-compat: generate ids for raw data entries
                    rebuilt.append(StagedAttachment(id: UUID(), data: blob, kind: .audio))
                }
            }
            self.stagedAudio = rebuilt
        }
        if let vidArray = d.array(forKey: TimerDefaultsKey.stagedVideo.rawValue) as? [Data] {
            var rebuilt: [StagedAttachment] = []
            for blob in vidArray {
                if let obj = try? JSONDecoder().decode(SerializedAttachment.self, from: blob) {
                    rebuilt.append(StagedAttachment(id: obj.id, data: obj.data, kind: .video))
                    if let thumb = generateVideoThumbnail(from: obj.data, id: obj.id) {
                        self.videoThumbnails[obj.id] = thumb
                    }
                } else {
                    let id = UUID()
                    rebuilt.append(StagedAttachment(id: id, data: blob, kind: .video))
                    if let thumb = generateVideoThumbnail(from: blob, id: id) {
                        self.videoThumbnails[id] = thumb
                    }
                }
            }
            self.stagedVideos = rebuilt
        }
        if let imgArray = d.array(forKey: TimerDefaultsKey.stagedImages.rawValue) as? [Data] {
            var rebuilt: [StagedAttachment] = []
            for blob in imgArray {
                if let obj = try? JSONDecoder().decode(SerializedAttachment.self, from: blob) {
                    rebuilt.append(StagedAttachment(id: obj.id, data: obj.data, kind: .image))
                } else {
                    rebuilt.append(StagedAttachment(id: UUID(), data: blob, kind: .image))
                }
            }
            self.stagedImages = rebuilt
        }
        if let titlesData = d.data(forKey: TimerDefaultsKey.audioTitles.rawValue),
           let titles = try? JSONDecoder().decode([UUID:String].self, from: titlesData) {
            self.audioTitles = titles
        }
        if let autoTitlesData = d.data(forKey: TimerDefaultsKey.audioAutoTitles.rawValue),
           let autos = try? JSONDecoder().decode([UUID:String].self, from: autoTitlesData) {
            self.audioAutoTitles = autos
        }
        if let durationsData = d.data(forKey: TimerDefaultsKey.audioDurations.rawValue),
           let durs = try? JSONDecoder().decode([UUID:Int].self, from: durationsData) {
            self.audioDurations = durs
        }
        if let selIDStr = d.string(forKey: TimerDefaultsKey.selectedThumbnailID.rawValue), let selID = UUID(uuidString: selIDStr) {
            self.selectedThumbnailID = selID
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

    private func clearPersistedTasks() {
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
    private struct SerializedAttachment: Codable {
        let id: UUID
        let data: Data
    }

    private func persistStagedAttachments() {
        let d = UserDefaults.standard
        // Encode attachments with stable IDs
        let enc = JSONEncoder()
        let audioPayload: [Data] = stagedAudio.compactMap { att in
            try? enc.encode(SerializedAttachment(id: att.id, data: att.data))
        }
        let videoPayload: [Data] = stagedVideos.compactMap { att in
            try? enc.encode(SerializedAttachment(id: att.id, data: att.data))
        }
        let imagePayload: [Data] = stagedImages.compactMap { att in
            try? enc.encode(SerializedAttachment(id: att.id, data: att.data))
        }
        d.set(audioPayload, forKey: TimerDefaultsKey.stagedAudio.rawValue)
        d.set(videoPayload, forKey: TimerDefaultsKey.stagedVideo.rawValue)
        d.set(imagePayload, forKey: TimerDefaultsKey.stagedImages.rawValue)
        // Encode dictionaries keyed by UUID
        if let titles = try? JSONEncoder().encode(audioTitles) {
            d.set(titles, forKey: TimerDefaultsKey.audioTitles.rawValue)
        }
        if let autos = try? JSONEncoder().encode(audioAutoTitles) {
            d.set(autos, forKey: TimerDefaultsKey.audioAutoTitles.rawValue)
        }
        if let durs = try? JSONEncoder().encode(audioDurations) {
            d.set(durs, forKey: TimerDefaultsKey.audioDurations.rawValue)
        }
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
        // Persist snapshot so timer resume remains consistent
        persistStagedAttachments()
    }

    private func clearPersistedStagedAttachments() {
        let d = UserDefaults.standard
        d.removeObject(forKey: TimerDefaultsKey.stagedAudio.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.stagedVideo.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.stagedImages.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.audioTitles.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.audioAutoTitles.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.audioDurations.rawValue)
        d.removeObject(forKey: TimerDefaultsKey.selectedThumbnailID.rawValue)
    }

    // MARK: - Audio attachment helpers

    private func stageAudioURL(_ url: URL) {
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

            // Compute duration from audio data
            var durationSeconds: Int = 0
            if let player = try? AVAudioPlayer(data: data) {
                durationSeconds = max(0, Int(player.duration.rounded()))
            }
            audioDurations[id] = durationSeconds

            stagedAudio.append(StagedAttachment(id: id, data: data, kind: .audio))
            persistStagedAttachments()

            // Double-write to staging store
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("m4a")
            try? data.write(to: tmp, options: .atomic)
            Task { _ = try? await StagingStore.saveNew(from: tmp, kind: .audio, suggestedName: title, duration: Double(durationSeconds), poster: nil) }
        } catch {
            print("Failed to stage audio: \(error)")
        }
    }

    private func stageVideoURL(_ url: URL) {
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
            Task { _ = try? await StagingStore.saveNew(from: tmp, kind: .video, suggestedName: id.uuidString, duration: duration.isFinite ? duration : nil, poster: posterURL) }
        } catch {
            print("Failed to stage video: \(error)")
        }
    }

    // Prepare and present a video player for a given staged video ID
    private func playVideo(_ id: UUID) {
        guard let att = stagedVideos.first(where: { $0.id == id }) else { return }
        // Write data to a temp file for AVPlayer
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("mov")
        do {
            try att.data.write(to: url, options: .atomic)
            videoPlayerItem = AVPlayer(url: url)
            showVideoPlayer = true
        } catch {
            print("Failed to prepare video for playback: \(error)")
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

    private func togglePlay(_ id: UUID) {
        if showAudioRecorder {
            return
        }
        if currentlyPlayingID == id {
            // Toggle play/pause for the same item and keep the selection so the icon flips reliably
            if let p = audioPlayer {
                if p.isPlaying {
                    p.pause()
                    isAudioPlaying = false
                    // Keep currentlyPlayingID so UI shows the item as selected (pause icon becomes play on next render)
                    // No change needed to currentlyPlayingID here
                } else {
                    // Attempt to resume
                    p.play()
                    isAudioPlaying = p.isPlaying
                    if !p.isPlaying {
                        // Resume failed; clear selection to avoid stuck icon
                        currentlyPlayingID = nil
                        isAudioPlaying = false
                    }
                }
            } else {
                // Player is nil; clear selection so the button becomes actionable again
                currentlyPlayingID = nil
                isAudioPlaying = false
            }
            return
        }
        // Stop any existing playback first (single-player policy)
        if audioPlayer?.isPlaying == true || currentlyPlayingID != nil {
            audioPlayer?.stop()
            audioPlayer = nil
            currentlyPlayingID = nil
            isAudioPlaying = false
        }
        guard let item = stagedAudio.first(where: { $0.id == id }) else { return }
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("m4a")
            try? item.data.write(to: tmp, options: .atomic)
            audioPlayer = try AVAudioPlayer(contentsOf: tmp)
            let delegate = AudioPlayerDelegateBridge(onFinish: {
                DispatchQueue.main.async {
                    if currentlyPlayingID == id {
                        currentlyPlayingID = nil
                        isAudioPlaying = false
                    }
                }
            })
            audioPlayer?.delegate = delegate
            audioPlayerDelegate = delegate // retain delegate so callbacks fire
            installAudioObserversIfNeeded()
            audioPlayer?.play()
            isAudioPlaying = (audioPlayer?.isPlaying == true)
            currentlyPlayingID = id
        } catch {
            print("Playback error: \(error)")
        }
    }

    private func deleteAudio(_ id: UUID) {
        if currentlyPlayingID == id {
            audioPlayer?.stop()
            audioPlayer = nil
            currentlyPlayingID = nil
            isAudioPlaying = false
        }
        // Remove surrogate temp file best-effort
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: tmp)
        stagedAudio.removeAll { $0.id == id }
        audioTitles.removeValue(forKey: id)
        audioAutoTitles.removeValue(forKey: id)
        audioDurations.removeValue(forKey: id)
        persistStagedAttachments()
        // Mirror delete to staging store
        if let ref = StagingStore.list().first(where: { $0.id == id }) {
            StagingStore.remove(ref)
        }
    }

    private func stopAttachmentPlayback() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
        }
        audioPlayer = nil
        isAudioPlaying = false
        currentlyPlayingID = nil
    }

    private func installAudioObserversIfNeeded() {
        guard !audioObserversInstalled else { return }
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            handleTimerAudioInterruption(note)
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            handleTimerAudioRouteChange(note)
        }
        #if canImport(UIKit)
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            if audioPlayer?.isPlaying == true {
                wasPlayingBeforeInterruption_timer = true
                audioPlayer?.pause()
                isAudioPlaying = false
                // do not clear currentlyPlayingID so UI shows paused state
            }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            if wasPlayingBeforeInterruption_timer, audioPlayer != nil {
                audioPlayer?.play()
                isAudioPlaying = true
            } else if audioPlayer == nil {
                // Player deallocated or invalid — reset UI so the button toggles work
                currentlyPlayingID = nil
                isAudioPlaying = false
            }
            wasPlayingBeforeInterruption_timer = false
        }
        #endif
        audioObserversInstalled = true
    }

    private func removeAudioObserversIfNeeded() {
        guard audioObserversInstalled else { return }
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        nc.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        #if canImport(UIKit)
        nc.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        nc.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
        audioObserversInstalled = false
    }

    private func handleTimerAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            if audioPlayer?.isPlaying == true {
                wasPlayingBeforeInterruption_timer = true
                audioPlayer?.pause()
                isAudioPlaying = false
                // Keep currentlyPlayingID set so UI shows paused state
            }
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), wasPlayingBeforeInterruption_timer, audioPlayer != nil {
                // Try to resume playback
                audioPlayer?.play()
                isAudioPlaying = true
            } else {
                // If we can't resume, clear stuck UI by resetting currentlyPlayingID
                wasPlayingBeforeInterruption_timer = false
                if audioPlayer == nil || audioPlayer?.url == nil {
                    currentlyPlayingID = nil
                    isAudioPlaying = false
                }
            }
            wasPlayingBeforeInterruption_timer = false
        @unknown default:
            break
        }
    }

    private func handleTimerAudioRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        switch reason {
        case .oldDeviceUnavailable:
            if audioPlayer?.isPlaying == true {
                wasPlayingBeforeInterruption_timer = true
                audioPlayer?.pause()
                isAudioPlaying = false
            }
        default:
            break
        }
        // If the route change invalidated the player, clear UI selection to prevent a stuck button
        if audioPlayer == nil {
            currentlyPlayingID = nil
            isAudioPlaying = false
        }
    }

    // MARK: - Image attachment helpers (camera)
    private func stageImage(_ image: UIImage) {
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
    private func surrogateURL(for att: StagedAttachment) -> URL? {
        let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
        return FileManager.default.temporaryDirectory.appendingPathComponent(att.id.uuidString).appendingPathExtension(ext)
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

private final class AudioPlayerDelegateBridge: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}


