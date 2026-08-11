import Foundation
import XCTest
@testable import LEO

final class DatabaseTests: XCTestCase {
    func testInMemoryDatabaseInitializesAndMigrates() throws {
        let database = Database(location: .inMemory)

        try database.open()

        XCTAssertEqual(try database.userVersion(), DatabaseMigrations.latestVersion)
    }

    func testTemporaryDatabaseSupportsFreshInstallAndMigration() throws {
        let database = Database(location: .temporary)

        try database.open()
        try database.execute("INSERT INTO metadata (key, value) VALUES ('hello', 'world');")

        XCTAssertEqual(try database.userVersion(), 1)
    }

    func testMissingParentDirectoryFailsSafely() {
        let database = Database(location: .file(URL(fileURLWithPath: "/private/tmp/does-not-exist/subdir/leo.sqlite")))

        XCTAssertThrowsError(try database.open()) { error in
            XCTAssertEqual(error as? DatabaseError, .invalidPath)
        }
    }

    func testCorruptDatabaseFailsSafely() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("leo-corrupt-\(UUID().uuidString).sqlite")
        try Data("not sqlite".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let database = Database(location: .file(url))

        XCTAssertThrowsError(try database.open())
    }
}

