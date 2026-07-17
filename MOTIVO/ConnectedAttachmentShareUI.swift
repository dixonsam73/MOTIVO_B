// CHANGE-ID: 20260717_ConnectedAttachmentUserFacingName_UI
// SCOPE: Generate meaningful PDF attachment names from the score title and selected pages, pass them through Connected sharing, and prefer them in recipient presentation. No storage, export, routing or lifecycle changes.
// SEARCH-TOKEN: 20260717_ConnectedAttachmentUserFacingName_UI
//
// CHANGE-ID: 20260717_ConnectedAttachmentSharing_VisualPolish
// SCOPE: Visual-only refinement of Connected attachment destination, page scope, person and Ensemble selection using established Études cards, typography and PeopleUserRow presentation. No sharing, transport, persistence, recipient, navigation or backend behaviour changes.
// SEARCH-TOKEN: 20260717_ConnectedAttachmentSharing_VisualPolish
//
// CHANGE-ID: 20260716_M8C_ConnectedSessionAttachmentSharing_UI
// SCOPE: Reuse the existing Connected destination/recipient flow for saved-session PDF, photo, audio and video attachments while preserving score page selection and native iOS Share.
// SEARCH-TOKEN: 20260716_M8C_ConnectedSessionAttachmentSharing_UI
//
// CHANGE-ID: 20260715_ConnectedAttachmentNotifications_OpenToClear
// SCOPE: Mark an unread received Connected attachment viewed when its existing detail view opens.
// No UI, navigation, rendering, save, delete, transport, or sharing changes.
//
// CHANGE-ID: 20260714_ConnectedAttachmentSharing_Phase1_UI
// SCOPE: Reusable PDF attachment destination/page/recipient flow and recipient PDF detail UI.
// No post, feed, messaging, or AttachmentViewerView integration.

import SwiftUI
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct ConnectedScoreShareRequest: Identifiable {
    let id = UUID()
    let scoreID: UUID
    let title: String
    let url: URL
    let currentPage: Int
}

struct ConnectedSessionAttachmentShareRequest: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let mimeType: String
    let pageCount: Int
}

struct NativeActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ScoreAttachmentShareFlow: View {
    let request: ConnectedScoreShareRequest
    let connectedEnabled: Bool
    let onIOSShare: (URL) -> Void

    var body: some View {
        ConnectedAttachmentShareFlow(
            request: .score(request),
            connectedEnabled: connectedEnabled,
            onIOSShare: onIOSShare
        )
    }
}

struct SessionAttachmentShareFlow: View {
    let request: ConnectedSessionAttachmentShareRequest
    let connectedEnabled: Bool
    let onIOSShare: (URL) -> Void

    var body: some View {
        ConnectedAttachmentShareFlow(
            request: .sessionAttachment(request),
            connectedEnabled: connectedEnabled,
            onIOSShare: onIOSShare
        )
    }
}

private struct ConnectedAttachmentShareFlow: View {
    enum Request {
        case score(ConnectedScoreShareRequest)
        case sessionAttachment(ConnectedSessionAttachmentShareRequest)

        var url: URL {
            switch self {
            case .score(let request): return request.url
            case .sessionAttachment(let request): return request.url
            }
        }

        var title: String {
            switch self {
            case .score(let request): return request.title
            case .sessionAttachment(let request): return request.title
            }
        }

        var requiresPageScope: Bool {
            if case .score = self { return true }
            return false
        }
    }

    let request: Request
    let connectedEnabled: Bool
    let onIOSShare: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var ensembleStore = EnsembleStore.shared

    @State private var route: Route = .destination
    @State private var chosenDestination: AttachmentShareDestination?
    @State private var selectedPages: [Int]? = nil
    @State private var directory: [String: DirectoryAccount] = [:]
    @State private var isLoadingRecipients = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showPageSelection = false

    private enum Route { case destination, pageScope, person, ensemble }

    private var pageCount: Int {
        switch request {
        case .score:
            return max(PDFDocument(url: request.url)?.pageCount ?? 1, 1)
        case .sessionAttachment(let item):
            return item.pageCount
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .destination: destinationView
                case .pageScope: pageScopeView
                case .person: personView
                case .ensemble: ensembleView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(route == .destination ? "Cancel" : "Back") {
                        if route == .destination {
                            dismiss()
                        } else if route == .person || route == .ensemble {
                            route = request.requiresPageScope ? .pageScope : .destination
                        } else {
                            route = .destination
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPageSelection, onDismiss: {
            if let selectedPages, !selectedPages.isEmpty { continueAfterScope() }
        }) {
            PDFPageSelectionSheet(pageCount: pageCount, selectedPages: $selectedPages)
        }
        .alert("Couldn’t Share", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var navigationTitle: String {
        switch route {
        case .destination: return "Choose destination"
        case .pageScope: return "Choose content"
        case .person: return "Person"
        case .ensemble: return "Ensemble"
        }
    }

    private var destinationView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if connectedEnabled {
                    VStack(spacing: 0) {
                        destinationRow(
                            title: "Person",
                            systemImage: "person"
                        ) {
                            choose(.person)
                        }

                        Divider()
                            .padding(.leading, 56)

                        destinationRow(
                            title: "Ensemble",
                            systemImage: "person.3"
                        ) {
                            choose(.ensemble)
                        }
                    }
                    .connectedShareCard()
                }

                VStack(spacing: 0) {
                    destinationRow(
                        title: "Outside Études",
                        systemImage: "square.and.arrow.up"
                    ) {
                        onIOSShare(request.url)
                        dismiss()
                    }
                }
                .connectedShareCard()
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .appBackground()
    }

    private func destinationRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(Theme.Text.body)
                    .foregroundStyle(Color.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ destination: AttachmentShareDestination) {
        chosenDestination = destination
        if request.requiresPageScope {
            route = .pageScope
        } else {
            continueAfterScope()
        }
    }

    private var pageScopeView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button {
                    selectedPages = nil
                    continueAfterScope()
                } label: {
                    scopeRow("Entire document")
                }

                Divider()
                    .padding(.leading, 56)

                Button {
                    if case .score(let score) = request {
                        selectedPages = [max(score.currentPage, 1)]
                    }
                    continueAfterScope()
                } label: {
                    scopeRow("Current page")
                }

                Divider()
                    .padding(.leading, 56)

                Button {
                    selectedPages = nil
                    showPageSelection = true
                } label: {
                    scopeRow("Selected pages…")
                }
            }
            .connectedShareCard()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .appBackground()
    }

    private func scopeRow(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.75))
                .frame(width: 28, height: 28)

            Text(title)
                .font(Theme.Text.body)
                .foregroundStyle(Color.primary)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
    }

    private func continueAfterScope() {
        route = chosenDestination == .ensemble ? .ensemble : .person
        Task { await loadRecipients() }
    }

    private var validFollowerIDs: [String] { followStore.followers.sorted() }

    private var personView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoadingRecipients {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.xl)
                } else if validFollowerIDs.isEmpty {
                    Text("No Connected people are available.")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.l)
                } else {
                    ForEach(Array(validFollowerIDs.enumerated()), id: \.element) { index, id in
                        let account = directory[id]

                        selectionPersonRow(userID: id, account: account)
                            .disabled(isSending || account == nil)

                        if index < validFollowerIDs.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
            }
            .connectedShareCard()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .appBackground()
    }

    private func selectionPersonRow(
        userID: String,
        account: DirectoryAccount?
    ) -> some View {
        ZStack {
            PeopleUserRow(
                userID: userID,
                overrideDisplayName: account?.displayName ?? "Connected musician",
                overrideSubtitle: account?.accountID.map { "@\($0)" },
                overrideAvatarKey: account?.avatarKey
            ) {
                EmptyView()
            } trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
            }
            .allowsHitTesting(false)

            Button {
                Task { await send(to: [userID]) }
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var ensembleView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if ensembleStore.ensembles.isEmpty {
                    Text("No Ensembles are available.")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.l)
                } else {
                    ForEach(Array(ensembleStore.ensembles.enumerated()), id: \.element.id) { index, ensemble in
                        let recipients = validRecipients(for: ensemble)

                        selectionEnsembleRow(
                            ensemble: ensemble,
                            recipients: recipients
                        )
                        .disabled(isSending || recipients.isEmpty)

                        if index < ensembleStore.ensembles.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
            }
            .connectedShareCard()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .appBackground()
    }

    private func selectionEnsembleRow(
        ensemble: Ensemble,
        recipients: [String]
    ) -> some View {
        ZStack {
            PeopleUserRow(
                userID: "ensemble:\(ensemble.id)",
                overrideDisplayName: ensemble.name,
                overrideSubtitle: "\(recipients.count) " + (recipients.count == 1 ? "person" : "people"),
                overrideAvatarKey: nil
            ) {
                EmptyView()
            } trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
            }
            .allowsHitTesting(false)

            Button {
                Task { await send(to: recipients) }
            } label: {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func validRecipients(for ensemble: Ensemble) -> [String] {
        let approved = Set(followStore.followers)
        return Array(Set(ensemble.memberUserIDs.map { $0.lowercased() }))
            .filter { approved.contains($0) && directory[$0] != nil }
            .sorted()
    }

    private func loadRecipients() async {
        await followStore.refreshFromBackendIfPossible()
        let ids = Array(Set(followStore.followers.union(ensembleStore.ensembles.flatMap { $0.memberUserIDs }))).sorted()
        guard !ids.isEmpty else { return }
        isLoadingRecipients = true
        defer { isLoadingRecipients = false }
        if case .success(let map) = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids) {
            directory = map
        }
    }

    private func preparedPayload() throws -> ConnectedAttachmentUploadPayload {
        switch request {
        case .score(let score):
            let preparedURL: URL
            let preparedPageCount: Int
            if let pages = selectedPages, !pages.isEmpty {
                preparedURL = try PDFSubsetExporter.export(from: score.url, selectedPages: pages)
                preparedPageCount = pages.count
            } else {
                preparedURL = score.url
                preparedPageCount = pageCount
            }
            let filename = score.title.lowercased().hasSuffix(".pdf") ? score.title : score.title + ".pdf"
            return ConnectedAttachmentUploadPayload(
                localURL: preparedURL,
                filename: filename,
                attachmentName: scoreAttachmentName(title: score.title, selectedPages: selectedPages),
                mimeType: "application/pdf",
                pageCount: preparedPageCount
            )

        case .sessionAttachment(let item):
            return ConnectedAttachmentUploadPayload(
                localURL: item.url,
                filename: item.title,
                attachmentName: item.title,
                mimeType: item.mimeType,
                pageCount: item.pageCount
            )
        }
    }

    private func scoreAttachmentName(title: String, selectedPages: [Int]?) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle: String
        if trimmedTitle.lowercased().hasSuffix(".pdf") {
            baseTitle = String(trimmedTitle.dropLast(4))
        } else {
            baseTitle = trimmedTitle
        }
        let safeTitle = baseTitle.isEmpty ? "Score" : baseTitle

        guard let selectedPages, !selectedPages.isEmpty else {
            return "\(safeTitle).pdf"
        }

        let pages = Array(Set(selectedPages.filter { $0 > 0 })).sorted()
        guard let firstPage = pages.first else {
            return "\(safeTitle).pdf"
        }

        if pages.count == 1 {
            return "\(safeTitle) — Page \(firstPage).pdf"
        }

        let consecutive = zip(pages, pages.dropFirst()).allSatisfy { next, following in
            following == next + 1
        }
        if consecutive, let lastPage = pages.last {
            return "\(safeTitle) — Pages \(firstPage)–\(lastPage).pdf"
        }

        return "\(safeTitle) — \(pages.count) selected pages.pdf"
    }

    private func send(to recipients: [String]) async {
        guard !recipients.isEmpty else {
            errorMessage = "There are no valid Connected recipients."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let payload = try preparedPayload()
            switch await BackendEnvironment.shared.connectedAttachments.upload(payload) {
            case .failure(let error): throw error
            case .success(let reference):
                switch await BackendEnvironment.shared.connectedAttachments.deliver(reference, to: recipients) {
                case .success: dismiss()
                case .failure(let error): throw error
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


private extension View {
    func connectedShareCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

struct ReceivedConnectedAttachmentDetailView: View {
    let attachment: ConnectedAttachment

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store =
        ReceivedConnectedAttachmentStore.shared

    @State private var localURL: URL?
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if let localURL {
                AttachmentViewerView(
                    imageURLs: attachmentKind == .image ? [localURL] : [],
                    startIndex: 0,
                    videoURLs: attachmentKind == .video ? [localURL] : [],
                    audioURLs: attachmentKind == .audio ? [localURL] : [],
                    pdfURLs: attachmentKind == .pdf ? [localURL] : [],
                    isReadOnly: true,
                    canShare: false
                )
            } else {
                ProgressView("Downloading…")
            }
        }
        .navigationTitle(attachment.attachmentName ?? attachment.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if attachmentKind == .pdf {
                    Button("Save to Scores") {
                        Task {
                            await saveToScores()
                        }
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task {
            if attachment.viewedAt == nil {
                await store.markViewed(attachment)
            }

            do {
                localURL = try await store.localURL(
                    for: attachment
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Delete this shared attachment?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.delete(attachment)
                    dismiss()
                }
            }
        }
        .alert(
            "Couldn’t Open Attachment",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var attachmentKind: AttachmentKind {
        let mime = attachment.mimeType.lowercased()
        if mime == "application/pdf" { return .pdf }
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("audio/") { return .audio }
        if mime.hasPrefix("video/") { return .video }

        switch URL(fileURLWithPath: attachment.filename).pathExtension.lowercased() {
        case "pdf": return .pdf
        case "jpg", "jpeg", "png", "heic", "heif", "gif": return .image
        case "m4a", "mp3", "wav", "aiff", "caf": return .audio
        case "mov", "mp4", "m4v": return .video
        default: return .file
        }
    }

    private func saveToScores() async {
        do {
            let url: URL

            if let localURL {
                url = localURL
            } else {
                url = try await store.localURL(
                    for: attachment
                )
            }

            _ = try ScoreLibraryStore.shared.importPDF(
                from: url
            )

            await store.markSavedToScores(attachment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
