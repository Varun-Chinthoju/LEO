import Foundation

struct JournalEvent: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: String
    let source: RequestSource?
    let entityID: String?
    let sensitivity: Sensitivity
    let summary: String?

    init(
        id: UUID,
        timestamp: Date,
        type: String,
        source: RequestSource?,
        entityID: String?,
        sensitivity: Sensitivity,
        summary: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.source = source
        self.entityID = entityID
        self.sensitivity = sensitivity
        self.summary = summary
    }

    enum Sensitivity: String, Codable, Sendable { case publicData, privateData, sensitive }
}

actor EventJournal {
    private let fileURL: URL?
    private var events: [JournalEvent]

    init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            self.events = try JSONDecoder().decode([JournalEvent].self, from: data)
        } else {
            self.events = []
        }
    }

    @discardableResult
    func append(_ event: JournalEvent) throws -> Bool {
        if events.last == event { return false }
        events.append(event)
        try persist()
        return true
    }

    func recent(limit: Int = 50) -> [JournalEvent] {
        Array(events.suffix(max(0, limit)))
    }

    func matching(type: String) -> [JournalEvent] {
        events.filter { $0.type == type }
    }

    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(events).write(to: fileURL, options: .atomic)
    }
}
