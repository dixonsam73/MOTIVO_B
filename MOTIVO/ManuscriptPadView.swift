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

    /// Fine, medium and broad: PencilKit width settings for `monoline`,
    /// chosen for the LINE they draw: about 1.3, 2 and 3 page points, on a
    /// page where a stave space is 7. That is under a fifth of a space for
    /// stems and accidentals, under a third for general writing, and under
    /// half, a printed beam's thickness, for beams and noteheads.
    ///
    /// `monoline` draws an even line, the same with a finger as with the
    /// Pencil, and a little over twice its setting. Measured on two saved
    /// sketches, with the same ruler as the figures below: settings of
    /// 0.65, 1, 1.3, 1.5, 2 and 3 drew 1.05, 1.75, 2.46, 2.63, 3.86 and
    /// 5.79 points (`lineThickness(forWidth:)` is the straight line through
    /// those).
    ///
    /// It replaced `pen` on 2026-11-22, after Samuel drew the same word six
    /// ways and the strokes were read back from the saved sketch: with
    /// `pen` the three buttons drew almost the same line (about 1.3, 1.5
    /// and 1.85 pt with the Pencil for settings of 1, 2 and 3.5), a
    /// finger's line was heavier than the Pencil's at every setting (2.1 to
    /// 2.4 pt), and no stroke varied along its length. `pen` starts from a
    /// fixed thickness and adds only a little for the width set, so in the
    /// range notation needs the setting hardly mattered.
    ///
    /// Confirmed on the iPad the same day (Études Dev 2014, the same six
    /// rows read back from the saved sketch): the Pencil and a finger store
    /// the same stroke and draw the same line, about 1.45, 2.25 and 3 pt.
    ///
    /// The fine line is close to the one the Pencil's fine pen drew before,
    /// which he was happy with. A stroke keeps the ink and width it was
    /// drawn with, so existing sketches are unchanged.
    static let penWidths: [CGFloat] = [0.8, 1.15, 1.6]
    static let inkType: PKInkingTool.InkType = .monoline
    /// The line `monoline` draws for a width setting, as measured.
    static func lineThickness(forWidth width: CGFloat) -> CGFloat { 2.11 * width - 0.36 }

    var pencilKitTool: PKTool {
        switch self {
        case .pen(let width): return PKInkingTool(Self.inkType, color: .black, width: width)
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
                        .frame(width: 4 + ManuscriptPadTool.lineThickness(forWidth: width) * 3.2,
                               height: 4 + ManuscriptPadTool.lineThickness(forWidth: width) * 3.2)
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

/// Choosing the paper for a new sketch: six sheets that fill the screen.
///
/// The order and names are Samuel's (2026-11-21): staves with no clef
/// first, then treble, bass, piano and alto, and last a page with nothing
/// printed on it. Two across in a narrow space (a phone), three across in a
/// wide one, so the six always make complete rows.
struct ManuscriptPaperChooser: View {
    let onChoose: (ManuscriptPaper) -> Void

    struct Choice: Identifiable, Equatable {
        let id: String
        let paper: ManuscriptPaper
    }

    static let choices: [Choice] = [
        Choice(id: "No clef", paper: ManuscriptPaper(kind: .singleStaff, clef: .none)),
        Choice(id: "Treble", paper: ManuscriptPaper(kind: .singleStaff, clef: .treble)),
        Choice(id: "Bass", paper: ManuscriptPaper(kind: .singleStaff, clef: .bass)),
        Choice(id: "Piano", paper: ManuscriptPaper(kind: .piano, clef: .none)),
        Choice(id: "Alto", paper: ManuscriptPaper(kind: .singleStaff, clef: .alto)),
        Choice(id: "Blank page", paper: ManuscriptPaper(kind: .plain, clef: .none)),
    ]

    var body: some View {
        GeometryReader { proxy in
            let layout = ManuscriptPaperChooserLayout(space: proxy.size, count: Self.choices.count)
            ScrollView {
                VStack(spacing: layout.rowSpacing) {
                    ForEach(0..<layout.rows, id: \.self) { row in
                        HStack(alignment: .top, spacing: layout.columnSpacing) {
                            ForEach(layout.indices(inRow: row), id: \.self) { index in
                                tile(Self.choices[index], sheet: layout.sheet)
                            }
                        }
                    }
                }
                .padding(ManuscriptPaperChooserLayout.margin)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    private func tile(_ choice: Choice, sheet: CGSize) -> some View {
        Button {
            onChoose(choice.paper)
        } label: {
            VStack(spacing: Theme.Spacing.s) {
                ManuscriptPaperSheetPreview(paper: choice.paper)
                    .frame(width: sheet.width, height: sheet.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                Text(choice.id)
                    .font(Theme.Text.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(height: ManuscriptPaperChooserLayout.labelHeight - Theme.Spacing.s)
            }
        }
        .buttonStyle(.plain)
    }
}

/// How the six sheets share the space under the pad's top bar. PURE.
///
/// A sheet always has the same shape. Where the space's HEIGHT decides its
/// size (a phone, an iPad in landscape) the sheets fill the page top to
/// bottom, close together. Where its WIDTH decides (an iPad in portrait)
/// the sheets are as large as fit three across with room between them,
/// which is about the size they are in landscape, and the height left over
/// is not filled: the rows are set a little further apart and the block is
/// centred (Samuel, 2026-11-21: landscape is right; portrait should be the
/// same size pages, spaced out, not stretched top to bottom).
struct ManuscriptPaperChooserLayout: Equatable {
    static let margin: CGFloat = Theme.Spacing.l
    static let spacing: CGFloat = Theme.Spacing.l
    /// Between sheets where the width decides their size, three across.
    static let widerSpacing: CGFloat = 24
    /// The most the rows are set apart where there is height to spare.
    static let widestRowSpacing: CGFloat = 48
    /// The name under a sheet, with the gap above it.
    static let labelHeight: CGFloat = 30
    /// A space at least this wide takes three across.
    static let threeAcrossWidth: CGFloat = 600
    /// A sheet's width as a share of its height.
    static let sheetAspect: CGFloat = 0.85
    /// Below this the sheets stop shrinking and the page scrolls instead.
    static let smallestSheetHeight: CGFloat = 120

    let columns: Int
    let rows: Int
    let sheet: CGSize
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    private let count: Int

    init(space: CGSize, count: Int) {
        self.count = count
        columns = space.width >= Self.threeAcrossWidth ? 3 : 2
        rows = Int((Double(count) / Double(columns)).rounded(.up))
        let columns = CGFloat(self.columns), rows = CGFloat(self.rows)

        // The tallest a sheet can be with the rows close together.
        let heightFromHeight = (space.height - 2 * Self.margin - (rows - 1) * Self.spacing) / rows - Self.labelHeight
        func heightFromWidth(gap: CGFloat) -> CGFloat {
            ((space.width - 2 * gap - (columns - 1) * gap) / columns) / Self.sheetAspect
        }

        if heightFromWidth(gap: Self.spacing) >= heightFromHeight {
            // The height decides: fill the page top to bottom.
            let height = max(Self.smallestSheetHeight, heightFromHeight).rounded(.down)
            sheet = CGSize(width: (height * Self.sheetAspect).rounded(.down), height: height)
            columnSpacing = Self.spacing
            rowSpacing = Self.spacing
        } else {
            // The width decides: as large as fit across with room between,
            // and the spare height shared out, up to a limit.
            let gap = self.columns >= 3 ? Self.widerSpacing : Self.spacing
            let height = max(Self.smallestSheetHeight, min(heightFromHeight, heightFromWidth(gap: gap))).rounded(.down)
            sheet = CGSize(width: (height * Self.sheetAspect).rounded(.down), height: height)
            columnSpacing = gap
            let spare = space.height - rows * (height + Self.labelHeight)
            rowSpacing = min(Self.widestRowSpacing, max(Self.spacing, (spare / (rows + 1)).rounded(.down)))
        }
    }

    func indices(inRow row: Int) -> [Int] {
        Array((row * columns)..<min(count, (row + 1) * columns))
    }
}

/// The top of the real page, drawn to fill a sheet-shaped tile at a size
/// where the clef is easy to read. Only complete staves are shown: a staff
/// the tile would cut through is left off, and the lines stop short of the
/// right-hand edge, so the tile reads as a small sheet, not a torn corner.
struct ManuscriptPaperSheetPreview: View {
    let paper: ManuscriptPaper

    /// The part of the page shown across the tile's width, in page points.
    static let pageOrigin = CGPoint(x: 30, y: 46)
    static let pageWidthShown: CGFloat = 240
    static let rightMargin: CGFloat = 18
    static let clefTail: CGFloat = 12

    /// PURE. Where the drawing must be blanked from, in page points, so no
    /// part-staff shows: just below the last row that fits whole. Nil when
    /// nothing needs blanking.
    static func blankFromY(paper: ManuscriptPaper, visiblePageHeight: CGFloat) -> CGFloat? {
        let bottom = pageOrigin.y + visiblePageHeight
        let rows = ManuscriptPaperRenderer.rows(for: paper)
        guard !rows.isEmpty else { return nil }
        // A treble clef's tail hangs about a line and a half below its staff.
        let whole = rows.filter { $0.bottom + clefTail <= bottom }
        guard whole.count < rows.count else { return nil }
        return (whole.last?.bottom ?? pageOrigin.y) + clefTail
    }

    var body: some View {
        Canvas { context, size in
            let scale = size.width / Self.pageWidthShown
            let blankFrom = Self.blankFromY(paper: paper, visiblePageHeight: size.height / scale)
            context.withCGContext { cg in
                cg.setFillColor(CGColor(gray: 1, alpha: 1))
                cg.fill(CGRect(origin: .zero, size: size))
                cg.saveGState()
                cg.scaleBy(x: scale, y: scale)
                cg.translateBy(x: -Self.pageOrigin.x, y: -Self.pageOrigin.y)
                ManuscriptPaperRenderer.draw(paper, in: cg)
                cg.setFillColor(CGColor(gray: 1, alpha: 1))
                // The page's lines run on to the right; the sheet's stop short.
                let right = Self.pageOrigin.x + Self.pageWidthShown - Self.rightMargin
                cg.fill(CGRect(x: right, y: 0, width: ManuscriptPaper.pageSize.width, height: ManuscriptPaper.pageSize.height))
                if let blankFrom {
                    cg.fill(CGRect(x: 0, y: blankFrom, width: ManuscriptPaper.pageSize.width, height: ManuscriptPaper.pageSize.height))
                }
                cg.restoreGState()
            }
        }
        .background(Color.white)
        .accessibilityHidden(true)
    }
}
