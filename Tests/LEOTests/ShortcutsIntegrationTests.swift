import XCTest
@testable import LEO

final class ShortcutsIntegrationTests: XCTestCase {
    func testListReturnsTypedShortcutsAndRunUsesExecutor() throws {
        let executor = MockShortcutsExecutor(result: "Done")
        let integration = ShortcutsIntegration(
            listProvider: MockShortcutsListProvider(shortcuts: [Shortcut(name: "Morning Brief")]),
            executor: executor
        )

        XCTAssertEqual(try integration.list(), [Shortcut(name: "Morning Brief")])
        XCTAssertEqual(try integration.run(named: "Morning Brief", input: "today"), "Done")
        XCTAssertEqual(executor.runs.count, 1)
        XCTAssertEqual(executor.runs[0].name, "Morning Brief")
        XCTAssertEqual(executor.runs[0].input, "today")
    }

    func testMissingShortcutFailsBeforeExecutorRuns() {
        let executor = MockShortcutsExecutor(result: "Should not run")
        let integration = ShortcutsIntegration(
            listProvider: MockShortcutsListProvider(shortcuts: [Shortcut(name: "Morning Brief")]),
            executor: executor
        )

        XCTAssertThrowsError(try integration.run(named: "Unknown Shortcut")) { error in
            XCTAssertEqual(error as? ShortcutsError, .missingShortcut("Unknown Shortcut"))
        }
        XCTAssertTrue(executor.runs.isEmpty)
    }

    func testToolDefinitionsRouteListAndRunThroughToolBrokerPolicy() async throws {
        let executor = MockShortcutsExecutor(result: "Sent")
        let integration = ShortcutsIntegration(
            listProvider: MockShortcutsListProvider(shortcuts: [Shortcut(name: "Send Report")]),
            executor: executor
        )
        let broker = ToolBroker(definitions: integration.toolDefinitions)

        let listed = try await broker.execute(ToolProposal(name: "shortcuts.list", arguments: [:]))
        XCTAssertEqual(listed.value, "Send Report")

        do {
            _ = try await broker.execute(ToolProposal(name: "shortcuts.run", arguments: ["name": "Send Report"]))
            XCTFail("running a shortcut should remain behind policy confirmation")
        } catch let error as ToolBrokerError {
            XCTAssertEqual(error, .denied("This action requires trusted confirmation."))
        }

        let run = try await broker.execute(
            ToolProposal(name: "shortcuts.run", arguments: ["name": "Send Report"]),
            confirmationGranted: true
        )
        XCTAssertEqual(run.value, "Sent")
    }
}

private struct MockShortcutsListProvider: ShortcutsListProvider {
    let shortcuts: [Shortcut]

    func list() throws -> [Shortcut] { shortcuts }
}

private final class MockShortcutsExecutor: ShortcutsExecutor, @unchecked Sendable {
    let result: String
    private(set) var runs: [Run] = []

    init(result: String) { self.result = result }

    func run(shortcut: Shortcut, input: String?) throws -> ShortcutRunResult {
        runs.append(Run(name: shortcut.name, input: input))
        return ShortcutRunResult(output: result)
    }

    struct Run {
        let name: String
        let input: String?
    }
}
