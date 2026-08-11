import XCTest
@testable import LEO

final class QuarantineTests: XCTestCase {
    func testQuarantineMovesAndRestoresWithMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leo-quarantine-\(UUID().uuidString)")
        let source = root.appendingPathComponent("important.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = QuarantineService(rootURL: root.appendingPathComponent("q"))
        let requestID = UUID()
        let record = try service.quarantine(source, requestID: requestID, entityID: "file-1", source: .cli)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.quarantinedURL.path))
        XCTAssertEqual(record.requestID, requestID)
        XCTAssertEqual(record.entityID, "file-1")
        XCTAssertEqual(record.source, .cli)
        let restartedService = QuarantineService(rootURL: root.appendingPathComponent("q"))
        XCTAssertEqual(try restartedService.restore(record.id), source)
        XCTAssertEqual(try String(contentsOf: source), "hello")
    }

    func testRestoreRejectsCollision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leo-quarantine-\(UUID().uuidString)")
        let source = root.appendingPathComponent("file.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: source)
        let service = QuarantineService(rootURL: root.appendingPathComponent("q"))
        let record = try service.quarantine(source, requestID: UUID())
        try Data("new".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try service.restore(record.id)) { error in
            XCTAssertEqual(error as? QuarantineError, .destinationExists(source))
        }
    }

    func testBrokerExposesOnlyReversibleQuarantineAndRestoreTools() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leo-quarantine-\(UUID().uuidString)")
        let source = root.appendingPathComponent("discardable.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = QuarantineService(rootURL: root.appendingPathComponent("q"))
        let broker = ToolBroker(definitions: service.definitions(requestID: UUID(), source: .cli))
        let quarantined = try await broker.execute(
            ToolProposal(name: "files.quarantine", arguments: ["path": source.path]),
            source: .cli,
            confirmationGranted: true
        )
        XCTAssertEqual(quarantined.value, "Quarantined discardable.txt.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))

        let recordURL = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: service.rootURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "json" }))
        let record = try JSONDecoder().decode(QuarantineRecord.self, from: Data(contentsOf: recordURL))
        let restored = try await broker.execute(
            ToolProposal(name: "files.restore", arguments: ["id": record.id.uuidString]),
            source: .cli,
            confirmationGranted: true
        )
        XCTAssertEqual(restored.value, "Restored discardable.txt.")
        XCTAssertEqual(try String(contentsOf: source), "hello")
    }
}
