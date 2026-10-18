//
//  WindowMetricsTests.swift
//  MOTIVOTests
//
//  iPhone Duo prep: sizing now follows the app's window, not the screen.
//  On an ordinary iPhone the two must be the same rectangle, so the iPhone
//  layout is unchanged; these tests check that on the iPhone simulator.
//

import XCTest
import UIKit
@testable import Etudes

final class WindowMetricsTests: XCTestCase {

    // MARK: - Keyboard overlap

    func testKeyboardOverlapMatchesTheOldScreenArithmeticWhenWindowFillsScreen() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
        let keyboard = CGRect(x: 0, y: 874 - 336, width: 402, height: 336)
        let old = max(0, screen.height - keyboard.minY)   // the replaced expression
        XCTAssertEqual(WindowMetrics.keyboardOverlap(windowFrameInScreen: screen, keyboardFrameInScreen: keyboard), old)
        XCTAssertEqual(old, 336)
    }

    func testKeyboardOffScreenIsNoOverlap() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
        let hidden = CGRect(x: 0, y: 874, width: 402, height: 336)
        XCTAssertEqual(WindowMetrics.keyboardOverlap(windowFrameInScreen: screen, keyboardFrameInScreen: hidden), 0)
    }

    /// The Duo / iPad case the change exists for: a window shorter than the
    /// screen is covered only by the part of the keyboard inside it.
    func testKeyboardOverlapUsesTheWindowsBottomEdge() {
        let window = CGRect(x: 0, y: 0, width: 600, height: 700)
        let keyboard = CGRect(x: 0, y: 600, width: 900, height: 300)   // screen is taller than the window
        XCTAssertEqual(WindowMetrics.keyboardOverlap(windowFrameInScreen: window, keyboardFrameInScreen: keyboard), 100)
    }

    // MARK: - On the iPhone simulator, window == screen

    @MainActor
    func testOnIPhoneTheWindowIsTheWholeScreen() throws {
        guard UITraitCollection.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("iPhone simulator only")
        }
        guard let window = WindowMetrics.keyWindow else {
            throw XCTSkip("the test host has no window")
        }
        let screenBounds = window.screen.bounds
        XCTAssertEqual(WindowMetrics.windowBounds, screenBounds,
                       "on iPhone the window must equal the screen, or the layout would change")
        XCTAssertEqual(WindowMetrics.windowFrameInScreen, screenBounds)
    }
}
