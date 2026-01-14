// CHANGE-ID: 20260114_103700_9E
// SCOPE: 9E use signed URLs for backend attachment playback

import SwiftUI
import Foundation

// Read-only detail view for a BackendSessionViewModel.
// - No CoreData imports
// - Step 8G Phase 2: download backend attachments (authenticated) to temp files and open AttachmentViewerView in strict read-only mode.
public struct BackendSessionDetailView: View {
    public let model: BackendSessionViewModel

    // Local shims to avoid hard dependencies on Theme while keeping visual consistency.
    private var spacingS: CGFloat { 8 }
    private var spacingM: CGFloat { 12 }
    private var spacingL: CGFloat { 16 }

    // Step 9E: read-only backend attachment playback (signed URLs at playback time + open AttachmentViewerView).
    @State private var isViewerPresented: Bool = false
    @State private var isLoadingAttachments: Bool = false
    @State private var attachmentLoadError: String? = nil
    @State private var viewerImageURLs: [URL] = []
    @State private var viewerVideoURLs: [URL] = []
    @State private var viewerAudioURLs: [URL] = []

    public init(model: BackendSessionViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacingL) {
                titleRow

                section(header: Text("Metadata")) {
                    VStack(alignment: .leading, spacing: spacingS) {
                        // Activity / instrument
                        labeledLine(label: "Activity", value: model.activityLabel)
                        labeledLine(label: "Instrument", value: model.instrumentLabel ?? "—")

                        // Ownership
                        labeledLine(label: "Owner", value: model.ownerUserID.isEmpty ? "—" : model.ownerUserID)
                        labeledLine(label: "Is mine", value: model.isMine ? "true" : "false")

                        // Timestamps
                        labeledLine(label: "Session time", value: model.sessionTimestampRaw ?? "—")
                        labeledLine(label: "Created", value: model.createdAtRaw ?? "—")
                        labeledLine(label: "Updated", value: model.updatedAtRaw ?? "—")
                    }
                }

                // Notes section (placeholder until backend provides it)
                section(header: Text("Notes")) {
                    if let notes = model.notes, !notes.isEmpty {
                        Text(notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No notes.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Attachments section (Step 8G Phase 2: read-only backend playback)
                section(header: Text("Attachments")) {
                    if model.attachmentRefs.isEmpty {
                        Text("No attachments.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: spacingS) {
                            Button {
                                Task { await openAttachmentsViewer() }
                            } label: {
                                HStack(spacing: spacingS) {
                                    Image(systemName: "paperclip")
                                        .foregroundStyle(.secondary)
                                    Text(isLoadingAttachments ? "Loading…" : "View attachments (\(model.attachmentRefs.count))")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingAttachments)

                            if let err = attachmentLoadError, !err.isEmpty {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // Light disclosure list (filenames) — presentation-only.
                            ForEach(model.attachmentRefs, id: \.self) { ref in
                                HStack(spacing: spacingS) {
                                    Image(systemName: icon(for: ref.kind))
                                        .foregroundStyle(.secondary)
                                    Text(filename(for: ref.path))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, spacingM)
            .padding(.vertical, spacingL)
        }
        .navigationTitle("Backend Detail")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isViewerPresented) {
            AttachmentViewerView(
                imageURLs: viewerImageURLs,
                startIndex: 0,
                themeBackground: Color(.systemBackground),
                videoURLs: viewerVideoURLs,
                audioURLs: viewerAudioURLs,
                onDelete: nil,
                titleForURL: nil,
                onRename: nil,
                onRenameLegacy: nil,
                onFavourite: nil,
                isFavourite: nil,
                onTogglePrivacy: nil,
                isPrivate: nil,
                onReplaceAttachment: nil,
                onSaveAsNewAttachment: nil,
                onSaveAsNewAttachmentFromSource: nil,
                isReadOnly: true,
                canShare: false
            )
        }
    }

    // MARK: - Step 8G Phase 2 helpers

    private func icon(for kind: BackendSessionViewModel.BackendAttachmentRef.Kind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        }
    }

    private func filename(for path: String) -> String {
        let comps = path.split(separator: "/")
        return comps.last.map(String.init) ?? path
    }

    private func openAttachmentsViewer() async {
        attachmentLoadError = nil
        isLoadingAttachments = true

        // Clear previous
        viewerImageURLs = []
        viewerVideoURLs = []
        viewerAudioURLs = []

        defer { isLoadingAttachments = false }

        // Step 9E: request short-lived signed URLs at playback time (do not persist).
        // AVPlayer / URLSession can use the signed URL directly; no local staging required.
        let expiresIn: Int = 60

        for ref in model.attachmentRefs {
            let result = await NetworkManager.shared.createSignedStorageObjectURL(bucket: ref.bucket, path: ref.path, expiresInSeconds: expiresIn)
            switch result {
            case .success(let signedURL):
                switch ref.kind {
                case .image: viewerImageURLs.append(signedURL)
                case .video: viewerVideoURLs.append(signedURL)
                case .audio: viewerAudioURLs.append(signedURL)
                }
            case .failure(let error):
                attachmentLoadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                return
            }
        }

        isViewerPresented = true
    }

    private func writeToTemp(data: Data, originalPath: String) -> URL? {
        let name = filename(for: originalPath)
        let safe = name.isEmpty ? UUID().uuidString : name
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("motivo_backend_\(UUID().uuidString)_\(safe)")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Small UI helpers

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.activityLabel)
                .font(.headline)
                .foregroundStyle(.primary)

            if let instrument = model.instrumentLabel, !instrument.isEmpty {
                Text("•")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(instrument)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Prefer sessionTimestamp in the header when available; fall back to createdAt.
            Text(model.sessionTimestampRaw ?? model.createdAtRaw ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(header: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacingS) {
            header
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: spacingS) {
                content()
            }
            .padding(spacingM)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func labeledLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacingS) {
            Text(label + ":")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.footnote)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
#Preview("BackendSessionDetailView") {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "owner_user_id": "user_123",
      "session_id": "00000000-0000-0000-0000-000000000002",
      "session_timestamp": "2025-12-31 23:58",
      "created_at": "2025-12-31 23:59",
      "updated_at": "2026-01-01 00:01",
      "is_public": true,
      "activity_label": "Practice",
      "instrument_label": "Bass"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let post = try! decoder.decode(BackendPost.self, from: json)
    let model = BackendSessionViewModel(post: post, currentUserID: "user_123")
    return NavigationStack { BackendSessionDetailView(model: model) }
}
#endif
