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

    @ViewBuilder
     func attachmentViewerView(for payload: PTVViewerURL) -> some View {
            // Build media URLs for the viewer. For this page, always launch the viewer for a single tapped video.
            let imageURLs: [URL] = []
            let audioURLs: [URL] = []
            let videoURLs: [URL] = [payload.url]

            let startIndex: Int = 0

            AttachmentViewerView(
                imageURLs: imageURLs,
                startIndex: startIndex,
                themeBackground: Color(.systemBackground),
                videoURLs: videoURLs,
                audioURLs: audioURLs
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
