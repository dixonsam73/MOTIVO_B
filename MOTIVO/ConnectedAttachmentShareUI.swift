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
        case .destination: return "Share with"
        case .pageScope: return "What would you like to share?"
        case .person: return "Person"
        case .ensemble: return "Ensemble"
        }
    }

    private var destinationView: some View {
        List {
            if connectedEnabled {
                Button { choose(.person) } label: { Label("Person…", systemImage: "person") }
                Button { choose(.ensemble) } label: { Label("Ensemble…", systemImage: "person.3") }
            }

            Section {
                Button {
                    onIOSShare(request.url)
                    dismiss()
                } label: {
                    Label("Share via iOS…", systemImage: "square.and.arrow.up")
                }
            }
        }
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
        List {
            Button { selectedPages = nil; continueAfterScope() } label: { scopeRow("Entire document") }
            Button {
                if case .score(let score) = request { selectedPages = [max(score.currentPage, 1)] }
                continueAfterScope()
            } label: { scopeRow("Current page") }
            Button { selectedPages = nil; showPageSelection = true } label: { scopeRow("Selected pages…") }
        }
    }

    private func scopeRow(_ title: String) -> some View {
        HStack { Image(systemName: "circle"); Text(title); Spacer() }
    }

    private func continueAfterScope() {
        route = chosenDestination == .ensemble ? .ensemble : .person
        Task { await loadRecipients() }
    }

    private var validFollowerIDs: [String] { followStore.followers.sorted() }

    private var personView: some View {
        List {
            if isLoadingRecipients { ProgressView().frame(maxWidth: .infinity) }
            ForEach(validFollowerIDs, id: \.self) { id in
                let account = directory[id]
                Button { Task { await send(to: [id]) } } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account?.displayName ?? "Connected musician")
                        if let accountID = account?.accountID {
                            Text("@\(accountID)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isSending || account == nil)
            }
            if !isLoadingRecipients && validFollowerIDs.isEmpty {
                Text("No Connected people are available.").foregroundStyle(.secondary)
            }
        }
    }

    private var ensembleView: some View {
        List {
            ForEach(ensembleStore.ensembles) { ensemble in
                let recipients = validRecipients(for: ensemble)
                Button { Task { await send(to: recipients) } } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ensemble.name)
                        Text("\(recipients.count) " + (recipients.count == 1 ? "person" : "people"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(isSending || recipients.isEmpty)
            }
            if ensembleStore.ensembles.isEmpty {
                Text("No Ensembles are available.").foregroundStyle(.secondary)
            }
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
                mimeType: "application/pdf",
                pageCount: preparedPageCount
            )

        case .sessionAttachment(let item):
            return ConnectedAttachmentUploadPayload(
                localURL: item.url,
                filename: item.title,
                mimeType: item.mimeType,
                pageCount: item.pageCount
            )
        }
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
        .navigationTitle(attachment.filename)
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
