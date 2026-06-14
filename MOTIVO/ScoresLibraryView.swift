// CHANGE-ID: 20260614_163800_ScoresPhase2B_UnifiedActiveViewer
// SCOPE: Scores V1 Phase 2B — remove the library-owned PDF viewer path so first-open score selection hands off to the Timer-owned active-score viewer with Timer + Library controls immediately. No attachment PDF viewer, store, AppRoute, page restoration, PRDV/AESV/SDV changes.
// SEARCH-TOKEN: 20260614_163800_SCORES_PHASE2B_UNIFIED_ACTIVE_VIEWER

// CHANGE-ID: 20260614_154500_ScoresPhase2_LibraryViewer
// SCOPE: Scores V1 Phase 2 — tapping or resuming a library score marks it active and opens PDFScoreView; Close clears active score. No session attachment, AppRoute, or PDF page restoration changes.
// SEARCH-TOKEN: 20260614_154500_SCORES_PHASE2_LIBRARY_VIEWER

// CHANGE-ID: 20260614_145200_ScoresPhase1_LibraryView
// SCOPE: Scores V1 Phase 1 — dedicated local Scores Library UI with search, PDF import, Scan Music PDF creation, rename, favourite, delete, and active-score card shell. No session attachment, backend, AppRoute, or PDF viewer changes.
// SEARCH-TOKEN: 20260614_145200_SCORES_PHASE1_LIBRARY_VIEW

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import VisionKit

struct ScoresLibraryView: View {
    @Environment(\.dismiss) private var dismiss

    private let onOpenActiveScore: ((ScoreLibraryItem) -> Void)?

    init(onOpenActiveScore: ((ScoreLibraryItem) -> Void)? = nil) {
        self.onOpenActiveScore = onOpenActiveScore
    }

    @StateObject private var store = ScoreLibraryStore.shared

    @State private var searchText: String = ""
    @State private var showAddOptions: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showScanner: Bool = false
    @State private var scannedPDFDataPendingName: Data? = nil
    @State private var scannedScoreTitle: String = ""
    @State private var showScannedScoreNamePrompt: Bool = false
    @State private var renameTarget: ScoreLibraryItem? = nil
    @State private var renameDraft: String = ""
    @State private var deleteTarget: ScoreLibraryItem? = nil
    @State private var errorMessage: String? = nil

    private var visibleItems: [ScoreLibraryItem] {
        store.filteredItems(matching: searchText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    searchField

                    if let activeItem = store.activeItem {
                        activeScoreSection(activeItem)
                    }

                    scoreListSection
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .appBackground()
            .navigationTitle("Scores")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddOptions = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add score")
                }
            }
            .confirmationDialog("Add Score", isPresented: $showAddOptions, titleVisibility: .visible) {
                Button("Import PDF") {
                    showFileImporter = true
                }

                Button("Scan Music") {
                    showScanner = true
                }

                Button("Cancel", role: .cancel) { }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        _ = try store.importPDF(from: url)
                    } catch {
                        errorMessage = "Couldn’t import that PDF."
                    }
                case .failure:
                    errorMessage = "Couldn’t import that PDF."
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScoreDocumentScanner(
                    onCancel: {
                        showScanner = false
                    },
                    onPDFCreated: { data in
                        showScanner = false
                        scannedPDFDataPendingName = data
                        scannedScoreTitle = ""
                        showScannedScoreNamePrompt = true
                    }
                )
                .ignoresSafeArea()
            }
            .alert("Name Score", isPresented: $showScannedScoreNamePrompt) {
                TextField("Score title", text: $scannedScoreTitle)
                    .textInputAutocapitalization(.words)

                Button("Cancel", role: .cancel) {
                    scannedPDFDataPendingName = nil
                    scannedScoreTitle = ""
                }

                Button("Save") {
                    saveScannedScore()
                }
                .disabled(scannedScoreTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Give this scanned score a library title.")
            }
            .alert("Rename Score", isPresented: renameBinding) {
                TextField("Score title", text: $renameDraft)
                    .textInputAutocapitalization(.words)

                Button("Cancel", role: .cancel) {
                    renameTarget = nil
                    renameDraft = ""
                }

                Button("Save") {
                    if let renameTarget {
                        store.rename(renameTarget, to: renameDraft)
                    }
                    renameTarget = nil
                    renameDraft = ""
                }
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("This changes the library title only. It does not rename the source file.")
            }
            .confirmationDialog(
                "Delete Score?",
                isPresented: deleteBinding,
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { item in
                Button("Delete", role: .destructive) {
                    store.delete(item)
                    deleteTarget = nil
                }

                Button("Cancel", role: .cancel) {
                    deleteTarget = nil
                }
            } message: { item in
                Text("Remove \"\(item.title)\" from the Scores library? Journal attachments already saved elsewhere will not be affected.")
            }
            .alert("Scores", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.secondaryText)

            TextField("Search scores", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(Theme.Text.body)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func activeScoreSection(_ item: ScoreLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Currently Active")
                .font(Theme.Text.meta.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondaryText)

            HStack(spacing: Theme.Spacing.m) {
                ScoreThumbnailView(url: store.url(for: item), page: item.thumbnailPage)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(Theme.Text.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(pageCountLabel(for: item))
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                Spacer(minLength: 0)

                Button("Resume") {
                    openScore(item)
                }
                .font(Theme.Text.meta.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)

                Button("Close") {
                    store.clearActiveScore()
                }
                .font(Theme.Text.meta.weight(.semibold))
                .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .cardSurface()
    }

    private var scoreListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Library")
                    .font(Theme.Text.meta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                if !store.items.isEmpty {
                    Text("\(visibleItems.count)")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            if visibleItems.isEmpty {
                emptyState
            } else {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(visibleItems) { item in
                        scoreRow(item)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No scores yet" : "No matching scores")
                .font(Theme.Text.body.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Import a PDF or scan printed music to create a local practice library.")
                .font(Theme.Text.meta)
                .foregroundStyle(Theme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func scoreRow(_ item: ScoreLibraryItem) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ScoreThumbnailView(url: store.url(for: item), page: item.thumbnailPage)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(Theme.Text.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if item.isFavourite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .accessibilityLabel("Favourite")
                    }
                }

                Text(pageCountLabel(for: item))
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    renameTarget = item
                    renameDraft = item.title
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    store.toggleFavourite(item)
                } label: {
                    Label(item.isFavourite ? "Remove Favourite" : "Favourite", systemImage: item.isFavourite ? "star.slash" : "star")
                }

                Button(role: .destructive) {
                    deleteTarget = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Score actions")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            openScore(item)
        }
        .cardSurface()
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { isPresented in
                if !isPresented {
                    renameTarget = nil
                    renameDraft = ""
                }
            }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { isPresented in
                if !isPresented {
                    deleteTarget = nil
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func openScore(_ item: ScoreLibraryItem) {
        store.markOpened(item)
        onOpenActiveScore?(item)
    }

    private func pageCountLabel(for item: ScoreLibraryItem) -> String {
        item.pageCount == 1 ? "1 page" : "\(item.pageCount) pages"
    }

    private func saveScannedScore() {
        guard let data = scannedPDFDataPendingName else { return }
        do {
            _ = try store.addScannedPDF(data: data, title: scannedScoreTitle)
            scannedPDFDataPendingName = nil
            scannedScoreTitle = ""
        } catch {
            errorMessage = "Couldn’t save that scanned score."
        }
    }
}

private struct ScoreThumbnailView: View {
    let url: URL
    let page: Int

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Color.secondary.opacity(0.10))

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(width: 56, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .task(id: url.path + ":\(page)") {
            thumbnail = nil
            let targetURL = url
            let targetPage = page
            let image = await Task.detached(priority: .utility) {
                AttachmentStore.generatePDFThumbnail(
                    url: targetURL,
                    size: CGSize(width: 160, height: 220),
                    page: targetPage
                )
            }.value
            await MainActor.run {
                thumbnail = image
            }
        }
    }
}

private struct ScoreDocumentScanner: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onPDFCreated: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, onPDFCreated: onPDFCreated)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCancel: () -> Void
        let onPDFCreated: (Data) -> Void

        init(onCancel: @escaping () -> Void, onPDFCreated: @escaping (Data) -> Void) {
            self.onCancel = onCancel
            self.onPDFCreated = onPDFCreated
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let data = makePDFData(from: scan)
            onPDFCreated(data)
        }

        private func makePDFData(from scan: VNDocumentCameraScan) -> Data {
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

            return renderer.pdfData { context in
                for pageIndex in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: pageIndex)
                    context.beginPage()

                    let imageSize = image.size
                    let scale = min(pageRect.width / max(imageSize.width, 1), pageRect.height / max(imageSize.height, 1))
                    let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                    let drawOrigin = CGPoint(
                        x: (pageRect.width - drawSize.width) / 2,
                        y: (pageRect.height - drawSize.height) / 2
                    )
                    image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
                }
            }
        }
    }
}
