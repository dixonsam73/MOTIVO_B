// CHANGE-ID: 20260209_113255_AESV_StarToggle_VisualGrid
// SCOPE: AESV: make ⭐ toggle bidirectional in visual attachment grid + context menu; keep existing ⭐⇒👁 and privacy→private clears ⭐; no UI/layout changes.
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

import SwiftUI
import CoreData
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers


// MARK: - Attachment Viewer Request (AESV)
// Atomic presentation payload for AttachmentViewerView.
// This is AESV-scoped and matches PRDV’s launch contract: visual (images+videos) vs audio-only.
private struct AttachmentViewerRequest: Identifiable {
    enum Mode {
        case visual
        case audio
    }

    let id = UUID()
    let mode: Mode
    let startIndex: Int

    let imageURLs: [URL]
    let videoURLs: [URL]
    let audioURLs: [URL]
    let viewerAttachmentIDs: [UUID]
}



struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Editing existing session or creating new
    var session: Session? = nil

    // Form state
    @State private var instruments: [Instrument] = []
    @State private var instrument: Instrument?
    @State private var timestamp: Date = Date()
    @State private var durationSeconds: Int = 0
    @State private var activity: SessionActivityType = .practice

    // Activity description (short detail) + defaulting logic
    @State private var activityDetail: String = ""
    @State private var lastAutoActivityDetail: String = ""     // tracks the last generated default
    @State private var userEditedActivityDetail: Bool = false  // breaks auto-sync once user types
    @State private var userHasEditedActivityDetail: Bool = false

    // User-local activities + selection
    @State private var userActivities: [UserActivity] = []
    /// String selector used by the wheel: "core:<raw>" or "custom:<name>"
    @State private var activityChoice: String = "core:0"
    /// If user picked a custom activity, hold its name separately (do NOT store in activityDetail)
    @State private var selectedCustomName: String = ""

    @State private var isPublic: Bool = true
    @State private var notes: String = ""
    @State private var areNotesPrivate_edit: Bool = false

    // Wheels
    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var showActivityPicker = false
    @State private var showInstrumentPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0

    // Attachments
    @State private var stagedAttachments: [StagedAttachment] = []
    @State private var selectedThumbnailID: UUID? = nil
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraDeniedAlert = false

    @State private var viewerRequest: AttachmentViewerRequest? = nil
    @State private var attachmentTitlesRefreshTick: Int = 0

    // UI stability (instruments empty-state)
    @State private var instrumentsGateArmed = false
    @State private var instrumentsReady = false

    // Track which staged attachments came from Core Data (existing) to prevent duplication on save
    @State private var existingAttachmentIDs: Set<UUID> = []

    // Map existing (Core Data) attachment IDs to their resolved on-disk URLs so the viewer can play audio/video without relying on staged bytes.
    @State private var existingAttachmentURLMap: [UUID: URL] = [:]

    // Primary Activity persisted ref
    @AppStorage("primaryActivityRef") private var primaryActivityRef: String = "core:0"

    // v7.9E — State circles (12-dot gradient, dark → light, drag select)
    private let stateDotsCount_edit: Int = 12

    @State private var selectedDotIndex_edit: Int? = nil
    @State private var hoverDotIndex_edit: Int? = nil        // transient during drag
    @State private var dragX_edit: CGFloat? = nil            // live finger x
    @State private var lastHapticDot_edit: Int? = nil        // per-dot haptic throttle

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
    @State private var privacyMap: [String: Bool] = [:]

    private func privacyKey(id: UUID?, url: URL?) -> String? {
        if let id { return "id://\(id.uuidString)" }
        if let url { return url.absoluteString }
        return nil
    }

    private func loadPrivacyMap() {
        privacyMap = (UserDefaults.standard.dictionary(forKey: AttachmentPrivacy.mapKey) as? [String: Bool]) ?? [:]
    }

    private func isPrivate(id: UUID?, url: URL?) -> Bool {
        if let key = privacyKey(id: id, url: url) {
            if let v = privacyMap[key] { return v }
            return AttachmentPrivacy.isPrivate(id: id, url: url)
        }
        return true
    }

    private func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        // Update local cache first for instant UI
        privacyMap[key] = value
        // Persist via centralized helper (also posts didChange notification)
        AttachmentPrivacy.setPrivate(id: id, url: url, value)
    }
    // ---- end privacy helpers ----

    // Persisted audio title overrides (existing store)
    private let persistedAudioTitlesKey = "persistedAudioTitles_v1"
    private func loadPersistedAudioTitles() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: persistedAudioTitlesKey) as? [String: String]) ?? [:]
    }

    // Persisted video title overrides (existing store)
    private let persistedVideoTitlesKey = "persistedVideoTitles_v1"
    private func loadPersistedVideoTitles() -> [String: String] {
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

    /// Apply/replace the FocusDotIndex line before saving
    private func applyFocusToNotesBeforeSave_edit() {
        // Notes must remain user-entered text only.
        // Focus is stored structurally (Session.effort / publish payload effort).
        stripFocusTokensFromNotes_edit()
    }

    init(session: Session? = nil) {
        self.session = session
        // Seed time-related fields on edit so they don’t flash empty
        if let s = session {
            if let ts = s.timestamp { _timestamp = State(initialValue: ts) }
            _durationSeconds = State(initialValue: Int(s.durationSeconds))
        }
    }

    private var isEdit: Bool { session != nil }
    private var hasNoInstruments: Bool { instruments.isEmpty }
    private var hasOneInstrument: Bool { instruments.count == 1 }
    private var hasMultipleInstruments: Bool { instruments.count > 1 }

    var body: some View {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {

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
VStack(alignment: .leading, spacing: Theme.Spacing.s) {
    Text("Instrument").sectionHeader()
    if hasMultipleInstruments {
        // Tappable row → wheel sheet
        Button {
            showInstrumentPicker = true
        } label: {
            HStack {
                Text(instrument?.name ?? "Select instrument…")
                    .font(Theme.Text.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Instrument")
        .accessibilityIdentifier("picker.instrument")
    } else {
        // Read-only row for single instrument (no chevron)
        HStack {
            Text(instrument?.name ?? "Instrument")
            Spacer()
        }
        .accessibilityLabel(instrument?.name ?? "Instrument")
    }
}
.cardSurface()
                }

                // Activity
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Activity").sectionHeader()
                    Button {
                        showActivityPicker = true
                    } label: {
                        let display = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? activity.label : selectedCustomName
                        HStack {
                            Text(display)
                                .font(Theme.Text.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Activity")
                    .accessibilityIdentifier("picker.activity")
                }
                .cardSurface()

                // Activity description (short detail)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Description").sectionHeader()
                    TextField("Activity description", text: $activityDetail, axis: .vertical)
                        .lineLimit(1...3)
                        .font(Theme.Text.body)
                        .onChange(of: activityDetail) { _, new in handleActivityDetailChange_v2(new) }
                }
                .cardSurface()

                // Start Time
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Start Time").sectionHeader()
                    Button {
                        tempDate = timestamp
                        showStartPicker = true
                    } label: {
                        HStack {
                            Text(formattedDate(timestamp))
                                .font(Theme.Text.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface()

                // Duration
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Duration").sectionHeader()
                    Button {
                        let hm = secondsToHM(durationSeconds)
                        tempHours = hm.0; tempMinutes = hm.1
                        showDurationPicker = true
                    } label: {
                        HStack {
                            Text(formattedDuration(durationSeconds))
                                .font(Theme.Text.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if durationSeconds == 0 {
                        Text("Duration must be greater than 0")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .cardSurface()

                // ---------- Visibility ----------
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Share with followers").sectionHeader()
                    Toggle("On", isOn: $isPublic)
                        .font(Theme.Text.body)
                }
                .cardSurface()

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
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .font(Theme.Text.body)
                            .frame(minHeight: 120)
                            .accessibilityLabel("Notes")
                    }
                }
                .cardSurface()

                // NEW — State card (read/write)
                stateStripCard_edit

                
                // Attachments grid
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Attachments").sectionHeader()
                    if !stagedAttachments.isEmpty {
                        let visuals = stagedAttachments.filter { $0.kind != .audio && $0.kind != .file }
                        let audioOnly = stagedAttachments.filter { $0.kind == .audio }

                        if !visuals.isEmpty {
                            let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                            LazyVGrid(columns: columns, spacing: 12) {
                                                            ForEach(visuals) { att in
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
                                                                                Image(systemName: "eye")
                                                                                    .font(.system(size: 16, weight: .semibold))
                                                                                    .padding(8)
                                                                                    .background(.ultraThinMaterial, in: Circle())
                                                                            }
                                                                            .opacity((priv || selectedThumbnailID == att.id) ? 0 : 1)
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
                                                                    // Visual gallery: images + videos (audio excluded)
                                                                    ensureSurrogateFilesExistForViewer_edit()

                                                                    let imageURLs: [URL] = visuals.compactMap { item in
                                                                        guard item.kind == .image else { return nil }
                                                                        return viewerResolvedURL_edit(for: item)
                                                                    }

                                                                    let videoURLs: [URL] = visuals.compactMap { item in
                                                                        guard item.kind == .video else { return nil }
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
                                                                        return imageIDs + videoIDs
                                                                    }()

                                                                    let startIndex: Int = {
                                                                        switch att.kind {
                                                                        case .image:
                                                                            let idx = visuals.filter { $0.kind == .image }.firstIndex(where: { $0.id == att.id }) ?? 0
                                                                            return idx
                                                                        case .video:
                                                                            let idx = visuals.filter { $0.kind == .video }.firstIndex(where: { $0.id == att.id }) ?? 0
                                                                            return imageURLs.count + idx
                                                                        default:
                                                                            return 0
                                                                        }
                                                                    }()

                                                                    viewerRequest = AttachmentViewerRequest(
                                                                        mode: .visual,
                                                                        startIndex: startIndex,
                                                                        imageURLs: imageURLs,
                                                                        videoURLs: videoURLs,
                                                                        audioURLs: [],
                                                                        viewerAttachmentIDs: orderedVisualIDs
                                                                    )
                                                                }
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
                                                guard let url = viewerAliasURLForAudio_edit(for: item) else { return nil }
                                                return (item.id, url)
                                            }
                                            let audioURLs: [URL] = audioItems.map { $0.1 }
                                            let orderedAudioIDs: [UUID] = audioItems.map { $0.0 }
                                            let startIndex = audioItems.firstIndex(where: { $0.0 == att.id }) ?? 0

                                            viewerRequest = AttachmentViewerRequest(
                                                mode: .audio,
                                                startIndex: startIndex,
                                                imageURLs: [],
                                                videoURLs: [],
                                                audioURLs: audioURLs,
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
                                                selectedThumbnailID = att.id
                                            } label: {
                                                Image(systemName: selectedThumbnailID == att.id ? "star.fill" : "star")
                                                    .font(.system(size: 16, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Set as thumbnail")

                                            let privURL = url
                                            let isPriv = isPrivate(id: att.id, url: privURL)
                                            Button {
                                                let current = isPrivate(id: att.id, url: privURL)
                                                setPrivate(id: att.id, url: privURL, !current)
                                            } label: {
                                                // Quiet Mode: only show when included
                                                Image(systemName: "eye")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .opacity(isPriv ? 0 : 1)
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
                    .padding(.vertical, 2)
                }
                .cardSurface(padding: Theme.Spacing.m)

            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(isEdit ? "Edit Session" : "New Session")
                    .font(Theme.Text.pageTitle)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(Theme.Text.body)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { save() }) {
                    Text("Save")
                        .font(Theme.Text.body)
                }
                .disabled(durationSeconds == 0 || instrument == nil)
                .accessibilityLabel("Save session")
                .accessibilityIdentifier("button.saveSession")
            }
        }
        .sheet(isPresented: $showInstrumentPicker) { instrumentPicker }
        .sheet(isPresented: $showActivityPicker) { activityPickerPinned }
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
        .fullScreenCover(item: $viewerRequest) { req in
            let imageURLs: [URL] = (req.mode == .visual) ? req.imageURLs : []
            let videoURLs: [URL] = (req.mode == .visual) ? req.videoURLs : []
            let audioURLs: [URL] = (req.mode == .audio) ? req.audioURLs : []
            let combined = imageURLs + videoURLs + audioURLs
            let startIndex = min(max(req.startIndex, 0), max(combined.count - 1, 0))

            let viewerAttachmentIDs: [UUID] = req.viewerAttachmentIDs

            let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
            let persistedTitles = loadPersistedAudioTitles()
            let audioTitles: [String] = audioURLs.map { u in
                let stem = u.deletingPathExtension().lastPathComponent
                // Prefer persisted override; then staged map; finally fall back to stem
                let persisted = (persistedTitles[stem] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !persisted.isEmpty { return persisted }
                let staged = (namesDict[stem] ?? stem).trimmingCharacters(in: .whitespacesAndNewlines)
                return staged.isEmpty ? stem : staged
            }

attachmentViewer_AESV(imageURLs: imageURLs, startIndex: startIndex, videoURLs: videoURLs, audioURLs: audioURLs, audioTitles: audioTitles, req: req)
        }
        .task { hydrate() } // unified first-appearance init
        .onAppear {
            preselectFocusFromNotesIfNeeded_edit()
            syncActivityChoiceFromState()
            loadPrivacyMap()
            // Ensure token is hidden in Notes whenever view appears
            stripFocusTokensFromNotes_edit()
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

    // Instrument picker sheet (wheel style)
private var instrumentPicker: some View {
    NavigationStack {
        VStack {
            Picker("Instrument", selection: $instrument) {
                Text("Select instrument…").tag(nil as Instrument?)
                ForEach(instruments, id: \.self) { inst in
                    Text(inst.name ?? "").tag(inst as Instrument?)
                }
            }
            .pickerStyle(.wheel)
        }
        .navigationTitle("Instrument")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showInstrumentPicker = false }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showInstrumentPicker = false }
            }
        }
    }
}

// MARK: - Subviews (pinned activity wheel + pickers)

    private var activityPickerPinned: some View {
        NavigationStack {
            VStack {
                let choices = activityChoicesPinned()
                Picker("", selection: $activityChoice) {
                    ForEach(choices, id: \.self) { choice in
                        Text(activityDisplayName(for: choice)).tag(choice)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                Spacer()
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showActivityPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyActivityChoice()
                        maybeUpdateActivityDetailFromDefaults_v2()
                        showActivityPicker = false
                        // After changing activity/custom, update default description if appropriate.
                        maybeUpdateActivityDetailFromDefaults()
                    }
                }
            }
            .onAppear { syncActivityChoiceFromState() }
        }
    }

    private var startPicker: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel).labelsHidden()
                Spacer()
            }
            .navigationTitle("Start Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showStartPicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { timestamp = tempDate; showStartPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var durationPicker: some View {
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

    // NEW — State card (read/write)
    @ViewBuilder
    private var stateStripCard_edit: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Focus").sectionHeader()

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let spacing: CGFloat = 8
                let count = stateDotsCount_edit
                let diameter = max(14, min(32, (totalWidth - spacing * CGFloat(count - 1)) / CGFloat(count)))
                let step = diameter + spacing

                // Drag gesture: per-dot haptic + snap to zone; faster mapping
                let drag = DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Clamp within the actual occupied width of the dot strip so extremes are reachable
                        let totalWidthUsed = diameter * CGFloat(count) + spacing * CGFloat(count - 1)
                        let x = max(0, min(value.location.x, totalWidthUsed))

                        dragX_edit = x

                        // Map x to nearest dot center across [0, totalWidthUsed]
                        let projected = (x / max(1, totalWidthUsed)) * CGFloat(count - 1)
                        let idx = Int(round(projected))
                        let clamped = max(0, min(count - 1, idx))

                        hoverDotIndex_edit = clamped
                        selectedDotIndex_edit = clamped  // single source of truth

                        // Per-dot haptic
                        if lastHapticDot_edit != clamped {
                            lastHapticDot_edit = clamped
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                        }
                    }
                    .onEnded { _ in
                        dragX_edit = nil
                        hoverDotIndex_edit = nil
                    }

                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        let isRinged = (i == selectedDotIndex_edit)

                        // Proximity bloom under finger
                        let hoverScale: CGFloat = {
                            guard let x = dragX_edit else { return 1.0 }
                            let cx = CGFloat(i) * step + diameter * 0.5
                            let distance = abs(cx - x)
                            let proximity = max(0, 1 - (distance / (step * 1.5)))
                            return 1.0 + (0.24 * proximity) // up to +24%
                        }()

                        // Persistent emphasis for selected zone center
                        let selectedBase: CGFloat = isRinged ? 1.18 : 1.0
                        let finalScale = selectedBase * hoverScale

                        Circle()
                            // Adaptive fill: black in light mode, white in dark mode, using centralized opacity ramp
                            .fill(FocusDotStyle.fillColor(index: i, total: count, colorScheme: colorScheme))
                            // Hairline outline on every dot for guaranteed contrast
                            .overlay(
                                Circle().stroke(FocusDotStyle.hairlineColor, lineWidth: FocusDotStyle.hairlineWidth)
                            )
                            // Adaptive ring for the selected index
                            .overlay(
                                Group {
                                    if isRinged {
                                        Circle().stroke(
                                            FocusDotStyle.ringColor(for: colorScheme),
                                            lineWidth: FocusDotStyle.ringWidth
                                        )
                                    }
                                }
                            )
                            .frame(width: diameter, height: diameter)
                            .scaleEffect(finalScale)
                            .animation(.easeOut(duration: 0.06), value: finalScale)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDotIndex_edit = (selectedDotIndex_edit == i) ? nil : i
                                #if canImport(UIKit)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                            }
                            .accessibilityLabel({
                                let bucket: String
                                switch i / 3 {
                                case 0: bucket = "Searching"
                                case 1: bucket = "Working"
                                case 2: bucket = "Flowing"
                                default: bucket = "Breakthrough"
                                }
                                return isRinged ? "\(bucket), selected" : bucket
                            }())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gesture(drag)
            }
            .frame(height: 48)    // half-height feel
            .padding(.vertical, 2)
        }
        .cardSurface()
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
        } else {
            // New mode defaults
            timestamp = Date()
            durationSeconds = 0

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

    // MARK: - Actions

    private func save() {
        let s = session ?? Session(context: viewContext)
        if (s.value(forKey: "id") as? UUID) == nil {
            s.setValue(UUID(), forKey: "id")
        }
        s.instrument = instrument

        // Title = activityDetail (trimmed) or fallback
        let trimmedDetail = activityDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        s.title = trimmedDetail.isEmpty ? defaultTitle(for: instrument, activity: activity) : trimmedDetail

        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = isPublic
        // Persist focus structurally (do NOT encode into notes)
        if s.entity.attributesByName.keys.contains("effort") {
            if let idx = selectedDotIndex_edit {
                s.setValue(Int16(idx), forKey: "effort")
            } else {
                // Treat nil as "unset" (default effort = 5)
                s.setValue(Int16(5), forKey: "effort")
            }
        }

        if selectedDotIndex_edit != nil {
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
        s.setValue(activity.rawValue, forKey: "activityType")
        s.setValue(trimmedDetail, forKey: "activityDetail")

        // If a custom name is selected, stamp userActivityLabel; otherwise clear any previous custom label
        let trimmedCustom = selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            s.setValue(trimmedCustom, forKey: "userActivityLabel")
        } else {
            s.setValue(nil, forKey: "userActivityLabel")
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

        // Commit staged attachments (skip existing to avoid duplicates; update thumbnail flags)
        commitStagedAttachments(to: s, ctx: viewContext)

        do {
            try viewContext.save()

            // ===== v7.12A • Publish hook after successful save =====
            guard let sid = s.id else {
                print("Publish skipped: missing Session.id")
                return
            }

            let focusValue: Int? = selectedDotIndex_edit

            let activityTypeString = trimmedCustom.isEmpty ? activity.label : trimmedCustom
            let instLabel =
                (s.userInstrumentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? s.instrument?.name

            let payload = SessionSyncQueue.PostPublishPayload(
                id: sid,
                sessionID: sid,
                sessionTimestamp: timestamp,
                title: s.title,
                durationSeconds: Int(durationSeconds),
                activityType: activityTypeString,
                activityDetail: trimmedDetail,
                instrumentLabel: instLabel,
                mood: nil,
                effort: focusValue,
                isPublic: isPublic
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
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { dismiss() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dismiss() }
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

    private func activityDisplayName(for choice: String) -> String {
        if choice.hasPrefix("core:") {
            if let raw = Int(choice.split(separator: ":").last ?? "0"),
               let t = SessionActivityType(rawValue: Int16(raw)) {
                return t.label
            }
            return SessionActivityType.practice.label
        } else if choice.hasPrefix("custom:") {
            return String(choice.dropFirst("custom:".count))
        }
        return SessionActivityType.practice.label
    }

    private func activityChoicesPinned() -> [String] {
        // Core list
        let core: [String] = SessionActivityType.allCases.map { "core:\($0.rawValue)" }
        // Custom list
        let customs: [String] = userActivities.compactMap { ua in
            let n = (ua.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "custom:\(n)"
        }

        // Normalize primary
        let primary = normalizedPrimary()
        var result: [String] = []

        if let p = primary { result.append(p) }
        for c in core where !result.contains(c) { result.append(c) }
        for cu in customs where !result.contains(cu) { result.append(cu) }
        return result
    }

    private func normalizedPrimary() -> String? {
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

    private func applyActivityChoice() {
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

    private func syncActivityChoiceFromState() {
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

    private func maybeUpdateActivityDetailFromDefaults_v2() {
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
    private func maybeUpdateActivityDetailFromDefaults() {
        let newDefault = editorDefaultDescription(timestamp: timestamp, activity: activity, customName: selectedCustomName)
        if activityDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activityDetail == lastAutoActivityDetail {
            lastAutoActivityDetail = newDefault
            activityDetail = newDefault
            userEditedActivityDetail = false
        }
    }

    // MARK: - Attachments (preload, stage & commit)

    /// Preload existing Core Data attachments so they appear in the grid during Edit (no duplication on save).
    private func preloadExistingAttachments() {
        guard let s = session else { return }
        // Try to fetch via relationship; fall back to fetch request if needed.
        var existing: [Attachment] = []
        if let set = s.value(forKey: "attachments") as? Set<Attachment> {
            existing = Array(set)
        } else {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", s.objectID)
            existing = (try? viewContext.fetch(req)) ?? []
        }

        // Sort by createdAt if available for stable order
        existing.sort {
            let a = ($0.value(forKey: "createdAt") as? Date) ?? .distantPast
            let b = ($1.value(forKey: "createdAt") as? Date) ?? .distantPast
            return a < b
        }

        // Map Core Data attachments into staged rows (image data for previews; icons for others).
        for a in existing {
            let kindStr = (a.value(forKey: "kind") as? String) ?? "file"
            let kind = AttachmentKind(rawValue: kindStr) ?? .file
            let id = (a.value(forKey: "id") as? UUID) ?? UUID()

            if let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                if let url = resolveStoredFileURL(at: path) {
                    existingAttachmentURLMap[id] = url
                }
            }


            // For audio attachments, populate the temporary names map used for captions
            if kind == .audio {
                if let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                    let filename = (path as NSString).lastPathComponent
                    let stem = (filename as NSString).deletingPathExtension
                    if !stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let key = "stagedAudioNames_temp"
                        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
                        dict[id.uuidString] = stem
                        UserDefaults.standard.set(dict, forKey: key)
                    }
                }
            }

            var data = Data()
            if kind == .image, let path = a.value(forKey: "fileURL") as? String, !path.isEmpty {
                if let d = loadImageData(at: path) { data = d }
            }

            // Stage item and remember it's existing to avoid duplication on save.
            let staged = StagedAttachment(id: id, data: data, kind: kind)
            stagedAttachments.append(staged)
            existingAttachmentIDs.insert(id)

            if (a.value(forKey: "isThumbnail") as? Bool) == true {
                // Do not surface an invalid thumbnail if the attachment is private.
                let storedPath = (a.value(forKey: "fileURL") as? String) ?? ""
                let resolvedURL = resolveStoredFileURL(at: storedPath)
                if !isPrivate(id: id, url: resolvedURL) {
                    selectedThumbnailID = id
                }
            }
        }
    }

    
    /// Resolves a stored Attachment.fileURL string into a valid on-disk file URL.
    /// Mirrors the resolution strategy used by loadImageData(at:), but returns URL without loading bytes.
    private func resolveStoredFileURL(at pathOrURLString: String) -> URL? {
        let trimmed = pathOrURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fm = FileManager.default

        // Case A: absolute filesystem path
        if trimmed.hasPrefix("/") {
            if fm.fileExists(atPath: trimmed) { return URL(fileURLWithPath: trimmed) }
            if let filename = URL(fileURLWithPath: trimmed).pathComponents.last, !filename.isEmpty {
                let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
                if let hit = docs?.appendingPathComponent(filename), fm.fileExists(atPath: hit.path) { return hit }
            }
        }

        // Case B: URL string (e.g., "file:///...")
        if let url = URL(string: trimmed), url.isFileURL, fm.fileExists(atPath: url.path) {
            return url
        }

        // Case C: relative path previously stored (resolve against Documents directory)
        if !trimmed.contains(":"), !trimmed.hasPrefix("/") {
            if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let hit = docs.appendingPathComponent(trimmed)
                if fm.fileExists(atPath: hit.path) { return hit }
            }
        }

        return nil
    }

/// Attempts to read image bytes from: absolute path → file:// URL → relative path in Documents directory.
    private func loadImageData(at pathOrURLString: String) -> Data? {
        let trimmed = pathOrURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        func loadAtAbsolutePath(_ abs: String) -> Data? {
            if FileManager.default.fileExists(atPath: abs) {
                if let ui = UIImage(contentsOfFile: abs) {
                    if let jpg = ui.jpegData(compressionQuality: 0.85) { return jpg }
                }
                if let raw = try? Data(contentsOf: URL(fileURLWithPath: abs)) { return raw }
            }
            return nil
        }

        // Case A: absolute filesystem path
        if trimmed.hasPrefix("/") {
            if let d = loadAtAbsolutePath(trimmed) { return d }
            // Fallback: treat as stale absolute path; try lastPathComponent in Documents
            if let filename = URL(fileURLWithPath: trimmed).pathComponents.last, !filename.isEmpty {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                if let hit = docs?.appendingPathComponent(filename), FileManager.default.fileExists(atPath: hit.path) {
                    if let ui = UIImage(contentsOfFile: hit.path) {
                        if let jpg = ui.jpegData(compressionQuality: 0.85) { return jpg }
                    }
                    if let raw = try? Data(contentsOf: hit) { return raw }
                }
            }
        }

        // Case B: URL string (e.g., "file:///...")
        if let url = URL(string: trimmed), url.isFileURL {
            if let d = loadAtAbsolutePath(url.path) { return d }
            if let raw = try? Data(contentsOf: url) { return raw }
        }

        // Case C: relative path previously stored (resolve against Documents directory)
        if !trimmed.isEmpty, !trimmed.contains(":"), !trimmed.hasPrefix("/") {
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let candidate = docs.appendingPathComponent(trimmed).path
                if let d = loadAtAbsolutePath(candidate) { return d }
            }
        }

        return nil
    }

    private func stageData(_ data: Data, kind: AttachmentKind) {
        let id = UUID()
        // For staged videos (e.g. imported from the photo library), write a temporary
        // surrogate file so that VideoPosterView can resolve a real URL and generate
        // a poster frame while we are still in edit mode. This uses the same
        // extension mapping as the persisted attachments.
        if kind == .video {
            let ext: String = (kind == .image ? "jpg" : kind == .audio ? "m4a" : kind == .video ? "mov" : "dat")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString)
                .appendingPathExtension(ext)
            try? data.write(to: tempURL, options: .atomic)
        }
        stagedAttachments.append(StagedAttachment(id: id, data: data, kind: kind))
        // No auto-thumbnail: thumbnail is set only via explicit user intent (⭐).
    }

    private func removeStagedAttachment(_ a: StagedAttachment) {
        stagedAttachments.removeAll { $0.id == a.id }
        existingAttachmentIDs.remove(a.id)
        if selectedThumbnailID == a.id {
            // No auto-reassign: removing the thumbnail clears it.
            selectedThumbnailID = nil
        }
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
                } catch { print("File import failed for \(url): \(error)") }
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
    // --- PATCH 8G-AESV: migrate staged privacy → persisted attachment keys ---
    // SEARCH-ANCHOR: private func migratePrivacy_AESV(
    private func migratePrivacy_AESV(
        fromStagedID stagedID: UUID,
        stagedURL: URL?,
        toNewID newID: UUID,
        newURL: URL?
    ) {
        // Read staged privacy (default=true → private unless explicitly included)
        let stagedIsPrivate = AttachmentPrivacy.isPrivate(id: stagedID, url: stagedURL)

        // Write onto persisted attachment keys so backend publish can see it
        if newID != stagedID {
            AttachmentPrivacy.setPrivate(id: newID, url: newURL, stagedIsPrivate)
        }

        // Keep AESV local cache coherent
        privacyMap = AttachmentPrivacy.currentMap()
    }
    // --- end PATCH 8G-AESV ---

    /// Adds only newly staged attachments (not those that originated from Core Data) and updates thumbnail flags for all.
    private func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) {
        // Persist renamed audio stems from the viewer (if any)
        let audioNamesDict: [String: String] = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]

        // Determine chosen thumbnail (if any)
        let imageIDs = stagedAttachments.filter { $0.kind == .image }.map { $0.id }
        var chosenThumbID = selectedThumbnailID
        if chosenThumbID == nil, imageIDs.count == 1 { chosenThumbID = imageIDs.first }

        // Track rollback closures for files written during this commit attempt
        var rollbacks: [() -> Void] = []
        var createdAttachments: [Attachment] = []

        // 1) Add ONLY newly staged attachments (skip those that were preloaded from Core Data)
        for att in stagedAttachments where existingAttachmentIDs.contains(att.id) == false {
            do {
                let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
                let suggestedName: String = {
                    switch att.kind {
                    case .audio:
                        // Use renamed audio stem from UserDefaults if provided, otherwise fallback to UUID.
                        let raw = audioNamesDict[att.id.uuidString] ?? ""
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? att.id.uuidString : trimmed
                    case .image, .video, .file:
                        // Keep existing behavior for non-audio kinds: use UUID stem
                        return att.id.uuidString
                    }
                }()
                let result = try AttachmentStore.saveDataWithRollback(att.data, suggestedName: suggestedName, ext: ext)
                rollbacks.append(result.rollback)
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                let created = try AttachmentStore.addAttachment(
                    kind: att.kind,
                    filePath: result.path,
                    to: session,
                    isThumbnail: isThumb,
                    ctx: ctx
                )
                createdAttachments.append(created)

                // --- PATCH 8G-AESV: migrate privacy from staged → persisted ---
                let stagedURL = surrogateURL(for: att)
                let persistedURL = resolveStoredFileURL(at: result.path)
                if let newID = created.value(forKey: "id") as? UUID {
                    migratePrivacy_AESV(
                        fromStagedID: att.id,
                        stagedURL: stagedURL,
                        toNewID: newID,
                        newURL: persistedURL
                    )
                }
                // --- end PATCH ---

            } catch {
                // Roll back any files written so far and discard created (unsaved) attachments
                for rb in rollbacks { rb() }
                rollbacks.removeAll()
                for a in createdAttachments { ctx.delete(a) }
                createdAttachments.removeAll()
                print("Attachment commit failed: ", error)
                break
            }
        }

        // 2) Update thumbnail flags across ALL existing attachments to reflect selection
        do {
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.predicate = NSPredicate(format: "session == %@", session.objectID)
            let existing = try ctx.fetch(req)
            for a in existing {
                let id = (a.value(forKey: "id") as? UUID)
                let isThumb = (id != nil) && (id == chosenThumbID)
                a.setValue(isThumb, forKey: "isThumbnail")
            }
        } catch {
            print("Failed to update thumbnail flags: ", error)
        }

        // Clear the staging area after successful commit creation (actual persistence depends on context.save())
        UserDefaults.standard.removeObject(forKey: "stagedAudioNames_temp")
        stagedAttachments.removeAll()
        existingAttachmentIDs.removeAll()
    }

    // Added helpers for attachment viewer integration:

    private func stagedIndexForAttachment_edit(_ target: StagedAttachment) -> Int {
        let images = stagedAttachments.filter { $0.kind == .image }
        let videos = stagedAttachments.filter { $0.kind == .video }
        let audios = stagedAttachments.filter { $0.kind == .audio }
        let combined: [StagedAttachment] = images + videos + audios
        return combined.firstIndex(where: { $0.id == target.id }) ?? -1
    }

    private func ensureSurrogateFilesExistForViewer_edit() {
        for att in stagedAttachments {
            // Only create a surrogate when we don't already have a real on-disk URL (existing attachments).
            if existingAttachmentURLMap[att.id] == nil {
                _ = guaranteedSurrogateURL_edit(for: att)
            }
        }
    }

    private func viewerURLArrays_edit() -> (images: [URL], videos: [URL], audios: [URL]) {
        let imageURLs: [URL] = stagedAttachments.filter { $0.kind == .image }.compactMap { viewerResolvedURL_edit(for: $0) }
        let videoURLs: [URL] = stagedAttachments.filter { $0.kind == .video }.compactMap { viewerResolvedURL_edit(for: $0) }
        let audioURLs: [URL] = stagedAttachments.filter { $0.kind == .audio }.compactMap { viewerResolvedURL_edit(for: $0) }
        return (imageURLs, videoURLs, audioURLs)
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

    private func formatClipDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func audioDurationText_edit(for att: StagedAttachment) -> String? {
        guard let url = surrogateURL(for: att) else { return nil }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? att.data.write(to: url, options: .atomic)
        }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return formatClipDuration(seconds)
    }


    private func ensureCameraAuthorized(onAuthorized: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            onAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? onAuthorized() : { self.showCameraDeniedAlert = true }() }
            }
        default:
            self.showCameraDeniedAlert = true
        }
    }
    
    @ViewBuilder
    private func AttachmentTileContent(att: StagedAttachment) -> some View {
        switch att.kind {
        case .image:
            if let ui = UIImage(data: att.data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary)
            }
        case .audio:
            VStack(spacing: 6) {
                Image(systemName: "waveform").imageScale(.large).foregroundStyle(.secondary)
                // Use the same temporary names map seeded during review/timer if present
                let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                let persistedTitles = loadPersistedAudioTitles()
                let override = (persistedTitles[att.id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let staged = (namesDict[att.id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let caption = !override.isEmpty ? override : staged
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                }
            }
        case .video:
            ZStack {
                VideoPosterView(url: surrogateURL(for: att))
                    .allowsHitTesting(false)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        case .file:
            Image(systemName: "doc").imageScale(.large).foregroundStyle(.secondary)
        }
    }

    private func surrogateURL(for att: StagedAttachment) -> URL? {
        let ext: String = (att.kind == .image ? "jpg" : att.kind == .audio ? "m4a" : att.kind == .video ? "mov" : "dat")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension(ext)
    }


    // Step 6A — Viewer population hardening:
    // Ensure a real file exists at the surrogate URL before passing it into AttachmentViewerView.
    
    
    // Step 6D — Viewer alias URL for AESV audio rename contract:
    // AttachmentViewerView maps URL → UUID via URL stem. Existing persisted audio file names may not be UUIDs,
    // so we provide a stable temp alias named <att.id>.m4a that points to the real on-disk file.
    // This is INTERNAL ONLY and must not affect displayed titles.
    private func viewerAliasURLForAudio_edit(for att: StagedAttachment) -> URL? {
        guard att.kind == .audio else { return viewerResolvedURL_edit(for: att) }
        guard let source = viewerResolvedURL_edit(for: att) else { return nil }

        let fm = FileManager.default
        let alias = FileManager.default.temporaryDirectory
            .appendingPathComponent(att.id.uuidString)
            .appendingPathExtension("m4a")

        // If alias already exists and is non-empty, reuse it.
        if fm.fileExists(atPath: alias.path) {
            if let attrs = try? fm.attributesOfItem(atPath: alias.path),
               let n = attrs[.size] as? NSNumber,
               n.intValue > 0 {
                return alias
            }
            try? fm.removeItem(at: alias)
        }

        // If the source is already the alias, we're done.
        if source.standardizedFileURL == alias.standardizedFileURL { return alias }

        // Best-effort copy to the alias path so the viewer URL stem remains the staged UUID.
        do {
            try fm.copyItem(at: source, to: alias)
            return alias
        } catch {
            // Fallback: allow playback from the real URL, but rename mapping may not work.
            return source
        }
    }

// Step 6C — Viewer URL resolution for AESV edit mode:
    // Prefer the persisted on-disk file URL for existing attachments; fall back to a guaranteed surrogate for staged bytes.
    private func viewerResolvedURL_edit(for att: StagedAttachment) -> URL? {
        if let existing = existingAttachmentURLMap[att.id], FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        return guaranteedSurrogateURL_edit(for: att)
    }

private func guaranteedSurrogateURL_edit(for att: StagedAttachment) -> URL? {
        guard let url = surrogateURL(for: att) else { return nil }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            switch att.kind {
            case .image, .video, .audio:
                do { try att.data.write(to: url, options: .atomic) } catch { return nil }
            case .file:
                return nil
            }
        }
        return fm.fileExists(atPath: url.path) ? url : nil
    }


    // CHANGE-ID: 20251229_175900-canShareAESV-typecheckHelper
    // SCOPE: Policy — disable AttachmentViewer share when launched from AddEditSessionView (AESV) by passing canShare: false.
    @ViewBuilder
    private func attachmentViewer_AESV(
        imageURLs: [URL],
        startIndex: Int,
        videoURLs: [URL],
        audioURLs: [URL],
        audioTitles: [String],
        req: AttachmentViewerRequest
    ) -> some View {

        AttachmentViewerView(
                                    imageURLs: imageURLs,
                                    startIndex: startIndex,
                                    themeBackground: Color(.systemBackground),
                                    videoURLs: videoURLs,
                                    audioURLs: audioURLs,
                                    audioTitles: audioTitles,
                                    onDelete: { url in
                                        // Map by staged id from surrogate URL stem
                                        let stem = url.deletingPathExtension().lastPathComponent
                                        if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
                                            let removed = stagedAttachments.remove(at: idx)
                                            existingAttachmentIDs.remove(removed.id)
                                            if selectedThumbnailID == removed.id {
                                                // No auto-reassign: removing the thumbnail clears it.
                                                selectedThumbnailID = nil
                                            }
                                        }
                                    },
                                    titleForURL: { url, kind in
                                        let _ = attachmentTitlesRefreshTick
                                        let stem = url.deletingPathExtension().lastPathComponent
                                        switch kind {
                                        case .audio:
                                            let namesDict = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                                            let persistedTitles = loadPersistedAudioTitles()
                                            if let persisted = persistedTitles[stem] {
                                                let t = persisted.trimmingCharacters(in: .whitespacesAndNewlines)
                                                return t.isEmpty ? nil : t
                                            }
                                            if let raw = namesDict[stem] {
                                                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                                return t.isEmpty ? nil : t
                                            }
                                            return nil
                                        case .video:
                                            let persistedVideoTitles = loadPersistedVideoTitles()
                                            // Determine the index of this URL within the viewer's video section
                                            // The AttachmentViewerView provides (url, kind) but not index directly; infer index within the combined sequence we passed.
                                            // We built `req.viewerAttachmentIDs` to match the order of (imageURLs + videoURLs + audioURLs).
                                            let indexInCombined: Int? = {
                                                let all = imageURLs + videoURLs + audioURLs
                                                return all.firstIndex(where: { $0 == url })
                                            }()
                                            guard let idx = indexInCombined, idx >= 0, idx < req.viewerAttachmentIDs.count else { return nil }
                                            let attID = req.viewerAttachmentIDs[idx]
                                            
                                            if existingAttachmentIDs.contains(attID) {
                                                if let persisted = persistedVideoTitles[attID.uuidString] {
                                                    let t = persisted.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    return t.isEmpty ? nil : t
                                                }
                                                return nil
                                            } else {
                                                let videoDict = (UserDefaults.standard.dictionary(forKey: "stagedVideoTitles_temp") as? [String: String]) ?? [:]
                                                if let raw = videoDict[attID.uuidString] {
                                                    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    return t.isEmpty ? nil : t
                                                }
                                                return nil
                                            }
                                        case .image, .file:
                                            return nil
                                        }
                                    }, onRename: { url, newTitle, kind in
                                        let stem = url.deletingPathExtension().lastPathComponent
                                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                        switch kind {
                                        case .audio:
                                            // Resolve attachment identity by viewer index → ID, then write to staged/persisted stores.
                                            // This avoids relying on URL stem being a UUID (it often isn't once filenames are user-named).
                                            let indexInCombined: Int? = {
                                                let all = imageURLs + videoURLs + audioURLs
                                                return all.firstIndex(where: { $0 == url })
                                            }()
                                            let ids = req.viewerAttachmentIDs
                                            guard let idx = indexInCombined, idx >= 0, idx < ids.count else { return }
                                            let attID = ids[idx]

                                            // Trim user input
                                            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

                                            // Always keep staged map in sync (used for unsaved items and local viewer titles)
                                            var staged = (UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp") as? [String: String]) ?? [:]
                                            if trimmed.isEmpty { staged.removeValue(forKey: attID.uuidString) }
                                            else { staged[attID.uuidString] = trimmed }
                                            UserDefaults.standard.set(staged, forKey: "stagedAudioNames_temp")

                                            // For existing attachments, also persist under final attachment UUID so publish can round-trip display_name
                                            if existingAttachmentIDs.contains(attID) {
                                                var persisted = (UserDefaults.standard.dictionary(forKey: "persistedAudioTitles_v1") as? [String: String]) ?? [:]
                                                if trimmed.isEmpty { persisted.removeValue(forKey: attID.uuidString) }
                                                else { persisted[attID.uuidString] = trimmed }
                                                UserDefaults.standard.set(persisted, forKey: "persistedAudioTitles_v1")
                                            }

                                            attachmentTitlesRefreshTick &+= 1
                                        case .video:
                                            // Resolve attachment identity by viewer index → ID, then route to persisted or staged store only.
                                            let indexInCombined: Int? = {
                                                let all = imageURLs + videoURLs + audioURLs
                                                return all.firstIndex(where: { $0 == url })
                                            }()
                                            let ids = req.viewerAttachmentIDs
                                            if let idx = indexInCombined, idx >= 0, idx < ids.count {
                                                let attID = ids[idx]
                                                if existingAttachmentIDs.contains(attID) {
                                                    // Persisted: write/remove only in persistedVideoTitles_v1
                                                    var persisted = (UserDefaults.standard.dictionary(forKey: "persistedVideoTitles_v1") as? [String: String]) ?? [:]
                                                    if trimmed.isEmpty { persisted.removeValue(forKey: attID.uuidString) }
                                                    else { persisted[attID.uuidString] = trimmed }
                                                    UserDefaults.standard.set(persisted, forKey: "persistedVideoTitles_v1")
                                                    attachmentTitlesRefreshTick &+= 1
                                                } else {
                                                    // Staged (unsaved): write/remove only in stagedVideoTitles_temp
                                                    var videoDict = (UserDefaults.standard.dictionary(forKey: "stagedVideoTitles_temp") as? [String: String]) ?? [:]
                                                    if trimmed.isEmpty { videoDict.removeValue(forKey: attID.uuidString) }
                                                    else { videoDict[attID.uuidString] = trimmed }
                                                    UserDefaults.standard.set(videoDict, forKey: "stagedVideoTitles_temp")
                                                    attachmentTitlesRefreshTick &+= 1
                                                }
                                            }
                                            return
                                        case .image, .file:
                                            return
                                        }
                                    },
                                    onFavourite: { url in
                                        // Resolve attachment identity by viewer index first, fallback to UUID-from-stem
                                        let all = imageURLs + videoURLs + audioURLs
                                        let attID: UUID? = {
                                            if let idx = all.firstIndex(where: { $0 == url }),
                                               idx >= 0,
                                               idx < req.viewerAttachmentIDs.count {
                                                return req.viewerAttachmentIDs[idx]
                                            }
                                            let stem = url.deletingPathExtension().lastPathComponent
                                            return UUID(uuidString: stem)
                                        }()
                                        guard let id = attID else { return }
                                        if let att = stagedAttachments.first(where: { $0.id == id }) {
                                            selectedThumbnailID = att.id
                                        }
                                    },
                                    isFavourite: { url in
                                        let all = imageURLs + videoURLs + audioURLs
                                        let attID: UUID? = {
                                            if let idx = all.firstIndex(where: { $0 == url }),
                                               idx >= 0,
                                               idx < req.viewerAttachmentIDs.count {
                                                return req.viewerAttachmentIDs[idx]
                                            }
                                            let stem = url.deletingPathExtension().lastPathComponent
                                            return UUID(uuidString: stem)
                                        }()
                                        guard let id = attID else { return false }
                                        guard stagedAttachments.contains(where: { $0.id == id }) else { return false }
                                        return selectedThumbnailID == id
                                    },
                                    onTogglePrivacy: { url in
    // Resolve attachment identity by viewer index first (matches imageURLs+videoURLs+audioURLs),
    // falling back to UUID-from-stem when possible.
    let attID: UUID? = {
        let all = imageURLs + videoURLs + audioURLs
        if let idx = all.firstIndex(where: { $0 == url }),
           idx >= 0,
           idx < req.viewerAttachmentIDs.count {
            return req.viewerAttachmentIDs[idx]
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem)
    }()
    guard let id = attID else { return }
    let priv = isPrivate(id: id, url: url)
    let newPriv = !priv
    if newPriv, selectedThumbnailID == id {
        // Making thumbnail private clears ⭐.
        selectedThumbnailID = nil
    }
    setPrivate(id: id, url: url, newPriv)
},
isPrivate: { url in
    let attID: UUID? = {
        let all = imageURLs + videoURLs + audioURLs
        if let idx = all.firstIndex(where: { $0 == url }),
           idx >= 0,
           idx < req.viewerAttachmentIDs.count {
            return req.viewerAttachmentIDs[idx]
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem)
    }()
    // Default is private when identity cannot be resolved.
    guard let id = attID else { return true }
    return isPrivate(id: id, url: url)
},

                                    onReplaceAttachment: { originalURL, newURL, kind in
                                        // Replace should preserve attachment identity.
                                        // AttachmentViewerView has already written the replacement file to disk and passes
                                        // the final on-disk URL here as newURL.
                                        if let (attID, _) = existingAttachmentURLMap.first(where: { $0.value.standardizedFileURL == originalURL.standardizedFileURL }) {
                                            existingAttachmentURLMap[attID] = newURL
        
                                            // Persistence deferred to save() to avoid SessionDetailView dismissal.
                                            /*
                                            // Persist the new file path to Core Data so future loads resolve correctly.
                                            let req = NSFetchRequest<Attachment>(entityName: "Attachment")
                                            req.predicate = NSPredicate(format: "id == %@", attID as CVarArg)
                                            req.fetchLimit = 1
                                            if let hit = try? viewContext.fetch(req).first {
                                                hit.fileURL = newURL.path
                                                viewContext.processPendingChanges()
                                            }
        
                                            #if canImport(UIKit)
                                            if kind == .video {
                                                _ = AttachmentStore.generateVideoPoster(url: newURL)
                                            }
                                            #endif
                                            */
                                        } else {
                                            // Fallback: this may be a newly-staged (not-yet-persisted) item. Update staged bytes by id-stem.
                                            let stem = originalURL.deletingPathExtension().lastPathComponent
                                            if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
                                                if let data = try? Data(contentsOf: newURL) {
                                                    let old = stagedAttachments[idx]
                                                    stagedAttachments[idx] = StagedAttachment(id: old.id, data: data, kind: old.kind)
                                                }
                                            }
                                        }
        
                                    },
                                    onSaveAsNewAttachment: { newURL, kind in
                                        // Append a new staged item of provided kind after current index section-wise
                                        let newID = UUID()
                                        let data = (try? Data(contentsOf: newURL)) ?? Data()
                                        let newAtt = StagedAttachment(id: newID, data: data, kind: kind)
                                        // Ensure a real file exists at a stable URL for poster generation + playback.
                                        // (VideoPosterView relies on a file URL; temp exports can disappear.)
                                        if kind == .video, let sur = guaranteedSurrogateURL_edit(for: newAtt) {
                                            
                                            // Write the trimmed output to the surrogate URL so poster generation has a real file.
                                            do {
                                                // Ensure tmp folder exists
                                                try FileManager.default.createDirectory(
                                                    at: sur.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: nil
                                                )
                                                // Prefer copy for large files; fall back to write if needed.
                                                if FileManager.default.fileExists(atPath: sur.path) {
                                                    try FileManager.default.removeItem(at: sur)
                                                }
                                                try FileManager.default.copyItem(at: newURL, to: sur)
                                                existingAttachmentURLMap[newID] = sur
                                            } catch {
                                                // Fallback: keep using the export temp URL
                                                existingAttachmentURLMap[newID] = newURL
                                            }
                                        } else {
                                            existingAttachmentURLMap[newID] = newURL
                                        }
        
                                        // Seed audio title for save-as-new so we don't fall back to "audio clip"
                                        if kind == .audio {
                                            let key = "stagedAudioNames_temp"
                                            var dict = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
                                            let stem = newURL.deletingPathExtension().lastPathComponent
                                            if !stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                dict[newID.uuidString] = stem
                                                UserDefaults.standard.set(dict, forKey: key)
                                            }
                                        }
                                        // Insert by section: images, then videos, then audios
                                        switch kind {
                                        case .image:
                                            if let splitIndex = stagedAttachments.firstIndex(where: { $0.kind != .image }) {
                                                stagedAttachments.insert(newAtt, at: splitIndex)
                                            } else { stagedAttachments.append(newAtt) }
                                        case .video:
                                            let lastVideoIndex = stagedAttachments.lastIndex(where: { $0.kind == .video })
                                            if let lastVideoIndex { stagedAttachments.insert(newAtt, at: lastVideoIndex + 1) }
                                            else if let lastImageIndex = stagedAttachments.lastIndex(where: { $0.kind == .image }) { stagedAttachments.insert(newAtt, at: lastImageIndex + 1) }
                                            else { stagedAttachments.append(newAtt) }
                                        case .audio:
                                            let lastAudioIndex = stagedAttachments.lastIndex(where: { $0.kind == .audio })
                                            if let lastAudioIndex { stagedAttachments.insert(newAtt, at: lastAudioIndex + 1) } else { stagedAttachments.append(newAtt) }
                                        case .file:
                                            stagedAttachments.append(newAtt)
                                        }
                                    },
                                    canShare: false,
                                    replaceStrategy: .deferred
                                )
    }
}
//  [ROLLBACK ANCHOR] v7.8 DesignLite — post


#if canImport(UIKit)
import AVKit
fileprivate struct VideoPosterView: View {
    let url: URL?
    @State private var poster: UIImage? = nil
    @State private var isPresenting = false

    var body: some View {
        ZStack {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "film")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { if let u = await resolvedPlayableURL() { isPresenting = true } }
        }
        .sheet(isPresented: $isPresenting) {
            TaskView { // lightweight wrapper to bridge async URL resolution into the sheet
                if let u = await resolvedPlayableURL() { VideoPlayerSheet_AE(url: u) }
            }
        }
        .task(id: url) {
            if poster == nil, let u = await resolvedPlayableURL() {
                await generatePoster(u)
            }
        }
    }

    // Prefer the surrogate temp URL if it exists on disk; otherwise fall back to the persisted file URL if available.
    private func resolvedPlayableURL() async -> URL? {
        if let u = url, FileManager.default.fileExists(atPath: u.path) { return u }
        // Attempt to derive from staged id embedded in the surrogate path (..../<uuid>.mov)
        if let u = url, let id = UUID(uuidString: u.deletingPathExtension().lastPathComponent) {
            // Search Core Data for an Attachment with this id to get the persisted file path
            let ctx = PersistenceController.shared.container.viewContext
            let req: NSFetchRequest<Attachment> = Attachment.fetchRequest()
            req.fetchLimit = 1
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let match = try? ctx.fetch(req).first, let stored = match.value(forKey: "fileURL") as? String, !stored.isEmpty {
                // Resolve to a real file URL on disk
                if let direct = URL(string: stored), direct.isFileURL, FileManager.default.fileExists(atPath: direct.path) { return direct }
                if FileManager.default.fileExists(atPath: stored) { return URL(fileURLWithPath: stored) }
                let filename = URL(fileURLWithPath: stored).lastPathComponent
                let fm = FileManager.default
                let dirs: [URL?] = [
                    fm.urls(for: .documentDirectory, in: .userDomainMask).first,
                    fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
                    fm.temporaryDirectory
                ]
                for base in dirs.compactMap({ $0 }) {
                    let candidate = base.appendingPathComponent(filename)
                    if fm.fileExists(atPath: candidate.path) { return candidate }
                }
            }
        }
        return url // last resort
    }

    private func generatePoster(_ url: URL) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = AttachmentStore.generateVideoPoster(url: url)
                DispatchQueue.main.async {
                    self.poster = img
                    continuation.resume()
                }
            }
        }
    }
}

// Async-to-View bridge for sheet content
fileprivate struct TaskView<Content: View>: View {
    @ViewBuilder var content: () async -> Content
    @State private var built: Content? = nil
    var body: some View {
        Group { if let built { built } else { ProgressView() } }
            .task { built = await content() }
    }
}

fileprivate struct VideoPlayerSheet_AE: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.player?.isMuted = true
        return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
#endif
