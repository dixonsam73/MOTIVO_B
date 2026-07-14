// CHANGE-ID: 20260714_ConnectedAttachmentSharing_Phase1_UI
// SCOPE: Reusable PDF attachment destination/page/recipient flow and recipient PDF detail UI.
// No post, feed, messaging, or AttachmentViewerView integration.

import SwiftUI
import PDFKit
import UIKit

struct ConnectedScoreShareRequest: Identifiable {
    let id = UUID()
    let scoreID: UUID
    let title: String
    let url: URL
    let currentPage: Int
}

struct NativeActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

struct ScoreAttachmentShareFlow: View {
    let request: ConnectedScoreShareRequest
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

    private enum Route {
        case destination
        case pageScope
        case person
        case ensemble
    }

    private var pageCount: Int {
        max(PDFDocument(url: request.url)?.pageCount ?? 1, 1)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch route {
                case .destination:
                    destinationView
                case .pageScope:
                    pageScopeView
                case .person:
                    personView
                case .ensemble:
                    ensembleView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(route == .destination ? "Cancel" : "Back") {
                        if route == .destination {
                            dismiss()
                        } else {
                            route = route == .person || route == .ensemble
                                ? .pageScope
                                : .destination
                        }
                    }
                }
            }
        }
        .sheet(
            isPresented: $showPageSelection,
            onDismiss: {
                if let selectedPages, !selectedPages.isEmpty {
                    continueAfterScope()
                }
            }
        ) {
            PDFPageSelectionSheet(
                pageCount: pageCount,
                selectedPages: $selectedPages
            )
        }
        .alert(
            "Couldn’t Share",
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

    private var navigationTitle: String {
        switch route {
        case .destination:
            return "Share with"
        case .pageScope:
            return "What would you like to share?"
        case .person:
            return "Person"
        case .ensemble:
            return "Ensemble"
        }
    }

    private var destinationView: some View {
        List {
            if connectedEnabled {
                Button {
                    chosenDestination = .person
                    route = .pageScope
                } label: {
                    Label("Person…", systemImage: "person")
                }

                Button {
                    chosenDestination = .ensemble
                    route = .pageScope
                } label: {
                    Label("Ensemble…", systemImage: "person.3")
                }
            }

            Section {
                Button {
                    onIOSShare(request.url)
                    dismiss()
                } label: {
                    Label(
                        "Share via iOS…",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        }
    }

    private var pageScopeView: some View {
        List {
            Button {
                selectedPages = nil
                continueAfterScope()
            } label: {
                scopeRow("Entire document", selected: false)
            }

            Button {
                selectedPages = [max(request.currentPage, 1)]
                continueAfterScope()
            } label: {
                scopeRow("Current page", selected: false)
            }

            Button {
                selectedPages = nil
                showPageSelection = true
            } label: {
                scopeRow("Selected pages…", selected: false)
            }
        }
    }

    private func scopeRow(
        _ title: String,
        selected: Bool
    ) -> some View {
        HStack {
            Image(
                systemName: selected
                    ? "largecircle.fill.circle"
                    : "circle"
            )

            Text(title)

            Spacer()
        }
    }

    private func continueAfterScope() {
        route = chosenDestination == .ensemble
            ? .ensemble
            : .person

        Task {
            await loadRecipients()
        }
    }

    private var validFollowerIDs: [String] {
        followStore.followers.sorted()
    }

    private var personView: some View {
        List {
            if isLoadingRecipients {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            ForEach(validFollowerIDs, id: \.self) { id in
                let account = directory[id]

                Button {
                    Task {
                        await send(to: [id])
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account?.displayName ?? "Connected musician")

                        if let accountID = account?.accountID {
                            Text("@\(accountID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isSending || account == nil)
            }

            if !isLoadingRecipients && validFollowerIDs.isEmpty {
                Text("No Connected people are available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ensembleView: some View {
        List {
            ForEach(ensembleStore.ensembles) { ensemble in
                let recipients = validRecipients(for: ensemble)

                Button {
                    Task {
                        await send(to: recipients)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ensemble.name)

                        Text(
                            "\(recipients.count) "
                            + (recipients.count == 1 ? "person" : "people")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .disabled(isSending || recipients.isEmpty)
            }

            if ensembleStore.ensembles.isEmpty {
                Text("No Ensembles are available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func validRecipients(
        for ensemble: Ensemble
    ) -> [String] {
        let approved = Set(followStore.followers)

        return Array(
            Set(
                ensemble.memberUserIDs.map {
                    $0.lowercased()
                }
            )
        )
        .filter {
            approved.contains($0) && directory[$0] != nil
        }
        .sorted()
    }

    private func loadRecipients() async {
        await followStore.refreshFromBackendIfPossible()

        let ids = Array(
            Set(
                followStore.followers.union(
                    ensembleStore.ensembles.flatMap {
                        $0.memberUserIDs
                    }
                )
            )
        )
        .sorted()

        guard !ids.isEmpty else {
            return
        }

        isLoadingRecipients = true

        defer {
            isLoadingRecipients = false
        }

        if case .success(let map) =
            await AccountDirectoryService.shared.resolveAccounts(
                userIDs: ids
            ) {
            directory = map
        }
    }

    private func preparedPDF() throws -> (URL, Int) {
        guard let pages = selectedPages, !pages.isEmpty else {
            return (request.url, pageCount)
        }

        let url = try PDFSubsetExporter.export(
            from: request.url,
            selectedPages: pages
        )

        return (url, pages.count)
    }

    private func send(to recipients: [String]) async {
        guard !recipients.isEmpty else {
            errorMessage = "There are no valid Connected recipients."
            return
        }

        isSending = true

        defer {
            isSending = false
        }

        do {
            let (url, count) = try preparedPDF()

            let filename = request.title
                .lowercased()
                .hasSuffix(".pdf")
                ? request.title
                : request.title + ".pdf"

            switch await BackendEnvironment.shared
                .connectedAttachments
                .uploadPDF(
                    localURL: url,
                    filename: filename,
                    pageCount: count
                ) {
            case .failure(let error):
                throw error

            case .success(let reference):
                switch await BackendEnvironment.shared
                    .connectedAttachments
                    .deliver(
                        reference,
                        to: recipients
                    ) {
                case .success:
                    dismiss()

                case .failure(let error):
                    throw error
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
                PDFScoreView(
                    url: localURL,
                    initialPage: 1,
                    background: Color(.systemBackground),
                    onPageChange: { _ in }
                )
            } else {
                ProgressView("Downloading…")
            }
        }
        .navigationTitle(attachment.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Save to Scores") {
                    Task {
                        await saveToScores()
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
