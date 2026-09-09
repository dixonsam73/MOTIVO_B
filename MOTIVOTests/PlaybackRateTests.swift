//
//  PlaybackRateTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-M — the pure rate model.
//
//  **THESE TESTS DO NOT PROVE THAT AUDIO SOUNDS PITCH-CORRECT.** Pitch
//  preservation rests on Apple's documented API contract, recorded in
//  `PlaybackRate.swift` and in the unit's prediction. Nothing here is perceptual
//  or device evidence, and it must never be described as such.
//

import XCTest
@testable import Etudes

final class PlaybackRateTests: XCTestCase {

    func testFiveRatesInOrder() {
        XCTAssertEqual(PlaybackRate.allCases.map(\.rawValue), [0.5, 0.75, 1.0, 1.5, 2.0])
    }

    func testDefaultIsNormal() {
        XCTAssertEqual(PlaybackRate.default, .normal)
        XCTAssertEqual(PlaybackRate.default.rawValue, 1.0)
    }

    /// Apple documents `AVAudioPlayer.rate` as supporting 0.5 through 2.0. The
    /// narrowest stack decides the set, so nothing may fall outside it.
    func testEveryRateIsInsideTheDocumentedAVAudioPlayerRange() {
        for r in PlaybackRate.allCases {
            XCTAssertGreaterThanOrEqual(r.rawValue, 0.5, "\(r) below AVAudioPlayer's documented range")
            XCTAssertLessThanOrEqual(r.rawValue, 2.0, "\(r) above AVAudioPlayer's documented range")
        }
    }

    func testDisplayLabelsUseOneTimesNotOnePointZero() {
        XCTAssertEqual(PlaybackRate.allCases.map(\.displayLabel),
                       ["0.5×", "0.75×", "1×", "1.5×", "2×"])
        XCTAssertFalse(PlaybackRate.normal.displayLabel.contains("1.0"))
    }

    func testAccessibilityStrings() {
        XCTAssertEqual(PlaybackRate.accessibilityLabel, "Playback speed")
        XCTAssertEqual(PlaybackRate.accessibilityHint, "Choose a playback speed")
        XCTAssertEqual(PlaybackRate.threeQuarters.accessibilityValue, "0.75 times")
        XCTAssertEqual(PlaybackRate.allCases.map(\.accessibilityValue),
                       ["0.5 times", "0.75 times", "1 times", "1.5 times", "2 times"])
    }

    /// "Normal" was excluded as product terminology; the menu uses the ordinary
    /// checkmark treatment instead.
    func testNoNormalTerminologyInAnyUserFacingString() {
        for r in PlaybackRate.allCases {
            XCTAssertFalse(r.displayLabel.lowercased().contains("normal"))
            XCTAssertFalse(r.accessibilityValue.lowercased().contains("normal"))
        }
    }

    func testPlayerRateMatchesRawValue() {
        for r in PlaybackRate.allCases {
            XCTAssertEqual(r.playerRate, Float(r.rawValue))
        }
    }

    // MARK: - Structural: the integration, asserted against source

    private func viewer() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("MOTIVO/AttachmentViewerView.swift"), encoding: .utf8)) ?? ""
    }

    /// CODE ONLY, comments stripped.
    ///
    /// **`testEnableRatePrecedesPrepareToPlay` FAILED AGAINST CORRECT CODE
    /// BECAUSE OF THIS.** The comment explaining that `enableRate` must precede
    /// `prepareToPlay()` mentions `prepareToPlay()` — so an ordering assertion
    /// over raw source found the COMMENT first and reported the calls in the
    /// wrong order. **A source-text assertion must target code, and a
    /// well-commented file is exactly the one most likely to defeat it** — the
    /// same failure recorded at `U5c-34` and again in U5d.
    private func viewerCode() -> String {
        viewer()
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Viewer-session ownership: the rate lives on the viewer and is passed down,
    /// so it survives paging and dies with the viewer.
    func testRateIsViewerSessionStateNotPagePrivate() {
        let s = viewerCode()
        XCTAssertTrue(s.contains("@State private var playbackRate: PlaybackRate = .default"),
                      "the viewer must own the rate so it survives paging")
        XCTAssertEqual(s.components(separatedBy: "@Binding var playbackRate: PlaybackRate").count - 1, 3,
                       "MediaPage, VideoPage and AudioPage must each bind the viewer's rate")
    }

    /// It must not be persisted anywhere.
    func testRateIsNotPersisted() {
        let s = viewer()
        for line in s.components(separatedBy: .newlines) where line.contains("playbackRate") {
            XCTAssertFalse(line.contains("UserDefaults"), "playback rate must be ephemeral: \(line)")
            XCTAssertFalse(line.contains("AppStorage"), "playback rate must be ephemeral: \(line)")
        }
    }

    /// THE HAZARD: `AVPlayer.play()` sets rate to 1.0, so a resume path using it
    /// would silently discard the chosen speed.
    ///
    /// **THIS TEST USED TO ASSERT ONLY THAT `playImmediately` APPEARED TWICE, AND
    /// IT PASSED WHILE THE BUG SHIPPED.** A third video play path —
    /// `requestPlay()`, reached from the big centre play button — still called
    /// `play()`, so video always ran at 1×. **Asserting the PRESENCE OF THE FIX
    /// cannot catch a second unfixed path; the absence of the DEFECT can.**
    func testNoAVPlayerPathUsesBarePlay() {
        let s = viewerCode()
        // Scoped by region: `AVAudioPlayer.play()` in `AudioPlayerController` is
        // legitimate — its rate survives pause/resume — and is excluded by where
        // it lives rather than by guessing at the call text.
        guard let videoStart = s.range(of: "private struct VideoPage: View"),
              let audioControllerStart = s.range(of: "private final class AudioPlayerController"),
              let remoteStart = s.range(of: "final class RemoteAudioPlayerController"),
              let audioPageStart = s.range(of: "private struct AudioPage: View") else {
            return XCTFail("viewer regions not found")
        }
        let videoRegion = String(s[videoStart.lowerBound..<audioControllerStart.lowerBound])
        let remoteRegion = String(s[remoteStart.lowerBound..<audioPageStart.lowerBound])

        for (name, region) in [("VideoPage", videoRegion), ("RemoteAudioPlayerController", remoteRegion)] {
            XCTAssertFalse(region.contains("player.play()"),
                           "\(name) must not use bare play(): it resets rate to 1.0")
            XCTAssertFalse(region.contains("player?.play()"),
                           "\(name) must not use bare play(): it resets rate to 1.0")
        }
    }

    /// `AVAudioPlayer.play()` is legitimate and must NOT be swept up by the above.
    func testLocalAudioKeepsItsOwnPlayCalls() {
        let s = viewerCode()
        guard let start = s.range(of: "private final class AudioPlayerController"),
              let end = s.range(of: "final class RemoteAudioPlayerController") else {
            return XCTFail("region not found")
        }
        let region = String(s[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(region.contains("player?.play()"),
                      "AVAudioPlayer.play() is correct here — its rate survives pause/resume")
    }

    /// P5-M fix: the control is its own view, so the high-frequency playback time
    /// state cannot invalidate it while its menu is open.
    func testSpeedControlIsAStandaloneViewIsolatedFromTimeState() {
        let s = viewerCode()
        guard let start = s.range(of: "private struct PlaybackSpeedMenu: View"),
              let end = s.range(of: "private struct MediaPage: View") else {
            return XCTFail("PlaybackSpeedMenu not found")
        }
        let region = String(s[start.lowerBound..<end.lowerBound])
        for forbidden in ["currentTime", "audioCurrentTime", "isPlaying", "duration"] {
            XCTAssertFalse(region.contains(forbidden),
                           "the speed control must not depend on \(forbidden) — that is what rebuilt it 10-30×/s during playback")
        }
        XCTAssertTrue(region.contains("Button {"),
                      "menu items must be Buttons: a Button's action fires on tap, a Picker selection must survive a rebuild")
        XCTAssertTrue(region.contains("checkmark"), "the selected rate keeps the checkmark treatment")
    }

    /// Apple: `enableRate` must be set BEFORE `prepareToPlay()`, or it silently
    /// does nothing.
    func testEnableRatePrecedesPrepareToPlay() {
        let s = viewerCode()
        guard let enable = s.range(of: "enableRate = true"),
              let prepare = s.range(of: "prepareToPlay()") else {
            return XCTFail("local audio rate configuration not found")
        }
        XCTAssertTrue(enable.lowerBound < prepare.lowerBound,
                      "enableRate must be set before prepareToPlay()")
    }

    /// Pitch preservation on the AVPlayer stacks is explicit, not inherited.
    func testBothAVPlayerItemsSetSpectral() {
        let s = viewerCode()
        XCTAssertEqual(s.components(separatedBy: "audioTimePitchAlgorithm = .spectral").count - 1, 2,
                       "video and remote audio items must both set .spectral")
    }

    /// The control is in both transport rows and is fully labelled.
    func testSpeedControlIsPresentAndAccessible() {
        let s = viewerCode()
        XCTAssertEqual(s.components(separatedBy: "PlaybackSpeedMenu(rate:").count - 1, 2,
                       "the control must be placed in BOTH transport rows")
        XCTAssertTrue(s.contains(".accessibilityLabel(PlaybackRate.accessibilityLabel)"))
        XCTAssertTrue(s.contains(".accessibilityValue(rate.accessibilityValue)"))
        XCTAssertTrue(s.contains(".accessibilityHint(PlaybackRate.accessibilityHint)"))
    }

    /// Existing reset semantics must be untouched by this unit.
    func testExistingSeekToZeroOnDisappearIsUnchanged() {
        let s = viewerCode()
        XCTAssertTrue(s.contains("player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)"),
                      "VideoPage's reset-to-start on disappear must survive P5-M")
    }
}
