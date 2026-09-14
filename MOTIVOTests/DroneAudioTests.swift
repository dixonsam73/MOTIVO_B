import XCTest
import AVFoundation
@testable import Etudes

@MainActor
final class DroneAudioTests: XCTestCase {
    func testRendererReceivesActualSourceRateAfterSessionChanges() {
        for rate in [44_100.0, 48_000.0] {
            let output = FakeDroneOutput(rate: rate)
            let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { "route" })
            XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
            XCTAssertEqual(output.renderer?.sampleRate, rate)
            engine.stop()
        }
    }
    func testSetupFailureDoesNotCreateOutputOrShowRunning() {
        let engine = DroneEngine(makeOutput: { XCTFail("Created output after failed setup"); return FakeDroneOutput() },
            activateSession: { throw DroneTestError.failed }, routeIdentity: { "route" })
        XCTAssertFalse(engine.start(frequency: 440, volume: 0.5))
        XCTAssertFalse(engine.isRunning)
    }
    func testFailedEngineStartDoesNotShowRunning() {
        let output = FakeDroneOutput()
        output.failStart = true
        let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { "route" })
        XCTAssertFalse(engine.start(frequency: 440, volume: 0.5))
        XCTAssertFalse(engine.isRunning)
        XCTAssertGreaterThan(output.stopCalls, 0)
    }
    func testInterruptionAndResetStopWithoutAutomaticResume() {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification] {
            let center = NotificationCenter()
            let output = FakeDroneOutput()
            let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { "route" }, notificationCenter: center)
            XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
            center.post(name: name, object: nil, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            XCTAssertFalse(engine.isRunning)
            XCTAssertFalse(output.isRunning)
            center.post(name: AVAudioSession.interruptionNotification, object: nil,
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                           AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
            XCTAssertFalse(engine.isRunning)
        }
    }
    func testOnlyAChangedRouteStopsTheDrone() {
        let center = NotificationCenter()
        let output = FakeDroneOutput()
        var route = "speaker:44100"
        let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { route }, notificationCenter: center)
        XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
        center.post(name: AVAudioSession.routeChangeNotification, object: nil)
        XCTAssertTrue(engine.isRunning)
        route = "usb:48000"
        center.post(name: AVAudioSession.routeChangeNotification, object: nil)
        XCTAssertFalse(engine.isRunning)
    }
    func testConfigurationChangeRequiresExplicitStartWithNewFormat() {
        let center = NotificationCenter()
        var output = FakeDroneOutput(rate: 44_100)
        let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { "route" }, notificationCenter: center)
        XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
        let old = output
        center.post(name: .AVAudioEngineConfigurationChange, object: old.notificationObject)
        XCTAssertFalse(engine.isRunning)
        output = FakeDroneOutput(rate: 48_000)
        XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
        XCTAssertEqual(output.renderer?.sampleRate, 48_000)
        center.post(name: .AVAudioEngineConfigurationChange, object: old.notificationObject)
        XCTAssertTrue(engine.isRunning)
        engine.stop()
    }
    func testOldFadeCannotStopAnExplicitRestart() async throws {
        var output = FakeDroneOutput()
        let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { "route" })
        XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
        engine.stop()
        output = FakeDroneOutput()
        XCTAssertTrue(engine.start(frequency: 220, volume: 0.5))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(output.isRunning)
        engine.stop()
    }
    func testStoppedAudioWithdrawsRunningState() async throws {
        let output = FakeDroneOutput()
        let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { "route" })
        XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
        output.isRunning = false
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(engine.isRunning)
    }
    func testNoRenderProgressWithdrawsRunningState() async throws {
        let output = FakeDroneOutput()
        var now = 0.0
        let engine = DroneEngine(makeOutput: { output }, activateSession: {}, routeIdentity: { "route" }, clock: { now })
        XCTAssertTrue(engine.start(frequency: 440, volume: 0.5))
        now = 2
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(engine.isRunning)
    }
    func testOriginalWaveformGainAndFadeArePreserved() {
        let renderer = DroneRenderKernel(sampleRate: 44_100, frequency: 440, volume: 0.5)
        renderer.beginBuffer()
        var phase = 0.0
        var volume = 0.0
        for _ in 0..<4_410 {
            volume += (0.5 - volume) * 0.002
            phase += 2 * .pi * 440 / 44_100
            if phase > 2 * .pi { phase -= 2 * .pi }
            let original = Float(sin(phase) * volume * 0.9 + sin(2 * phase) * volume * 0.1)
            XCTAssertEqual(renderer.nextSample(), original, accuracy: 0.0000001)
        }
        renderer.mailbox.volume.store(0.0.bitPattern, ordering: .releasing)
        renderer.beginBuffer()
        for _ in 0..<13_230 { _ = renderer.nextSample() }
        XCTAssertLessThan(abs(renderer.nextSample()), 0.000001)
    }
    func testOfflinePitchWithDifferentSourceAndOutputFormats() throws {
        for sourceRate in [44_100.0, 48_000.0] {
            for outputRate in [44_100.0, 48_000.0] {
                let samples = try offlineDrone(sourceRate: sourceRate, outputRate: outputRate)
                let pitch = measuredPitch(samples, rate: outputRate)
                XCTAssertEqual(pitch, 440, accuracy: 0.02, "source=\(sourceRate), output=\(outputRate)")
            }
        }
    }

    private func offlineDrone(sourceRate: Double, outputRate: Double) throws -> [Float] {
        let audio = AVAudioEngine()
        let sourceFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1))
        let outputFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1))
        let renderer = DroneRenderKernel(sampleRate: sourceRate, frequency: 440, volume: 0.5)
        let source = AVAudioSourceNode(format: sourceFormat) { _, _, count, buffers in
            let output = UnsafeMutableAudioBufferListPointer(buffers)
            renderer.beginBuffer()
            for frame in 0..<Int(count) {
                let sample = renderer.nextSample()
                for buffer in output { buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample }
            }
            renderer.endBuffer(frameCount: Int(count))
            return noErr
        }
        audio.attach(source)
        audio.connect(source, to: audio.mainMixerNode, format: sourceFormat)
        try audio.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 1024)
        try audio.start()
        defer { audio.stop() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.manualRenderingFormat, frameCapacity: 1024))
        var result: [Float] = []
        for _ in 0..<Int(outputRate / 1024) + 4 {
            let status = try audio.renderOffline(1024, to: buffer)
            XCTAssertEqual(status, .success)
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            result.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        return result
    }

    private func measuredPitch(_ samples: [Float], rate: Double) -> Double {
        var crossings: [Double] = []
        for index in Int(rate * 0.2)..<(samples.count - 1) where samples[index] <= 0 && samples[index + 1] > 0 {
            crossings.append(Double(index) - Double(samples[index]) / Double(samples[index + 1] - samples[index]))
        }
        guard let first = crossings.first, let last = crossings.last, last > first else { return 0 }
        return Double(crossings.count - 1) * rate / (last - first)
    }
}

private enum DroneTestError: Error { case failed }
@MainActor
private final class FakeDroneOutput: DroneAudioOutput {
    let sourceFormat: AVAudioFormat
    var isRunning = false
    var notificationObject: AnyObject { self }
    var failStart = false
    var stopCalls = 0
    var renderer: DroneRenderKernel?
    init(rate: Double = 44_100) { sourceFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)! }
    func start(renderer: DroneRenderKernel) throws {
        self.renderer = renderer
        if failStart { throw DroneTestError.failed }
        isRunning = true
    }
    func stop() { stopCalls += 1; isRunning = false }
}
