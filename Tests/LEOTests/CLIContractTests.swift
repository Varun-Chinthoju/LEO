import XCTest

final class CLIContractTests: XCTestCase {
    func testCLIProductIsBuiltAsASeparateTarget() throws {
        let package = try String(contentsOfFile: "Package.swift", encoding: .utf8)
        XCTAssertTrue(package.contains("name: \"LEOCLI\""))
        XCTAssertTrue(package.contains("executable(name: \"leo\""))
    }

    func testCLIUsesCodableWireMessagesAndDedicatedInteractiveSession() throws {
        let client = try String(contentsOfFile: "Sources/LEOCLI/CLIClient.swift", encoding: .utf8)
        let wire = try String(contentsOfFile: "Sources/LEOCLI/CLIWire.swift", encoding: .utf8)
        let interactive = try String(contentsOfFile: "Sources/LEOCLI/InteractiveSession.swift", encoding: .utf8)

        XCTAssertTrue(wire.contains("struct CLIWireMessage: Codable"))
        XCTAssertTrue(client.contains("JSONEncoder().encode(message)"))
        XCTAssertFalse(client.contains("{\\\"version\\\":1"))
        XCTAssertTrue(client.contains("readExactly"))
        XCTAssertTrue(client.contains("1_048_576"))
        XCTAssertTrue(interactive.contains("private let sessionID = UUID()"))
    }

    func testCLIHasExplicitEOFAndInterruptHandling() throws {
        let main = try String(contentsOfFile: "Sources/LEOCLI/main.swift", encoding: .utf8)
        let client = try String(contentsOfFile: "Sources/LEOCLI/CLIClient.swift", encoding: .utf8)

        XCTAssertTrue(main.contains("signal(SIGINT, SIG_IGN)"))
        XCTAssertTrue(main.contains("cancellation.cancel()"))
        XCTAssertTrue(client.contains("serverClosedConnection"))
        XCTAssertTrue(client.contains("case .cancelled"))
    }
}
