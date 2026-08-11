import Foundation

struct ConversationTurn: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let source: RequestSource
    let input: AssistantInput
    let createdAt: Date

    var requestID: UUID { id }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        source: RequestSource,
        input: AssistantInput,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.source = source
        self.input = input
        self.createdAt = createdAt
    }
}

struct SessionReferent: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let label: String
    var updatedAt: Date
    var sourceTurnID: UUID?
    var entityID: String?
    var currentURL: URL?

    init(
        id: UUID = UUID(),
        label: String,
        sourceTurnID: UUID? = nil,
        updatedAt: Date = .now,
        entityID: String? = nil,
        currentURL: URL? = nil
    ) {
        self.id = id
        self.label = label
        self.updatedAt = updatedAt
        self.sourceTurnID = sourceTurnID
        self.entityID = entityID
        self.currentURL = currentURL
    }
}

typealias ConversationReferent = SessionReferent

struct ConversationState: Codable, Sendable, Equatable {
    let sessionID: UUID
    private(set) var recentTurns: [ConversationTurn]
    private(set) var activeTask: TaskState?
    private(set) var referents: [SessionReferent]
    private(set) var updatedAt: Date

    init(
        sessionID: UUID,
        recentTurns: [ConversationTurn] = [],
        activeTask: TaskState? = nil,
        referents: [SessionReferent] = [],
        updatedAt: Date = .now
    ) {
        self.sessionID = sessionID
        self.recentTurns = recentTurns
        self.activeTask = activeTask
        self.referents = referents
        self.updatedAt = updatedAt
    }

    mutating func recordTurn(from request: AssistantRequest) -> ConversationTurn {
        let turn = ConversationTurn(
            id: request.id,
            sessionID: sessionID,
            source: request.source,
            input: request.input,
            createdAt: request.createdAt
        )

        recentTurns.append(turn)
        updatedAt = request.createdAt
        return turn
    }

    mutating func setActiveTask(_ task: TaskState?) {
        activeTask = task
        updatedAt = task?.updatedAt ?? .now
    }

    mutating func upsertReferent(_ referent: ConversationReferent) {
        referents.removeAll { $0.label == referent.label }
        referents.append(referent)
        updatedAt = referent.updatedAt
    }

    mutating func setReferents(_ referents: [SessionReferent]) {
        self.referents = referents
        updatedAt = .now
    }

    mutating func removeReferent(label: String) {
        referents.removeAll { $0.label == label }
        updatedAt = .now
    }

    func referent(label: String) -> ConversationReferent? {
        referents.first { $0.label == label }
    }

    func recentTurns(limit: Int? = nil) -> [ConversationTurn] {
        guard let limit, limit >= 0, recentTurns.count > limit else {
            return recentTurns
        }

        return Array(recentTurns.suffix(limit))
    }
}
