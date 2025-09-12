//
//  PostRecordDetailsView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  PostRecordDetailsView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData
import PhotosUI

struct PostRecordDetailsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Close review first, then save
    @Binding var isPresented: Bool
    var onSaved: (() -> Void)? = nil

    // Prefill
    private let prefillTimestamp: Date
    private let prefillDurationSeconds: Int
    private let prefillInstrument: Instrument?

    // Form
    @State private var instrument: Instrument?
    @State private var title = ""
    @State private var timestamp = Date()
    @State private var durationSeconds = 0
    @State private var isPublic = true
    @State private var mood = 5
    @State private var effort = 5
    @State private var tagsText = ""
    @State private var notes = ""

    // Pickers
    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0

    // Guard
    @State private var isSaving = false
    @State private var isTitleEdited = false
    @State private var initialAutoTitle = ""

    // Attachments
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraKeyAlert = false

    init(
        isPresented: Binding<Bool>,
        timestamp: Date? = nil,
        durationSeconds: Int? = nil,
        instrument: Instrument? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.prefillTimestamp = timestamp ?? Date()
        self.prefillDurationSeconds = max(0, durationSeconds ?? 0)
        self.prefillInstrument = instrument
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Instrument", selection: $instrument) {
                        // ✅ allow nil selection
                        Text("Select instrument…").tag(nil as Instrument?)
                        ForEach(fetchInstruments(), id: \.self) { inst in
                            Text(inst.name ?? "").tag(inst as Instrument?)
                        }
                    }
                }
                Section {
                    TextField("Title", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.trimmingCharacters(in: .whitespacesAndNewlines) != initialAutoTitle {
                                isTitleEdited = true
                            }
                        }
                }
                Section {
                    Button {
                        tempDate = timestamp
                        showStartPicker = true
                    } label: {
                        HStack { Text("Start Time"); Spacer(); Text(formattedDate(timestamp)).foregroundStyle(.secondary) }
                    }
                }
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
                Section { TextField("Tags (comma-separated)", text: $tagsText) }

                // Attachments UI
                StagedAttachmentsSectionView(attachments: stagedAttachments, onRemove: removeStagedAttachment)
                Section {
                    Button("Add Photo") { showPhotoPicker = true }
                    Button("Add File") { showFileImporter = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") {
                            if cameraUsageDescriptionPresent() {
                                showCamera = true
                            } else {
                                showCameraKeyAlert = true
                                print("NSCameraUsageDescription:", Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") ?? "nil")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review & Save")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !isSaving else { return }
                        isSaving = true
                        isPresented = false
                        DispatchQueue.main.async {
                            saveToCoreData()
                            onSaved?()
                        }
                    } label: { Text("Save") }
                    .disabled(isSaving || durationSeconds == 0 || instrument == nil)
                }
            }
            .sheet(isPresented: $showStartPicker) {
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
                }.presentationDetents([.medium])
            }
            .sheet(isPresented: $showDurationPicker) {
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
                }.presentationDetents([.medium])
            }
            .onAppear(perform: loadPrefill)
            .onChange(of: instrument) { _, _ in
                guard !isTitleEdited else { return }
                let auto = defaultTitle(); title = auto; initialAutoTitle = auto
            }
            // Attachments modifiers
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
            .alert("Camera permission key missing",
                   isPresented: $showCameraKeyAlert,
                   actions: { Button("OK", role: .cancel) {} },
                   message: { Text("App build is missing NSCameraUsageDescription. Please reinstall after adding it.") })
        }
    }

    // MARK: - Existing helpers
    private func loadPrefill() {
        timestamp = prefillTimestamp
        durationSeconds = prefillDurationSeconds
        instrument = prefillInstrument
        let auto = defaultTitle()
        title = auto; initialAutoTitle = auto; isTitleEdited = false
    }

    private func saveToCoreData() {
        let s = Session(context: viewContext)
        s.instrument = instrument
        s.title = title.isEmpty ? defaultTitle() : title
        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = isPublic
        s.mood = Int16(mood)
        s.effort = Int16(effort)
        s.notes = notes
        let tagNames = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        s.tags = NSSet(array: upsertTags(tagNames))

        // Commit staged attachments
        commitStagedAttachments(to: s, ctx: viewContext)

        do { try viewContext.save() } catch { print("Error saving session: \(error)") }
    }

    private func defaultTitle(for inst: Instrument? = nil) -> String {
        if let name = (inst ?? instrument)?.name, !name.isEmpty { return "\(name) Practice" }
        return "Practice"
    }
    private func fetchInstruments() -> [Instrument] {
        let req: NSFetchRequest<Instrument> = Instrument.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? viewContext.fetch(req)) ?? []
    }
    private func upsertTags(_ names: [String]) -> [Tag] {
        var results: [Tag] = []
        for name in names {
            let req: NSFetchRequest<Tag> = Tag.fetchRequest()
            req.predicate = NSPredicate(format: "name ==[c] %@", name)
            if let existing = (try? viewContext.fetch(req))?.first { results.append(existing) }
            else { let t = Tag(context: viewContext); t.name = name; results.append(t) }
        }
        return results
    }
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.doesRelativeDateFormatting = true; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private func secondsToHM(_ seconds: Int) -> (Int, Int) {
        let h = seconds / 3600; let m = (seconds % 3600) / 60; return (h, m)
    }

    // MARK: - Attachment helpers
    private func stageData(_ data: Data, kind: AttachmentKind) {
        stagedAttachments.append(StagedAttachment(id: UUID(), data: data, kind: kind))
    }
    private func removeStagedAttachment(_ a: StagedAttachment) {
        stagedAttachments.removeAll { $0.id == a.id }
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
                } catch {
                    print("File import failed for \(url): \(error)")
                }
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
        for att in stagedAttachments {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let path = try AttachmentStore.saveData(att.data, suggestedName: att.id.uuidString, ext: ext)
                try AttachmentStore.addAttachment(kind: att.kind, filePath: path, to: session, ctx: ctx)
            } catch {
                print("Attachment commit failed: \(error)")
            }
        }
        stagedAttachments.removeAll()
    }

    // MARK: - Camera plist guard
    private func cameraUsageDescriptionPresent() -> Bool {
        if let v = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String, !v.isEmpty {
            return true
        }
        return false
    }
}
