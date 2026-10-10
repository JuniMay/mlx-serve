import XCTest
@testable import MLXCore

final class ReasoningEffortSliderMappingTests: XCTestCase {
    func testSliderReservesTheFirstPositionForOff() {
        XCTAssertEqual(ReasoningEffortSliderMapping.index(for: .low), 1)
        XCTAssertEqual(ReasoningEffortSliderMapping.index(for: .medium), 2)
        XCTAssertEqual(ReasoningEffortSliderMapping.index(for: .high), 3)
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: 0), .low)
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: 1), .low)
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: 2), .medium)
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: 3), .high)
    }

    func testOutOfRangePositionsClampToSupportedEfforts() {
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: -1), .low)
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: Int.min), .low)
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: 3), .high)
        XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: Int.max), .high)
    }

    func testEveryEffortSurvivesASliderRoundTrip() {
        for effort in ReasoningEffort.allCases {
            XCTAssertEqual(ReasoningEffortSliderMapping.effort(at: ReasoningEffortSliderMapping.index(for: effort)), effort)
        }
    }

    func testOffUsesTheFirstPositionRegardlessOfRememberedEffort() {
        for effort in ReasoningEffort.allCases {
            XCTAssertEqual(ReasoningEffortSliderMapping.index(for: effort, isOn: false), 0)
            let selection = ReasoningEffortSliderMapping.selection(at: 0, preserving: effort)
            XCTAssertFalse(selection.isOn)
            XCTAssertEqual(selection.effort, effort)
        }
    }

    func testChoosingAnEffortEnablesThinkingAtThatLevel() {
        for (index, effort) in [(1, ReasoningEffort.low), (2, .medium), (3, .high)] {
            let selection = ReasoningEffortSliderMapping.selection(at: index, preserving: .high)
            XCTAssertTrue(selection.isOn)
            XCTAssertEqual(selection.effort, effort)
        }
    }

    func testSelectionClampsOutsideTheFourPositions() {
        let below = ReasoningEffortSliderMapping.selection(at: Int.min, preserving: .medium)
        XCTAssertFalse(below.isOn)
        XCTAssertEqual(below.effort, .medium)
        let above = ReasoningEffortSliderMapping.selection(at: Int.max, preserving: .low)
        XCTAssertTrue(above.isOn)
        XCTAssertEqual(above.effort, .high)
    }
}
