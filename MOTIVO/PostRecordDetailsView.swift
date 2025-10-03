//  PostRecordDetailsView.swift
//  MOTIVO
//  [ROLLBACK ANCHOR] v7.8 pre-hotfix commit: remove first-use lag in picker/notes
//  [ROLLBACK ANCHOR] v7.8 Stage2 — pre (before Primary pinned-first)
//
//  v7.8 Stage 2 — Primary pinned-first in Activity wheel
//  - Pins Primary Activity at top (deduped), then core, then customs.
//  - Restores local helper functions used in the original file (formattedDate, secondsToHM, formattedDuration, ensureCameraAuthorized).
//  - Breaks up complex expressions to keep the compiler happy.
//  - No schema/migrations.
//
import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit

// SessionActivityType moved to SessionActivityType.swift

struct PostRecordDetailsView: View {
    @Environment(\.managedObjectContext) private var viewContext

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
    // P3: default description tracking
    @State private var lastAutoActivityDetail: String = ""
    @State private var userEditedActivityDetail: Bool = false

    // Title control
    @State private var isTitleEdited = false
    @State private var initialAutoTitle = ""

    // Wheels
    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var showActivityPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0
    @State private var tempActivity: SessionActivityType = .practice

    // Staged attachments + thumbnail choice
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var selectedThumbnailID: UUID? = nil
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraDeniedAlert = false

    // Primary Activity persisted ref
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

    var onSaved: (() -> Void)?

    init(
        isPresented: Binding<Bool>,
        timestamp: Date? = nil,
        durationSeconds: Int? = nil,
        instrument: Instrument? = nil,
        activityTypeRaw: Int16? = nil,
        activityDetailPrefill: String? = nil,
        onSaved: (() -> Void)? = nil
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
        self.onSaved = onSaved
    }

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
        NavigationStack {
            Form {
                if hasNoInstruments {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No instruments found").font(.headline)
                            Text("Add an instrument in your Profile to save this session.")
                                .foregroundStyle(.secondary).font(.subheadline)
                        }
                    }
                } else if hasMultipleInstruments {
                    Section {
                        Picker("Instrument", selection: $instrument) {
                            Text("Select instrument…").tag(nil as Instrument?)
                            ForEach(instruments, id: \.self) { inst in
                                let name = inst.name ?? ""
                                Text(name).tag(inst as Instrument?)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        tempActivity = activity
                        showActivityPicker = true
                    } label: {
                        let display = selectedCustomName.isEmpty ? activity.label : selectedCustomName
                        HStack { Text("Activity"); Spacer(); Text(display).foregroundStyle(.secondary) }
                    }
                }

                // Activity description (short detail)
                Section {
                    TextField("Activity description", text: $activityDetail, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Button {
                        tempDate = timestamp
                        showStartPicker = true
                    } label: {
                        let dateStr = formattedDate(timestamp)
                        HStack { Text("Start Time"); Spacer(); Text(dateStr).foregroundStyle(.secondary) }
                    }
                }

                Section {
                    Button {
                        let hm = secondsToHM(durationSeconds)
                        tempHours = hm.0
                        tempMinutes = hm.1
                        showDurationPicker = true
                    } label: {
                        let durStr = formattedDuration(durationSeconds)
                        HStack { Text("Duration"); Spacer(); Text(durStr).foregroundStyle(.secondary) }
                    }
                    if durationSeconds == 0 {
                        Text("Duration must be greater than 0").font(.footnote).foregroundColor(.red)
                    }
                }

                Section { Toggle("Public", isOn: $isPublic) }

                Section("Mood & Effort") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Mood"); Spacer(); Text("\(mood)").foregroundStyle(.secondary) }
                        Slider(value: Binding(get: { Double(mood) }, set: { mood = Int($0.rounded()) }), in: 0...10, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Effort"); Spacer(); Text("\(effort)").foregroundStyle(.secondary) }
                        Slider(value: Binding(get: { Double(effort) }, set: { effort = Int($0.rounded()) }), in: 0...10, step: 1)
                    }
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes).frame(minHeight: 100)
                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Notes").foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 8)
                        }
                    }
                }
                // Staged attachments with thumbnail selection
                StagedAttachmentsSectionView(
                    attachments: stagedAttachments,
                    onRemove: removeStagedAttachment,
                    selectedThumbnailID: $selectedThumbnailID
                )

                Section {
                    Button("Add Photo") { showPhotoPicker = true }
                    Button("Add File") { showFileImporter = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") {
                            ensureCameraAuthorized { showCamera = true }
                        }
                    }
                }
            }
            .navigationTitle("Session Review")
            // [v7.8 hotfix] merged into unified .task to avoid duplicate first-paint work
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveToCoreData()
                        DispatchQueue.main.async { withAnimation(.none) { isPresented = false } }
                    }
                    .disabled(durationSeconds == 0 || instrument == nil)
                }
            }
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
                // [v7.8 hotfix] Unified first-appearance init to avoid duplicate work and main-thread stalls.
                instruments = fetchInstruments()

                if instrument == nil {
                    if let primaryName = fetchPrimaryInstrumentName(),
                       let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                        instrument = match
                    } else if hasOneInstrument {
                        instrument = instruments.first
                    }
                }

                // IMPORTANT: do NOT reset `activity` here; it was preselected from the Timer.
                tempActivity = activity

                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let auto = defaultTitle(for: instrument, activity: activity)
                    title = auto
                    initialAutoTitle = auto
                    isTitleEdited = false
                }
                // Prefill default description on first open if blank
                if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let autoDesc = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
                    activityDetail = autoDesc
                    lastAutoActivityDetail = autoDesc
                    userEditedActivityDetail = false
                }

                // Preload user-local activities once so the activity picker opens instantly.
                loadUserActivities()
                // Keep the string selector in sync with current state.
                syncActivityChoiceFromState()
            }
            .onChange(of: instrument) { _, _ in
                refreshAutoTitleIfNeeded()
            }
            .onChange(of: activity) { _, _ in
                // P3: keep description synced if still default
                maybeUpdateActivityDetailFromDefaults()
            }
            .onChange(of: activityDetail) { old, new in
                let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                userEditedActivityDetail = (!trimmed.isEmpty && trimmed != lastAutoActivityDetail)
            }
        }
    }

    // MARK: - Subviews

    private var activityPickerPinned: some View {
        NavigationStack {
            VStack {
                // Break out choices to ease type-checking
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showActivityPicker = false }
                }
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
                            // leave description alone
                        } else if activityChoice.hasPrefix("custom:") {
                            let name = String(activityChoice.dropFirst("custom:".count))
                            tempActivity = .practice
                            activity = .practice
                            selectedCustomName = name
                            // keep description blank
                        }
                        showActivityPicker = false
                        // P3: Update default description if appropriate
                        maybeUpdateActivityDetailFromDefaults()
                        refreshAutoTitleIfNeeded()
                    }
                }
            }
            .onAppear {
                // Keep wheel aligned with current state when presented
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { durationSeconds = (tempHours * 3600) + (tempMinutes * 60); showDurationPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers for pinned list

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

    private func loadUserActivities() {
        do {
            userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext)
        } catch {
            userActivities = []
        }
    }

    private func syncActivityChoiceFromState() {
        if selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityChoice = "core:\(activity.rawValue)"
        } else {
            activityChoice = "custom:\(selectedCustomName)"
        }
    }

    // MARK: - P3 Helpers — Default description logic (editor)
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

    // Update activityDetail only if it's empty OR still equal to the last auto-generated default
    private func maybeUpdateActivityDetailFromDefaults() {
        let newDefault = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activityDetail == lastAutoActivityDetail {
            activityDetail = newDefault
            lastAutoActivityDetail = newDefault
            userEditedActivityDetail = false
        }
    }

    // MARK: - Save

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
        s.notes = notes
        s.setValue(activityDetail.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "activityDetail")

        // Persist activity type
        s.setValue(activity.rawValue, forKey: "activityType")

        // Stamp owner (required)
        if let uid = PersistenceController.shared.currentUserID, !uid.isEmpty {
            s.setValue(uid, forKey: "ownerUserID")
        }
        // Commit staged attachments with thumbnail choice
        commitStagedAttachments(to: s, ctx: viewContext)

        do {
            try viewContext.save()
            // 👇 Nudge SwiftUI immediately after saving in the same context.
            viewContext.processPendingChanges()
            onSaved?()
        } catch {
            print("Error saving session (timer review): \(error)")
        }
    }

    // MARK: - Attachments (stage & commit)

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

        for att in stagedAttachments {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let path = try AttachmentStore.saveData(att.data, suggestedName: att.id.uuidString, ext: ext)
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                _ = try AttachmentStore.addAttachment(kind: att.kind, filePath: path, to: session, isThumbnail: isThumb, ctx: ctx)
            } catch {
                print("Attachment commit failed: ", error)
            }
        }

        stagedAttachments.removeAll()
    }

    // MARK: - Misc helpers

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
        } catch {
            print("Profile fetch failed: \(error)")
        }
        return nil
    }

    // Restored local helpers (from original file patterns)

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
