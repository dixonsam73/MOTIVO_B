//
//  StagedAttachmentsSectionView.swift
//  MOTIVO
//

import SwiftUI

/// Section that previews staged (unsaved) attachments and allows removal / thumbnail marking.
struct StagedAttachmentsSectionView: View {
    let attachments: [StagedAttachment]
    let onRemove: (StagedAttachment) -> Void

    /// Selected staged attachment id to be saved as thumbnail (images only).
    @Binding var selectedThumbnailID: UUID?

    private let grid = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        Section {
            if attachments.isEmpty {
                Text("No attachments yet")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(attachments) { att in
                        AttachmentThumb(
                            att: att,
                            isThumbnail: selectedThumbnailID == att.id,
                            onMakeThumbnail: { selectedThumbnailID = att.id },
                            onRemove: { onRemove(att) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Thumb cell

fileprivate struct AttachmentThumb: View {
    let att: StagedAttachment
    let isThumbnail: Bool
    let onMakeThumbnail: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbContent
                .frame(width: 84, height: 84)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.secondary.opacity(0.15), lineWidth: 1)
                )


            // Overlays (top-right): Thumbnail star (images only) + Delete (all kinds)
            HStack(spacing: 6) {
                if att.kind == .image {
                    Text(isThumbnail ? "★" : "☆")
                        .font(.system(size: 16))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .onTapGesture { onMakeThumbnail() }
                        .accessibilityLabel(isThumbnail ? "Thumbnail (selected)" : "Set as Thumbnail")
                }
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .onTapGesture { onRemove() }
                    .accessibilityLabel("Delete attachment")
            }
            .padding(4)

        }
        .contextMenu {
            if att.kind == .image {
                Button("Set as Thumbnail") { onMakeThumbnail() }
            }
            Button(role: .destructive) { onRemove() } label: { Text("Remove") }
        }
    }

    @ViewBuilder
    private var thumbContent: some View {
        switch att.kind {
        case .image:
            if let ui = UIImage(data: att.data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                placeholder(system: "photo")
            }
        case .audio:
            placeholder(system: "waveform")
        case .video:
            placeholder(system: "video")
        case .file:
            placeholder(system: "doc")
        }
    }

    private func placeholder(system: String) -> some View {
        Image(systemName: system)
            .imageScale(.large)
            .foregroundStyle(.secondary)
    }
}
