import Foundation

actor SessionManager {
    nonisolated let sharedSessionID: UUID
    nonisolated var defaultSessionID: UUID { sharedSessionID }

    private var sessions: [UUID: ConversationState]

    init(sharedSessionID: UUID = UUID()) {
        self.sharedSessionID = sharedSessionID
        self.sessions = [
            sharedSessionID: ConversationState(sessionID: sharedSessionID)
        ]
    }

    func createIsolatedSession() -> UUID {
        let sessionID = UUID()
        sessions[sessionID] = ConversationState(sessionID: sessionID)
        return sessionID
    }

    func makeIsolatedSession() -> UUID { createIsolatedSession() }

    nonisolated func sessionID(for source: RequestSource) -> UUID { sharedSessionID }

    func sessionID(for request: AssistantRequest) -> UUID {
        sessions[request.sessionID] != nil ? request.sessionID : defaultSessionID
    }

    func record(request: AssistantRequest, in sessionID: UUID? = nil) -> ConversationTurn {
        let resolvedSessionID = sessionID ?? self.sessionID(for: request)
        var state = conversationState(in: resolvedSessionID)
        let turn = state.recordTurn(from: request)
        sessions[resolvedSessionID] = state
        return turn
    }

    func record(_ request: AssistantRequest, in sessionID: UUID? = nil) -> ConversationTurn {
        record(request: request, in: sessionID)
    }

    func updateActiveTask(_ task: TaskState?, in sessionID: UUID? = nil) {
        let resolvedSessionID = sessionID ?? defaultSessionID
        var state = conversationState(in: resolvedSessionID)
        state.setActiveTask(task)
        sessions[resolvedSessionID] = state
    }

    func upsertReferent(_ referent: ConversationReferent, in sessionID: UUID? = nil) {
        let resolvedSessionID = sessionID ?? defaultSessionID
        var state = conversationState(in: resolvedSessionID)
        state.upsertReferent(referent)
        sessions[resolvedSessionID] = state
    }

    func setActiveTask(_ task: TaskState?, for sessionID: UUID) -> ConversationState {
        updateActiveTask(task, in: sessionID)
        return conversationState(in: sessionID)
    }

    func setReferents(_ referents: [SessionReferent], for sessionID: UUID) -> ConversationState {
        var state = conversationState(in: sessionID)
        state.setReferents(referents)
        sessions[sessionID] = state
        return state
    }

    func removeReferent(label: String, in sessionID: UUID? = nil) {
        let resolvedSessionID = sessionID ?? defaultSessionID
        var state = conversationState(in: resolvedSessionID)
        state.removeReferent(label: label)
        sessions[resolvedSessionID] = state
    }

    func conversationState(in sessionID: UUID? = nil) -> ConversationState {
        let resolvedSessionID = sessionID ?? defaultSessionID
        if let state = sessions[resolvedSessionID] {
            return state
        }

        let state = ConversationState(sessionID: resolvedSessionID)
        sessions[resolvedSessionID] = state
        return state
    }

    func conversationState(for sessionID: UUID) -> ConversationState? {
        sessions[sessionID]
    }

    func conversationState(for request: AssistantRequest) -> ConversationState {
        conversationState(in: sessionID(for: request))
    }

    func recentTurns(in sessionID: UUID? = nil, limit: Int? = nil) -> [ConversationTurn] {
        conversationState(in: sessionID).recentTurns(limit: limit)
    }

    func activeTask(in sessionID: UUID? = nil) -> TaskState? {
        conversationState(in: sessionID).activeTask
    }

    func referent(label: String, in sessionID: UUID? = nil) -> ConversationReferent? {
        conversationState(in: sessionID).referent(label: label)
    }
}
