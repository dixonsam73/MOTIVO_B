//
//  ConnectedAudioDerivative.swift
//  MOTIVO
//
//  PHASE 5 · UNIT 1 — THE CONNECTED AUDIO REPRESENTATION.
//
//  **Policy A: the local Journal keeps the original; Connected carries a
//  derived M4A/AAC representation.** The same principle PDF already uses — local
//  PDF, Connected JPEG. **The local original is never mutated, renamed or
//  replaced.**
//
//  **WHY A WRITER RATHER THAN `AVAssetExportPresetAppleM4A`:** the preset cannot
//  set a bitrate and lands near 128 kbps. This is a musician's product, so the
//  target is ~256 kbps — measured at ~1.4-1.9 MB/min, leaving 50 MB covering
//  well over twenty minutes. Sample rate and channel count are read from the
//  SOURCE and preserved, never hard-coded.
//
//  **THE ARITHMETIC PREFLIGHT IS NOT A SUBSTITUTE FOR THIS.** `predictedBytes`
//  exists so the member never waits at Save; it is an estimate. The real size is
//  checked after conversion, before upload, by the caller.
//

import Foundation
import AVFoundation

enum ConnectedAudioDerivative {

    /// ~256 kbps AAC. Approved as the quality target; NOT to be silently
    /// lowered to make a file fit.
    static let targetBitrate = 256_000

    /// **MEASURED WORST CASE, and it is why a margin exists.** With white noise
    /// — the maximally incompressible signal — the encoder EXCEEDS the request:
    /// 263 kbps for a 256 k ask, a ratio of 1.0257. So `duration × bitrate` is
    /// **not** an upper bound. 1.10 is roughly four times that measured excess.
    static let safetyMargin = 1.10

    /// Conservative estimate, for the pre-queue decision only.
    static func predictedBytes(durationSeconds: Double) -> Int {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }
        return Int((durationSeconds * Double(targetBitrate) / 8.0) * safetyMargin)
    }

    /// The longest source whose derivative is predicted to fit. ~24.8 minutes.
    static func maxPredictedDurationSeconds(limitBytes: Int) -> Double {
        (Double(limitBytes) / safetyMargin) * 8.0 / Double(targetBitrate)
    }

    /// Owns the three AVFoundation objects the encode loop touches.
    ///
    /// **`@unchecked Sendable` is justified, not waved through:**
    /// `requestMediaDataWhenReady(on:)` invokes its block SERIALLY on the queue
    /// it is given, and nothing else touches these objects for the lifetime of
    /// the export — so there is exactly one accessor at a time. Without this the
    /// compiler reports three non-Sendable captures, which was measured as the
    /// only warning delta this type introduced.
    private final class Pump: @unchecked Sendable {
        private let reader: AVAssetReaderTrackOutput
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput

        init(reader: AVAssetReaderTrackOutput, writer: AVAssetWriter, input: AVAssetWriterInput) {
            self.reader = reader; self.writer = writer; self.input = input
        }

        func run(on queue: DispatchQueue, completion: @escaping @Sendable () -> Void) {
            input.requestMediaDataWhenReady(on: queue) { [reader, writer, input] in
                while input.isReadyForMoreMediaData {
                    if let buffer = reader.copyNextSampleBuffer() {
                        input.append(buffer)
                    } else {
                        input.markAsFinished()
                        writer.finishWriting { completion() }
                        return
                    }
                }
            }
        }
    }

    enum Failure: LocalizedError {
        case noAudioTrack
        case cannotStart
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "The audio file has no playable audio track"
            case .cannotStart: return "Could not start the audio conversion"
            case .writeFailed(let d): return "Audio conversion failed: \(d)"
            }
        }
    }

    /// Converts `source` to AAC-in-M4A at `targetBitrate`, preserving the
    /// source's sample rate and channel count. Off the main actor by
    /// construction: the pump runs on its own queue.
    static func make(from source: URL, to destination: URL) async throws -> (bytes: Int, seconds: Double, elapsedMs: Int) {
        let started = Date()
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw Failure.noAudioTrack
        }

        let asbd = try await track.load(.formatDescriptions).first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sampleRate = asbd?.mSampleRate ?? 44_100
        let channels = Int(asbd?.mChannelsPerFrame ?? 2)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: targetBitrate
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { throw Failure.cannotStart }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "etudes.connected.audio.derivative")
        let pump = Pump(reader: output, writer: writer, input: input)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pump.run(on: queue) { cont.resume() }
        }

        guard writer.status == .completed else {
            throw Failure.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? NSNumber)?.intValue ?? 0
        let seconds = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        return (bytes, seconds, elapsedMs)
    }
}
