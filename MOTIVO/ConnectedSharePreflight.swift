//
//  ConnectedSharePreflight.swift
//  MOTIVO
//
//  PHASE 5 · UNIT 1 — THE PRE-QUEUE DECISION.
//
//  **IT OPERATES ONLY ON EXPLICITLY SHARE-ENABLED ATTACHMENTS.** Attachments are
//  default-private and the member turns the private-eye off per attachment. A
//  private 500 MB video is irrelevant to Connected: it is never inspected, never
//  warned about, and never blocks a post.
//
//  **SIZE IS ARITHMETIC, NOT TRANSCODING.** Measured, 10 minutes of WAV takes
//  ~7 s to convert on a Mac and more on a device — so transcoding here would make
//  the member wait at Save. Instead the derivative's size is PREDICTED from
//  duration and the conversion happens later in the queue flush.
//
//  **THE PREDICTION IS AN OPTIMISATION, NEVER A SUBSTITUTE FOR VALIDATION.** The
//  real derivative is still checked against the real ceiling before upload.
//
//  **C-73 TYPE 1 — PREPARABILITY.** An attachment that can NEVER be prepared for
//  upload must not be queued into a publish that can never succeed. A PDF is
//  checked with the SAME renderer and page the upload uses, so the verdicts
//  agree; audio that needs a derivative must at least open in `AVAudioPlayer`
//  — the best cheap signal, NOT exact parity with the flush-time converter (a
//  file that opens but still fails to convert remains a retry). Either failure
//  goes through the existing omission consent.
//
//  Pure and view-free so the decision can be tested directly.
//

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

enum ConnectedSharePreflight {

    struct Candidate {
        let id: UUID
        let format: MediaFormat?
        let localBytes: Int
        /// Known for audio and video; `nil` when it does not apply.
        let durationSeconds: Double?
        /// C-73: false when the attachment can never be prepared for upload.
        let preparable: Bool

        init(id: UUID, format: MediaFormat?, localBytes: Int, durationSeconds: Double? = nil, preparable: Bool = true) {
            self.id = id; self.format = format
            self.localBytes = localBytes; self.durationSeconds = durationSeconds
            self.preparable = preparable
        }
    }

    enum Verdict: Equatable {
        /// Publishes as-is or via a derivative predicted to fit.
        case canShare
        /// Nothing Études can do automatically: the member must be asked.
        case needsConsent
    }

    /// The decision for ONE explicitly share-enabled attachment.
    static func verdict(for c: Candidate, limitBytes: Int) -> Verdict {
        // C-73: an attachment that can never be prepared would fail on every
        // flush forever. Ask now, through the same consent as oversize.
        guard c.preparable else { return .needsConsent }

        // Policy A: deliberate audio always publishes as an M4A/AAC derivative,
        // so the LOCAL size is irrelevant — a 200 MB WAV is not rejected for
        // being 200 MB. Only the predicted derivative decides.
        if let format = c.format, format.needsConnectedAudioDerivative {
            guard let seconds = c.durationSeconds, seconds > 0 else {
                // Duration unknown: fall back to the local size rather than
                // guessing that a derivative will fit.
                return c.localBytes <= limitBytes ? .canShare : .needsConsent
            }
            return ConnectedAudioDerivative.predictedBytes(durationSeconds: seconds) <= limitBytes
                ? .canShare : .needsConsent
        }

        // Everything else — images, video, PDF — publishes from the local file,
        // so its own size decides. Video has NO automatic optimisation in this
        // unit; that is C-75, and until it exists an oversized shared video asks
        // for consent rather than being silently omitted.
        return c.localBytes <= limitBytes ? .canShare : .needsConsent
    }

    /// Every attachment that cannot be shared automatically.
    static func requiringConsent(_ candidates: [Candidate], limitBytes: Int) -> [Candidate] {
        candidates.filter { verdict(for: $0, limitBytes: limitBytes) == .needsConsent }
    }

    /// Restrained copy: one alert however many attachments are involved, and no
    /// attachment-management surface.
    static func consentMessage(count: Int) -> String {
        count == 1
            ? "This attachment can’t be included in this Connected post. It will remain in your Journal."
            : "\(count) attachments can’t be included in this Connected post. They will remain in your Journal."
    }

    /// CAUSE-NEUTRAL (C-73): the same dialog now covers attachments that cannot be
    /// prepared as well as oversized ones, so it names no reason. It used to read
    /// "Attachment too large to share", which would be false for a PDF with no
    /// renderable page.
    static func consentTitle(count: Int) -> String {
        count == 1 ? "Attachment can’t be shared" : "Attachments can’t be shared"
    }

    /// Builds a candidate from a STAGED attachment.
    ///
    /// **Shared by BOTH publish call sites**, so the two views ask the same
    /// question of the same data rather than growing two consent models.
    /// Duration comes from `AVAudioPlayer`, which reads it cheaply and
    /// synchronously — the decision must not make Save async.
    static func candidate(forStaged id: UUID,
                          data: Data,
                          kind: AttachmentKind,
                          sourceFormat: MediaFormat?) -> Candidate {
        var seconds: Double?
        var preparable = true
        switch kind {
        case .audio:
            let player = try? AVAudioPlayer(data: data)
            seconds = player?.duration
            if sourceFormat?.needsConnectedAudioDerivative == true { preparable = (player != nil) }
        case .pdf:
            #if canImport(UIKit)
            preparable = AttachmentStore.generatePDFThumbnail(
                data: data,
                cacheKey: "preflight-\(id.uuidString)",
                page: PDFSelectedPagesStore.pages(for: id)?.first) != nil
            #endif
        case .image, .video, .file:
            break
        }
        return Candidate(id: id, format: sourceFormat, localBytes: data.count,
                         durationSeconds: seconds, preparable: preparable)
    }

    /// Builds a candidate from a PERSISTED attachment — the same rules as
    /// `candidate(forStaged:)`, read from the file. C-73: this used to be built
    /// inline in `AddEditSessionView`, a second copy of the rules.
    static func candidate(forPersisted id: UUID, url: URL) -> Candidate {
        let bytes = Int((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                        ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
                        ?? 0)
        let format = MediaFormat.from(url: url)
        var seconds: Double?
        var preparable = true
        switch format?.kind {
        case .audio?:
            let player = try? AVAudioPlayer(contentsOf: url)
            seconds = player?.duration
            if format?.needsConnectedAudioDerivative == true { preparable = (player != nil) }
        case .pdf?:
            #if canImport(UIKit)
            preparable = AttachmentStore.generatePDFThumbnail(
                url: url,
                page: PDFSelectedPagesStore.pages(for: id)?.first) != nil
            #endif
        default:
            break
        }
        return Candidate(id: id, format: format, localBytes: bytes,
                         durationSeconds: seconds, preparable: preparable)
    }
}
