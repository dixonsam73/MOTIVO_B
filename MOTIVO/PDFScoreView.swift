import SwiftUI
import PDFKit

struct PDFScoreView: View {
    let url: URL
    var background: Color = Color.clear
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
                controller: controller,
                pageIndex: $pageIndex,
                pageCount: $pageCount,
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
    let controller: PDFScoreController
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    var onFailure: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pageIndex: $pageIndex,
            pageCount: $pageCount,
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
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit

        controller.register(pdfView)
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
        controller.register(pdfView)

        guard context.coordinator.loadedURL != url else {
            context.coordinator.refreshPageState()
            return
        }

        context.coordinator.loadedURL = url
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
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

        init(
            pageIndex: Binding<Int>,
            pageCount: Binding<Int>,
            onFailure: (() -> Void)?
        ) {
            self._pageIndex = pageIndex
            self._pageCount = pageCount
            self.onFailure = onFailure
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
            if let currentPage = pdfView.currentPage {
                pageIndex = max(0, document.index(for: currentPage))
            } else {
                pageIndex = 0
            }
        }
    }
}
