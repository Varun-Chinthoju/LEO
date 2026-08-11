import Foundation

struct AssistantRequest: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let input: AssistantInput
    let source: RequestSource
    let createdAt: Date
    let presentation: PresentationPreference

    init(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        input: AssistantInput,
        source: RequestSource,
        createdAt: Date = .now,
        presentation: PresentationPreference? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.input = input
        self.source = source
        self.createdAt = createdAt
        self.presentation = presentation ?? .defaultPresentation(for: source)
    }
}

enum AssistantInput: Codable, Sendable, Equatable {
    case text(String)
}

enum RequestSource: String, Codable, Sendable, Equatable {
    case voice
    case commandPalette
    case cli
}
