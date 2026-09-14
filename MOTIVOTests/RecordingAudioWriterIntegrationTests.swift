import XCTest
import AVFoundation
@testable import Etudes

final class RecordingAudioWriterIntegrationTests: XCTestCase {
    /// Real PCM sample buffers, AAC writer and saved MOV track. Readiness is held
    /// artificially; no camera/microphone or claim of a physical encoder stall is involved.
    func testQueuedAudioMatchesDirectWritingAfterStopAndDecodesCompletely() async throws {
        let direct = try await writeClip(queued: false)
        let recovered = try await writeClip(queued: true)
        // Compare the container with a direct-write control: a MOV track's header
        // can start at zero even when the original sample timestamps start later.
        XCTAssertEqual(recovered.start, direct.start, accuracy: 1 / 44_100.0)
        XCTAssertEqual(recovered.duration, direct.duration, accuracy: 1 / 44_100.0)
        XCTAssertEqual(recovered.firstDecodedPTS, direct.firstDecodedPTS, accuracy: 1 / 44_100.0)
        XCTAssertEqual(recovered.frames, direct.frames)
        XCTAssertGreaterThanOrEqual(recovered.frames, 11 * 1024)
        print("[RecordingAudioFixture] direct/recovered start=\(direct.start)/\(recovered.start) duration=\(direct.duration)/\(recovered.duration) decodedFirstPTS=\(direct.firstDecodedPTS)/\(recovered.firstDecodedPTS) frames=\(direct.frames)/\(recovered.frames)")
    }

    private func writeClip(queued: Bool) async throws -> (start: Double, duration: Double, firstDecodedPTS: Double, frames: Int) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000
        ])
        input.expectsMediaDataInRealTime = true
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let queue = DispatchQueue(label: "test.real.recording.audio.writer")
        let finished = expectation(description: "Real audio writer finished")
        let chunks = try (0..<12).map { try makeAudioBuffer(index: $0) }
        let control = WriterFixtureControl()
        let delivery = BufferedRecordingAudio<CMSampleBuffer>(queue: queue,
            isWriting: { writer.status == .writing },
            isReady: { control.releaseReadiness && input.isReadyForMoreMediaData },
            append: { buffer in
                control.writtenPTS.append(CMSampleBufferGetPresentationTimeStamp(buffer).seconds)
                return input.append(buffer)
            },
            timestamp: { CMSampleBufferGetPresentationTimeStamp($0).seconds },
            onFailure: { failure in XCTFail("Audio delivery failed: \(failure)") })
        if queued {
            queue.sync {
                for chunk in chunks { delivery.receive(chunk) }
                delivery.finish { failure in
                    XCTAssertNil(failure)
                    input.markAsFinished()
                    writer.finishWriting { finished.fulfill() }
                }
            }
            // Stop is already requested, and there will be no new capture callback.
            queue.asyncAfter(deadline: .now() + 0.025) { control.releaseReadiness = true }
        } else {
            // Control deliberately bypasses BufferedRecordingAudio altogether.
            queue.sync {
                for chunk in chunks {
                    XCTAssertTrue(input.isReadyForMoreMediaData)
                    XCTAssertTrue(input.append(chunk))
                }
                input.markAsFinished()
                writer.finishWriting { finished.fulfill() }
            }
        }
        await fulfillment(of: [finished], timeout: 5)
        queue.sync {
            delivery.cancel()
            if queued {
                XCTAssertEqual(control.writtenPTS.count, chunks.count)
                for (index, pts) in control.writtenPTS.enumerated() {
                    XCTAssertEqual(pts, 0.05 + Double(index * 1024) / 44_100, accuracy: 0.00000001)
                }
            }
        }
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let range = try await track.load(.timeRange)
        // The track range includes the leading empty edit; compare its end on the presentation timeline.
        XCTAssertEqual(range.end.seconds, 0.05 + Double(12 * 1024) / 44_100, accuracy: 0.024)
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        XCTAssertTrue(reader.canAdd(decoded))
        reader.add(decoded)
        XCTAssertTrue(reader.startReading())
        var frames = 0
        var firstPTS: Double?
        while let buffer = decoded.copyNextSampleBuffer() {
            if firstPTS == nil { firstPTS = CMSampleBufferGetPresentationTimeStamp(buffer).seconds }
            frames += CMSampleBufferGetNumSamples(buffer)
        }
        XCTAssertEqual(reader.status, .completed)
        return (range.start.seconds, range.duration.seconds, try XCTUnwrap(firstPTS), frames)
    }

    private func makeAudioBuffer(index: Int) throws -> CMSampleBuffer {
        let frames = 1024
        let samples = (0..<frames).map { Float(sin(2 * .pi * 440 * Double(index * frames + $0) / 44_100) * 0.2) }
        var format = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
            memoryBlock: nil, blockLength: frames * 4, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: frames * 4, flags: 0,
            blockBufferOut: &block), noErr)
        let data = try XCTUnwrap(block)
        samples.withUnsafeBytes { bytes in
            XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: data,
                offsetIntoDestination: 0, dataLength: bytes.count), noErr)
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100),
            presentationTimeStamp: CMTime(seconds: 0.05, preferredTimescale: 44_100) + CMTime(value: Int64(index * frames), timescale: 44_100),
            decodeTimeStamp: .invalid)
        var size = 4
        var buffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
            formatDescription: try XCTUnwrap(description), sampleCount: frames, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &buffer), noErr)
        return try XCTUnwrap(buffer)
    }
}

// Accessed only on the fixture writer queue.
private final class WriterFixtureControl: @unchecked Sendable {
    var releaseReadiness = false
    var writtenPTS: [Double] = []
}
