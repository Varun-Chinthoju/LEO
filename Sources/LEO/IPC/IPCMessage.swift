import Foundation

struct IPCMessage: Codable, Sendable, Equatable {
    static let currentVersion = 1
    let version: Int
    let payload: Payload

    enum Payload: Codable, Sendable, Equatable {
        case request(AssistantRequest)
        case event(AssistantEvent)

        private enum CodingKeys: String, CodingKey { case kind, request, event }
        private enum Kind: String, Codable { case request, event }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .request: self = .request(try container.decode(AssistantRequest.self, forKey: .request))
            case .event: self = .event(try container.decode(AssistantEvent.self, forKey: .event))
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

    init(version: Int = currentVersion, payload: Payload) {
        self.version = version
        self.payload = payload
    }
}
