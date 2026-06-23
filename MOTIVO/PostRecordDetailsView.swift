// CHANGE-ID: 20260623_151500_ManualScoreAttach
// SCOPE: PRDV manual first-class score references via ScoresLibraryView attach mode; merge/dedupe with timer-used scores; no generic staged score attachments.
// SEARCH-TOKEN: 20260623_MANUAL_SCORE_ATTACH_PRDV

// CHANGE-ID: 20260622_205500_SCORES_PHASE8_MEANINGFUL_PAGES
// SCOPE: Scores V1 Phase 8 — show meaningful score page attachment suggestions in PRDV using existing page-selection state. No persistence, schema, backend, score storage, or attachment pipeline changes.
// SEARCH-TOKEN: 20260622_205500_SCORES_PHASE8

// CHANGE-ID: 20260622_175900_SCORES_PHASE7_V2
// SCOPE: Scores V1 Phase 7 v2 — persist used score PDFs as normal session Attachment rows from PRDV save path; reference Documents/Scores originals; persist selected-page metadata; no UI/schema/backend changes.
// SEARCH-TOKEN: 20260622_175900_SCORES_PHASE7_V2

// CHANGE-ID: 20260614_181500_ScoresPhase6_PRDVScoreSelection
// SCOPE: Scores V1 Phase 6 — PRDV-only selectable Scores Used rows using existing PDFPageSelectionSheet; store score page selections in PRDV state only. No attachment creation, persistence, save-path, SDV, AESV, backend, or file-copy changes.
// SEARCH-TOKEN: 20260614_181500_SCORES_PHASE6_PRDV_SCORE_SELECTION

// CHANGE-ID: 20260614_174200_ScoresPhase4_UsageTracking
// SCOPE: Scores Phase 4 — accept silently tracked live-session score IDs from PTV for later PRDV Scores Used UI. No UI, attachment, save, or persistence changes.
// SEARCH-TOKEN: 20260614_174200_SCORES_PHASE4_USAGE_TRACKING

// CHANGE-ID: 20260610_1430_PDFPhase2A
// SCOPE: PDF Scores Phase 2A — metadata-only PDF page selection; staged-to-persisted UUID migration; selected-page viewer routing and display labels.
// SEARCH-TOKEN: 20260610_1430-PDF-PAGE-SELECTION
// CHANGE-ID: 20260605_190500_PRDV_StateStripExtract
// SCOPE: PostRecordDetailsView — extract Focus/state strip view and interaction helpers into PostRecordDetailsView+StateStrip without UI or logic changes.
// SEARCH-TOKEN: 20260605_190500_PRDV_StateStripExtract

// CHANGE-ID: 20260605_184500_PRDV_PickerExtract
// SCOPE: PostRecordDetailsView — extract picker sheet/view-builder helpers into PostRecordDetailsView+Pickers without UI or logic changes.
// SEARCH-TOKEN: 20260605_184500_PRDV_PickerExtract

// CHANGE-ID: 20260605_181000_PRDV_AttachmentRequestNameFix
// SCOPE: PostRecordDetailsView — extract attachment viewer/plumbing into PostRecordDetailsView+Attachments without UI or logic changes.
// SEARCH-TOKEN: 20260605_181000_PRDV_AttachmentRequestNameFix

// CHANGE-ID: 20260604_204500_SelectorCards_PRDV
// SCOPE: Replace PRDV instrument/activity wheel pickers with card-sheet selector rows only. No persistence/model/date/duration changes.
// SEARCH-TOKEN: 20260604_204500_SelectorCards_PRDV

// CHANGE-ID: 20260517_164900_PRDV_MetadataMicroPolish
// SCOPE: PostRecordDetailsView — PRDV-only micro-polish of floating metadata rows: calmer thread icon, slightly softer metadata icons/chevrons, tighter label/value spacing, and modest attachment-action breathing room. Preserve all behaviour and reflective sections.
// SEARCH-TOKEN: 20260517_164900_PRDV_MetadataMicroPolish

// CHANGE-ID: 20260513_073900_PRDV_AmbientThreadPrefill
// SCOPE: PostRecordDetailsView — accept optional provisional thread prefill from PracticeTimerView while preserving PRDV as canonical confirmation surface. No UI or logic changes outside thread seeding.
// SEARCH-TOKEN: 20260513_073900_PRDV_AmbientThreadPrefill

// CHANGE-ID: 20260317_181500_PRDV_AutoDescriptionReplaceOnFocus
// SCOPE: PostRecordDetailsView — retain content-header parity and make untouched auto description clear on first focus, restoring auto text on blur if left empty. No other UI or logic changes.
// SEARCH-TOKEN: 20260317_181500_PRDV_AutoDescriptionReplaceOnFocus



//  PostRecordDetailsView_20251004c.swift
//  MOTIVO
//
//  Visual polish + Instrument row chevron fix
//  Silent if one instrument, chevron row if multiple.

// CHANGE-ID: 20260130_164830_PRDV_ShareDebug
// CHANGE-ID: 20260225_092800_prdv_audio_saveas_titles
// SCOPE: PRDV — Audio Save-as-New retains title + suffix (_1, _2...) by seeding stagedAudioNames_temp for new staged audio IDs.
// SCOPE: PRDV — Add definitive debug logging for Share toggle (isPublic) at toggle-change, draft hydration, and save-tap to identify where it flips to true.
// CHANGE-ID: 20260227_223200_PRDV_focusDismiss_desc_notes
// SCOPE: PRDV — Dismiss keyboard/focus for Description + Notes on tap outside/scroll; keep pencil affordance; no other UI/logic changes.
// CHANGE-ID: 20260304_081800_Threads_S3_PRDV_ThreadCardAndPersist
// SCOPE: PRDV — Add owner-only Thread selector card under Description; bind to Session.threadLabel on save; present ThreadPickerView. No other UI/logic changes.

// CHANGE-ID: 20260304_140500_Threads_S6_1_PRDV_ThreadSuggestions
// SCOPE: PRDV Threads v1 Stage 6.1 — pass existing thread suggestions into ThreadPickerView from local Core Data Sessions. No other UI/logic changes.
// SEARCH-TOKEN: 20260304_140500_Threads_S6_1_PRDV_ThreadSuggestions

// CHANGE-ID: 20260412_000100_PRDV_BottomSaveSession
// SCOPE: PostRecordDetailsView — remove top-right Save and add bottom "Save Session" commit action with TimerCard-family styling. No other UI or logic changes.
// SEARCH-TOKEN: 20260412_000100_PRDV_BottomSaveSession

import SwiftUI
import CoreData
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import UIKit

// MARK: - Threads v1 Stage 6.1 (PRDV/AESV suggestions)
// Local-only helper to sanitize, de-duplicate (case-insensitive), and sort thread labels.
// Kept file-local to avoid cross-file dependencies.
private enum ThreadLabelSanitizer_Stage6_1 {
    static let maxLength: Int = 32

    static func sanitize(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let collapsed = trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.isEmpty { return nil }
        if collapsed.count <= maxLength { return collapsed }
        return String(collapsed.prefix(maxLength))
    }

    static func uniqueSorted(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        out.reserveCapacity(raw.count)
        for s in raw {
            guard let clean = sanitize(s) else { continue }
            let key = clean.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(clean)
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}



// MARK: - Attachment Viewer Request (Step 1)
// CHANGE-ID: 20260607_1820_PDFViewerParity
// SCOPE: Route staged PDF attachments through AttachmentViewerView/PDFScoreView from PRDV.
// SEARCH-TOKEN: 20260607_1820-PDF-VIEWER-PARITY
// Atomic presentation payload for AttachmentViewerView (used starting Step 2).
// Defined here (PRDV-only scope) to keep this step compiling without touching other files.
struct PRDVAttachmentViewerRequest: Identifiable {
    enum Mode {
        case visual   // images + videos
        case audio    // audio clips only
    }

    let id = UUID()
    let mode: Mode
    let startIndex: Int

    // Pass-through arrays; actual usage will filter by mode when presented (Step 2+).
    let imageURLs: [URL]
    let videoURLs: [URL]
    let audioURLs: [URL]
    let pdfURLs: [URL]
    let viewerAttachmentIDs: [UUID]

    init(mode: Mode, startIndex: Int, imageURLs: [URL], videoURLs: [URL], audioURLs: [URL], pdfURLs: [URL], viewerAttachmentIDs: [UUID] = []) {
        self.mode = mode
        self.startIndex = startIndex
        self.imageURLs = imageURLs
        self.videoURLs = videoURLs
        self.audioURLs = audioURLs
        self.pdfURLs = pdfURLs
        self.viewerAttachmentIDs = viewerAttachmentIDs
    }
}

private enum TaskLineType_PRDV_Stage1: String, Decodable {
    case task
    case context
}

private struct PersistedTaskLine_PRDV_Stage1: Decodable {
    let id: UUID
    let text: String
    let isDone: Bool
    let type: TaskLineType_PRDV_Stage1

    init(id: UUID, text: String, isDone: Bool, type: TaskLineType_PRDV_Stage1 = .task) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case isDone
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        type = try container.decodeIfPresent(TaskLineType_PRDV_Stage1.self, forKey: .type) ?? .task
    }
}





private struct PRDVScorePageSelection: Equatable {
    var pages: [Int]?
    var hasSelection: Bool
}

struct PostRecordDetailsView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appSettings_tintMode") private var tintModeRawValue: String = Theme.TintMode.auto.rawValue
    @State private var cachedInstrumentCardTint: Theme.ResolvedTint = Theme.ResolvedTint(source: .off, instrumentLabel: nil, activityLabel: nil)


    private var existingThreadOptions: [String] {
        let request: NSFetchRequest<Session> = Session.fetchRequest()
        request.predicate = NSPredicate(format: "threadLabel != nil AND threadLabel != ''")
        request.fetchLimit = 500
        request.returnsObjectsAsFaults = true

        do {
            let sessions = try viewContext.fetch(request)
            let raw = sessions.compactMap { $0.threadLabel }
            return ThreadLabelSanitizer_Stage6_1.uniqueSorted(raw)
        } catch {
            return []
        }
    }

    @Binding var isPresented: Bool
    private let prefillTimestamp: Date
    private let prefillDurationSeconds: Int

    @State var instruments: [Instrument] = []
    @State var instrument: Instrument?
    @State private var title: String = ""
    @State var timestamp: Date
    @State var durationSeconds: Int
    @State var activity: SessionActivityType = .practice
    @State var userActivities: [UserActivity] = []
    @State var activityChoice: String = "core:0"
    @State var selectedCustomName: String = ""
    @State private var isPublic: Bool = true
    @State private var mood: Int = 5
    @State private var effort: Int = 5
    @State private var notes: String = ""
    @State private var activityDetail: String = ""
@State private var threadLabel: String? = nil
    @State private var lastAutoActivityDetail: String = ""
    @State private var userEditedActivityDetail: Bool = false

    @State private var isTitleEdited = false
    @State private var initialAutoTitle = ""
    
    @State private var areNotesPrivate: Bool = false
    @State private var includeTasksInNotes: Bool = false
    @State private var injectedCompletedTasksBlock: String? = nil


    @FocusState private var isActivityDetailFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @State private var notesKeyboardInset: CGFloat = 0
    @State var attachmentTitlesRefreshTick: Int = 0


    @State var showStartPicker = false
    @State var showDurationPicker = false
@State private var showThreadPicker = false
    @State var showActivityPicker = false
    @State var showInstrumentPicker = false
    @State var tempDate = Date()
    @State var tempHours = 0
    @State var tempMinutes = 0
    @State var tempActivity: SessionActivityType = .practice

    @State var stagedAttachments: [StagedAttachment] = []
    @State var selectedThumbnailID: UUID? = nil
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraDeniedAlert = false

    @State var isShowingAttachmentViewer: Bool = false
    @State var viewerStartIndex: Int = 0

    // Step 1: New atomic request state (unused until Step 2).
    @State var viewerRequest: PRDVAttachmentViewerRequest? = nil
    @State var pdfPageSelectionRequest: PDFPageSelectionRequest? = nil
    @State private var scorePageSelectionRequest: PDFPageSelectionRequest? = nil
    @State private var scorePageSelections: [UUID: PRDVScorePageSelection] = [:]
    @State private var showScoreAttachLibrary: Bool = false
    @State private var manuallyAttachedScoreIDs: [UUID] = []

    @AppStorage("primaryActivityRef") var primaryActivityRef: String = "core:0"

    private let draftNotesKey = "PostRecordDetailsView.draft.notes"
    private let draftFocusKey = "PostRecordDetailsView.draft.focusDot"
    private let draftIsPublicKey = "PostRecordDetailsView.draft.isPublic_v1"

    private let sessionIDKey = "PracticeTimer.currentSessionID"
    private let lastSeenSessionIDKey = "PostRecordDetailsView.lastSeenSessionID"
    private let sessionStartTimestampKey = "PracticeTimer.currentSessionStartTimestamp"
    private let timerTaskLinesKey = "PracticeTimer.taskLines"

    private func currentSessionID() -> String? {
        UserDefaults.standard.string(forKey: sessionIDKey)
    }

    private func loadDraftIsPublicIfNeeded() {
        // Default is ON (true). If user flipped OFF and the view was recreated before Save,
        // rehydrate from draft storage to avoid snapping back to true.
        if UserDefaults.standard.object(forKey: draftIsPublicKey) != nil {
            isPublic = UserDefaults.standard.bool(forKey: draftIsPublicKey)
        } else {
            // Keep existing default (true) unless a future caller explicitly sets it.
        }
    }

    private func persistDraftIsPublic() {
        UserDefaults.standard.set(isPublic, forKey: draftIsPublicKey)
    }

    private func clearDraftIsPublic() {
        UserDefaults.standard.removeObject(forKey: draftIsPublicKey)
    }


    // v7.9E — State circles (neutral greys)
    private let stateOpacities: [Double] = [0.80, 0.60, 0.30, 0.05] // 0=Searching (dark) → 3=Breakthrough (clear)

    // v7.9E — 12-dot gradient strip (dark → light) with drag selection
    private let stateDotsCount: Int = 12

    @State var selectedDotIndex: Int? = nil
    @State private var hoverDotIndex: Int? = nil        // transient dot under finger during drag
    @State private var lastHapticZone: Int? = nil       // throttle haptic to zone changes

    // Drag refinements
    @State private var dragX: CGFloat? = nil          // live finger x within the strip
    @State var lastHapticDot: Int? = nil      // fire haptic when this changes

    let focusSnapCount: Int = 10
    @State var liveFocusProgress: CGFloat? = nil


    /// DARK ➜ LIGHT across the row. On dark themes this reads as “clearer toward the right”.
    private func opacityForDot(_ i: Int) -> Double {
        // 0 = darkest (high opacity), 11 = lightest (low opacity)
        let start: Double = 0.95   // darker (more opaque) on the left
        let end:   Double = 0.15   // lighter (less opaque) on the right (slightly lighter than before)
        guard stateDotsCount > 1 else { return start }
        let t = Double(i) / Double(stateDotsCount - 1)
        return start + (end - start) * t
    }

    // ---- Privacy cache & helpers (inside the view struct) ----
    @State private var privacyMap: [String: Bool] = [:]

    private func privacyKey(id: UUID?, url: URL?) -> String? {
        if let id { return "id://\(id.uuidString)" }
        if let url { return url.absoluteString }
        return nil
    }

    private func loadPrivacyMap() {
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
        // Update cache immediately for responsive UI
        privacyMap[key] = value
        // Persist via shared utility (also posts didChange)
        AttachmentPrivacy.setPrivate(id: id, url: url, value)
    }

    // --- PATCH 8G3A: migrate staged privacy → final attachment keys using AttachmentPrivacy (file-backed) ---
    // SEARCH-ANCHOR: func migratePrivacy(fromStagedID stagedID: UUID, stagedURL: URL?, toNewID newID: UUID?, newURL: URL?)
    func migratePrivacy(fromStagedID stagedID: UUID, stagedURL: URL?, toNewID newID: UUID?, newURL: URL?) {
        // AttachmentPrivacy is file-backed; read staged value from the real source of truth.
        // Default is private=true, so only explicit “included” (private=false) needs to be preserved for Phase 3.
        let stagedIsPrivate = AttachmentPrivacy.isPrivate(id: stagedID, url: stagedURL)

        // Write the staged value onto the final keys so backend publish selection sees it.
        if newID != nil || newURL != nil {
            AttachmentPrivacy.setPrivate(id: newID, url: newURL, stagedIsPrivate)
        }


        // Keep PRDV local cache in sync for any immediate UI reads in this view.
        privacyMap = AttachmentPrivacy.currentMap()
    }
    // ---- end privacy helpers ----

    // Best-effort purge for surrogate temp files created for staged items
    private func purgeStagedTempFiles() {
        let fm = FileManager.default
        for att in stagedAttachments {
            let ext: String = {
                    if let surl = surrogateURL(for: att) {
                        let e = surl.pathExtension.lowercased()
                        if !e.isEmpty { return e }
                    }
                    return defaultSurrogateExtension(for: att.kind)
                }()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(att.id.uuidString)
                .appendingPathExtension(ext)
            try? fm.removeItem(at: url)
        }
    }

    private var totalStagedBytes: Int {
        stagedAttachments.reduce(0) { $0 + $1.data.count }
    }
    var stagedSizeWarning: String? {
        let limit = 100 * 1024 * 1024 // 100 MB
        return totalStagedBytes > limit ? "Large staging size (~\(totalStagedBytes / (1024*1024)) MB). Consider saving or removing some items." : nil
    }

    var onSaved: (() -> Void)?
    var onCancel: () -> Void = {}

    private let usedScoreIDsPrefill: [UUID]
    private let meaningfulScorePagesPrefill: [UUID: [Int]]
    private let lastMeaningfulScorePagePrefill: [UUID: Int]
    private let prefillAttachments: [StagedAttachment]?
    private let prefillAttachmentNames: [UUID: String]?

    init(
        isPresented: Binding<Bool>,
        timestamp: Date? = nil,
        durationSeconds: Int? = nil,
        instrument: Instrument? = nil,
        activityTypeRaw: Int16? = nil,
        activityDetailPrefill: String? = nil,
        notesPrefill: String? = nil,
        threadLabelPrefill: String? = nil,
        usedScoreIDsPrefill: [UUID] = [],
        meaningfulScorePagesPrefill: [UUID: [Int]] = [:],
        lastMeaningfulScorePagePrefill: [UUID: Int] = [:],
        prefillAttachments: [StagedAttachment]? = nil,
        prefillAttachmentNames: [UUID: String]? = nil,
        onSaved: (() -> Void)? = nil,
        onCancel: @escaping () -> Void = {}
    ) {
        self._isPresented = isPresented
        // Prefer the actual session start time from PracticeTimerView if available
        let ud = UserDefaults.standard
        var resolvedStart = timestamp
        if resolvedStart == nil {
            if let sessionID = ud.string(forKey: sessionIDKey) {
                // If a session is active, try to load its recorded start timestamp
                let key = "\(sessionStartTimestampKey).\(sessionID)"
                if let startInterval = ud.object(forKey: key) as? TimeInterval {
                    resolvedStart = Date(timeIntervalSince1970: startInterval)
                } else if let startInterval = ud.object(forKey: sessionStartTimestampKey) as? TimeInterval {
                    // Back-compat: support a global start timestamp key if used by older builds
                    resolvedStart = Date(timeIntervalSince1970: startInterval)
                }
            } else if let startInterval = ud.object(forKey: sessionStartTimestampKey) as? TimeInterval {
                // Fallback if no session ID is available but a start timestamp exists
                resolvedStart = Date(timeIntervalSince1970: startInterval)
            }
        }
        self.prefillTimestamp = resolvedStart ?? Date()
        self.prefillDurationSeconds = max(0, durationSeconds ?? 0)
        self._timestamp = State(initialValue: self.prefillTimestamp)
        self._durationSeconds = State(initialValue: self.prefillDurationSeconds)
        self._instrument = State(initialValue: instrument)
        if let prefill = activityDetailPrefill, !prefill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self._selectedCustomName = State(initialValue: prefill)
            self._activityDetail = State(initialValue: "")
            self._activity = State(initialValue: .practice)
            self._activityChoice = State(initialValue: "custom:\(prefill)")
        }
        if let raw = activityTypeRaw { self._activity = State(initialValue: SessionActivityType(rawValue: raw) ?? .practice) }
        self._notes = State(initialValue: notesPrefill ?? "")
        self._threadLabel = State(initialValue: ThreadLabelSanitizer_Stage6_1.sanitize(threadLabelPrefill ?? ""))
        self.usedScoreIDsPrefill = usedScoreIDsPrefill
        self.meaningfulScorePagesPrefill = meaningfulScorePagesPrefill
        self.lastMeaningfulScorePagePrefill = lastMeaningfulScorePagePrefill
        self.prefillAttachments = prefillAttachments
        self.prefillAttachmentNames = prefillAttachmentNames
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    private var prdvTintMode: Theme.TintMode {
        Theme.TintMode(rawValue: tintModeRawValue) ?? .auto
    }

    private var effectiveInstrumentTintLabel: String? {
        if let selectedName = instrument?.name,
           let normalized = Theme.InstrumentTint.normalizedLabel(selectedName) {
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
        let direct = item.userInstrumentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty {
            return Theme.InstrumentTint.normalizedLabel(direct)
        }

        let related = item.instrument?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let related, !related.isEmpty {
            return Theme.InstrumentTint.normalizedLabel(related)
        }

        return nil
    }

    private func normalizedActivityLabel(for item: Session) -> String? {
        let direct = item.userActivityLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty {
            return Theme.ActivityTint.normalizedLabel(direct)
        }

        if let raw = item.value(forKey: "activityType") as? Int16,
           let type = SessionActivityType(rawValue: raw) {
            return Theme.ActivityTint.normalizedLabel(type.label)
        }

        return nil
    }

    private func recomputeInstrumentCardTintIfNeeded() {
        let owner = tintOwnerID?.trimmingCharacters(in: .whitespacesAndNewlines)

        let ownerSessions: [Session]
        if let owner, !owner.isEmpty {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.sortDescriptors = []
            request.predicate = NSPredicate(format: "ownerUserID == %@", owner)

            do {
                ownerSessions = try viewContext.fetch(request)
            } catch {
                ownerSessions = []
            }
        } else {
            ownerSessions = []
        }

        var instrumentCounts: [String: Int] = [:]
        var activityCounts: [String: Int] = [:]

        for item in ownerSessions {
            if let instrument = normalizedInstrumentLabel(for: item) {
                instrumentCounts[instrument, default: 0] += 1
            }
            if let activity = normalizedActivityLabel(for: item) {
                activityCounts[activity, default: 0] += 1
            }
        }

        cachedInstrumentCardTint = Theme.resolvedTint(
            instrument: effectiveInstrumentTintLabel,
            activity: effectiveActivityTintLabel,
            tintMode: prdvTintMode,
            instrumentCounts: instrumentCounts,
            activityCounts: activityCounts
        )
    }

    private var instrumentCardFillColor: Color {
        guard cachedInstrumentCardTint.source == .instrument else {
            return Theme.Colors.surface(colorScheme)
        }
        return cachedInstrumentCardTint.fill(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var instrumentCardStrokeColor: Color {
        guard cachedInstrumentCardTint.source == .instrument else {
            return Theme.Colors.cardStroke(colorScheme)
        }
        return cachedInstrumentCardTint.stroke(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var activityCardFillColor: Color {
        guard cachedInstrumentCardTint.source == .activity else {
            return Theme.Colors.surface(colorScheme)
        }
        return cachedInstrumentCardTint.fill(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    private var activityCardStrokeColor: Color {
        guard cachedInstrumentCardTint.source == .activity else {
            return Theme.Colors.cardStroke(colorScheme)
        }
        return cachedInstrumentCardTint.stroke(
            ownerID: tintOwnerID,
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    
    private var usedScoreItems: [ScoreLibraryItem] {
        let lookup = Dictionary(uniqueKeysWithValues: ScoreLibraryStore.shared.items.map { ($0.id, $0) })
        var seen = Set<UUID>()
        let combinedIDs = usedScoreIDsPrefill + manuallyAttachedScoreIDs
        return combinedIDs.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return lookup[id]
        }
    }

    private func attachManualScore(_ score: ScoreLibraryItem) {
        guard !usedScoreIDsPrefill.contains(score.id), !manuallyAttachedScoreIDs.contains(score.id) else { return }
        manuallyAttachedScoreIDs.append(score.id)
    }

    private func selectedPagesForUsedScore(_ id: UUID) -> [Int]? {
        PDFSelectedPagesStore.sanitized(scorePageSelections[id]?.pages)
    }

    private func setSelectedPagesForUsedScore(_ pages: [Int]?, id: UUID) {
        scorePageSelections[id] = PRDVScorePageSelection(
            pages: PDFSelectedPagesStore.sanitized(pages),
            hasSelection: true
        )
    }

    private func commitUsedScoreAttachments(to session: Session, ctx: NSManagedObjectContext) {
        let fileManager = FileManager.default
        var committedScoreIDs = Set<UUID>()

        for score in usedScoreItems {
            guard committedScoreIDs.insert(score.id).inserted else { continue }

            let url = ScoreLibraryStore.shared.url(for: score)
            guard fileManager.fileExists(atPath: url.path) else {
                #if DEBUG
                print("Scores Phase 7 skipped missing score PDF: \(url.path)")
                #endif
                continue
            }

            do {
                let created = try AttachmentStore.addAttachment(
                    kind: .pdf,
                    filePath: url.path,
                    to: session,
                    isThumbnail: false,
                    displayName: score.title,
                    ctx: ctx
                )

                if let finalID = created.value(forKey: "id") as? UUID {
                    PDFSelectedPagesStore.setPages(selectedPagesForUsedScore(score.id), for: finalID)
                }
            } catch {
                #if DEBUG
                print("Scores Phase 7 failed to attach score PDF: \(error)")
                #endif
            }
        }
    }

    private func selectionSummaryForUsedScore(_ id: UUID) -> String? {
        guard let selection = scorePageSelections[id], selection.hasSelection else { return nil }
        return PDFSelectedPagesFormatter.summary(for: selection.pages)
    }

    private func meaningfulPagesForUsedScore(_ id: UUID) -> [Int] {
        PDFSelectedPagesStore.sanitized(meaningfulScorePagesPrefill[id]) ?? []
    }

    private func lastMeaningfulPageForUsedScore(_ id: UUID) -> Int? {
        guard let page = lastMeaningfulScorePagePrefill[id], page > 0 else { return nil }
        return page
    }

    private func isScoreSelection(_ id: UUID, matching pages: [Int]?) -> Bool {
        guard let selection = scorePageSelections[id], selection.hasSelection else {
            return PDFSelectedPagesStore.sanitized(pages) == nil
        }
        return PDFSelectedPagesStore.sanitized(selection.pages) == PDFSelectedPagesStore.sanitized(pages)
    }

    @ViewBuilder
    private func scoreSelectionOption(title: String, pages: [Int]?, id: UUID) -> some View {
        Button {
            setSelectedPagesForUsedScore(pages, id: id)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: isScoreSelection(id, matching: pages) ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isScoreSelection(id, matching: pages)
                        ? AnyShapeStyle(Theme.Colors.accent)
                        : AnyShapeStyle(Theme.Colors.secondaryText.opacity(0.65))
                    )
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scoreCustomSelectionOption(_ score: ScoreLibraryItem) -> some View {
        Button {
            scorePageSelectionRequest = PDFPageSelectionRequest(
                id: score.id,
                pageCount: max(score.pageCount, 1)
            )
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.65))
                    .frame(width: 22, height: 22)

                Text("Custom…")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func usedScoreRow(_ score: ScoreLibraryItem) -> some View {
        let meaningfulPages = meaningfulPagesForUsedScore(score.id)
        let lastMeaningfulPage = lastMeaningfulPageForUsedScore(score.id)

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.title)
                        .font(Theme.Text.body)

                    if let summary = selectionSummaryForUsedScore(score.id) {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                scoreSelectionOption(title: "Entire document", pages: nil, id: score.id)

                if meaningfulPages.count == 1, let page = meaningfulPages.first {
                    scoreSelectionOption(title: "Page \(page)", pages: [page], id: score.id)
                } else if meaningfulPages.count > 1 {
                    if let lastMeaningfulPage {
                        scoreSelectionOption(
                            title: "Last meaningful page (\(lastMeaningfulPage))",
                            pages: [lastMeaningfulPage],
                            id: score.id
                        )
                    }

                    scoreSelectionOption(
                        title: "Meaningful pages (\(meaningfulPages.map(String.init).joined(separator: ", ")))",
                        pages: meaningfulPages,
                        id: score.id
                    )
                }

                scoreCustomSelectionOption(score)
            }
        }
        .padding(.vertical, 2)
    }

var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    Text("Session Review").sectionHeader()

                    // ---------- Instrument ----------
                    if hasNoInstruments {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("No instruments found").sectionHeader()
                            Text("Add an instrument in your Profile to save this session.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .cardSurface()
                    } else if hasMultipleInstruments {
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
                    }
                    // Silent if exactly one instrument

                    // ---------- Activity ----------
                    Button {
                        tempActivity = activity
                        showActivityPicker = true
                    } label: {
                        HStack(alignment: .center, spacing: Theme.Spacing.m) {
                            Image(systemName: "circle.grid.2x2")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.63))
                                .frame(width: 22, height: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Activity")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                let display = selectedCustomName.isEmpty ? activity.label : selectedCustomName
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

                    // ---------- Activity description ----------
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
                                .textInputAutocapitalization(.never)
                                .font(Theme.Text.body)
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

                    // ---------- Thread ----------
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

                    // ---------- Start time ----------
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
                                Text("Start Time")
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

                    // ---------- Duration ----------
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            let hm = secondsToHM(durationSeconds)
                            tempHours = hm.0
                            tempMinutes = hm.1
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


                    if !usedScoreItems.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Scores Used").sectionHeader()

                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                ForEach(usedScoreItems) { score in
                                    usedScoreRow(score)
                                }
                            }
                        }
                        .cardSurface()
                    }

                    // ---------- Notes ----------
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Notes").sectionHeader()
                            Spacer()
                            Button(action: {
                                areNotesPrivate.toggle()
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            }) {
                                Image(systemName: areNotesPrivate ? "eye.slash" : "eye")
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(areNotesPrivate ? "Make notes visible to others" : "Make notes private")
                        }
                        if areNotesPrivate {
                            Text("Only you will see these notes.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        Toggle("Include tasks in notes", isOn: $includeTasksInNotes)
                            .font(Theme.Text.body)
                            .tint(Theme.Colors.accent)
                        TextEditor(text: $notes)
                            .focused($isNotesFocused)
                            .frame(minHeight: 120)
                            .font(Theme.Text.body)
                    }
                    .cardSurface()

                    stateStripCard

                    attachmentsSection
                        .cardSurface(padding: Theme.Spacing.m)

                    addAttachmentsControlsSection

                    Group {
                        bottomSaveButton
                    }
                }
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
                    Button {
                        // Intentional discard: purge any currently staged items for this review
                        let discardIDs: [UUID] = stagedAttachments.map { $0.id }
                        if !discardIDs.isEmpty {
                            StagingStore.removeMany(ids: discardIDs)
                        }
                        // Also purge any surrogate temp files created for staged items
                        purgeStagedTempFiles()
                        onCancel()
                        // Update last seen session ID on cancel to prevent re-clearing within same session
                        if let cur = currentSessionID() { UserDefaults.standard.set(cur, forKey: lastSeenSessionIDKey) }
                        isPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back to Timer")
                }

            }
            .onAppear {
                loadDraftIsPublicIfNeeded()
                recomputeInstrumentCardTintIfNeeded()
            }
            .onChange(of: includeTasksInNotes) { _ in
                syncCompletedTasksIntoVisibleNotes()
            }
            .onChange(of: tintModeRawValue) { _, _ in
                recomputeInstrumentCardTintIfNeeded()
            }
            .onChange(of: isPublic) {
                persistDraftIsPublic()
            }
            .fullScreenCover(item: $viewerRequest) { request in
                attachmentViewerCover(request: request)
            }
            // Sheets
            .sheet(isPresented: $showInstrumentPicker) { instrumentPicker }
            .sheet(isPresented: $showActivityPicker) { activityPickerPinned }
            .sheet(isPresented: $showStartPicker) { startPicker }
            .sheet(isPresented: $showDurationPicker) { durationPicker }
            .sheet(isPresented: $showThreadPicker) {
                ThreadPickerView(selectedThread: $threadLabel, recentThreads: existingThreadOptions)
            }
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
            .sheet(item: $scorePageSelectionRequest) { request in
                PDFPageSelectionSheet(
                    pageCount: request.pageCount,
                    selectedPages: Binding(
                        get: { selectedPagesForUsedScore(request.id) },
                        set: { setSelectedPagesForUsedScore($0, id: request.id) }
                    )
                )
            }
            .sheet(isPresented: $showScoreAttachLibrary) {
                ScoresLibraryView(
                    mode: .attach,
                    onAttachScore: { score in
                        attachManualScore(score)
                    }
                )
            }
            .sheet(isPresented: $showCamera) { CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.8) { stageData(data, kind: .image) }
            } }
            .alert("Camera access denied",
                   isPresented: $showCameraDeniedAlert,
                   actions: {
                       Button("OK", role: .cancel) {}
                       Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                   },
                   message: { Text("Enable camera access in Settings → Privacy → Camera to take photos.") })
            .task {
                if let pre = prefillAttachments, !pre.isEmpty, stagedAttachments.isEmpty {
                    stagedAttachments.append(contentsOf: pre)
                    if let nameMap = prefillAttachmentNames {
                        // Store in a temporary map via UserDefaults for the lifetime of this view, keyed by staged id
                        let key = "stagedAudioNames_temp"
                        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
                        for att in pre {
                            if let title = nameMap[att.id], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                dict[att.id.uuidString] = title
                            }
                        }
                        UserDefaults.standard.set(dict, forKey: key)
                    }
                }

                // Clear Notes and Focus when entering from a fresh PracticeTimer session
                // Only clear if we don't already have a prefilled note (e.g., from PracticeTimerView)
                let ud = UserDefaults.standard
                let currentID = currentSessionID()
                let lastSeen = ud.string(forKey: lastSeenSessionIDKey)
                if currentID != nil && currentID != lastSeen {
                    // New session detected: clear persisted draft and local state,
                    // but only if the current notes are effectively empty so we don't clobber a prefill.
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        notes = ""
                        selectedDotIndex = nil
                        clearDraft()
                    }
                    ud.set(currentID, forKey: lastSeenSessionIDKey)
                }

                preselectFocusFromNotesIfNeeded()
                loadDraftIfAvailable()
                instruments = fetchInstruments()
                if instrument == nil {
                    if let primaryName = fetchPrimaryInstrumentName(),
                       let match = instruments.first(where: { ($0.name ?? "").caseInsensitiveCompare(primaryName) == .orderedSame }) {
                        instrument = match
                    } else if hasOneInstrument {
                        instrument = instruments.first
                    }
                }
                tempActivity = activity
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let auto = defaultTitle(for: instrument, activity: activity)
                    title = auto
                    initialAutoTitle = auto
                    isTitleEdited = false
                }
                if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let autoDesc = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
                    activityDetail = autoDesc
                    lastAutoActivityDetail = autoDesc
                    userEditedActivityDetail = false
                }
                loadUserActivities()
                syncActivityChoiceFromState()
                loadDraftIfAvailable()
            }
            .onChange(of: instrument) { _, _ in
                refreshAutoTitleIfNeeded()
                recomputeInstrumentCardTintIfNeeded()
            }
            .onChange(of: activity) { _, _ in
                maybeUpdateActivityDetailFromDefaults()
                recomputeInstrumentCardTintIfNeeded()
            }
            .onChange(of: selectedCustomName) { _, _ in
                recomputeInstrumentCardTintIfNeeded()
            }
            .onChange(of: isActivityDetailFocused) { oldValue, newValue in
                handleActivityDetailFocusChange(oldValue: oldValue, newValue: newValue)
            }
            .onChange(of: activityDetail) { _, newValue in
                handleActivityDetailChange(newValue)
            }
            .onChange(of: notes) { _, new in
                UserDefaults.standard.set(new, forKey: draftNotesKey)
            }
            .onChange(of: selectedDotIndex) { _, new in
                if let v = new {
                    UserDefaults.standard.set(v, forKey: draftFocusKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: draftFocusKey)
                }
            }
            .onAppear { loadPrivacyMap() }
            .onReceive(NotificationCenter.default.publisher(for: AttachmentPrivacy.didChangeNotification)) { _ in
                loadPrivacyMap()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                purgeStagedTempFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                clearDraft()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Do not clear drafts on background; preserve in-session state when user switches apps
            }
            .appBackground()
            .onDisappear {
                purgeStagedTempFiles()
                // Keep last seen session ID in sync on disappear (non-destructive)
                if let cur = currentSessionID() { UserDefaults.standard.set(cur, forKey: lastSeenSessionIDKey) }
            }
        }
    }

    // MARK: - Draft helpers

    private func loadDraftIfAvailable() {
        let ud = UserDefaults.standard
        if let draft = ud.string(forKey: draftNotesKey) {
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notes = draft
            }
        }
        if selectedDotIndex == nil, ud.object(forKey: draftFocusKey) != nil {
            let v = ud.integer(forKey: draftFocusKey)
            if (0...11).contains(v) {
                selectedDotIndex = v
            }
        }
    }

    private func clearDraft() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: draftNotesKey)
        ud.removeObject(forKey: draftFocusKey)
    }

    // MARK: - Subviews

    private var bottomSaveButton: some View {
        HStack {
            Spacer(minLength: 0)

            Button(action: {
                let visibility = isPublic
                saveToCoreData(visibility: visibility)
                DispatchQueue.main.async { withAnimation(.none) { isPresented = false } }
            }) {
                Text("Save Session")
                    .font(Theme.Text.body)
            }
            .frame(maxWidth: 260, minHeight: 44)
            .background(Theme.Colors.primaryAction.opacity(0.17))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .buttonStyle(.plain)
            .disabled(durationSeconds == 0 || instrument == nil)

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.m)
    }

    private var addAttachmentsControlsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: 32) {
                Button(action: { showPhotoPicker = true }) {
                    ZStack {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62)) // slate blue-grey
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
                            .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62)) // slate blue-grey
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.18))
                                    .frame(width: 64, height: 64)
                            )
                    }
                }
                .accessibilityLabel("Add file")
                .contentShape(Circle())
                .buttonStyle(.plain)
                .tint(.accentColor)

                Button(action: { showScoreAttachLibrary = true }) {
                    ZStack {
                        Image(systemName: "book.closed")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62)) // slate blue-grey
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.18))
                                    .frame(width: 64, height: 64)
                            )
                    }
                }
                .accessibilityLabel("Attach score")
                .contentShape(Circle())
                .buttonStyle(.plain)
                .tint(.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)
        }
    }


    // Instrument picker sheet






    // MARK: - Helpers
    func formatClipDuration(_ seconds: Double) -> String {
        // Simple mm:ss formatter
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }


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

    func loadUserActivities() {
        do { userActivities = try PersistenceController.shared.fetchUserActivities(in: viewContext) }
        catch { userActivities = [] }
    }


    private func handleActivityDetailFocusChange(oldValue: Bool, newValue: Bool) {
        if oldValue == false && newValue == true {
            let trimmed = activityDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userEditedActivityDetail,
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
            }
        }
    }

    private func handleActivityDetailChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        userEditedActivityDetail = (!trimmed.isEmpty && trimmed != lastAutoActivityDetail)
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

    func maybeUpdateActivityDetailFromDefaults() {
        let newDefault = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activityDetail == lastAutoActivityDetail {
            activityDetail = newDefault
            lastAutoActivityDetail = newDefault
            userEditedActivityDetail = false
        }
    }

    private func completedTasksNotesStringForCurrentSession() -> String? {
        guard let data = UserDefaults.standard.data(forKey: timerTaskLinesKey),
              let decoded = try? JSONDecoder().decode([PersistedTaskLine_PRDV_Stage1].self, from: data) else {
            return nil
        }

        var output = ""
        var lastEmittedType: TaskLineType_PRDV_Stage1? = nil

        for line in decoded {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let formattedLine: String
            switch line.type {
            case .context:
                formattedLine = trimmed
            case .task:
                guard line.isDone else { continue }
                formattedLine = "• \(trimmed)"
            }

            if output.isEmpty {
                output = formattedLine
            } else {
                switch (lastEmittedType, line.type) {
                case (.task?, .context):
                    output += "\n\n" + formattedLine
                default:
                    output += "\n" + formattedLine
                }
            }

            lastEmittedType = line.type
        }

        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedOutput.isEmpty ? nil : trimmedOutput
    }

    private func notesIncludingCompletedTasksIfNeeded() -> String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncCompletedTasksIntoVisibleNotes() {
        let previousBlock = injectedCompletedTasksBlock?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let previousBlock, !previousBlock.isEmpty {
            let suffixWithSpacing = "\n\n" + previousBlock
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedNotes == previousBlock {
                notes = ""
            } else if notes.hasSuffix(suffixWithSpacing) {
                notes.removeLast(suffixWithSpacing.count)
            }
            injectedCompletedTasksBlock = nil
        }

        guard includeTasksInNotes, let completedTasks = completedTasksNotesStringForCurrentSession() else {
            return
        }

        let trimmedCompleted = completedTasks.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCompleted.isEmpty else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNotes.isEmpty {
            notes = trimmedCompleted
        } else {
            notes += "\n\n" + trimmedCompleted
        }
        injectedCompletedTasksBlock = trimmedCompleted
    }

    private func preselectFocusFromNotesIfNeeded() {
        guard selectedDotIndex == nil, !notes.isEmpty else { return }

        if let r = notes.range(of: "FocusDotIndex:") {
            let tail = notes[r.upperBound...]
            let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if let n = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), (0...11).contains(n) {
                selectedDotIndex = n
                stripFocusTokensFromNotes()
                return
            }
        }

        // Back-compat from legacy StateIndex: 0–3 → center dots
        if let r = notes.range(of: "StateIndex:") {
            let tail = notes[r.upperBound...]
            let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            if let n = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), (0...3).contains(n) {
                let centers = [1, 4, 7, 10]
                selectedDotIndex = centers[n]
                stripFocusTokensFromNotes()
            }
        }
    }

    private func stripFocusTokensFromNotes() {
        let tokens = ["FocusDotIndex:", "StateIndex:"]
        for t in tokens {
            while let r = notes.range(of: t) {
                let tail = notes[r.upperBound...]
                let end = tail.firstIndex(of: "\n") ?? notes.endIndex
                notes.removeSubrange(r.lowerBound..<end)
                // Remove a trailing newline if we left an empty line
                if notes.hasSuffix("\n\n") { notes.removeLast() }
            }
        }
    }

    private func applyFocusToNotesBeforeSave() {
        // Notes must remain user-entered text only.
        // Focus is already stored structurally (Session.effort / publish payload effort).
        stripFocusTokensFromNotes()
    }

    @MainActor
    private func saveToCoreData(visibility: Bool) {
        let s = Session(context: viewContext)
        if (s.value(forKey: "id") as? UUID) == nil {
            let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
            s.setValue(trimmedCustom.isEmpty ? nil : trimmedCustom, forKey: "userActivityLabel")
            s.setValue(UUID(), forKey: "id")
        }
        if s.timestamp == nil { s.timestamp = Date() }
        s.instrument = instrument
        s.title = title.isEmpty ? defaultTitle(for: instrument, activity: activity) : title
        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = visibility
        s.mood = Int16(mood)
        if let idx = selectedDotIndex {
            s.effort = Int16(idx)
        } else {
            s.effort = Int16(effort)
        }

        applyFocusToNotesBeforeSave()
        if s.entity.attributesByName.keys.contains("areNotesPrivate") {
            s.setValue(areNotesPrivate, forKey: "areNotesPrivate")
        }
        s.notes = notesIncludingCompletedTasksIfNeeded()

        s.setValue(activityDetail.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "activityDetail")
        if s.entity.attributesByName.keys.contains("threadLabel") {
            s.setValue(threadLabel, forKey: "threadLabel")
        }

        
        let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        let activityTypeString = trimmedCustom.isEmpty ? activity.label : trimmedCustom

        // Replaced this line:
        // s.setValue(activityTypeString, forKey: "activityType")
        s.setValue(activity.rawValue, forKey: "activityType")
        
        #if DEBUG
        let __dbgID = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride")
        let __effectiveUID = __dbgID ?? PersistenceController.shared.currentUserID
#else
        let __effectiveUID = PersistenceController.shared.currentUserID
#endif
        if let uid = __effectiveUID, !uid.isEmpty {
            s.setValue(uid, forKey: "ownerUserID")
        }
        commitUsedScoreAttachments(to: s, ctx: viewContext)
        commitStagedAttachments(to: s, ctx: viewContext)
        do {
            try viewContext.save()
            viewContext.processPendingChanges()
            clearDraftIsPublic()
            // v7.12A — Social Pilot (local-only)
            if let sid = s.id {
                let resolvedTitle = s.title ?? ""
                let instLabel =
                    (s.userInstrumentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? s.instrument?.name

                let focusValue: Int? = {
                    if let idx = selectedDotIndex { return idx }
                    return nil
                }()

                let payload = SessionSyncQueue.PostPublishPayload(
                    id: sid,
                    sessionID: sid,
                    sessionTimestamp: timestamp,
                    title: resolvedTitle,
                    durationSeconds: Int(durationSeconds),
                    activityType: activityTypeString,
                    activityDetail: activityDetail.trimmingCharacters(in: .whitespacesAndNewlines),
                    instrumentLabel: instLabel,
                    mood: nil,
                    effort: focusValue,
                    isPublic: visibility
                )

                PublishService.shared.publish(
                    payload: payload,
                    objectID: s.objectID,
                    shouldPublish: true
                )
            } else {
                print("Publish skipped: missing Session.id")
            }
            FeedInteractionStore.markForPublish(s.id ?? UUID())

            // Cleanup: remove staged items that were just committed successfully
            let consumedIDs: [UUID] = stagedAttachments.map { $0.id }
            if !consumedIDs.isEmpty {
                StagingStore.removeMany(ids: consumedIDs)
            }
            // Also purge any surrogate temp files created for staged items
            purgeStagedTempFiles()

            PracticeInsightSessionStore.shared.generateInsight(forNewlySavedSession: s, in: viewContext)

            onSaved?()
            clearDraft()
            // Mark this session ID as seen so reopening within the same session doesn't clear again
            if let cur = currentSessionID() { UserDefaults.standard.set(cur, forKey: lastSeenSessionIDKey) }

            // Reset local fields after save so next fresh session starts blank
            notes = ""
            selectedDotIndex = nil
        } catch {
            // On failure, best-effort: remove any files written during this attempt by scanning attachments without permanent IDs
          
            if let set = s.attachments as? Set<Attachment> {
                for a in set {
                    if a.objectID.isTemporaryID, let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                        AttachmentStore.removeIfExists(path: path)
                    }
                }
            }
            viewContext.rollback()
            purgeStagedTempFiles()
            print("Error saving session (timer review): \(error)")
        }
    }

    private func defaultTitle(for inst: Instrument? = nil, activity: SessionActivityType) -> String {
        if let name = (inst ?? instrument)?.name, !name.isEmpty { return "\(name) : \(activity.label)" }
        return activity.label
    }

    func refreshAutoTitleIfNeeded() {
        guard !isTitleEdited else { return }
        let auto = defaultTitle(for: instrument, activity: activity)
        title = auto
        initialAutoTitle = auto
    }

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
        } catch { print("Profile fetch failed: \(error)") }
        return nil
    }

    private func secondsToHM(_ seconds: Int) -> (Int, Int) {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return (h, m)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func ensureCameraAuthorized(onAuthorized: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: onAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? onAuthorized() : { self.showCameraDeniedAlert = true }() }
            }
        default: self.showCameraDeniedAlert = true
        }
    }

    private func dismissToRoot() {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let keyWindow = windowScene?.windows.first { $0.isKeyWindow }
        keyWindow?.rootViewController?.dismiss(animated: true)
        #endif
    }
}

