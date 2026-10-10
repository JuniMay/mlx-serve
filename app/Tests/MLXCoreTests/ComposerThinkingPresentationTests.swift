import XCTest
@testable import MLXCore

final class ComposerThinkingPresentationTests: XCTestCase {
    func testUnlockedChatShowsItsSelectedEffortWhileThinkingIsOn() {
        for (effort, expected) in [(ReasoningEffort.low, "Low"), (.medium, "Medium"), (.high, "High")] {
            XCTAssertEqual(ComposerThinkingPresentation.summary(isOn: true, effort: effort,
                                                                 isExternalBridge: false, lockedBy: nil), expected)
        }
    }

    func testThinkingOffHidesTheStoredEffort() {
        for effort in ReasoningEffort.allCases {
            XCTAssertEqual(ComposerThinkingPresentation.summary(isOn: false, effort: effort,
                                                                 isExternalBridge: false, lockedBy: nil), "Off")
        }
    }

    func testAgentLockedThinkingDoesNotClaimAnEffortLevel() {
        XCTAssertEqual(ComposerThinkingPresentation.summary(isOn: true, effort: .high,
                                                             isExternalBridge: false, lockedBy: "Researcher"), "Thinking")
        XCTAssertEqual(ComposerThinkingPresentation.summary(isOn: false, effort: .high,
                                                             isExternalBridge: false, lockedBy: "Researcher"), "Off")
    }

    func testTelegramDoesNotShowTheVisibleSessionsUnusedEffort() {
        XCTAssertEqual(ComposerThinkingPresentation.summary(isOn: true, effort: .high,
                                                             isExternalBridge: true, lockedBy: nil), "Thinking")
        XCTAssertEqual(ComposerThinkingPresentation.summary(isOn: false, effort: .high,
                                                             isExternalBridge: true, lockedBy: nil), "Off")
    }

    func testAppleThinkingRemainsOffDespiteTheStoredEffort() {
        XCTAssertEqual(ComposerThinkingPresentation.summary(isOn: false, effort: .high,
                                                             isExternalBridge: false,
                                                             lockedBy: AppleFoundationChat.displayName), "Off")
    }
}
