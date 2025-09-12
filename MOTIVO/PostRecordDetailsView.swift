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

//
//  PostRecordDetailsView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit

struct PostRecordDetailsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Presented sheet binding from timer
    @Binding var isPresented: Bool

    // Prefill from timer (passed in)
    private let prefillTimestamp: Date
    private let prefillDurationSeconds: Int

    // Review state
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var title: String = ""
    @State private var timestamp: Date
    @State private var durationSeconds: Int
    @State private var isPublic: Bool = true
    @State private var mood: Int = 5
    @State private var effort: Int = 5
    @State private var tagsText: String = ""
    @State private var notes: String = ""

    // Track if user has edited title (so we don’t overwrite on instrument change)
    @State private var isTitleEdited = false
    @State private var initialAutoTitle = ""

    // Wheels
    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0

    // Attachments staging
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?

    // Camera permission alert
    @State private var showCameraDeniedAlert = false

    // Callback to notify timer view when saved (optional)
    var onSaved: (() -> Void)?

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
        self._timestamp = State(initialValue: self.prefillTimestamp)
        self._durationSeconds = State(initialValue: self.prefillDurationSeconds)
        self._instrument = State(initialValue: instrument)
        self.onSaved = onSaved
    }

    // Convenience flags
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
        NavigationStack {
            Form {
                // Instrument logic:
                // - 0 instruments: guidance (edge case)
                // - 1 instrument: hide the instrument section entirely (per request)
                // - 2+ instruments: show picker; changing selection updates title if user hasn’t edited
                if hasNoInstruments {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No instruments found")
                                .font(.headline)
                            Text("Add an instrument in your Profile to save this session.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
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
                }
                // (When hasOneInstrument, we show nothing here by design)

                // Title
                Section {
                    TextField("Title", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.trimmingCharacters(in: .whitespacesAndNewlines) != initialAutoTitle {
                                isTitleEdited = true
                            }
                        }
                }

                // Start Time
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

                // Attachments staging
                StagedAttachmentsSectionView(attachments: stagedAttachments, onRemove: removeStagedAttachment)
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
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Close first, then commit
                        isPresented = false
                        DispatchQueue.main.async { saveToCoreData() }
                    }
                    .disabled(durationSeconds == 0 || instrument == nil)
                }
            }

            // Start picker
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
                }
                .presentationDetents([.medium])
            }

            // Duration picker
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
                }
                .presentationDetents([.medium])
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
            .onAppear {
                // Load instruments and apply single-instrument policy
                instruments = fetchInstruments()

                // If only one instrument exists, auto-assign and hide selector.
                if instrument == nil, hasOneInstrument {
                    instrument = instruments.first
                }

                // Auto title using instrument if available and title is empty
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let auto = defaultTitle(for: instrument)
                    title = auto
                    initialAutoTitle = auto
                    isTitleEdited = false
                }
            }
            .onChange(of: instrument) { _, _ in
                // Update title when instrument changes, but only if user hasn’t edited manually
                guard !isTitleEdited else { return }
                let auto = defaultTitle(for: instrument)
                title = auto
                initialAutoTitle = auto
            }
        }
    }

    // MARK: - Save

    private func saveToCoreData() {
        let s = Session(context: viewContext)

        // Ensure required Core Data fields
        if (s.value(forKey: "id") as? UUID) == nil {
            s.setValue(UUID(), forKey: "id")
        }
        if s.timestamp == nil {
            s.timestamp = Date()
        }

        s.instrument = instrument
        s.title = title.isEmpty ? defaultTitle(for: instrument) : title
        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = isPublic
        s.mood = Int16(mood)
        s.effort = Int16(effort)
        s.notes = notes

        let tagNames = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        s.tags = NSSet(array: upsertTags(tagNames))

        // Commit staged attachments
        commitStagedAttachments(to: s, ctx: viewContext)

        do {
            try viewContext.save()
            onSaved?()
        } catch {
            print("Error saving session (timer review): \(error)")
        }
    }

    // MARK: - Helpers

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

    // MARK: - Camera authorization

    private func ensureCameraAuthorized(onAuthorized: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            onAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    granted ? onAuthorized() : { self.showCameraDeniedAlert = true }()
                }
            }
        default:
            self.showCameraDeniedAlert = true
        }
    }
}
