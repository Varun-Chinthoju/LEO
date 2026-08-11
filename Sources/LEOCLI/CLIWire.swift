import Foundation

struct CLIWireMessage: Codable {
    static let currentVersion = 1
    let version: Int
    let payload: Payload

    enum Payload: Codable {
        case request(CLIWireRequest)
        case event(CLIWireEvent)

        private enum CodingKeys: String, CodingKey { case kind, request, event }
        private enum Kind: String, Codable { case request, event }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .request: self = .request(try container.decode(CLIWireRequest.self, forKey: .request))
            case .event: self = .event(try container.decode(CLIWireEvent.self, forKey: .event))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .request(let request):
                try container.encode(Kind.request, forKey: .kind)
                try container.encode(request, forKey: .request)
            case .event(let event):
                try container.encode(Kind.event, forKey: .kind)
                try container.encode(event, forKey: .event)
            }
        }
    }
}

struct CLIWireRequest: Codable {
    let id: UUID
    let sessionID: UUID
    let input: Input
    let source: String
    let createdAt: Date
    let presentation: Presentation

    enum Input: Codable { case text(String) }

    struct Presentation: Codable {
        let showText: Bool
        let speakResponse: Bool
        let machineReadable: Bool
    }
}

struct CLIWireEvent: Codable {
    private enum Event: String, Codable {
        case accepted, thinking, reasoningSummary, actionStarted, actionProgress
        case actionFinished, responseDelta, responseCompleted, confirmationRequired, failed
    }

    let value: Value

    enum Value {
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

    private enum CodingKeys: String, CodingKey { case event, accepted, thinking, reasoningSummary, actionStarted, actionProgress, actionFinished, responseDelta, responseCompleted, confirmationRequired, failed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // AssistantEvent uses Swift's synthesized enum Codable shape, e.g.
        // {"responseCompleted":{"_0":"Done."}}. Keep accepting the
        // explicit discriminator shape for forward compatibility, but decode
        // the synthesized shape used by the app today.
        let event: Event
        if let explicit = try? container.decode(Event.self, forKey: .event) {
            event = explicit
        } else {
            guard let key = container.allKeys.first(where: { $0.stringValue != CodingKeys.event.stringValue }),
                  let synthesized = Event(rawValue: key.stringValue) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown assistant event"))
            }
            event = synthesized
        }
        switch event {
        case .accepted: self.value = .accepted(try container.decode(Associated<UUID>.self, forKey: .accepted)._0)
        case .thinking: self.value = .thinking
        case .reasoningSummary: self.value = .reasoningSummary(try container.decode(Associated<String>.self, forKey: .reasoningSummary)._0)
        case .actionStarted: self.value = .actionStarted(try container.decode(Associated<ActionSummary>.self, forKey: .actionStarted)._0)
        case .actionProgress: self.value = .actionProgress(try container.decode(Associated<ActionProgress>.self, forKey: .actionProgress)._0)
        case .actionFinished: self.value = .actionFinished(try container.decode(Associated<ActionResultSummary>.self, forKey: .actionFinished)._0)
        case .responseDelta: self.value = .responseDelta(try container.decode(Associated<String>.self, forKey: .responseDelta)._0)
        case .responseCompleted: self.value = .responseCompleted(try container.decode(Associated<String>.self, forKey: .responseCompleted)._0)
        case .confirmationRequired: self.value = .confirmationRequired(try container.decode(Associated<ConfirmationRequest>.self, forKey: .confirmationRequired)._0)
        case .failed: self.value = .failed(try container.decode(Associated<AssistantFailure>.self, forKey: .failed)._0)
        }
    }

    struct ActionSummary: Codable { let id: UUID; let title: String; let detail: String? }
    struct ActionProgress: Codable { let actionID: UUID; let detail: String?; let fractionCompleted: Double? }
    struct ActionResultSummary: Codable { let actionID: UUID; let title: String; let detail: String?; let succeeded: Bool }
    struct ConfirmationRequest: Codable { let id: UUID; let title: String; let detail: String?; let defaultIsConfirmed: Bool }
    struct AssistantFailure: Codable { let message: String; let code: String?; let isRecoverable: Bool }

    func encode(to encoder: Encoder) throws { fatalError("CLI only decodes events") }
}

private struct Associated<T: Codable>: Codable {
    let _0: T
}
