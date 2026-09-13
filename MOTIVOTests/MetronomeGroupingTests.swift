import XCTest
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import Etudes

final class MetronomeGroupingTests: XCTestCase {
    private func grouped(_ meter: MetronomeMeter = .asymmetric(5), _ parts: [Int] = [2,3]) -> MetronomeSettings {
        var value = MetronomeSettings(); value.selectMeter(meter); value.selectGrouping(.init(parts: parts))
        value.bpm = 60; value.accent = true; value.volume = 1
        return value
    }
    private func ticks(_ settings: MetronomeSettings, frames: Int) -> [(Int, MetronomeClickRole)] {
        var timeline = MetronomeTimeline(sampleRate: 100, settings: .init(command: settings.command(running: true)))
        return (0..<frames).compactMap { frame in timeline.nextFrame().map { (frame, $0.role) } }
    }
    private func render(_ settings: MetronomeSettings, bank: MetronomeSoundBank, frames: Int, buffers: [Int]) -> [Float] {
        let kernel = MetronomeRenderKernel(bank: bank, mailbox: MetronomeMailbox(settings: settings))
        var result: [Float] = []; var index = 0
        while result.count < frames {
            let count = min(buffers[index % buffers.count], frames - result.count)
            kernel.beginBuffer()
            for _ in 0..<count { result.append(kernel.nextSample()) }
            kernel.endBuffer(frameCount: count); index += 1
        }
        return result
    }
    func testPresetsAreDistinctValidAndLimitedToEligibleMeters() {
        XCTAssertEqual(MetronomeMeter.asymmetric(7).groupingChoices.map(\.label), ["Even", "2+2+3", "2+3+2", "3+2+2"])
        XCTAssertTrue(MetronomeMeter.asymmetric(10).groupingChoices.contains(.init(parts: [3,3,2,2])))
        for meter in MetronomeMeter.standard {
            XCTAssertEqual(Set(meter.groupingChoices).count, meter.groupingChoices.count)
            for grouping in meter.groupingChoices.dropFirst() {
                XCTAssertEqual(grouping.parts.reduce(0,+), meter.numerator)
                XCTAssertTrue(grouping.parts.allSatisfy { $0 == 2 || $0 == 3 })
                XCTAssertNotEqual(grouping.startMask, 0)
            }
        }
        for meter: MetronomeMeter in [.simple(4), .simpleEighth(3), .compound(6), .compound(9)] {
            XCTAssertEqual(meter.groupingChoices, [.even]); XCTAssertFalse(meter.supportsGrouping)
        }
    }
    func testEvenIsTheDefaultAndDoesNotAlterTempoOrAccent() {
        var settings = MetronomeSettings()
        for meter in MetronomeMeter.standard {
            settings.selectMeter(meter)
            XCTAssertEqual(settings.grouping, .even)
            XCTAssertEqual(MetronomeRenderSettings(command: settings.command(running: true)).groupStartMask, 0)
            XCTAssertEqual(settings.bpm, 80); XCTAssertFalse(settings.accent)
        }
    }
    func testEachMeterRemembersItsPatternAcrossPersistenceAndEvenClearsOnlyThatMeter() {
        var settings = grouped()
        settings.selectMeter(.asymmetric(7)); settings.selectGrouping(.init(parts: [2,3,2]))
        var restored = MetronomeSettings(); restored.restoreGroupings(from: settings.encodedGroupings())
        restored.selectMeter(.asymmetric(5)); XCTAssertEqual(restored.grouping.parts, [2,3])
        restored.selectGrouping(.even)
        restored.selectMeter(.asymmetric(7)); XCTAssertEqual(restored.grouping.parts, [2,3,2])
        restored.selectMeter(.asymmetric(5)); XCTAssertEqual(restored.grouping, .even)
    }
    func testMalformedOrUnsupportedStoredPatternsAreIgnored() {
        var settings = MetronomeSettings()
        settings.restoreGroupings(from: Data("{bad".utf8)); XCTAssertEqual(settings.rememberedGroupings, [:])
        let data = Data(#"{"5/8":[2,3],"7/8":[7],"4/4":[2,2],"10/8":[3,3,3],"999/8":[2,3]}"#.utf8)
        settings.restoreGroupings(from: data)
        XCTAssertEqual(settings.rememberedGroupings, ["5/8":[2,3]])
        settings.selectMeter(.asymmetric(5)); settings.selectGrouping(.init(parts: [3,3]))
        XCTAssertEqual(settings.grouping.parts, [2,3])
        XCTAssertEqual(MetronomeGrouping(parts: [Int.max]).startMask, 0)
    }
    func testGroupMaskAndOtherControlsRoundTripTogether() {
        XCTAssertEqual(MetronomeGrouping(parts: [3,3,2,2]).startMask, 329)
        for meter in MetronomeMeter.standard {
            for grouping in meter.groupingChoices {
                var settings = grouped(meter, grouping.parts)
                settings.bpm = 137; settings.subdivision = .semiquavers; settings.volume = 0.123
                let decoded = MetronomeRenderSettings(command: settings.command(running: true))
                XCTAssertEqual(decoded.groupStartMask, grouping.startMask)
                XCTAssertEqual(decoded.bpm, 137); XCTAssertEqual(decoded.meterCode, meter.code)
                XCTAssertEqual(decoded.volume, 0.123, accuracy: 0.0001)
                XCTAssertEqual(decoded.divisions, settings.subdivision.count(in: meter))
                XCTAssertTrue(decoded.accent); XCTAssertTrue(decoded.running)
            }
        }
    }
    func testSevenEightGroupingKeepsEqualQuaverSpacingAndBarStartAccent() {
        let events = ticks(grouped(.asymmetric(7), [2,2,3]), frames: 1400)
        XCTAssertEqual(events.map(\.0), (0..<14).map { $0 * 100 })
        let bar: [MetronomeClickRole] = [.downbeat, .groupInterior, .groupAccent, .groupInterior, .groupAccent, .groupInterior, .groupInterior]
        XCTAssertEqual(events.map(\.1), bar + bar)
    }
    func testTurningDownbeatOffPreservesInternalGrouping() {
        var settings = grouped(); settings.accent = false
        XCTAssertEqual(ticks(settings, frames: 500).map(\.1), [.groupAccent,.groupInterior,.groupAccent,.groupInterior,.groupInterior])
    }
    func testEvenRestoresTheOriginalUnweightedQuavers() {
        var settings = grouped(); settings.selectGrouping(.even)
        XCTAssertEqual(ticks(settings, frames: 500).map(\.1), [.downbeat,.beat,.beat,.beat,.beat])
    }
    func testLivePatternChangeBeginsNewPatternOnNextBeatWithoutChangingSpacing() {
        var settings = grouped(); settings.subdivision = .quavers
        var timeline = MetronomeTimeline(sampleRate: 100, settings: .init(command: settings.command(running: true)))
        for _ in 0..<125 { _ = timeline.nextFrame() }
        settings.selectGrouping(.init(parts: [3,2])); timeline.update(.init(command: settings.command(running: true)))
        var events: [(Int64, MetronomeClickRole)] = []
        for _ in 0..<476 { let frame = timeline.frame; if let tick = timeline.nextFrame() { events.append((frame,tick.role)) } }
        XCTAssertEqual(events.map(\.0), stride(from: Int64(150), through: 600, by: 50).map { $0 })
        XCTAssertEqual(events[0].1, .subdivision)
        XCTAssertEqual(events[1].1, .downbeat)
        XCTAssertEqual(events[7].1, .groupAccent) // next group begins at quaver 4
    }
    func testGroupedAudioHasFourDistinctLevelsUsingExistingRecordings() throws {
        let bank = try MetronomeTestSamples.bank(rate: 48000)
        var settings = grouped(); settings.subdivision = .semiquavers
        let samples = render(settings, bank: bank, frames: 97000, buffers: [256])
        for i in 0..<960 {
            XCTAssertEqual(samples[i], bank.sample(0,i) * Float(pow(10.0,-3.0/20)), accuracy: 0.000001)
            XCTAssertEqual(samples[12000+i], bank.sample(2,i) * 0.14, accuracy: 0.000001)
            XCTAssertEqual(samples[48000+i], bank.sample(1,i) * 0.22, accuracy: 0.000001)
            XCTAssertEqual(samples[96000+i], bank.sample(3,i) * 0.35, accuracy: 0.000001)
        }
    }
    func testGroupedRenderIsIdenticalAcrossBufferBoundaries() throws {
        let bank = try MetronomeTestSamples.bank(rate: 48000)
        var settings = grouped(.asymmetric(10), [3,3,2,2]); settings.bpm = 137; settings.subdivision = .quavers
        XCTAssertEqual(render(settings, bank: bank, frames: 96000, buffers: [256]),
                       render(settings, bank: bank, frames: 96000, buffers: [1,127,1024,13,511]))
    }
    func testFastGroupedSubdivisionsDoNotClipAndVisualsCountEveryQuaver() throws {
        let bank = try MetronomeTestSamples.bank(rate: 48000)
        var settings = grouped(.asymmetric(10), [3,3,2,2]); settings.bpm = 400; settings.subdivision = .semiquavers
        let mailbox = MetronomeMailbox(settings: settings), kernel: MetronomeRenderKernel
        kernel = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
        kernel.beginBuffer(); for _ in 0..<72000 { _ = kernel.nextSample() }
        XCTAssertLessThan(kernel.maximumUnclampedSample, 1)
        XCTAssertEqual(mailbox.beat.load(ordering: .acquiring) >> 1, 10)
    }
}

#if canImport(UIKit)
extension MetronomeGroupingTests {
    @MainActor
    func testLargeTextGroupingChoicesRemainScrollable() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
        let content = MetronomeGroupingPopover(meter: .asymmetric(11), selected: .even,
            recorderIcon: .gray, onSelect: { _ in }).environment(\.dynamicTypeSize, .accessibility3)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        XCTAssertGreaterThan(scroll.bounds.height, 0)
        XCTAssertLessThanOrEqual(scroll.bounds.height, 301)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height * 2,
            "The viewport must stay bounded so the remaining large-text choices are reachable")
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        XCTAssertGreaterThan(scroll.contentOffset.y, 0)
    }
}
#endif
