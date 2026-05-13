// CHANGE-ID: 20260513_171900_MonthThoughtThreadDisplayParity
// SCOPE: Add subdued thread chip continuity display to Journal Month Thought rows only; preserve existing compact geometry, neutral timeline anchor, attachments, navigation, analytics, and Year behavior.
// SEARCH-TOKEN: 20260513_171900_MonthThoughtThreadDisplayParity

import SwiftUI

struct MonthThoughtRow: View {
    let session: Session
    @Binding var selectedThread: String?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter
    }()

    private var titleText: String {
        if let header = session.thoughtHeader?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty {
            return header
        }
        return "Thought"
    }

    private var timestampText: String {
        Self.timestampFormatter.string(from: session.timestamp ?? Date())
    }

    private var threadLabel: String? {
        sanitizeThoughtThreadLabel(session.threadLabel ?? "", maxLength: 32)
    }

    private var visualAttachment: Attachment? {
        let attachments = (session.attachments as? Set<Attachment>).map { Array($0) } ?? []
        return pickFavoriteVisualAttachment(from: attachments)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.Colors.secondaryText.opacity(0.30))
                    .frame(width: 1.5, height: 38)
            }
            .frame(width: 6, height: 44, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(Theme.Text.body.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("monthThought.title")

                Text(timestampText)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.68))
                    .lineLimit(1)
                    .accessibilityIdentifier("monthThought.datetime")

                if let thread = threadLabel, !thread.isEmpty {
                    Button {
                        if selectedThread == thread {
                            selectedThread = nil
                        } else {
                            selectedThread = thread
                        }
                    } label: {
                        ThreadMetaPill(title: thread, isSelected: selectedThread == thread, font: .caption2, verticalPadding: 0)
                            .scaleEffect(0.94)
                            .opacity(0.92)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                    .accessibilityLabel("Thread \(thread)")
                    .accessibilityIdentifier("monthThought.thread")
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if let visualAttachment {
                SingleAttachmentPreview(attachment: visualAttachment)
                    .scaleEffect(0.50)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityIdentifier("monthThought.visualAttachment")
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func pickFavoriteVisualAttachment(from attachments: [Attachment]) -> Attachment? {
    let visualAttachments = attachments.filter { attachmentVisualKind($0) != nil }

    if let flagged = visualAttachments.first(where: { attachmentHasTrueFlag($0, keys: ["isThumbnail", "thumbnail", "isFavorite", "favorite", "isStarred", "starred", "isPrimary", "isCover"]) }) {
        return flagged
    }

    if let firstImage = visualAttachments.first(where: { attachmentVisualKind($0) == "image" }) {
        return firstImage
    }

    if let firstVideo = visualAttachments.first(where: { attachmentVisualKind($0) == "video" }) {
        return firstVideo
    }

    return nil
}

private func attachmentHasTrueFlag(_ attachment: Attachment, keys: [String]) -> Bool {
    let properties = attachment.entity.propertiesByName

    for key in keys where properties[key] != nil {
        if let number = attachment.value(forKey: key) as? NSNumber, number.boolValue {
            return true
        }

        if let bool = attachment.value(forKey: key) as? Bool, bool {
            return true
        }
    }

    return false
}

private func attachmentVisualKind(_ attachment: Attachment) -> String? {
    let properties = attachment.entity.propertiesByName

    func stringValue(_ key: String) -> String? {
        guard properties[key] != nil else { return nil }
        return attachment.value(forKey: key) as? String
    }

    let typeString = (stringValue("type") ?? stringValue("kind") ?? stringValue("mimeType") ?? "").lowercased()
    if typeString.contains("image") { return "image" }
    if typeString.contains("video") { return "video" }
    if typeString.contains("audio") || typeString.contains("pdf") || typeString.contains("document") {
        return nil
    }

    let urlString = (stringValue("url") ?? stringValue("fileURL") ?? stringValue("path") ?? "").lowercased()
    if urlString.hasSuffix(".png") || urlString.hasSuffix(".jpg") || urlString.hasSuffix(".jpeg") || urlString.hasSuffix(".heic") {
        return "image"
    }
    if urlString.hasSuffix(".mp4") || urlString.hasSuffix(".mov") || urlString.hasSuffix(".m4v") {
        return "video"
    }

    return nil
}


private func sanitizeThoughtThreadLabel(_ label: String, maxLength: Int) -> String? {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count <= maxLength { return trimmed }
    return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
}
