// CHANGE-ID: 20251010_161159_autodesc_fix_edit
// SCOPE: Edit-mode auto-description restoration; load userActivityLabel; reconcile auto vs custom; preserve ordering fix; no other changes
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

    @State private var isShowingAttachmentViewer: Bool = false
    @State private var viewerStartIndex: Int = 0

    // UI stability (instruments empty-state)
    @State private var instrumentsGateArmed = false
    @State private var instrumentsReady = false

    // Track which staged attachments came from Core Data (existing) to prevent duplication on save
    @State private var existingAttachmentIDs: Set<UUID> = []

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
        return false
    }

    private func setPrivate(id: UUID?, url: URL?, _ value: Bool) {
        guard let key = privacyKey(id: id, url: url) else { return }
        // Update local cache first for instant UI
        privacyMap[key] = value
        // Persist via centralized helper (also posts didChange notification)
        AttachmentPrivacy.setPrivate(id: id, url: url, value)
    }
    // ---- end privacy helpers ----

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
        guard let dot = selectedDotIndex_edit else {
            stripFocusTokensFromNotes_edit()
            return
        }

        stripFocusTokensFromNotes_edit()
        if !notes.isEmpty && !notes.hasSuffix("\n") { notes.append("\n") }
        notes.append("FocusDotIndex: \(dot)")
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
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {

                // No instruments / Instrument picker
                if hasNoInstruments {
                    // Show the empty-state card only after the first 120ms tick
                    if instrumentsGateArmed && !instrumentsReady {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No instruments found").font(.headline)
                            Text("Add an instrument in your Profile to save this session.")
                                .foregroundStyle(.secondary).font(.subheadline)
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
                        .padding(.bottom, 4)
                    }
                    .buttonStyle(.plain)
                    if durationSeconds == 0 {
                        Text("Duration must be greater than 0")
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                }
                .cardSurface()

                // Privacy
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Toggle("Public", isOn: $isPublic)
                        .font(Theme.Text.body)
                }
                .cardSurface()

                // Notes
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Notes").sectionHeader()
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .font(Theme.Text.body)
                            .frame(minHeight: 100)
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
                        let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(stagedAttachments) { att in
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
                                                .onTapGesture { selectedThumbnailID = att.id }
                                                .accessibilityLabel(selectedThumbnailID == att.id ? "Thumbnail (selected)" : "Set as Thumbnail")
                                        }

                                        let fileURL: URL? = surrogateURL(for: att)
                                        let priv: Bool = isPrivate(id: att.id, url: fileURL)
                                        Button {
                                            setPrivate(id: att.id, url: fileURL, !priv)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Image(systemName: priv ? "eye.slash" : "eye")
                                                .font(.system(size: 16, weight: .semibold))
                                                .padding(8)
                                                .background(.ultraThinMaterial, in: Circle())
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
                                        Button("Set as Thumbnail") { selectedThumbnailID = att.id }
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
                                    let index = stagedIndexForAttachment_edit(att)
                                    if index >= 0 {
                                        viewerStartIndex = index
                                        ensureSurrogateFilesExistForViewer_edit()
                                        isShowingAttachmentViewer = true
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .cardSurface()
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
                .cardSurface()

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
        .fullScreenCover(isPresented: $isShowingAttachmentViewer) {
            let arrays = viewerURLArrays_edit()
            let imageURLs = arrays.images
            let videoURLs = arrays.videos
            let audioURLs = arrays.audios
            let combined = imageURLs + videoURLs + audioURLs
            let startIndex = min(max(viewerStartIndex, 0), max(combined.count - 1, 0))

            AttachmentViewerView(
                imageURLs: imageURLs,
                startIndex: startIndex,
                themeBackground: Color(.systemBackground),
                videoURLs: videoURLs,
                audioURLs: audioURLs,
                onDelete: { url in
                    // Map by staged id from surrogate URL stem
                    let stem = url.deletingPathExtension().lastPathComponent
                    if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
                        let removed = stagedAttachments.remove(at: idx)
                        existingAttachmentIDs.remove(removed.id)
                        if selectedThumbnailID == removed.id {
                            selectedThumbnailID = stagedAttachments.first(where: { $0.kind == .image })?.id
                        }
                    }
                },
                onFavourite: { url in
                    // Selecting favourite maps to setting selectedThumbnailID for images/videos/audio
                    let stem = url.deletingPathExtension().lastPathComponent
                    if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
                        selectedThumbnailID = att.id
                    }
                },
                isFavourite: { url in
                    let stem = url.deletingPathExtension().lastPathComponent
                    if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
                        return selectedThumbnailID == att.id
                    }
                    return false
                },
                onTogglePrivacy: { url in
                    let stem = url.deletingPathExtension().lastPathComponent
                    if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
                        let priv = isPrivate(id: att.id, url: url)
                        setPrivate(id: att.id, url: url, !priv)
                    }
                },
                isPrivate: { url in
                    let stem = url.deletingPathExtension().lastPathComponent
                    if let att = stagedAttachments.first(where: { $0.id.uuidString == stem }) {
                        return isPrivate(id: att.id, url: url)
                    }
                    return false
                },
                onReplaceAttachment: { originalURL, newURL, kind in
                    // Replace staged data by matching surrogate stem
                    let stem = originalURL.deletingPathExtension().lastPathComponent
                    if let idx = stagedAttachments.firstIndex(where: { $0.id.uuidString == stem }) {
                        if let data = try? Data(contentsOf: newURL) {
                            let old = stagedAttachments[idx]
                            stagedAttachments[idx] = StagedAttachment(id: old.id, data: data, kind: old.kind)
                        }
                    }
                },
                onSaveAsNewAttachment: { newURL, kind in
                    // Append a new staged item of provided kind after current index section-wise
                    let newID = UUID()
                    let data = (try? Data(contentsOf: newURL)) ?? Data()
                    let newAtt = StagedAttachment(id: newID, data: data, kind: kind)
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
                }
            )
        }
        .task { hydrate() } // unified first-appearance init
        .onAppear {
            preselectFocusFromNotesIfNeeded_edit()
            syncActivityChoiceFromState()
            loadPrivacyMap()
            // Ensure token is hidden in Notes whenever view appears
            stripFocusTokensFromNotes_edit()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
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

        if selectedDotIndex_edit != nil {
            applyFocusToNotesBeforeSave_edit()
        } else {
            // No focus selected — ensure tokens are not persisted
            stripFocusTokensFromNotes_edit()
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

        // Commit staged attachments (skip existing to avoid duplicates; update thumbnail flags)
        commitStagedAttachments(to: s, ctx: viewContext)

        do {
            try viewContext.save()
            // ===== v7.12A • Publish hook after successful save =====
            PublishService.shared.publishIfNeeded(
                objectID: s.objectID,
                shouldPublish: isPublic
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
                selectedThumbnailID = id
            }
        }
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
        if kind == .image {
            let imageCount = stagedAttachments.filter { $0.kind == .image }.count
            if imageCount == 1 { selectedThumbnailID = id }
        }
    }

    private func removeStagedAttachment(_ a: StagedAttachment) {
        stagedAttachments.removeAll { $0.id == a.id }
        existingAttachmentIDs.remove(a.id)
        if selectedThumbnailID == a.id {
            selectedThumbnailID = stagedAttachments.first(where: { $0.kind == .image })?.id
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

    /// Adds only newly staged attachments (not those that originated from Core Data) and updates thumbnail flags for all.
    private func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) {
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
                let result = try AttachmentStore.saveDataWithRollback(att.data, suggestedName: att.id.uuidString, ext: ext)
                rollbacks.append(result.rollback)
                let isThumb = (att.kind == .image) && (chosenThumbID == att.id)
                let created = try AttachmentStore.addAttachment(kind: att.kind, filePath: result.path, to: session, isThumbnail: isThumb, ctx: ctx)
                createdAttachments.append(created)
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
        let fm = FileManager.default
        for att in stagedAttachments {
            guard let url = surrogateURL(for: att) else { continue }
            if !fm.fileExists(atPath: url.path) {
                switch att.kind {
                case .image, .video, .audio:
                    try? att.data.write(to: url, options: .atomic)
                case .file:
                    break
                }
            }
        }
    }

    private func viewerURLArrays_edit() -> (images: [URL], videos: [URL], audios: [URL]) {
        let imageURLs: [URL] = stagedAttachments.filter { $0.kind == .image }.compactMap { surrogateURL(for: $0) }
        let videoURLs: [URL] = stagedAttachments.filter { $0.kind == .video }.compactMap { surrogateURL(for: $0) }
        let audioURLs: [URL] = stagedAttachments.filter { $0.kind == .audio }.compactMap { surrogateURL(for: $0) }
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
                if let display = namesDict[att.id.uuidString], !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(display)
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





