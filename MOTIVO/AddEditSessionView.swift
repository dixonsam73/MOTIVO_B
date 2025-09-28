////////////
//  AddEditSessionView.swift
//  MOTIVO
//

import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

fileprivate enum ActivityType: Int16, CaseIterable, Identifiable {
    case practice = 0, rehearsal = 1, recording = 2, lesson = 3, performance = 4
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .practice: return "Practice"
        case .rehearsal: return "Rehearsal"
        case .recording: return "Recording"
        case .lesson: return "Lesson"
        case .performance: return "Performance"
    }
    }
    static func from(_ raw: Int16?) -> ActivityType { ActivityType(rawValue: raw ?? 0) ?? .practice }
}

// Represents user's thumbnail pick (existing vs staged)
fileprivate enum ThumbnailChoice {
    case existing(NSManagedObjectID)
    case staged(UUID)
}

struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @Binding var isPresented: Bool
    var session: Session? = nil
    var onSaved: (() -> Void)? = nil

    // Core fields
    @State private var instrument: Instrument?
    @State private var title = ""
    @State private var timestamp = Date()
    @State private var durationSeconds = 0
    @State private var activity: ActivityType = .practice
    @State private var userActivities: [UserActivity] = []
    @State private var activityChoice: String = "core:0"
    @State private var selectedCustomName: String = ""
@State private var selectedCustomActivity: String = ""
    @State private var isPublic = true
    @State private var mood = 5
    @State private var effort = 5
    @State private var notes = ""
    @State private var activityDetail = ""

    // Pickers
    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var showActivityPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0
    @State private var tempActivity: ActivityType = .practice

    // Save/title behavior
    @State private var isSaving = false
    @State private var isTitleEdited = false
    @State private var initialAutoTitle = ""

    // Existing attachments (for EDIT mode)
    @State private var existingAttachments: [Attachment] = []

    // Attachments (staged for new additions during this edit)
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraDeniedAlert = false

    // Thumbnail selection (either existing or staged). We only write it if user actually changed it.
    @State private var thumbnailChoice: ThumbnailChoice? = nil
    @State private var thumbnailChoiceDirty = false

    // Instruments
    @State private var instruments: [Instrument] = []
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    // Layout
    private let grid = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                // Instrument
                if hasNoInstruments {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No instruments found").font(.headline)
                            Text("Add an instrument in your Profile to create a session.")
                                .foregroundStyle(.secondary).font(.subheadline)
                        }
                    }
                } else if hasMultipleInstruments {
                    Section {
                        Picker("Instrument", selection: $instrument) {
                            Text("Select instrument…").tag(nil as Instrument?)
                            ForEach(instruments, id: \.self) { inst in
                                Text(inst.name ?? "").tag(inst as Instrument?)
                            }
                        }
                    }
                } else {
                    Section {
                        HStack { Text("Instrument"); Spacer(); Text(instruments.first?.name ?? "—").foregroundStyle(.secondary) }
                    }
                }

                // Activity
                Section {
                    Button {
                        tempActivity = activity
                        showActivityPicker = true
                    } label: {
                        HStack { Text("Activity"); Spacer(); Text(!selectedCustomName.isEmpty ? selectedCustomName : activity.label).foregroundStyle(.secondary) }
                    }
                }

                // Title
                
                // Activity description (short detail)
                Section {
                    TextField("Activity description", text: $activityDetail, axis: .vertical)
                        .lineLimit(1...3)
                }
    

                // Start time
                Section {
                    Button {
                        tempDate = timestamp
                        showStartPicker = true
                    } label: {
                        HStack { Text("Start Time"); Spacer(); Text(formattedDate(timestamp)).foregroundStyle(.secondary) }
                    }
                }

                // Duration
                Section {
                    Button {
                        (tempHours, tempMinutes) = secondsToHM(durationSeconds)
                        showDurationPicker = true
                    } label: {
                        HStack { Text("Duration"); Spacer(); Text(formattedDuration(durationSeconds)).foregroundStyle(.secondary) }
                    }
                    if durationSeconds == 0 {
                        Text("Duration must be greater than 0").font(.footnote).foregroundColor(.red)
                    }
                }

                Section { Toggle("Public", isOn: $isPublic) }

                // Mood & Effort
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

                // Notes
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes).frame(minHeight: 100)
                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Notes").foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 8)
                        }
                    }
                }

                attachmentsSection

                // Add attachments
                Section {
                    Button("Add Photo") { showPhotoPicker = true }
                    Button("Add File") { showFileImporter = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") { ensureCameraAuthorized { showCamera = true } }
                    }
                }
            }
            .onAppear { loadUserActivities(); syncActivityChoiceFromState() }
            .task { loadUserActivities(); syncActivityChoiceFromState() }

            .navigationTitle(session == nil ? "New Session" : "Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                        dismiss()
                    }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !isSaving else { return }
                        isSaving = true
// Commit first
saveToCoreData()
viewContext.processPendingChanges()
// Dismiss parent (Session detail) to land on Feed
onSaved?()
// Close this editor on the next runloop with no animation
DispatchQueue.main.async {
    withAnimation(.none) {
        isPresented = false
        dismiss()
    }
}
} label: { Text("Save") }
                    .disabled(isSaving || durationSeconds == 0 || instrument == nil)
                }
            }

            // Pickers
            .sheet(isPresented: $showActivityPicker) { activityPickerUnified }
            .sheet(isPresented: $showStartPicker) { startPicker }
            .sheet(isPresented: $showDurationPicker) { durationPicker }

            // Importers
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
            .task(id: photoPickerItem) {
                guard let item = photoPickerItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    stageData(data, kind: .image)
                }
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
                           if let url = URL(string: UIApplication.openSettingsURLString) {
                               UIApplication.shared.open(url)
                           }
                       }
                   },
                   message: { Text("Enable camera access in Settings → Privacy → Camera to take photos.") })
            .onAppear { onAppearSetup() }
            .onChange(of: instrument) { _, _ in refreshAutoTitleIfNeeded() }
        }
    }

    // MARK: - Pickers

    private var activityPicker: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $tempActivity) {
                    ForEach(ActivityType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                Spacer()
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showActivityPicker = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { activity = tempActivity; showActivityPicker = false; refreshAutoTitleIfNeeded() } }
            }
        }
        .presentationDetents([.medium])
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
                ToolbarItem(placement: .confirmationAction) { Button("Done") { timestamp = tempDate; showStartPicker = false } }
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

    // MARK: - Lifecycle

    private func onAppearSetup() {
        instruments = fetchInstruments()

        if let s = session {
            // EDIT MODE
            instrument = s.instrument
            title = s.title ?? ""
            timestamp = s.timestamp ?? Date()
            durationSeconds = Int(s.durationSeconds)
            isPublic = s.isPublic
            mood = Int(s.mood)
            effort = Int(s.effort)
            notes = s.notes ?? ""
            // activity from Core Data
            let raw = s.value(forKey: "activityType") as? Int16
            activity = ActivityType.from(raw)
            tempActivity = activity
        // Hydrate custom label + description for Edit mode
        let hydratedLabel = (s.value(forKey: "userActivityLabel") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedCustomName = hydratedLabel
        activityDetail = (s.value(forKey: "activityDetail") as? String) ?? ""
        // Align unified picker with hydrated state
        syncActivityChoiceFromState()


            // Existing attachments
            if let set = s.attachments as? Set<Attachment> {
                existingAttachments = set.sorted { (a, b) in
                    let da = (a.value(forKey: "createdAt") as? Date) ?? .distantPast
                    let db = (b.value(forKey: "createdAt") as? Date) ?? .distantPast
                    return da < db
                }
                // Seed the visual star from current thumbnail (but don't mark dirty)
                if let currentThumb = existingAttachments.first(where: { ($0.value(forKey: "isThumbnail") as? Bool) == true }) {
                    thumbnailChoice = .existing(currentThumb.objectID)
                    thumbnailChoiceDirty = false
                }
            } else {
                existingAttachments = []
            }

            // Auto-title only if empty
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let auto = defaultTitle(for: instrument, activity: activity)
                title = auto
                initialAutoTitle = auto
                isTitleEdited = false
            } else {
                initialAutoTitle = title
                isTitleEdited = true
            }
        } else {
            // NEW MODE
            if instrument == nil {
                if let primaryName = fetchPrimaryInstrumentName(),
                   let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                    instrument = match
                } else if hasOneInstrument {
                    instrument = instruments.first
                }
            }
            activity = .practice
            tempActivity = activity
            let auto = defaultTitle(for: instrument, activity: activity)
            title = auto
            initialAutoTitle = auto
            isTitleEdited = false
        }
    }

    // MARK: - Save

    @MainActor
    private func saveToCoreData() {
        let s = session ?? Session(context: viewContext)

        if (s.value(forKey: "id") as? UUID) == nil {         s.setValue(selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "userActivityLabel")
s.setValue(UUID(), forKey: "id") }
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
        s.setValue(selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "userActivityLabel")

        // Persist activity type
        s.setValue(activity.rawValue, forKey: "activityType")

        // 🔐 V4 hardening: ensure Session has ownerUserID before save
        if let uid = PersistenceController.shared.currentUserID, !uid.isEmpty {
            s.setValue(uid, forKey: "ownerUserID")
        }

                // Commit staged attachments; only mark a staged one as thumbnail if the user explicitly picked it.
        let chosenStagedID: UUID? = (thumbnailChoiceDirty
                                     ? { if case .staged(let id) = thumbnailChoice { return id } else { return nil } }()
                                     : nil)
        commitStagedAttachments(to: s, chosenStagedID: chosenStagedID, ctx: viewContext)

        // If user starred an EXISTING image, update flags now.
        if thumbnailChoiceDirty, case .existing(let oid) = thumbnailChoice {
            if let set = s.attachments as? Set<Attachment> {
                for a in set {
                    let isImage = (a.kind ?? "") == "image"
                    let makeThumb = isImage && (a.objectID == oid)
                    a.setValue(makeThumb, forKey: "isThumbnail")
                }
            }
        }

        do {
            try viewContext.save()
            // Ensure SwiftUI fetches refresh immediately after a same-context save.
            viewContext.processPendingChanges()
        } catch {
            print("Error saving session: \(error)")
        }
    }

    // MARK: - Attachment staging & commit

    private func stageData(_ data: Data, kind: AttachmentKind) {
        let id = UUID()
        stagedAttachments.append(StagedAttachment(id: id, data: data, kind: kind))

        // Only auto-pick thumbnail for brand-new sessions (convenience).
        if session == nil, kind == .image, thumbnailChoice == nil {
            thumbnailChoice = .staged(id)
            thumbnailChoiceDirty = true
        }
    }

    private func removeStagedAttachment(_ a: StagedAttachment) {
        stagedAttachments.removeAll { $0.id == a.id }
        if case .staged(let id) = thumbnailChoice, id == a.id {
            thumbnailChoice = nil
            thumbnailChoiceDirty = true
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

    private func commitStagedAttachments(to session: Session, chosenStagedID: UUID?, ctx: NSManagedObjectContext) {
        // If a staged image is chosen, clear existing image thumbnails.
        if let _ = chosenStagedID, let set = session.attachments as? Set<Attachment> {
            for a in set where (a.kind ?? "") == "image" {
                a.setValue(false, forKey: "isThumbnail")
            }
        }

        // Persist each staged item
        for att in stagedAttachments {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let path = try AttachmentStore.saveData(att.data, suggestedName: att.id.uuidString, ext: ext)
                let isThumb = (att.kind == .image) && (chosenStagedID == att.id)
                _ = try AttachmentStore.addAttachment(kind: att.kind, filePath: path, to: session, isThumbnail: isThumb, ctx: ctx)
            } catch {
                print("Attachment commit failed: \(error)")
            }
        }

        stagedAttachments.removeAll()
    }

    // MARK: - Helpers

    private func defaultTitle(for inst: Instrument? = nil, activity: ActivityType) -> String {
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
        case .authorized: onAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? onAuthorized() : { self.showCameraDeniedAlert = true }() }
            }
        default: self.showCameraDeniedAlert = true
        }
    }

    // ✅ Tag upsert helper
    @MainActor
    private func upsertTags(_ names: [String]) -> [Tag] {
        var results: [Tag] = []
        guard let uid = PersistenceController.shared.currentUserID else { return results }
        for name in names {
            let req: NSFetchRequest<Tag> = Tag.fetchRequest()
            req.predicate = NSPredicate(format: "name ==[c] %@ AND ownerUserID == %@", name, uid)
            if let existing = (try? viewContext.fetch(req))?.first {
                results.append(existing)
            } else {
                let t = Tag(context: viewContext)
                t.name = name
                t.ownerUserID = uid
                if (t.value(forKey: "id") as? UUID) == nil { t.setValue(UUID(), forKey: "id") }
                results.append(t)
            }
        }
        return results
    }

    // MARK: - Unified Attachments section

    @ViewBuilder
    private var attachmentsSection: some View {
        Section("Attachments") {
            let existingImages = existingAttachments.filter { ($0.kind ?? "") == "image" }
            let existingFiles  = existingAttachments.filter { ($0.kind ?? "") != "image" }
            let stagedImages   = stagedAttachments.filter { $0.kind == .image }
            let stagedFiles    = stagedAttachments.filter { $0.kind != .image }

            // Nothing yet?
            if existingImages.isEmpty && existingFiles.isEmpty && stagedImages.isEmpty && stagedFiles.isEmpty {
                Text("No attachments yet").foregroundStyle(.secondary)
            } else {
                // Thumbnails grid (existing + staged images together)
                if !existingImages.isEmpty || !stagedImages.isEmpty {
                    LazyVGrid(columns: grid, spacing: 12) {
                        // Existing image thumbs (tap star to choose)
                        ForEach(existingImages, id: \.objectID) { a in
                            ExistingThumbCell(
                                image: loadExistingImage(a),
                                isStarred: isExistingChosen(a),
                                onStar: {
                                    thumbnailChoice = .existing(a.objectID)
                                    thumbnailChoiceDirty = true
                                }
                            )
                        }
                        // Staged image thumbs (tap star to choose; X to remove)
                        ForEach(stagedImages) { att in
                            StagedThumbCell(
                                att: att,
                                isStarred: isStagedChosen(att.id),
                                onStar: {
                                    thumbnailChoice = .staged(att.id)
                                    thumbnailChoiceDirty = true
                                },
                                onRemove: { removeStagedAttachment(att) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Existing non-image files
                ForEach(existingFiles, id: \.objectID) { a in
                    HStack {
                        Image(systemName: icon(for: a.kind ?? "file"))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileName(of: a)).lineLimit(1)
                            Text(a.kind ?? "file").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                // Staged non-image files (with remove button)
                ForEach(stagedFiles) { att in
                    HStack {
                        Image(systemName: icon(for: att.kind.rawValue)).foregroundStyle(.secondary)
                        Text("New \(att.kind.rawValue)")
                        Spacer()
                        Button(role: .destructive) {
                            removeStagedAttachment(att)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func isExistingChosen(_ a: Attachment) -> Bool {
        if thumbnailChoiceDirty {
            if case .existing(let oid) = thumbnailChoice { return oid == a.objectID }
            return false
        } else {
            return (a.value(forKey: "isThumbnail") as? Bool) == true
        }
    }

    private func isStagedChosen(_ id: UUID) -> Bool {
        if thumbnailChoiceDirty {
            if case .staged(let sid) = thumbnailChoice { return sid == id }
            return false
        } else {
            return false
        }
    }

    // ✅ Path-resilient loader: try stored path/URL, else fall back to Documents/<filename>
    private func loadExistingImage(_ a: Attachment) -> UIImage? {
        guard let url = resolveAttachmentURL(a) else { return nil }
        if let data = try? Data(contentsOf: url) { return UIImage(data: data) }
        return UIImage(contentsOfFile: url.path)
    }

    private func resolveAttachmentURL(_ a: Attachment) -> URL? {
        guard let s = a.fileURL, !s.isEmpty else { return nil }
        let fm = FileManager.default

        // 1) If it's a valid file URL and exists, use it
        if let u = URL(string: s), u.isFileURL, fm.fileExists(atPath: u.path) {
            return u
        }

        // 2) If it's a plain path and exists, use it
        if fm.fileExists(atPath: s) {
            return URL(fileURLWithPath: s)
        }

        // 3) Fall back to Documents/<filename> in case the saved absolute path is stale
        let filename = URL(fileURLWithPath: s).lastPathComponent
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate = docs.appendingPathComponent(filename, isDirectory: false)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "image": return "photo"
        default: return "doc"
        }
    }

    private func fileName(of a: Attachment) -> String {
        guard let path = a.fileURL, !path.isEmpty else { return "file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Custom activities loader
    private func loadUserActivities() {
        do {
            userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext)
        } catch {
            userActivities = []
        }
    }

    // MARK: - Unified Activity Picker (core + user customs)
    private var activityPickerUnified: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $activityChoice) {
                    // Core activities
                    ForEach(ActivityType.allCases) { type in
                        Text(type.label).tag("core:\(type.rawValue)")
                    }
                    // User-local customs
                    if !userActivities.isEmpty {
                        ForEach(userActivities.compactMap { $0.displayName }, id: \.self) { name in
                            Text(name).tag("custom:\(name)")
                        }
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
                                tempActivity = ActivityType(rawValue: Int16(raw)) ?? .practice
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
                    }
                }
            }
        }
    }

    // MARK: - Activity helpers
    
    private func syncActivityChoiceFromState() {
        if !selectedCustomName.isEmpty { activityChoice = "custom:\(selectedCustomName)" }
        else { activityChoice = "core:\(activity.rawValue)" }
    }
}

// MARK: - Thumb cells

fileprivate struct ExistingThumbCell: View {
    let image: UIImage?
    let isStarred: Bool
    let onStar: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let ui = image {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.secondary.opacity(0.15), lineWidth: 1)
            )

            Text(isStarred ? "★" : "☆")
                .font(.system(size: 16))
                .padding(6)
                .background(.ultraThinMaterial, in: Circle())
                .padding(4)
                .onTapGesture { onStar() }
                .accessibilityLabel(isStarred ? "Thumbnail (selected)" : "Set as Thumbnail")
        }
    }
}

fileprivate struct StagedThumbCell: View {
    let att: StagedAttachment
    let isStarred: Bool
    let onStar: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumb
                .frame(width: 84, height: 84)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.secondary.opacity(0.15), lineWidth: 1)
                )

            HStack(spacing: 6) {
                if att.kind == .image {
                    Text(isStarred ? "★" : "☆")
                        .font(.system(size: 16))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .onTapGesture { onStar() }
                        .accessibilityLabel(isStarred ? "Thumbnail (selected)" : "Set as Thumbnail")
                }
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .accessibilityLabel("Remove")
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var thumb: some View {
        switch att.kind {
        case .image:
            if let ui = UIImage(data: att.data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary)
            }
        case .audio:
            Image(systemName: "waveform").imageScale(.large).foregroundStyle(.secondary)
        case .video:
            Image(systemName: "video").imageScale(.large).foregroundStyle(.secondary)
        case .file:
            Image(systemName: "doc").imageScale(.large).foregroundStyle(.secondary)
        }
    }
}
