//
//  AddEditSessionView.swift
//  MOTIVO
//

import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit

fileprivate enum ActivityType: Int16, CaseIterable, Identifiable {
    case practice = 0, rehearsal = 1, recording = 2, lesson = 3
    var id: Int16 { rawValue }
    var label: String {
        switch self {
        case .practice: return "Practice"
        case .rehearsal: return "Rehearsal"
        case .recording: return "Recording"
        case .lesson: return "Lesson"
        }
    }
    static func from(_ raw: Int16?) -> ActivityType { ActivityType(rawValue: raw ?? 0) ?? .practice }
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
    @State private var isPublic = true
    @State private var mood = 5
    @State private var effort = 5
    @State private var tagsText = ""
    @State private var notes = ""

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

    // Attachments (staged)
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var selectedThumbnailID: UUID? = nil
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraDeniedAlert = false

    // Instruments
    @State private var instruments: [Instrument] = []
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

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
                        HStack { Text("Activity"); Spacer(); Text(activity.label).foregroundStyle(.secondary) }
                    }
                }

                // Title
                Section {
                    TextField("Title", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.trimmingCharacters(in: .whitespacesAndNewlines) != initialAutoTitle {
                                isTitleEdited = true
                            }
                        }
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

                // Tags
                Section { TextField("Tags (comma-separated)", text: $tagsText) }

                // Staged attachments (with thumbnail selection)
                StagedAttachmentsSectionView(
                    attachments: stagedAttachments,
                    onRemove: removeStagedAttachment,
                    selectedThumbnailID: $selectedThumbnailID
                )

                // Add attachments
                Section {
                    Button("Add Photo") { showPhotoPicker = true }
                    Button("Add File") { showFileImporter = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") { ensureCameraAuthorized { showCamera = true } }
                    }
                }
            }
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
                        // Close first
                        isPresented = false
                        dismiss()
                        // Then commit & notify
                        DispatchQueue.main.async {
                            saveToCoreData()
                            onSaved?()
                        }
                    } label: { Text("Save") }
                    .disabled(isSaving || durationSeconds == 0 || instrument == nil)
                }
            }

            // Pickers
            .sheet(isPresented: $showActivityPicker) { activityPicker }
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

    private func saveToCoreData() {
        let s = session ?? Session(context: viewContext)

        if (s.value(forKey: "id") as? UUID) == nil { s.setValue(UUID(), forKey: "id") }
        if s.timestamp == nil { s.timestamp = Date() }

        s.instrument = instrument
        s.title = title.isEmpty ? defaultTitle(for: instrument, activity: activity) : title
        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = isPublic
        s.mood = Int16(mood)
        s.effort = Int16(effort)
        s.notes = notes

        // Persist activity type
        s.setValue(activity.rawValue, forKey: "activityType")

        // Persist tags — normalize & ensure each Tag has required UUID 'id'
        let tagNames = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } // <<< CHANGED
            .filter { !$0.isEmpty }
        s.tags = NSSet(array: upsertTags(tagNames))

        // Commit staged attachments (with thumbnail choice)
        commitStagedAttachments(to: s, ctx: viewContext)

        do { try viewContext.save() } catch { print("Error saving session: \(error)") }
    }

    // MARK: - Attachment staging & commit

    private func stageData(_ data: Data, kind: AttachmentKind) {
        let id = UUID()
        stagedAttachments.append(StagedAttachment(id: id, data: data, kind: kind))
        if kind == .image {
            // If it's the first and only image, auto-select it as thumbnail
            let imageCount = stagedAttachments.filter { $0.kind == .image }.count
            if imageCount == 1 {
                selectedThumbnailID = id
            }
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
        // Resolve thumbnail choice
        let imageIDs = stagedAttachments.filter { $0.kind == .image }.map { $0.id }
        var chosenThumbID = selectedThumbnailID
        if chosenThumbID == nil, imageIDs.count == 1 { chosenThumbID = imageIDs.first }

        for att in stagedAttachments {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let path = try AttachmentStore.saveData(att.data, suggestedName: att.id.uuidString, ext: ext)
                let isThumb = (att.id == chosenThumbID) && (att.kind == .image)
                _ = try AttachmentStore.addAttachment(kind: att.kind, filePath: path, to: session, isThumbnail: isThumb, ctx: ctx)
            } catch {
                print("Attachment commit failed: \(error)")
            }
        }
        stagedAttachments.removeAll()
        selectedThumbnailID = nil
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

    private func upsertTags(_ names: [String]) -> [Tag] {
        var results: [Tag] = []
        for name in names {
            let req: NSFetchRequest<Tag> = Tag.fetchRequest()
            req.predicate = NSPredicate(format: "name ==[c] %@", name)
            if let existing = (try? viewContext.fetch(req))?.first {
                results.append(existing)
            } else {
                let t = Tag(context: viewContext)
                t.name = name
                // Ensure required UUID id is set so validation passes
                if (t.value(forKey: "id") as? UUID) == nil { t.setValue(UUID(), forKey: "id") }   // <<< CHANGED
                results.append(t)
            }
        }
        return results
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

    private func secondsToHM(_ seconds: Int) -> (Int, Int) {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return (h, m)
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
