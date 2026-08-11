import XCTest
@testable import LEO

final class FileToolsJournalTests: XCTestCase {
    func testContextRetrieverRanksRecentMatchingPDFAndBoundsResults() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let events = [
            JournalEvent(id: UUID(), timestamp: now.addingTimeInterval(-10), type: "file.open", source: .commandPalette, entityID: "file:pdf", sensitivity: .privateData, summary: "geometry.pdf"),
            JournalEvent(id: UUID(), timestamp: now.addingTimeInterval(-20), type: "file.open", source: .cli, entityID: "file:notes", sensitivity: .privateData, summary: "notes.txt"),
            JournalEvent(id: UUID(), timestamp: now.addingTimeInterval(-30), type: "app.open", source: .commandPalette, entityID: "app:Preview", sensitivity: .publicData, summary: "Preview")
        ]

        let matches = ContextRetriever(maximumResults: 2, maximumContextCharacters: 40)
            .retrieve(query: "open the PDF from earlier", from: events, now: now)

        XCTAssertEqual(matches.first?.event.summary, "geometry.pdf")
        XCTAssertLessThanOrEqual(matches.count, 2)
        XCTAssertLessThanOrEqual(matches.reduce(0) { $0 + ($1.event.summary?.count ?? 0) }, 40)
    }

    func testFileToolsMoveRenameAndInspectTemporaryFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("before.txt")
        let destination = root.appendingPathComponent("moved.txt")
        try Data("hello".utf8).write(to: source)
        let tools = FileTools()
        XCTAssertEqual(try tools.inspect(source).byteSize, 5)
        try tools.move(source, to: destination)
        let renamed = try tools.rename(destination, to: "after.txt")
        XCTAssertEqual(renamed.lastPathComponent, "after.txt")
    }

    func testJournalFiltersImmediateDuplicatesAndPersists() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let event = JournalEvent(id: UUID(), timestamp: .now, type: "file.move", source: .cli, entityID: "file:/tmp/a", sensitivity: .privateData)
        let journal = try EventJournal(fileURL: url)
        let firstAppend = try await journal.append(event)
        let duplicateAppend = try await journal.append(event)
        XCTAssertTrue(firstAppend)
        XCTAssertFalse(duplicateAppend)
        let reopened = try EventJournal(fileURL: url)
        let persisted = await reopened.recent()
        XCTAssertEqual(persisted, [event])
    }
}
