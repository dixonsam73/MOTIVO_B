//
//  TransportAccessibilityLabelTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-N Tier 1 — the structural control for C-11 and C-67.
//
//  **ABSENCE OF THE DEFECT, NOT PRESENCE OF THE FIX.** C-11 was a control
//  announcing another control's action, and the only assertion that could have
//  caught it is that adjacent actionable controls do not SHARE a label. A test
//  that merely checked "the favourite button has a label" would have passed
//  against the defect.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`, and three times since).
//
//  **STATED LIMITATION.** Source cannot establish VoiceOver behaviour. These
//  assertions prove labels exist, are state-derived and are distinct. They say
//  nothing about how any of it is announced.
//
//  **SCOPE: the two Tier-1 files only.** The ~49 Tier-2 candidates in other
//  files are deliberately not asserted on — they are an unverified candidate
//  inventory, not defects, and not a quality metric.
//

import XCTest
@testable import Etudes

final class TransportAccessibilityLabelTests: XCTestCase {

    private func code(_ file: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(file)"), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Every string a control in this region can ANNOUNCE — including both arms
    /// of a state ternary.
    ///
    /// **The first version of this only matched a bare string literal, and it
    /// failed against the CORRECT code**: the favourite and share labels are
    /// ternaries, so the region yielded one label and the uniqueness check had
    /// nothing to compare. A label extractor that cannot see a state-dependent
    /// label is blind to exactly the controls this unit added.
    private func literalLabels(in region: String) -> [String] {
        let arg = try! NSRegularExpression(pattern: #"\.accessibilityLabel\(([^)]*)\)"#)
        let str = try! NSRegularExpression(pattern: #""([^"]*)""#)
        let ns = region as NSString
        var out: [String] = []
        for m in arg.matches(in: region, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            let ins = inner as NSString
            for sm in str.matches(in: inner, range: NSRange(location: 0, length: ins.length)) {
                out.append(ins.substring(with: sm.range(at: 1)))
            }
        }
        return out
    }

    private func region(_ src: String, from: String, to: String) -> String {
        guard let a = src.range(of: from) else { return "" }
        let rest = src[a.upperBound...]
        let end = rest.range(of: to)?.lowerBound ?? rest.endIndex
        return String(rest[rest.startIndex..<end])
    }

    // MARK: - C-11

    private func actionRow() -> String {
        // The row runs from the favourite button's toggleSaved call to the
        // container's accessibilityElement modifier.
        region(code("SessionDetailView.swift"),
               from: "FeedInteractionStore.toggleSaved",
               to: ".accessibilityElement(children: .contain)")
    }

    func testActionRowIsFound() {
        XCTAssertFalse(actionRow().isEmpty, "the SessionDetailView action row must be locatable")
    }

    /// **THE C-11 ASSERTION.** No two actionable controls in that row may share
    /// a label. Against pre-fix HEAD the favourite and comments buttons both
    /// said "Open comments" and this fails.
    func testAdjacentActionableControlsDoNotShareALabel() {
        let labels = literalLabels(in: actionRow())
        XCTAssertGreaterThanOrEqual(labels.count, 4, "expected every labelled control in the row, ternary arms included")
        XCTAssertEqual(Set(labels).count, labels.count,
                       "adjacent controls must not share an accessibility label; found \(labels)")
    }

    /// The genuine comments button keeps its own label, byte for byte.
    func testCommentsLabelPreserved() {
        XCTAssertTrue(actionRow().contains(#".accessibilityLabel("Open comments")"#),
                      "the real comments control must keep its existing label")
    }

    /// The favourite control follows its state rather than describing an icon.
    func testFavouriteLabelIsStateDerived() {
        let row = actionRow()
        XCTAssertTrue(row.contains(#"isSavedLocal ? "Remove from favourites" : "Add to favourites""#),
                      "the favourite control's label must follow isSavedLocal")
    }

    /// The share control in the same row was unlabelled.
    func testShareControlIsLabelled() {
        XCTAssertTrue(actionRow().contains(#"session.isThought ? "Share thought" : "Share session""#),
                      "the share control must be labelled, and truthful for a Thought")
    }

    // MARK: - C-67

    private func viewer() -> String { code("AttachmentViewerView.swift") }

    /// Every transport control named by the C-67 census carries a label,
    /// **asserted PER PAGE**.
    ///
    /// **The first version searched the whole file and was vacuous.** Video and
    /// audio carry the SAME label strings, so deleting the video row's
    /// "Skip forward 10 seconds" still passed on the audio row's copy —
    /// presence-of-the-fix again, the exact defect P5-M was caught by. Region
    /// scoping is what makes each row's absence detectable.
    func testTransportControlsAreLabelledInBothPages() {
        let v = viewer()
        let video = region(v, from: "private struct VideoPage: View {", to: "private struct AudioPage: View {")
        let audio = region(v, from: "private struct AudioPage: View {", to: "\u{0}NEVER")
        XCTAssertFalse(video.isEmpty, "VideoPage region must be locatable")
        XCTAssertFalse(audio.isEmpty, "AudioPage region must be locatable")

        let shared = [
            #"isMuted ? "Unmute" : "Mute""#,
            #".accessibilityLabel("Skip back 10 seconds")"#,
            #".accessibilityLabel("Skip forward 10 seconds")"#,
        ]
        for expected in shared {
            XCTAssertTrue(video.contains(expected), "VideoPage is missing: \(expected)")
            XCTAssertTrue(audio.contains(expected), "AudioPage is missing: \(expected)")
        }

        // Video's inline transport is PAUSE-ONLY by construction: when not
        // playing the slot is Color.clear and play is the centre overlay.
        XCTAssertTrue(video.contains(#".accessibilityLabel("Pause")"#), "VideoPage pause is unlabelled")
        // Audio's single button changes meaning with state, so its label must too.
        XCTAssertTrue(audio.contains(#"isPlaybackPlaying ? "Pause" : "Play""#),
                      "AudioPage play/pause label must follow state")
    }

    /// Both scrub sliders carry a label AND a value, and neither says "Slider".
    func testBothScrubSlidersHaveLabelAndValue() {
        let v = viewer()
        XCTAssertEqual(v.components(separatedBy: "PlaybackAccessibility.scrubLabel").count - 1, 2,
                       "both scrub sliders must carry the scrub label")
        XCTAssertEqual(v.components(separatedBy: "PlaybackAccessibility.scrubValue").count - 1, 2,
                       "both scrub sliders must expose a value")
        XCTAssertTrue(v.contains("elapsed: currentTime, duration: duration"), "video slider value must be live")
        XCTAssertTrue(v.contains("elapsed: audioCurrentTime, duration: audioDuration"), "audio slider value must be live")
    }

    // MARK: - Regression: what this unit must NOT disturb

    /// P5-M's speed control is already device/VoiceOver verified.
    func testPlaybackSpeedAccessibilityUnchanged() {
        XCTAssertTrue(viewer().contains("PlaybackRate.accessibilityLabel")
                      || code("PlaybackRate.swift").contains("accessibilityValue"),
                      "the speed control's own accessibility must remain in place")
        XCTAssertTrue(viewer().contains(#".accessibilityLabel("Play video")"#),
                      "the centre overlay play button's existing label must survive")
    }

    /// The already-labelled favourite control for ATTACHMENTS is out of scope
    /// and must not have been relabelled in passing.
    func testAttachmentFavouriteLabelUntouched() {
        XCTAssertTrue(viewer().contains(#"isFav ? "Unfavourite attachment" : "Favourite attachment""#),
                      "the attachment favourite label is outside this unit and must be unchanged")
    }
}
