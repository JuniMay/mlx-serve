import XCTest
@testable import MLXCore

final class ComposerTipTests: XCTestCase {

    private var all: [ComposerTip] {
        [.attachments(audioSupported: true), .attachments(audioSupported: false),
         .attachments(audioSupported: true, videoSupported: true), .attachments(audioSupported: false, videoSupported: true),
         .thinking(isOn: true), .thinking(isOn: false)]
            + lockedTips
    }

    private var lockedTips: [ComposerTip] {
        [.thinking(isOn: true, lockedBy: "Chef"), .thinking(isOn: false, lockedBy: "Chef")]
    }

    func testEveryTipHasATitleAndABody() {
        for tip in all {
            XCTAssertFalse(tip.title.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(tip.body.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertLessThanOrEqual(tip.title.count, 32, "title too long to sit on one line: \(tip.title)")
            XCTAssertLessThanOrEqual(tip.body.count, 120, "card body is too long to glance at: \(tip.body)")
        }
    }

    func testModeTipsNameTheCurrentStateAndTheirSettingsMenu() {
        let cases: [(on: ComposerTip, off: ComposerTip)] = [
            (.thinking(isOn: true), .thinking(isOn: false))
        ]
        for (on, off) in cases {
            XCTAssertTrue(on.title.contains("ON"))
            XCTAssertTrue(off.title.contains("OFF"))
            XCTAssertEqual(on.body, off.body)
            XCTAssertTrue(on.body.lowercased().contains("menu"))
            XCTAssertFalse(on.body.lowercased().contains("right-click"))
            XCTAssertFalse(on.body.lowercased().contains("click to turn"))
        }
    }

    func testAttachmentTipMentionsAudioOnlyWhenTheModelCanHearIt() {
        XCTAssertTrue(ComposerTip.attachments(audioSupported: true).body.lowercased().contains("audio"))
        XCTAssertFalse(ComposerTip.attachments(audioSupported: false).body.lowercased().contains("audio"))
    }

    func testAttachmentTipMentionsVideoOnlyWhenTheModelCanSeeIt() {
        XCTAssertTrue(ComposerTip.attachments(audioSupported: false, videoSupported: true).body.lowercased().contains("video"))
        XCTAssertFalse(ComposerTip.attachments(audioSupported: false, videoSupported: false).body.lowercased().contains("video"))
        let both = ComposerTip.attachments(audioSupported: true, videoSupported: true).body.lowercased()
        XCTAssertTrue(both.contains("audio") && both.contains("video"))
    }


    func testLockedTipsNameTheAgentAndWhereToChangeIt() {
        for tip in lockedTips {
            XCTAssertTrue(tip.body.contains("Chef"), "a locked card must name the agent: \(tip.body)")
            XCTAssertTrue(tip.body.lowercased().contains("agent"), tip.body)
            XCTAssertFalse(tip.body.lowercased().contains("click to turn it"),
                           "a locked control can't be toggled — don't offer it: \(tip.body)")
        }
    }

    func testLockedTipsStillSayWhetherTheControlIsOnOrOff() {
        XCTAssertTrue(ComposerTip.thinking(isOn: true, lockedBy: "Chef").title.contains("ON"))
        XCTAssertTrue(ComposerTip.thinking(isOn: false, lockedBy: "Chef").title.contains("OFF"))
    }
}
