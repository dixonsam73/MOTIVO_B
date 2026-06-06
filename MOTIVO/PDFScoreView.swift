import SwiftUI
import PDFKit

struct PDFScoreView: View {
    let url: URL
    var background: Color = Color.clear
    var onFailure: (() -> Void)? = nil

    @State private var pageIndex: Int = 0
    @State private var pageCount: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()

            PDFScoreRepresentable(
                url: url,
                pageIndex: $pageIndex,
                pageCount: $pageCount,
                onFailure: onFailure
            )
            .ignoresSafeArea()

            if pageCount > 0 {
                Text("\(pageIndex + 1) / \(pageCount)")
                    .font(Theme.Text.meta.weight(.semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, Theme.Spacing.l)
                    .accessibilityLabel("Page \(pageIndex + 1) of \(pageCount)")
            }
        }
    }
}

private struct PDFScoreRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    var onFailure: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(pageIndex: $pageIndex, pageCount: $pageCount, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        pdfView.displaysPageBreaks = false
        pdfView.document = PDFDocument(url: url)

        context.coordinator.pdfView = pdfView
        context.coordinator.loadedURL = url
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
        guard context.coordinator.loadedURL != url else {
            context.coordinator.refreshPageState()
            return
        }

        context.coordinator.loadedURL = url
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
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

    final class Coordinator: NSObject {
        @Binding private var pageIndex: Int
        @Binding private var pageCount: Int
        private let onFailure: (() -> Void)?

        weak var pdfView: PDFView?
        var loadedURL: URL?

        init(pageIndex: Binding<Int>, pageCount: Binding<Int>, onFailure: (() -> Void)?) {
            self._pageIndex = pageIndex
            self._pageCount = pageCount
            self.onFailure = onFailure
        }

        @objc func pageChanged(_ notification: Notification) {
            refreshPageState()
        }

        func refreshPageState() {
            guard let pdfView else { return }
            guard let document = pdfView.document else {
                pageIndex = 0
                pageCount = 0
                onFailure?()
                return
            }

            pageCount = document.pageCount
            if let currentPage = pdfView.currentPage {
                pageIndex = max(0, document.index(for: currentPage))
            } else {
                pageIndex = 0
            }
        }
    }
}
