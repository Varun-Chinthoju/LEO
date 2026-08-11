import EventKit
import Foundation

enum CalendarAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

struct CalendarEvent: Codable, Sendable, Equatable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarName: String
    let location: String?
    let notes: String?
    let isAllDay: Bool

    init(
        identifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarName: String,
        location: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarName = calendarName
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
    }
}

struct CalendarEventCreationRequest: Sendable, Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let isAllDay: Bool

    init(title: String, startDate: Date, endDate: Date, location: String? = nil, notes: String? = nil, isAllDay: Bool = false) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
    }
}

enum CalendarError: Error, Equatable {
    case accessDenied
    case invalidRequest(String)
    case unavailable(String)
}

protocol CalendarAccessProviding: Sendable {
    func authorizationStatus() -> CalendarAuthorizationStatus
    func requestAccess() async throws -> Bool
}

protocol CalendarStore: Sendable {
    func fetchEvents(from: Date, to: Date, limit: Int) async throws -> [CalendarEvent]
    func saveEvent(_ request: CalendarEventCreationRequest) async throws -> CalendarEvent
}

protocol CalendarProviderProtocol: Sendable {
    func upcomingEvents(from: Date, to: Date, limit: Int) async throws -> [CalendarEvent]
    func createEvent(_ request: CalendarEventCreationRequest) async throws -> CalendarEvent
}

struct CalendarProvider: CalendarProviderProtocol, Sendable {
    private let store: any CalendarStore
    private let access: any CalendarAccessProviding

    init(store: some CalendarStore = EventKitCalendarStore(), access: some CalendarAccessProviding = EventKitCalendarAccess()) {
        self.store = store
        self.access = access
    }

    func upcomingEvents(from: Date, to: Date, limit: Int) async throws -> [CalendarEvent] {
        guard from <= to, limit > 0 else { throw CalendarError.invalidRequest("Calendar range or limit is invalid.") }
        try await ensureAccess()
        return try await store.fetchEvents(from: from, to: to, limit: min(limit, 100))
    }

    func createEvent(_ request: CalendarEventCreationRequest) async throws -> CalendarEvent {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.startDate < request.endDate else {
            throw CalendarError.invalidRequest("Calendar event title or time is invalid.")
        }
        try await ensureAccess()
        return try await store.saveEvent(request)
    }

    private func ensureAccess() async throws {
        switch access.authorizationStatus() {
        case .authorized:
            return
        case .denied, .restricted:
            throw CalendarError.accessDenied
        case .notDetermined:
            guard try await access.requestAccess(), access.authorizationStatus() == .authorized else {
                throw CalendarError.accessDenied
            }
        }
    }
}

final class EventKitCalendarAccess: CalendarAccessProviding, @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) { self.store = store }

    func authorizationStatus() -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .authorized, .fullAccess: return .authorized
        case .writeOnly: return .denied
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }
}

final class EventKitCalendarStore: CalendarStore, @unchecked Sendable {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) { self.store = store }

    func fetchEvents(from: Date, to: Date, limit: Int) async throws -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map(Self.map)
    }

    func saveEvent(_ request: CalendarEventCreationRequest) async throws -> CalendarEvent {
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarError.unavailable("No writable calendar is available.")
        }
        let event = EKEvent(eventStore: store)
        event.title = request.title
        event.startDate = request.startDate
        event.endDate = request.endDate
        event.location = request.location
        event.notes = request.notes
        event.isAllDay = request.isAllDay
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return Self.map(event)
    }

    private static func map(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(identifier: event.eventIdentifier ?? "", title: event.title ?? "", startDate: event.startDate, endDate: event.endDate, calendarName: event.calendar.title, location: event.location, notes: event.notes, isAllDay: event.isAllDay)
    }
}
