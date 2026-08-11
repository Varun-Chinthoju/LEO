import XCTest
@testable import LEO

final class SessionManagerTests: XCTestCase {
    func testDefaultSessionIDIsSharedAcrossSources() async {
        let manager = SessionManager(sharedSessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)

        XCTAssertEqual(manager.sessionID(for: .commandPalette), manager.sharedSessionID)
        XCTAssertEqual(manager.sessionID(for: .cli), manager.sharedSessionID)
        XCTAssertEqual(manager.sessionID(for: .voice), manager.sharedSessionID)
    }

    func testSharedSessionPersistsAcrossAlternatingSources() async {
        let manager = SessionManager(sharedSessionID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let sessionID = manager.sharedSessionID

        let requests = [
            AssistantRequest(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                sessionID: sessionID,
                input: .text("Open Mail"),
                source: .commandPalette,
                createdAt: Date(timeIntervalSinceReferenceDate: 1)
            ),
            AssistantRequest(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                sessionID: sessionID,
                input: .text("List drafts"),
                source: .cli,
                createdAt: Date(timeIntervalSinceReferenceDate: 2)
            ),
            AssistantRequest(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                sessionID: sessionID,
                input: .text("Read my last email"),
                source: .voice,
                createdAt: Date(timeIntervalSinceReferenceDate: 3)
            )
        ]

        for request in requests {
            _ = await manager.record(request: request)
        }

        let state = await manager.conversationState(for: sessionID)
        XCTAssertEqual(state?.recentTurns.map(\.source), [.commandPalette, .cli, .voice])
        XCTAssertEqual(state?.recentTurns.map(\.requestID), requests.map(\.id))
        XCTAssertNil(state?.activeTask)
        XCTAssertEqual(state?.referents, [])
    }

    func testConversationStateStoresActiveTaskAndReferents() async {
        let manager = SessionManager(sharedSessionID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!)
        let sessionID = await manager.createIsolatedSession()

        let task = TaskState(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "Draft reply",
            detail: "Follow up on the meeting notes",
            status: .active,
            updatedAt: Date(timeIntervalSinceReferenceDate: 4)
        )
        let referents = [
            SessionReferent(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                label: "meeting notes",
                sourceTurnID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                updatedAt: Date(timeIntervalSinceReferenceDate: 5)
            )
        ]

        _ = await manager.setActiveTask(task, for: sessionID)
        _ = await manager.setReferents(referents, for: sessionID)

        let state = await manager.conversationState(for: sessionID)
        XCTAssertEqual(state?.activeTask, task)
        XCTAssertEqual(state?.referents, referents)
    }

    func testIsolatedSessionDoesNotShareStateWithDefaultSession() async {
        let manager = SessionManager(sharedSessionID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!)
        let sharedSessionID = manager.sharedSessionID
        let isolatedSessionID = await manager.createIsolatedSession()

        let sharedRequest = AssistantRequest(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            sessionID: sharedSessionID,
            input: .text("Open Calendar"),
            source: .commandPalette,
            createdAt: Date(timeIntervalSinceReferenceDate: 6)
        )
        let isolatedRequest = AssistantRequest(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            sessionID: isolatedSessionID,
            input: .text("List Downloads"),
            source: .cli,
            createdAt: Date(timeIntervalSinceReferenceDate: 7)
        )

        _ = await manager.record(request: sharedRequest)
        _ = await manager.record(request: isolatedRequest)

        let sharedState = await manager.conversationState(for: sharedSessionID)
        let isolatedState = await manager.conversationState(for: isolatedSessionID)

        XCTAssertEqual(sharedState?.recentTurns.map(\.requestID), [sharedRequest.id])
        XCTAssertEqual(isolatedState?.recentTurns.map(\.requestID), [isolatedRequest.id])
        XCTAssertNotEqual(sharedState?.recentTurns.first?.sessionID, isolatedState?.recentTurns.first?.sessionID)
    }
}
