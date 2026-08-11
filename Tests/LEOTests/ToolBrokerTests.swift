import XCTest
@testable import LEO

final class ToolBrokerTests: XCTestCase {
    func testRegisteredToolValidatesArgumentsAndReturnsTrace() async throws {
        let broker = ToolBroker()
        await broker.register(ToolDefinition(
            name: "test.echo",
            effect: .readOnly,
            idempotency: .idempotent,
            requiredArguments: ["value"]
        ) { arguments in
            ToolResult.success(arguments["value"] ?? "")
        })

        let result = try await broker.execute(ToolProposal(name: "test.echo", arguments: ["value": "hello"]))
        let secondResult = try await broker.execute(ToolProposal(name: "test.echo", arguments: ["value": "hello"]))
        XCTAssertEqual(result.value, "hello")
        XCTAssertFalse(result.traceID.isEmpty)
        XCTAssertNotEqual(result.traceID, secondResult.traceID)
    }

    func testUnknownAndInvalidToolsFailSafely() async {
        let broker = ToolBroker()
        do {
            _ = try await broker.execute(ToolProposal(name: "missing.tool", arguments: [:]))
            XCTFail("unknown tool should fail")
        } catch let error as ToolBrokerError {
            XCTAssertEqual(error, .unknownTool("missing.tool"))
        } catch { XCTFail("unexpected error: \(error)") }

        await broker.register(ToolDefinition(name: "test.required", effect: .readOnly, idempotency: .idempotent, requiredArguments: ["path"]) { _ in
            ToolResult.success("ok")
        })
        do {
            _ = try await broker.execute(ToolProposal(name: "test.required", arguments: [:]))
            XCTFail("missing arguments should fail")
        } catch let error as ToolBrokerError {
            XCTAssertEqual(error, .missingArguments(["path"]))
        } catch { XCTFail("unexpected error: \(error)") }
    }

    func testSlowToolTimesOutWithoutWaitingForTheToolToReturn() async {
        let broker = ToolBroker(definitions: [
            ToolDefinition(name: "test.slow", effect: .readOnly, idempotency: .idempotent) { _ in
                Thread.sleep(forTimeInterval: 0.2)
                return ToolResult.success("late")
            }
        ])

        let started = ContinuousClock.now
        do {
            _ = try await broker.execute(
                ToolProposal(name: "test.slow", arguments: [:]),
                timeoutNanoseconds: 10_000_000
            )
            XCTFail("slow tool should time out")
        } catch let error as ToolBrokerError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(150))
    }

    func testCallerCancellationReturnsWithoutWaitingForTheToolToReturn() async {
        let broker = ToolBroker(definitions: [
            ToolDefinition(name: "test.cancellable", effect: .readOnly, idempotency: .idempotent) { _ in
                Thread.sleep(forTimeInterval: 0.2)
                return ToolResult.success("late")
            }
        ])

        let task = Task {
            try await broker.execute(ToolProposal(name: "test.cancellable", arguments: [:]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("cancelled tool should not return a result")
        } catch let error as ToolBrokerError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
