//
//  PlaybackAccessibilityTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-N Tier 1 / C-67.
//
//  **THESE TESTS DO NOT PROVE VOICEOVER BEHAVIOUR.** They prove a label and a
//  value exist, are derived from live state, and are not the word "Slider".
//  Whether VoiceOver announces them sensibly, and in a sensible order, is a
//  physical-device observation this suite cannot make and must never imply.
//

import XCTest
@testable import Etudes

final class PlaybackAccessibilityTests: XCTestCase {

    // MARK: - Spoken durations

    func testSecondsOnly() {
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(0), "0 seconds")
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(1), "1 second")
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(45), "45 seconds")
    }

    func testWholeMinutes() {
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(60), "1 minute")
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(120), "2 minutes")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(83), "1 minute 23 seconds")
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(61), "1 minute 1 second")
    }

    /// Degrades rather than crashes or lies.
    func testNonFiniteAndNegativeAreZero() {
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(.nan), "0 seconds")
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(.infinity), "0 seconds")
        XCTAssertEqual(PlaybackAccessibility.spokenDuration(-5), "0 seconds")
    }

    // MARK: - The scrub value

    func testValueReportsPositionWithinDuration() {
        XCTAssertEqual(PlaybackAccessibility.scrubValue(elapsed: 83, duration: 250),
                       "1 minute 23 seconds of 4 minutes 10 seconds")
    }

    /// **The audio page's own binding tolerates an unknown duration.** The value
    /// must then report the elapsed time ALONE rather than asserting a total
    /// nobody knows.
    func testUnknownDurationDoesNotAssertATotal() {
        for d in [0.0, -1.0, TimeInterval.nan] {
            let v = PlaybackAccessibility.scrubValue(elapsed: 30, duration: d)
            XCTAssertEqual(v, "30 seconds")
            XCTAssertFalse(v.contains(" of "), "must not claim a duration it does not have: \(v)")
        }
    }

    func testElapsedIsClampedToDuration() {
        XCTAssertEqual(PlaybackAccessibility.scrubValue(elapsed: 999, duration: 60),
                       "1 minute of 1 minute")
        XCTAssertEqual(PlaybackAccessibility.scrubValue(elapsed: -10, duration: 60),
                       "0 seconds of 1 minute")
    }

    // MARK: - C-67 itself

    /// The defect was a slider announcing only "Slider".
    func testNoScrubStringIsTheWordSlider() {
        XCTAssertFalse(PlaybackAccessibility.scrubLabel.lowercased().contains("slider"))
        for (e, d) in [(0.0, 0.0), (30.0, 250.0), (250.0, 250.0)] {
            XCTAssertFalse(PlaybackAccessibility.scrubValue(elapsed: e, duration: d)
                .lowercased().contains("slider"))
        }
    }
}
