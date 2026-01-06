// CHANGE-ID: 20260106_000900_ptv_sheets_viewer_state_sync
// SCOPE: PTV viewer callbacks now use stable privacy keys + enforce ⭐⇔selection with privacy/thumbnail invariants; remove any thumbnail fallback on delete.

// CHANGE-ID: 20251227_153950-ptv-sheets-renamewire-audioPersistSync-01
// SCOPE: PTV viewer audio rename: also write to StagingStore.updateAudioMetadata so card does not snap back. No other changes.

import SwiftUI
import AVFoundation
import AVKit

extension PracticeTimerView {

    @ViewBuilder
     var instrumentPickerSheet: some View {
            NavigationView {
                VStack {
                    Picker("Instrument", selection: $instrumentIndex) {
                        ForEach(instruments.indices, id: \.self) { i in
                            Text(instruments[i].name ?? "Instrument").tag(i)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
                .navigationTitle("Instrument")
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
                notesPrefill: composeCompletedTasksNotesString(),
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
                    isPresented = false
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
            onFavourite: { url in
                guard let uuid = resolveStagedID(from: url) else { return }

                // Use a stable surrogate URL for privacy keys so viewer and thumbnails stay in sync.
                let stableURL: URL = {
                    if let a = stagedImages.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    if let a = stagedVideos.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    if let a = stagedAudio.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    return url
                }()

                if selectedThumbnailID == uuid {
                    // Toggle OFF ⭐ (does not imply removing 👁)
                    selectedThumbnailID = nil
                    persistStagedAttachments()
                    return
                }

                // ⭐ ⇒ 👁 (included): starring forces non-private.
                AttachmentPrivacy.setPrivate(id: uuid, url: stableURL, false)
                selectedThumbnailID = uuid
                persistStagedAttachments()
            },
            isFavourite: { url in
                if let uuid = resolveStagedID(from: url) {
                    return selectedThumbnailID == uuid
                }
                return false
            },
            onTogglePrivacy: { url in
                guard let uuid = resolveStagedID(from: url) else { return }

                let stableURL: URL = {
                    if let a = stagedImages.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    if let a = stagedVideos.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    if let a = stagedAudio.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    return url
                }()

                let current = AttachmentPrivacy.isPrivate(id: uuid, url: stableURL)
                let next = !current
                AttachmentPrivacy.setPrivate(id: uuid, url: stableURL, next)

                // private ⇒ clear ⭐
                if next == true, selectedThumbnailID == uuid {
                    selectedThumbnailID = nil
                }

                persistStagedAttachments()
            },
            isPrivate: { url in
                guard let uuid = resolveStagedID(from: url) else { return true }

                let stableURL: URL = {
                    if let a = stagedImages.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    if let a = stagedVideos.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    if let a = stagedAudio.first(where: { $0.id == uuid }), let u = surrogateURL(for: a) { return u }
                    return url
                }()

                return AttachmentPrivacy.isPrivate(id: uuid, url: stableURL)
            },
            onReplaceAttachment: { oldURL, newURL, _ in
                if let uuid = resolveStagedID(from: oldURL) {
                    if let item = stagedVideos.first(where: { $0.id == uuid })
                        ?? stagedAudio.first(where: { $0.id == uuid })
                        ?? stagedImages.first(where: { $0.id == uuid }) {
                        handleTrimReplaceOriginal(from: newURL, for: item)
                    }
                }
            },
            onSaveAsNewAttachmentFromSource: { sourceURL, newURL, _ in
                if let uuid = resolveStagedID(from: sourceURL) {
                    if let item = stagedVideos.first(where: { $0.id == uuid })
                        ?? stagedAudio.first(where: { $0.id == uuid })
                        ?? stagedImages.first(where: { $0.id == uuid }) {
                        handleTrimSaveAsNew(from: newURL, basedOn: item)
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

}
