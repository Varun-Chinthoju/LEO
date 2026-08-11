import XCTest
@testable import LEO

final class InteractionOrchestratorTests: XCTestCase {
    private struct StreamingMockModel: StreamingLanguageModel {
        let chunks: [String]

        func response(to input: AssistantInput) async throws -> String {
            chunks.joined()
        }

        func responseStream(to input: AssistantInput) async throws -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        }
    }

    private final class MockFileSystemProvider: FileSystemProvider, @unchecked Sendable {
        var opened: [URL] = []
        var moves: [(URL, URL)] = []

        func inspect(_ url: URL) throws -> FileInspection {
            FileInspection(url: url, isDirectory: false, byteSize: 1)
        }

        func move(_ source: URL, to destination: URL) throws { moves.append((source, destination)) }
        func rename(_ source: URL, to name: String) throws -> URL { source.deletingLastPathComponent().appendingPathComponent(name) }
        func open(_ url: URL) -> Bool { opened.append(url); return true }
        func reveal(_ url: URL) -> Bool { true }
    }

    func testSubmitStreamsOrderedMockEventsAndRecordsSession() async {
        let sessions = SessionManager()
        let orchestrator = InteractionOrchestrator(sessionManager: sessions, model: MockLanguageModel(responseText: "Hello"))
        let request = AssistantRequest(input: .text("hello"), source: .commandPalette)
        var events: [AssistantEvent] = []
        for await event in await orchestrator.submit(request) { events.append(event) }

        XCTAssertEqual(events, [.accepted(request.id), .thinking, .reasoningSummary("Working on your request"), .responseCompleted("Hello")])
        let state = await sessions.conversationState(for: sessions.sharedSessionID)
        XCTAssertEqual(state?.recentTurns.count, 1)
    }

    func testCancellationStopsDelayedMockResponse() async {
        let model = MockLanguageModel(responseText: "late", delayNanoseconds: 500_000_000)
        let orchestrator = InteractionOrchestrator(model: model)
        let request = AssistantRequest(input: .text("cancel"), source: .cli)
        let stream = await orchestrator.submit(request)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        _ = await iterator.next()
        iterator = stream.makeAsyncIterator()
        XCTAssertNotNil(iterator)
    }

    func testStreamingLanguageModelEmitsDeltasBeforeCompletion() async {
        let orchestrator = InteractionOrchestrator(model: StreamingMockModel(chunks: ["Hel", "lo"]))
        let request = AssistantRequest(input: .text("hello"), source: .commandPalette)
        var events: [AssistantEvent] = []
        for await event in await orchestrator.submit(request) { events.append(event) }

        XCTAssertEqual(events.suffix(3), [.responseDelta("Hel"), .responseDelta("lo"), .responseCompleted("Hello")])
    }

    func testOpenRequestUsesTypedToolBrokerPath() async {
        let broker = ToolBroker(definitions: [ToolDefinition(name: "apps.open", effect: .readOnly, idempotency: .idempotent, requiredArguments: ["name"]) { arguments in
            ToolResult.success("Opened \(arguments["name"] ?? "").")
        }])
        let orchestrator = InteractionOrchestrator(toolBroker: broker)
        let request = AssistantRequest(input: .text("open Xcode"), source: .commandPalette)
        var events: [AssistantEvent] = []
        for await event in await orchestrator.submit(request) { events.append(event) }
        XCTAssertTrue(events.contains { if case .actionStarted = $0 { return true }; return false })
        XCTAssertEqual(events.last, .responseCompleted("Opened Xcode."))
    }

    func testTypedAndCLIFileFollowUpsShareAndUpdateTheSameReferent() async {
        let files = MockFileSystemProvider()
        let sessions = SessionManager(sharedSessionID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!)
        let orchestrator = InteractionOrchestrator(
            sessionManager: sessions,
            fileTools: FileTools(provider: files)
        )
        let source = "/tmp/falcon.pdf"
        let typed = AssistantRequest(input: .text("open \(source)"), source: .commandPalette)
        let cli = AssistantRequest(sessionID: sessions.sharedSessionID, input: .text("move it to Downloads"), source: .cli)
        let followUp = AssistantRequest(sessionID: sessions.sharedSessionID, input: .text("open it"), source: .commandPalette)

        var typedEvents: [AssistantEvent] = []
        for await event in await orchestrator.submit(typed) { typedEvents.append(event) }
        var cliEvents: [AssistantEvent] = []
        for await event in await orchestrator.submit(cli) { cliEvents.append(event) }
        var followUpEvents: [AssistantEvent] = []
        for await event in await orchestrator.submit(followUp) { followUpEvents.append(event) }

        XCTAssertEqual(typedEvents.last, .responseCompleted("Opened falcon.pdf."))
        XCTAssertEqual(cliEvents.last, .responseCompleted("Moved falcon.pdf to Downloads."))
        XCTAssertEqual(files.moves.count, 1)
        XCTAssertEqual(files.opened.count, 2)
        XCTAssertTrue(followUpEvents.contains(.responseCompleted("Opened falcon.pdf.")))
        let state = await sessions.conversationState(for: sessions.sharedSessionID)
        XCTAssertEqual(state?.referents.first?.currentURL, files.moves[0].1)
    }

    func testOpenThisUsesOnlyTheInjectedCurrentFileSelection() async {
        let files = MockFileSystemProvider()
        let selection = URL(fileURLWithPath: "/tmp/selected.pdf")
        let orchestrator = InteractionOrchestrator(
            fileTools: FileTools(provider: files),
            currentFileSelection: StaticCurrentFileSelection(file: selection)
        )
        let request = AssistantRequest(input: .text("open this"), source: .commandPalette)

        var events: [AssistantEvent] = []
        for await event in await orchestrator.submit(request) { events.append(event) }

        XCTAssertEqual(events.last, .responseCompleted("Opened selected.pdf."))
        XCTAssertEqual(files.opened, [selection])
    }

    func testMoveUsesExplicitAliasBeforeTreatingDestinationAsAPath() async throws {
        let files = MockFileSystemProvider()
        var aliases = AliasStore()
        _ = try aliases.create(alias: "school folder", target: "/tmp/School")
        let sessions = SessionManager()
        let orchestrator = InteractionOrchestrator(sessionManager: sessions, fileTools: FileTools(provider: files), aliases: aliases)
        let opened = AssistantRequest(input: .text("open /tmp/geometry.pdf"), source: .commandPalette)
        let moved = AssistantRequest(input: .text("move it to school folder"), source: .cli)

        for await _ in await orchestrator.submit(opened) {}
        var events: [AssistantEvent] = []
        for await event in await orchestrator.submit(moved) { events.append(event) }

        XCTAssertEqual(files.moves.first?.1.path, "/tmp/School/geometry.pdf")
        XCTAssertEqual(events.last, .responseCompleted("Moved geometry.pdf to School."))
    }
}
