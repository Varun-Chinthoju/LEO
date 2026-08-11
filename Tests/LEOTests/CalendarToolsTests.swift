import XCTest
@testable import LEO

final class CalendarToolsTests: XCTestCase {
    func testUpcomingRequestsPermissionOnlyWhenFirstNeeded() async throws {
        let access = MockCalendarAccess(status: .notDetermined, requestResult: true)
        let store = MockCalendarStore(events: [CalendarEvent(
            identifier: "event-1",
            title: "Design review",
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 1_600),
            calendarName: "Work",
            location: "Room 1"
        )])
        let provider = CalendarProvider(store: store, access: access)

        _ = try await provider.upcomingEvents(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 2_000), limit: 10)
        _ = try await provider.upcomingEvents(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 2_000), limit: 10)

        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(store.fetchCount, 2)
    }

    func testDeniedAccessFailsBeforeReadingOrCreating() async {
        let access = MockCalendarAccess(status: .denied, requestResult: false)
        let store = MockCalendarStore()
        let provider = CalendarProvider(store: store, access: access)

        do {
            _ = try await provider.upcomingEvents(from: .now, to: .now.addingTimeInterval(3_600), limit: 10)
            XCTFail("Expected access denial")
        } catch let error as CalendarError {
            XCTAssertEqual(error, .accessDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(store.fetchCount, 0)
        XCTAssertEqual(access.requestCount, 0)
    }

    func testCreateIsExplicitAndPreservesCreatedEvent() async throws {
        let event = CalendarEvent(
            identifier: "created",
            title: "Lunch",
            startDate: Date(timeIntervalSince1970: 2_000),
            endDate: Date(timeIntervalSince1970: 2_600),
            calendarName: "Personal",
            location: "Cafe"
        )
        let store = MockCalendarStore(createdEvent: event)
        let provider = CalendarProvider(store: store, access: MockCalendarAccess(status: .authorized))
        let request = CalendarEventCreationRequest(title: "Lunch", startDate: event.startDate, endDate: event.endDate, location: "Cafe")

        let created = try await provider.createEvent(request)

        XCTAssertEqual(created, event)
        XCTAssertEqual(store.lastCreateRequest, request)
    }

    func testToolDefinitionsExposeReadAndExplicitCreate() throws {
        let tools = CalendarTools(provider: MockCalendarProvider()).definitions()
        XCTAssertEqual(tools.map(\.name), ["calendar.list", "calendar.create"])
        XCTAssertEqual(tools[0].effect, .readOnly)
        XCTAssertEqual(tools[1].effect, .consequential)
        XCTAssertEqual(tools[1].idempotency, .nonIdempotent)
        XCTAssertEqual(tools[1].requiredArguments, ["title", "start", "end"])
    }
}

private final class MockCalendarAccess: CalendarAccessProviding, @unchecked Sendable {
    var currentStatus: CalendarAuthorizationStatus
    let requestResult: Bool
    private(set) var requestCount = 0

    init(status: CalendarAuthorizationStatus, requestResult: Bool = true) {
        currentStatus = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> CalendarAuthorizationStatus { currentStatus }
    func requestAccess() async throws -> Bool {
        requestCount += 1
        currentStatus = requestResult ? .authorized : .denied
        return requestResult
    }
}

private final class MockCalendarStore: CalendarStore, @unchecked Sendable {
    var events: [CalendarEvent]
    let createdEvent: CalendarEvent?
    private(set) var fetchCount = 0
    private(set) var lastCreateRequest: CalendarEventCreationRequest?

    init(events: [CalendarEvent] = [], createdEvent: CalendarEvent? = nil) {
        self.events = events
        self.createdEvent = createdEvent
    }

    func fetchEvents(from: Date, to: Date, limit: Int) async throws -> [CalendarEvent] {
        fetchCount += 1
        return Array(events.filter { $0.startDate >= from && $0.startDate <= to }.prefix(limit))
    }

    func saveEvent(_ request: CalendarEventCreationRequest) async throws -> CalendarEvent {
        lastCreateRequest = request
        return createdEvent ?? CalendarEvent(identifier: "mock", title: request.title, startDate: request.startDate, endDate: request.endDate, calendarName: "Mock", location: request.location)
    }
}

private struct MockCalendarProvider: CalendarProviderProtocol {
    func upcomingEvents(from: Date, to: Date, limit: Int) async throws -> [CalendarEvent] { [] }
    func createEvent(_ request: CalendarEventCreationRequest) async throws -> CalendarEvent {
        CalendarEvent(identifier: "mock", title: request.title, startDate: request.startDate, endDate: request.endDate, calendarName: "Mock")
    }
}
