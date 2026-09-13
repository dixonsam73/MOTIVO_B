import XCTest
@testable import Etudes

final class MetronomeTimingTests: XCTestCase {
    private func ticks(_ settings: MetronomeSettings, rate: Double = 1000, seconds: Double) -> [(Int, MetronomeTick)] {
        var timeline = MetronomeTimeline(sampleRate: rate, settings: .init(command: settings.command(running: true)))
        var result: [(Int, MetronomeTick)] = []
        for frame in 0..<Int(rate * seconds) {
            if let event = timeline.nextFrame() { result.append((frame, event)) }
        }
        return result
    }

    func testFourFourQuaversPreserveBeatTempoAndDownbeat() {
        var settings = MetronomeSettings(); settings.bpm = 120; settings.accent = true; settings.subdivision = .quavers
        let events = ticks(settings, seconds: 2)
        XCTAssertEqual(events.map(\.0), stride(from: 0, to: 2000, by: 250).map { $0 })
        XCTAssertEqual(events.map { $0.1.role }, [.downbeat, .subdivision, .beat, .subdivision, .beat, .subdivision, .beat, .subdivision])
    }
    func testCompoundTimeHasTwoBeatsAndSixQuavers() {
        var settings = MetronomeSettings(); settings.bpm = 120; settings.accent = true
        settings.selectMeter(.compound(6)); settings.subdivision = .quavers
        let events = ticks(settings, rate: 1200, seconds: 2)
        XCTAssertEqual(events.count, 12)
        XCTAssertEqual(events.filter { $0.1.role == .downbeat }.map(\.0), [0, 1200])
        XCTAssertEqual(events.filter { $0.1.isPrimary }.map(\.0), [0, 600, 1200, 1800])
    }
    func testEveryMeterCountsItsOwnBar() {
        let meters = MetronomeMeter.standard
        for meter in meters {
            for subdivision in MetronomeSubdivision.choices(in: meter) {
                var settings = MetronomeSettings(); settings.bpm = 120; settings.selectMeter(meter)
                settings.accent = true; settings.subdivision = subdivision
                let events = ticks(settings, rate: 1200, seconds: Double(meter.beats))
                XCTAssertEqual(events.count, 2 * meter.beats * subdivision.count(in: meter), meter.label)
                XCTAssertEqual(events.filter { $0.1.role == .downbeat }.count, 2, meter.label)
            }
        }
    }
    func testAccentOffStillDistinguishesPrimaryBeats() {
        var settings = MetronomeSettings(); settings.subdivision = .triplets
        let events = ticks(settings, seconds: 3)
        XCTAssertEqual(events.filter { $0.1.role == .downbeat }.count, 0)
        XCTAssertEqual(events.filter { $0.1.role == .beat }.count, 4)
        XCTAssertEqual(events.filter { $0.1.role == .subdivision }.count, 8)
    }
    func testFractionalTimingAtActualRenderRates() {
        for rate in [44100.0, 48000, 96000] {
            for bpm in [20, 29, 30, 80, 137, 400] {
                var settings = MetronomeSettings(); settings.bpm = bpm; settings.subdivision = .triplets
                let events = ticks(settings, rate: rate, seconds: 3.1)
                for (index, event) in events.enumerated() {
                    XCTAssertEqual(Double(event.0), Double(index) * rate * 60 / Double(bpm * 3), accuracy: 0.501)
                }
            }
        }
    }
    func testLongRunDoesNotAccumulateIntervalRoundingError() {
        var settings = MetronomeSettings(); settings.bpm = 137; settings.subdivision = .semiquavers
        let events = ticks(settings, rate: 1000, seconds: 600)
        for (index, event) in events.enumerated() {
            XCTAssertEqual(Double(event.0), Double(index) * 60000 / (137 * 4), accuracy: 0.501)
        }
    }
    func testLargeTempoIncreasePreservesElapsedBeatFraction() {
        var settings = MetronomeSettings(); settings.bpm = 30
        var timeline = MetronomeTimeline(sampleRate: 1000, settings: .init(command: settings.command(running: true)))
        for _ in 0..<100 { _ = timeline.nextFrame() }
        settings.bpm = 400; timeline.update(.init(command: settings.command(running: true)))
        var frames: [Int64] = []
        for _ in 0..<600 { let frame = timeline.frame; if timeline.nextFrame() != nil { frames.append(frame) } }
        XCTAssertEqual(frames, [242, 392, 542, 692]) // round-to-nearest boundary, 142.5 ms until next beat
    }
    func testTempoDecreaseRescalesPendingSubdivisions() {
        var settings = MetronomeSettings(); settings.bpm = 400; settings.subdivision = .quavers
        var timeline = MetronomeTimeline(sampleRate: 1200, settings: .init(command: settings.command(running: true)))
        for _ in 0..<60 { _ = timeline.nextFrame() }
        settings.bpm = 30; timeline.update(.init(command: settings.command(running: true)))
        var events: [(Int64, MetronomeTick)] = []
        for _ in 0..<2100 { let frame = timeline.frame; if let tick = timeline.nextFrame() { events.append((frame, tick)) } }
        XCTAssertEqual(events.map(\.0), [460, 1660])
        XCTAssertEqual(events.map { $0.1.role }, [.subdivision, .beat])
    }
    func testMeterAndSubdivisionCommitTogetherOnNextBeat() {
        var settings = MetronomeSettings(); settings.bpm = 120; settings.accent = true; settings.subdivision = .quavers
        var timeline = MetronomeTimeline(sampleRate: 1200, settings: .init(command: settings.command(running: true)))
        for _ in 0..<400 { _ = timeline.nextFrame() }
        settings.selectMeter(.compound(6)); timeline.update(.init(command: settings.command(running: true)))
        var events: [(Int64, MetronomeTick)] = []
        for _ in 0..<1400 { let frame = timeline.frame; if let tick = timeline.nextFrame() { events.append((frame, tick)) } }
        XCTAssertEqual(events.map(\.0), [600, 800, 1000, 1200, 1400, 1600])
        XCTAssertEqual(events.first?.1.role, .downbeat)
        XCTAssertEqual(events[3].1.role, .beat)
    }
    func testChangingWrittenMeterWithSameBeatCountRestartsBar() {
        var settings = MetronomeSettings(); settings.bpm = 120; settings.selectMeter(.simple(2)); settings.accent = true
        var timeline = MetronomeTimeline(sampleRate: 1000, settings: .init(command: settings.command(running: true)))
        for _ in 0..<250 { _ = timeline.nextFrame() }
        settings.selectMeter(.compound(6)); timeline.update(.init(command: settings.command(running: true)))
        var next: MetronomeTick?
        for _ in 0..<251 { if let tick = timeline.nextFrame() { next = tick } }
        XCTAssertEqual(next?.role, .downbeat)
    }
    func testAccentChangeWaitsForBeatWithoutResettingBar() {
        var settings = MetronomeSettings(); settings.bpm = 120; settings.accent = true; settings.subdivision = .quavers
        var timeline = MetronomeTimeline(sampleRate: 1000, settings: .init(command: settings.command(running: true)))
        for _ in 0..<100 { _ = timeline.nextFrame() }
        settings.accent = false; timeline.update(.init(command: settings.command(running: true)))
        var events: [MetronomeTick] = []
        for _ in 0..<2001 { if let tick = timeline.nextFrame() { events.append(tick) } }
        XCTAssertEqual(events.first?.role, .subdivision)
        XCTAssertEqual(events.filter(\.isPrimary).map(\.beatInBar), [1, 2, 3, 0])
        XCTAssertTrue(events.filter(\.isPrimary).allSatisfy { $0.role == .beat })
    }
    func testAsymmetricMetersClickEachQuaverAndAccentOnlyBarStart() {
        for numerator in [5, 7, 11] {
            var settings = MetronomeSettings(); settings.bpm = 120
            settings.selectMeter(.asymmetric(numerator)); settings.accent = true
            let events = ticks(settings, seconds: Double(numerator))
            XCTAssertEqual(events.map(\.0), (0..<(2 * numerator)).map { $0 * 500 })
            XCTAssertEqual(events.filter { $0.1.role == .downbeat }.map(\.0), [0, numerator * 500])
        }
    }
    func testSwitchingCrotchetToQuaverMeterRestartsBarAtNextPrimaryBeat() {
        var settings = MetronomeSettings(); settings.bpm = 120
        settings.selectMeter(.simple(5)); settings.accent = true; settings.subdivision = .quavers
        var timeline = MetronomeTimeline(sampleRate: 1000, settings: .init(command: settings.command(running: true)))
        for _ in 0..<600 { _ = timeline.nextFrame() }
        settings.selectMeter(.asymmetric(5)); timeline.update(.init(command: settings.command(running: true)))
        var events: [(Int64, MetronomeTick)] = []
        for _ in 0..<501 { let frame = timeline.frame; if let event = timeline.nextFrame() { events.append((frame, event)) } }
        XCTAssertEqual(events.map(\.0), [750, 1000])
        XCTAssertEqual(events.map { $0.1.role }, [.subdivision, .downbeat])
        XCTAssertEqual(events.last?.1.beatInBar, 0)
    }
}
