//
//  ProfileSectionGroupingTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-P / H-1 — the Profile grouping, asserted against source.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`, and four times since).
//  This file's own comments name every string it checks, which is exactly how a
//  source-text assertion gets defeated by the file that explains it.
//
//  **THESE ASSERTIONS ARE ABOUT GROUPING AND GATES, NOT ABOUT APPEARANCE.**
//  Whether the reorganised Profile reads well is a device judgement they cannot
//  make.
//

import XCTest
@testable import Etudes

final class ProfileSectionGroupingTests: XCTestCase {

    private func code() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/ProfileView.swift"), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func region(_ s: String, from: String, to: String) -> String {
        guard let a = s.range(of: from) else { return "" }
        let rest = s[a.upperBound...]
        let end = rest.range(of: to)?.lowerBound ?? rest.endIndex
        return String(rest[rest.startIndex..<end])
    }

    private func settingsSection() -> String {
        region(code(), from: #"Section(header: Text("Settings").sectionHeader())"#,
               to: "private var connectedPreferencesSection")
    }

    private func connectedSection() -> String {
        region(code(), from: "private var connectedPreferencesSection",
               to: "private var connectedPromoSection")
    }

    // MARK: - The grouping

    func testConnectedSectionExistsAndIsNamedConnected() {
        let s = code()
        XCTAssertTrue(s.contains(#"Section(header: Text("Connected").sectionHeader())"#),
                      "the Connected section must exist and be titled Connected")
        XCTAssertFalse(s.contains(#"Text("Privacy").sectionHeader()"#),
                       "the section is Connected, never Privacy — that would imply a scope it does not have")
        XCTAssertFalse(s.contains(#"Text("Connected Account").sectionHeader()"#),
                       "the account section is Account, never Connected Account")
    }

    /// **THE H-1 ASSERTION.** Both Connected preferences have left Settings.
    /// Absence of the old grouping, not presence of the new one.
    func testConnectedPreferencesAreNoLongerInSettings() {
        let settings = settingsSection()
        XCTAssertFalse(settings.isEmpty, "the Settings section must be locatable")
        XCTAssertFalse(settings.contains("Default to Private Posts"),
                       "Default to Private Posts must not be in Settings")
        XCTAssertFalse(settings.contains("Let other members find you"),
                       "the discovery control must not be in Settings")
    }

    func testConnectedSectionHoldsBothControlsInOrder() {
        let c = connectedSection()
        guard let a = c.range(of: "Default to Private Posts"),
              let b = c.range(of: "Let other members find you") else {
            return XCTFail("both Connected controls must live in the Connected section")
        }
        XCTAssertTrue(a.lowerBound < b.lowerBound, "posting default comes before discovery")
    }

    /// Settings keeps everything it is supposed to keep.
    func testSettingsRetainsItsOwnControls() {
        let settings = settingsSection()
        for expected in ["Instruments", "Activities", "Journal Tint", "Tasks",
                        "Show Metronome", "Show Drone", "Show Scores"] {
            XCTAssertTrue(settings.contains(expected), "Settings lost: \(expected)")
        }
    }

    // MARK: - Gates and writers: presentation-only means these must not move

    func testConnectedSectionIsGatedAndCannotRenderEmptyInSolo() {
        let c = connectedSection()
        XCTAssertTrue(c.contains("if appModeManager.canShowConnectedAccountManagement {"),
                      "the section must carry the gate that previously wrapped both controls")
        XCTAssertTrue(c.contains("if auth.accountPrivacyState != nil {"),
                      "the discovery control keeps its own nested condition")
    }

    func testBindingsAndTheSoleDiscoveryWriterAreUnchanged() {
        let c = connectedSection()
        XCTAssertTrue(c.contains("isOn: $defaultPrivacy"), "posting-default binding must be unchanged")
        XCTAssertTrue(c.contains("isOn: $discoverabilityOn"), "discovery binding must be unchanged")
        XCTAssertTrue(c.contains("await applyDiscoverability(newValue)"),
                      "discovery must still be written through the only client writer")
    }

    /// The account section is untouched, including the state-dependent
    /// erase/delete button whose Solo and Connected wording deliberately differ.
    func testAccountSectionsUntouched() {
        let s = code()
        XCTAssertEqual(s.components(separatedBy: #"Section(header: Text("Account").sectionHeader())"#).count - 1, 2,
                       "both mutually exclusive Account sections must survive")
        XCTAssertEqual(s.components(separatedBy: "eraseAllEtudesDataButton").count - 1, 3,
                       "the erase/delete button: one declaration and both call sites")
    }
}
