// CHANGE-ID: 20251012_202320-tasks-pad-a2
// SCOPE: Add optional notesPrefill parameter and init notes from it

//  PostRecordDetailsView_20251004c.swift
//  MOTIVO
//
//  Visual polish + Instrument row chevron fix
//  Silent if one instrument, chevron row if multiple.

import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit

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

    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

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
        return false
    }

    private func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        // Update cache immediately for responsive UI
        privacyMap[key] = value
        // Persist via shared utility (also posts didChange)
        AttachmentPrivacy.setPrivate(id: id, url: url, value)
    }

    private func migratePrivacy(fromStagedID stagedID: UUID, stagedURL: URL?, toNewID newID: UUID?, newURL: URL?) {
        // Read current maps fresh to avoid stale cache writes
        var map = (UserDefaults.standard.dictionary(forKey: AttachmentPrivacy.mapKey) as? [String: Bool]) ?? [:]

        // Resolve any value stored under staged keys
        let stagedIDKey = "id://\(stagedID.uuidString)"
        let stagedURLKey = stagedURL?.absoluteString

        // Prefer explicit staged id value; otherwise fallback to staged URL value
        let stagedValue: Bool? = map[stagedIDKey] ?? (stagedURLKey.flatMap { map[$0] })

        guard let value = stagedValue else { return }

        // Write the same value to the final keys (ID-first, URL fallback)
        if let newID { map["id://\(newID.uuidString)"] = value }
        if let newURL { map[newURL.absoluteString] = value }

        // Persist and update live cache for immediate UI reflection
        UserDefaults.standard.set(map, forKey: AttachmentPrivacy.mapKey)
        privacyMap = map
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
        self.prefillTimestamp = timestamp ?? Date()
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
                        Text("Visibility").sectionHeader()
                        Toggle("Public", isOn: $isPublic)
                            .font(Theme.Text.body)
                    }
                    .cardSurface()

                    // ---------- Notes ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Notes").sectionHeader()
                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
                            .font(Theme.Text.body)
                    }
                    .cardSurface()

                    stateStripCard

                    attachmentsSection
                        .cardSurface()

                    addAttachmentsControlsSection
                        .cardSurface()
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
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
                        onCancel()
                        isPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to Timer")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        saveToCoreData()
                        DispatchQueue.main.async { withAnimation(.none) { isPresented = false } }
                    }) {
                        Text("Save")
                            .font(Theme.Text.body)
                    }
                    .disabled(durationSeconds == 0 || instrument == nil)
                }
            }
            // Sheets
            .sheet(isPresented: $showInstrumentPicker) { instrumentPicker }
            .sheet(isPresented: $showActivityPicker) { activityPickerPinned }
            .sheet(isPresented: $showStartPicker) { startPicker }
            .sheet(isPresented: $showDurationPicker) { durationPicker }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
            .task(id: photoPickerItem) {
                guard let item = photoPickerItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) { stageData(data, kind: .image) }
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
                preselectFocusFromNotesIfNeeded()
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
            }
            .onChange(of: instrument) { _, _ in refreshAutoTitleIfNeeded() }
            .onChange(of: activity) { _, _ in maybeUpdateActivityDetailFromDefaults() }
            .onChange(of: activityDetail) { old, new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                userEditedActivityDetail = (!trimmed.isEmpty && trimmed != lastAutoActivityDetail)
            }
            .onAppear { loadPrivacyMap() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                loadPrivacyMap()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                purgeStagedTempFiles()
            }
            .appBackground()
        }
}

    // MARK: - Subviews

    @ViewBuilder
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Attachments").sectionHeader()
            if !stagedAttachments.isEmpty {
                let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(stagedAttachments) { att in
                        AttachmentThumbCell(
                            att: att,
                            isThumbnail: selectedThumbnailID == att.id,
                            onMakeThumbnail: { selectedThumbnailID = att.id },
                            onRemove: { removeStagedAttachment(att) },
                            isPrivate: { id, url in
                                return isPrivate(id: id, url: url)
                            },
                            setPrivate: { id, url, value in
                                setPrivate(id: id, url: url, value)
                            }
                        )
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
    }

    @ViewBuilder
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
        .cardSurface()
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
        guard let dot = selectedDotIndex else {
            stripFocusTokensFromNotes()
            return
        }

        stripFocusTokensFromNotes()
        if !notes.isEmpty && !notes.hasSuffix("\n") { notes.append("\n") }
        notes.append("FocusDotIndex: \(dot)")
    }

    @MainActor
    private func saveToCoreData() {
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
        s.isPublic = isPublic
        s.mood = Int16(mood)
        s.effort = Int16(effort)

        applyFocusToNotesBeforeSave()
        s.notes = notes

        s.setValue(activityDetail.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "activityDetail")
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
            // v7.12A — Social Pilot (local-only)
            PublishService.shared.publishIfNeeded(objectID: s.objectID, shouldPublish: isPublic /* or your current flag */)
            FeedInteractionStore.markForPublish(s.id ?? UUID())

            // Cleanup: remove staged items that were just committed successfully
            let consumedIDs: [UUID] = stagedAttachments.map { $0.id }
            if !consumedIDs.isEmpty {
                StagingStore.removeMany(ids: consumedIDs)
            }

            onSaved?()
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
        if chosenThumbID == nil, imageIDs.count == 1 { chosenThumbID = imageIDs.first }

        let namesKey = "stagedAudioNames_temp"
        let namesDict = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]

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

                // Attempt to migrate privacy from staged keys (ID/Temp URL) to final keys (ID/File URL)
                let finalURL = URL(fileURLWithPath: result.path)
                let stagedURL = surrogateURL(for: att)
                migratePrivacy(fromStagedID: att.id, stagedURL: stagedURL, toNewID: (created.value(forKey: "id") as? UUID), newURL: finalURL)

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

        // 2) Update thumbnail flags across ALL attachments in this session to reflect selection
        do {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", session.objectID)
            let existing = try ctx.fetch(req)
            for a in existing {
                let id = (a.value(forKey: "id") as? UUID)
                let isThumb = (id != nil) && (id == chosenThumbID)
                a.setValue(isThumb, forKey: "isThumbnail")
            }
        } catch {
            // If thumbnail update fails before save, it will be covered by context save error handling outside.
            print("Failed to update thumbnail flags: ", error)
        }

        // Note: Do not save the context here; caller will attempt save and handle rollback of files on failure.
        UserDefaults.standard.removeObject(forKey: namesKey)
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
                    Image(systemName: priv ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
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
            VStack(spacing: 6) {
                placeholder(system: "waveform")
                // Read display name from temp names map if present; else show filename stem
                let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                let display = namesDict[att.id.uuidString] ?? ""
                if !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(display)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
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
                            await generatePosterIfNeeded(for: url)
                        }
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { if resolvedURL != nil { isPresentingVideo = true } }
            .sheet(isPresented: $isPresentingVideo) {
                if let url = resolvedURL { VideoPlayerSheet(url: url) }
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







