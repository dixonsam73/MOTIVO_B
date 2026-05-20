// CHANGE-ID: 20260520_211500_ContentViewRowExtractionPass1
// SCOPE: ContentView ThoughtRow extraction only; moved unchanged from ContentView except file-scope access required for separate compilation.
// SEARCH-TOKEN: 20260520_211500_ContentViewRowExtractionPass1

import SwiftUI
import CoreData
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Photos)
import Photos
#endif

struct ThoughtRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let session: Session
    let scope: FeedScope
    @Binding var selectedThread: String?
    let context: ThoughtRowContext
    let viewerUserID: String?
    let threadChipFillColor: Color?
    let threadChipTextColor: Color?

    @State private var isSavedLocal: Bool = false
    @AppStorage("hasSeenSaveHint_v1") private var hasSeenSaveHint: Bool = false
    @State private var showSaveHint: Bool = false
    @State private var saveHintToken = UUID()

    init(
        session: Session,
        scope: FeedScope,
        selectedThread: Binding<String?> = .constant(nil),
        context: ThoughtRowContext = .feed,
        viewerUserID: String? = nil,
        threadChipFillColor: Color? = nil,
        threadChipTextColor: Color? = nil
    ) {
        self.session = session
        self.scope = scope
        self._selectedThread = selectedThread
        self.context = context
        self.viewerUserID = viewerUserID
        self.threadChipFillColor = threadChipFillColor
        self.threadChipTextColor = threadChipTextColor
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    private var timestampText: String {
        Self.timestampFormatter.string(from: session.timestamp ?? Date())
    }

    private var sessionUUID: UUID? {
        session.value(forKey: "id") as? UUID
    }


    private var threadLabel: String? {
        ThreadLabelSanitizer.sanitize(session.threadLabel ?? "", maxLength: 32)
    }

    private var attachments: [Attachment] {
        (session.attachments as? Set<Attachment>).map { Array($0) } ?? []
    }

    private var favoriteAttachment: Attachment? {
        pickFavoriteAttachment(from: attachments)
    }

    private var verticalPadding: CGFloat {
        if context == .journalWeek { return 5 }
        return scope == .mine ? 7 : 6
    }

    private var rowSpacing: CGFloat {
        context == .journalWeek ? 3 : 4
    }

    private var timestampOpacity: Double {
        context == .journalWeek ? 0.64 : 0.72
    }

    private var headerTopPadding: CGFloat {
        context == .journalWeek ? 0 : 1
    }

    private var bodyTopPadding: CGFloat {
        context == .journalWeek ? 0 : 1
    }

    private var bodyOpacity: Double {
        context == .journalWeek ? 0.78 : 0.88
    }

    private var thumbnailTopPadding: CGFloat {
        if context == .journalWeek { return 3 }
        return scope == .mine ? 5 : 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(timestampText)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.secondaryText.opacity(timestampOpacity))
                .lineLimit(1)
                .padding(.leading, (context == .journalWeek && threadLabel != nil && !(threadLabel?.isEmpty ?? true)) ? 3 : 0)
                .accessibilityLabel("Date and time")
                .accessibilityIdentifier("row.datetime")


            if context == .journalWeek, let thread = threadLabel, !thread.isEmpty {
                Button {
                    if selectedThread == thread {
                        selectedThread = nil
                    } else {
                        selectedThread = thread
                    }
                } label: {
                    if selectedThread == thread {
                        ThreadMetaPill(title: thread, isSelected: true, font: .caption, verticalPadding: 1)
                    } else if let threadChipFillColor, let threadChipTextColor {
                        Text(thread)
                            .font(Theme.Text.meta.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.82))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                threadChipFillColor,
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(threadChipTextColor.opacity(0.72), lineWidth: 1)
                            )
                    } else {
                        ThreadMetaPill(title: thread, isSelected: false, font: .caption, verticalPadding: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .accessibilityLabel("Thread \(thread)")
                .accessibilityIdentifier("row.thread")
            }

            if let header = session.thoughtHeader {
                let splitHeader = splitThoughtLead(header)
                (
                    Text(splitHeader.lead)
                        .font(Theme.Text.body.weight(.semibold))
                        .foregroundColor(Color.primary.opacity(0.86))
                    +
                    Text(splitHeader.remainder)
                        .font(Theme.Text.body)
                        .foregroundColor(Color.primary.opacity(0.78))
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, headerTopPadding)
                .accessibilityIdentifier("row.title")
            }

            if let body = session.thoughtBodyPreview {
                Text(body)
                    .font(Theme.Text.body)
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(bodyOpacity))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, bodyTopPadding)
                    .accessibilityIdentifier("row.subtitle")
            }

            if let favoriteAttachment {
                HStack(alignment: .center, spacing: 8) {
                    SingleAttachmentPreview(attachment: favoriteAttachment)
                    Spacer(minLength: 0)
                }
                .padding(.top, thumbnailTopPadding)
            }

            if context == .journalWeek, let sessionUUID {
                journalWeekSaveRow(sessionID: sessionUUID)
                    .padding(.top, favoriteAttachment == nil ? thumbnailTopPadding : 8)
            }
        }
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: sessionUUID) {
            if context == .journalWeek, let sessionUUID, let viewerUserID {
                isSavedLocal = FeedInteractionStore.isSaved(sessionUUID, viewerUserID: viewerUserID)
            } else {
                isSavedLocal = false
            }
        }
    }


    private var saveHintView: some View {
        VStack(spacing: 2) {
            Text("Saved for later")
                .font(Theme.Text.meta)
                .foregroundStyle(.primary)
            Text("Use Filter to find saved posts")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .transition(.opacity)
    }

    private func presentSaveHint() {
        let token = UUID()
        saveHintToken = token
        withAnimation(.easeInOut(duration: 0.15)) {
            showSaveHint = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard saveHintToken == token else { return }
            hideSaveHint()
        }
    }

    private func hideSaveHint() {
        withAnimation(.easeInOut(duration: 1.0)) {
            showSaveHint = false
        }
    }

    @ViewBuilder
    private func journalWeekSaveRow(sessionID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSaveHint {
                saveHintView
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                let vid = viewerUserID ?? "unknown"
                let newState = FeedInteractionStore.toggleSaved(sessionID, viewerUserID: vid)
                isSavedLocal = newState
                if !hasSeenSaveHint {
                    presentSaveHint()
                    hasSeenSaveHint = true
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSavedLocal ? "heart.fill" : "heart")
                        .foregroundStyle(isSavedLocal ? Color.red.opacity(0.75) : Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSavedLocal ? "Unsave" : "Save")

            Spacer(minLength: 0)
            }
        }
    }
}

