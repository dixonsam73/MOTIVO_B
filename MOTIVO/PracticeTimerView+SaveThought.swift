//
//  PracticeTimerView+SaveThought.swift
//  MOTIVO
//
//  SAVE THOUGHT — a recording made on the timer before any practice has
//  started goes to the thought editor directly, without post-record details.
//  See `TimerThoughtHandoff.swift` for the rules; this file is the timer's
//  side: when the row shows, what a tap builds, and what a successful local
//  save consumes.
//

import SwiftUI

/// The timer's slate blue-grey (the recorder icons' colour), not the green
/// primary action: saving a thought is not starting a timed session.
private let saveThoughtSlate = Color(red: 0.44, green: 0.50, blue: 0.57)

extension PracticeTimerView {

    // MARK: - Availability

    /// Save thought shows when practice has not started since the last reset
    /// (including never) and at least one attachment is staged. The same shared
    /// check gates the "+" actions and the timer card's transport mode.
    var isSaveThoughtAvailable: Bool {
        !hasStartedSinceReset && hasAttachments
    }

    /// Disabled, with a quiet reason, while the recorder is recording or any
    /// staging is still landing. Enabled once every clip is safely staged.
    var saveThoughtDisabledReason: String? {
        if isAudioRecorderRecording { return "Recording…" }
        if !pendingStagingOps.isEmpty { return "Preparing recording…" }
        return nil
    }

    var saveThoughtCountLabel: String {
        let n = stagedAudio.count + stagedVideos.count + stagedImages.count
        if stagedImages.isEmpty {
            return n == 1 ? "1 recording" : "\(n) recordings"
        }
        return n == 1 ? "1 attachment" : "\(n) attachments"
    }

    // MARK: - The row

    @ViewBuilder
    var saveThoughtRow: some View {
        let reason = saveThoughtDisabledReason
        HStack(spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            Button {
                beginSaveThought()
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Save Thought")
                        .font(Theme.Text.body)
                    if let reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text(saveThoughtCountLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(saveThoughtSlate.opacity(reason == nil ? 1.0 : 0.55))
            .frame(maxWidth: 320, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(saveThoughtSlate.opacity(reason == nil ? 0.14 : 0.07))
            )
            .disabled(reason != nil)
            .accessibilityLabel("Save Thought")
            .accessibilityHint(reason ?? "Saves \(saveThoughtCountLabel) as a thought")
            .accessibilityIdentifier("button.saveThought")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The tap

    /// Builds the hand-off once per tap, after flushing pending title edits.
    /// Rechecks the shared gate at the moment of the tap; a failure shows an
    /// error and keeps the whole draft.
    func beginSaveThought() {
        guard isSaveThoughtAvailable else { return }
        guard saveThoughtDisabledReason == nil else { return }
        stopAttachmentPlayback()
        commitAudioTitleEditingBuffers()
        showAddEntryActions = false
        do {
            thoughtHandoff = try makeThoughtHandoff()
        } catch {
            saveThoughtErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "The recording could not be prepared. Nothing has been removed — please try again."
        }
    }

    func makeThoughtHandoff() throws -> TimerThoughtHandoff {
        // Video titles may come from either of the timer's two stores: the
        // persisted map, or the viewer's rename map.
        let viewerTitles = (UserDefaults.standard.dictionary(forKey: PracticeTimerView.ptvVideoTitlesDefaultsKey) as? [String: String]) ?? [:]
        var mergedVideoTitles = videoTitles
        for video in stagedVideos where mergedVideoTitles[video.id] == nil {
            if let t = viewerTitles[video.id.uuidString] { mergedVideoTitles[video.id] = t }
        }
        return try TimerThoughtHandoffBuilder.make(
            audio: stagedAudio,
            videos: stagedVideos,
            images: stagedImages,
            audioTitles: audioTitles,
            videoTitles: mergedVideoTitles,
            thumbnailID: selectedThumbnailID,
            threadLabel: selectedProvisionalThreadLabelForReview,
            pendingStagingCount: pendingStagingOps.count)
    }

    // MARK: - The editor

    @ViewBuilder
    func thoughtHandoffEditor(for payload: TimerThoughtHandoff) -> some View {
        AddEditSessionView(
            isThoughtMode: true,
            threadLabelPrefill: payload.threadLabel,
            prefillAttachments: payload.attachments,
            prefillAudioTitles: payload.audioTitles,
            prefillVideoTitles: payload.videoTitles,
            prefillThumbnailID: payload.thumbnailID,
            onLocalCommit: { committed in
                consumeStagedAttachmentsSavedAsThought(committed, sourceIDs: payload.sourceIDs)
            },
            onSuccessfulSave: {
                thoughtHandoff = nil
                appRoute.transientNotice = "Thought saved"
                if isHomePresentation {
                    DispatchQueue.main.async {
                        appRoute.route = .content
                    }
                } else {
                    isPresented = false
                }
            }
        )
    }

    // MARK: - Consumption

    /// Runs when the editor's Core Data save has succeeded — inside its
    /// finalisation, independent of the Connected upload or the sharing alert.
    /// Removes exactly the committed source ids from the store and from the
    /// draft (items, titles, durations, posters, thumbnail, persisted id
    /// arrays). Everything else is kept: left-out clips, list content, thread,
    /// activity, instrument. Never a reset, never a discard; safe to repeat;
    /// never a permanent file.
    func consumeStagedAttachmentsSavedAsThought(_ committed: [UUID], sourceIDs: [UUID]) {
        let stillStaged = Set(stagedAudio.map(\.id) + stagedVideos.map(\.id) + stagedImages.map(\.id))
        let ids = TimerThoughtHandoffBuilder.idsToConsume(committed: committed, sourceIDs: sourceIDs, stillStaged: stillStaged)
        guard !ids.isEmpty else { return }
        let doomed = Set(ids)

        stopAttachmentPlayback()

        // The timer's own tmp surrogates for these ids (viewer copies, posters).
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        for id in ids {
            for name in ["\(id.uuidString).m4a", "\(id.uuidString).jpg", "\(id.uuidString).mov",
                         "\(id.uuidString).mp4", "\(id.uuidString)_poster.jpg"] {
                try? fm.removeItem(at: tmp.appendingPathComponent(name))
            }
        }

        stagedAudio.removeAll { doomed.contains($0.id) }
        audioTitles = audioTitles.filter { !doomed.contains($0.key) }
        audioAutoTitles = audioAutoTitles.filter { !doomed.contains($0.key) }
        audioDurations = audioDurations.filter { !doomed.contains($0.key) }
        audioTitleEditingBuffer = audioTitleEditingBuffer.filter { !doomed.contains($0.key) }

        stagedVideos.removeAll { doomed.contains($0.id) }
        videoThumbnails = videoThumbnails.filter { !doomed.contains($0.key) }
        videoTitles = videoTitles.filter { !doomed.contains($0.key) }
        var viewerTitles = (UserDefaults.standard.dictionary(forKey: PracticeTimerView.ptvVideoTitlesDefaultsKey) as? [String: String]) ?? [:]
        for id in ids { viewerTitles.removeValue(forKey: id.uuidString) }
        UserDefaults.standard.set(viewerTitles, forKey: PracticeTimerView.ptvVideoTitlesDefaultsKey)

        stagedImages.removeAll { doomed.contains($0.id) }
        if let t = selectedThumbnailID, doomed.contains(t) { selectedThumbnailID = nil }

        // The ONE staging removal on this path: these ids and no others. The
        // files behind saved attachments are permanent media, outside staging.
        StagingStore.removeMany(ids: ids)

        persistStagedAttachments()
        if !hasAttachments {
            UserDefaults.standard.set(false, forKey: ephemeralMediaFlagKey)
            isAttachmentsVisible = false
        }
    }
}
