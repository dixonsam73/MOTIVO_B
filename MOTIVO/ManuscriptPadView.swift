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
    /// Counts the changes made in the pad, so "has anything been drawn" and
    /// the recovery copy do not depend on comparing drawings.
    @Binding var revision: Int
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
                self.parent.revision += 1
                self.parent.controller.refresh()
            }
        }
    }
}

// MARK: - The pad

/// What the pad hands over at Save.
struct ManuscriptPadResult {
    /// The sketch as PDF data, carrying its drawing.
    let data: Data
    /// The recovery copy that goes on protecting it until the entry is saved.
    let recoveryKey: String
    let title: String
}

struct ManuscriptPadView: View {
    /// A sketch being reopened; nil for a new one, which starts by choosing its paper.
    let existing: ManuscriptSketch?
    /// Called at once when an already attached sketch is given a title; nil
    /// for a new sketch, whose title goes with it at Save.
    let onRename: ((String) -> Void)?
    /// Receives the finished sketch. Throwing keeps the pad open.
    let onSave: (ManuscriptPadResult) throws -> Void

    static let defaultTitle = "Sketch"
    @State private var title: String
    @State private var titleDraft = ""
    @State private var isNaming = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var controller = ManuscriptPadController()
    @State private var paper: ManuscriptPaper?
    @State private var drawing: PKDrawing
    @State private var revision = 0
    /// How this pad was opened, for recovery. Restoring a copy adopts its key.
    @State private var opening: ManuscriptSketchRecovery.Opening
    /// A sketch left unsaved earlier; the pad waits for the answer before
    /// showing anything to draw on.
    @State private var offered: ManuscriptSketchRecovery.Copy?
    @State private var restoredFromDraft = false
    @State private var tool: ManuscriptPadTool = .pen(width: ManuscriptPadTool.penWidths[1])
    @State private var confirmDiscard = false
    @State private var saveFailed = false
    @State private var keepTask: Task<Void, Never>?

    init(existing: ManuscriptSketch? = nil,
         title: String = ManuscriptPadView.defaultTitle,
         recovery: ManuscriptSketchRecovery.Opening = .new(),
         onRename: ((String) -> Void)? = nil,
         onSave: @escaping (ManuscriptPadResult) throws -> Void) {
        self.existing = existing
        self.onRename = onRename
        self.onSave = onSave
        _title = State(initialValue: title)
        _paper = State(initialValue: existing?.paper)
        _drawing = State(initialValue: existing?.drawing ?? PKDrawing())
        _opening = State(initialValue: recovery)
        _offered = State(initialValue: ManuscriptSketchRecovery.offer(for: recovery))
    }

    private var hasChanges: Bool { revision > 0 || restoredFromDraft }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if offered != nil {
                Color.clear
            } else if let paper {
                ManuscriptCanvas(paper: paper, drawing: $drawing, revision: $revision, tool: tool, controller: controller)
                    .background(Color(white: colorScheme == .dark ? 0.16 : 0.86))
                toolBar
            } else {
                ManuscriptPaperChooser { paper = $0 }
            }
        }
        .appBackground()
        .onChange(of: revision) { _, _ in keepSoon() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { keepNow() } }
        .onDisappear { keepTask?.cancel() }
        .alert("Restore your unfinished sketch?", isPresented: Binding(get: { offered != nil }, set: { _ in })) {
            Button("Restore") {
                if let copy = offered {
                    paper = copy.sketch.paper
                    drawing = copy.sketch.drawing
                    restoredFromDraft = true
                    // It goes on being that sketch's one copy.
                    opening.key = copy.key
                }
                offered = nil
            }
            Button("Discard", role: .destructive) {
                if let copy = offered { ManuscriptSketchRecovery.clear(key: copy.key) }
                // A new sketch may have more than one left behind: one at a time.
                offered = ManuscriptSketchRecovery.offer(for: opening)
            }
            // Decide later: the pad closes and the unsaved sketch is kept.
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("It wasn't saved last time.")
        }
        .confirmationDialog("Discard this sketch?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(existing == nil ? "Discard Sketch" : "Discard Changes", role: .destructive) { leaveWithoutSaving() }
            Button("Keep Drawing", role: .cancel) { }
        }
        .alert("Title", isPresented: $isNaming) {
            TextField(Self.defaultTitle, text: $titleDraft)
            Button("Done") {
                let typed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                title = typed.isEmpty ? Self.defaultTitle : typed
                onRename?(title)
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("The sketch couldn't be saved.", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nothing was lost. Try again.")
        }
    }

    // MARK: Recovery copy

    /// Shortly after the last stroke, so a burst of drawing is one write.
    private func keepSoon() {
        keepTask?.cancel()
        keepTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            keepNow()
        }
    }

    private func keepNow() {
        guard let paper, hasChanges, offered == nil else { return }
        ManuscriptSketchRecovery.keep(ManuscriptSketch(paper: paper, drawing: drawing), key: opening.key, attachment: opening.attachment)
    }

    /// Cancel, or a confirmed discard: the work drawn in this pad is dropped.
    /// A sketch the editor already holds keeps the copy of what it holds.
    private func leaveWithoutSaving() {
        keepTask?.cancel()
        if hasChanges { ManuscriptSketchRecovery.leftWithoutSaving(opening: opening, heldSketch: existing) }
        dismiss()
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                if hasChanges { confirmDiscard = true } else { leaveWithoutSaving() }
            }
            .foregroundStyle(.primary)
            Spacer()
            if paper == nil {
                Text("Paper")
                    .font(Theme.Text.sectionHeader)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } else {
                // The sketch's title, and the text button that sets it.
                Button {
                    titleDraft = title == Self.defaultTitle ? "" : title
                    isNaming = true
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(title)
                            .font(Theme.Text.sectionHeader)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "character.cursor.ibeam")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Self.controlColor)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.secondary.opacity(0.14)))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Title: \(title). Change title")

                // Printed bar lines: none, two or four to a row. Paper, not ink,
                // so it can be switched at any time. Plain paper has no rows to bar.
                if let current = paper, current.kind != .plain {
                    Button {
                        stepBars()
                    } label: {
                        ManuscriptBarsIcon(bars: current.barsPerRow)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(current.barsPerRow == nil ? Color.secondary.opacity(0.14) : Self.controlColor.opacity(0.16)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(barsLabel(current.barsPerRow))
                }
            }
            Spacer()
            Button("Save") { save() }
                .fontWeight(.semibold)
                .tint(Theme.Colors.primaryAction)
                .disabled(paper == nil || !hasChanges || offered != nil)
        }
        .font(Theme.Text.body)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    fileprivate static let controlColor = Color(red: 0.38, green: 0.48, blue: 0.62)

    /// None, then two, then four bars to a row, then none again. Counts as a
    /// change to the sketch, so it is saved and kept for recovery like ink.
    private func stepBars() {
        guard var current = paper else { return }
        let choices = ManuscriptPaper.barChoices
        let index = choices.firstIndex(of: current.barsPerRow) ?? 0
        current.barsPerRow = choices[(index + 1) % choices.count]
        paper = current
        revision += 1
    }

    private func barsLabel(_ bars: Int?) -> String {
        switch bars {
        case 2: return "Bar lines: two bars to a row. Change"
        case 4: return "Bar lines: four bars to a row. Change"
        default: return "Bar lines: none. Change"
        }
    }

    private var toolBar: some View {
        // Six controls must fit an iPhone's width: close spacing, with the
        // slack going between the three groups.
        HStack(spacing: Theme.Spacing.s) {
            padButton("arrow.uturn.backward", label: "Undo", selected: false) { controller.undo() }
                .disabled(!controller.canUndo)
            padButton("arrow.uturn.forward", label: "Redo", selected: false) { controller.redo() }
                .disabled(!controller.canRedo)
            Spacer(minLength: 0)
            ForEach(ManuscriptPadTool.penWidths, id: \.self) { width in
                let selected = tool == .pen(width: width)
                Button {
                    tool = .pen(width: width)
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 4 + width * 2.4, height: 4 + width * 2.4)
                        .frame(width: 44, height: 44)
                        .background(toolBackground(selected: selected))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(penLabel(width))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
            padButton("eraser", label: "Eraser", selected: tool == .eraser) { tool = .eraser }
        }
        // On a wide window, clear of the corner it is resized from.
        .padding(.horizontal, horizontalSizeClass == .regular ? Theme.Spacing.xl : Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
    }

    /// The tool in use carries a ring; the others sit on the plain disc.
    private func toolBackground(selected: Bool) -> some View {
        Circle()
            .fill(selected ? Self.controlColor.opacity(0.16) : Color.secondary.opacity(0.14))
            .overlay(Circle().stroke(Self.controlColor.opacity(selected ? 0.9 : 0), lineWidth: 2))
    }

    private func penLabel(_ width: CGFloat) -> String {
        switch ManuscriptPadTool.penWidths.firstIndex(of: width) {
        case 0: return "Fine pen"
        case 2: return "Broad pen"
        default: return "Medium pen"
        }
    }

    private func padButton(_ systemImage: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Self.controlColor)
                .frame(width: 44, height: 44)
                .background(toolBackground(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        guard let paper else { return }
        let sketch = ManuscriptSketch(paper: paper, drawing: drawing)
        do {
            let file = try ManuscriptSketchFile.writeVerified(sketch)
            defer { try? FileManager.default.removeItem(at: file) }
            let data = try Data(contentsOf: file)
            keepTask?.cancel()
            // The copy is NOT removed here. The editor holds the finished
            // sketch only in memory until the entry is saved, so the copy
            // stays, marked as handed over, and the editor removes it once
            // that save is durable (or the person discards the work).
            // The copy comes first: if it cannot be written the editor is
            // not given the sketch and the pad stays open.
            try ManuscriptSketchRecovery.handOver(sketch, data: data, opening: opening) { data, key in
                try onSave(ManuscriptPadResult(data: data, recoveryKey: key, title: title))
            }
            dismiss()
        } catch {
            // The pad stays open with the drawing in it; nothing is lost.
            saveFailed = true
        }
    }
}

/// A row of staff with its bars: what the bar-lines switch is showing now.
struct ManuscriptBarsIcon: View {
    let bars: Int?

    var body: some View {
        Canvas { context, size in
            let box = CGRect(x: size.width * 0.22, y: size.height * 0.34, width: size.width * 0.56, height: size.height * 0.32)
            var path = Path()
            // The row: top and bottom lines.
            path.move(to: CGPoint(x: box.minX, y: box.minY)); path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
            path.move(to: CGPoint(x: box.minX, y: box.maxY)); path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            // Its bar lines, closing line included.
            if let bars {
                for step in 0...bars {
                    let x = box.minX + box.width * CGFloat(step) / CGFloat(bars)
                    path.move(to: CGPoint(x: x, y: box.minY)); path.addLine(to: CGPoint(x: x, y: box.maxY))
                }
            }
            context.stroke(path, with: .color(ManuscriptPadView.controlColor), lineWidth: 1.4)
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

    /// Complete staves only: two single staves, or one piano system, with
    /// nothing of the next one showing and the lines ending inside the frame.
    static func preview(of paper: ManuscriptPaper) -> UIImage {
        let crop = CGRect(x: 30, y: 46, width: 240, height: 142)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { renderer in
            let context = renderer.cgContext
            context.translateBy(x: -crop.minX, y: -crop.minY)
            ManuscriptPaperRenderer.draw(paper, in: context)
            // The page's lines run on to the right; the preview's stop short.
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: crop.maxX - 18, y: crop.minY, width: 18, height: crop.height))
        }
    }
}
