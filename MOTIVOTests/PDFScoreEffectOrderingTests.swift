import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import Etudes

/// PDFScoreView: no page or failure report is published from inside SwiftUI's
/// view-update pass, a newer event never overtakes an older one, obsolete state is
/// never delivered, and closing withdraws pending reports before close-time work.
///
/// A manual scheduler stands in for the main queue, so nothing runs until the test
/// drains it; no timing is asserted. PDFs are generated synthetically in a test
/// temporary directory. No app, device or user data.
@MainActor
final class PDFScoreEffectOrderingTests: XCTestCase {
    private var scheduled: [() -> Void] = []
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFScoreEffect-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        scheduled = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeGate() -> PDFScoreEffectGate {
        PDFScoreEffectGate(schedule: { [unowned self] in self.scheduled.append($0) })
    }

    /// Runs whatever has been scheduled, including drains scheduled meanwhile.
    private func drainScheduled() {
        while !scheduled.isEmpty { scheduled.removeFirst()() }
    }

    // MARK: - Gate

    func testG1_IdleOutsideUpdateRunsSynchronously() {
        let gate = makeGate()
        var log: [String] = []
        gate.run { log.append("a") }
        XCTAssertEqual(log, ["a"])
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testG2_InsideUpdateNothingRunsUntilDrainThenFIFO() {
        let gate = makeGate()
        var log: [String] = []
        gate.beginViewUpdate()
        gate.run { log.append("a") }
        gate.run { log.append("b") }
        gate.run { log.append("c") }
        gate.endViewUpdate()
        XCTAssertEqual(log, [])
        XCTAssertEqual(scheduled.count, 1, "one drain for the burst")
        drainScheduled()
        XCTAssertEqual(log, ["a", "b", "c"])
    }

    func testG3_OutsideEffectWaitsBehindPendingUpdateEffect() {
        let gate = makeGate()
        var log: [String] = []
        gate.beginViewUpdate()
        gate.run { log.append("A") }
        gate.endViewUpdate()
        gate.run { log.append("B") }
        XCTAssertEqual(log, [], "B must not overtake the pending A")
        drainScheduled()
        XCTAssertEqual(log, ["A", "B"])
    }

    func testG4_StaleEpochIsDroppedAtDrain() {
        let gate = makeGate()
        var log: [String] = []
        gate.beginViewUpdate()
        gate.run { log.append("old") }
        gate.invalidate()
        gate.run { log.append("new") }
        gate.endViewUpdate()
        drainScheduled()
        XCTAssertEqual(log, ["new"])
    }

    func testG5_AfterDrainOutsideEffectsAreSynchronousAgain() {
        let gate = makeGate()
        var log: [String] = []
        gate.beginViewUpdate(); gate.run { log.append("a") }; gate.endViewUpdate()
        drainScheduled()
        gate.run { log.append("b") }
        XCTAssertEqual(log, ["a", "b"])
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testG6_ReentrantEffectsStayFIFOEvenWhenTheQueueEmptiesMidDrain() {
        let gate = makeGate()
        var log: [String] = []
        gate.beginViewUpdate()
        gate.run {
            log.append("A-start")
            gate.run { log.append("B") }     // the queue is empty at this instant
            log.append("A-end")
        }
        gate.endViewUpdate()
        drainScheduled()
        XCTAssertEqual(log, ["A-start", "A-end", "B"], "B runs after A, never inside it")
    }

    func testG7_DrainDuringAnUpdateIsDeferredAgain() {
        let gate = makeGate()
        var log: [String] = []
        gate.beginViewUpdate()
        gate.run { log.append("a") }
        scheduled.removeFirst()()            // the drain arrives while still updating
        XCTAssertEqual(log, [])
        gate.endViewUpdate()
        drainScheduled()
        XCTAssertEqual(log, ["a"])
    }

    func testG8_CloseDropsPendingAndRefusesLaterUntilReopened() {
        let gate = makeGate()
        var log: [String] = []
        gate.beginViewUpdate(); gate.run { log.append("pending") }; gate.endViewUpdate()
        gate.close()
        gate.close()                          // idempotent
        gate.run { log.append("after-close") }
        drainScheduled()
        XCTAssertEqual(log, [])
        gate.reopen()
        gate.run { log.append("reopened") }
        XCTAssertEqual(log, ["reopened"])
    }

    // MARK: - Coordinator, through the same entry points the representable calls

    private final class Recorder {
        var index = 0
        var count = 0
        var reports: [Int] = []
        var failures = 0
        var log: [String] = []
    }

    private func pdf(pages: Int, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name + ".pdf")
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 300)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in 1...pages {
                context.beginPage()
                ("Page \(page)" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
            }
        }
        try data.write(to: url)
        return url
    }

    /// Configured as `makeUIView` configures it.
    private func makePDFView() -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.autoScales = true
        view.backgroundColor = .clear
        view.displaysPageBreaks = false
        return view
    }

    private func coordinator(_ recorder: Recorder, gate: PDFScoreEffectGate) -> PDFScoreRepresentable.Coordinator {
        PDFScoreRepresentable.Coordinator(
            pageIndex: Binding(get: { recorder.index }, set: { recorder.index = $0 }),
            pageCount: Binding(get: { recorder.count }, set: { recorder.count = $0 }),
            initialPage: nil, onPageChange: nil, onFailure: nil, effects: gate
        )
    }

    private func onPage(_ recorder: Recorder) -> (Int) -> Void { { recorder.reports.append($0); recorder.log.append("page \($0)") } }
    private func onFail(_ recorder: Recorder) -> () -> Void { { recorder.failures += 1 } }

    private func swipe(_ view: PDFView, toPage number: Int) throws {
        let page = try XCTUnwrap(view.document?.page(at: number - 1))
        view.go(to: page)
    }

    func testK1_OpeningReportsTheInitialPageOnlyAfterTheUpdatePass() throws {
        let r = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(r, gate: gate)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 3, onPageChange: onPage(r), onFailure: onFail(r))
        XCTAssertEqual(r.reports, [], "nothing published inside the update")
        XCTAssertEqual(r.count, 0)
        drainScheduled()
        XCTAssertEqual(r.reports, [3])
        XCTAssertEqual(r.index, 2)
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.failures, 0)
    }

    func testK2_PendingOpenReportThenSwipeDeliverInOrder() throws {
        let r = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(r, gate: gate)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 2, onPageChange: onPage(r), onFailure: onFail(r))
        c.startObserving()
        defer { c.dismantle() }

        try swipe(view, toPage: 3)           // outside any update, while the open report is pending
        XCTAssertEqual(r.reports, [], "the swipe must not overtake the pending report")
        drainScheduled()
        XCTAssertEqual(r.reports, [2, 3])
        XCTAssertEqual(r.index, 2)

        try swipe(view, toPage: 1)           // nothing pending: immediate, as today
        XCTAssertEqual(r.reports, [2, 3, 1])
        XCTAssertEqual(r.index, 0)
    }

    func testK3_ReplacingTheDocumentDropsItsPendingReport() throws {
        let r = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(r, gate: gate)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 3, onPageChange: onPage(r), onFailure: onFail(r))
        c.didUpdate(url: try pdf(pages: 2, name: "two"), selectedPages: nil,
                    initialPage: 1, onPageChange: onPage(r), onFailure: onFail(r))
        drainScheduled()
        XCTAssertEqual(r.reports, [1], "no report of the replaced document is delivered")
        XCTAssertEqual(r.count, 2)
    }

    func testK4_ReplacedCallbackGetsOnlyLaterEvents() throws {
        let old = Recorder(), new = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(old, gate: gate)
        let url = try pdf(pages: 3, name: "three")
        c.didMake(pdfView: view, url: url, selectedPages: nil, initialPage: 2,
                  onPageChange: onPage(old), onFailure: onFail(old))
        c.startObserving()
        defer { c.dismantle() }
        c.didUpdate(url: url, selectedPages: nil, initialPage: 2,
                    onPageChange: onPage(new), onFailure: onFail(new))
        drainScheduled()
        XCTAssertEqual(old.reports, [2])
        XCTAssertEqual(new.reports, [])

        try swipe(view, toPage: 3)
        XCTAssertEqual(old.reports, [2])
        XCTAssertEqual(new.reports, [3])
    }

    func testK5_MissingDocumentFailsOnceAndOnlyAfterTheUpdatePass() throws {
        let r = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(r, gate: gate)
        let missing = directory.appendingPathComponent("missing.pdf")
        c.didMake(pdfView: view, url: missing, selectedPages: nil, initialPage: nil,
                  onPageChange: onPage(r), onFailure: onFail(r))
        XCTAssertEqual(r.failures, 0)
        drainScheduled()
        XCTAssertEqual(r.failures, 1)

        c.didUpdate(url: missing, selectedPages: nil, initialPage: nil,
                    onPageChange: onPage(r), onFailure: onFail(r))   // an ordinary re-render
        drainScheduled()
        XCTAssertEqual(r.failures, 1, "failure is reported once per document")
    }

    func testK6_DismantleWithdrawsPendingReports() throws {
        let r = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(r, gate: gate)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 3, onPageChange: onPage(r), onFailure: onFail(r))
        c.dismantle()
        drainScheduled()
        XCTAssertEqual(r.reports, [])
        XCTAssertEqual(r.count, 0)
    }

    func testK7_ReRenderOnTheSamePageDoesNotReportAgain() throws {
        let r = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(r, gate: gate)
        let url = try pdf(pages: 3, name: "three")
        c.didMake(pdfView: view, url: url, selectedPages: nil, initialPage: 2,
                  onPageChange: onPage(r), onFailure: onFail(r))
        drainScheduled()
        c.didUpdate(url: url, selectedPages: nil, initialPage: 2, onPageChange: onPage(r), onFailure: onFail(r))
        drainScheduled()
        XCTAssertEqual(r.reports, [2])
    }

    /// The order PDFScoreView.onDisappear establishes: close the gate, THEN the
    /// caller's close work (the practice timer flushes page tracking there).
    func testK8_CloseThenFlushLeavesNoLateReportToReopenTracking() throws {
        let r = Recorder(), gate = makeGate(), view = makePDFView()
        let c = coordinator(r, gate: gate)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 3, onPageChange: onPage(r), onFailure: onFail(r))

        gate.close()
        r.log.append("flush")                // the caller's onClose
        drainScheduled()
        XCTAssertEqual(r.log, ["flush"], "no page report after the flush")
        XCTAssertEqual(r.reports, [])
    }

    // MARK: - Reappearance after a close

    private func controllerAndCoordinator(_ r: Recorder) -> (PDFScoreController, PDFScoreRepresentable.Coordinator) {
        let controller = PDFScoreController(effects: makeGate())
        let c = coordinator(r, gate: controller.effects)
        controller.attach(c)
        return (controller, c)
    }

    func testR1_PendingReportClosedThenSameViewerReappears() throws {
        let r = Recorder(), view = makePDFView()
        let (controller, c) = controllerAndCoordinator(r)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 3, onPageChange: onPage(r), onFailure: onFail(r))
        controller.viewDidDisappear()
        r.log.append("flush")
        drainScheduled()
        XCTAssertEqual(r.log, ["flush"], "nothing after close until reappearance")

        controller.viewDidAppear()
        XCTAssertEqual(r.reports, [], "not published synchronously on appear")
        drainScheduled()
        XCTAssertEqual(r.log, ["flush", "page 3"])
        XCTAssertEqual(r.index, 2)
        XCTAssertEqual(r.count, 3)
    }

    func testR2_DeliveredThenCloseFlushThenReappearOnSamePageReportsItAgain() throws {
        let r = Recorder(), view = makePDFView()
        let (controller, c) = controllerAndCoordinator(r)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 1, onPageChange: onPage(r), onFailure: onFail(r))
        c.startObserving()
        defer { c.dismantle() }
        controller.viewDidAppear()                   // first appearance: nothing extra
        drainScheduled()
        try swipe(view, toPage: 2)
        XCTAssertEqual(r.reports, [1, 2])

        controller.viewDidDisappear()
        r.log.append("flush")
        controller.viewDidAppear()
        drainScheduled()
        XCTAssertEqual(Array(r.log.suffix(2)), ["flush", "page 2"], "the CURRENT page, not the initial one")
        XCTAssertEqual(r.reports, [1, 2, 2])
    }

    func testR3_NewCoordinatorOnARetainedClosedControllerReportsOnAppear() throws {
        let old = Recorder(), r = Recorder()
        let (controller, first) = controllerAndCoordinator(old)
        first.didMake(pdfView: makePDFView(), url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                      initialPage: 1, onPageChange: onPage(old), onFailure: onFail(old))
        drainScheduled()
        controller.viewDidDisappear()

        let second = coordinator(r, gate: controller.effects)
        controller.attach(second)
        second.didMake(pdfView: makePDFView(), url: try pdf(pages: 3, name: "again"), selectedPages: nil,
                       initialPage: 2, onPageChange: onPage(r), onFailure: onFail(r))
        drainScheduled()
        XCTAssertEqual(r.reports, [], "closed: nothing delivered before appearance")

        controller.viewDidAppear()
        drainScheduled()
        XCTAssertEqual(r.reports, [2])
        XCTAssertEqual(old.reports, [1], "the old viewer receives nothing more")
    }

    func testR4_FailureDroppedByCloseIsReportedOnReappear() throws {
        let r = Recorder(), view = makePDFView()
        let (controller, c) = controllerAndCoordinator(r)
        c.didMake(pdfView: view, url: directory.appendingPathComponent("missing.pdf"), selectedPages: nil,
                  initialPage: nil, onPageChange: onPage(r), onFailure: onFail(r))
        controller.viewDidDisappear()
        drainScheduled()
        XCTAssertEqual(r.failures, 0)

        controller.viewDidAppear()
        drainScheduled()
        XCTAssertEqual(r.failures, 1)
        controller.viewDidAppear()                   // not closed: no republish
        drainScheduled()
        XCTAssertEqual(r.failures, 1)
    }

    func testR5_FirstAppearanceDoesNotDuplicateTheOpeningReport() throws {
        let r = Recorder(), view = makePDFView()
        let (controller, c) = controllerAndCoordinator(r)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 2, onPageChange: onPage(r), onFailure: onFail(r))
        controller.viewDidAppear()
        drainScheduled()
        XCTAssertEqual(r.reports, [2])
    }

    func testR6_OldScheduledDrainAfterReappearDeliversOnlyTheFreshSnapshot() throws {
        let r = Recorder(), view = makePDFView()
        let (controller, c) = controllerAndCoordinator(r)
        c.didMake(pdfView: view, url: try pdf(pages: 3, name: "three"), selectedPages: nil,
                  initialPage: 3, onPageChange: onPage(r), onFailure: onFail(r))
        XCTAssertEqual(scheduled.count, 1, "the opening drain is still pending")
        controller.viewDidDisappear()
        controller.viewDidAppear()                   // before that old drain has run
        drainScheduled()
        XCTAssertEqual(r.reports, [3], "one fresh report; the withdrawn one is not resurrected")
    }

    // MARK: - Structural (executable code only)

    func testS1_CloseOrderAndNoDirectCallbackCalls() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO/PDFScoreView.swift")
        let code = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") || t.hasPrefix("///") { return "" }
                if let r = line.range(of: " //") { return String(line[..<r.lowerBound]) }
                return String(line)
            }.joined(separator: "\n")
        let close = try XCTUnwrap(code.range(of: "controller.viewDidDisappear()"))
        let onClose = try XCTUnwrap(code.range(of: "onClose?()"))
        XCTAssertLessThan(close.lowerBound, onClose.lowerBound, "pending reports are withdrawn before close work")
        // The only callback invocations are inside the gated snapshot.
        XCTAssertEqual(code.components(separatedBy: "onPageChange?(").count - 1, 1)
        XCTAssertEqual(code.components(separatedBy: "onFailure?(").count - 1, 1)
        XCTAssertTrue(code.contains("if let report { onPageChange?(report) }"))
        XCTAssertTrue(code.contains("if fail { onFailure?() }"))
    }
}
