import SwiftUI
import UIKit
import XCTest
@testable import Etudes

@MainActor
final class MetronomeNotationTests: XCTestCase {
    private typealias Wheel = MetronomeNotationWheel<Int, Text>
    private final class Selection { var value = 4 }
    private func wheel(_ selection: Selection, values: [Int] = [2, 3, 4, 5]) -> Wheel {
        Wheel(values: values, selection: Binding(get: { selection.value }, set: { selection.value = $0 }),
              label: "Time signature", valueLabel: { "\($0)/4" }, height: 56, contentID: 0) { Text("\($0)") }
    }
    private func picker(_ coordinator: Wheel.Coordinator) -> MetronomePickerView {
        let picker = MetronomePickerView(frame: CGRect(x: 0, y: 0, width: 100, height: 56))
        picker.dataSource = coordinator
        picker.delegate = coordinator
        return picker
    }
    private func prepare(_ coordinator: Wheel.Coordinator, wheel: Wheel, picker: MetronomePickerView) {
        coordinator.synchronize(wheel, with: picker)
        // Render a real row, as the displayed wheel does, before testing later redraws.
        _ = coordinator.pickerView(picker, viewForRow: 2, forComponent: 0, reusing: nil)
    }

    func testBeatRedrawDoesNotResetUncommittedWheelMovement() {
        let selection = Selection()
        let coordinator = wheel(selection).makeCoordinator()
        let picker = picker(coordinator)
        prepare(coordinator, wheel: wheel(selection), picker: picker)
        picker.selectRow(3, inComponent: 0, animated: false)
        for _ in 0..<20 { coordinator.synchronize(wheel(selection), with: picker) }
        XCTAssertEqual(picker.selectedRow(inComponent: 0), 3, "Beat redraw must not rewind a scrolling wheel")
        XCTAssertEqual(selection.value, 4, "The model commits only after UIKit reports a selection")
    }

    func testExternalSelectionChangeStillRepositionsWheel() {
        let selection = Selection()
        let coordinator = wheel(selection).makeCoordinator()
        let picker = picker(coordinator)
        prepare(coordinator, wheel: wheel(selection), picker: picker)
        picker.selectRow(3, inComponent: 0, animated: false)
        selection.value = 2
        coordinator.synchronize(wheel(selection), with: picker)
        XCTAssertEqual(picker.selectedRow(inComponent: 0), 0)
        XCTAssertEqual(picker.accessibilityValue, "2/4")
    }

    func testCommittedSelectionSurvivesSubsequentBeatRedraws() {
        let selection = Selection()
        let coordinator = wheel(selection).makeCoordinator()
        let picker = picker(coordinator)
        prepare(coordinator, wheel: wheel(selection), picker: picker)
        picker.selectRow(3, inComponent: 0, animated: false)
        coordinator.pickerView(picker, didSelectRow: 3, inComponent: 0)
        for _ in 0..<20 { coordinator.synchronize(wheel(selection), with: picker) }
        XCTAssertEqual(selection.value, 5)
        XCTAssertEqual(picker.selectedRow(inComponent: 0), 3)
        XCTAssertEqual(picker.accessibilityValue, "5/4")
    }

    func testChangedChoicesResynchroniseEvenWhenSelectedValueIsUnchanged() {
        let selection = Selection()
        let coordinator = wheel(selection).makeCoordinator()
        let picker = picker(coordinator)
        prepare(coordinator, wheel: wheel(selection), picker: picker)
        coordinator.synchronize(wheel(selection, values: [4, 5, 6]), with: picker)
        XCTAssertEqual(picker.numberOfRows(inComponent: 0), 3)
        XCTAssertEqual(picker.selectedRow(inComponent: 0), 0)
        XCTAssertEqual(selection.value, 4)
    }
    func testStackedSignaturesLeaveVerticalClearanceInsideTheWheel() throws {
        let sizes: [(DynamicTypeSize, UIContentSizeCategory)] = [
            (.large, .large), (.xxxLarge, .extraExtraExtraLarge),
            (.accessibility3, .accessibilityExtraLarge), (.accessibility5, .accessibilityExtraExtraExtraLarge)
        ]
        for (dynamicSize, category) in sizes {
            let wheelHeight = UIFontMetrics(forTextStyle: .body).scaledValue(for: 56,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            for meter: MetronomeMeter in [.asymmetric(5), .asymmetric(10), .asymmetric(11)] {
                let renderer = ImageRenderer(content: MetronomeMeterGlyph(meter: meter).environment(\.dynamicTypeSize, dynamicSize))
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertGreaterThan(image.size.height, 0)
                XCTAssertLessThanOrEqual(image.size.height, wheelHeight * 0.72,
                    "Keep the complete signature away from the wheel's fading edges at \(dynamicSize)")
            }
        }
    }

}
