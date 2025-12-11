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
            let stem = url.deletingPathExtension().lastPathComponent
            if let uuid = UUID(uuidString: stem) { return uuid }
            // Fallback for audio: filename may be a sanitized title, not the UUID
            // Try to match by data size first, then by byte equality as a tie-breaker.
            guard let fileData = try? Data(contentsOf: url) else { return nil }
            // Prefer matching among stagedAudio
            if let match = stagedAudio.first(where: { $0.data.count == fileData.count }) {
                return match.id
            }
            if let exact = stagedAudio.first(where: { $0.data == fileData }) {
                return exact.id
            }
            // As a last resort, try videos/images by size (unlikely for audio but harmless)
            if let vm = stagedVideos.first(where: { $0.data.count == fileData.count }) { return vm.id }
            if let im = stagedImages.first(where: { $0.data.count == fileData.count }) { return im.id }
            return nil
        }

        return AttachmentViewerView(
            imageURLs: imageURLs,
            startIndex: startIndex,
            themeBackground: Color(.systemBackground),
            videoURLs: videoURLs,
            audioURLs: audioURLs,
            onDelete: { url in
                if let uuid = resolveStagedID(from: url) {
                    // Remove from matching staged arrays and caches
                    if let idx = stagedImages.firstIndex(where: { $0.id == uuid }) {
                        let removed = stagedImages.remove(at: idx)
                        if selectedThumbnailID == removed.id {
                            selectedThumbnailID = stagedImages.first(where: { $0.kind == .image })?.id
                        }
                        persistStagedAttachments()
                        return
                    }
                    if let idx = stagedVideos.firstIndex(where: { $0.id == uuid }) {
                        let removed = stagedVideos.remove(at: idx)
                        videoThumbnails.removeValue(forKey: removed.id)
                        if selectedThumbnailID == removed.id {
                            selectedThumbnailID = stagedImages.first?.id
                        }
                        persistStagedAttachments()
                        return
                    }
                    if let idx = stagedAudio.firstIndex(where: { $0.id == uuid }) {
                        let removed = stagedAudio.remove(at: idx)
                        audioTitles.removeValue(forKey: removed.id)
                        audioAutoTitles.removeValue(forKey: removed.id)
                        audioDurations.removeValue(forKey: removed.id)
                        if selectedThumbnailID == removed.id {
                            selectedThumbnailID = stagedImages.first?.id
                        }
                        persistStagedAttachments()
                        return
                    }
                }
            },
            onFavourite: { url in
                if let uuid = resolveStagedID(from: url) {
                    selectedThumbnailID = uuid
                    persistStagedAttachments()
                }
            },
            isFavourite: { url in
                if let uuid = resolveStagedID(from: url) {
                    return selectedThumbnailID == uuid
                }
                return false
            },
            onTogglePrivacy: { url in
                if let uuid = resolveStagedID(from: url) {
                    let current = AttachmentPrivacy.isPrivate(id: uuid, url: url)
                    AttachmentPrivacy.setPrivate(id: uuid, url: url, !current)
                }
            },
            isPrivate: { url in
                if let uuid = resolveStagedID(from: url) {
                    return AttachmentPrivacy.isPrivate(id: uuid, url: url)
                }
                return false
            }
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
                    onSaveAsNew: { newURL in
                        handleTrimSaveAsNew(from: newURL, basedOn: item)
                    },
                    onReplaceOriginal: { newURL in
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
