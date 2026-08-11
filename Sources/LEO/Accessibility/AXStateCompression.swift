import Foundation

struct AXRawElement: Sendable, Equatable {
    let role: String?
    let label: String?
    let value: String?
    let actions: [String]
    let isVisible: Bool
    let isStructural: Bool
}

struct AXCompressedElement: Codable, Sendable, Equatable {
    let role: String
    let label: String?
    let value: String?
    let actions: [String]
}

struct AXStateCompressor {
    let maxElements: Int

    init(maxElements: Int = 100) { self.maxElements = max(1, maxElements) }

    func compress(_ elements: [AXRawElement]) -> [AXCompressedElement] {
        elements.lazy
            .filter { $0.isVisible && !$0.isStructural && $0.role != nil }
            .prefix(maxElements)
            .map {
                let role = bounded($0.role!, limit: 64) ?? String($0.role!)
                let label = bounded($0.label, limit: 120)
                let value: String?
                if role == "AXSecureTextField" || role == "secureTextField" {
                    value = $0.value == nil ? nil : "[redacted]"
                } else {
                    value = bounded($0.value, limit: 120)
                }
                let actions = Array($0.actions.filter { Self.allowedActions.contains($0) }.prefix(4))
                return AXCompressedElement(role: role, label: label, value: value, actions: actions)
            }
    }

    private static let allowedActions: Set<String> = ["press", "increment", "decrement", "confirm", "cancel"]

    private func bounded(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let sanitized = value.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        let string = String(String.UnicodeScalarView(sanitized))
        guard string.count > limit else { return string }
        return String(string.prefix(limit)) + "…"
    }
}
