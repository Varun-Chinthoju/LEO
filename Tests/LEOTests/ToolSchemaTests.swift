import XCTest
@testable import LEO

final class ToolSchemaTests: XCTestCase {
    func testValidAppsOpenArgumentsRemainAccepted() throws {
        let definition = AppTools(provider: TestAppProvider()).definition()

        let result = try definition.execute(["name": "Visual Studio Code"])

        XCTAssertEqual(result.value, "Opened Visual Studio Code.")
    }

    func testRejectsMalformedArgumentKey() {
        let definition = testDefinition()

        XCTAssertThrowsError(try definition.execute(["bad key": "Safari"])) { error in
            XCTAssertEqual(error as? ToolArgumentValidationError, .invalidKey("bad key"))
        }
    }

    func testRejectsEmptyArgumentValues() {
        let definition = testDefinition()

        XCTAssertThrowsError(try definition.execute(["name": "   "])) { error in
            XCTAssertEqual(error as? ToolArgumentValidationError, .emptyValue("name"))
        }
    }

    func testRejectsControlCharactersInKeysAndValues() {
        let definition = testDefinition()

        XCTAssertThrowsError(try definition.execute(["name\n": "Safari"])) { error in
            XCTAssertEqual(error as? ToolArgumentValidationError, .controlCharacter("name\n"))
        }

        XCTAssertThrowsError(try definition.execute(["name": "Safari\u{0000}" ])) { error in
            XCTAssertEqual(error as? ToolArgumentValidationError, .controlCharacter("name"))
        }
    }

    func testRejectsOversizedValueAndArgumentCollection() {
        let definition = testDefinition()

        XCTAssertThrowsError(try definition.execute(["name": String(repeating: "a", count: 257)])) { error in
            XCTAssertEqual(error as? ToolArgumentValidationError, .valueTooLong("name"))
        }

        let tooManyArguments = Dictionary(uniqueKeysWithValues: (0..<33).map { ("key\($0)", "value") })
        XCTAssertThrowsError(try definition.execute(tooManyArguments)) { error in
            XCTAssertEqual(error as? ToolArgumentValidationError, .tooManyArguments)
        }
    }

    func testRejectsOversizedTotalArgumentPayload() {
        let definition = testDefinition()
        let arguments = ["first": String(repeating: "a", count: 256), "second": String(repeating: "b", count: 256)]

        XCTAssertThrowsError(try definition.execute(arguments)) { error in
            XCTAssertEqual(error as? ToolArgumentValidationError, .payloadTooLarge)
        }
    }

    private func testDefinition() -> ToolDefinition {
        ToolDefinition(name: "test.echo", effect: .readOnly, idempotency: .idempotent) { _ in
            ToolResult.success("executed")
        }
    }
}

private struct TestAppProvider: AppProvider {
    func findApplication(named name: String) -> InstalledApplication? {
        InstalledApplication(name: name, bundleIdentifier: "com.example.\(name)", url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func open(_ application: InstalledApplication) -> Bool { true }
}
