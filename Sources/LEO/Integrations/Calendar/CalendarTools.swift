import Foundation

struct CalendarTools {
    let provider: any CalendarProviderProtocol

    init(provider: some CalendarProviderProtocol = CalendarProvider()) { self.provider = provider }

    func definitions() -> [ToolDefinition] { [listDefinition(), createDefinition()] }

    private func listDefinition() -> ToolDefinition {
        ToolDefinition(name: "calendar.list", effect: .readOnly, idempotency: .idempotent, requiredArguments: ["start", "end"]) { [provider] arguments in
            let start = try Self.date(arguments["start"] ?? "")
            let end = try Self.date(arguments["end"] ?? "")
            let limit = Int(arguments["limit"] ?? "20") ?? 20
            let events = try Self.await { try await provider.upcomingEvents(from: start, to: end, limit: limit) }
            return try ToolResult.success(Self.encode(events))
        }
    }

    private func createDefinition() -> ToolDefinition {
        ToolDefinition(name: "calendar.create", effect: .consequential, idempotency: .nonIdempotent, requiredArguments: ["title", "start", "end"]) { [provider] arguments in
            let request = CalendarEventCreationRequest(title: arguments["title"] ?? "", startDate: try Self.date(arguments["start"] ?? ""), endDate: try Self.date(arguments["end"] ?? ""), location: arguments["location"], notes: arguments["notes"], isAllDay: arguments["allDay"] == "true")
            let event = try Self.await { try await provider.createEvent(request) }
            return try ToolResult.success(Self.encode(event))
        }
    }

    private static func date(_ value: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else { throw CalendarError.invalidRequest("Calendar dates must use ISO 8601 format.") }
        return date
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }

    private static func await<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedCalendarResult<T>()
        Task.detached {
            do { result.store(.success(try await operation())) }
            catch { result.store(.failure(error)) }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 2) == .success else { throw ToolBrokerError.timedOut }
        return try result.take()
    }
}

private final class LockedCalendarResult<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    func store(_ result: Result<T, Error>) { lock.withLock { self.result = result } }
    func take() throws -> T {
        try lock.withLock {
            guard let result else { throw ToolBrokerError.executionFailed("Calendar tool returned no result.") }
            return try result.get()
        }
    }
}
