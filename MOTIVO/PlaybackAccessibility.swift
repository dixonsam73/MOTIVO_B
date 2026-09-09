//
//  PlaybackAccessibility.swift
//  MOTIVO
//
//  PHASE 5 · P5-N Tier 1 / C-67 — the spoken form of a scrub position.
//
//  **WHY THIS EXISTS.** Both scrub sliders in `AttachmentViewerView` bind a
//  `TimeInterval` against a duration, and NEITHER viewer displays that position
//  as text — the file has no time formatter at all. So a VoiceOver value has to
//  be built. Unlabelled, both sliders announce only "Slider", which tells a
//  member nothing about where they are in the recording.
//
//  **IT DEGRADES RATHER THAN LIES.** When the duration is unknown or zero —
//  which the audio page's own binding explicitly tolerates — the value reports
//  the elapsed time ALONE rather than asserting a total nobody knows.
//
//  Plain English, consistent with every other string in the product: there is
//  no localisation catalogue in this project (no `.lproj`, no `.xcstrings`).
//
//  Pure and view-free so it can be tested directly.
//

import Foundation

enum PlaybackAccessibility {

    static let scrubLabel = "Playback position"

    /// "1 minute 23 seconds", spoken rather than positional — VoiceOver reads
    /// "1:23" as a number, not as a time.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.isFinite && seconds > 0 ? seconds.rounded() : 0)
        let m = total / 60
        let s = total % 60
        switch (m, s) {
        case (0, _):
            return "\(s) second\(s == 1 ? "" : "s")"
        case (_, 0):
            return "\(m) minute\(m == 1 ? "" : "s")"
        default:
            return "\(m) minute\(m == 1 ? "" : "s") \(s) second\(s == 1 ? "" : "s")"
        }
    }

    /// The slider's spoken value. `duration <= 0` means "not known yet".
    static func scrubValue(elapsed: TimeInterval, duration: TimeInterval) -> String {
        guard duration.isFinite, duration > 0 else {
            return spokenDuration(elapsed)
        }
        let clamped = min(max(elapsed, 0), duration)
        return "\(spokenDuration(clamped)) of \(spokenDuration(duration))"
    }
}
