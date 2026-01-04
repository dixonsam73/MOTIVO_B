//
//  AttachmentsSectionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 10/09/2025.
//

import SwiftUI
import AVKit

struct AttachmentsSectionView: View {
    let attachments: [Attachment]
    let onOpen: (Attachment) -> Void

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            Section(header: Text("Attachments")) {
                ForEach(attachments, id: \.objectID) { a in
                    HStack {
                        Image(systemName: icon(for: a.kind ?? "file"))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileName(of: a))
                                .lineLimit(1)
                            Text(a.kind ?? "file")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(a) }
                }
            }
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "audio": return "waveform"
        case "video": return "video"
        case "image": return "photo"
        default: return "doc"
        }
    }

    private func fileName(of a: Attachment) -> String {
        guard let path = a.fileURL, !path.isEmpty else { return "file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

