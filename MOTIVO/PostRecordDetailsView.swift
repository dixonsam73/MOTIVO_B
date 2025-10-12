// CHANGE-ID: 20251012_202320-tasks-pad-a2
// SCOPE: Add optional notesPrefill parameter and init notes from it

private let kPrivacyMapKey = "attachmentPrivacyMap_v1"

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

    // ---- Privacy cache & helpers (inside the view struct) ----
    @State private var privacyMap: [String: Bool] = [:]

    private func privacyKey(id: UUID?, url: URL?) -> String? {
        if let id { return "id://\(id.uuidString)" }
        if let url { return url.absoluteString }
        return nil
    }

    private func loadPrivacyMap() {
        privacyMap = (UserDefaults.standard.dictionary(forKey: kPrivacyMapKey) as? [String: Bool]) ?? [:]
    }

    private func isPrivate(id: UUID?, url: URL?) -> Bool {
        // Prefer live cache; fall back to persisted map for back-compat
        if let key = privacyKey(id: id, url: url) {
            if let v = privacyMap[key] { return v }
            let map = (UserDefaults.standard.dictionary(forKey: kPrivacyMapKey) as? [String: Bool]) ?? [:]
            return map[key] ?? false
        }
        return false
    }

    private func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        // Update cache first (instant UI), then persist
        privacyMap[key] = value
        var map = (UserDefaults.standard.dictionary(forKey: kPrivacyMapKey) as? [String: Bool]) ?? [:]
        map[key] = value
        UserDefaults.standard.set(map, forKey: kPrivacyMapKey)
    }

    private func migratePrivacy(fromStagedID stagedID: UUID, stagedURL: URL?, toNewID newID: UUID?, newURL: URL?) {
        // Read current maps fresh to avoid stale cache writes
        var map = (UserDefaults.standard.dictionary(forKey: kPrivacyMapKey) as? [String: Bool]) ?? [:]

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
        UserDefaults.standard.set(map, forKey: kPrivacyMapKey)
        privacyMap = map
    }
    // ---- end privacy helpers ----

    var onSaved: (() -> Void)?

    init(
        isPresented: Binding<Bool>,
        timestamp: Date? = nil,
        durationSeconds: Int? = nil,
        instrument: Instrument? = nil,
        activityTypeRaw: Int16? = nil,
        activityDetailPrefill: String? = nil,
        notesPrefill: String? = nil,
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
        self._notes = State(initialValue: notesPrefill ?? "")
        self.onSaved = onSaved
    }

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {

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
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .padding(6)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                }
                                .contentShape(Rectangle())
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
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .contentShape(Rectangle())
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
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .contentShape(Rectangle())
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
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .contentShape(Rectangle())
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
                    }
                    .cardSurface()

                    // ---------- Notes ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Notes").sectionHeader()
                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
                    }
                    .cardSurface()

                    // ---------- Attachments ----------
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
                    }
                    .cardSurface()

                    // ---------- Add Attachments Controls ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Button("Add Photo") { showPhotoPicker = true }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        Button("Add File") { showFileImporter = true }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take Photo") {
                                ensureCameraAuthorized { showCamera = true }
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                    }
                    .cardSurface()
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationTitle("Session Review")
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
            .appBackground()
        }
}

    // MARK: - Subviews

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
        s.setValue(activity.rawValue, forKey: "activityType")
        if let uid = PersistenceController.shared.currentUserID, !uid.isEmpty {
            s.setValue(uid, forKey: "ownerUserID")
        }
        commitStagedAttachments(to: s, ctx: viewContext)
        do {
            try viewContext.save()
            viewContext.processPendingChanges()
            onSaved?()
        } catch { print("Error saving session (timer review): \(error)") }
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
        for att in stagedAttachments {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let path = try AttachmentStore.saveData(att.data, suggestedName: att.id.uuidString, ext: ext)
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                let created: Attachment = try AttachmentStore.addAttachment(kind: att.kind, filePath: path, to: session, isThumbnail: isThumb, ctx: ctx)
                // Attempt to migrate privacy from staged keys (ID/Temp URL) to final keys (ID/File URL)
                let finalURL = URL(fileURLWithPath: path)
                let stagedURL = surrogateURL(for: att)
                migratePrivacy(fromStagedID: att.id, stagedURL: stagedURL, toNewID: (created.value(forKey: "id") as? UUID), newURL: finalURL)
            } catch {
                print("Attachment commit failed: ", error)
            }
        }
        stagedAttachments.removeAll()
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
}

fileprivate struct AttachmentThumbCell: View {
    let att: StagedAttachment
    let isThumbnail: Bool
    let onMakeThumbnail: () -> Void
    let onRemove: () -> Void
    let isPrivate: (_ id: UUID?, _ url: URL?) -> Bool
    let setPrivate: (_ id: UUID?, _ url: URL?, _ value: Bool) -> Void

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
                // Star (thumbnail selection for images)
                if att.kind == .image {
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
            if att.kind == .image {
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
            placeholder(system: "waveform")
        case .video:
            placeholder(system: "film")
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
}
