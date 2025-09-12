//
//  StagedAttachmentsSectionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 12/09/2025.
//

import SwiftUI

struct StagedAttachmentsSectionView: View {
    let attachments: [StagedAttachment]
    let onRemove: (StagedAttachment) -> Void

    var body: some View {
        Section(header: Text("Attachments")) {
            if attachments.isEmpty {
                Text("No attachments")
                    .foregroundColor(.secondary)
            } else {
                ForEach(attachments) { att in
                    HStack {
                        Text(label(for: att))
                        Spacer()
                        Button(role: .destructive) {
                            onRemove(att)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    private func label(for att: StagedAttachment) -> String {
        switch att.kind {
        case .image: return "Image"
        case .audio: return "Audio"
        case .video: return "Video"
        case .file:  return "File"
        }
    }
}
