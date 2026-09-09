//
//  PlaybackRate.swift
//  MOTIVO
//
//  PHASE 5 · P5-M — playback speed for the attachment viewer.
//
//  PURE BY DESIGN: no player types, no UIKit, no AVFoundation. The rate model and
//  its strings are decided here so they can be tested without a player, a file or
//  a device.
//
//  ── PITCH ─────────────────────────────────────────────────────────────────
//
//  Changing rate must never transpose musical material. That is guaranteed by
//  the two player APIs rather than by anything here:
//
//    * `AVAudioPlayer` — Apple's documentation states, on `rate`:
//      "Adjusting the audio's playback rate doesn't alter its pitch."
//    * `AVPlayer` — `AVPlayerItem.audioTimePitchAlgorithm` defaults to
//      `.timeDomain` on iOS 15+, and this app sets `.spectral` explicitly, which
//      Apple documents as "often the best choice ... assuming that it is
//      desirable to maintain a constant pitch".
//
//  **THAT IS A DOCUMENTED API CONTRACT, NOT A MEASUREMENT.** No listening test
//  was performed and none is claimed.
//
//  ── THE RANGE IS NOT ARBITRARY ────────────────────────────────────────────
//
//  Apple documents `AVAudioPlayer.rate` as supporting "0.5 for half-speed
//  playback to 2.0 for double-speed playback". The set below sits inside that
//  range at both ends, so the narrowest of the three player stacks is the one
//  the choice was fitted to.
//

import Foundation

/// The playback speeds offered in the attachment viewer.
enum PlaybackRate: Double, CaseIterable, Identifiable, Sendable {
    case half           = 0.5
    case threeQuarters  = 0.75
    case normal         = 1.0
    case oneAndAHalf    = 1.5
    case double         = 2.0

    static let `default`: PlaybackRate = .normal

    var id: Double { rawValue }

    /// The value handed to a player.
    var playerRate: Float { Float(rawValue) }

    /// Shown on the control's face. **`1×`, never `1.0×`** — the face is small
    /// and the extra character buys nothing.
    var displayLabel: String {
        switch self {
        case .half:          return "0.5×"
        case .threeQuarters: return "0.75×"
        case .normal:        return "1×"
        case .oneAndAHalf:   return "1.5×"
        case .double:        return "2×"
        }
    }

    /// Spoken by VoiceOver as the control's value.
    ///
    /// Deliberately mechanical — "1 times" rather than "normal speed" — because
    /// "Normal" was excluded as product terminology, and inventing it only for
    /// the accessibility value would make the spoken control disagree with the
    /// visible one.
    var accessibilityValue: String {
        switch self {
        case .half:          return "0.5 times"
        case .threeQuarters: return "0.75 times"
        case .normal:        return "1 times"
        case .oneAndAHalf:   return "1.5 times"
        case .double:        return "2 times"
        }
    }

    static let accessibilityLabel = "Playback speed"
    static let accessibilityHint  = "Choose a playback speed"
}
