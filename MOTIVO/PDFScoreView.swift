// CHANGE-ID: 20260614_171200_ScoresPhase3A_PageMemory_PDFViewer
// SCOPE: Scores V1 Phase 3A — add optional initial page restoration and page-change reporting for active score page memory. No zoom, viewport, attachment workflow, or UI changes.
// SEARCH-TOKEN: 20260614_171200_SCORES_PHASE3A_PAGE_MEMORY
import SwiftUI
import PDFKit

struct PDFScoreView: View {
    let url: URL
    var selectedPages: [Int]? = nil
    var initialPage: Int? = nil
    var background: Color = Color.clear
    var onPageChange: ((Int) -> Void)? = nil
    var onFailure: (() -> Void)? = nil

    @StateObject private var controller = PDFScoreController()

    @State private var pageIndex: Int = 0
    @State private var pageCount: Int = 0
    @State private var showPageJump = false
    @State private var requestedPage = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()

            PDFScoreRepresentable(
                url: url,
                selectedPages: selectedPages,
                controller: controller,
                pageIndex: $pageIndex,
                pageCount: $pageCount,
                initialPage: initialPage,
                onPageChange: onPageChange,
                onFailure: onFailure
            )
            .ignoresSafeArea()

            if pageCount > 0 {
                Button {
                    requestedPage = "\(pageIndex + 1)"
                    showPageJump = true
                } label: {
                    Text("\(pageIndex + 1) / \(pageCount)")
                        .font(Theme.Text.meta.weight(.semibold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, Theme.Spacing.l)
                .accessibilityLabel("Page \(pageIndex + 1) of \(pageCount)")
                .accessibilityHint("Tap to jump to a page")
            }
        }
        .sheet(isPresented: $showPageJump) {
            pageJumpSheet
        }
    }

    private var pageJumpSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Page number", text: $requestedPage)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Enter a page between 1 and \(max(pageCount, 1)).")
                }
            }
            .navigationTitle("Go to Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPageJump = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        let trimmedPage = requestedPage.trimmingCharacters(in: .whitespacesAndNewlines)

                        if let page = Int(trimmedPage),
                           controller.goToPage(page) {
                            pageIndex = page - 1
                        }

                        showPageJump = false
                    }
                    .disabled(!isRequestedPageValid)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private var isRequestedPageValid: Bool {
        guard let number = Int(requestedPage.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return number >= 1 && number <= pageCount
    }
}

private final class PDFScoreController: ObservableObject {
    private weak var pdfView: PDFView?

    func register(_ pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func goToPage(_ pageNumber: Int) -> Bool {
        guard pageNumber >= 1 else { return false }
        guard let pdfView,
              let document = pdfView.document,
              pageNumber <= document.pageCount,
              let targetPage = document.page(at: pageNumber - 1)
        else {
            return false
        }

        pdfView.go(to: targetPage)
        return true
    }
}

private struct PDFScoreRepresentable: UIViewRepresentable {
    let url: URL
    let selectedPages: [Int]?
    let controller: PDFScoreController
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    let initialPage: Int?
    var onPageChange: ((Int) -> Void)?
    var onFailure: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pageIndex: $pageIndex,
            pageCount: $pageCount,
            initialPage: initialPage,
            onPageChange: onPageChange,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        pdfView.displaysPageBreaks = false
        pdfView.document = makeDocument(url: url, selectedPages: selectedPages)
        pdfView.autoScales = true
        pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit

        controller.register(pdfView)
        context.coordinator.pdfView = pdfView
        context.coordinator.loadedURL = url
        context.coordinator.loadedSelectedPages = PDFSelectedPagesStore.sanitized(selectedPages)
        context.coordinator.updateCallbacks(initialPage: initialPage, onPageChange: onPageChange)
        context.coordinator.restoreInitialPageIfNeeded()
        context.coordinator.refreshPageState()

        if pdfView.document == nil {
            onFailure?()
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        controller.register(pdfView)
        context.coordinator.updateCallbacks(initialPage: initialPage, onPageChange: onPageChange)

        let sanitizedPages = PDFSelectedPagesStore.sanitized(selectedPages)
        guard context.coordinator.loadedURL != url || context.coordinator.loadedSelectedPages != sanitizedPages else {
            context.coordinator.restoreInitialPageIfNeeded()
            context.coordinator.refreshPageState()
            return
        }

        context.coordinator.loadedURL = url
        context.coordinator.loadedSelectedPages = sanitizedPages
        context.coordinator.resetInitialPageRestoration()
        pdfView.document = makeDocument(url: url, selectedPages: sanitizedPages)
        pdfView.autoScales = true
        pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
        context.coordinator.restoreInitialPageIfNeeded()
        context.coordinator.refreshPageState()

        if pdfView.document == nil {
            onFailure?()
        }
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
    }

    private func makeDocument(url: URL, selectedPages: [Int]?) -> PDFDocument? {
        guard let source = PDFDocument(url: url) else { return nil }
        guard let clean = PDFSelectedPagesStore.sanitized(selectedPages), !clean.isEmpty else {
            return source
        }

        let filtered = PDFDocument()
        var insertIndex = 0

        for pageNumber in clean {
            guard pageNumber >= 1,
                  pageNumber <= source.pageCount,
                  let page = source.page(at: pageNumber - 1)
            else { continue }

            filtered.insert(page, at: insertIndex)
            insertIndex += 1
        }

        return insertIndex > 0 ? filtered : source
    }

    final class Coordinator: NSObject {
        @Binding private var pageIndex: Int
        @Binding private var pageCount: Int
        private var initialPage: Int?
        private var onPageChange: ((Int) -> Void)?
        private let onFailure: (() -> Void)?
        private var hasRestoredInitialPage = false
        private var lastReportedPage: Int?

        weak var pdfView: PDFView?
        var loadedURL: URL?
        var loadedSelectedPages: [Int]?

        init(
            pageIndex: Binding<Int>,
            pageCount: Binding<Int>,
            initialPage: Int?,
            onPageChange: ((Int) -> Void)?,
            onFailure: (() -> Void)?
        ) {
            self._pageIndex = pageIndex
            self._pageCount = pageCount
            self.initialPage = initialPage
            self.onPageChange = onPageChange
            self.onFailure = onFailure
        }

        func updateCallbacks(initialPage: Int?, onPageChange: ((Int) -> Void)?) {
            self.initialPage = initialPage
            self.onPageChange = onPageChange
        }

        func resetInitialPageRestoration() {
            hasRestoredInitialPage = false
            lastReportedPage = nil
        }

        func restoreInitialPageIfNeeded() {
            guard !hasRestoredInitialPage else { return }
            guard let pdfView,
                  let document = pdfView.document,
                  document.pageCount > 0
            else { return }

            hasRestoredInitialPage = true

            guard let initialPage else {
                return
            }

            let boundedPage = min(max(initialPage, 1), document.pageCount)
            guard let targetPage = document.page(at: boundedPage - 1) else {
                return
            }

            pdfView.go(to: targetPage)
        }

        @objc func pageChanged(_ notification: Notification) {
            refreshPageState()
        }

        func refreshPageState() {
            guard let pdfView else { return }

            let fittedScale = pdfView.scaleFactorForSizeToFit

            if fittedScale > 0 {
                pdfView.minScaleFactor = fittedScale
            }
            guard let document = pdfView.document else {
                pageIndex = 0
                pageCount = 0
                onFailure?()
                return
            }

            pageCount = document.pageCount
            let newPageIndex: Int

            if let currentPage = pdfView.currentPage {
                newPageIndex = max(0, document.index(for: currentPage))
            } else {
                newPageIndex = 0
            }

            pageIndex = newPageIndex

            let visiblePage = newPageIndex + 1
            if visiblePage >= 1,
               visiblePage <= document.pageCount,
               lastReportedPage != visiblePage {
                lastReportedPage = visiblePage
                onPageChange?(visiblePage)
            }
        }
    }
}
