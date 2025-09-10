//
//  AddEditSessionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData
import PhotosUI
import UniformTypeIdentifiers

struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    /// Pass a Session to edit; leave nil to create new
    var session: Session?

    // MARK: - State (form fields)
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var when: Date = Date()
    @State private var isPublic: Bool = false
    @State private var mood: Double = 5
    @State private var effort: Double = 5
    @State private var selectedInstrument: String = ""
    @State private var tagsCSV: String = ""

    // Duration entry: minutes + seconds (text fields + ± buttons)
    @State private var durMinutes: String = "0"
    @State private var durSeconds: String = "0"

    // Track whether user overrode auto-title
    @State private var userEditedTitle: Bool = false
    @FocusState private var titleFocused: Bool   // NEW: detect real user edits

    // Instruments for picker
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var instruments: FetchedResults<Instrument>

    // Attachments (staged in /tmp until Save)
    @State private var pending: [PendingAttachment] = []
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem?

    init(session: Session? = nil) {
        self.session = session
    }

    var body: some View {
        NavigationView {
            Form {
                // When
                DatePicker("Date & time", selection: $when, displayedComponents: [.date, .hourAndMinute])

                // Instrument (picker)
                Picker("Instrument", selection: $selectedInstrument) {
                    Text("—").tag("")
                    ForEach(instrumentNames, id: \.self) { ins in
                        Text(ins).tag(ins)
                    }
                }
                .onChange(of: selectedInstrument) { _, _ in
                    applyAutoTitleIfNeeded()
                }

                // Title
                TextField("Title", text: $title)
                    .textInputAutocapitalization(.words)
                    .focused($titleFocused)
                    .onChange(of: title) { _, _ in
                        if titleFocused { userEditedTitle = true }  // only when user is typing
                    }

                // Duration
                DurationEditor(
                    minutes: $durMinutes,
                    seconds: $durSeconds,
                    incMin: { adjustMinutes(+1) },
                    decMin: { adjustMinutes(-1) },
                    incSec: { adjustSeconds(+1) },
                    decSec: { adjustSeconds(-1) }
                )

                // Privacy & Feel
                Section(header: Text("Privacy & Feel")) {
                    Toggle("Public", isOn: $isPublic)
                    VStack(alignment: .leading) {
                        HStack { Text("Mood"); Spacer(); Text("\(Int(mood))").foregroundStyle(.secondary) }
                        Slider(value: $mood, in: 0...10, step: 1)
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("Effort"); Spacer(); Text("\(Int(effort))").foregroundStyle(.secondary) }
                        Slider(value: $effort, in: 0...10, step: 1)
                    }
                }

                // Tags
                TextField("Tags (comma-separated: e.g. scales, repertoire)", text: $tagsCSV)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                // Attachments (staged prior to save)
                Section {
                    ForEach(pending) { p in
                        HStack {
                            Image(systemName: p.iconName).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.displayName).lineLimit(1)
                                Text(p.kind.rawValue).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { idxSet in
                        for idx in idxSet { pending[idx].cleanupTemp() }
                        pending.remove(atOffsets: idxSet)
                    }

                    Menu {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Files", systemImage: "folder")
                        }
                    } label: {
                        Label("Add Attachment", systemImage: "paperclip.circle")
                    }
                } header: {
                    Text("Attachments")
                } footer: {
                    if !pending.isEmpty {
                        Text("Attachments are staged and will be saved when you tap Save.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(session == nil ? "New Session" : "Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if session == nil {
                            pending.forEach { $0.cleanupTemp() }
                            pending.removeAll()
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(totalDurationSeconds == 0)
                }
            }
            .onAppear(perform: loadIfEditing)
            // Pickers
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, item in
                Task { await handlePhotoSelection(item) }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.image, .audio, .movie, .pdf, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { handleFileImport(url: url) }
                case .failure: break
                }
            }
        }
    }

    // MARK: - Derived
    private var totalDurationSeconds: Int {
        let mins = Int(durMinutes.filter(\.isNumber)) ?? 0
        let rawSecs = Int(durSeconds.filter(\.isNumber)) ?? 0
        let secs = min(max(rawSecs, 0), 59)
        let clampedMins = max(mins, 0)
        return clampedMins * 60 + secs
    }

    private var instrumentNames: [String] {
        instruments
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Actions
    private func loadIfEditing() {
        if let s = session {
            // Editing existing
            title = s.title ?? ""
            notes = s.notes ?? ""
            when = s.timestamp ?? Date()
            isPublic = s.isPublic
            mood = Double(s.mood)
            effort = Double(s.effort)
            selectedInstrument = s.instrument ?? ""

            let secs = max(0, Int(s.durationSeconds))
            durMinutes = String(secs / 60)
            durSeconds = String(secs % 60)
            tagsCSV = ((s.tags as? Set<Tag>) ?? [])
                .compactMap { $0.name }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: ", ")
        } else {
            // New
            if selectedInstrument.isEmpty {
                let fr: NSFetchRequest<Profile> = Profile.fetchRequest()
                fr.fetchLimit = 1
                let primary = (try? ctx.fetch(fr).first?.primaryInstrument) ?? ""
                if !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedInstrument = primary
                } else if let first = instrumentNames.first {
                    selectedInstrument = first
                } else {
                    selectedInstrument = ""
                }
            }
            applyAutoTitleIfNeeded()
            durMinutes = "0"
            durSeconds = "0"

            // Default privacy from Profile
            let fr: NSFetchRequest<Profile> = Profile.fetchRequest()
            fr.fetchLimit = 1
            if let p = try? ctx.fetch(fr).first {
                isPublic = p.defaultPrivacy
            } else {
                isPublic = false
            }
        }
    }

    private func applyAutoTitleIfNeeded() {
        guard !userEditedTitle else { return }
        let trimmed = selectedInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? "Practice Session" : "\(trimmed) Practice"
    }

    // MARK: - Duration adjustments (+ / -)
    private func adjustMinutes(_ delta: Int) {
        var m = Int(durMinutes.filter(\.isNumber)) ?? 0
        m = max(0, m + delta)
        durMinutes = String(m)
    }

    private func adjustSeconds(_ delta: Int) {
        var m = Int(durMinutes.filter(\.isNumber)) ?? 0
        var s = Int(durSeconds.filter(\.isNumber)) ?? 0
        s += delta

        if s >= 60 {
            m += s / 60
            s = s % 60
        } else if s < 0 {
            let borrow = (abs(s) + 59) / 60
            if m >= borrow {
                m -= borrow
                s += borrow * 60
            } else {
                m = 0
                s = 0
            }
        }

        durMinutes = String(max(0, m))
        durSeconds = String(max(0, min(59, s)))
    }

    // MARK: - Attachments handling (staged in tmp)
    private func handleFileImport(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            let kind = kindForExtension(ext)
            let tmpURL = try writeTemp(data: data, ext: ext)
            pending.append(PendingAttachment(tempPath: tmpURL.path, suggestedName: base, ext: ext, kind: kind))
        } catch { }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let ts = Int(Date().timeIntervalSince1970)
                let name = "image_\(ts)"
                let ext = "png"
                let tmpURL = try writeTemp(data: data, ext: ext)
                pending.append(PendingAttachment(tempPath: tmpURL.path, suggestedName: name, ext: ext, kind: .image))
            }
        } catch { }
    }

    private func writeTemp(data: Data, ext: String) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let fname = UUID().uuidString + "." + ext.lowercased()
        let url = tmpDir.appendingPathComponent(fname)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func kindForExtension(_ ext: String) -> AttachmentKind {
        let e = ext.lowercased()
        if ["png","jpg","jpeg","heic","gif","tiff","bmp","webp"].contains(e) { return .image }
        if ["m4a","aac","mp3","wav","aiff","caf","flac","ogg"].contains(e) { return .audio }
        if ["mov","mp4","m4v","avi","mkv","hevc"].contains(e) { return .video }
        return .file
    }

    // MARK: - Save
    private func save() {
        let isEditing = (session != nil)
        let s: Session = session ?? Session(context: ctx)
        if s.id == nil { s.id = UUID() }

        s.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        s.notes = notes
        s.timestamp = when
        s.isPublic = isPublic
        s.mood = Int16(min(max(Int(mood), 0), 10))
        s.effort = Int16(min(max(Int(effort), 0), 10))
        s.instrument = selectedInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        s.durationSeconds = Int64(totalDurationSeconds)

        // Upsert tags
        do {
            let tags = try TagCanonicalizer.upsertCSV(in: ctx, csv: tagsCSV)
            if isEditing { s.removeFromTags((s.tags as? NSSet) ?? NSSet()) }
            for t in tags { s.addToTags(t) }
        } catch { }

        do { try ctx.save() } catch {
            if !isEditing { ctx.delete(s) }
            return
        }

        // Persist staged attachments
        if !pending.isEmpty {
            for p in pending {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: p.tempPath))
                    let finalPath = try AttachmentStore.saveData(data, suggestedName: p.suggestedName, ext: p.ext)
                    try AttachmentStore.addAttachment(kind: p.kind, filePath: finalPath, to: s, ctx: ctx)
                } catch { }
            }
            pending.forEach { $0.cleanupTemp() }
            pending.removeAll()
        }

        dismiss()
    }
}

// MARK: - DurationEditor & StepButton (unchanged)
private struct DurationEditor: View {
    @Binding var minutes: String
    @Binding var seconds: String

    let incMin: () -> Void
    let decMin: () -> Void
    let incSec: () -> Void
    let decSec: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("0", text: $minutes)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 52)
                    .onChange(of: minutes) { _, new in sanitizeMinutes(new) }
                Text("min").foregroundStyle(.secondary)
                StepButton(system: "minus.circle.fill", action: decMin)
                StepButton(system: "plus.circle.fill", action: incMin)
            }
            HStack(spacing: 8) {
                TextField("0", text: $seconds)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 52)
                    .onChange(of: seconds) { _, new in sanitizeSeconds(new) }
                Text("sec").foregroundStyle(.secondary)
                StepButton(system: "minus.circle.fill", action: decSec)
                StepButton(system: "plus.circle.fill", action: incSec)
            }
        }
    }

    private func sanitizeMinutes(_ value: String) {
        let digits = value.filter(\.isNumber)
        if digits != value { minutes = digits }
        if digits.count > 5 { minutes = String(digits.prefix(5)) }
    }

    private func sanitizeSeconds(_ value: String) {
        let digits = value.filter(\.isNumber)
        if digits != value { seconds = digits }
        if let n = Int(digits), n > 59 { seconds = "59" }
        if digits.count > 2 { seconds = String(digits.prefix(2)) }
    }
}

private struct StepButton: View {
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 32, minHeight: 32)
        .contentShape(Rectangle())
    }
}

// MARK: - PendingAttachment
private struct PendingAttachment: Identifiable {
    let id = UUID()
    let tempPath: String
    let suggestedName: String
    let ext: String
    let kind: AttachmentKind

    var displayName: String { suggestedName + "." + ext }
    var iconName: String {
        switch kind {
        case .audio: return "waveform"
        case .video: return "video"
        case .image: return "photo"
        case .file:  return "doc"
        }
    }

    func cleanupTemp() {
        let url = URL(fileURLWithPath: tempPath)
        try? FileManager.default.removeItem(at: url)
    }
}
