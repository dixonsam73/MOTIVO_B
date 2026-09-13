import XCTest
import Dispatch
@testable import Etudes

final class MetronomeRenderTests: XCTestCase {
    private func render(bank: MetronomeSoundBank, settings: MetronomeSettings, count: Int, buffers: [Int]) -> [Float] {
        let mailbox = MetronomeMailbox(settings: settings)
        let renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
        var samples: [Float] = []; samples.reserveCapacity(count)
        var index = 0
        while samples.count < count {
            let length = min(buffers[index % buffers.count], count - samples.count)
            renderer.beginBuffer()
            for _ in 0..<length { samples.append(renderer.nextSample()) }
            renderer.endBuffer(frameCount: length); index += 1
        }
        return samples
    }
    func testAudioIsIdenticalAcrossVariableBufferBoundaries() throws {
        let bank = try MetronomeTestSamples.bank(rate: 48000)
        var settings = MetronomeSettings(); settings.bpm = 137; settings.accent = true; settings.subdivision = .triplets
        let a = render(bank: bank, settings: settings, count: 96000, buffers: [256])
        let b = render(bank: bank, settings: settings, count: 96000, buffers: [1, 127, 1024, 13, 511])
        XCTAssertEqual(a, b)
    }
    func testStopClearsTailsAtNextRenderBoundary() throws {
        let bank = try MetronomeTestSamples.bank()
        var settings = MetronomeSettings(); settings.accent = true
        let mailbox = MetronomeMailbox(settings: settings), renderer: MetronomeRenderKernel
        renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
        renderer.beginBuffer(); for _ in 0..<500 { _ = renderer.nextSample() }
        mailbox.command.store(settings.command(running: false), ordering: .releasing)
        renderer.beginBuffer()
        for _ in 0..<1000 { XCTAssertEqual(renderer.nextSample(), 0) }
    }
    func testVolumeZeroMutesAlreadyPlayingTail() throws {
        let bank = try MetronomeTestSamples.bank()
        var settings = MetronomeSettings(); settings.accent = true
        let mailbox = MetronomeMailbox(settings: settings)
        let renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
        renderer.beginBuffer(); for _ in 0..<500 { _ = renderer.nextSample() }
        settings.volume = 0; mailbox.command.store(settings.command(running: true), ordering: .releasing)
        renderer.beginBuffer()
        for _ in 0..<1000 { XCTAssertEqual(renderer.nextSample(), 0) }
    }
    func testRestartBeginsWithCleanDownbeatAndNoOldTails() throws {
        let bank = try MetronomeTestSamples.bank()
        var settings = MetronomeSettings(); settings.bpm = 400; settings.accent = true; settings.subdivision = .semiquavers
        let mailbox = MetronomeMailbox(settings: settings)
        let renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
        renderer.beginBuffer(); for _ in 0..<3000 { _ = renderer.nextSample() }
        mailbox.command.store(settings.command(running: false), ordering: .releasing); renderer.beginBuffer()
        mailbox.command.store(settings.command(running: true), ordering: .releasing); renderer.beginBuffer()
        let restarted = (0..<2000).map { _ in renderer.nextSample() }
        let fresh = render(bank: bank, settings: settings, count: 2000, buffers: [256])
        XCTAssertEqual(restarted, fresh)
    }
    func testFastestSubdivisionsDoNotClipInCompoundOrAsymmetricMeters() throws {
        let bank = try MetronomeTestSamples.bank(rate: 48000)
        for meter: MetronomeMeter in [.compound(6), .asymmetric(11)] {
            var settings = MetronomeSettings(); settings.bpm = 400; settings.meter = meter
            settings.accent = true; settings.subdivision = .semiquavers; settings.volume = 1
            let mailbox = MetronomeMailbox(settings: settings)
            let renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
            renderer.beginBuffer()
            for _ in 0..<96000 { _ = renderer.nextSample() }
            XCTAssertLessThan(renderer.maximumUnclampedSample, 1)
        }
    }
    func testAccentIsReducedThreeDecibelsWithBeatAndSubdivisionGainsPreserved() throws {
        let bank = try MetronomeTestSamples.bank(rate: 48000)
        var settings = MetronomeSettings(); settings.bpm = 60; settings.accent = true
        settings.subdivision = .quavers; settings.volume = 1
        let samples = render(bank: bank, settings: settings, count: 49000, buffers: [256])
        for index in 0..<960 {
            XCTAssertEqual(samples[index], bank.sample(0, index) * Float(pow(10.0, -3.0 / 20.0)), accuracy: 0.000001)
            XCTAssertEqual(samples[24000 + index], bank.sample(2, index) * 0.14, accuracy: 0.000001)
            XCTAssertEqual(samples[48000 + index], bank.sample(1, index) * 0.35, accuracy: 0.000001)
        }
    }
    func testVisualEventsCountOnlyPrimaryBeats() throws {
        let bank = try MetronomeTestSamples.bank()
        var settings = MetronomeSettings(); settings.bpm = 120; settings.accent = true; settings.subdivision = .semiquavers
        let mailbox = MetronomeMailbox(settings: settings)
        let renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
        renderer.beginBuffer(); for _ in 0..<44100 { _ = renderer.nextSample() }
        XCTAssertEqual(mailbox.beat.load(ordering: .acquiring) >> 1, 2)
    }
    func testConcurrentControlAndRenderUseCoherentAtomicSnapshots() throws {
        let bank = try MetronomeTestSamples.bank()
        let mailbox = MetronomeMailbox(settings: MetronomeSettings())
        let renderer = MetronomeRenderKernel(bank: bank, mailbox: mailbox)
        DispatchQueue.concurrentPerform(iterations: 2) { worker in
            if worker == 0 {
                for index in 0..<10000 {
                    var settings = MetronomeSettings(); settings.bpm = 20 + index % 381
                    settings.accent = index % 2 == 0; settings.volume = Double(index % 100) / 100
                    mailbox.command.store(settings.command(running: index % 31 != 0), ordering: .releasing)
                    _ = mailbox.beat.load(ordering: .acquiring)
                    _ = mailbox.frames.load(ordering: .acquiring)
                }
            } else {
                for _ in 0..<1000 {
                    renderer.beginBuffer()
                    for _ in 0..<128 { _ = renderer.nextSample() }
                    renderer.endBuffer(frameCount: 128)
                }
            }
        }
        XCTAssertTrue(renderer.maximumUnclampedSample.isFinite)
    }
}
