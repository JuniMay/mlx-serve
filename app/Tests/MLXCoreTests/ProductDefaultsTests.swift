import XCTest
@testable import MLXCore

final class ProductDefaultsTests: XCTestCase {
    func testAppUpdateChecksAreSuspendedForEveryDistribution() {
        XCTAssertFalse(BuildFeatures.developerID.selfUpdate)
        XCTAssertFalse(BuildFeatures.mas.selfUpdate)
    }

    func testVoiceDoesNotSupplyAnUnchosenWakePhrase() throws {
        XCTAssertEqual(ServerOptions().wakePhrase, "")
        XCTAssertEqual(WakeWord.activePhrase(agentPhrase: nil, global: ""), "")
        XCTAssertNil(WakeWord.strip("Hey Loki, do something", phrase: ""))
        let decoded = try JSONDecoder().decode(ServerOptions.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.wakePhrase, "")
    }

    func testSavedCustomWakePhraseIsPreserved() throws {
        let decoded = try JSONDecoder().decode(ServerOptions.self, from: Data(#"{"wakePhrase":"Hey Computer"}"#.utf8))
        XCTAssertEqual(decoded.wakePhrase, "Hey Computer")
    }

    func testBlankWakePhraseHasGenericVoiceGuidance() {
        XCTAssertTrue(VoicePrompt.speakingStyle(phrase: "").hasPrefix("You are a voice assistant."))
    }
}
