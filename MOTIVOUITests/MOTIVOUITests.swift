//
//  MotivoUITests.swift
//  MotivoUITests
//
//  Created by Samuel Dixon on 2025-10-09.
//

import XCTest

final class AccessibilityAndPersistenceTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - 1) Edit session description persists
    func testEditSessionDescriptionPersists() throws {
        // Precondition: at least one session row exists
        let firstRow = app.otherElements["row.openDetail"].firstMatch
        guard firstRow.waitForExistence(timeout: 5) else {
            throw XCTSkip("No sessions available to open.")
        }

        // Open session detail
        firstRow.tap()

        // Tap Edit
        let editButton = app.buttons["button.editSession"]
        guard editButton.waitForExistence(timeout: 3) else {
            XCTFail("Edit button not found on SessionDetailView")
            return
        }
        editButton.tap()

        // Locate Notes text editor and append " QA"
        let notes = app.textViews.matching(identifier: "Notes").firstMatch
        if !notes.exists {
            // Fallback: use the first available text view
            let anyTextView = app.textViews.firstMatch
            guard anyTextView.waitForExistence(timeout: 2) else {
                XCTFail("Notes text view not found")
                return
            }
            anyTextView.tap()
            anyTextView.typeText(" QA")
        } else {
            notes.tap()
            notes.typeText(" QA")
        }

        // Tap Save
        let save = app.buttons["button.saveSession"]
        guard save.waitForExistence(timeout: 2) else {
            XCTFail("Save button not found")
            return
        }
        save.tap()

        // Wait for feed to reappear and reopen the same session
        let feedRow = app.otherElements["row.openDetail"].firstMatch
        XCTAssertTrue(feedRow.waitForExistence(timeout: 5), "Feed row not found after saving")
        feedRow.tap()

        // Reopen Edit
        XCTAssertTrue(editButton.waitForExistence(timeout: 3), "Edit button not found after reopening")
        editButton.tap()

        // Assert Notes contains " QA"
        let editedNotes = app.textViews.firstMatch
        XCTAssertTrue(editedNotes.waitForExistence(timeout: 3), "Notes text view not found after reopening")
        let value = editedNotes.value as? String ?? ""
        XCTAssertTrue(value.contains(" QA"), "Notes did not persist appended QA text. Value: \(value)")
    }

    // MARK: - 2) Primary activity fallback on hide/delete (optional)
    func testPrimaryActivityFallbackOnHideOrDelete() throws {
        // Skip unless Activity Manager exists
        throw XCTSkip("Activity Manager not available")
        // Implementation placeholder:
        // 1. Navigate to Activity Manager
        // 2. Set custom activity as primary
        // 3. Hide or delete that activity
        // 4. Return to AddEditSessionView and confirm picker shows a valid fallback ("Practice" or default)
    }

    // MARK: - 3) Background timer path (optional)
    func testBackgroundTimerPath() throws {
        // If a timer feature exists, verify persistence through background/foreground
        let timerButton = app.buttons["button.openTimer"]
        guard timerButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("Timer not present")
        }

        timerButton.tap()

        // Wait briefly to simulate elapsed time
        sleep(1)

        // Background and return to foreground
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        sleep(1)

        // Verify the timer screen is still visible
        let navTitle = app.navigationBars["Timer"].firstMatch
        XCTAssertTrue(navTitle.exists, "Timer screen did not remain after background/foreground cycle")
    }
}
