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
import Photos

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

struct ListAttachmentShareFlow: View {
    let request: ConnectedListShareRequest
    let connectedEnabled: Bool

    var body: some View {
        ConnectedAttachmentShareFlow(request: .list(request), connectedEnabled: connectedEnabled, onIOSShare: { _ in })
    }
}

private struct ConnectedAttachmentShareFlow: View {
    enum Request {
        case score(ConnectedScoreShareRequest)
        case sessionAttachment(ConnectedSessionAttachmentShareRequest)
        case list(ConnectedListShareRequest)

        var url: URL? {
            switch self {
            case .score(let request): return request.url
            case .sessionAttachment(let request): return request.url
            case .list: return nil
            }
        }

        var title: String {
            switch self {
            case .score(let request): return request.title
            case .sessionAttachment(let request): return request.title
            case .list(let request): return request.payload.name
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

    @State private var route: Route

    init(request: Request, connectedEnabled: Bool, onIOSShare: @escaping (URL) -> Void) {
        self.request = request
        self.connectedEnabled = connectedEnabled
        self.onIOSShare = onIOSShare
        _route = State(initialValue: request.requiresPageScope ? .pageScope : .destination)
    }
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
        case .score(let score):
            return max(PDFDocument(url: score.url)?.pageCount ?? 1, 1)
        case .sessionAttachment(let item):
            return item.pageCount
        case .list: return 0
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
                    .disabled(isSending)
                }
            }
        }
        .interactiveDismissDisabled(isSending)
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

                if let url = request.url {
                    VStack(spacing: 0) {
                        destinationRow(title: "Outside Études", systemImage: "square.and.arrow.up") {
                            onIOSShare(url)
                            dismiss()
                        }
                    }
                    .connectedShareCard()
                }
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
        continueAfterScope()
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
        guard let destination = chosenDestination else {
            route = .destination
            return
        }
        route = destination == .ensemble ? .ensemble : .person
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
                overrideSubtitle: DirectorySubtitle.text(for: account),
                overrideAvatarKey: account?.avatarKey,
                overrideAvatarVersion: account?.avatarVersion
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
                        .disabled(isSending || isLoadingRecipients || recipients.isEmpty)

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
        isLoadingRecipients = true
        directory = [:]
        defer { isLoadingRecipients = false }
        await followStore.refreshFromBackendIfPossible()
        let ids = Array(Set(followStore.followers.union(ensembleStore.ensembles.flatMap { $0.memberUserIDs }))).sorted()
        guard !ids.isEmpty else { return }
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
                attachmentName: sessionAttachmentName(for: item),
                mimeType: item.mimeType,
                pageCount: item.pageCount
            )
        case .list:
            throw ConnectedAttachmentError.invalidAttachment

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



    private func sessionAttachmentName(for item: ConnectedSessionAttachmentShareRequest) -> String {
        let trimmed = item.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let mime = item.mimeType.lowercased()

        func isMeaningfulTitle(_ title: String) -> Bool {
            guard !title.isEmpty else { return false }
            let stem = (title as NSString).deletingPathExtension
            return UUID(uuidString: stem) == nil
        }

        if mime.hasPrefix("image/") {
            return "Photo"
        }

        if mime.hasPrefix("video/") {
            return isMeaningfulTitle(trimmed) ? trimmed : "Video"
        }

        if mime.hasPrefix("audio/") {
            return isMeaningfulTitle(trimmed) ? trimmed : "Recording"
        }

        return trimmed
    }

    private func send(to recipients: [String]) async {
        guard !isSending else { return }
        guard !recipients.isEmpty else {
            errorMessage = "There are no valid Connected recipients."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            if case .list(let list) = request {
                guard connectedEnabled, BackendEnvironment.shared.isConnected,
                      BackendConfig.isConfigured, NetworkManager.shared.baseURL != nil else {
                    errorMessage = "Connect to Études Connected to send this list."
                    return
                }
                let service = BackendEnvironment.shared.connectedAttachments
                let reference = try await ConnectedListUpload.upload(list.payload, using: service)
                // Each explicit send is an independent snapshot, as for existing attachments.
                try await service.deliver(reference, to: recipients).get()
                dismiss()
                return
            }
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


private struct ConnectedAttachmentFileExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}
}

struct ReceivedConnectedAttachmentDetailView: View {
    let attachment: ConnectedAttachment

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store =
        ReceivedConnectedAttachmentStore.shared

    @State private var localURL: URL?
    @State private var listPayload: ConnectedListPayload?
    @State private var listOwnerScope: String?
    @State private var listLoadFailed = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var fileExportURL: URL?
    @State private var showFileExporter = false

    var body: some View {
        Group {
            if attachment.isList {
                if let listPayload {
                    ReceivedListPreview(payload: listPayload)
                } else if listLoadFailed {
                    VStack(spacing: Theme.Spacing.m) {
                        Text("This list could not be opened.").font(Theme.Text.body)
                        Button("Try Again") { Task { await loadAttachment() } }
                    }
                } else {
                    ProgressView("Downloading…")
                }
            } else if let localURL {
                AttachmentViewerView(
                    imageURLs: attachmentKind == .image ? [localURL] : [],
                    startIndex: 0,
                    videoURLs: attachmentKind == .video ? [localURL] : [],
                    audioURLs: attachmentKind == .audio ? [localURL] : [],
                    pdfURLs: attachmentKind == .pdf ? [localURL] : [],
                    titleForURL: { _, _ in
                        attachment.attachmentName ?? attachment.filename
                    },
                    isReadOnly: true,
                    canShare: false,
                    showsDismissButton: false
                )
            } else {
                ProgressView("Downloading…")
            }
        }
        .navigationTitle(listPayload?.name ?? attachment.attachmentName ?? attachment.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let adoptionAction {
                    Button(adoptionAction.title) {
                        Task {
                            await performAdoptionAction(adoptionAction)
                        }
                    }
                    .disabled(isDeleting || (attachment.isList && listPayload == nil))
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isDeleting)
                .accessibilityLabel(attachment.isList ? "Delete received list" : "Delete attachment")
            }
        }
        .task {
            if attachment.viewedAt == nil {
                await store.markViewed(attachment)
            }

            await loadAttachment()
        }
        .sheet(isPresented: $showFileExporter) {
            if let fileExportURL {
                ConnectedAttachmentFileExporter(url: fileExportURL)
            }
        }
        .confirmationDialog(
            attachment.isList ? "Delete this received list?" : "Delete this shared attachment?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    defer { isDeleting = false }
                    if await store.delete(attachment) {
                        dismiss()
                    } else {
                        errorMessage = store.errorMessage
                    }
                }
            }
        } message: {
            if attachment.isList {
                Text("This removes the received delivery only. The sender’s original and any copy you saved to Lists are kept.")
            }
        }
        .alert(
            attachment.isList ? "Couldn’t Complete List Action" : "Couldn’t Open Attachment",
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
        .alert(
            "Saved",
            isPresented: Binding(
                get: { successMessage != nil },
                set: {
                    if !$0 {
                        successMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
    }

    private enum AdoptionAction {
        case scores
        case photos
        case files
        case lists

        var title: String {
            switch self {
            case .scores: return "Add to Scores"
            case .photos: return "Save to Photos"
            case .files: return "Save to Files"
            case .lists: return "Save to Lists"
            }
        }
    }

    private var adoptionAction: AdoptionAction? {
        if attachment.isList { return .lists }
        switch attachmentKind {
        case .pdf: return .scores
        case .image, .video: return .photos
        case .audio: return .files
        case .file: return nil
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

    private func performAdoptionAction(_ action: AdoptionAction) async {
        switch action {
        case .scores:
            await saveToScores()
        case .photos:
            await saveToPhotos()
        case .files:
            await saveToFiles()
        case .lists:
            saveToLists()
        }
    }

    private var currentListOwnerScope: String {
        if let id = PersistenceController.shared.currentUserID,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return id }
        return "device"
    }

    private func loadAttachment() async {
        listLoadFailed = false
        let owner = currentListOwnerScope
        do {
            let url = try await store.localURL(for: attachment)
            if attachment.isList {
                guard currentListOwnerScope == owner else { throw ConnectedAttachmentError.missingUserID }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= ConnectedListPayload.maxBytes else { throw ConnectedListError.tooLarge }
                listPayload = try ConnectedListPayload.decode(Data(contentsOf: url))
                listOwnerScope = owner
            }
            localURL = url
        } catch {
            listLoadFailed = true
            errorMessage = error.localizedDescription
        }
    }

    private func saveToLists() {
        do {
            guard let listPayload, let listOwnerScope, listOwnerScope == currentListOwnerScope else {
                throw ConnectedListError.invalidList
            }
            _ = try SavedListLibrary.adopt(listPayload, sourceSendID: attachment.id, ownerScope: listOwnerScope)
            // Adoption is local and private. No saved-to-Scores marker or sender progress.
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedLocalURL() async throws -> URL {
        if let localURL {
            return localURL
        }

        return try await store.localURL(for: attachment)
    }

    private func saveToScores() async {
        do {
            let url = try await resolvedLocalURL()

            _ = try ScoreLibraryStore.shared.importPDF(
                from: url,
                displayName: attachment.attachmentName ?? attachment.filename,
                sourceAttachmentID: attachment.id // C-5
            )

            await store.markSavedToScores(attachment)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveToPhotos() async {
        do {
            let url = try await resolvedLocalURL()
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

            guard status == .authorized || status == .limited else {
                throw ConnectedAttachmentAdoptionError.photoLibraryAccessDenied
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    switch attachmentKind {
                    case .image:
                        PHAssetChangeRequest.creationRequestForAssetFromImage(
                            atFileURL: url
                        )
                    case .video:
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(
                            atFileURL: url
                        )
                    default:
                        break
                    }
                } completionHandler: { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(
                            throwing: ConnectedAttachmentAdoptionError.photoSaveFailed
                        )
                    }
                }
            }

            successMessage = attachmentKind == .video
                ? "Video saved to Photos."
                : "Photo saved to Photos."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveToFiles() async {
        do {
            let sourceURL = try await resolvedLocalURL()

            let rawName = attachment.attachmentName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (rawName?.isEmpty == false)
                ? rawName!
                : sourceURL.deletingPathExtension().lastPathComponent

            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(displayName)
                .appendingPathExtension(sourceURL.pathExtension)

            if FileManager.default.fileExists(atPath: exportURL.path) {
                try? FileManager.default.removeItem(at: exportURL)
            }

            try FileManager.default.copyItem(at: sourceURL, to: exportURL)

            fileExportURL = exportURL
            showFileExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ConnectedAttachmentAdoptionError: LocalizedError {
    case photoLibraryAccessDenied
    case photoSaveFailed

    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Études doesn’t have permission to add items to your Photos library."
        case .photoSaveFailed:
            return "The attachment couldn’t be saved to Photos."
        }
    }
}


private struct ReceivedListPreview: View {
    let payload: ConnectedListPayload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(payload.items.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        if line.type == .item {
                            Image(systemName: "circle")
                                .foregroundStyle(Theme.Colors.secondaryText)
                                .accessibilityHidden(true)
                        }
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(line.type == .header ? Theme.Text.body.weight(.medium) : Theme.Text.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(line.type == .header ? .isHeader : [])
                    }
                    .padding(Theme.Spacing.m)
                    if index < payload.items.count - 1 { Divider().padding(.horizontal, Theme.Spacing.m) }
                }
            }
            .connectedShareCard()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .appBackground()
    }
}
