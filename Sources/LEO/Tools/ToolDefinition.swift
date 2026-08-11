import Foundation

enum ToolEffect: String, Codable, Sendable, Equatable {
    case readOnly
    case reversibleWrite
    case consequential
}

enum ToolIdempotency: String, Codable, Sendable, Equatable {
    case idempotent
    case nonIdempotent
}

struct ToolProposal: Codable, Sendable, Equatable {
    let name: String
    let arguments: [String: String]
}

struct ToolResult: Codable, Sendable, Equatable {
    let value: String
    let succeeded: Bool
    let traceID: String

    static func success(_ value: String, traceID: String = UUID().uuidString) -> ToolResult {
        ToolResult(value: value, succeeded: true, traceID: traceID)
    }
}

enum ToolArgumentValidationError: Error, Equatable {
    case invalidKey(String)
    case keyTooLong(String)
    case emptyValue(String)
    case controlCharacter(String)
    case valueTooLong(String)
    case tooManyArguments
    case payloadTooLarge
}

struct ToolDefinition: Sendable {
    // Keep the schema deliberately small and transport-safe. Limits are byte-based
    // so they bound the actual UTF-8 payload crossing the IPC boundary.
    static let maximumArgumentCount = 32
    static let maximumKeyBytes = 64
    static let maximumValueBytes = 256
    static let maximumPayloadBytes = 512

    let name: String
    let effect: ToolEffect
    let idempotency: ToolIdempotency
    let requiredArguments: Set<String>
    let execute: @Sendable ([String: String]) throws -> ToolResult

    init(
        name: String,
        effect: ToolEffect,
        idempotency: ToolIdempotency,
        requiredArguments: Set<String> = [],
        execute: @escaping @Sendable ([String: String]) throws -> ToolResult
    ) {
        self.name = name
        self.effect = effect
        self.idempotency = idempotency
        self.requiredArguments = requiredArguments
        self.execute = { arguments in
            try ToolDefinition.validate(arguments)
            return try execute(arguments)
        }
    }

    private static func validate(_ arguments: [String: String]) throws {
        guard arguments.count <= maximumArgumentCount else {
            throw ToolArgumentValidationError.tooManyArguments
        }

        var payloadBytes = 0
        for (key, value) in arguments {
            guard !key.isEmpty else {
                throw ToolArgumentValidationError.invalidKey(key)
            }
            if containsControlCharacter(key) {
                throw ToolArgumentValidationError.controlCharacter(key)
            }
            guard !key.contains(where: \.isWhitespace) else {
                throw ToolArgumentValidationError.invalidKey(key)
            }
            guard key.utf8.count <= maximumKeyBytes else {
                throw ToolArgumentValidationError.keyTooLong(key)
            }
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolArgumentValidationError.emptyValue(key)
            }
            guard !containsControlCharacter(value) else {
                throw ToolArgumentValidationError.controlCharacter(key)
            }
            guard value.utf8.count <= maximumValueBytes else {
                throw ToolArgumentValidationError.valueTooLong(key)
            }

            payloadBytes += key.utf8.count + value.utf8.count
            guard payloadBytes <= maximumPayloadBytes else {
                throw ToolArgumentValidationError.payloadTooLarge
            }
        }
    }

    private static func containsControlCharacter(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
        }
    }
}
