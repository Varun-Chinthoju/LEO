import XCTest
@testable import LEO

final class AliasStoreTests: XCTestCase {
    func testCreateReadAndResolveAreCaseInsensitive() throws {
        var store = AliasStore()

        let created = try store.create(alias: "School Folder", target: "~/School")

        XCTAssertEqual(created.alias, "School Folder")
        XCTAssertEqual(created.target, "~/School")
        XCTAssertEqual(store.read(alias: " school   folder ")?.target, "~/School")
        XCTAssertEqual(store.resolve("SCHOOL FOLDER"), "~/School")
    }

    func testUpdateChangesTargetWithoutCreatingDuplicate() throws {
        var store = AliasStore()
        _ = try store.create(alias: "Coding Folder", target: "~/Developer")

        let updated = try store.update(alias: " coding folder ", target: "~/Projects")

        XCTAssertEqual(updated.alias, "Coding Folder")
        XCTAssertEqual(updated.target, "~/Projects")
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.resolve("CODING FOLDER"), "~/Projects")
    }

    func testDeleteRemovesAliasAndReportsMissingRecords() throws {
        var store = AliasStore()
        _ = try store.create(alias: "School Folder", target: "~/School")

        XCTAssertTrue(try store.delete(alias: "school folder"))
        XCTAssertFalse(try store.delete(alias: "school folder"))
        XCTAssertNil(store.resolve("school folder"))
    }

    func testNormalizationRejectsUnsafeOrEmptyValues() {
        var store = AliasStore()

        XCTAssertThrowsError(try store.create(alias: "   ", target: "~/School"))
        XCTAssertThrowsError(try store.create(alias: "School\nFolder", target: "~/School"))
        XCTAssertThrowsError(try store.create(alias: "School Folder", target: "   "))
        XCTAssertThrowsError(try store.create(alias: "School Folder", target: "~/School\n"))
    }

    func testDuplicateAliasesAreRejectedAfterNormalization() throws {
        var store = AliasStore()
        _ = try store.create(alias: "School Folder", target: "~/School")

        XCTAssertThrowsError(try store.create(alias: " school   folder ", target: "~/Other")) { error in
            XCTAssertEqual(error as? AliasStoreError, .duplicateAlias("school folder"))
        }
    }

    func testRecordsAreReturnedInDeterministicNormalizedOrder() throws {
        var store = AliasStore()
        _ = try store.create(alias: "Zebra", target: "z")
        _ = try store.create(alias: "alpha", target: "a")
        _ = try store.create(alias: "Beta", target: "b")

        XCTAssertEqual(store.records.map(\.alias), ["alpha", "Beta", "Zebra"])
    }

    func testAliasesReloadFromExplicitPersistentStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("leo-aliases-\(UUID().uuidString)")
        let storageURL = directory.appendingPathComponent("aliases.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        var firstLaunch = try AliasStore(storageURL: storageURL)
        _ = try firstLaunch.create(alias: "school folder", target: "~/School")
        let secondLaunch = try AliasStore(storageURL: storageURL)

        XCTAssertEqual(secondLaunch.resolve("School Folder"), "~/School")
    }
}
