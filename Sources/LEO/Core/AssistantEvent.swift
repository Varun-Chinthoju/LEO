import Foundation

struct ActionSummary: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let detail: String?

    init(id: UUID = UUID(), title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

struct ActionProgress: Codable, Sendable, Equatable {
    let actionID: UUID
    let detail: String?
    let fractionCompleted: Double?

    init(actionID: UUID, detail: String? = nil, fractionCompleted: Double? = nil) {
        self.actionID = actionID
        self.detail = detail
        self.fractionCompleted = fractionCompleted
    }
}

struct ActionResultSummary: Codable, Sendable, Equatable {
    let actionID: UUID
    let title: String
    let detail: String?
    let succeeded: Bool

    init(actionID: UUID, title: String, detail: String? = nil, succeeded: Bool) {
        self.actionID = actionID
        self.title = title
        self.detail = detail
        self.succeeded = succeeded
    }
}

struct ConfirmationRequest: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let detail: String?
    let defaultIsConfirmed: Bool

    init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        defaultIsConfirmed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.defaultIsConfirmed = defaultIsConfirmed
    }
}

struct AssistantFailure: Codable, Sendable, Equatable {
    let message: String
    let code: String?
    let isRecoverable: Bool

    init(message: String, code: String? = nil, isRecoverable: Bool = true) {
        self.message = message
        self.code = code
        self.isRecoverable = isRecoverable
    }
}

enum AssistantEvent: Codable, Sendable, Equatable {
    case accepted(UUID)
    case thinking
    case reasoningSummary(String)
    case actionStarted(ActionSummary)
    case actionProgress(ActionProgress)
    case actionFinished(ActionResultSummary)
    case responseDelta(String)
    case responseCompleted(String)
    case confirmationRequired(ConfirmationRequest)
    case failed(AssistantFailure)
}
