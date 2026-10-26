//
//  C137ProfileNameCommitTests.swift
//  MOTIVOTests
//
//  C-137: clearing or temporarily emptying the Profile name must not send an
//  established person back to onboarding. The name is mandatory (set-up
//  cannot finish without one), so an empty draft never commits over the last
//  committed name, and the field shows that name again when the edit ends.
//  The set-up gate reads the committed row, which this keeps non-empty.
//

import XCTest
@testable import Etudes

final class C137ProfileNameCommitTests: XCTestCase {

    func testClearingKeepsTheCommittedNameAndRetypingReplacesIt() {
        XCTAssertEqual(ProfileNameCommitPolicy.committedName(draft: "", stored: "Samuel"), "Samuel", "cleared mid-edit: the row keeps the name")
        XCTAssertEqual(ProfileNameCommitPolicy.committedName(draft: "   ", stored: "Samuel"), "Samuel")
        XCTAssertEqual(ProfileNameCommitPolicy.committedName(draft: " Sam ", stored: "Samuel"), "Sam", "retyped: the new name commits, trimmed")
        XCTAssertEqual(ProfileNameCommitPolicy.committedName(draft: "", stored: nil), "", "first run: nothing to keep")
        XCTAssertEqual(ProfileNameCommitPolicy.committedName(draft: "", stored: "  "), "")
    }

    func testTheFieldShowsTheKeptNameAgainOnlyWhenAnEditEndsEmptyOverAName() {
        XCTAssertEqual(ProfileNameCommitPolicy.restoredDraft(draft: "", stored: "Samuel"), "Samuel")
        XCTAssertNil(ProfileNameCommitPolicy.restoredDraft(draft: "Sam", stored: "Samuel"), "a typed name stands")
        XCTAssertNil(ProfileNameCommitPolicy.restoredDraft(draft: "", stored: ""), "set-up: an empty field stays empty for validation there")
        XCTAssertNil(ProfileNameCommitPolicy.restoredDraft(draft: "", stored: nil))
    }

    /// The gate's input is the committed row. Across clear → commit → retype →
    /// commit → relaunch (a fresh read of the row) it never reads empty.
    func testTheCommittedRowNeverReadsEmptyAcrossClearRetypeAndRelaunch() {
        var row: String? = "Samuel"
        for draft in ["", "S", "", "Sa", "Sam"] {
            row = ProfileNameCommitPolicy.committedName(draft: draft, stored: row)
            XCTAssertFalse(row!.isEmpty, "draft \(draft.debugDescription) emptied the row")
        }
        XCTAssertEqual(row, "Sam")
        let relaunched = row   // what a fresh launch reads
        XCTAssertEqual(ProfileNameCommitPolicy.committedName(draft: relaunched ?? "", stored: relaunched), "Sam")
    }
}
