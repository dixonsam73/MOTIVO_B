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
    /// Called when the viewer disappears, AFTER its pending page and failure
    /// reports have been withdrawn — so close-time work (such as flushing page
    /// tracking) can never be followed by a late report from this viewer.
    var onClose: (() -> Void)? = nil

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
        .onAppear {
            controller.viewDidAppear()
        }
        .onDisappear {
            controller.viewDidDisappear()
            onClose?()
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

final class PDFScoreController: ObservableObject {
    private weak var pdfView: PDFView?
    private weak var coordinator: PDFScoreRepresentable.Coordinator?

    /// Owns the ordering of the viewer's outward effects for its whole lifetime,
    /// so closing the viewer can withdraw pending work before the caller flushes.
    let effects: PDFScoreEffectGate

    init(effects: PDFScoreEffectGate = PDFScoreEffectGate()) {
        self.effects = effects
    }

    func register(_ pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func attach(_ coordinator: PDFScoreRepresentable.Coordinator) {
        self.coordinator = coordinator
    }

    /// The viewer closed: withdraw pending reports. Close-time work runs after this.
    func viewDidDisappear() {
        effects.close()
    }

    /// The viewer is visible again. Only after a close: reports that close withdrew
    /// were already counted as sent, so the current page (and any failure) is
    /// reported afresh — never the initial page restored again, and never an
    /// obsolete queued report replayed.
    func viewDidAppear() {
        guard effects.reopen() else { return }
        coordinator?.reappeared()
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

/// Orders the viewer's outward effects — binding writes, `onPageChange`,
/// `onFailure` — so none is published from inside SwiftUI's view-update pass.
///
/// - Outside an update, with nothing pending, an effect runs immediately (a swipe
///   behaves as it always has).
/// - Otherwise it is queued and runs, in order, in a drain scheduled on the main
///   queue. While anything is queued, scheduled or draining, later effects queue
///   too, so a newer event can never overtake an older one.
/// - Each effect carries the epoch it was created in. `invalidate()` (document
///   replaced) and `close()` (viewer closed) advance the epoch and drop the queue,
///   so obsolete state is never delivered.
final class PDFScoreEffectGate {
    typealias Scheduler = (@escaping () -> Void) -> Void

    private(set) var epoch = 0
    private(set) var isClosed = false
    private var updateDepth = 0
    private var queue: [(epoch: Int, effect: () -> Void)] = []
    private var drainScheduled = false
    private var isDraining = false
    private let schedule: Scheduler

    init(schedule: @escaping Scheduler = { DispatchQueue.main.async(execute: $0) }) {
        self.schedule = schedule
    }

    var isInViewUpdate: Bool { updateDepth > 0 }

    func beginViewUpdate() { updateDepth += 1 }
    func endViewUpdate() { updateDepth = max(0, updateDepth - 1) }

    func run(_ effect: @escaping () -> Void) {
        guard !isClosed else { return }
        if updateDepth == 0, queue.isEmpty, !drainScheduled, !isDraining {
            effect()
            return
        }
        queue.append((epoch, effect))
        scheduleDrainIfNeeded()
    }

    func drain() {
        drainScheduled = false
        guard !isDraining else { return }
        guard updateDepth == 0 else { return scheduleDrainIfNeeded() }
        isDraining = true
        defer { isDraining = false }
        while !queue.isEmpty {
            let item = queue.removeFirst()
            guard !isClosed, item.epoch == epoch else { continue }
            item.effect()   // anything it causes to run is appended and runs after it
        }
    }

    /// The document was replaced: nothing produced for the old one is delivered.
    func invalidate() {
        epoch += 1
        queue.removeAll()
    }

    /// The viewer closed. Idempotent. Called before the caller's own close work.
    func close() {
        invalidate()
        isClosed = true
    }

    /// Returns whether the gate had been closed.
    @discardableResult
    func reopen() -> Bool {
        defer { isClosed = false }
        return isClosed
    }

    private func scheduleDrainIfNeeded() {
        guard !drainScheduled, !isDraining else { return }
        drainScheduled = true
        schedule { [weak self] in self?.drain() }
    }
}

struct PDFScoreRepresentable: UIViewRepresentable {
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
            onFailure: onFailure,
            effects: controller.effects
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

        controller.register(pdfView)
        controller.attach(context.coordinator)
        context.coordinator.didMake(
            pdfView: pdfView,
            url: url,
            selectedPages: selectedPages,
            initialPage: initialPage,
            onPageChange: onPageChange,
            onFailure: onFailure
        )
        context.coordinator.startObserving()
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        controller.register(pdfView)
        context.coordinator.didUpdate(
            url: url,
            selectedPages: selectedPages,
            initialPage: initialPage,
            onPageChange: onPageChange,
            onFailure: onFailure
        )
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.dismantle()
    }

    static func makeDocument(url: URL, selectedPages: [Int]?) -> PDFDocument? {
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
        private var onFailure: (() -> Void)?
        private var hasRestoredInitialPage = false
        private var lastReportedPage: Int?
        private var hasReportedFailure = false
        let effects: PDFScoreEffectGate

        weak var pdfView: PDFView?
        var loadedURL: URL?
        var loadedSelectedPages: [Int]?

        init(
            pageIndex: Binding<Int>,
            pageCount: Binding<Int>,
            initialPage: Int?,
            onPageChange: ((Int) -> Void)?,
            onFailure: (() -> Void)?,
            effects: PDFScoreEffectGate
        ) {
            self._pageIndex = pageIndex
            self._pageCount = pageCount
            self.initialPage = initialPage
            self.onPageChange = onPageChange
            self.onFailure = onFailure
            self.effects = effects
        }

        /// `makeUIView`'s work after configuring the view, inside the update window.
        func didMake(pdfView: PDFView, url: URL, selectedPages: [Int]?, initialPage: Int?,
                     onPageChange: ((Int) -> Void)?, onFailure: (() -> Void)?) {
            effects.beginViewUpdate()
            defer { effects.endViewUpdate() }

            pdfView.document = PDFScoreRepresentable.makeDocument(url: url, selectedPages: selectedPages)
            pdfView.autoScales = true
            pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit

            self.pdfView = pdfView
            loadedURL = url
            loadedSelectedPages = PDFSelectedPagesStore.sanitized(selectedPages)
            updateCallbacks(initialPage: initialPage, onPageChange: onPageChange, onFailure: onFailure)
            restoreInitialPageIfNeeded()
            refreshPageState()
        }

        /// `updateUIView`'s work, inside the update window.
        func didUpdate(url: URL, selectedPages: [Int]?, initialPage: Int?,
                       onPageChange: ((Int) -> Void)?, onFailure: (() -> Void)?) {
            effects.beginViewUpdate()
            defer { effects.endViewUpdate() }

            updateCallbacks(initialPage: initialPage, onPageChange: onPageChange, onFailure: onFailure)

            let sanitizedPages = PDFSelectedPagesStore.sanitized(selectedPages)
            guard loadedURL != url || loadedSelectedPages != sanitizedPages else {
                restoreInitialPageIfNeeded()
                refreshPageState()
                return
            }
            guard let pdfView else { return }

            loadedURL = url
            loadedSelectedPages = sanitizedPages
            resetInitialPageRestoration()
            pdfView.document = PDFScoreRepresentable.makeDocument(url: url, selectedPages: sanitizedPages)
            pdfView.autoScales = true
            pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
            restoreInitialPageIfNeeded()
            refreshPageState()
        }

        func startObserving() {
            guard let pdfView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: Notification.Name.PDFViewPageChanged,
                object: pdfView
            )
        }

        /// The viewer reappeared after a close. Report the CURRENT state afresh,
        /// through the update window so nothing is published synchronously here.
        func reappeared() {
            lastReportedPage = nil
            hasReportedFailure = false
            effects.beginViewUpdate()
            defer { effects.endViewUpdate() }
            refreshPageState()
        }

        /// Backstop for the view's own close: idempotent.
        func dismantle() {
            if let pdfView {
                NotificationCenter.default.removeObserver(self, name: Notification.Name.PDFViewPageChanged, object: pdfView)
            }
            effects.close()
        }

        func updateCallbacks(initialPage: Int?, onPageChange: ((Int) -> Void)?, onFailure: (() -> Void)?) {
            self.initialPage = initialPage
            self.onPageChange = onPageChange
            self.onFailure = onFailure
        }

        /// A new document: its reports start afresh, and nothing queued for the old
        /// one is delivered.
        func resetInitialPageRestoration() {
            hasRestoredInitialPage = false
            lastReportedPage = nil
            hasReportedFailure = false
            effects.invalidate()
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

        /// Computes now; publishes through the gate as ONE snapshot, with the
        /// callbacks current at this moment.
        func refreshPageState() {
            guard let pdfView else { return }

            let fittedScale = pdfView.scaleFactorForSizeToFit

            if fittedScale > 0 {
                pdfView.minScaleFactor = fittedScale
            }

            let newIndex: Int
            let newCount: Int
            var report: Int? = nil
            var fail = false

            if let document = pdfView.document {
                newCount = document.pageCount
                if let currentPage = pdfView.currentPage {
                    newIndex = max(0, document.index(for: currentPage))
                } else {
                    newIndex = 0
                }
                let visiblePage = newIndex + 1
                if visiblePage >= 1, visiblePage <= document.pageCount, lastReportedPage != visiblePage {
                    lastReportedPage = visiblePage
                    report = visiblePage
                }
            } else {
                newIndex = 0
                newCount = 0
                if !hasReportedFailure {
                    hasReportedFailure = true
                    fail = true
                }
            }

            let onPageChange = self.onPageChange
            let onFailure = self.onFailure
            effects.run { [weak self] in
                if let self {
                    if self.pageCount != newCount { self.pageCount = newCount }
                    if self.pageIndex != newIndex { self.pageIndex = newIndex }
                }
                if fail { onFailure?() }
                if let report { onPageChange?(report) }
            }
        }
    }
}
