import Foundation

struct ComputerTools {
    private let controller: any AccessibilityController

    init(controller: any AccessibilityController) {
        self.controller = controller
    }

    func definitions() -> [ToolDefinition] {
        [snapshotDefinition(), searchDefinition(), performDefinition()]
    }

    private func snapshotDefinition() -> ToolDefinition {
        ToolDefinition(name: "computer.snapshot", effect: .readOnly, idempotency: .idempotent) { [controller] _ in
            let snapshot = try Self.await { try await controller.snapshotFrontmostApplication() }
            return try ToolResult.success(Self.encode(snapshot))
        }
    }

    private func searchDefinition() -> ToolDefinition {
        ToolDefinition(name: "computer.search", effect: .readOnly, idempotency: .idempotent, requiredArguments: ["query"]) { [controller] arguments in
            let query = arguments["query"] ?? ""
            let matches = try Self.await { try await controller.find(AXQuery(value: query)) }
            let semantic = AXStateCompressor(maxElements: 20).compress(matches.map {
                AXRawElement(role: $0.role, label: $0.label, value: $0.value, actions: $0.actions, isVisible: true, isStructural: false)
            })
            return try ToolResult.success(Self.encode(semantic))
        }
    }

    private func performDefinition() -> ToolDefinition {
        ToolDefinition(name: "computer.perform", effect: .reversibleWrite, idempotency: .nonIdempotent, requiredArguments: ["query", "action"]) { [controller] arguments in
            let action = arguments["action"] ?? ""
            guard MacosUseAccessibilityController.allowedActions.contains(action) else {
                throw AccessibilityControllerError.actionNotAllowed(action)
            }
            let matches = try Self.await { try await controller.find(AXQuery(value: arguments["query"] ?? "")) }
            guard matches.count == 1, let match = matches.first else {
                throw matches.isEmpty ? AccessibilityControllerError.elementUnavailable : AccessibilityControllerError.ambiguousMatch
            }
            try Self.await { try await controller.perform(AXAction(value: action), on: match) }
            return ToolResult.success("Performed \(action).")
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8_192 else { throw AccessibilityControllerError.elementUnavailable }
        return String(decoding: data, as: UTF8.self)
    }

    private static func await<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedComputerResult<T>()
        Task.detached {
            do {
                result.store(.success(try await operation()))
            } catch {
                result.store(.failure(error))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 2) == .success else {
            throw ToolBrokerError.timedOut
        }
        return try result.take()
    }
}

private final class LockedComputerResult<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ result: Result<T, Error>) { lock.withLock { self.result = result } }
    func take() throws -> T {
        try lock.withLock {
            guard let result else { throw ToolBrokerError.executionFailed("Computer tool returned no result.") }
            return try result.get()
        }
    }
}
