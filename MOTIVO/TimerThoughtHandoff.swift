//
//  TimerThoughtHandoff.swift
//  MOTIVO
//
//  SAVE A SPONTANEOUS RECORDING AS A THOUGHT, WITHOUT THE PRACTICE FLOW.
//
//  A member who records on the Practice Timer without starting practice can
//  save what they recorded as a Thought through `AddEditSessionView` in thought
//  mode. The hand-off is a COPY: the timer keeps its originals until the local
//  save has succeeded, and then consumes exactly the staged ids the editor
//  committed — never everything that was passed in, never anything else in the
//  draft, and never through a reset or a discard.
//
//  What lives here is the part the timer view cannot expose to a test (its
//  state is SwiftUI `@State`): the payload, the throwing builder, the
//  consumption rule, the final-id title migration the editor was missing, and
//  the presentation modifier. The timer and the editor are thin callers.
//

import Foundation
import SwiftUI

/// Everything one Save thought tap carries into the editor. Built once per
/// tap, after pending title edits are flushed; released when the sheet closes.
struct TimerThoughtHandoff: Identifiable {
    let id = UUID()
    /// The staged media, in the editor's form. Video bytes are materialised
    /// here, once, from the staged file — never on restore.
    let attachments: [StagedAttachment]
    /// The timer's staged ids the payload was built from. Only ids in this list
    /// AND in the editor's committed list are consumed.
    let sourceIDs: [UUID]
    let audioTitles: [UUID: String]
    let videoTitles: [UUID: String]
    /// The photo chosen as thumbnail, by staged id, if any.
    let thumbnailID: UUID?
    let threadLabel: String?
}

/// Why a hand-off could not be built. Shown to the member; the draft is kept.
enum TimerThoughtHandoffError: LocalizedError, Equatable {
    /// A clip has no `StagingStore` ref yet (its staging failed or has not
    /// landed), so a save could not consume it safely.
    case notStaged(kind: AttachmentKind)
    /// A staged video's file could not be read.
    case unreadable(kind: AttachmentKind)
    /// Staging is still in progress.
    case stagingInProgress
    case nothingToSave

    var errorDescription: String? {
        switch self {
        case .notStaged, .stagingInProgress:
            return "A recording isn’t ready to save yet. Wait a moment and try again, or remove it from the draft."
        case .unreadable:
            return "A recording could not be read. Nothing has been removed — try again, or remove it from the draft."
        case .nothingToSave:
            return "There is nothing to save yet."
        }
    }
}

@MainActor
enum TimerThoughtHandoffBuilder {

    /// Builds the payload or throws. Unlike `makeReviewPrefill()` (post-record
    /// details, unchanged), an unreadable or unstaged item FAILS the whole
    /// hand-off visibly rather than being dropped: a thought that silently
    /// lacks a clip would consume nothing for it and leave the member unsure
    /// what was saved.
    ///
    /// `ref(for:)` is the staging lookup, injected so a test can drive it with
    /// a disposable store root.
    static func make(audio: [StagedAttachment],
                     videos: [TimerStagedVideo],
                     images: [StagedAttachment],
                     audioTitles: [UUID: String],
                     videoTitles: [UUID: String],
                     thumbnailID: UUID?,
                     threadLabel: String?,
                     pendingStagingCount: Int,
                     ref: @MainActor (UUID) -> StagedAttachmentRef? = { StagingStore.ref(withId: $0) },
                     readVideo: (URL) throws -> Data = { try Data(contentsOf: $0) }) throws -> TimerThoughtHandoff {
        guard pendingStagingCount == 0 else { throw TimerThoughtHandoffError.stagingInProgress }
        guard !(audio.isEmpty && videos.isEmpty && images.isEmpty) else { throw TimerThoughtHandoffError.nothingToSave }

        var out: [StagedAttachment] = []
        var sourceIDs: [UUID] = []

        for att in images {
            guard let r = ref(att.id), r.kind == .image else { throw TimerThoughtHandoffError.notStaged(kind: .image) }
            out.append(StagedAttachment(id: att.id, data: att.data, kind: .image))
            sourceIDs.append(att.id)
        }
        for att in audio {
            guard let r = ref(att.id), r.kind == .audio else { throw TimerThoughtHandoffError.notStaged(kind: .audio) }
            out.append(StagedAttachment(id: att.id, data: att.data, kind: .audio))
            sourceIDs.append(att.id)
        }
        for video in videos {
            guard let r = ref(video.id), r.kind == .video else { throw TimerThoughtHandoffError.notStaged(kind: .video) }
            let url = StagingStore.absoluteURL(for: r)
            let data: Data
            do { data = try readVideo(url) } catch { throw TimerThoughtHandoffError.unreadable(kind: .video) }
            // C-85 — the video's REAL format travels with it: a trim is MP4, a
            // recording QuickTime.
            out.append(StagedAttachment(id: video.id, data: data, kind: .video,
                                        sourceFormat: TimerStagedVideo.format(forFile: url)))
            sourceIDs.append(video.id)
        }

        let ids = Set(sourceIDs)
        let trimmedTitles: ([UUID: String]) -> [UUID: String] = { map in
            var result: [UUID: String] = [:]
            for (id, raw) in map where ids.contains(id) {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { result[id] = t }
            }
            return result
        }
        let thumb = thumbnailID.flatMap { t in images.contains(where: { $0.id == t }) ? t : nil }

        return TimerThoughtHandoff(attachments: out,
                                   sourceIDs: sourceIDs,
                                   audioTitles: trimmedTitles(audioTitles),
                                   videoTitles: trimmedTitles(videoTitles),
                                   thumbnailID: thumb,
                                   threadLabel: threadLabel)
    }

    /// The ids the timer may consume after a successful local save: exactly
    /// the editor's committed staged ids that are also the payload's source
    /// ids and still staged in the timer. Anything else — an import made in the
    /// editor, a clip the member removed from the thought, an id consumed by an
    /// earlier save — is left alone. Safe to apply repeatedly.
    static func idsToConsume(committed: [UUID], sourceIDs: [UUID], stillStaged: Set<UUID>) -> [UUID] {
        let sources = Set(sourceIDs)
        var seen = Set<UUID>()
        return committed.filter { sources.contains($0) && stillStaged.contains($0) && seen.insert($0).inserted }
    }

    /// The thumbnail flag is applied against FINAL ids, so a thumbnail chosen
    /// among newly staged items must be translated through the attempt's map.
    /// An already persisted attachment keeps its id and passes through.
    static func finalThumbnailID(chosen: UUID?, attempt: AttachmentCommitAttempt) -> UUID? {
        guard let chosen else { return nil }
        return attempt.stagedToFinalID[chosen] ?? chosen
    }
}

/// The staged → final title migration `AddEditSessionView` lacked (post-record
/// details has had it since C-47). Runs ONLY after the Core Data save has
/// succeeded, through the one shared id-keyed writer.
enum StagedTitleMigration {
    static let stagedAudioNamesKey = "stagedAudioNames_temp"
    static let stagedVideoTitlesKey = "stagedVideoTitles_temp"

    /// Writes a persisted title for every committed audio and video attachment
    /// that had a staged one. `kind(of:)` resolves a staged id's kind.
    static func writeFinalTitles(for attempt: AttachmentCommitAttempt,
                                 kind: (UUID) -> AttachmentKind?,
                                 defaults: UserDefaults = .standard) {
        let audioNames = (defaults.dictionary(forKey: stagedAudioNamesKey) as? [String: String]) ?? [:]
        let videoTitles = (defaults.dictionary(forKey: stagedVideoTitlesKey) as? [String: String]) ?? [:]
        for stagedID in attempt.committedStagedIDs {
            guard let finalID = attempt.stagedToFinalID[stagedID] else { continue }
            switch kind(stagedID) {
            case .audio:
                if let raw = audioNames[stagedID.uuidString] {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        AttachmentTitlePersistenceKeys.writeLocalTitle(trimmed, kind: .audio, attachmentID: finalID, defaults: defaults)
                    }
                }
            case .video:
                if let raw = videoTitles[stagedID.uuidString] {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        AttachmentTitlePersistenceKeys.writeLocalTitle(trimmed, kind: .video, attachmentID: finalID, defaults: defaults)
                    }
                }
            default:
                break
            }
        }
    }

    /// Seeds the editor's staged-title maps from a hand-off, by staged id.
    static func seedStagedTitles(audio: [UUID: String], video: [UUID: String], defaults: UserDefaults = .standard) {
        if !audio.isEmpty {
            var dict = (defaults.dictionary(forKey: stagedAudioNamesKey) as? [String: String]) ?? [:]
            for (id, title) in audio { dict[id.uuidString] = title }
            defaults.set(dict, forKey: stagedAudioNamesKey)
        }
        if !video.isEmpty {
            var dict = (defaults.dictionary(forKey: stagedVideoTitlesKey) as? [String: String]) ?? [:]
            for (id, title) in video { dict[id.uuidString] = title }
            defaults.set(dict, forKey: stagedVideoTitlesKey)
        }
    }
}

extension AttachmentImportPolicy {
    /// C-85 — a trim's output names its own container (`.mp4`), a recorder's
    /// `.mov`. The editor's trim callbacks used to drop `sourceFormat`, so a
    /// trimmed video was persisted and declared as MOV. Only a format of the
    /// same kind is adopted; otherwise the previous one stands.
    static func format(forTrimOutput url: URL, kind: AttachmentKind, previous: MediaFormat?) -> MediaFormat? {
        if let f = MediaFormat.from(url: url), f.kind == kind { return f }
        return previous
    }
}

// MARK: - Presentation

/// The timer's Save thought presentation — the editor sheet, the hand-off error
/// and the recorder-state observation — as ONE modifier. `PracticeTimerView`'s
/// body is at the type-checker's limit, so these cannot be added inline.
struct TimerThoughtHandoffPresentation<Editor: View>: ViewModifier {
    @Binding var handoff: TimerThoughtHandoff?
    @Binding var errorMessage: String?
    @Binding var isRecording: Bool
    let editor: (TimerThoughtHandoff) -> Editor

    static var recorderStateNotification: Notification.Name {
        Notification.Name("etudesAudioRecorderRecordingStateDidChange")
    }

    func body(content: Content) -> some View {
        content
            // `.sheet(item:)`: ONE payload per presentation, released on dismiss.
            // Cancel and swipe-dismiss return to the same draft.
            .sheet(item: $handoff) { payload in
                editor(payload)
            }
            .alert("Couldn’t Save Thought",
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } }),
                   actions: { Button("OK", role: .cancel) {} },
                   message: { Text(errorMessage ?? "") })
            .onReceive(NotificationCenter.default.publisher(for: Self.recorderStateNotification)) { note in
                isRecording = (note.object as? Bool) ?? false
            }
    }
}

/// A brief confirmation in the app's existing hint style (see "Added to
/// Favourites"): fades in, holds, fades out. Shown where the member lands.
struct TransientNoticeView: View {
    @EnvironmentObject private var appRoute: AppRouteStore
    @State private var shown: String? = nil
    @State private var token = UUID()

    var body: some View {
        // A ZStack, not a Group: an empty Group renders nothing, so its
        // `onAppear`/`onChange` never fire and the notice would never show.
        ZStack(alignment: .top) {
            if let shown {
                Text(shown)
                    .font(Theme.Text.meta)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Capsule(style: .continuous).fill(.thinMaterial))
                    .padding(.top, Theme.Spacing.s)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: appRoute.transientNotice) { _, notice in
            guard let notice else { return }
            consume(notice)
        }
        .onAppear {
            if let notice = appRoute.transientNotice { consume(notice) }
        }
    }

    /// Shows the notice and clears the store outside the current view update.
    private func consume(_ notice: String) {
        present(notice)
        DispatchQueue.main.async {
            if appRoute.transientNotice == notice { appRoute.transientNotice = nil }
        }
    }

    private func present(_ text: String) {
        let t = UUID()
        token = t
        withAnimation(.easeInOut(duration: 0.15)) { shown = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard token == t else { return }
            withAnimation(.easeInOut(duration: 1.0)) { shown = nil }
        }
    }
}
