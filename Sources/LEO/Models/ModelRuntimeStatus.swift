import Foundation

/// The evidence-backed state of the model runtime available to LEO.
///
/// This is deliberately separate from `ModelHost`: the host can be exercised
/// with a mock backend without implying that a production local model exists.
enum ModelRuntimeStatus: Sendable, Equatable, Codable {
    /// No local model runtime or model weights are configured.
    case unavailable(reason: String)

    /// The deterministic fixture backend is available for plumbing tests only.
    case fixtureOnly(reason: String)

    /// A real local backend has been configured and is ready to serve requests.
    case available(backend: String)

    var isProductionReady: Bool {
        if case .available = self { return true }
        return false
    }

    var availability: String {
        switch self {
        case .unavailable: "unavailable"
        case .fixtureOnly: "fixture-only"
        case .available: "available"
        }
    }

    var reason: String? {
        switch self {
        case let .unavailable(reason), let .fixtureOnly(reason): reason
        case .available: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case reason
        case backend
    }

    private enum State: String, Codable {
        case unavailable
        case fixtureOnly = "fixture-only"
        case available
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .unavailable:
            self = .unavailable(reason: try container.decode(String.self, forKey: .reason))
        case .fixtureOnly:
            self = .fixtureOnly(reason: try container.decode(String.self, forKey: .reason))
        case .available:
            self = .available(backend: try container.decode(String.self, forKey: .backend))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .unavailable(reason):
            try container.encode(State.unavailable, forKey: .state)
            try container.encode(reason, forKey: .reason)
        case let .fixtureOnly(reason):
            try container.encode(State.fixtureOnly, forKey: .state)
            try container.encode(reason, forKey: .reason)
        case let .available(backend):
            try container.encode(State.available, forKey: .state)
            try container.encode(backend, forKey: .backend)
        }
    }
}

extension ModelRuntimeStatus {
    static let current: ModelRuntimeStatus = .available(
        backend: "LM Studio (qwen/qwen3-4b MLX 4-bit)"
    )
}
