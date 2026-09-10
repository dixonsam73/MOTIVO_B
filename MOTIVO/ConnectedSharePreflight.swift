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
//  **IT IS ARITHMETIC, NOT TRANSCODING.** Measured, 10 minutes of WAV takes ~7 s
//  to convert on a Mac and more on a device — so transcoding here would make the
//  member wait at Save. Instead the derivative's size is PREDICTED from duration
//  and the conversion happens later in the queue flush.
//
//  **THE PREDICTION IS AN OPTIMISATION, NEVER A SUBSTITUTE FOR VALIDATION.** The
//  real derivative is still checked against the real ceiling before upload.
//
//  Pure and view-free so the decision can be tested directly.
//

import Foundation
import AVFoundation

enum ConnectedSharePreflight {

    struct Candidate {
        let id: UUID
        let format: MediaFormat?
        let localBytes: Int
        /// Known for audio and video; `nil` when it does not apply.
        let durationSeconds: Double?

        init(id: UUID, format: MediaFormat?, localBytes: Int, durationSeconds: Double? = nil) {
            self.id = id; self.format = format
            self.localBytes = localBytes; self.durationSeconds = durationSeconds
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

    static func consentTitle(count: Int) -> String {
        count == 1 ? "Attachment too large to share" : "Attachments too large to share"
    }

    /// Builds a candidate from a staged attachment.
    ///
    /// **Shared by BOTH publish call sites**, so the two views ask the same
    /// question of the same data rather than growing two consent models.
    /// Duration comes from `AVAudioPlayer`, which reads it cheaply and
    /// synchronously — the decision is arithmetic and must not make Save async.
    static func candidate(forStaged id: UUID,
                          data: Data,
                          kind: AttachmentKind,
                          sourceFormat: MediaFormat?) -> Candidate {
        var seconds: Double?
        if kind == .audio { seconds = (try? AVAudioPlayer(data: data))?.duration }
        return Candidate(id: id, format: sourceFormat, localBytes: data.count, durationSeconds: seconds)
    }
}
