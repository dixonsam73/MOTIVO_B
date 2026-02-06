

//  PostRecordDetailsView_20251004c.swift
//  MOTIVO
//
//  Visual polish + Instrument row chevron fix
//  Silent if one instrument, chevron row if multiple.

// CHANGE-ID: 20260130_164830_PRDV_ShareDebug
// SCOPE: PRDV — Add definitive debug logging for Share toggle (isPublic) at toggle-change, draft hydration, and save-tap to identify where it flips to true.
import SwiftUI
import CoreData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit


// MARK: - Attachment Viewer Request (Step 1)
// Atomic presentation payload for AttachmentViewerView (used starting Step 2).
// Defined here (PRDV-only scope) to keep this step compiling without touching other files.
private struct AttachmentViewerRequest: Identifiable {
    enum Mode {
        case visual   // images + videos
        case audio    // audio clips only
    }

    let id = UUID()
    let mode: Mode
    let startIndex: Int

    // Pass-through arrays; actual usage will filter by mode when presented (Step 2+).
    let imageURLs: [URL]
    let videoURLs: [URL]
    let audioURLs: [URL]
}


struct PostRecordDetailsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme

    @Binding var isPresented: Bool
    private let prefillTimestamp: Date
    private let prefillDurationSeconds: Int

    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var title: String = ""
    @State private var timestamp: Date
    @State private var durationSeconds: Int
    @State private var activity: SessionActivityType = .practice
    @State private var userActivities: [UserActivity] = []
    @State private var activityChoice: String = "core:0"
    @State private var selectedCustomName: String = ""
    @State private var isPublic: Bool = true
    @State private var mood: Int = 5
    @State private var effort: Int = 5
    @State private var notes: String = ""
    @State private var activityDetail: String = ""
    @State private var lastAutoActivityDetail: String = ""
    @State private var userEditedActivityDetail: Bool = false

    @State private var isTitleEdited = false
    @State private var initialAutoTitle = ""
    
    @State private var areNotesPrivate: Bool = false

    @State private var attachmentTitlesRefreshTick: Int = 0


    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var showActivityPicker = false
    @State private var showInstrumentPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0
    @State private var tempActivity: SessionActivityType = .practice

    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var selectedThumbnailID: UUID? = nil
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraDeniedAlert = false

    @State private var isShowingAttachmentViewer: Bool = false
    @State private var viewerStartIndex: Int = 0

    // Step 1: New atomic request state (unused until Step 2).
    @State private var viewerRequest: AttachmentViewerRequest? = nil

    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

    private let draftNotesKey = "PostRecordDetailsView.draft.notes"
    private let draftFocusKey = "PostRecordDetailsView.draft.focusDot"
    private let draftIsPublicKey = "PostRecordDetailsView.draft.isPublic_v1"

    private let sessionIDKey = "PracticeTimer.currentSessionID"
    private let lastSeenSessionIDKey = "PostRecordDetailsView.lastSeenSessionID"
    private let sessionStartTimestampKey = "PracticeTimer.currentSessionStartTimestamp"

    private func currentSessionID() -> String? {
        UserDefaults.standard.string(forKey: sessionIDKey)
    }

    private func loadDraftIsPublicIfNeeded() {
        // Default is ON (true). If user flipped OFF and the view was recreated before Save,
        // rehydrate from draft storage to avoid snapping back to true.
        if UserDefaults.standard.object(forKey: draftIsPublicKey) != nil {
            isPublic = UserDefaults.standard.bool(forKey: draftIsPublicKey)
        } else {
            // Keep existing default (true) unless a future caller explicitly sets it.
        }
    }

    private func persistDraftIsPublic() {
        UserDefaults.standard.set(isPublic, forKey: draftIsPublicKey)
    }

    private func clearDraftIsPublic() {
        UserDefaults.standard.removeObject(forKey: draftIsPublicKey)
    }


    // v7.9E — State circles (neutral greys)
    private let stateOpacities: [Double] = [0.80, 0.60, 0.30, 0.05] // 0=Searching (dark) → 3=Breakthrough (clear)

    // v7.9E — 12-dot gradient strip (dark → light) with drag selection
    private let stateDotsCount: Int = 12

    @State private var selectedDotIndex: Int? = nil
    @State private var hoverDotIndex: Int? = nil        // transient dot under finger during drag
    @State private var lastHapticZone: Int? = nil       // throttle haptic to zone changes

    // Drag refinements
    @State private var dragX: CGFloat? = nil          // live finger x within the strip
    @State private var lastHapticDot: Int? = nil      // fire haptic when this changes

    /// DARK ➜ LIGHT across the row. On dark themes this reads as “clearer toward the right”.
    private func opacityForDot(_ i: Int) -> Double {
        // 0 = darkest (high opacity), 11 = lightest (low opacity)
        let start: Double = 0.95   // darker (more opaque) on the left
        let end:   Double = 0.15   // lighter (less opaque) on the right (slightly lighter than before)
        guard stateDotsCount > 1 else { return start }
        let t = Double(i) / Double(stateDotsCount - 1)
        return start + (end - start) * t
    }

    // ---- Privacy cache & helpers (inside the view struct) ----
    @State private var privacyMap: [String: Bool] = [:]

    private func privacyKey(id: UUID?, url: URL?) -> String? {
        if let id { return "id://\(id.uuidString)" }
        if let url { return url.absoluteString }
        return nil
    }

    private func loadPrivacyMap() {
        privacyMap = (UserDefaults.standard.dictionary(forKey: AttachmentPrivacy.mapKey) as? [String: Bool]) ?? [:]
    }

    private func isPrivate(id: UUID?, url: URL?) -> Bool {
        if let key = privacyKey(id: id, url: url) {
            if let v = privacyMap[key] { return v }
            return AttachmentPrivacy.isPrivate(id: id, url: url)
        }
        return true
    }

    private func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        // Update cache immediately for responsive UI
        privacyMap[key] = value
        // Persist via shared utility (also posts didChange)
        AttachmentPrivacy.setPrivate(id: id, url: url, value)
    }

    // --- PATCH 8G3A: migrate staged privacy → final attachment keys using AttachmentPrivacy (file-backed) ---
    // SEARCH-ANCHOR: private func migratePrivacy(fromStagedID stagedID: UUID, stagedURL: URL?, toNewID newID: UUID?, newURL: URL?)
    private func migratePrivacy(fromStagedID stagedID: UUID, stagedURL: URL?, toNewID newID: UUID?, newURL: URL?) {
        // AttachmentPrivacy is file-backed; read staged value from the real source of truth.
        // Default is private=true, so only explicit “included” (private=false) needs to be preserved for Phase 3.
        let stagedIsPrivate = AttachmentPrivacy.isPrivate(id: stagedID, url: stagedURL)

        // Write the staged value onto the final keys so backend publish selection sees it.
        if newID != nil || newURL != nil {
            AttachmentPrivacy.setPrivate(id: newID, url: newURL, stagedIsPrivate)
        }


        // Keep PRDV local cache in sync for any immediate UI reads in this view.
        privacyMap = AttachmentPrivacy.currentMap()
    }
    // ---- end privacy helpers ----

    // Best-effort purge for surrogate temp files created for staged items
    private func purgeStagedTempFiles() {
        let fm = FileManager.default
        for att in stagedAttachments {
            let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(att.id.uuidString)
                .appendingPathExtension(ext)
            try? fm.removeItem(at: url)
        }
    }

    private var totalStagedBytes: Int {
        stagedAttachments.reduce(0) { $0 + $1.data.count }
    }
    private var stagedSizeWarning: String? {
        let limit = 100 * 1024 * 1024 // 100 MB
        return totalStagedBytes > limit ? "Large staging size (~\(totalStagedBytes / (1024*1024)) MB). Consider saving or removing some items." : nil
    }

    var onSaved: (() -> Void)?
    var onCancel: () -> Void = {}

    private let prefillAttachments: [StagedAttachment]?
    private let prefillAttachmentNames: [UUID: String]?

    init(
        isPresented: Binding<Bool>,
        timestamp: Date? = nil,
        durationSeconds: Int? = nil,
        instrument: Instrument? = nil,
        activityTypeRaw: Int16? = nil,
        activityDetailPrefill: String? = nil,
        notesPrefill: String? = nil,
        prefillAttachments: [StagedAttachment]? = nil,
        prefillAttachmentNames: [UUID: String]? = nil,
        onSaved: (() -> Void)? = nil,
        onCancel: @escaping () -> Void = {}
    ) {
        self._isPresented = isPresented
        // Prefer the actual session start time from PracticeTimerView if available
        let ud = UserDefaults.standard
        var resolvedStart = timestamp
        if resolvedStart == nil {
            if let sessionID = ud.string(forKey: sessionIDKey) {
                // If a session is active, try to load its recorded start timestamp
                let key = "\(sessionStartTimestampKey).\(sessionID)"
                if let startInterval = ud.object(forKey: key) as? TimeInterval {
                    resolvedStart = Date(timeIntervalSince1970: startInterval)
                } else if let startInterval = ud.object(forKey: sessionStartTimestampKey) as? TimeInterval {
                    // Back-compat: support a global start timestamp key if used by older builds
                    resolvedStart = Date(timeIntervalSince1970: startInterval)
                }
            } else if let startInterval = ud.object(forKey: sessionStartTimestampKey) as? TimeInterval {
                // Fallback if no session ID is available but a start timestamp exists
                resolvedStart = Date(timeIntervalSince1970: startInterval)
            }
        }
        self.prefillTimestamp = resolvedStart ?? Date()
        self.prefillDurationSeconds = max(0, durationSeconds ?? 0)
        self._timestamp = State(initialValue: self.prefillTimestamp)
        self._durationSeconds = State(initialValue: self.prefillDurationSeconds)
        self._instrument = State(initialValue: instrument)
        if let prefill = activityDetailPrefill, !prefill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self._selectedCustomName = State(initialValue: prefill)
            self._activityDetail = State(initialValue: "")
            self._activity = State(initialValue: .practice)
            self._activityChoice = State(initialValue: "custom:\(prefill)")
        }
        if let raw = activityTypeRaw { self._activity = State(initialValue: SessionActivityType(rawValue: raw) ?? .practice) }
        self._notes = State(initialValue: notesPrefill ?? "")
        self.prefillAttachments = prefillAttachments
        self.prefillAttachmentNames = prefillAttachmentNames
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {

                    // ---------- Instrument ----------
                    if hasNoInstruments {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("No instruments found").sectionHeader()
                            Text("Add an instrument in your Profile to save this session.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .cardSurface()
                    } else if hasMultipleInstruments {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Instrument").sectionHeader()
                            Button {
                                showInstrumentPicker = true
                            } label: {
                                HStack {
                                    Text(instrument?.name ?? "Select instrument…")
                                        .font(Theme.Text.body)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .padding(6)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                        .cardSurface()
                    }
                    // Silent if exactly one instrument

                    // ---------- Activity ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Activity").sectionHeader()
                        Button {
                            tempActivity = activity
                            showActivityPicker = true
                        } label: {
                            HStack {
                                let display = selectedCustomName.isEmpty ? activity.label : selectedCustomName
                                Text(display)
                                    .font(Theme.Text.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .cardSurface()

                    // ---------- Activity description ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Description").sectionHeader()
                        TextField("Activity description", text: $activityDetail, axis: .vertical)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.never)
                            .font(Theme.Text.body)
                    }
                    .cardSurface()

                    // ---------- Start time ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Start Time").sectionHeader()
                        Button {
                            tempDate = timestamp
                            showStartPicker = true
                        } label: {
                            HStack {
                                Text(formattedDate(timestamp))
                                    .font(Theme.Text.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .cardSurface()

                    // ---------- Duration ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Duration").sectionHeader()
                        Button {
                            let hm = secondsToHM(durationSeconds)
                            tempHours = hm.0
                            tempMinutes = hm.1
                            showDurationPicker = true
                        } label: {
                            HStack {
                                Text(formattedDuration(durationSeconds))
                                    .font(Theme.Text.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if durationSeconds == 0 {
                            Text("Duration must be greater than 0")
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                    .cardSurface()

                    // ---------- Visibility ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Share with followers").sectionHeader()
                        Toggle("On", isOn: $isPublic)
                            .font(Theme.Text.body)
                    }
                    .cardSurface()

                    // ---------- Notes ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Notes").sectionHeader()
                            Spacer()
                            Button(action: {
                                areNotesPrivate.toggle()
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }) {
                                Image(systemName: areNotesPrivate ? "eye.slash" : "eye")
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(areNotesPrivate ? "Make notes visible to others" : "Make notes private")
                        }
                        if areNotesPrivate {
                            Text("Only you will see these notes.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
                            .font(Theme.Text.body)
                    }
                    .cardSurface()

                    stateStripCard

                    attachmentsSection
                        .cardSurface(padding: Theme.Spacing.m)

                    addAttachmentsControlsSection
                        .cardSurface(padding: Theme.Spacing.m)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Session Review").font(Theme.Text.pageTitle)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        // Intentional discard: purge any currently staged items for this review
                        let discardIDs: [UUID] = stagedAttachments.map { $0.id }
                        if !discardIDs.isEmpty {
                            StagingStore.removeMany(ids: discardIDs)
                        }
                        // Also purge any surrogate temp files created for staged items
                        purgeStagedTempFiles()
                        onCancel()
                        // Update last seen session ID on cancel to prevent re-clearing within same session
                        if let cur = currentSessionID() { UserDefaults.standard.set(cur, forKey: lastSeenSessionIDKey) }
                        isPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to Timer")
                }


                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        let visibility = isPublic
                        saveToCoreData(visibility: visibility)
                        DispatchQueue.main.async { withAnimation(.none) { isPresented = false } }
                    }) {
                        Text("Save")
                            .font(Theme.Text.body)
                    }
                    .disabled(durationSeconds == 0 || instrument == nil)
                }
            }
            .onAppear {
                loadDraftIsPublicIfNeeded()
            }
            .onChange(of: isPublic) { _ in
                persistDraftIsPublic()
            }
            .fullScreenCover(item: $viewerRequest) { request in
                let imageURLs = (request.mode == .visual) ? request.imageURLs : []
                let videoURLs = (request.mode == .visual) ? request.videoURLs : []
                let audioURLs = (request.mode == .audio) ? request.audioURLs : []

                let combined: [URL] = {
                    switch request.mode {
                    case .visual:
                        return imageURLs + videoURLs
                    case .audio:
                        return audioURLs
                    }
                }()

                let startIndex = min(max(request.startIndex, 0), max(combined.count - 1, 0))

                let _ = attachmentTitlesRefreshTick
                                let audioNamesKey = "stagedAudioNames_temp"
                let audioNamesDict = (UserDefaults.standard.dictionary(forKey: audioNamesKey) as? [String: String]) ?? [:]

                let videoTitlesKey = "stagedVideoTitles_temp"
                let videoTitlesDict = (UserDefaults.standard.dictionary(forKey: videoTitlesKey) as? [String: String]) ?? [:]

AttachmentViewerView(
                    imageURLs: imageURLs,
                    startIndex: startIndex,
                    themeBackground: Color(.systemBackground),
                    videoURLs: videoURLs,
                    audioURLs: audioURLs,
onDelete: { url in
    // Map surrogate URL back to staged attachment by matching staged id in the basename
    let stem = url.deletingPathExtension().lastPathComponent
    if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
        let removed = stagedAttachments[idx]
        // Use existing removal path
        removeStagedAttachment(removed)
        // If this was the current thumbnail, reassign or clear using existing logic
        if selectedThumbnailID == removed.id {
            if let nextImage = stagedAttachments.first(where: { $0.kind == .image }) {
                selectedThumbnailID = nextImage.id
            } else {
                selectedThumbnailID = nil
            }
        }
        // Dismiss the viewer cleanly
        viewerRequest = nil
    }
},
                    titleForURL: { url, kind in
                        let stem = url.deletingPathExtension().lastPathComponent
                        guard let id = UUID(uuidString: stem) else { return nil }

                        switch kind {
                        case .audio:
                            if let raw = audioNamesDict[id.uuidString] {
                                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                return t.isEmpty ? "Audio clip" : t
                            }
                            return "Audio clip"

                        case .video:
                            if let raw = videoTitlesDict[id.uuidString] {
                                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                return t.isEmpty ? nil : t
                            }
                            return nil

                        case .image, .file:
                            return nil
                        }
                    },
                    onRename: { url, newTitle, kind in
                        let stem = url.deletingPathExtension().lastPathComponent
                        guard let id = UUID(uuidString: stem) else { return }

                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

                        switch kind {
                        case .audio:
                            var dict = (UserDefaults.standard.dictionary(forKey: audioNamesKey) as? [String: String]) ?? [:]
                            if trimmed.isEmpty { dict.removeValue(forKey: id.uuidString) }
                            else { dict[id.uuidString] = trimmed }
                            UserDefaults.standard.set(dict, forKey: audioNamesKey)
                            attachmentTitlesRefreshTick &+= 1

                        case .video:
                            var dict = (UserDefaults.standard.dictionary(forKey: videoTitlesKey) as? [String: String]) ?? [:]
                            if trimmed.isEmpty { dict.removeValue(forKey: id.uuidString) }
                            else { dict[id.uuidString] = trimmed }
                            UserDefaults.standard.set(dict, forKey: videoTitlesKey)
                            attachmentTitlesRefreshTick &+= 1

                        case .image, .file:
                            break
                        }
                    },
                    onFavourite: { url in
                        let stem = url.deletingPathExtension().lastPathComponent
                        if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
                            toggleThumbnail(att)
                        }
                    },
                    isFavourite: { url in
                        let stem = url.deletingPathExtension().lastPathComponent
                        if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
                            return selectedThumbnailID == att.id
                        }
                        return false
                    },
                    onTogglePrivacy: { url in
    // Toggle "shown in post" state (default private) using ID-first key.
    let stem = url.deletingPathExtension().lastPathComponent
    if let staged = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
        let priv = isPrivate(id: staged.id, url: url)
        setPrivate(id: staged.id, url: url, !priv)
        return
    }
    // Fallback: if the URL stem is a UUID but we couldn't find it in stagedAttachments (should be rare), still toggle.
    if let id = UUID(uuidString: stem) {
        let priv = isPrivate(id: id, url: url)
        setPrivate(id: id, url: url, !priv)
    }
},
isPrivate: { url in
    let stem = url.deletingPathExtension().lastPathComponent
    if let staged = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
        return isPrivate(id: staged.id, url: url)
    }
    // Default private if unknown.
    if let id = UUID(uuidString: stem) {
        return isPrivate(id: id, url: url)
    }
    return true
},

                    onReplaceAttachment: { originalURL, newURL, kind in
                        replaceStagedAttachment(originalURL: originalURL, with: newURL, kind: kind)
                    },
                    onSaveAsNewAttachment: { newURL, kind in
                        // Insert new item after the current one in its section
                        insertNewStagedAttachment(after: combined[min(max(startIndex,0), max(combined.count-1,0))], newURL: newURL, kind: kind)
                    },
                    canShare: false
                )
            }
            // Sheets
            .sheet(isPresented: $showInstrumentPicker) { instrumentPicker }
            .sheet(isPresented: $showActivityPicker) { activityPickerPinned }
            .sheet(isPresented: $showStartPicker) { startPicker }
            .sheet(isPresented: $showDurationPicker) { durationPicker }
            .photosPicker(isPresented: $showPhotoPicker,
                        selection: $photoPickerItem,
                        matching: .any(of: [.images, .videos]))
            .task(id: photoPickerItem) {
                guard let item = photoPickerItem else { return }
                if let contentType = item.supportedContentTypes.first {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        if contentType.conforms(to: .image) {
                            stageData(data, kind: .image)
                        } else if contentType.conforms(to: .movie) {
                            stageData(data, kind: .video)
                        } else {
                            stageData(data, kind: .file)
                        }
                    }
                } else if let data = try? await item.loadTransferable(type: Data.self) {
                    stageData(data, kind: .file)
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: handleFileImport)
            .sheet(isPresented: $showCamera) { CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.8) { stageData(data, kind: .image) }
            } }
            .alert("Camera access denied",
                   isPresented: $showCameraDeniedAlert,
                   actions: {
                       Button("OK", role: .cancel) {}
                       Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                   },
                   message: { Text("Enable camera access in Settings → Privacy → Camera to take photos.") })
            .task {
                if let pre = prefillAttachments, !pre.isEmpty, stagedAttachments.isEmpty {
                    stagedAttachments.append(contentsOf: pre)
                    if let nameMap = prefillAttachmentNames {
                        // Store in a temporary map via UserDefaults for the lifetime of this view, keyed by staged id
                        let key = "stagedAudioNames_temp"
                        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
                        for att in pre {
                            if let title = nameMap[att.id], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                dict[att.id.uuidString] = title
                            }
                        }
                        UserDefaults.standard.set(dict, forKey: key)
                    }
                }

                // Clear Notes and Focus when entering from a fresh PracticeTimer session
                // Only clear if we don't already have a prefilled note (e.g., from PracticeTimerView)
                let ud = UserDefaults.standard
                let currentID = currentSessionID()
                let lastSeen = ud.string(forKey: lastSeenSessionIDKey)
                if currentID != nil && currentID != lastSeen {
                    // New session detected: clear persisted draft and local state,
                    // but only if the current notes are effectively empty so we don't clobber a prefill.
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        notes = ""
                        selectedDotIndex = nil
                        clearDraft()
                    }
                    ud.set(currentID, forKey: lastSeenSessionIDKey)
                }

                preselectFocusFromNotesIfNeeded()
                loadDraftIfAvailable()
                instruments = fetchInstruments()
                if instrument == nil {
                    if let primaryName = fetchPrimaryInstrumentName(),
                       let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                        instrument = match
                    } else if hasOneInstrument {
                        instrument = instruments.first
                    }
                }
                tempActivity = activity
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let auto = defaultTitle(for: instrument, activity: activity)
                    title = auto
                    initialAutoTitle = auto
                    isTitleEdited = false
                }
                if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let autoDesc = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
                    activityDetail = autoDesc
                    lastAutoActivityDetail = autoDesc
                    userEditedActivityDetail = false
                }
                loadUserActivities()
                syncActivityChoiceFromState()
                loadDraftIfAvailable()
            }
            .onChange(of: instrument) { _, _ in refreshAutoTitleIfNeeded() }
            .onChange(of: activity) { _, _ in maybeUpdateActivityDetailFromDefaults() }
            .onChange(of: activityDetail) { old, new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                userEditedActivityDetail = (!trimmed.isEmpty && trimmed != lastAutoActivityDetail)
            }
            .onChange(of: notes) { _, new in
                UserDefaults.standard.set(new, forKey: draftNotesKey)
            }
            .onChange(of: selectedDotIndex) { _, new in
                if let v = new {
                    UserDefaults.standard.set(v, forKey: draftFocusKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: draftFocusKey)
                }
            }
            .onAppear { loadPrivacyMap() }
            .onReceive(NotificationCenter.default.publisher(for: AttachmentPrivacy.didChangeNotification)) { _ in
                loadPrivacyMap()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                purgeStagedTempFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                clearDraft()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Do not clear drafts on background; preserve in-session state when user switches apps
            }
            .appBackground()
            .onDisappear {
                purgeStagedTempFiles()
                // Keep last seen session ID in sync on disappear (non-destructive)
                if let cur = currentSessionID() { UserDefaults.standard.set(cur, forKey: lastSeenSessionIDKey) }
            }
        }
    }

    // MARK: - Draft helpers

    private func loadDraftIfAvailable() {
        let ud = UserDefaults.standard
        if let draft = ud.string(forKey: draftNotesKey) {
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notes = draft
            }
        }
        if selectedDotIndex == nil, ud.object(forKey: draftFocusKey) != nil {
            let v = ud.integer(forKey: draftFocusKey)
            if (0...11).contains(v) {
                selectedDotIndex = v
            }
        }
    }

    private func clearDraft() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: draftNotesKey)
        ud.removeObject(forKey: draftFocusKey)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Attachments").sectionHeader()
            if !stagedAttachments.isEmpty {
                let nonAudio = stagedAttachments.filter { $0.kind != .audio }
                let audioOnly = stagedAttachments.filter { $0.kind == .audio }

                if !nonAudio.isEmpty {
                    let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(nonAudio) { att in
                            ZStack(alignment: .topTrailing) {
                                AttachmentThumbCell(
                                    att: att,
                                    isThumbnail: selectedThumbnailID == att.id,
                                    onMakeThumbnail: { toggleThumbnail(att) },
                                    onRemove: { removeStagedAttachment(att) },
                                    isPrivate: { id, url in
                                        return isPrivate(id: id, url: url)
                                    },
                                    setPrivate: { id, url, value in
                                        setPrivate(id: id, url: url, value)
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Step 3: Visual taps (images + videos) present via viewerRequest only.
                                    // Ordering matches the PRDV visual grid (non-audio attachments in stagedAttachments order).
                                    ensureSurrogateFilesExistForViewer()

                                    let visuals = stagedAttachments.filter { $0.kind != .audio && $0.kind != .file }

                                    let imageURLs: [URL] = visuals.compactMap { item in
                                        guard item.kind == .image else { return nil }
                                        return surrogateURL(for: item)
                                    }

                                    let videoURLs: [URL] = visuals.compactMap { item in
                                        guard item.kind == .video else { return nil }
                                        return surrogateURL(for: item)
                                    }

                                    let startIndex: Int = {
                                        switch att.kind {
                                        case .image:
                                            let idx = visuals.filter { $0.kind == .image }.firstIndex(where: { $0.id == att.id }) ?? 0
                                            return idx
                                        case .video:
                                            let idx = visuals.filter { $0.kind == .video }.firstIndex(where: { $0.id == att.id }) ?? 0
                                            return imageURLs.count + idx
                                        default:
                                            return 0
                                        }
                                    }()

                                    viewerRequest = AttachmentViewerRequest(
                                        mode: .visual,
                                        startIndex: startIndex,
                                        imageURLs: imageURLs,
                                        videoURLs: videoURLs,
                                        audioURLs: []
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, -Theme.Spacing.s)
                }

                if !audioOnly.isEmpty {
                    // Use the same temporary title map as PracticeTimerView (keyed by staged id UUID string)
                    let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(audioOnly) { att in
                            let rawDisplay = namesDict[att.id.uuidString] ?? ""
                            let trimmedDisplay = rawDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
                            let title = trimmedDisplay.isEmpty ? "Audio clip" : trimmedDisplay

                            let url = surrogateURL(for: att)
                            let durationText: String? = {
                                guard let url = url else { return nil }
                                let fm = FileManager.default
                                if !fm.fileExists(atPath: url.path) {
                                    try? att.data.write(to: url, options: .atomic)
                                }
                                let asset = AVURLAsset(url: url)
                                let seconds = CMTimeGetSeconds(asset.duration)
                                guard seconds.isFinite, seconds > 0 else { return nil }
                                return formatClipDuration(seconds)
                            }()

                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    ensureSurrogateFilesExistForViewer()

                                    let audioItems: [(UUID, URL)] = audioOnly.compactMap { item in
                                        guard let url = surrogateURL(for: item) else { return nil }
                                        return (item.id, url)
                                    }
                                    let audioURLs: [URL] = audioItems.map { $0.1 }
                                    let startIndex = audioItems.firstIndex(where: { $0.0 == att.id }) ?? 0

                                    viewerRequest = AttachmentViewerRequest(
                                        mode: .audio,
                                        startIndex: startIndex,
                                        imageURLs: [],
                                        videoURLs: [],
                                        audioURLs: audioURLs
                                    )
                                } label: {
                                    HStack(spacing: 8) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 16, weight: .semibold))
                                        .opacity(0.85)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title)
                                            .font(.footnote)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)

                                        if let durationText {
                                            Text(durationText)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    }
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Open audio clip \(title)")

                                Spacer(minLength: 8)

                                VStack(spacing: 6) {
                                    // Star (use audio clip as session thumbnail)
                                    Button {
                                        toggleThumbnail(att)
                                    } label: {
                                        Image(systemName: selectedThumbnailID == att.id ? "star.fill" : "star")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(selectedThumbnailID == att.id ? "Unset as thumbnail" : "Set as thumbnail")

                                    // Privacy toggle
                                    let privURL = url
                                    Button {
                                        let current = isPrivate(id: att.id, url: privURL)
                                        setPrivate(id: att.id, url: privURL, !current)
                                    } label: {
                                        let current = isPrivate(id: att.id, url: privURL)
                                        Image(systemName: "eye")
                                            .font(.system(size: 16, weight: .semibold))
                                            .opacity((current || selectedThumbnailID == att.id) ? 0 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isPrivate(id: att.id, url: privURL) ? "Mark attachment public" : "Mark attachment private")

                                    // Delete
                                    Button(role: .destructive) {
                                        removeStagedAttachment(att)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete attachment")
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let index = stagedIndexForAttachment(att)
                                if index >= 0 {
                                    viewerStartIndex = index
                                    ensureSurrogateFilesExistForViewer()
                                    isShowingAttachmentViewer = true
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if let warn = stagedSizeWarning {
                Text(warn)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.top, 4)
            }
        }
    }
    private var addAttachmentsControlsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: 32) {
                Button(action: { showPhotoPicker = true }) {
                    ZStack {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62)) // slate blue-grey
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.18))
                                    .frame(width: 64, height: 64)
                            )
                    }
                }
                .accessibilityLabel("Add photo or video from library")
                .contentShape(Circle())
                .buttonStyle(.plain)
                .tint(.accentColor)

                Button(action: { showFileImporter = true }) {
                    ZStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62)) // slate blue-grey
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.18))
                                    .frame(width: 64, height: 64)
                            )
                    }
                }
                .accessibilityLabel("Add file (PDF, score, etc.)")
                .contentShape(Circle())
                .buttonStyle(.plain)
                .tint(.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var stateStripCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Focus").sectionHeader()
            // Half-height horizontal strip of twelve neutral-grey circles with gradient fade
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let spacing: CGFloat = 8
                let count = stateDotsCount

                // compute diameter so dots + spacings fill available width; allow a bit larger
                let diameter = max(14, min(32, (totalWidth - spacing * CGFloat(count - 1)) / CGFloat(count)))
                let step = diameter + spacing

                let drag = DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Clamp within the actual occupied width of the dot strip so extremes are reachable
                        let totalWidthUsed = diameter * CGFloat(count) + spacing * CGFloat(count - 1)
                        let x = max(0, min(value.location.x, totalWidthUsed))

                        dragX = x

                        // Map x to nearest dot center across [0, totalWidthUsed]
                        let projected = (x / max(1, totalWidthUsed)) * CGFloat(count - 1)
                        let idx = Int(round(projected))
                        let clamped = max(0, min(count - 1, idx))

                        hoverDotIndex = clamped
                        selectedDotIndex = clamped  // single source of truth

                        // Per-dot haptic (not just per-zone)
                        if lastHapticDot != clamped {
                            lastHapticDot = clamped
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                        }
                    }
                    .onEnded { _ in
                        dragX = nil
                        hoverDotIndex = nil
                    }

                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        let isRinged = (i == selectedDotIndex)

                        // Proximity bloom (drag hover)
                        let hoverScale: CGFloat = {
                            guard let x = dragX else { return 1.0 }
                            let cx = CGFloat(i) * step + diameter * 0.5
                            let distance = abs(cx - x)
                            let proximity = max(0, 1 - (distance / (step * 1.5)))   // 0…1
                            return 1.0 + (0.24 * proximity)                          // up to +24%
                        }()

                        // NEW: persistent selected scale so chosen dot always stands out
                        let selectedBaseScale: CGFloat = isRinged ? 1.18 : 1.0       // +18% when selected

                        // Final scale = persistent selected scale × hover bloom
                        let finalScale = selectedBaseScale * hoverScale

                        Circle()
                            // Adaptive fill: black in light mode, white in dark mode, using centralized opacity ramp
                            .fill(FocusDotStyle.fillColor(index: i, total: count, colorScheme: colorScheme))
                            // Hairline outline on every dot for guaranteed contrast
                            .overlay(
                                Circle().stroke(FocusDotStyle.hairlineColor, lineWidth: FocusDotStyle.hairlineWidth)
                            )
                            // Adaptive ring for the selected index
                            .overlay(
                                Group {
                                    if isRinged {
                                        Circle().stroke(
                                            FocusDotStyle.ringColor(for: colorScheme),
                                            lineWidth: FocusDotStyle.ringWidth
                                        )
                                    }
                                }
                            )
                            .frame(width: diameter, height: diameter)
                            .scaleEffect(finalScale)
                            .animation(.easeOut(duration: 0.06), value: finalScale)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDotIndex = (selectedDotIndex == i) ? nil : i
                                #if canImport(UIKit)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                            }
                            .accessibilityLabel({
                                // Bucket labels for clarity
                                let bucket: String
                                switch i / 3 {
                                case 0: bucket = "Searching"
                                case 1: bucket = "Working"
                                case 2: bucket = "Flowing"
                                default: bucket = "Breakthrough"
                                }
                                return isRinged ? "\(bucket), selected" : bucket
                            }())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gesture(drag)
            }
            .frame(height: 48)       // a touch taller for the bloom
            .padding(.vertical, 2)
        }
        .cardSurface(padding: Theme.Spacing.m)
    }

    // Instrument picker sheet
    private var instrumentPicker: some View {
        NavigationStack {
            VStack {
                Picker("Instrument", selection: $instrument) {
                    Text("Select instrument…").tag(nil as Instrument?)
                    ForEach(instruments, id: \.self) { inst in
                        Text(inst.name ?? "").tag(inst as Instrument?)
                    }
                }
                .pickerStyle(.wheel)
                Spacer()
            }
            .navigationTitle("Instrument")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showInstrumentPicker = false } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showInstrumentPicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    private var activityPickerPinned: some View {
        NavigationStack {
            VStack {
                let choices = activityChoicesPinned()
                Picker("", selection: $activityChoice) {
                    ForEach(choices, id: \.self) { choice in
                        let label = activityDisplayName(for: choice)
                        Text(label).tag(choice)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                Spacer()
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showActivityPicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if activityChoice.hasPrefix("core:") {
                            if let raw = Int(activityChoice.split(separator: ":").last ?? "0") {
                                tempActivity = SessionActivityType(rawValue: Int16(raw)) ?? .practice
                                activity = tempActivity
                            } else {
                                tempActivity = .practice
                                activity = .practice
                            }
                            selectedCustomName = ""
                        } else if activityChoice.hasPrefix("custom:") {
                            let name = String(activityChoice.dropFirst("custom:".count))
                            tempActivity = .practice
                            activity = .practice
                            selectedCustomName = name
                        }
                        showActivityPicker = false
                        maybeUpdateActivityDetailFromDefaults()
                        refreshAutoTitleIfNeeded()
                    }
                }
            }
            .onAppear {
                if !selectedCustomName.isEmpty {
                    activityChoice = "custom:\(selectedCustomName)"
                } else {
                    activityChoice = "core:\(activity.rawValue)"
                }
            }
        }
    }

    private var startPicker: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel).labelsHidden()
                Spacer()
            }
            .navigationTitle("Start Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showStartPicker = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { timestamp = tempDate; showStartPicker = false; maybeUpdateActivityDetailFromDefaults() } }
            }
        }
        .presentationDetents([.medium])
    }

    private var durationPicker: some View {
        NavigationStack {
            VStack {
                HStack {
                    Picker("Hours", selection: $tempHours) { ForEach(0..<24, id: \.self) { Text("\($0) h").tag($0) } }.pickerStyle(.wheel)
                    Picker("Minutes", selection: $tempMinutes) { ForEach(0..<60, id: \.self) { Text("\($0) m").tag($0) } }.pickerStyle(.wheel)
                }
                Spacer()
            }
            .navigationTitle("Duration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDurationPicker = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { durationSeconds = (tempHours * 3600) + (tempMinutes * 60); showDurationPicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers
    private func formatClipDuration(_ seconds: Double) -> String {
        // Simple mm:ss formatter
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
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

    private func loadUserActivities() {
        do { userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext) }
        catch { userActivities = [] }
    }

    private func syncActivityChoiceFromState() {
        if selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityChoice = "core:\(activity.rawValue)"
        } else {
            activityChoice = "custom:\(selectedCustomName)"
        }
    }

    private func editorDefaultDescription(timestamp: Date, activity: SessionActivityType, customName: String) -> String {
        let label = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? activity.label : customName
        let hour = Calendar.current.component(.hour, from: timestamp)
        let part: String
        switch hour {
        case 0...4: part = "Late Night"
        case 5...11: part = "Morning"
        case 12...17: part = "Afternoon"
        default: part = "Evening"
        }
        return "\(part) \(label)"
    }

    private func maybeUpdateActivityDetailFromDefaults() {
        let newDefault = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activityDetail == lastAutoActivityDetail {
            activityDetail = newDefault
            lastAutoActivityDetail = newDefault
            userEditedActivityDetail = false
        }
    }

    private func preselectFocusFromNotesIfNeeded() {
        guard selectedDotIndex == nil, !notes.isEmpty else { return }

        if let r = notes.range(of: "FocusDotIndex:") {
            let tail = notes[r.upperBound...]
            let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if let n = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), (0...11).contains(n) {
                selectedDotIndex = n
                stripFocusTokensFromNotes()
                return
            }
        }

        // Back-compat from legacy StateIndex: 0–3 → center dots
        if let r = notes.range(of: "StateIndex:") {
            let tail = notes[r.upperBound...]
            let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if let n = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), (0...3).contains(n) {
                let centers = [1, 4, 7, 10]
                selectedDotIndex = centers[n]
                stripFocusTokensFromNotes()
            }
        }
    }

    private func stripFocusTokensFromNotes() {
        let tokens = ["FocusDotIndex:", "StateIndex:"]
        for t in tokens {
            while let r = notes.range(of: t) {
                let tail = notes[r.upperBound...]
                let end = tail.firstIndex(of: "\n") ?? notes.endIndex
                notes.removeSubrange(r.lowerBound..<end)
                // Remove a trailing newline if we left an empty line
                if notes.hasSuffix("\n\n") { notes.removeLast() }
            }
        }
    }

    private func applyFocusToNotesBeforeSave() {
        // Notes must remain user-entered text only.
        // Focus is already stored structurally (Session.effort / publish payload effort).
        stripFocusTokensFromNotes()
    }

    @MainActor
    private func saveToCoreData(visibility: Bool) {
        let s = Session(context: viewContext)
        if (s.value(forKey: "id") as? UUID) == nil {
            let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
            s.setValue(trimmedCustom.isEmpty ? nil : trimmedCustom, forKey: "userActivityLabel")
            s.setValue(UUID(), forKey: "id")
        }
        if s.timestamp == nil { s.timestamp = Date() }
        s.instrument = instrument
        s.title = title.isEmpty ? defaultTitle(for: instrument, activity: activity) : title
        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = visibility
        s.mood = Int16(mood)
        if let idx = selectedDotIndex {
            s.effort = Int16(idx)
        } else {
            s.effort = Int16(effort)
        }

        applyFocusToNotesBeforeSave()
        if s.entity.attributesByName.keys.contains("areNotesPrivate") {
            s.setValue(areNotesPrivate, forKey: "areNotesPrivate")
        }
        s.notes = notes

        s.setValue(activityDetail.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "activityDetail")
        
        let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let activityTypeString = trimmedCustom.isEmpty ? activity.label : trimmedCustom

        // Replaced this line:
        // s.setValue(activityTypeString, forKey: "activityType")
        s.setValue(activity.rawValue, forKey: "activityType")
        
        #if DEBUG
        let __dbgID = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride")
        let __effectiveUID = __dbgID ?? PersistenceController.shared.currentUserID
#else
        let __effectiveUID = PersistenceController.shared.currentUserID
#endif
        if let uid = __effectiveUID, !uid.isEmpty {
            s.setValue(uid, forKey: "ownerUserID")
        }
        commitStagedAttachments(to: s, ctx: viewContext)
        do {
            try viewContext.save()
            viewContext.processPendingChanges()
            clearDraftIsPublic()
            // v7.12A — Social Pilot (local-only)
            if let sid = s.id {
                let resolvedTitle = s.title ?? ""
                let instLabel =
                    (s.userInstrumentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? s.instrument?.name

                let focusValue: Int? = {
                    if let idx = selectedDotIndex { return idx }
                    return nil
                }()

                let payload = SessionSyncQueue.PostPublishPayload(
                    id: sid,
                    sessionID: sid,
                    sessionTimestamp: timestamp,
                    title: resolvedTitle,
                    durationSeconds: Int(durationSeconds),
                    activityType: activityTypeString,
                    activityDetail: activityDetail.trimmingCharacters(in: .whitespacesAndNewlines),
                    instrumentLabel: instLabel,
                    mood: nil,
                    effort: focusValue,
                    isPublic: visibility
                )

                PublishService.shared.publish(
                    payload: payload,
                    objectID: s.objectID,
                    shouldPublish: true
                )
            } else {
                print("Publish skipped: missing Session.id")
            }
            FeedInteractionStore.markForPublish(s.id ?? UUID())

            // Cleanup: remove staged items that were just committed successfully
            let consumedIDs: [UUID] = stagedAttachments.map { $0.id }
            if !consumedIDs.isEmpty {
                StagingStore.removeMany(ids: consumedIDs)
            }
            // Also purge any surrogate temp files created for staged items
            purgeStagedTempFiles()

            onSaved?()
            clearDraft()
            // Mark this session ID as seen so reopening within the same session doesn't clear again
            if let cur = currentSessionID() { UserDefaults.standard.set(cur, forKey: lastSeenSessionIDKey) }

            // Reset local fields after save so next fresh session starts blank
            notes = ""
            selectedDotIndex = nil
        } catch {
            // On failure, best-effort: remove any files written during this attempt by scanning attachments without permanent IDs
            let fm = FileManager.default
            if let set = s.attachments as? Set<Attachment> {
                for a in set {
                    if a.objectID.isTemporaryID, let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                        AttachmentStore.removeIfExists(path: path)
                    }
                }
            }
            viewContext.rollback()
            purgeStagedTempFiles()
            print("Error saving session (timer review): \(error)")
        }
    }

    private func surrogateURL(for att: StagedAttachment) -> URL? {
        let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension(ext)
    }

    // CHANGE-ID: 20260105_prdv_star_toggle_sync
    // SCOPE: PRDV attachments card star toggle must be bidirectional and consistent with AttachmentViewerView.
    private func toggleThumbnail(_ att: StagedAttachment) {
        guard let url = surrogateURL(for: att) else { return }
        if selectedThumbnailID == att.id {
            selectedThumbnailID = nil
            return
        }
        // ⭐ implies 👁 (thumbnail implies included)
        if isPrivate(id: att.id, url: url) {
            setPrivate(id: att.id, url: url, false)
        }
        selectedThumbnailID = att.id
    }


    private func stageData(_ data: Data, kind: AttachmentKind) {
        let id = UUID()
        stagedAttachments.append(StagedAttachment(id: id, data: data, kind: kind))
        if kind == .image {
            let imageCount = stagedAttachments.filter { $0.kind == .image }.count
            if imageCount == 1 { selectedThumbnailID = id }
        }
    }

    private func removeStagedAttachment(_ a: StagedAttachment) {
        stagedAttachments.removeAll { $0.id == a.id }
        if selectedThumbnailID == a.id {
            selectedThumbnailID = stagedAttachments.first(where: { $0.kind == .image })?.id
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let kind = kindForURL(url)
                    stageData(data, kind: kind)
                } catch { print("File import failed for \(url): \(error)") }
            }
        }
    }

    private func kindForURL(_ url: URL) -> AttachmentKind {
        let ext = url.pathExtension.lowercased()
        if ["png","jpg","jpeg","heic","heif","gif","bmp","tiff","tif"].contains(ext) { return .image }
        if ["m4a","aac","mp3","wav","aiff","caf"].contains(ext) { return .audio }
        if ["mov","mp4","m4v","avi"].contains(ext) { return .video }
        return .file
    }

    private func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) {
        let imageIDs = stagedAttachments.filter { $0.kind == .image }.map { $0.id }
        var chosenThumbID = selectedThumbnailID

        // Ensure thumbnail implies included (staged privacy) before migration/commit
        if let tid = chosenThumbID, let thumb = stagedAttachments.first(where: { $0.id == tid }) {
            setPrivate(id: tid, url: surrogateURL(for: thumb), false)
        }

        // Map staged UUID → final Attachment UUID (used to persist isThumbnail correctly)
        var stagedToFinalID: [UUID: UUID] = [:]
        

        // Map staged UUID → final file URL (used to persist privacy on final keys)
        var stagedToFinalURL: [UUID: URL] = [:]
let namesKey = "stagedAudioNames_temp"
        let namesDict = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]

        // Read staged video titles captured during timer flow and define persisted store key
        let stagedVideoTitlesKey = "stagedVideoTitles_temp"
        let stagedVideoTitles: [String: String] = (UserDefaults.standard.dictionary(forKey: stagedVideoTitlesKey) as? [String: String]) ?? [:]
        let persistedVideoTitlesKey = "persistedVideoTitles_v1"
        let persistedAudioTitlesKey = "persistedAudioTitles_v1"

        // Track rollback closures for files written during this commit attempt
        var rollbacks: [() -> Void] = []
        var createdAttachments: [Attachment] = []

        // 1) Write files using rollback-safe API and create Attachment objects
        for att in stagedAttachments {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let baseName: String
                if let custom = namesDict[att.id.uuidString], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    baseName = custom
                } else {
                    baseName = att.id.uuidString
                }
                let result = try AttachmentStore.saveDataWithRollback(att.data, suggestedName: baseName, ext: ext)
                rollbacks.append(result.rollback)

                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                let created: Attachment = try AttachmentStore.addAttachment(kind: att.kind, filePath: result.path, to: session, isThumbnail: isThumb, ctx: ctx)
                if let finalID = (created.value(forKey: "id") as? UUID) {
                    stagedToFinalID[att.id] = finalID
                }


                // Attempt to migrate privacy from staged keys (ID/Temp URL) to final keys (ID/File URL)
                let finalURL = URL(fileURLWithPath: result.path)
                
                stagedToFinalURL[att.id] = finalURL
let stagedURL = surrogateURL(for: att)
                migratePrivacy(fromStagedID: att.id, stagedURL: stagedURL, toNewID: (created.value(forKey: "id") as? UUID), newURL: finalURL)
                // Persist any staged AUDIO title so publish pipeline can round-trip it (remote display_name)
                if att.kind == .audio {
                    let stagedKey = att.id.uuidString
                    if let stagedTitleRaw = namesDict[stagedKey] {
                        let trimmed = stagedTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if let finalID = created.value(forKey: "id") as? UUID {
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
                                persisted[finalID.uuidString] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedAudioTitlesKey)
                            } else {
                                // Fallback (should be rare): key by saved filename stem
                                let stem = URL(fileURLWithPath: result.path).deletingPathExtension().lastPathComponent
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
                                persisted[stem] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedAudioTitlesKey)
                            }
                        }
                    }
                }
                // Persist any staged video title so SessionDetailView can surface it later
                if att.kind == .video {
                    let stagedKey = att.id.uuidString
                    if let stagedTitleRaw = stagedVideoTitles[stagedKey] {
                        let trimmed = stagedTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            // Store under the final attachment UUID (preferred) if available; else fall back to file path stem
                            if let finalID = created.value(forKey: "id") as? UUID {
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedVideoTitlesKey) as? [String: String]) ?? [:]
                                persisted[finalID.uuidString] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedVideoTitlesKey)
                            } else {
                                // Fallback: use the created file path stem as a last resort
                                let stem = URL(fileURLWithPath: result.path).deletingPathExtension().lastPathComponent
                                var persisted = (UserDefaults.standard.dictionary(forKey: persistedVideoTitlesKey) as? [String: String]) ?? [:]
                                persisted[stem] = trimmed
                                UserDefaults.standard.set(persisted, forKey: persistedVideoTitlesKey)
                            }
                        }
                    }
                }

                createdAttachments.append(created)
            } catch {
                // If any write/add fails mid-loop, best-effort rollback files written so far and clear created objects from the context
                for rb in rollbacks { rb() }
                rollbacks.removeAll()
                // Delete any created attachments from the context (unsaved yet)
                for a in createdAttachments { ctx.delete(a) }
                createdAttachments.removeAll()
                print("Attachment commit failed: ", error)
                break
            }
        }

        // Resolve staged thumbnail UUID to final Attachment UUID
        let chosenFinalThumbID: UUID? = chosenThumbID.flatMap { stagedToFinalID[$0] }


        

        // Persist inclusion on FINAL keys for the chosen thumbnail attachment (ContentView relies on final URL keys)
        if let stagedID = chosenThumbID,
           let finalID = chosenFinalThumbID,
           let finalURL = stagedToFinalURL[stagedID] {
            setPrivate(id: finalID, url: finalURL, false)
        }
// 2) Update thumbnail flags across ALL attachments in this session to reflect selection
        do {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", session.objectID)
            let existing = try ctx.fetch(req)
            for a in existing {
                let id = (a.value(forKey: "id") as? UUID)
                let isThumb = (id != nil) && (id == chosenFinalThumbID)
                a.setValue(isThumb, forKey: "isThumbnail")
            }
        } catch {
            // If thumbnail update fails before save, it will be covered by context save error handling outside.
            print("Failed to update thumbnail flags: ", error)
        }

        // Note: Do not save the context here; caller will attempt save and handle rollback of files on failure.
        UserDefaults.standard.removeObject(forKey: namesKey)
        UserDefaults.standard.removeObject(forKey: stagedVideoTitlesKey)
    }

    private func stagedIndexForAttachment(_ target: StagedAttachment) -> Int {
        let images = stagedAttachments.filter { $0.kind == .image }
        let videos = stagedAttachments.filter { $0.kind == .video }
        let audios = stagedAttachments.filter { $0.kind == .audio }
        let combined: [StagedAttachment] = images + videos + audios
        return combined.firstIndex(where: { $0.id == target.id }) ?? -1
    }

    private func ensureSurrogateFilesExistForViewer() {
        let fm = FileManager.default
        for att in stagedAttachments {
            guard let url = surrogateURL(for: att) else { continue }
            if !fm.fileExists(atPath: url.path) {
                switch att.kind {
                case .image, .video, .audio:
                    // Write the staged bytes to the surrogate temp URL so the viewer can load by URL
                    try? att.data.write(to: url, options: .atomic)
                case .file:
                    // Files are not displayed in the full-screen media viewer
                    break
                }
            }
        }
    }

    private func viewerURLArrays() -> (images: [URL], videos: [URL], audios: [URL]) {
        let imageURLs: [URL] = stagedAttachments.filter { $0.kind == .image }.compactMap { surrogateURL(for: $0) }
        let videoURLs: [URL] = stagedAttachments.filter { $0.kind == .video }.compactMap { surrogateURL(for: $0) }
        let audioURLs: [URL] = stagedAttachments.filter { $0.kind == .audio }.compactMap { surrogateURL(for: $0) }
        return (imageURLs, videoURLs, audioURLs)
    }

    private func replaceStagedAttachment(originalURL: URL, with newURL: URL, kind: AttachmentKind) {
        // Match by surrogate URL basename (staged id)
        let stem = originalURL.deletingPathExtension().lastPathComponent
        guard let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) else { return }
        // Replace data by reading from newURL; keep id and kind stable
        if let data = try? Data(contentsOf: newURL) {
            var att = stagedAttachments[idx]
            att = StagedAttachment(id: att.id, data: data, kind: att.kind)
            stagedAttachments[idx] = att
        }
    }

    private func insertNewStagedAttachment(after originalURL: URL, newURL: URL, kind: AttachmentKind) {
        // Insert a new staged item of the provided kind, with a new UUID
        let newID = UUID()
        let data = (try? Data(contentsOf: newURL)) ?? Data()
        let newAtt = StagedAttachment(id: newID, data: data, kind: kind)
        // Phase 2: Seed a reasonable display title for new audio trims so UI doesn't fall back to "Audio clip".
        if kind == .audio {
            let stem = newURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = stem.isEmpty ? "Audio clip" : stem
            var dict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
            dict[newID.uuidString] = title
            UserDefaults.standard.set(dict, forKey: "stagedAudioNames_temp")
        }
        // Compute gallery ordering position: after the tapped item within its section
        let images = stagedAttachments.filter { $0.kind == .image }
        let videos = stagedAttachments.filter { $0.kind == .video }
        let audios = stagedAttachments.filter { $0.kind == .audio }
        let combined: [StagedAttachment] = images + videos + audios
        let stem = originalURL.deletingPathExtension().lastPathComponent
        let currentIndex = combined.firstIndex(where: { $0.id.uuidString == stem }) ?? (combined.count - 1)
        // Determine target array and base index
        switch kind {
        case .image:
            // Append to end of images
            if let splitIndex = stagedAttachments.firstIndex(where: { $0.kind != .image }) {
                stagedAttachments.insert(newAtt, at: splitIndex)
            } else {
                stagedAttachments.append(newAtt)
            }
        case .video:
            // Insert after current video within videos section
            let videosOnly = stagedAttachments.enumerated().filter { $0.element.kind == .video }
            let currentVideoIndexInVideos: Int? = {
                if combined.indices.contains(currentIndex) {
                    let currentItem = combined[currentIndex]
                    if currentItem.kind == .video {
                        return videosOnly.firstIndex(where: { $0.element.id == currentItem.id })
                    }
                }
                return nil
            }()
            if let cv = currentVideoIndexInVideos {
                let insertAt = videosOnly[cv].offset + 1
                stagedAttachments.insert(newAtt, at: insertAt)
            } else {
                // Append after all images and existing videos
                let lastVideoIndex = stagedAttachments.lastIndex(where: { $0.kind == .video })
                if let lastVideoIndex {
                    stagedAttachments.insert(newAtt, at: lastVideoIndex + 1)
                } else {
                    // If no videos yet, insert after images
                    let lastImageIndex = stagedAttachments.lastIndex(where: { $0.kind == .image })
                    if let lastImageIndex { stagedAttachments.insert(newAtt, at: lastImageIndex + 1) } else { stagedAttachments.append(newAtt) }
                }
            }
        case .audio:
            // Insert after current audio within audios section
            let audiosOnly = stagedAttachments.enumerated().filter { $0.element.kind == .audio }
            let currentAudioIndexInAudios: Int? = {
                if combined.indices.contains(currentIndex) {
                    let currentItem = combined[currentIndex]
                    if currentItem.kind == .audio {
                        return audiosOnly.firstIndex(where: { $0.element.id == currentItem.id })
                    }
                }
                return nil
            }()
            if let ca = currentAudioIndexInAudios {
                let insertAt = audiosOnly[ca].offset + 1
                stagedAttachments.insert(newAtt, at: insertAt)
            } else {
                stagedAttachments.append(newAtt)
            }
        case .file:
            stagedAttachments.append(newAtt)
        }
    }

    private func defaultTitle(for inst: Instrument? = nil, activity: SessionActivityType) -> String {
        if let name = (inst ?? instrument)?.name, !name.isEmpty { return "\(name) : \(activity.label)" }
        return activity.label
    }

    private func refreshAutoTitleIfNeeded() {
        guard !isTitleEdited else { return }
        let auto = defaultTitle(for: instrument, activity: activity)
        title = auto
        initialAutoTitle = auto
    }

    private func fetchInstruments() -> [Instrument] {
        let req: NSFetchRequest<Instrument> = Instrument.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? viewContext.fetch(req)) ?? []
    }

    private func fetchPrimaryInstrumentName() -> String? {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Profile")
        req.fetchLimit = 1
        do {
            if let profile = try viewContext.fetch(req).first {
                let name = profile.value(forKey: "primaryInstrument") as? String
                let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed?.isEmpty == false) ? trimmed : nil
            }
        } catch { print("Profile fetch failed: \(error)") }
        return nil
    }

    private func secondsToHM(_ seconds: Int) -> (Int, Int) {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return (h, m)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func ensureCameraAuthorized(onAuthorized: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: onAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? onAuthorized() : { self.showCameraDeniedAlert = true }() }
            }
        default: self.showCameraDeniedAlert = true
        }
    }

    private func dismissToRoot() {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let keyWindow = windowScene?.windows.first { $0.isKeyWindow }
        keyWindow?.rootViewController?.dismiss(animated: true)
        #endif
    }
}

fileprivate struct AttachmentThumbCell: View {
    let att: StagedAttachment
    let isThumbnail: Bool
    let onMakeThumbnail: () -> Void
    let onRemove: () -> Void
    let isPrivate: (_ id: UUID?, _ url: URL?) -> Bool
    let setPrivate: (_ id: UUID?, _ url: URL?, _ value: Bool) -> Void

    @State private var videoPoster: UIImage? = nil
    @State private var isPresentingVideo = false
    @State private var audioDuration: Double? = nil

    private let tile: CGFloat = 128

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .topLeading) {
                thumbContent
                    .frame(width: tile, height: tile)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }

            // Right-side vertical control column: Star, Privacy, Delete
            VStack(spacing: 6) {
                // Star (thumbnail selection for images, audio, and video)
                if att.kind == .image || att.kind == .audio || att.kind == .video {
                    Text(isThumbnail ? "★" : "☆")
                        .font(.system(size: 16))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .onTapGesture { onMakeThumbnail() }
                        .accessibilityLabel(isThumbnail ? "Thumbnail (selected)" : "Set as Thumbnail")
                }

                // Privacy toggle (ID-first, URL fallback)
                let priv = isPrivate(att.id, resolvedURL)
                Button {
                    setPrivate(att.id, resolvedURL, !priv)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .opacity((priv || isThumbnail) ? 0 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(priv ? "Mark attachment public" : "Mark attachment private")

                // Delete
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete attachment")
            }
            .padding(6)
        }
        .contextMenu {
            if att.kind == .image || att.kind == .audio || att.kind == .video {
                Button("Set as Thumbnail") { onMakeThumbnail() }
            }
            Button(role: .destructive) { onRemove() } label: { Text("Remove") }
        }
    }

    private var resolvedURL: URL? {
        // Use a stable, surrogate URL in Caches/Temp using the staged id and an extension by kind.
        let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension(ext)
    }

    @ViewBuilder
    private var thumbContent: some View {
        switch att.kind {
        case .image:
            if let ui = UIImage(data: att.data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder(system: "photo")
            }
        case .audio:
            let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
            let rawDisplay = namesDict[att.id.uuidString] ?? ""
            let trimmedDisplay = rawDisplay.trimmingCharacters(in: .whitespacesAndNewlines)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .opacity(0.85)

                    VStack(alignment: .leading, spacing: 2) {
                        if !trimmedDisplay.isEmpty {
                            Text(trimmedDisplay)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("Audio clip")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let secs = audioDuration {
                            Text(formatClipDuration(secs))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onAppear {
                // Ensure a temp surrogate exists for the staged audio so inline players/viewers can resolve it after navigation
                if let url = resolvedURL, !FileManager.default.fileExists(atPath: url.path) {
                    try? att.data.write(to: url, options: .atomic)
                }

                // Lazily compute audio duration once
                if audioDuration == nil, let url = resolvedURL {
                    let asset = AVURLAsset(url: url)
                    let seconds = CMTimeGetSeconds(asset.duration)
                    if seconds.isFinite && seconds > 0 {
                        audioDuration = seconds
                    }
                }
            }

        case .video:
            ZStack {
                if let poster = videoPoster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(system: "film")
                        .task(id: resolvedURL) {
                            guard let url = resolvedURL else { return }
                            // Ensure a temp surrogate exists for the staged video so we can generate a poster
                            if !FileManager.default.fileExists(atPath: url.path) {
                                try? att.data.write(to: url, options: .atomic)
                            }
                            await generatePosterIfNeeded(for: url)
                        }
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .onAppear {
                if let url = resolvedURL, !FileManager.default.fileExists(atPath: url.path) {
                    try? att.data.write(to: url, options: .atomic)
                }
            }
        case .file:
            placeholder(system: "doc")
        }
    }

    private func placeholder(system: String) -> some View {
        Image(systemName: system)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(24)
    }


    private func formatClipDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func generatePosterIfNeeded(for url: URL) async {
        if videoPoster != nil { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                #if canImport(UIKit)
                let img = AttachmentStore.generateVideoPoster(url: url)
                #else
                let img: UIImage? = nil
                #endif
                DispatchQueue.main.async {
                    self.videoPoster = img
                    continuation.resume()
                }
            }
        }
    }
}

#if canImport(UIKit)
import AVKit
fileprivate struct VideoPlayerSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.player?.isMuted = true
        return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
#endif

