//
//  ManuscriptPadView.swift
//  MOTIVO
//
//  The manuscript sketch pad: digital manuscript paper to draw on by finger
//  or Pencil. One page. No recognition, engraving or playback.
//
//  The page is a fixed size and the staves never move; the window only
//  changes how much of it is seen. Two fingers move and zoom the page.
//
//  Saving hands back the finished sketch as PDF data (`ManuscriptSketchFile`),
//  which carries the drawing so the pad can reopen it.
//

import SwiftUI
import PencilKit

// MARK: - Paper under the ink

/// The printed paper, placed behind the ink inside the canvas so the two
/// move and zoom as one page.
final class ManuscriptPaperUIView: UIView {
    var paper: ManuscriptPaper { didSet { setNeedsDisplay() } }

    init(paper: ManuscriptPaper) {
        self.paper = paper
        super.init(frame: CGRect(origin: .zero, size: ManuscriptPaper.pageSize))
        isOpaque = true
        backgroundColor = .white
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        ManuscriptPaperRenderer.draw(paper, in: context)
    }
}

/// Reports its layout, so the page can be fitted to the window it is in.
final class ManuscriptCanvasUIView: PKCanvasView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

// MARK: - Undo and redo, from outside the canvas

@MainActor
final class ManuscriptPadController: ObservableObject {
    weak var canvas: PKCanvasView?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    func undo() { canvas?.undoManager?.undo(); refresh() }
    func redo() { canvas?.undoManager?.redo(); refresh() }

    func refresh() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }
}

// MARK: - The canvas

enum ManuscriptPadTool: Equatable {
    case pen(width: CGFloat)
    case eraser

    static let penWidths: [CGFloat] = [1.6, 3, 5.5]

    var pencilKitTool: PKTool {
        switch self {
        case .pen(let width): return PKInkingTool(.pen, color: .black, width: width)
        case .eraser: return PKEraserTool(.vector)
        }
    }
}

struct ManuscriptCanvas: UIViewRepresentable {
    let paper: ManuscriptPaper
    @Binding var drawing: PKDrawing
    let tool: ManuscriptPadTool
    let controller: ManuscriptPadController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ManuscriptCanvasUIView {
        let canvas = ManuscriptCanvasUIView()
        // The page is always white paper with dark ink, whatever the appearance.
        canvas.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.drawing = drawing
        canvas.tool = tool.pencilKitTool
        canvas.contentSize = ManuscriptPaper.pageSize
        canvas.maximumZoomScale = 4
        canvas.minimumZoomScale = 0.25
        canvas.bouncesZoom = true
        canvas.alwaysBounceVertical = true
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.delegate = context.coordinator

        let paperView = ManuscriptPaperUIView(paper: paper)
        paperView.layer.anchorPoint = .zero
        paperView.layer.position = .zero
        canvas.insertSubview(paperView, at: 0)
        context.coordinator.paperView = paperView
        context.coordinator.canvas = canvas

        canvas.onLayout = { [weak coordinator = context.coordinator] in coordinator?.fitIfNeeded() }
        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: ManuscriptCanvasUIView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.appliedTool != tool {
            canvas.tool = tool.pencilKitTool
            context.coordinator.appliedTool = tool
        }
        if context.coordinator.paperView?.paper != paper { context.coordinator.paperView?.paper = paper }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ManuscriptCanvas
        weak var canvas: ManuscriptCanvasUIView?
        weak var paperView: ManuscriptPaperUIView?
        var appliedTool: ManuscriptPadTool?
        private var fittedWidth: CGFloat = 0

        init(_ parent: ManuscriptCanvas) {
            self.parent = parent
            self.appliedTool = parent.tool
        }

        /// Fits the page's width to the window the first time, and again when
        /// the window's width changes (rotation, a resized window).
        func fitIfNeeded() {
            guard let canvas, canvas.bounds.width > 0, abs(canvas.bounds.width - fittedWidth) > 0.5 else { return }
            fittedWidth = canvas.bounds.width
            let margin: CGFloat = 12
            let fit = (canvas.bounds.width - margin * 2) / ManuscriptPaper.pageSize.width
            canvas.minimumZoomScale = min(fit, 1) * 0.6
            canvas.maximumZoomScale = max(fit * 4, 4)
            canvas.setZoomScale(fit, animated: false)
            place()
            canvas.contentOffset = CGPoint(x: -canvas.contentInset.left, y: -canvas.contentInset.top)
        }

        /// Keeps the paper under the ink at the canvas's zoom, and the page
        /// centred when it is narrower than the window.
        private func place() {
            guard let canvas, let paperView else { return }
            let zoom = canvas.zoomScale
            paperView.transform = CGAffineTransform(scaleX: zoom, y: zoom)
            paperView.contentScaleFactor = canvas.traitCollection.displayScale * max(zoom, 1)
            paperView.setNeedsDisplay()
            let pageWidth = ManuscriptPaper.pageSize.width * zoom
            let side = max((canvas.bounds.width - pageWidth) / 2, 0)
            canvas.contentInset = UIEdgeInsets(top: 12, left: side, bottom: 24, right: side)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { place() }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.drawing = drawing
                self.parent.controller.refresh()
            }
        }
    }
}

// MARK: - The pad

struct ManuscriptPadView: View {
    /// A sketch being reopened; nil for a new one, which starts by choosing its paper.
    let existing: ManuscriptSketch?
    /// Receives the finished sketch as PDF data. Throwing keeps the pad open.
    let onSave: (Data) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var controller = ManuscriptPadController()
    @State private var paper: ManuscriptPaper?
    @State private var drawing: PKDrawing
    @State private var tool: ManuscriptPadTool = .pen(width: ManuscriptPadTool.penWidths[1])
    @State private var confirmDiscard = false
    @State private var saveFailed = false

    init(existing: ManuscriptSketch? = nil, onSave: @escaping (Data) throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        _paper = State(initialValue: existing?.paper)
        _drawing = State(initialValue: existing?.drawing ?? PKDrawing())
    }

    private var hasChanges: Bool {
        if let existing { return drawing.dataRepresentation() != existing.drawing.dataRepresentation() }
        return !drawing.strokes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let paper {
                ManuscriptCanvas(paper: paper, drawing: $drawing, tool: tool, controller: controller)
                    .background(Color(white: colorScheme == .dark ? 0.16 : 0.86))
                toolBar
            } else {
                ManuscriptPaperChooser { paper = $0 }
            }
        }
        .appBackground()
        .confirmationDialog("Discard this sketch?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(existing == nil ? "Discard Sketch" : "Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Drawing", role: .cancel) { }
        }
        .alert("The sketch couldn't be saved.", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nothing was lost. Try again.")
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                if hasChanges { confirmDiscard = true } else { dismiss() }
            }
            .foregroundStyle(.primary)
            Spacer()
            Text(paper == nil ? "Paper" : "Sketch")
                .font(Theme.Text.sectionHeader)
                .foregroundStyle(Theme.Colors.secondaryText)
            Spacer()
            Button("Save") { save() }
                .fontWeight(.semibold)
                .tint(Theme.Colors.primaryAction)
                .disabled(paper == nil || !hasChanges)
        }
        .font(Theme.Text.body)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    private var toolBar: some View {
        HStack(spacing: Theme.Spacing.l) {
            padButton("arrow.uturn.backward", label: "Undo", active: false) { controller.undo() }
                .disabled(!controller.canUndo)
            padButton("arrow.uturn.forward", label: "Redo", active: false) { controller.redo() }
                .disabled(!controller.canRedo)
            Spacer(minLength: 0)
            ForEach(ManuscriptPadTool.penWidths, id: \.self) { width in
                Button {
                    tool = .pen(width: width)
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 4 + width * 2.4, height: 4 + width * 2.4)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.secondary.opacity(tool == .pen(width: width) ? 0.32 : 0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(penLabel(width))
            }
            Spacer(minLength: 0)
            padButton("eraser", label: "Eraser", active: tool == .eraser) { tool = .eraser }
        }
        // Clear of the corner an iPad window is resized from.
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.s)
    }

    private func penLabel(_ width: CGFloat) -> String {
        switch ManuscriptPadTool.penWidths.firstIndex(of: width) {
        case 0: return "Fine pen"
        case 2: return "Broad pen"
        default: return "Medium pen"
        }
    }

    private func padButton(_ systemImage: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.secondary.opacity(active ? 0.32 : 0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func save() {
        guard let paper else { return }
        do {
            let file = try ManuscriptSketchFile.writeVerified(ManuscriptSketch(paper: paper, drawing: drawing))
            defer { try? FileManager.default.removeItem(at: file) }
            try onSave(try Data(contentsOf: file))
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

// MARK: - Choosing the paper

struct ManuscriptPaperChooser: View {
    let onChoose: (ManuscriptPaper) -> Void

    private struct Choice: Identifiable {
        let id: String
        let paper: ManuscriptPaper
    }

    private let choices: [Choice] = [
        Choice(id: "Treble clef", paper: ManuscriptPaper(kind: .singleStaff, clef: .treble)),
        Choice(id: "Bass clef", paper: ManuscriptPaper(kind: .singleStaff, clef: .bass)),
        Choice(id: "Alto clef", paper: ManuscriptPaper(kind: .singleStaff, clef: .alto)),
        Choice(id: "No clef", paper: ManuscriptPaper(kind: .singleStaff, clef: .none)),
        Choice(id: "Piano", paper: ManuscriptPaper(kind: .piano, clef: .none)),
        Choice(id: "Plain", paper: ManuscriptPaper(kind: .plain, clef: .none)),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Theme.Spacing.l)], spacing: Theme.Spacing.l) {
                ForEach(choices) { choice in
                    Button {
                        onChoose(choice.paper)
                    } label: {
                        VStack(spacing: Theme.Spacing.s) {
                            Image(uiImage: Self.preview(of: choice.paper))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                            Text(choice.id)
                                .font(Theme.Text.body)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    /// The top of the page, large enough to tell the papers apart.
    static func preview(of paper: ManuscriptPaper) -> UIImage {
        let crop = CGRect(x: 30, y: 44, width: 240, height: 170)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { renderer in
            let context = renderer.cgContext
            context.translateBy(x: -crop.minX, y: -crop.minY)
            ManuscriptPaperRenderer.draw(paper, in: context)
        }
    }
}
