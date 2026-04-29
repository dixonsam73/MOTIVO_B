// CHANGE-ID: 20260429_102500_AVVTrimPlaybackCopy
// SCOPE: PTV attachment viewer trim callbacks — pass disposable copies to trim persistence so AVV keeps its active playback URL alive after video replace/save-as-new. No UI, recorder, trim export, or non-viewer logic changes.
// SEARCH-TOKEN: 20260429_102500_AVVTrimPlaybackCopy

// CHANGE-ID: 20260324_144300_ptv_sheets_root_route_reviewsave
// SCOPE: Root-route handoff only — review save in home presentation now switches AppRoute directly to .content instead of triggering modal ContentView presentation. No UI/layout or sheet architecture changes.
// SEARCH-TOKEN: 20260324_144300_ptv_sheets_root_route_reviewsave

// CHANGE-ID: 20260217_104417_ad416700
// SCOPE: PTV Audio Recorder card width contract — remove ARV self-card chrome; wrap in PTV cardSurface

// CHANGE-ID: 20251227_153950-ptv-sheets-renamewire-audioPersistSync-01
// SCOPE: PTV viewer audio rename: also write to StagingStore.updateAudioMetadata so card does not snap back. No other changes.

import SwiftUI
import AVFoundation
import AVKit
import UIKit
import Vision
import VisionKit
import UniformTypeIdentifiers

extension PracticeTimerView {

    @ViewBuilder
     var instrumentPickerSheet: some View {
            NavigationView {
                VStack(spacing: 0) {
                    Picker("Instrument", selection: $instrumentIndex) {
                        ForEach(instruments.indices, id: \.self) { i in
                            Text(instruments[i].name ?? "Instrument").tag(i)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, Theme.Spacing.s)
                .appBackground()
                .navigationTitle("Instrument")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            applyInstrumentIndex()
                            showInstrumentSheet = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showInstrumentSheet = false }
                    }
                }
            }
        }

    @ViewBuilder
     var activityPickerSheet: some View {
            ActivityPickerSheet(
                activityChoice: $activityChoice,
                showActivitySheet: $showActivitySheet,
                choices: activityChoicesPinned(),
                displayName: { activityDisplayName(for: $0) },
                applyChoice: { choice in
                    applyChoice(choice)
                },
                resetTasks: {
                    // when activity changes in the timer, reset tasks context
                    resetTasksForNewSessionContext()
                }
            )
        }


    @ViewBuilder
     var reviewSheet: some View {
            PostRecordDetailsView(
                isPresented: $showReviewSheet,
                timestamp: (finalizedStartDate ?? startDate ?? Date()),
                durationSeconds: finalizedDuration,
                instrument: instrument,
                activityTypeRaw: activity.rawValue,
                activityDetailPrefill: activityDetail.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ? nil : activityDetail,
                notesPrefill: nil,
                prefillAttachments: (stagedImages + stagedAudio + stagedVideos),
                prefillAttachmentNames: audioTitles,
                onSaved: {
                    didSaveFromReview = true
                    clearPersistedTimer()
                    clearPersistedStagedAttachments()
                    clearPersistedTasks()
                    resetUIOnly()
                    stagedAudio.removeAll()
                    audioTitles.removeAll()
                    stagedImages.removeAll()
                    stagedVideos.removeAll()
                    videoThumbnails.removeAll()
                    selectedThumbnailID = nil
                    UserDefaults.standard.set(false, forKey: sessionActiveKey)
                    UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
                    UserDefaults.standard.removeObject(forKey: currentSessionIDKey)
                    if isHomePresentation {
                        DispatchQueue.main.async {
                            appRoute.route = .content
                        }
                    } else {
                        isPresented = false
                    }
                },
                onCancel: { didCancelFromReview = true }
            )
        }

    @ViewBuilder
     var audioHelpSheet: some View {
            InfoSheetView(
                title: "Quick audio takes (for now)",
                bullets: [
                    "Open Voice Memos to record.",
                    "Share to Files when done.",
                    "Back here, use Add Attachment to include it."
                ],
                primaryCTA: nil
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }

    @ViewBuilder
     var videoHelpSheet: some View {
            InfoSheetView(
                title: "Quick video clips (for now)",
                bullets: [
                    "Open Camera → Video to record.",
                    "Save to Photos or Files.",
                    "Back here, use Add Attachment to include it."
                ],
                primaryCTA: nil
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }

    @ViewBuilder
    var audioRecorderPanel: some View {
        AudioRecorderView { url in
            Task { await stageAudioURL(url) }
            showAudioRecorder = false
        }
        .cardSurface()
    }


    @ViewBuilder
     var videoRecorderFullScreen: some View {
            NavigationStack {
                VideoRecorderView { url in
                    stageVideoURL(url)
                    showVideoRecorder = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showVideoRecorder = false }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }

    @ViewBuilder
     var cameraSheet: some View {
            CameraCaptureView { image in
                stageImage(image)
            }
        }


    
    // MARK: - Viewer Rename (PTV staged video titles)
    // Video titles are optional metadata only (no defaults). Stored in UserDefaults keyed by UUID string.
    private static let ptvVideoTitlesDefaultsKey = "PracticeTimer.videoTitles_v1"

    private func loadPTVVideoTitlesMap() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: Self.ptvVideoTitlesDefaultsKey) as? [String: String]) ?? [:]
    }

    private func savePTVVideoTitlesMap(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: Self.ptvVideoTitlesDefaultsKey)
    }

    private func videoTitle(for id: UUID) -> String? {
        let v = loadPTVVideoTitlesMap()[id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return v.isEmpty ? nil : v
    }

    private func setVideoTitle(_ title: String?, for id: UUID) {
        var map = loadPTVVideoTitlesMap()
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map.removeValue(forKey: id.uuidString)
        } else {
            map[id.uuidString] = trimmed
        }
        savePTVVideoTitlesMap(map)
        // Snapshot staged state for resilience (matches other staged metadata persistence expectations)
        persistStagedAttachments()
    }

func attachmentViewerView(for payload: PTVViewerURL) -> some View {
        var imageURLs: [URL] = []
        var videoURLs: [URL] = []
        var audioURLs: [URL] = []
        var startIndex: Int = 0

        switch payload.kind {
        case .image:
            imageURLs = [payload.url]
            videoURLs = []
            audioURLs = []
            startIndex = 0
        case .video:
            videoURLs = [payload.url]
            audioURLs = []
            imageURLs = []
            startIndex = 0
        case .audio:
            videoURLs = []
            audioURLs = [payload.url]
            imageURLs = []
            startIndex = 0
        }

        func resolveStagedID(from url: URL) -> UUID? {
            // LOCKED: URL → UUID mapping is stem-only.
            let stem = url.deletingPathExtension().lastPathComponent
            return UUID(uuidString: stem)
        }

        func disposableTrimPersistenceURL(from url: URL) -> URL {
            let fm = FileManager.default
            let ext = url.pathExtension
            let filename = ext.isEmpty
                ? UUID().uuidString
                : "\(UUID().uuidString).\(ext)"
            let copyURL = fm.temporaryDirectory.appendingPathComponent(filename)
            do {
                try fm.copyItem(at: url, to: copyURL)
                return copyURL
            } catch {
#if DEBUG
                print("[PTV] attachmentViewer trim copy failed; falling back to original URL: \(error)")
#endif
                return url
            }
        }

        return AttachmentViewerView(
            imageURLs: imageURLs,
            startIndex: startIndex,
            themeBackground: Color(.systemBackground),
            videoURLs: videoURLs,
            audioURLs: audioURLs,
            onDelete: { url in
                if let uuid = resolveStagedID(from: url) {
                    // Remove from matching staged arrays and caches (no thumbnail fallback; user must explicitly set ⭐)
                    if let idx = stagedImages.firstIndex(where: { $0.id == uuid }) {
                        let removed = stagedImages.remove(at: idx)
                        if selectedThumbnailID == removed.id { selectedThumbnailID = nil }
                        persistStagedAttachments()
                    } else if let idx = stagedVideos.firstIndex(where: { $0.id == uuid }) {
                        let removed = stagedVideos.remove(at: idx)
                        videoThumbnails.removeValue(forKey: removed.id)
                        if selectedThumbnailID == removed.id { selectedThumbnailID = nil }
                        persistStagedAttachments()
                    } else if let idx = stagedAudio.firstIndex(where: { $0.id == uuid }) {
                        let removed = stagedAudio.remove(at: idx)
                        audioTitles.removeValue(forKey: removed.id)
                        audioAutoTitles.removeValue(forKey: removed.id)
                        audioDurations.removeValue(forKey: removed.id)
                        if selectedThumbnailID == removed.id { selectedThumbnailID = nil }
                        persistStagedAttachments()
                    }

                    // Mirror delete to staging store
                    if let ref = StagingStore.list().first(where: { $0.id == uuid }) {
                        StagingStore.remove(ref)
                    }
                }
            },
            titleForURL: { url, kind in
                guard let id = resolveStagedID(from: url) else { return nil }
                switch kind {
                case .audio:
#if DEBUG
                    print("[PTV] titleForURL.audio id=\(id) title=\(audioTitles[id] ?? "nil") auto=\(audioAutoTitles[id] ?? "nil")")
#endif
                    if let t = audioTitles[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
                    if let t = audioAutoTitles[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
                    return nil
                case .video:
                    // Prefer shared staging map used by PRDV for seamless handoff
                    let stagingKey = "stagedVideoTitles_temp"
                    if let dict = UserDefaults.standard.dictionary(forKey: stagingKey) as? [String: String],
                       let raw = dict[id.uuidString] {
                        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { return t }
                    }
                    // Fallback to PTV-local map
                    return videoTitle(for: id)
                case .image, .file:
                    return nil
                }
            },
            onRename: { url, newTitle, kind in
                guard let id = resolveStagedID(from: url) else { return }
                let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                switch kind {
                case .audio:
                    // LOCKED: audio rename writes into the existing staged audio title store.
                    guard !trimmed.isEmpty else { return }
                    audioTitles[id] = trimmed
#if DEBUG
                    print("[PTV] onRename.audio id=\(id) new=\(trimmed)")
#endif
                    // Keep staged persistence in sync with the same mechanism used elsewhere in PTV.
                    let auto = audioAutoTitles[id] ?? ""
                    let dur = audioDurations[id].map(Double.init)
                    StagingStore.updateAudioMetadata(id: id, title: trimmed, autoTitle: auto, duration: dur)

                    persistStagedAttachments()
                case .video:
                    // Video titles are optional; empty means clear.
                    setVideoTitle(trimmed, for: id)
                    // Mirror into shared staging map so PRDV can read immediately after finishing timer
                    let stagingKey = "stagedVideoTitles_temp"
                    var dict = (UserDefaults.standard.dictionary(forKey: stagingKey) as? [String: String]) ?? [:]
                    if trimmed.isEmpty { dict.removeValue(forKey: id.uuidString) }
                    else { dict[id.uuidString] = trimmed }
                    UserDefaults.standard.set(dict, forKey: stagingKey)
                case .image, .file:
                    break
                }
            },
           
            onReplaceAttachment: { oldURL, newURL, _ in
                if let uuid = resolveStagedID(from: oldURL) {
                    if let item = stagedVideos.first(where: { $0.id == uuid })
                        ?? stagedAudio.first(where: { $0.id == uuid })
                        ?? stagedImages.first(where: { $0.id == uuid }) {
                        handleTrimReplaceOriginal(from: disposableTrimPersistenceURL(from: newURL), for: item)
                    }
                }
            },
            onSaveAsNewAttachmentFromSource: { sourceURL, newURL, _ in
                if let uuid = resolveStagedID(from: sourceURL) {
                    if let item = stagedVideos.first(where: { $0.id == uuid })
                        ?? stagedAudio.first(where: { $0.id == uuid })
                        ?? stagedImages.first(where: { $0.id == uuid }) {
                        handleTrimSaveAsNew(from: disposableTrimPersistenceURL(from: newURL), basedOn: item)
                    }
                }
            },
            canShare: false
        )
        .onAppear {
            killDroneAndMetronome()
        }
    }
    @ViewBuilder
     func trimSheet(for item: StagedAttachment) -> some View {
            if let url = surrogateURL(for: item) {
                MediaTrimView(
                    assetURL: url,
                    mediaType: (item.kind == .audio ? .audio : .video),
                    onCancel: {
                        trimItem = nil
                    },
                    onSaveAsNewAttachment: { newURL, _ in
                        handleTrimSaveAsNew(from: newURL, basedOn: item)
                    },
                    onReplaceAttachment: { _, newURL, _ in
                        handleTrimReplaceOriginal(from: newURL, for: item)
                    }
                )
                .accessibilityLabel("Trim media")
                .accessibilityHint("Edit start and end of the clip")
            } else {
                Text("Unable to open trimmer").padding()
            }
        }


    // MARK: - Task Import Helpers

    @ViewBuilder
    var taskImportPasteSheet: some View {
        TaskImportSourceSheet(
            onClose: {
                showTaskImportPasteSheet = false
            },
            onConfirmImportedLines: { imported in
                stagedImportedTaskLinesAfterPasteDismiss = imported
                showTaskImportPasteSheet = false
            }
        )
    }

    @ViewBuilder
    var taskImportScanSheet: some View {
        TaskImportScanSheet(
            title: "Scan tasks",
            onCancel: {
                showTaskImportScanSheet = false
            },
            onConfirm: { imported in
                beginImportedTaskFlow(with: imported.map { TaskLine(text: $0, isDone: false, type: .task) })
                showTaskImportScanSheet = false
            }
        )
    }

    func beginImportedTaskFlow(with imported: [TaskLine]) {
        let cleaned = imported
            .map {
                TaskLine(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDone: false,
                    type: $0.type
                )
            }
            .filter { !$0.text.isEmpty }

        guard !cleaned.isEmpty else { return }

        pendingImportedTaskLines = cleaned

        let hasExistingTasks = taskLines.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if hasExistingTasks {
            showTaskImportReplaceAppendDialog = true
        } else {
            applyPendingImportedTasks(appending: false)
        }
    }

    func applyPendingImportedTasks(appending: Bool) {
        let importedTaskLines = pendingImportedTaskLines
            .map {
                TaskLine(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDone: false,
                    type: $0.type
                )
            }
            .filter { !$0.text.isEmpty }

        guard !importedTaskLines.isEmpty else {
            pendingImportedTaskLines.removeAll()
            return
        }

        applyTaskLinesSafely(importedTaskLines, appending: appending) {
            autoTaskTexts.removeAll()
            userClearedTasksForCurrentContext = false
            unlinkTaskSetForLoadedOrImportedList()
            persistTasksSnapshot()
            pendingImportedTaskLines.removeAll()
        }
    }

    static func parseImportedTaskLines(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                return trimmed.replacingOccurrences(
                    of: #"^\s*(?:[-*•◦▪︎▹►]+|\d+[\.\)]|[A-Za-z][\.\)])\s*"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}

private struct SavedTaskSetPickerLine: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var type: TaskLineType

    init(id: UUID = UUID(), text: String, type: TaskLineType = .task) {
        self.id = id
        self.text = text
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        type = try container.decodeIfPresent(TaskLineType.self, forKey: .type) ?? .task
    }
}

private struct SavedTaskSetPickerRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var items: [SavedTaskSetPickerLine]
}

private struct LegacySavedTaskSetPickerRecord: Codable {
    let id: UUID
    var name: String
    var items: [String]
}

private enum TaskImportSourceOption: String, Identifiable, CaseIterable {
    case loadSavedSet
    case pasteOrType
    case scan

    var id: String { rawValue }
}

private struct TaskImportSourceSheet: View {
    let onClose: () -> Void
    let onConfirmImportedLines: ([TaskLine]) -> Void

    @State private var savedTaskSets: [SavedTaskSetPickerRecord] = []
    @State private var activeOption: TaskImportSourceOption? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Import tasks")
                        .sectionHeader()

                    VStack(spacing: 12) {
                        importOptionButton(
                            title: "Paste or type"
                        ) {
                            activeOption = .pasteOrType
                        }

                        importOptionButton(
                            title: "Scan"
                        ) {
                            activeOption = .scan
                        }

                        importOptionButton(
                            title: "Load saved set",
                            isEnabled: savedTaskSets.isEmpty == false
                        ) {
                            activeOption = .loadSavedSet
                        }
                    }
                    .cardSurface()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .appBackground()
           
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onClose() }
                }
            }
            .onAppear {
                savedTaskSets = loadAllSavedTaskSets()
            }
            .sheet(item: $activeOption) { option in
                switch option {
                case .loadSavedSet:
                    TaskImportSavedSetPickerSheet(
                        savedTaskSets: savedTaskSets,
                        onCancel: {
                            activeOption = nil
                        },
                        onSelect: { selectedSet in
                            activeOption = nil
                            onConfirmImportedLines(selectedSet.items.map { TaskLine(text: $0.text, isDone: false, type: $0.type) })
                        }
                    )
                case .pasteOrType:
                    TaskImportEditorSheet(
                        title: "Import tasks",
                        initialRawText: "",
                        onCancel: {
                            activeOption = nil
                        },
                        onConfirm: { imported in
                            activeOption = nil
                            onConfirmImportedLines(imported.map { TaskLine(text: $0, isDone: false, type: .task) })
                        }
                    )
                case .scan:
                    TaskImportScanSheet(
                        title: "Scan tasks",
                        onCancel: {
                            activeOption = nil
                        },
                        onConfirm: { imported in
                            activeOption = nil
                            onConfirmImportedLines(imported.map { TaskLine(text: $0, isDone: false, type: .task) })
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func importOptionButton(
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Text.body.weight(.semibold))
                .foregroundStyle(isEnabled ? .primary : Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1.0 : 0.6)
    }

    private func loadAllSavedTaskSets() -> [SavedTaskSetPickerRecord] {
        let defaults = UserDefaults.standard

        let ownerScope: String = {
            if let id = PersistenceController.shared.currentUserID,
               !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return id
            }
            return "device"
        }()

        let globalTaskSetsKey = "practiceTasks_saved_sets_v2::" + ownerScope

        var merged: [SavedTaskSetPickerRecord] = []
        var seenIDs = Set<UUID>()
        var seenContentSignatures = Set<String>()

        func normalizedLines(from lines: [SavedTaskSetPickerLine]) -> [SavedTaskSetPickerLine] {
            lines
                .map {
                    SavedTaskSetPickerLine(
                        id: $0.id,
                        text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        type: $0.type
                    )
                }
                .filter { !$0.text.isEmpty }
        }

        func merge(_ sets: [SavedTaskSetPickerRecord]) {
            for set in sets {
                let trimmedName = set.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedItems = normalizedLines(from: set.items)
                guard !normalizedItems.isEmpty else { continue }

                let fallbackName = normalizedItems.first?.text ?? "Saved task set"
                let finalName = trimmedName.isEmpty ? fallbackName : trimmedName
                let contentSignature = finalName.lowercased() + "||" + normalizedItems.map { $0.type.rawValue + ":" + $0.text.lowercased() }.joined(separator: "\u{241E}")

                if seenIDs.contains(set.id) || seenContentSignatures.contains(contentSignature) {
                    continue
                }

                seenIDs.insert(set.id)
                seenContentSignatures.insert(contentSignature)
                merged.append(SavedTaskSetPickerRecord(id: set.id, name: finalName, items: normalizedItems))
            }
        }

        if let data = defaults.data(forKey: globalTaskSetsKey) {
            if let decoded = try? JSONDecoder().decode([SavedTaskSetPickerRecord].self, from: data) {
                merge(decoded)
            } else if let legacyDecoded = try? JSONDecoder().decode([LegacySavedTaskSetPickerRecord].self, from: data) {
                merge(
                    legacyDecoded.map {
                        SavedTaskSetPickerRecord(
                            id: $0.id,
                            name: $0.name,
                            items: $0.items.map { SavedTaskSetPickerLine(text: $0, type: .task) }
                        )
                    }
                )
            }
        }

        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasSuffix("::saved_sets_v1") else { continue }

            let data: Data?
            if let directData = defaults.data(forKey: key) {
                data = directData
            } else if let valueData = value as? Data {
                data = valueData
            } else {
                data = nil
            }

            guard let data else { continue }

            if let decoded = try? JSONDecoder().decode([SavedTaskSetPickerRecord].self, from: data) {
                merge(decoded)
                continue
            }

            if let legacyDecoded = try? JSONDecoder().decode([LegacySavedTaskSetPickerRecord].self, from: data) {
                merge(
                    legacyDecoded.map {
                        SavedTaskSetPickerRecord(
                            id: $0.id,
                            name: $0.name,
                            items: $0.items.map { SavedTaskSetPickerLine(text: $0, type: .task) }
                        )
                    }
                )
            }
        }

        return merged.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct TaskImportSavedSetPickerSheet: View {
    let savedTaskSets: [SavedTaskSetPickerRecord]
    let onCancel: () -> Void
    let onSelect: (SavedTaskSetPickerRecord) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saved task sets")
                        .sectionHeader()

                    if savedTaskSets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No saved task sets yet.")
                                .font(Theme.Text.body.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("Save a task set in Tasks Manager to load it here.")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .cardSurface()
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(savedTaskSets) { taskSet in
                                Button {
                                    onSelect(taskSet)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(taskSet.name)
                                                .font(Theme.Text.body.weight(.semibold))
                                                .foregroundStyle(.primary)

                                            Text("\(taskSet.items.count) \(taskSet.items.count == 1 ? "task" : "tasks")")
                                                .font(Theme.Text.meta)
                                                .foregroundStyle(Theme.Colors.secondaryText)
                                        }

                                        Spacer(minLength: 12)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                                    }
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if taskSet.id != savedTaskSets.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .cardSurface()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .appBackground()
            .navigationTitle("Load saved set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}

private struct EditableImportedTaskLine: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

private struct TaskImportEditorSheet: View {
    let title: String
    let initialRawText: String
    let onCancel: () -> Void
    let onConfirm: ([String]) -> Void

    @State private var rawText: String
    @State private var draftLines: [EditableImportedTaskLine]
    @State private var draggedLineID: UUID? = nil
    @State private var suppressRawTextObserver: Bool = false
    @FocusState private var focusedDraftLineID: UUID?

    private let dragHandleWidth: CGFloat = 20
    private let deleteIconWidth: CGFloat = 20
    private let dragDeleteSpacing: CGFloat = 16

    private var rightControlZoneWidth: CGFloat {
        dragHandleWidth + dragDeleteSpacing + deleteIconWidth
    }

    init(
        title: String,
        initialRawText: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([String]) -> Void
    ) {
        self.title = title
        self.initialRawText = initialRawText
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        let parsed = PracticeTimerView.parseImportedTaskLines(from: initialRawText)
        _draftLines = State(initialValue: parsed.map { EditableImportedTaskLine(text: $0) })

        let initialBuffer = parsed.isEmpty ? initialRawText : ""
        _rawText = State(initialValue: initialBuffer)
    }

    private var cleanedDraftLines: [String] {
        draftLines
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Add tasks")
                            .sectionHeader()

                        Spacer()

                        Button {
                            guard let pasted = UIPasteboard.general.string,
                                  pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            else { return }

                            suppressRawTextObserver = true
                            rawText = pasted
                            suppressRawTextObserver = false
                            handleRawTextChanged(oldValue: "", newValue: pasted)
                        } label: {
                            Text("Paste")
                                .font(Theme.Text.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                        .fill(Color.secondary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 0) {
                        if draftLines.isEmpty == false {
                            ForEach($draftLines) { $line in
                                importedTaskRow($line)
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: ImportedTaskLineDropDelegate(
                                            targetID: line.id,
                                            draftLines: $draftLines,
                                            draggedLineID: $draggedLineID
                                        )
                                    )

                                if line.id != draftLines.last?.id {
                                    Divider()
                                }
                            }
                        }

                        if draftLines.isEmpty == false && rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                            Divider()
                                .padding(.vertical, 8)
                        }

                        TextEditor(text: $rawText)
                            .frame(minHeight: draftLines.isEmpty ? 140 : 44)
                            .font(Theme.Text.body)
                            .scrollContentBackground(.hidden)
                            .onChange(of: rawText) { oldValue, newValue in
                                handleRawTextChanged(oldValue: oldValue, newValue: newValue)
                            }
                    }
                    .cardSurface()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
            .appBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use for this session") {
                        let lines = cleanedDraftLines.isEmpty
                            ? PracticeTimerView.parseImportedTaskLines(from: rawText)
                            : cleanedDraftLines
                        onConfirm(lines)
                    }
                    .disabled(cleanedDraftLines.isEmpty && PracticeTimerView.parseImportedTaskLines(from: rawText).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func importedTaskRow(_ line: Binding<EditableImportedTaskLine>) -> some View {
        HStack(spacing: 6) {
            TextField("Task", text: line.text)
                .textFieldStyle(.plain)
                .font(Theme.Text.body)
                .disableAutocorrection(true)
                .focused($focusedDraftLineID, equals: line.wrappedValue.id)

            Spacer(minLength: 8)

            HStack(spacing: dragDeleteSpacing) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                    .frame(width: dragHandleWidth, height: 28)
                    .contentShape(Rectangle())
                    .onDrag {
                        dismissKeyboard()
                        draggedLineID = line.wrappedValue.id
                        return NSItemProvider(object: NSString(string: line.wrappedValue.id.uuidString))
                    }
                    .accessibilityLabel("Reorder task")

                Button(role: .destructive) {
                    draftLines.removeAll { $0.id == line.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                        .frame(width: deleteIconWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: rightControlZoneWidth, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func handleRawTextChanged(oldValue: String, newValue: String) {
        guard suppressRawTextObserver == false else { return }
        guard newValue.contains("\n") else { return }

        let isLikelyPaste = abs(newValue.count - oldValue.count) > 1

        let committedText: String
        let remainingText: String

        if isLikelyPaste {
            committedText = newValue
            remainingText = ""
        } else if newValue.hasSuffix("\n") {
            committedText = newValue
            remainingText = ""
        } else {
            var components = newValue.components(separatedBy: .newlines)
            remainingText = components.popLast() ?? ""
            committedText = components.joined(separator: "\n")
        }

        let parsed = PracticeTimerView.parseImportedTaskLines(from: committedText)
        guard parsed.isEmpty == false else { return }

        draftLines.append(contentsOf: parsed.map { EditableImportedTaskLine(text: $0) })

        suppressRawTextObserver = true
        rawText = remainingText
        suppressRawTextObserver = false

        dismissKeyboard()
    }

    private func dismissKeyboard() {
        focusedDraftLineID = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct ImportedTaskLineDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draftLines: [EditableImportedTaskLine]
    @Binding var draggedLineID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedLineID,
              draggedLineID != targetID,
              let from = draftLines.firstIndex(where: { $0.id == draggedLineID }),
              let to = draftLines.firstIndex(where: { $0.id == targetID })
        else { return }

        if draftLines[to].id != draggedLineID {
            let moving = draftLines.remove(at: from)
            draftLines.insert(moving, at: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedLineID = nil
        return true
    }
}

private struct TaskImportScanSheet: View {
    let title: String
    let onCancel: () -> Void
    let onConfirm: ([String]) -> Void

    @State private var scannedText: String = ""
    @State private var showScanner: Bool = true

    var body: some View {
        Group {
            if showScanner {
                TaskDocumentScanner(
                    onCancel: {
                        onCancel()
                    },
                    onRecognizedText: { text in
                        scannedText = text
                        showScanner = false
                    }
                )
                .ignoresSafeArea()
            } else {
                TaskImportEditorSheet(
                    title: title,
                    initialRawText: scannedText,
                    onCancel: onCancel,
                    onConfirm: onConfirm
                )
            }
        }
    }
}

private struct TaskDocumentScanner: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onRecognizedText: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onRecognizedText: onRecognizedText)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCancel: () -> Void
        let onRecognizedText: (String) -> Void

        init(onCancel: @escaping () -> Void, onRecognizedText: @escaping (String) -> Void) {
            self.onCancel = onCancel
            self.onRecognizedText = onRecognizedText
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            Task {
                var chunks: [String] = []

                for pageIndex in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: pageIndex)
                    if let recognized = await recognizeText(in: image), !recognized.isEmpty {
                        chunks.append(recognized)
                    }
                }

                await MainActor.run {
                    onRecognizedText(chunks.joined(separator: "\n"))
                }
            }
        }

        private func recognizeText(in image: UIImage) async -> String? {
            guard let cgImage = image.cgImage else { return nil }

            return await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { request, _ in
                    let text = (request.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        }
    }
}

