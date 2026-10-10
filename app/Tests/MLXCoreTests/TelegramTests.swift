import XCTest
@testable import MLXCore

/// Saved Telegram settings and existing chat history remain readable.
final class TelegramTests: XCTestCase {

    // MARK: - TelegramConfig

    func testTelegramDefaultsAreOff() {
        let c = ServerOptions.TelegramConfig()
        XCTAssertFalse(c.enabled)
        XCTAssertFalse(c.agentMode)
        XCTAssertFalse(c.useMCP)
        XCTAssertTrue(c.botToken.isEmpty)
        XCTAssertTrue(c.allowedChatIds.isEmpty)
    }

    func testTelegramConfigRoundTripsThroughServerOptions() throws {
        var opts = ServerOptions()
        opts.telegram.enabled = true
        opts.telegram.botToken = "8864:TESTONLY"
        opts.telegram.agentMode = true
        opts.telegram.useMCP = true
        opts.telegram.enableThinking = true
        opts.telegram.allowedChatIds = [7123456789, 42]  // > Int32 to pin Int64 storage

        let data = try JSONEncoder().encode(opts)
        let decoded = try JSONDecoder().decode(ServerOptions.self, from: data)
        XCTAssertEqual(opts, decoded)
        XCTAssertEqual(decoded.telegram.allowedChatIds, [7123456789, 42])
        XCTAssertTrue(decoded.telegram.useMCP)
    }

    /// MIGRATION GUARD (nested): a telegram blob written before `useMCP` existed
    /// must decode with useMCP=false rather than throwing — a throw inside the
    /// nested TelegramConfig propagates up and resets the WHOLE ServerOptions
    /// (token included). This is the exact shape already on disk for early users.
    func testTelegramConfigDecodesWhenNestedFieldMissing() throws {
        var opts = ServerOptions()
        opts.telegram.enabled = true
        opts.telegram.botToken = "8864:TESTONLY"
        opts.telegram.agentMode = true
        var full = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(opts)) as! [String: Any]
        var tg = full["telegram"] as! [String: Any]
        tg.removeValue(forKey: "useMCP")   // pre-useMCP telegram blob
        full["telegram"] = tg
        let data = try JSONSerialization.data(withJSONObject: full)

        let decoded = try JSONDecoder().decode(ServerOptions.self, from: data)
        XCTAssertTrue(decoded.telegram.enabled, "token + flags must survive")
        XCTAssertEqual(decoded.telegram.botToken, "8864:TESTONLY")
        XCTAssertTrue(decoded.telegram.agentMode)
        XCTAssertFalse(decoded.telegram.useMCP, "missing nested key → safe default")
    }

    /// MIGRATION GUARD: an existing user's saved `serverOptions` blob predates
    /// the `telegram` field. Decoding it under the new struct must SUCCEED with
    /// `telegram` defaulting to off — otherwise `ServerOptions.load()` silently
    /// resets every upgrading user's tuning to defaults (it `try?`s the decode
    /// and falls back to `ServerOptions()`). Simulate the old blob by encoding a
    /// current options object and stripping the `telegram` key.
    func testDecodesOldBlobWithoutTelegramKey() throws {
        var opts = ServerOptions()
        opts.port = 9876
        opts.defaultTemperature = 0.55
        let full = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(opts)) as! [String: Any]
        XCTAssertNotNil(full["telegram"], "sanity: new encoder emits the telegram key")
        var old = full
        // Strip a representative spread of keys added across releases — proving
        // the fix is a class guard, not a one-off telegram patch.
        for key in ["telegram", "tokenizeCacheEntries", "skipMemPreflight", "llamaKvQuant"] {
            old.removeValue(forKey: key)
        }
        let oldData = try JSONSerialization.data(withJSONObject: old)

        let decoded = try JSONDecoder().decode(ServerOptions.self, from: oldData)
        // Preserved keys keep their stored values…
        XCTAssertEqual(decoded.port, 9876, "existing tuning must survive the upgrade")
        XCTAssertEqual(decoded.defaultTemperature, 0.55, accuracy: 0.0001)
        // …and every stripped key falls back to its default instead of throwing.
        XCTAssertFalse(decoded.telegram.enabled, "missing telegram key → safe default (off)")
        XCTAssertTrue(decoded.telegram.botToken.isEmpty)
        XCTAssertEqual(decoded.tokenizeCacheEntries, ServerOptions().tokenizeCacheEntries)
        XCTAssertEqual(decoded.skipMemPreflight, ServerOptions().skipMemPreflight)
        XCTAssertEqual(decoded.llamaKvQuant, ServerOptions().llamaKvQuant)
    }

    /// A blob that is just `{}` (or wholly unknown) must still decode to a
    /// full-defaults options object — the ultimate degenerate upgrade case.
    func testDecodesEmptyObjectToDefaults() throws {
        let decoded = try JSONDecoder().decode(ServerOptions.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, ServerOptions())
    }

    /// Dormant compatibility fields do not change server launch arguments.
    func testTelegramChangesDoNotTriggerServerRestart() {
        let a = ServerOptions()
        var b = ServerOptions()
        b.telegram.enabled = true
        b.telegram.botToken = "123:abc"
        b.telegram.agentMode = true
        b.telegram.allowedChatIds = [1]
        XCTAssertTrue(a.serverLaunchEquals(b),
                      "Stored Telegram configuration must not require a server restart")
    }

    // MARK: - Sidebar visibility

    /// Existing external chat history remains visible; task-run sessions stay hidden.
    func testSidebarShowsTelegramSessionsButHidesTaskRuns() {
        let normal = ChatSession(title: "normal chat")
        var telegram = ChatSession(title: "Dave (Telegram)")
        telegram.isExternalBridge = true
        var taskRun = ChatSession(title: "task vehicle")
        taskRun.taskRunId = UUID()

        let titles = AppState.sidebarSessions(from: [normal, telegram, taskRun]).map(\.title)
        XCTAssertTrue(titles.contains("normal chat"))
        XCTAssertTrue(titles.contains("Dave (Telegram)"), "Telegram mirrors must appear in the sidebar")
        XCTAssertFalse(titles.contains("task vehicle"), "task-run vehicles stay hidden")
    }

}
