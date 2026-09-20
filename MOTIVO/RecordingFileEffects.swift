//
//  RecordingFileEffects.swift
//  MOTIVO
//
//  CHANGE-ID: 20260920_150000_C97_PendingStartCancellation
//  SCOPE: C-97 — the seam through which a cancelled start's file effects run, so file
//  PRESERVATION can be tested on real files rather than modelled.
//  SEARCH-TOKEN: 20260920_150000_C97_PendingStartCancellation
//

import Foundation
import AVFoundation

/// C-97. A cancellation's only file effect, behind an injectable seam.
///
/// The seam exists because a pure decision test cannot establish that an existing take
/// survived: it can only assert which url a model *said* to delete. These closures are
/// the real effect, so a test can drive the real implementation against real files and
/// assert the reviewed take is byte-identical afterwards.
///
/// **The url is always supplied by the caller from the claim's immutable `url`.** Nothing
/// here re-reads `recordingURL`, which is mutable main-thread state and may by then name
/// a newer start or a reviewed take.
struct RecordingFileEffects {
    var removeFile: (URL) -> Void = { url in
        try? FileManager.default.removeItem(at: url)
    }
    var cancelWriting: (AVAssetWriter) -> Void = { writer in
        // `cancelWriting` is only legal once writing has begun; `.unknown` means
        // startWriting never ran, and there is nothing to cancel.
        if writer.status == .writing { writer.cancelWriting() }
    }
}
