// CHANGE-ID: 20260607_222700_AESV_PDF_CAPTION_PARITY
// SCOPE: AddEditSessionView — move staged PDF display-name caption inside the AESV attachment tile cell so it renders below the thumbnail.
// SEARCH-TOKEN: 20260607_222700_AESV_PDF_CAPTION_PARITY

// CHANGE-ID: 20260607_213500_AESVPDFDisplayName
// SCOPE: AddEditSessionView — render staged PDF display names below AESV thumbnail tiles only; no persistence/import/viewer/backend changes.
// SEARCH-TOKEN: 20260607_213500_AESV_PDF_DISPLAY_NAME

// CHANGE-ID: 20260606_171500_AESVDocumentAttachmentCardParity
// SCOPE: AddEditSessionView — include document attachments (.file and .pdf) in AESV attachment card grid. No persistence/import/viewer/backend changes.
// SEARCH-TOKEN: 20260606_171500_AESVDocumentAttachmentCardParity

// CHANGE-ID: 20260605_201500_AESV_PickerExtract
// SCOPE: AddEditSessionView — extract picker sheet/view-builder helpers into AddEditSessionView+Pickers without UI or logic changes.
// SEARCH-TOKEN: 20260605_201500_AESV_PickerExtract

// CHANGE-ID: 20260604_204500_SelectorCards_AESV
// SCOPE: Replace AESV instrument/activity wheel pickers with card-sheet selector rows only. No persistence/model/date/duration changes.
// SEARCH-TOKEN: 20260604_204500_SelectorCards_AESV

// CHANGE-ID: 20260517_173800_AESV_FloatingMetadataParity
// SCOPE: AddEditSessionView visual-only — port PRDV floating metadata row language to AESV/Thought mode; remove metadata card/tint treatment while preserving Focus/Notes/Attachments/save behaviours.
// SEARCH-TOKEN: 20260517_173800_AESV_FloatingMetadataParity

// CHANGE-ID: 20260513_081900_AESV_ThoughtThreadSupport
// SCOPE: AddEditSessionView — allow optional Thread selection in Thought mode and preserve Thought threadLabel on save. No analytics/filter/UI redesign changes.
// SEARCH-TOKEN: 20260513_081900_AESV_ThoughtThreadSupport

// CHANGE-ID: 20260501_224500_AESV_ShareToggleInline
// SCOPE: AESV visibility card — remove redundant “On” label and place Share with followers inline with the toggle. No logic or persistence changes.
// SEARCH-TOKEN: 20260501_224500_AESV_ShareToggleInline

// CHANGE-ID: 20260317_183800_AESV_AutoDescriptionReplaceOnFocus
// SCOPE: AddEditSessionView — make untouched auto description clear on first focus and restore current auto description on blur if left empty. No other UI or logic changes.
// SEARCH-TOKEN: 20260317_183800_AESV_AutoDescriptionReplaceOnFocus

// CHANGE-ID: 20260304_144500_Threads_S6_1_AESV_ThreadSuggestions
// SCOPE: Threads v1 Stage 6.1 — provide existing local thread suggestions to ThreadPickerView when launched from AESV. No other UI/logic changes.
// SEARCH-TOKEN: 20260304_144500_Threads_S6_1_AESV_ThreadSuggestions

// CHANGE-ID: 20260304_124500_Threads_S4R2_AESV_TypecheckFix
// SCOPE: AESV Threads v1 — Fix SwiftUI type-check timeout by extracting body content stack into a @ViewBuilder computed property. No UI/logic changes beyond Stage 4 Threads scope.
// SEARCH-TOKEN: 20260304_124500_Threads_S4R2_AESV_TypecheckFix
// CHANGE-ID: 20260304_122500_Threads_S4R_AESV_ThreadCardVisibleAndPersist
// SCOPE: AESV Threads v1 — add visible Thread selector card under Description; bind to Session.threadLabel on hydrate+save; present ThreadPickerView. No other UI/logic changes.
// SEARCH-TOKEN: 20260304_122500_Threads_S4R_AESV_ThreadCardVisibleAndPersist

// CHANGE-ID: 20260227_223900_AESV_desc_pencil_focusDismiss
// SCOPE: AESV visual-only — add pencil affordance to Description editable line (hide while editing) + dismiss keyboard/focus for Description + Notes on tap/scroll. No other UI/logic changes.
// SEARCH-TOKEN: 20260227_223900_AESV_desc_pencil_focusDismiss

// CHANGE-ID: 20260225_122845_AESV_ThumbIconParity_00e0df34
// SCOPE: AESV attachment thumbnails — overlay icon parity with PRDV (eye/eye.slash indicators; hide privacy only when starred; audio star toggles). UI-only; no other logic changes.
// SEARCH-TOKEN: 20260225_122845_AESV_ThumbIconParity_00e0df34

// CHANGE-ID: 20260225_093600_aesv_audio_saveas_titles
// SCOPE: AESV: seed stagedAudioNames_temp for audio Save-as-New to retain title + _n suffix; naming-only
// SEARCH-TOKEN: TRIM_NOORPHANS_20260224_135000_AESV_HELPER_FIX
// CHANGE-ID: 20260224_125814_TrimPersist_NoOrphans
// SCOPE: Trim Persistence Canonicalization — eliminate duplicate/orphan container siblings (PRDV + AESV staged-byte paths only)
// SEARCH-TOKEN: 20260224_095210_AESV_AudioReplacePersistFix_v2_Token

// CHANGE-ID: 20260222_195620_AESV_TmpHygieneHardening
// SCOPE: Local filesystem hygiene hardening — best-effort cleanup of AESV tmp surrogate/alias files on remove, cancel, and successful save. No UI/behavior changes.
// SEARCH-TOKEN: 20260222_195620_AESV_TmpHygieneHardening

// CHANGE-ID: 20260222_141200_AESV_DeletePersist_Warn50MB
// SCOPE: AESV: persist local attachment deletions on save (existing Core Data attachments) + warn on Files-picker attachments >50MB that they will remain local and not publish. No UI/layout changes beyond a single alert.
// SEARCH-TOKEN: 20260222_141200_AESV_DeletePersist_Warn50MB

// CHANGE-ID: 20260209_123100_AESV_StarPersistParity_7c2d3f
// SCOPE: AESV: allow clearing ⭐ to persist (no forced single-image thumbnail); AVV favourite toggle now mirrors AESV toggle + ⭐⇒👁; no UI/layout changes.
// SEARCH-TOKEN: 20260209_113255_AESV_StarToggle_VisualGrid

// CHANGE-ID: 20260130_155652_ShareTogglePersist
// SCOPE: AESV: pass isPublic into PostPublishPayload and always publish on save; Share toggle only sets visibility.
// SEARCH-TOKEN: AESV_VISUAL_PARITY_20260106_214417

// CHANGE-ID: 20260105_183654-aesv-thumb-inclusion-invariants-3109c299
// SCOPE: AESV: remove auto-thumbnail defaults; enforce ⭐⇒👁; privacy→private clears thumbnail; suppress eye badge when starred; gate invalid persisted thumbnails
// CHANGE-ID: 20260103_205708
// SCOPE: Fix AESV AttachmentViewer privacy sync by resolving attachment ID via viewer index (handles persisted URLs). Default unknown => private.

// CHANGE-ID: 20251228_210200-aesv-videoTitleParityFix-01
// SCOPE: AESV video title routing: staged temp titles only for unsaved videos; persisted videos read/write canonical persistedVideoTitles_v1 only; no other logic/UI changes.

// CHANGE-ID: 20251227_163900-aesv-renamewire-audioAliasURL-01
// SCOPE: Wire AttachmentViewer rename callbacks for AESV staged audio/video titles (UserDefaults temp maps) + refresh tick; no other UI/logic changes.
// CHANGE-ID: 20251219_160900-aesv-replace-urlmap-01
// SCOPE: Fix Replace mapping for existing attachments (update Core Data fileURL + URL map); no UI changes.
// CHANGE-ID: 20251218_211500-aesv-attachviewerfixAB-7bbd
// SCOPE: Scope A+B — Harden viewer URL population for staged audio/video + wire audio row controls
// CHANGE-ID: 20251008_172540_aa2f1
// SCOPE: Visual-only — tint add buttons to light grey; remove notes placeholder; hide empty attachments message
// CHANGE-ID: 20260421_191200_AESV_TintResolver_6d2a
// SCOPE: AESV — replace instrument-only metadata card tint path with shared tint resolver. No layout, flow, persistence, or non-tint logic changes.
// SEARCH-TOKEN: 20260421_191200_AESV_TintResolver_6d2a

//  AddEditSessionView.swift
//  MOTIVO
//
//  [ROLLBACK ANCHOR] v7.8 DesignLite — pre
//
//  v7.8 — Edit thumbnails: preload existing images safely
//  - Preload uses only known fields (id, kind, fileURL, isThumbnail).
//  - Image bytes resolved from: absolute path → file:// URL → relative-in-Documents.
//  - Avoids duplicating existing attachments on Save; updates cover flag.
//  - No schema/migrations. No other behaviour changes.
//

// CHANGE-ID: 20260605_192500_AESV_AttachmentPass1
// SCOPE: AddEditSessionView — extract attachment viewer/plumbing into AddEditSessionView+Attachments without UI or logic changes.
// SEARCH-TOKEN: 20260605_192500_AESV_AttachmentPass1

import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

// MARK: - Threads v1 Stage 6.1 (AESV) — local suggestions
fileprivate enum ThreadLabelSanitizer_Stage6_1_AESV {
    static let maxLength: Int = 32

    static func sanitize(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.isEmpty { return nil }
        if collapsed.count <= maxLength { return collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<idx])
    }
}

fileprivate func uniqueSortedThreadOptions_Stage6_1_AESV(_ raw: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    out.reserveCapacity(min(raw.count, 32))
    for s in raw {
        guard let clean = ThreadLabelSanitizer_Stage6_1_AESV.sanitize(s) else { continue }
        let key = clean.lowercased()
        if seen.contains(key) { continue }
        seen.insert(key)
        out.append(clean)
    }
    out.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    return out
}







struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Editing existing session or creating new
    var session: Session? = nil
    var onSuccessfulSave: (() -> Void)? = nil
    var isThoughtMode: Bool = false
    var threadLabelPrefill: String? = nil

    // Form state
    @State var instruments: [Instrument] = []
    @State var instrument: Instrument?
    @State var timestamp: Date = Date()
    @State var durationSeconds: Int = 0
    @State var activity: SessionActivityType = .practice

    // Activity description (short detail) + defaulting logic
    @State private var activityDetail: String = ""
    @State private var lastAutoActivityDetail: String = ""     // tracks the last generated default
    @State private var userEditedActivityDetail: Bool = false  // breaks auto-sync once user types
    @State private var userHasEditedActivityDetail: Bool = false

    // User-local activities + selection
    @State var userActivities: [UserActivity] = []
    /// String selector used by the wheel: "core:<raw>" or "custom:<name>"
    @State var activityChoice: String = "core:0"
    /// If user picked a custom activity, hold its name separately (do NOT store in activityDetail)
    @State var selectedCustomName: String = ""

    // Threads v1 (owner-only metadata)
    @State private var threadLabel: String? = nil
    @State private var showThreadPicker: Bool = false

    private var existingThreadOptions: [String] {
        guard let uid = PersistenceController.shared.currentUserID, !uid.isEmpty else { return [] }
        let req = NSFetchRequest<Session>(entityName: "Session")
        req.predicate = NSPredicate(format: "ownerUserID == %@ AND threadLabel != nil AND threadLabel != ''", uid)
        req.fetchLimit = 500
        do {
            let results = try viewContext.fetch(req)
            let raw = results.compactMap { $0.threadLabel }
            return uniqueSortedThreadOptions_Stage6_1_AESV(raw)
        } catch {
            return []
        }
    }


    @State private var isPublic: Bool = true
    @State private var notes: String = ""
    @State private var areNotesPrivate_edit: Bool = false

    // Focus (UI-only) — used to dismiss cursor/keyboard on tap away
    @FocusState private var isActivityDetailFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @State private var notesKeyboardInset: CGFloat = 0

    // Wheels
    @State var showStartPicker = false
    @State var showDurationPicker = false
    @State var showActivityPicker = false
    @State var showInstrumentPicker = false
    @State var tempDate = Date()
    @State var tempHours = 0
    @State var tempMinutes = 0

    // Attachments
    @State var stagedAttachments: [StagedAttachment] = []
    @State var selectedThumbnailID: UUID? = nil
    @State var showPhotoPicker = false
    @State var showFileImporter = false
    @State var showCamera = false
    @State var photoPickerItem: PhotosPickerItem?
    @State var showCameraDeniedAlert = false
    @State var showPublishLimitAlert = false
    @State var publishLimitAlertMessage: String = ""


    @State var viewerRequest: AESVAttachmentViewerRequest? = nil
    @State var attachmentTitlesRefreshTick: Int = 0

    // UI stability (instruments empty-state)
    @State private var instrumentsGateArmed = false
    @State private var instrumentsReady = false

    // Track which staged attachments came from Core Data (existing) to prevent duplication on save
    @State var existingAttachmentIDs: Set<UUID> = []

    // Track existing (Core Data) attachment IDs that were deleted in AESV so we can delete them from Core Data on save.
    @State var deletedExistingAttachmentIDs: Set<UUID> = []

    static let publishUploadLimitBytes: Int64 = 50 * 1024 * 1024


    // Map existing (Core Data) attachment IDs to their resolved on-disk URLs so the viewer can play audio/video without relying on staged bytes.
    @State var existingAttachmentURLMap: [UUID: URL] = [:]

    // Primary Activity persisted ref
    @AppStorage("primaryActivityRef") var primaryActivityRef: String = "core:0"
    @AppStorage("appSettings_tintMode") private var tintModeRawValue: String = Theme.TintMode.auto.rawValue
    @State private var cachedMetadataCardTint: Theme.ResolvedTint = Theme.ResolvedTint(source: .off, instrumentLabel: nil, activityLabel: nil)

    // v7.9E — State circles (12-dot gradient, dark → light, drag select)
    private let stateDotsCount_edit: Int = 12

    @State private var selectedDotIndex_edit: Int? = nil
    @State private var hoverDotIndex_edit: Int? = nil        // transient during drag
    @State private var dragX_edit: CGFloat? = nil            // live finger x
    @State private var lastHapticDot_edit: Int? = nil        // per-dot haptic throttle
    @State private var liveFocusProgress_edit: CGFloat? = nil

    private let focusSnapCount_edit: Int = 10

    private func storedFocusValue_edit(forVisualFocusValue visualValue: Int) -> Int {
        FocusCircleView.storedFocusValue(forVisualFocusValue: visualValue)
    }

    private func visualFocusValue_edit(forStoredFocusValue storedValue: Int?) -> Int? {
        FocusCircleView.visualFocusValue(forStoredFocusValue: storedValue)
    }

    private func updateFocusFromTrack_edit(locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }

        let clampedX = max(0, min(locationX, width))
        let progress = clampedX / width
        let visualValue = visualFocusValue_edit(forProgress: progress)
        let storedValue = storedFocusValue_edit(forVisualFocusValue: visualValue)

        liveFocusProgress_edit = progress
        selectedDotIndex_edit = storedValue

        if lastHapticDot_edit != visualValue {
            lastHapticDot_edit = visualValue
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }

    private func visualFocusValue_edit(forProgress progress: CGFloat) -> Int {
        max(1, min(focusSnapCount_edit, Int(round(progress * CGFloat(focusSnapCount_edit - 1))) + 1))
    }

    private func progressForVisualFocusValue_edit(_ visualValue: Int?) -> CGFloat? {
        guard let visualValue else { return nil }
        return CGFloat(max(1, min(focusSnapCount_edit, visualValue)) - 1) / CGFloat(focusSnapCount_edit - 1)
    }

    private func settleFocusTrackAfterDrag_edit() {
        let snappedProgress = progressForVisualFocusValue_edit(visualFocusValue_edit(forStoredFocusValue: selectedDotIndex_edit))
        withAnimation(.easeOut(duration: 0.16)) {
            liveFocusProgress_edit = snappedProgress
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            liveFocusProgress_edit = nil
        }
    }

    /// DARK → LIGHT across the row (left→right). Use textPrimary so it reads in dark mode.
    private func opacityForDot_edit(_ i: Int) -> Double {
        // 0 = darkest (high opacity), 11 = lightest (low opacity)
        let start: Double = 0.95   // darker (more opaque) on the left
        let end:   Double = 0.15   // lighter (less opaque) on the right
        guard stateDotsCount_edit > 1 else { return start }
        let t = Double(i) / Double(stateDotsCount_edit - 1)
        return start + (end - start) * t
    }

    /// Visual “center” dot per zone — ring this for consistency.
    private func centerDot_edit(for zone: Int) -> Int {
        switch zone { case 0: return 1; case 1: return 4; case 2: return 7; default: return 10 }
    }
    // ---- Privacy cache & helpers (ID-first, URL-fallback) ----
    @State var privacyMap: [String: Bool] = [:]

    func privacyKey(id: UUID?, url: URL?) -> String? {
        if let id { return "id://\(id.uuidString)" }
        if let url { return url.absoluteString }
        return nil
    }

    func loadPrivacyMap() {
        privacyMap = (UserDefaults.standard.dictionary(forKey: AttachmentPrivacy.mapKey) as? [String: Bool]) ?? [:]
    }

    func isPrivate(id: UUID?, url: URL?) -> Bool {
        if let key = privacyKey(id: id, url: url) {
            if let v = privacyMap[key] { return v }
            return AttachmentPrivacy.isPrivate(id: id, url: url)
        }
        return true
    }

    func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        // Update local cache first for instant UI
        privacyMap[key] = value
        // Persist via centralized helper (also posts didChange notification)
        AttachmentPrivacy.setPrivate(id: id, url: url, value)
    }
    // ---- end privacy helpers ----

    // Persisted audio title overrides (existing store)
    let persistedAudioTitlesKey = "persistedAudioTitles_v1"
    func loadPersistedAudioTitles() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
    }

    // Persisted video title overrides (existing store)
    let persistedVideoTitlesKey = "persistedVideoTitles_v1"
    func loadPersistedVideoTitles() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: persistedVideoTitlesKey) as? [String: String]) ?? [:]
    }

    /// Remove the `FocusDotIndex:` and `StateIndex:` lines from `notes` for clean UI display.
    private func stripFocusTokensFromNotes_edit() {
        let tokens = ["FocusDotIndex:", "StateIndex:"]
        for t in tokens {
            while let r = notes.range(of: t) {
                let tail = notes[r.upperBound...]
                let end = tail.firstIndex(of: "\n") ?? notes.endIndex
                notes.removeSubrange(r.lowerBound..<end)
                if notes.hasSuffix("\n\n") { notes.removeLast() }
            }
        }
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Preselect from notes if a FocusDotIndex or legacy StateIndex exists
    private func preselectFocusFromNotesIfNeeded_edit() {
        guard selectedDotIndex_edit == nil, !notes.isEmpty else { return }

        if let r = notes.range(of: "FocusDotIndex:") {
            let tail = notes[r.upperBound...]
            let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if let n = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), (0...11).contains(n) {
                selectedDotIndex_edit = n
                stripFocusTokensFromNotes_edit()
                return
            }
        }

        // Back-compat from legacy StateIndex: 0–3 → center dots
        if let r = notes.range(of: "StateIndex:") {
            let tail = notes[r.upperBound...]
            let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if let n = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), (0...3).contains(n) {
                let centers = [1, 4, 7, 10]
                selectedDotIndex_edit = centers[n]
                stripFocusTokensFromNotes_edit()
            }
        }
    }

    /// Preselect from the structural Session.effort value when no note token exists.
    private func preselectFocusFromSessionEffortIfNeeded_edit(_ session: Session?) {
        guard selectedDotIndex_edit == nil else { return }
        guard let session else { return }
        guard session.entity.attributesByName.keys.contains("effort") else { return }

        let effortDot = Int(session.effort)
        selectedDotIndex_edit = (effortDot == 5) ? nil : effortDot
    }

    /// Apply/replace the FocusDotIndex line before saving
    private func applyFocusToNotesBeforeSave_edit() {
        // Notes must remain user-entered text only.
        // Focus is stored structurally (Session.effort / publish payload effort).
        stripFocusTokensFromNotes_edit()
    }

    init(
        session: Session? = nil,
        isThoughtMode: Bool = false,
        threadLabelPrefill: String? = nil,
        onSuccessfulSave: (() -> Void)? = nil
    ) {
        self.session = session
        self.onSuccessfulSave = onSuccessfulSave
        self.isThoughtMode = isThoughtMode || (session?.isThought ?? false)
        self.threadLabelPrefill = threadLabelPrefill
        // Seed time-related fields on edit so they don’t flash empty
        if let s = session {
            if let ts = s.timestamp { _timestamp = State(initialValue: ts) }
            _durationSeconds = State(initialValue: Int(s.durationSeconds))

            // Threads v1 (owner-only metadata)
            if s.entity.attributesByName.keys.contains("threadLabel") {
                let raw = (s.value(forKey: "threadLabel") as? String) ?? ""
                _threadLabel = State(initialValue: sanitizeThreadLabel_v1(raw))
            }
        } else if let clean = sanitizeThreadLabel_v1(threadLabelPrefill) {
            _threadLabel = State(initialValue: clean)
        }
    }

    private var isEdit: Bool { session != nil }
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    private var aesvTintMode: Theme.TintMode {
        Theme.TintMode(rawValue: tintModeRawValue) ?? .auto
    }

    private var effectiveInstrumentTintLabel: String? {
        if let selectedName = instrument?.name,
           let normalized = Theme.InstrumentTint.normalizedLabel(selectedName) {
            return normalized
        }

        if hasMultipleInstruments,
           let fallbackName = instrument?.name ?? instruments.first?.name,
           let normalized = Theme.InstrumentTint.normalizedLabel(fallbackName) {
            return normalized
        }

        if let onlyName = instruments.first?.name,
           let normalized = Theme.InstrumentTint.normalizedLabel(onlyName) {
            return normalized
        }

        return nil
    }

    private var effectiveActivityTintLabel: String? {
        let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmedCustom.isEmpty ? activity.label : trimmedCustom
        return Theme.ActivityTint.normalizedLabel(display)
    }

    private var tintOwnerID: String? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        #endif

        if let persistenceID = PersistenceController.shared.currentUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !persistenceID.isEmpty {
            return persistenceID
        }

        return nil
    }

    private func normalizedInstrumentLabel(for item: Session) -> String? {
        if let label = item.userInstrumentLabel,
           let normalized = Theme.InstrumentTint.normalizedLabel(label) {
            return normalized
        }

        if let instrument = item.instrument,
           let name = instrument.name,
           let normalized = Theme.InstrumentTint.normalizedLabel(name) {
            return normalized
        }

        return nil
    }

    private func normalizedActivityLabel(for item: Session) -> String? {
        let trimmedCustom = (item.userActivityLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty,
           let normalized = Theme.ActivityTint.normalizedLabel(trimmedCustom) {
            return normalized
        }

        if let activity = SessionActivityType(rawValue: item.activityType),
           let normalized = Theme.ActivityTint.normalizedLabel(activity.label) {
            return normalized
        }

        return nil
    }

    private func recomputeMetadataCardTintIfNeeded() {
        let currentInstrument = effectiveInstrumentTintLabel
        let currentActivity = effectiveActivityTintLabel

        guard let ownerID = tintOwnerID else {
            cachedMetadataCardTint = Theme.resolvedTint(
                instrument: currentInstrument,
                activity: currentActivity,
                tintMode: aesvTintMode,
                instrumentCounts: [:],
                activityCounts: [:]
            )
            return
        }

        let request = NSFetchRequest<Session>(entityName: "Session")
        request.predicate = NSPredicate(format: "ownerUserID == %@", ownerID)
        request.fetchBatchSize = 256

        do {
            let sessions = try viewContext.fetch(request)

            var instrumentCounts: [String: Int] = [:]
            instrumentCounts.reserveCapacity(16)
            var activityCounts: [String: Int] = [:]
            activityCounts.reserveCapacity(16)

            for item in sessions {
                if let instrumentLabel = normalizedInstrumentLabel(for: item) {
                    instrumentCounts[instrumentLabel, default: 0] += 1
                }
                if let activityLabel = normalizedActivityLabel(for: item) {
                    activityCounts[activityLabel, default: 0] += 1
                }
            }

            cachedMetadataCardTint = Theme.resolvedTint(
                instrument: currentInstrument,
                activity: currentActivity,
                tintMode: aesvTintMode,
                instrumentCounts: instrumentCounts,
                activityCounts: activityCounts
            )
        } catch {
            cachedMetadataCardTint = Theme.resolvedTint(
                instrument: currentInstrument,
                activity: currentActivity,
                tintMode: aesvTintMode,
                instrumentCounts: [:],
                activityCounts: [:]
            )
        }
    }

    private var instrumentCardFillColor: Color {
        guard cachedMetadataCardTint.source == .instrument else {
            return Theme.Colors.surface(colorScheme)
        }

        return cachedMetadataCardTint.fill(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var instrumentCardStrokeColor: Color {
        guard cachedMetadataCardTint.source == .instrument else {
            return Theme.Colors.cardStroke(colorScheme)
        }

        return cachedMetadataCardTint.stroke(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var activityCardFillColor: Color {
        guard cachedMetadataCardTint.source == .activity else {
            return Theme.Colors.surface(colorScheme)
        }

        return cachedMetadataCardTint.fill(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var activityCardStrokeColor: Color {
        guard cachedMetadataCardTint.source == .activity else {
            return Theme.Colors.cardStroke(colorScheme)
        }

        return cachedMetadataCardTint.stroke(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    var body: some View {
    NavigationStack {
        ScrollView {
                        contentStack
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: isNotesFocused ? notesKeyboardInset : 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }

            let screenHeight = UIScreen.main.bounds.height
            notesKeyboardInset = max(0, screenHeight - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            notesKeyboardInset = 0
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                isActivityDetailFocused = false
                isNotesFocused = false
            }
        )
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    cancelAndCleanup_AESV_bestEffort()
                }
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .sheet(isPresented: $showInstrumentPicker) {
            instrumentPicker
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showActivityPicker) {
            activityPickerPinned
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showThreadPicker) { ThreadPickerView(selectedThread: $threadLabel, recentThreads: existingThreadOptions) }
        .sheet(isPresented: $showStartPicker) { startPicker }
        .sheet(isPresented: $showDurationPicker) { durationPicker }
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $photoPickerItem,
                      matching: .any(of: [.images, .videos]))
        .task(id: photoPickerItem) {
            guard let item = photoPickerItem else { return }
            if let contentType = item.supportedContentTypes.first {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    if contentType.conforms(to: .image) {
                        stageData(data, kind: .image)
                    } else if contentType.conforms(to: .movie) {
                        stageData(data, kind: .video)
                    } else {
                        stageData(data, kind: .file)
                    }
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                stageData(data, kind: .file)
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
                       if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                   }
               },
               message: { Text("Enable camera access in Settings → Privacy → Camera to take photos.") })
        .alert("Publish limit",
               isPresented: $showPublishLimitAlert,
               actions: { Button("OK", role: .cancel) {} },
               message: { Text(publishLimitAlertMessage) })
        .fullScreenCover(item: $viewerRequest) { req in
            let imageURLs: [URL] = (req.mode == .visual) ? req.imageURLs : []
            let videoURLs: [URL] = (req.mode == .visual) ? req.videoURLs : []
            let audioURLs: [URL] = (req.mode == .audio) ? req.audioURLs : []
            let pdfURLs: [URL] = (req.mode == .visual) ? req.pdfURLs : []
            let combined = imageURLs + videoURLs + audioURLs + pdfURLs
            let startIndex = min(max(req.startIndex, 0), max(combined.count - 1, 0))

            let viewerAttachmentIDs: [UUID] = req.viewerAttachmentIDs

            let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
            let persistedTitles = loadPersistedAudioTitles()
            let audioTitles: [String] = audioURLs.enumerated().map { index, u in
                let fallbackStem = u.deletingPathExtension().lastPathComponent
                guard index < viewerAttachmentIDs.count else { return fallbackStem }
                let attID = viewerAttachmentIDs[index]

                // Prefer persisted override; then staged map; finally fall back to stem
                let persisted = (persistedTitles[attID.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !persisted.isEmpty { return persisted }
                let staged = (namesDict[attID.uuidString] ?? fallbackStem).trimmingCharacters(in: .whitespacesAndNewlines)
                return staged.isEmpty ? fallbackStem : staged
            }

attachmentViewer_AESV(imageURLs: imageURLs, startIndex: startIndex, videoURLs: videoURLs, audioURLs: audioURLs, pdfURLs: pdfURLs, audioTitles: audioTitles, req: req)
        }
        .task { hydrate() } // unified first-appearance init
        .onAppear {
            preselectFocusFromNotesIfNeeded_edit()
            syncActivityChoiceFromState()
            loadPrivacyMap()
            // Ensure token is hidden in Notes whenever view appears
            stripFocusTokensFromNotes_edit()
        }
        .onAppear {
            recomputeMetadataCardTintIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AttachmentPrivacy.didChangeNotification)) { _ in
            loadPrivacyMap()
        }
        .onChange(of: activity) { _, _ in
            maybeUpdateActivityDetailFromDefaults()
        }
        .onChange(of: timestamp) { _, _ in
            maybeUpdateActivityDetailFromDefaults()
        }
        .onChange(of: timestamp) { _, _ in maybeUpdateActivityDetailFromDefaults_v2() }
        .onChange(of: activity) { _, _ in maybeUpdateActivityDetailFromDefaults_v2() }
        .onChange(of: tintModeRawValue) {
            recomputeMetadataCardTintIfNeeded()
        }
        .onChange(of: instrument) {
            recomputeMetadataCardTintIfNeeded()
        }
        .onChange(of: activity) {
            recomputeMetadataCardTintIfNeeded()
        }
        .onChange(of: selectedCustomName) {
            recomputeMetadataCardTintIfNeeded()
        }
            .onChange(of: isActivityDetailFocused) { oldValue, newValue in
                if oldValue == false && newValue == true {
                    let trimmed = activityDetail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !userEditedActivityDetail,
                       !userHasEditedActivityDetail,
                       !trimmed.isEmpty,
                       activityDetail == lastAutoActivityDetail {
                        activityDetail = ""
                    }
                }

                if oldValue == true && newValue == false {
                    let trimmed = activityDetail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        let autoDesc = editorDefaultDescription(
                            timestamp: timestamp,
                            activity: activity,
                            customName: selectedCustomName
                        )
                        activityDetail = autoDesc
                        lastAutoActivityDetail = autoDesc
                        userEditedActivityDetail = false
                        userHasEditedActivityDetail = false
                    }
                }
            }
        .onChange(of: activityDetail) { old, new in
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            userEditedActivityDetail = (!trimmed.isEmpty && trimmed != lastAutoActivityDetail)
        }
        .onAppear {
            instrumentsGateArmed = false
            instrumentsReady = false
            // Give instruments a breath to bind if they’re coming from Core Data
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                instrumentsGateArmed = true
                // If they’re already non-empty by now, mark ready
                if !instruments.isEmpty { instrumentsReady = true }
            }
        }
        .onChange(of: instruments.count) { _, newCount in
            // As soon as instruments arrive, it's safe to render their section
            if newCount > 0 { instrumentsReady = true }
        }
        .appBackground()
    }
}

    // Threads v1 — compiler assistance (no UI/logic change)
    @ViewBuilder
    private var contentStack: some View {
VStack(alignment: .leading, spacing: Theme.Spacing.section) {
    Text(isThoughtMode ? (isEdit ? "Edit Thought" : "Add Thought") : (isEdit ? "Edit Session" : "Add Session")).sectionHeader()


                if !isThoughtMode {
                    // No instruments / Instrument picker
                    if hasNoInstruments {
                        // Show the empty-state card only after the first 120ms tick
                        if instrumentsGateArmed && !instrumentsReady {
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                Text("No instruments found").sectionHeader()
                                Text("Add an instrument in your Profile to save this session.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .cardSurface()
                        } else {
                            // Render nothing until either the arm time passes or instruments arrive
                            EmptyView()
                        }
                    } else if hasMultipleInstruments {
                        // Instrument (always visible if any instruments exist)
                        Button {
                            showInstrumentPicker = true
                        } label: {
                            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                                    .frame(width: 22, height: 22)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Instrument")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                    Text(instrument?.name ?? "Select instrument…")
                                        .font(Theme.Text.body)
                                }

                                Spacer(minLength: Theme.Spacing.m)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Instrument")
                        .accessibilityIdentifier("picker.instrument")
                    }

                    // Activity
                    Button {
                        showActivityPicker = true
                    } label: {
                        let display = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? activity.label : selectedCustomName
                        HStack(alignment: .center, spacing: Theme.Spacing.m) {
                            Image(systemName: "circle.grid.2x2")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                                .frame(width: 22, height: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Activity")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                Text(display)
                                    .font(Theme.Text.body)
                            }

                            Spacer(minLength: Theme.Spacing.m)

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Activity")
                    .accessibilityIdentifier("picker.activity")

                    // Activity description (short detail)
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Description")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.Colors.secondaryText)
                            TextField(
                                "Activity description",
                                text: $activityDetail
                            )
                            .focused($isActivityDetailFocused)
                            .lineLimit(1)
                            .submitLabel(.done)
                            .onSubmit {
                                isActivityDetailFocused = false
                            }
                                .font(Theme.Text.body)
                                .onChange(of: activityDetail) { _, new in handleActivityDetailChange_v2(new) }
                        }

                        Spacer(minLength: Theme.Spacing.m)

                        if !isActivityDetailFocused {
                            Image(systemName: "pencil")
                                .font(.subheadline)
                                .imageScale(.medium)
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .opacity(0.8)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }

                // Thread (owner-only metadata)
                Button {
                    showThreadPicker = true
                } label: {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thread")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.Colors.secondaryText)
                            if let thread = threadLabel, !thread.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(thread)
                                    .font(Theme.Text.body)
                            } else {
                                Text("None")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }

                        Spacer(minLength: Theme.Spacing.m)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thread")
                .accessibilityIdentifier("picker.thread")

                // Start Time
                Button {
                    tempDate = timestamp
                    showStartPicker = true
                } label: {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        Image(systemName: "clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isThoughtMode ? "Time" : "Start Time")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.Colors.secondaryText)
                            Text(formattedDate(timestamp))
                                .font(Theme.Text.body)
                        }

                        Spacer(minLength: Theme.Spacing.m)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                // Duration
                if !isThoughtMode {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            let hm = secondsToHM(durationSeconds)
                            tempHours = hm.0; tempMinutes = hm.1
                            showDurationPicker = true
                        } label: {
                            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                                Image(systemName: "timer")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                                    .frame(width: 22, height: 22)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Duration")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Theme.Colors.secondaryText)
                                    Text(formattedDuration(durationSeconds))
                                        .font(Theme.Text.body)
                                }

                                Spacer(minLength: Theme.Spacing.m)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if durationSeconds == 0 {
                            Text("Duration must be greater than 0")
                                .font(.footnote)
                                .foregroundColor(.red.opacity(0.65))
                                .padding(.leading, 22 + Theme.Spacing.m)
                        }
                    }
                }

                // ---------- Visibility ----------
                HStack(alignment: .center, spacing: Theme.Spacing.m) {
                    Image(systemName: "person.2")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Visibility")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Share with followers")
                            .font(Theme.Text.body)
                    }

                    Spacer(minLength: Theme.Spacing.m)

                    Toggle("", isOn: $isPublic)
                        .labelsHidden()
                        .tint(Theme.Colors.accent)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 10)

                // Notes
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Notes").sectionHeader()
                        Spacer(minLength: 0)
                        Button(action: {
                            areNotesPrivate_edit.toggle()
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }) {
                            Image(systemName: areNotesPrivate_edit ? "eye.slash" : "eye")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(areNotesPrivate_edit ? "Make notes visible to others" : "Make notes private")
                    }
                    if areNotesPrivate_edit {
                        Text("Only you will see these notes.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }

                    Spacer()
                        .frame(height: Theme.Spacing.s)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .focused($isNotesFocused)
                            .font(Theme.Text.body)
                            .frame(minHeight: 120)
                            .accessibilityLabel("Notes")
                    }
                }
                .cardSurface()
                .padding(.bottom, Theme.Spacing.s)
                // NEW — State card (read/write)
                if !isThoughtMode {
                    stateStripCard_edit
                }

                
                // Attachments grid
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Attachments").sectionHeader()
                    if !stagedAttachments.isEmpty {
                        let visuals = stagedAttachments.filter { $0.kind != .audio }
                        let audioOnly = stagedAttachments.filter { $0.kind == .audio }

                        if !visuals.isEmpty {
                            let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                            LazyVGrid(columns: columns, spacing: 12) {
                                                            ForEach(visuals) { att in
                                                                VStack(alignment: .leading, spacing: 4) {
                                                                    ZStack(alignment: .topTrailing) {
                                                                        // Tile content
                                                                        AttachmentTileContent(att: att)
                                                                            .frame(width: 128, height: 128)
                                                                            .background(Color.secondary.opacity(0.08))
                                                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                                            .overlay(
                                                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                                    .stroke(.secondary.opacity(0.15), lineWidth: 1)
                                                                            )
    
                                                                        // Right-side vertical controls: Star, Privacy, Delete
                                                                        VStack(spacing: 6) {
                                                                            if att.kind == .image || att.kind == .audio || att.kind == .video {
                                                                                Text(selectedThumbnailID == att.id ? "★" : "☆")
                                                                                    .font(.system(size: 16))
                                                                                    .padding(8)
                                                                                    .background(.ultraThinMaterial, in: Circle())
                                                                                    .onTapGesture {
                                                                                        let fileURL: URL? = surrogateURL(for: att)
                                                                                        let privNow: Bool = isPrivate(id: att.id, url: fileURL)
                                                                                        if selectedThumbnailID == att.id {
                                                                                            // Toggle OFF
                                                                                            selectedThumbnailID = nil
                                                                                        } else {
                                                                                            if privNow {
                                                                                                // ⭐ implies 👁 — starring auto-includes.
                                                                                                setPrivate(id: att.id, url: fileURL, false)
                                                                                            }
                                                                                            // Toggle ON
                                                                                            selectedThumbnailID = att.id
                                                                                        }
                                                                                    }
                                                                                    .accessibilityLabel(selectedThumbnailID == att.id ? "Thumbnail (selected)" : "Set as Thumbnail")
                                                                            }
    
                                                                            let fileURL: URL? = surrogateURL(for: att)
                                                                            let priv: Bool = isPrivate(id: att.id, url: fileURL)
                                                                            Button {
                                                                                let newPriv = !priv
                                                                                if newPriv, selectedThumbnailID == att.id {
                                                                                    // Making thumbnail private clears ⭐.
                                                                                    selectedThumbnailID = nil
                                                                                }
                                                                                setPrivate(id: att.id, url: fileURL, newPriv)
                                                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                                            } label: {
                                                                                // Quiet Mode: show badge only when included (not private)
                                                                                ZStack {
                                                                                    Image(systemName: priv ? "eye.slash" : "eye")
                                                                                        .font(.system(size: 16, weight: .semibold))
                                                                                        .padding(8)
                                                                                        .background(.ultraThinMaterial, in: Circle())
                                                                                }
                                                                                .opacity((selectedThumbnailID == att.id) ? 0 : 1)
                                                                            }
                                                                            .buttonStyle(.plain)
                                                                            .accessibilityLabel(priv ? "Mark attachment public" : "Mark attachment private")
    
                                                                            Button {
                                                                                // Preserve existing persistent delete behavior for items sourced from Core Data
                                                                                if existingAttachmentIDs.contains(att.id), let s = session {
                                                                                    let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
                                                                                    req.predicate = NSPredicate(format: "session == %@ AND id == %@", s.objectID, att.id as CVarArg)
                                                                                    req.fetchLimit = 1
                                                                                    if let match = try? viewContext.fetch(req).first {
                                                                                        if let path = match.value(forKey: "fileURL") as? String, !path.isEmpty {
                                                                                            AttachmentStore.deleteAttachmentFile(atPath: path)
                                                                                        }
                                                                                        viewContext.delete(match)
                                                                                        do { try viewContext.save() } catch { print("Delete save error: \(error)") }
                                                                                    }
                                                                                }
                                                                                removeStagedAttachment(att)
                                                                            } label: {
                                                                                Image(systemName: "trash")
                                                                                    .font(.system(size: 16, weight: .semibold))
                                                                                    .padding(8)
                                                                                    .background(.ultraThinMaterial, in: Circle())
                                                                            }
                                                                            .buttonStyle(.plain)
                                                                            .accessibilityLabel("Delete attachment")
                                                                        }
                                                                        .padding(6)
                                                                    }
                                                                    .contextMenu {
                                                                        if att.kind == .image || att.kind == .audio || att.kind == .video {
                                                                            Button("Set as Thumbnail") {
                                                                                let fileURL: URL? = surrogateURL(for: att)
                                                                                let privNow: Bool = isPrivate(id: att.id, url: fileURL)
                                                                                if selectedThumbnailID == att.id {
                                                                                    // Toggle OFF
                                                                                    selectedThumbnailID = nil
                                                                                } else {
                                                                                    if privNow {
                                                                                        // ⭐ implies 👁 — starring auto-includes.
                                                                                        setPrivate(id: att.id, url: fileURL, false)
                                                                                    }
                                                                                    // Toggle ON
                                                                                    selectedThumbnailID = att.id
                                                                                }
                                                                            }
                                                                        }
                                                                        Button(role: .destructive) {
                                                                            if existingAttachmentIDs.contains(att.id), let s = session {
                                                                                let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
                                                                                req.predicate = NSPredicate(format: "session == %@ AND id == %@", s.objectID, att.id as CVarArg)
                                                                                req.fetchLimit = 1
                                                                                if let match = try? viewContext.fetch(req).first {
                                                                                    if let path = match.value(forKey: "fileURL") as? String, !path.isEmpty {
                                                                                        AttachmentStore.deleteAttachmentFile(atPath: path)
                                                                                    }
                                                                                    viewContext.delete(match)
                                                                                    do { try viewContext.save() } catch { print("Delete save error: \(error)") }
                                                                                }
                                                                            }
                                                                            removeStagedAttachment(att)
                                                                        } label: { Text("Remove") }
                                                                    }
                                                                    .contentShape(Rectangle())
                                                                    .onTapGesture {
                                                                        // Visual gallery: images + videos + PDFs (audio/generic files excluded)
                                                                        ensureSurrogateFilesExistForViewer_edit()
    
                                                                        let imageURLs: [URL] = visuals.compactMap { item in
                                                                            guard item.kind == .image else { return nil }
                                                                            return viewerResolvedURL_edit(for: item)
                                                                        }
    
                                                                        let videoURLs: [URL] = visuals.compactMap { item in
                                                                            guard item.kind == .video else { return nil }
                                                                            return viewerResolvedURL_edit(for: item)
                                                                        }
    
                                                                        let pdfURLs: [URL] = visuals.compactMap { item in
                                                                            guard item.kind == .pdf else { return nil }
                                                                            return viewerResolvedURL_edit(for: item)
                                                                        }
    
                                                                        let orderedVisualIDs: [UUID] = {
                                                                            let imageIDs: [UUID] = visuals.compactMap { item in
                                                                                guard item.kind == .image else { return nil }
                                                                                return item.id
                                                                            }
                                                                            let videoIDs: [UUID] = visuals.compactMap { item in
                                                                                guard item.kind == .video else { return nil }
                                                                                return item.id
                                                                            }
                                                                            let pdfIDs: [UUID] = visuals.compactMap { item in
                                                                                guard item.kind == .pdf else { return nil }
                                                                                return item.id
                                                                            }
                                                                            return imageIDs + videoIDs + pdfIDs
                                                                        }()
    
                                                                        let startIndex: Int = {
                                                                            switch att.kind {
                                                                            case .image:
                                                                                let idx = visuals.filter { $0.kind == .image }.firstIndex(where: { $0.id == att.id }) ?? 0
                                                                                return idx
                                                                            case .video:
                                                                                let idx = visuals.filter { $0.kind == .video }.firstIndex(where: { $0.id == att.id }) ?? 0
                                                                                return imageURLs.count + idx
                                                                            case .pdf:
                                                                                let idx = visuals.filter { $0.kind == .pdf }.firstIndex(where: { $0.id == att.id }) ?? 0
                                                                                return imageURLs.count + videoURLs.count + idx
                                                                            default:
                                                                                return 0
                                                                            }
                                                                        }()
    
                                                                        viewerRequest = AESVAttachmentViewerRequest(
                                                                            mode: .visual,
                                                                            startIndex: startIndex,
                                                                            imageURLs: imageURLs,
                                                                            videoURLs: videoURLs,
                                                                            audioURLs: [],
                                                                            pdfURLs: pdfURLs,
                                                                            viewerAttachmentIDs: orderedVisualIDs
                                                                        )
                                                                    }
                                                                    if att.kind == .pdf,
                                                                       let displayName = ((UserDefaults.standard.dictionary(forKey: "stagedAttachmentDisplayNames_temp") as? [String: String])?[att.id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines)),
                                                                       !displayName.isEmpty {
                                                                        Text(displayName)
                                                                            .font(.caption2)
                                                                            .foregroundStyle(Theme.Colors.secondaryText)
                                                                            .lineLimit(1)
                                                                            .truncationMode(.tail)
                                                                            .frame(width: 128, alignment: .leading)
                                                                    }
                                                                }
                                                                .frame(width: 128, alignment: .leading)
                                                            }
                            }
                            .padding(.vertical, 4)
                        }

                        if !audioOnly.isEmpty {
                            // Titles for staged audio (keyed by staged id UUID string)
                            let _ = attachmentTitlesRefreshTick
                            let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                            let persistedTitles = loadPersistedAudioTitles()

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(audioOnly) { att in
                                    // Prefer persisted override by attachment UUID; fallback to staged map; then default label
                                    let persisted = (persistedTitles[att.id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let staged = (namesDict[att.id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let displayTitle = !persisted.isEmpty ? persisted : (!staged.isEmpty ? staged : "Audio clip")

                                    let url = surrogateURL(for: att)
                                    let durationText: String? = audioDurationText_edit(for: att)

                                    HStack(alignment: .center, spacing: 12) {
                                        // Main tap target: open audio-only viewer starting on this clip
                                        Button {
                                            ensureSurrogateFilesExistForViewer_edit()

                                            let audioItems: [(UUID, URL)] = audioOnly.compactMap { item in
                                                guard let url = (viewerResolvedURL_edit(for: item) ?? guaranteedSurrogateURL_edit(for: item)) else { return nil }
                                                return (item.id, url)
                                            }
                                            let audioURLs: [URL] = audioItems.map { $0.1 }
                                            let orderedAudioIDs: [UUID] = audioItems.map { $0.0 }
                                            let startIndex = audioItems.firstIndex(where: { $0.0 == att.id }) ?? 0

                                            viewerRequest = AESVAttachmentViewerRequest(
                                                mode: .audio,
                                                startIndex: startIndex,
                                                imageURLs: [],
                                                videoURLs: [],
                                                audioURLs: audioURLs,
                                                pdfURLs: [],
                                                viewerAttachmentIDs: orderedAudioIDs
                                            )
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "waveform")
                                                    .font(.system(size: 16, weight: .semibold))

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(displayTitle)
                                                        .font(.footnote)
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)

                                                    if let durationText {
                                                        Text(durationText)
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .contentShape(Rectangle())
                                        .accessibilityLabel("Open audio clip \(displayTitle)")

                                        Spacer(minLength: 8)

                                        // PRDV-parity control stack (Option A: present, no-op)
                                        VStack(spacing: 6) {
                                            Button {
                                                if selectedThumbnailID == att.id {
                                                    selectedThumbnailID = nil
                                                } else {
                                                    selectedThumbnailID = att.id
                                                }
                                            } label: {
                                                Image(systemName: selectedThumbnailID == att.id ? "star.fill" : "star")
                                                    .font(.system(size: 16, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(selectedThumbnailID == att.id ? "Unset thumbnail" : "Set as thumbnail")

                                            let privURL = url
                                            let isPriv = isPrivate(id: att.id, url: privURL)
                                            Button {
                                                let current = isPrivate(id: att.id, url: privURL)
                                                setPrivate(id: att.id, url: privURL, !current)
                                            } label: {
                                                // Quiet Mode: only show when included
                                                Image(systemName: isPriv ? "eye.slash" : "eye")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .opacity(selectedThumbnailID == att.id ? 0 : 1)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Toggle privacy")

                                            Button(role: .destructive) {
                                                removeStagedAttachment(att)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 16, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Delete attachment")
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                }
                .cardSurface(padding: Theme.Spacing.m)
                .accessibilityLabel("Attachments")

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: 32) {
                        Button(action: { showPhotoPicker = true }) {
                            ZStack {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .fill(Color.secondary.opacity(0.18))
                                            .frame(width: 64, height: 64)
                                    )
                            }
                        }
                        .accessibilityLabel("Add photo or video from library")
                        .contentShape(Circle())
                        .buttonStyle(.plain)
                        .tint(.accentColor)

                        Button(action: { showFileImporter = true }) {
                            ZStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .fill(Color.secondary.opacity(0.18))
                                            .frame(width: 64, height: 64)
                                    )
                            }
                        }
                        .accessibilityLabel("Add file (PDF, score, etc.)")
                        .contentShape(Circle())
                        .buttonStyle(.plain)
                        .tint(.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.s)
                }
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.s)

                bottomSaveButton
            }
    }

    private var bottomSaveButton: some View {
        HStack {
            Spacer(minLength: 0)

            Button(action: { save() }) {
                Text(isThoughtMode ? "Save Thought" : "Save Session")
                    .font(Theme.Text.body)
                    .foregroundColor(.primary)
                    .opacity(1.0)
            }
            .frame(maxWidth: 260, minHeight: 44)
            .background(Theme.Colors.primaryAction.opacity(0.17))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .buttonStyle(.plain)
            .disabled(isThoughtMode ? !canSaveThought : (durationSeconds == 0 || instrument == nil))
            .accessibilityLabel(isThoughtMode ? "Save thought" : "Save session")
            .accessibilityIdentifier("button.saveSession")

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: - Focus / State

    // NEW — State card (read/write)
    @ViewBuilder
    private var stateStripCard_edit: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Focus").sectionHeader()

            VStack(spacing: Theme.Spacing.s) {
                FocusCircleView(
                    normalizedFocus: liveFocusProgress_edit ?? progressForVisualFocusValue_edit(visualFocusValue_edit(forStoredFocusValue: selectedDotIndex_edit)),
                    size: 74
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)

                GeometryReader { geo in
                    let width = geo.size.width
                    let visualValue = visualFocusValue_edit(forStoredFocusValue: selectedDotIndex_edit)
                    let progress = liveFocusProgress_edit ?? progressForVisualFocusValue_edit(visualValue)
                    let knobSize: CGFloat = 18
                    let knobX = progress.map { min(max($0 * width, knobSize * 0.5), width - knobSize * 0.5) }

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(FocusCircleView.baseFocusColor.opacity(0.08))
                            .frame(height: 5)
                            .frame(maxWidth: .infinity)

                        if let progress {
                            Capsule()
                                .fill(FocusCircleView.baseFocusColor.opacity(0.105))
                                .frame(width: max(0, width * progress), height: 5)
                        }

                        if let knobX {
                            Circle()
                                .fill(FocusCircleView.baseFocusColor.opacity(0.34))
                                .overlay(
                                    Circle()
                                        .stroke(FocusCircleView.baseFocusColor.opacity(0.15), lineWidth: 1)
                                )
                                .frame(width: knobSize, height: knobSize)
                                .position(x: knobX, y: 18)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateFocusFromTrack_edit(locationX: value.location.x, width: width)
                            }
                            .onEnded { _ in
                                settleFocusTrackAfterDrag_edit()
                                lastHapticDot_edit = nil
                            }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Focus")
                    .accessibilityValue(visualValue.map { "\($0) of 10" } ?? "Unset")
                    .accessibilityAdjustableAction { direction in
                        let currentVisual = visualFocusValue_edit(forStoredFocusValue: selectedDotIndex_edit) ?? 5
                        let nextVisual: Int
                        switch direction {
                        case .increment:
                            nextVisual = min(focusSnapCount_edit, currentVisual + 1)
                        case .decrement:
                            nextVisual = max(1, currentVisual - 1)
                        @unknown default:
                            return
                        }
                        selectedDotIndex_edit = storedFocusValue_edit(forVisualFocusValue: nextVisual)
                        liveFocusProgress_edit = progressForVisualFocusValue_edit(nextVisual)
                    }
                }
                .frame(height: 36)

                HStack {
                    Text("Unfocused")
                    Spacer()
                    Text("Focused")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(0.72)
            }
        }
        .cardSurface(padding: Theme.Spacing.m)
    }

    // MARK: - Data hydration

    private func hydrate() {
        instruments = fetchInstruments()

        if let s = session {
            // Edit mode
            instrument = s.instrument
            timestamp = s.timestamp ?? Date()
            durationSeconds = Int(s.durationSeconds)
            isPublic = s.isPublic
            notes = s.notes ?? ""
            if s.entity.attributesByName.keys.contains("areNotesPrivate") {
                areNotesPrivate_edit = (s.value(forKey: "areNotesPrivate") as? Bool) == true
            } else {
                areNotesPrivate_edit = false
            }
            // Preselect focus from notes before stripping token so the dots reflect persisted state
            preselectFocusFromNotesIfNeeded_edit()
            preselectFocusFromSessionEffortIfNeeded_edit(s)
            // Ensure the token is not visible in the Notes UI on edit hydrate
            stripFocusTokensFromNotes_edit()

            let raw = Int16(s.value(forKey: "activityType") as? Int ?? 0)
            activity = SessionActivityType(rawValue: raw) ?? .practice
            activityDetail = (s.value(forKey: "activityDetail") as? String) ?? ""

            // Reconcile auto vs custom on edit hydrate: keep auto-updates alive if detail equals the computed default.
            do {
                let expectedAuto = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: ((s.value(forKey: "userActivityLabel") as? String) ?? selectedCustomName))
                if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines) == expectedAuto.trimmingCharacters(in: .whitespacesAndNewlines) {
                    lastAutoActivityDetail = activityDetail
                    userHasEditedActivityDetail = false
                    userEditedActivityDetail = false
                } else {
                    userHasEditedActivityDetail = true
                    userEditedActivityDetail = true
                }
            }

            selectedCustomName = (s.value(forKey: "userActivityLabel") as? String) ?? "" // remains blank unless user selects a custom in the picker

            // Threads v1 (owner-only metadata)
            if s.entity.attributesByName.keys.contains("threadLabel") {
                let raw = (s.value(forKey: "threadLabel") as? String) ?? ""
                threadLabel = sanitizeThreadLabel_v1(raw)
            } else {
                threadLabel = nil
            }
        } else {
            // New mode defaults
            timestamp = Date()
            durationSeconds = 0
            isPublic = !isThoughtMode

            // Threads v1 (owner-only metadata)
            threadLabel = sanitizeThreadLabel_v1(threadLabelPrefill)

            if instrument == nil {
                if let primaryName = fetchPrimaryInstrumentName(),
                   let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                    instrument = match
                } else if instruments.count == 1 {
                    instrument = instruments.first
                }
            }
        }

        // Prefetch customs and align choice
        loadUserActivities()
        applyPrimaryActivityRefIfNeeded()
        syncActivityChoiceFromState()

        // Seed default description if blank (new session) or if coming from a state with empty detail
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let auto = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
            lastAutoActivityDetail = auto
            activityDetail = auto
            userEditedActivityDetail = false
        }
        // If we loaded a non-empty description that differs from the last auto, treat it as user-customized
        else if activityDetail != lastAutoActivityDetail {
            userHasEditedActivityDetail = true
            userEditedActivityDetail = true
        }

        // Preload existing attachments for edit mode (only once to avoid duplicates)
        if session != nil, stagedAttachments.isEmpty {
            preloadExistingAttachments()
        }
    }

    private func applyPrimaryActivityRefIfNeeded() {
        // Only seed from Primary when creating a new session and no explicit activity set
        guard session == nil else { return }
        let raw = primaryActivityRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("core:") {
            if let v = Int(raw.split(separator: ":").last ?? "0"),
               let t = SessionActivityType(rawValue: Int16(v)) {
                activity = t
                selectedCustomName = ""
                return
            }
        } else if raw.hasPrefix("custom:") {
            let name = String(raw.dropFirst("custom:".count))
            if userActivities.contains(where: { ($0.displayName ?? "") == name }) {
                activity = .practice
                selectedCustomName = name
                return
            }
        }
        // fallback → practice
        activity = .practice
        selectedCustomName = ""
    }

    
    // MARK: - Threads v1 helpers

    private func sanitizeThreadLabel_v1(_ raw: String?) -> String? {
        guard let raw else { return nil }
        // Trim and collapse internal whitespace.
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        if s.count > 32 {
            s = String(s.prefix(32))
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return nil }
        }
        return s
    }

// MARK: - Actions

    private var canSaveThought: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !stagedAttachments.isEmpty
    }

    private func save() {
        if isThoughtMode && !canSaveThought { return }
        let shouldGeneratePracticeInsight = (session == nil && isThoughtMode == false)
        let s = session ?? Session(context: viewContext)
        if (s.value(forKey: "id") as? UUID) == nil {
            s.setValue(UUID(), forKey: "id")
        }
        let trimmedDetail = activityDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveDurationSeconds = isThoughtMode ? 0 : durationSeconds

        if isThoughtMode {
            s.instrument = nil
            s.title = ""
        } else {
            s.instrument = instrument
            // Title = activityDetail (trimmed) or fallback
            s.title = trimmedDetail.isEmpty ? defaultTitle(for: instrument, activity: activity) : trimmedDetail
        }

        s.timestamp = timestamp
        s.durationSeconds = Int64(effectiveDurationSeconds)
        s.isPublic = isPublic
        // Persist focus structurally (do NOT encode into notes)
        if s.entity.attributesByName.keys.contains("effort") {
            if isThoughtMode {
                s.setValue(Int16(5), forKey: "effort")
            } else if let idx = selectedDotIndex_edit {
                s.setValue(Int16(idx), forKey: "effort")
            } else {
                // Treat nil as "unset" (default effort = 5)
                s.setValue(Int16(5), forKey: "effort")
            }
        }

        if !isThoughtMode, selectedDotIndex_edit != nil {
            applyFocusToNotesBeforeSave_edit()
        } else {
            // No focus selected — ensure tokens are not persisted
            stripFocusTokensFromNotes_edit()
        }
        if s.entity.attributesByName.keys.contains("areNotesPrivate") {
            s.setValue(areNotesPrivate_edit, forKey: "areNotesPrivate")
        }
        s.notes = notes

        // Persist activity type + detail
        let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isThoughtMode {
            s.setValue(activity.rawValue, forKey: "activityType")
            s.setValue("", forKey: "activityDetail")
            s.setValue(nil, forKey: "userActivityLabel")
        } else {
            s.setValue(activity.rawValue, forKey: "activityType")
            s.setValue(trimmedDetail, forKey: "activityDetail")

            // If a custom name is selected, stamp userActivityLabel; otherwise clear any previous custom label
            if !trimmedCustom.isEmpty {
                s.setValue(trimmedCustom, forKey: "userActivityLabel")
            } else {
                s.setValue(nil, forKey: "userActivityLabel")
            }
        }

        // Threads v1 (owner-only metadata)
        if s.entity.attributesByName.keys.contains("threadLabel") {
            s.setValue(sanitizeThreadLabel_v1(threadLabel), forKey: "threadLabel")
        }

        // Owner stamp
        #if DEBUG
        let __dbgID = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride")
        let __effectiveUID = __dbgID ?? PersistenceController.shared.currentUserID
#else
        let __effectiveUID = PersistenceController.shared.currentUserID
#endif
        if let uid = __effectiveUID, !uid.isEmpty {
            s.setValue(uid, forKey: "ownerUserID")
        }
        
        // Apply pending replacements for existing attachments (defer persistence to save-time).
        // This avoids SessionDetailView dismissal caused by intermediate saves on replacement.
        do {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", s.objectID)
            let attachments = try viewContext.fetch(req)
            for attachment in attachments {
                if let id = attachment.value(forKey: "id") as? UUID,
                   let newURL = existingAttachmentURLMap[id] {
                    attachment.fileURL = newURL.path
                }
            }
        } catch {
            print("Failed to apply replacement URLs before save: \(error)")
        }

        
        // Apply pending deletions for existing attachments (delete from Core Data + remove local file).
        if !deletedExistingAttachmentIDs.isEmpty {
            do {
                let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
                req.predicate = NSPredicate(format: "session == %@ AND id IN %@", s, Array(deletedExistingAttachmentIDs) as NSArray)
                let matches = try viewContext.fetch(req)
                for a in matches {
                    if let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                        AttachmentStore.removeIfExists(path: path)
                    }
                    viewContext.delete(a)
                }
            } catch {
                print("Failed to delete existing attachments before save: \(error)")
            }
        }

// Commit staged attachments (skip existing to avoid duplicates; update thumbnail flags)

        // Snapshot AESV tmp surrogate/alias targets before commit clears stagedAttachments.
        // Cleanup runs only after a successful save (hardening; no user-visible behavior changes).
        let __tmpCleanupSnapshot: [(UUID, AttachmentKind)] = stagedAttachments.map { ($0.id, $0.kind) }

        commitStagedAttachments(to: s, ctx: viewContext)

        do {
            try viewContext.save()

            // AESV tmp hygiene: best-effort delete surrogate/alias files created in tmp during this edit session.
            for (id, kind) in __tmpCleanupSnapshot {
                cleanupTempArtifacts_AESV_bestEffort(for: id, kind: kind)
            }


            deletedExistingAttachmentIDs.removeAll()

            // ===== v7.12A • Publish hook after successful save =====
            guard let sid = s.id else {
                print("Publish skipped: missing Session.id")
                return
            }

            let focusValue: Int? = isThoughtMode ? nil : selectedDotIndex_edit

            let activityTypeString = trimmedCustom.isEmpty ? activity.label : trimmedCustom
            let instLabel =
                (s.userInstrumentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? s.instrument?.name

            let payload = SessionSyncQueue.PostPublishPayload(
                id: sid,
                sessionID: sid,
                sessionTimestamp: timestamp,
                title: isThoughtMode ? nil : s.title,
                durationSeconds: effectiveDurationSeconds,
                activityType: isThoughtMode ? nil : activityTypeString,
                activityDetail: isThoughtMode ? nil : trimmedDetail,
                instrumentLabel: isThoughtMode ? nil : instLabel,
                mood: nil,
                effort: focusValue,
                isPublic: isPublic,
                notes: notes,
                areNotesPrivate: areNotesPrivate_edit
            )

            // Publish and visibility are separate concepts:
            // - shouldPublish controls existence (publish vs unpublish/delete)
            // - payload.isPublic controls follower visibility.
            PublishService.shared.publish(
                payload: payload,
                objectID: s.objectID,
                shouldPublish: true
            )

            viewContext.processPendingChanges()
            if shouldGeneratePracticeInsight {
                PracticeInsightSessionStore.shared.generateInsight(forNewlySavedSession: s, in: viewContext)
            }
            if let onSuccessfulSave {
                onSuccessfulSave()
            } else {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { dismiss() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dismiss() }
            }
        } catch {
            // Delete any files written during this commit attempt by scanning attachments without permanent IDs
            if let set = s.attachments as? Set<Attachment> {
                for a in set {
                    if a.objectID.isTemporaryID, let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                        AttachmentStore.removeIfExists(path: path)
                    }
                }
            }
            viewContext.rollback()
            print("Save error (Add/Edit): \(error)")
        }
    }

    // MARK: - Pinned activity list + helpers

    func normalizedPrimary() -> String? {
        let raw = primaryActivityRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("core:") {
            if let v = Int(raw.split(separator: ":").last ?? "0"),
               SessionActivityType(rawValue: Int16(v)) != nil {
                return "core:\(v)"
            }
            return "core:0"
        } else if raw.hasPrefix("custom:") {
            let name = String(raw.dropFirst("custom:".count))
            if userActivities.contains(where: { ($0.displayName ?? "") == name }) {
                return "custom:\(name)"
            }
            return "core:0"
        } else {
            return "core:0"
        }
    }

    func applyActivityChoice() {
        if activityChoice.hasPrefix("core:") {
            if let raw = Int(activityChoice.split(separator: ":").last ?? "0") {
                activity = SessionActivityType(rawValue: Int16(raw)) ?? .practice
            } else {
                activity = .practice
            }
            selectedCustomName = ""
        } else if activityChoice.hasPrefix("custom:") {
            let name = String(activityChoice.dropFirst("custom:".count))
            activity = .practice
            selectedCustomName = name
        }
    }

     func syncActivityChoiceFromState() {
        if selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityChoice = "core:\(activity.rawValue)"
        } else {
            activityChoice = "custom:\(selectedCustomName)"
        }
    }

    private func loadUserActivities() {
        do {
            userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext)
        } catch {
            userActivities = []
        }
    }

    // MARK: - Default description logic

    private func timeOfDayString(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:   return "Morning"
        case 12..<17:  return "Afternoon"
        case 17..<22:  return "Evening"
        default:       return "Night"
        }
    }

    private func editorDefaultDescription(timestamp: Date, activityDisplayName: String) -> String {
        "\(timeOfDayString(for: timestamp)) \(activityDisplayName)"
    }

    private func currentActivityDisplayName() -> String {
        let custom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return activity.label
    }

    func maybeUpdateActivityDetailFromDefaults_v2() {
        guard !userHasEditedActivityDetail else { return }
        let auto = editorDefaultDescription(timestamp: timestamp, activityDisplayName: currentActivityDisplayName())
        activityDetail = auto
        lastAutoActivityDetail = auto
    }

    private func handleActivityDetailChange_v2(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userHasEditedActivityDetail = false
            return
        }
        if new != lastAutoActivityDetail {
            userHasEditedActivityDetail = true
        }
    }

    private func editorDefaultDescription(timestamp: Date, activity: SessionActivityType, customName: String) -> String {
        let label = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? activity.label : customName
        let hour = Calendar.current.component(.hour, from: timestamp)
        let part: String
        switch hour {
        case 0...4: part = "Late Night"
        case 5...11: part = "Morning"
        case 12...17: part = "Afternoon"
        default: part = "Evening"
        }
        return "\(part) \(label)"
    }

    /// Update activityDetail only if it's empty OR still equal to the last auto-generated default
    func maybeUpdateActivityDetailFromDefaults() {
        let newDefault = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activityDetail == lastAutoActivityDetail {
            lastAutoActivityDetail = newDefault
            activityDetail = newDefault
            userEditedActivityDetail = false
        }
    }


    // MARK: - Fetches & misc helpers

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

    private func defaultTitle(for inst: Instrument? = nil, activity: SessionActivityType) -> String {
        if let name = (inst ?? instrument)?.name, !name.isEmpty { return "\(name) : \(activity.label)" }
        return activity.label
    }

    private func secondsToHM(_ seconds: Int) -> (Int, Int) {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return (h, m)
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

//  [ROLLBACK ANCHOR] v7.8 DesignLite — post
}
