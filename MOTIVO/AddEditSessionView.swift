// CHANGE-ID: 20251010_161159_autodesc_fix_edit
// SCOPE: Edit-mode auto-description restoration; load userActivityLabel; reconcile auto vs custom; preserve ordering fix; no other changes
// CHANGE-ID: 20251008_172540_aa2f1
// SCOPE: Visual-only — tint add buttons to light grey; remove notes placeholder; hide empty attachments message
//  AddEditSessionView.swift
//  MOTIVO
//
//  [ROLLBACK ANCHOR] v7.8 DesignLite — pre
//
//  v7.8 — Edit thumbnails: preload existing images safely
//  - Preload uses only known fields (id, kind, fileURL, isThumbnail).
//  - Image bytes resolved from: absolute path → file:// URL → relative-in-Documents.
//  - Avoids duplicating existing attachments on Save; updates cover flag.
//  - No schema/migrations. No other behaviour changes.
//

import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // Editing existing session or creating new
    var session: Session? = nil

    // Form state
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var timestamp: Date = Date()
    @State private var durationSeconds: Int = 0
    @State private var activity: SessionActivityType = .practice

    // Activity description (short detail) + defaulting logic
    @State private var activityDetail: String = ""
    @State private var lastAutoActivityDetail: String = ""     // tracks the last generated default
    @State private var userEditedActivityDetail: Bool = false  // breaks auto-sync once user types
    @State private var userHasEditedActivityDetail: Bool = false

    // User-local activities + selection
    @State private var userActivities: [UserActivity] = []
    /// String selector used by the wheel: "core:<raw>" or "custom:<name>"
    @State private var activityChoice: String = "core:0"
    /// If user picked a custom activity, hold its name separately (do NOT store in activityDetail)
    @State private var selectedCustomName: String = ""

    @State private var isPublic: Bool = true
    @State private var notes: String = ""

    // Wheels
    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var showActivityPicker = false
    @State private var showInstrumentPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0

    // Attachments
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var selectedThumbnailID: UUID? = nil
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraDeniedAlert = false

    // UI stability (instruments empty-state)
    @State private var instrumentsGateArmed = false
    @State private var instrumentsReady = false

    // Track which staged attachments came from Core Data (existing) to prevent duplication on save
    @State private var existingAttachmentIDs: Set<UUID> = []

    // Primary Activity persisted ref
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

    init(session: Session? = nil) {
        self.session = session
        // Seed time-related fields on edit so they don’t flash empty
        if let s = session {
            if let ts = s.timestamp { _timestamp = State(initialValue: ts) }
            _durationSeconds = State(initialValue: Int(s.durationSeconds))
        }
    }

    private var isEdit: Bool { session != nil }
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {

                // No instruments / Instrument picker
                if hasNoInstruments {
                    // Show the empty-state card only after the first 120ms tick
                    if instrumentsGateArmed && !instrumentsReady {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No instruments found").font(.headline)
                            Text("Add an instrument in your Profile to save this session.")
                                .foregroundStyle(.secondary).font(.subheadline)
                        }
                        .cardSurface()
                    } else {
                        // Render nothing until either the arm time passes or instruments arrive
                        EmptyView()
                    }
                } else if hasMultipleInstruments {
                    // Instrument (always visible if any instruments exist)
VStack(alignment: .leading, spacing: Theme.Spacing.s) {
    Text("Instrument").sectionHeader()
    if hasMultipleInstruments {
        // Tappable row → wheel sheet
        Button {
            showInstrumentPicker = true
        } label: {
            HStack {
                Text(instrument?.name ?? "Select instrument…")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Instrument")
        .accessibilityIdentifier("picker.instrument")
    } else {
        // Read-only row for single instrument (no chevron)
        HStack {
            Text(instrument?.name ?? "Instrument")
            Spacer()
        }
        .accessibilityLabel(instrument?.name ?? "Instrument")
    }
}
.cardSurface()
                }

                // Activity
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Activity").sectionHeader()
                    Button {
                        showActivityPicker = true
                    } label: {
                        let display = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? activity.label : selectedCustomName
                        HStack {
                            Text(display)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Activity")
                    .accessibilityIdentifier("picker.activity")
                }
                .cardSurface()

                // Activity description (short detail)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Description").sectionHeader()
                    TextField("Activity description", text: $activityDetail, axis: .vertical)
                        .lineLimit(1...3)
                        .onChange(of: activityDetail) { _, new in handleActivityDetailChange_v2(new) }
                }
                .cardSurface()

                // Start Time
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Start Time").sectionHeader()
                    Button {
                        tempDate = timestamp
                        showStartPicker = true
                    } label: {
                        HStack {
                            Text(formattedDate(timestamp))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                // Duration
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Duration").sectionHeader()
                    Button {
                        let hm = secondsToHM(durationSeconds)
                        tempHours = hm.0; tempMinutes = hm.1
                        showDurationPicker = true
                    } label: {
                        HStack {
                            Text(formattedDuration(durationSeconds))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    if durationSeconds == 0 {
                        Text("Duration must be greater than 0").font(.footnote).foregroundColor(.red)
                    }
                }
                .cardSurface()

                // Privacy
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Toggle("Public", isOn: $isPublic)
                }
                .cardSurface()

                // Notes
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Notes").sectionHeader()
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes).frame(minHeight: 100)
                            .accessibilityLabel("Notes")
                    }
                }
                .cardSurface()

                // Attachments grid
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Attachments").sectionHeader()
                    Group {
                        if !stagedAttachments.isEmpty {
                            StagedAttachmentsSectionView(
                                attachments: stagedAttachments,
                                onRemove: { staged in
                                    // If this staged item came from Core Data, delete the backing Attachment persistently
                                    if existingAttachmentIDs.contains(staged.id), let s = session {
                                        // Fetch the matching Attachment by its persisted UUID
                                        let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
                                        req.predicate = NSPredicate(format: "session == %@ AND id == %@", s.objectID, staged.id as CVarArg)
                                        req.fetchLimit = 1
                                        if let match = try? viewContext.fetch(req).first {
                                            viewContext.delete(match)
                                            do { try viewContext.save() } catch { print("Delete save error: \(error)") }
                                        }
                                    }
                                    // Always update the local staged list to reflect UI immediately
                                    removeStagedAttachment(staged)
                                },
                                selectedThumbnailID: $selectedThumbnailID
                            )
                        }
                    }
                }
                .cardSurface()
                .accessibilityLabel("Attachments")

                // Add buttons
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Button("Add Photo") { showPhotoPicker = true }
                        .tint(Theme.Colors.secondaryText)
                        .accessibilityLabel("Add photo")
                        .accessibilityHint("Choose a photo from your library or camera")
                        .accessibilityIdentifier("addAttachment.photo")
                    Button("Add File") { showFileImporter = true }
                        .tint(Theme.Colors.secondaryText)
                        .accessibilityLabel("Add file")
                        .accessibilityHint("Choose a file from your library")
                        .accessibilityIdentifier("addAttachment.file")
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") { ensureCameraAuthorized { showCamera = true } }
                            .tint(Theme.Colors.secondaryText)
                            .accessibilityLabel("Add photo")
                            .accessibilityHint("Choose a photo from your library or camera")
                            .accessibilityIdentifier("addAttachment.photo")
                    }
                }
                .cardSurface()

            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .navigationTitle(isEdit ? "Edit Session" : "New Session")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(durationSeconds == 0 || instrument == nil)
                    .accessibilityLabel("Save session")
                    .accessibilityIdentifier("button.saveSession")
            }
        }
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
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.8) { stageData(data, kind: .image) }
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
        .task { hydrate() } // unified first-appearance init
        .onAppear {
            syncActivityChoiceFromState()
        }
        .onChange(of: activity) { _, _ in
            maybeUpdateActivityDetailFromDefaults()
        }
        .onChange(of: timestamp) { _, _ in
            maybeUpdateActivityDetailFromDefaults()
        }
        .onChange(of: timestamp) { _, _ in maybeUpdateActivityDetailFromDefaults_v2() }
        .onChange(of: activity) { _, _ in maybeUpdateActivityDetailFromDefaults_v2() }
        .onChange(of: activityDetail) { old, new in
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            userEditedActivityDetail = (!trimmed.isEmpty && trimmed != lastAutoActivityDetail)
        }
        .onAppear {
            instrumentsGateArmed = false
            instrumentsReady = false
            // Give instruments a breath to bind if they’re coming from Core Data
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                instrumentsGateArmed = true
                // If they’re already non-empty by now, mark ready
                if !instruments.isEmpty { instrumentsReady = true }
            }
        }
        .onChange(of: instruments.count) { _, newCount in
            // As soon as instruments arrive, it's safe to render their section
            if newCount > 0 { instrumentsReady = true }
        }
        .appBackground()
    }
}

    // Instrument picker sheet (wheel style)
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
        }
        .navigationTitle("Instrument")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showInstrumentPicker = false }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showInstrumentPicker = false }
            }
        }
    }
}

// MARK: - Subviews (pinned activity wheel + pickers)

    private var activityPickerPinned: some View {
        NavigationStack {
            VStack {
                let choices = activityChoicesPinned()
                Picker("", selection: $activityChoice) {
                    ForEach(choices, id: \.self) { choice in
                        Text(activityDisplayName(for: choice)).tag(choice)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                Spacer()
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showActivityPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyActivityChoice()
                        maybeUpdateActivityDetailFromDefaults_v2()
                        showActivityPicker = false
                        // After changing activity/custom, update default description if appropriate.
                        maybeUpdateActivityDetailFromDefaults()
                    }
                }
            }
            .onAppear { syncActivityChoiceFromState() }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { timestamp = tempDate; showStartPicker = false }
                }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { durationSeconds = (tempHours * 3600) + (tempMinutes * 60); showDurationPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Data hydration

    private func hydrate() {
        instruments = fetchInstruments()

        if let s = session {
            // Edit mode
            instrument = s.instrument
            timestamp = s.timestamp ?? Date()
            durationSeconds = Int(s.durationSeconds)
            isPublic = s.isPublic
            notes = s.notes ?? ""

            let raw = Int16(s.value(forKey: "activityType") as? Int ?? 0)
            activity = SessionActivityType(rawValue: raw) ?? .practice
            activityDetail = (s.value(forKey: "activityDetail") as? String) ?? ""

            // Reconcile auto vs custom on edit hydrate: keep auto-updates alive if detail equals the computed default.
            do {
                let expectedAuto = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: ((s.value(forKey: "userActivityLabel") as? String) ?? selectedCustomName))
                if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines) == expectedAuto.trimmingCharacters(in: .whitespacesAndNewlines) {
                    lastAutoActivityDetail = activityDetail
                    userHasEditedActivityDetail = false
                    userEditedActivityDetail = false
                } else {
                    userHasEditedActivityDetail = true
                    userEditedActivityDetail = true
                }
            }

            selectedCustomName = (s.value(forKey: "userActivityLabel") as? String) ?? "" // remains blank unless user selects a custom in the picker
        } else {
            // New mode defaults
            timestamp = Date()
            durationSeconds = 0

            if instrument == nil {
                if let primaryName = fetchPrimaryInstrumentName(),
                   let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                    instrument = match
                } else if instruments.count == 1 {
                    instrument = instruments.first
                }
            }
        }

        // Prefetch customs and align choice
        loadUserActivities()
        applyPrimaryActivityRefIfNeeded()
        syncActivityChoiceFromState()

        // Seed default description if blank (new session) or if coming from a state with empty detail
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let auto = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
            lastAutoActivityDetail = auto
            activityDetail = auto
            userEditedActivityDetail = false
        }
        // If we loaded a non-empty description that differs from the last auto, treat it as user-customized
        else if activityDetail != lastAutoActivityDetail {
            userHasEditedActivityDetail = true
            userEditedActivityDetail = true
        }

        // Preload existing attachments for edit mode (only once to avoid duplicates)
        if session != nil, stagedAttachments.isEmpty {
            preloadExistingAttachments()
        }
    }

    private func applyPrimaryActivityRefIfNeeded() {
        // Only seed from Primary when creating a new session and no explicit activity set
        guard session == nil else { return }
        let raw = primaryActivityRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("core:") {
            if let v = Int(raw.split(separator: ":").last ?? "0"),
               let t = SessionActivityType(rawValue: Int16(v)) {
                activity = t
                selectedCustomName = ""
                return
            }
        } else if raw.hasPrefix("custom:") {
            let name = String(raw.dropFirst("custom:".count))
            if userActivities.contains(where: { ($0.displayName ?? "") == name }) {
                activity = .practice
                selectedCustomName = name
                return
            }
        }
        // fallback → practice
        activity = .practice
        selectedCustomName = ""
    }

    // MARK: - Actions

    private func save() {
        let s = session ?? Session(context: viewContext)
        if (s.value(forKey: "id") as? UUID) == nil {
            s.setValue(UUID(), forKey: "id")
        }
        s.instrument = instrument

        // Title = activityDetail (trimmed) or fallback
        let trimmedDetail = activityDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        s.title = trimmedDetail.isEmpty ? defaultTitle(for: instrument, activity: activity) : trimmedDetail

        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = isPublic
        s.notes = notes

        // Persist activity type + detail
        s.setValue(activity.rawValue, forKey: "activityType")
        s.setValue(trimmedDetail, forKey: "activityDetail")

        // If a custom name is selected, stamp userActivityLabel; otherwise clear any previous custom label
        let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            s.setValue(trimmedCustom, forKey: "userActivityLabel")
        } else {
            s.setValue(nil, forKey: "userActivityLabel")
        }

        // Owner stamp
        if let uid = PersistenceController.shared.currentUserID, !uid.isEmpty {
            s.setValue(uid, forKey: "ownerUserID")
        }

        // Commit staged attachments (skip existing to avoid duplicates; update thumbnail flags)
        commitStagedAttachments(to: s, ctx: viewContext)

        do {
            try viewContext.save()
            viewContext.processPendingChanges()
            // Return to ContentView (root) — triple, staggered dismiss to unwind sheet/fullScreenCover and underlying presenter
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { dismiss() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dismiss() }
        } catch {
            print("Save error (Add/Edit): \(error)")
        }
    }

    // MARK: - Pinned activity list + helpers

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
        // Core list
        let core: [String] = SessionActivityType.allCases.map { "core:\($0.rawValue)" }
        // Custom list
        let customs: [String] = userActivities.compactMap { ua in
            let n = (ua.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "custom:\(n)"
        }

        // Normalize primary
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

    private func applyActivityChoice() {
        if activityChoice.hasPrefix("core:") {
            if let raw = Int(activityChoice.split(separator: ":").last ?? "0") {
                activity = SessionActivityType(rawValue: Int16(raw)) ?? .practice
            } else {
                activity = .practice
            }
            selectedCustomName = ""
        } else if activityChoice.hasPrefix("custom:") {
            let name = String(activityChoice.dropFirst("custom:".count))
            activity = .practice
            selectedCustomName = name
        }
    }

    private func syncActivityChoiceFromState() {
        if selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityChoice = "core:\(activity.rawValue)"
        } else {
            activityChoice = "custom:\(selectedCustomName)"
        }
    }

    private func loadUserActivities() {
        do {
            userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext)
        } catch {
            userActivities = []
        }
    }

    // MARK: - Default description logic

    private func timeOfDayString(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:   return "Morning"
        case 12..<17:  return "Afternoon"
        case 17..<22:  return "Evening"
        default:       return "Night"
        }
    }

    private func editorDefaultDescription(timestamp: Date, activityDisplayName: String) -> String {
        "\(timeOfDayString(for: timestamp)) \(activityDisplayName)"
    }

    private func currentActivityDisplayName() -> String {
        let custom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return activity.label
    }

    private func maybeUpdateActivityDetailFromDefaults_v2() {
        guard !userHasEditedActivityDetail else { return }
        let auto = editorDefaultDescription(timestamp: timestamp, activityDisplayName: currentActivityDisplayName())
        activityDetail = auto
        lastAutoActivityDetail = auto
    }

    private func handleActivityDetailChange_v2(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userHasEditedActivityDetail = false
            return
        }
        if new != lastAutoActivityDetail {
            userHasEditedActivityDetail = true
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

    /// Update activityDetail only if it's empty OR still equal to the last auto-generated default
    private func maybeUpdateActivityDetailFromDefaults() {
        let newDefault = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activityDetail == lastAutoActivityDetail {
            lastAutoActivityDetail = newDefault
            activityDetail = newDefault
            userEditedActivityDetail = false
        }
    }

    // MARK: - Attachments (preload, stage & commit)

    /// Preload existing Core Data attachments so they appear in the grid during Edit (no duplication on save).
    private func preloadExistingAttachments() {
        guard let s = session else { return }
        // Try to fetch via relationship; fall back to fetch request if needed.
        var existing: [Attachment] = []
        if let set = s.value(forKey: "attachments") as? Set<Attachment> {
            existing = Array(set)
        } else {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", s.objectID)
            existing = (try? viewContext.fetch(req)) ?? []
        }

        // Sort by createdAt if available for stable order
        existing.sort {
            let a = ($0.value(forKey: "createdAt") as? Date) ?? .distantPast
            let b = ($1.value(forKey: "createdAt") as? Date) ?? .distantPast
            return a < b
        }

        // Map Core Data attachments into staged rows (image data for previews; icons for others).
        for a in existing {
            let kindStr = (a.value(forKey: "kind") as? String) ?? "file"
            let kind = AttachmentKind(rawValue: kindStr) ?? .file
            let id = (a.value(forKey: "id") as? UUID) ?? UUID()

            var data = Data()
            if kind == .image, let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                if let d = loadImageData(at: path) { data = d }
            }

            // Stage item and remember it's existing to avoid duplication on save.
            let staged = StagedAttachment(id: id, data: data, kind: kind)
            stagedAttachments.append(staged)
            existingAttachmentIDs.insert(id)

            if (a.value(forKey: "isThumbnail") as? Bool) == true {
                selectedThumbnailID = id
            }
        }
    }

    /// Attempts to read image bytes from: absolute path → file:// URL → relative path in Documents directory.
    private func loadImageData(at pathOrURLString: String) -> Data? {
        let trimmed = pathOrURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        func loadAtAbsolutePath(_ abs: String) -> Data? {
            if FileManager.default.fileExists(atPath: abs) {
                if let ui = UIImage(contentsOfFile: abs) {
                    if let jpg = ui.jpegData(compressionQuality: 0.85) { return jpg }
                }
                if let raw = try? Data(contentsOf: URL(fileURLWithPath: abs)) { return raw }
            }
            return nil
        }

        // Case A: absolute filesystem path
        if trimmed.hasPrefix("/") {
            if let d = loadAtAbsolutePath(trimmed) { return d }
            // Fallback: treat as stale absolute path; try lastPathComponent in Documents
            if let filename = URL(fileURLWithPath: trimmed).pathComponents.last, !filename.isEmpty {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                if let hit = docs?.appendingPathComponent(filename), FileManager.default.fileExists(atPath: hit.path) {
                    if let ui = UIImage(contentsOfFile: hit.path) {
                        if let jpg = ui.jpegData(compressionQuality: 0.85) { return jpg }
                    }
                    if let raw = try? Data(contentsOf: hit) { return raw }
                }
            }
        }

        // Case B: URL string (e.g., "file:///...")
        if let url = URL(string: trimmed), url.isFileURL {
            if let d = loadAtAbsolutePath(url.path) { return d }
            if let raw = try? Data(contentsOf: url) { return raw }
        }

        // Case C: relative path previously stored (resolve against Documents directory)
        if !trimmed.isEmpty, !trimmed.contains(":"), !trimmed.hasPrefix("/") {
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let candidate = docs.appendingPathComponent(trimmed).path
                if let d = loadAtAbsolutePath(candidate) { return d }
            }
        }

        return nil
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
        existingAttachmentIDs.remove(a.id)
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

    /// Adds only newly staged attachments (not those that originated from Core Data) and updates thumbnail flags for all.
    private func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) {
        // Determine chosen thumbnail (if any)
        let imageIDs = stagedAttachments.filter { $0.kind == .image }.map { $0.id }
        var chosenThumbID = selectedThumbnailID
        if chosenThumbID == nil, imageIDs.count == 1 { chosenThumbID = imageIDs.first }

        // 1) Add ONLY newly staged attachments (skip those that were preloaded from Core Data)
        for att in stagedAttachments where existingAttachmentIDs.contains(att.id) == false {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let path = try AttachmentStore.saveData(att.data, suggestedName: att.id.uuidString, ext: ext)
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                _ = try AttachmentStore.addAttachment(kind: att.kind, filePath: path, to: session, isThumbnail: isThumb, ctx: ctx)
            } catch {
                print("Attachment commit failed: ", error)
            }
        }

        // 2) Update thumbnail flags across ALL existing attachments to reflect selection
        do {
            // Fetch all attachments for this session
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", session.objectID)
            let existing = try ctx.fetch(req)
            for a in existing {
                let id = (a.value(forKey: "id") as? UUID)
                let isThumb = (id != nil) && (id == chosenThumbID)
                a.setValue(isThumb, forKey: "isThumbnail")
            }
        } catch {
            print("Failed to update thumbnail flags: ", error)
        }

        // Clear the staging area after commit
        stagedAttachments.removeAll()
        existingAttachmentIDs.removeAll()
    }

    // MARK: - Fetches & misc helpers

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
        } catch {
            print("Profile fetch failed: \(error)")
        }
        return nil
    }

    private func defaultTitle(for inst: Instrument? = nil, activity: SessionActivityType) -> String {
        if let name = (inst ?? instrument)?.name, !name.isEmpty { return "\(name) : \(activity.label)" }
        return activity.label
    }

    private func secondsToHM(_ seconds: Int) -> (Int, Int) {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return (h, m)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.doesRelativeDateFormatting = true
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
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

//  [ROLLBACK ANCHOR] v7.8 DesignLite — post













