import XCTest
@testable import MLXCore

/// The empty input names the selected agent and explains its purpose.
final class ChatGreetingTests: XCTestCase {

    // MARK: The greeting names the agent

    /// The name is the thing. "Agent" was the 30pt word with the name as its
    /// caption, which is the same inversion the sidebar rows had.
    func testAnAgentThreadIsHeadedByTheAgentsName() {
        XCTAssertEqual(ChatGreeting.heading(agentName: "Coder copy"), "Coder copy")
    }

    func testAPlainThreadKeepsTheAppsGreeting() {
        XCTAssertEqual(ChatGreeting.heading(agentName: nil), ChatGreeting.plainHeading)
    }

    /// A half-saved agent can't head a screen with an empty string.
    func testABlankAgentNameFallsBackToTheAppsGreeting() {
        XCTAssertEqual(ChatGreeting.heading(agentName: "   "), ChatGreeting.plainHeading)
    }

    /// The brief is what tells you what to ask this agent — the reason it, and
    /// not a row of app features, belongs under the name.
    func testTheSubtitleIsTheAgentsBrief() {
        XCTAssertEqual(ChatGreeting.subtitle(agentBrief: "a hands-on programmer",
                                             serverRunning: true),
                       "a hands-on programmer")
    }

    /// A stopped server outranks the brief: it is the one thing on this screen
    /// the user has to act on before anything else works.
    func testAStoppedServerOutranksTheBrief() {
        XCTAssertEqual(ChatGreeting.subtitle(agentBrief: "a hands-on programmer",
                                             serverRunning: false),
                       ChatGreeting.serverStopped)
        XCTAssertEqual(ChatGreeting.subtitle(agentBrief: nil, serverRunning: false),
                       ChatGreeting.serverStopped)
    }

    /// An agent with no description gets no caption rather than an empty line
    /// holding space under the name.
    func testNoBriefMeansNoSubtitle() {
        XCTAssertNil(ChatGreeting.subtitle(agentBrief: nil, serverRunning: true))
        XCTAssertNil(ChatGreeting.subtitle(agentBrief: "  ", serverRunning: true))
    }

}
