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
    }
    private func toggleDone(_ id: UUID) {
        if let idx = taskLines.firstIndex(where: { $0.id == id }) {
            taskLines[idx].isDone.toggle()
        }
    }
    private func deleteLine(_ id: UUID) {
        taskLines.removeAll { $0.id == id }
        autoTaskTexts.removeValue(forKey: id)
        if taskLines.isEmpty { showTasksPad = false }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    selectorsCard()
                    timerCard()

                    // ---------- Recording helpers (moved below timer) ----------
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            Button {
                                stopAttachmentPlayback()
                                showAudioRecorder = true
                            } label: {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .frame(width: 44, height: 44)
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
                                        .font(.system(size: 22, weight: .semibold))
                                        .frame(width: 44, height: 44)
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
                                    .font(.system(size: 22, weight: .semibold))
                                    .frame(width: 44, height: 44)
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
                                Text("Notes / Tasks")
                                    .sectionHeader()
                                    .frame(maxWidth: .infinity, alignment: .center)

                                ForEach($taskLines) { $line in
                                    HStack(spacing: 8) {
                                        Button { line.isDone.toggle() } label: {
                                            Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
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
                                            }
                                            .onChange(of: focusedTaskID) { _, newFocus in
                                                if newFocus == line.id {
                                                    // If current equals auto text, clear to start fresh
                                                    if let auto = autoTaskTexts[line.id], line.text == auto {
                                                        line.text = ""
                                                    }
                                                }
                                            }

                                        Spacer(minLength: 8)

                                        Button(role: .destructive) { deleteLine(line.id) } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Button(action: { addEmptyTaskLine() }) {
                                    HStack { Image(systemName: "plus"); Text("Add line") }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        } else {
                            Button(action: {
                                showTasksPad = true
                                loadPracticeDefaultsIfNeeded()
                                loadDefaultTasksIfNeeded()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                    Text("Notes / Tasks")
                                }
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

                                    Button(role: .destructive, action: { deleteAudio(att.id) }) {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
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
                                            // Delete button remains in the top-right
                                            VStack(spacing: 6) {
                                                Button {
                                                    // Remove surrogate temp file best-effort
                                                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(att.id.uuidString).appendingPathExtension("mov")
                                                    try? FileManager.default.removeItem(at: tmp)
                                                    stagedVideos.removeAll { $0.id == att.id }
                                                    videoThumbnails.removeValue(forKey: att.id)
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
                    removeAudioObserversIfNeeded()
                    purgeStagedTempFiles()
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
                    notesPrefill: composeCompletedTasksNotesString(),
                    prefillAttachments: (stagedImages + stagedAudio + stagedVideos),
                    prefillAttachmentNames: audioTitles,
                    onSaved: {
                        didSaveFromReview = true
                        clearPersistedTimer()
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

