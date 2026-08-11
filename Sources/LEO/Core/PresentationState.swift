import Foundation

enum PresentationState: String, Codable, Sendable, Equatable {
    case pending
    case speaking
    case spoken
    case interrupted
    case silent
}

struct UtterancePresentation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let source: RequestSource
    var state: PresentationState
    let createdAt: Date
}

struct PresentationTracker: Sendable {
    private(set) var utterances: [UtterancePresentation] = []

    mutating func record(text: String, source: RequestSource, speaks: Bool, id: UUID = UUID()) -> UtterancePresentation {
        let utterance = UtterancePresentation(id: id, text: text, source: source, state: speaks ? .pending : .silent, createdAt: .now)
        utterances.append(utterance)
        return utterance
    }

    mutating func update(_ id: UUID, state: PresentationState) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else { return }
        utterances[index].state = state
    }
}
