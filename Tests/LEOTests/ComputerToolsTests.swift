import XCTest
@testable import LEO

final class ComputerToolsTests: XCTestCase {
    func testPermissionDenialIsReturnedWithoutPerforming() async {
        let controller = MockAccessibilityController()
        await controller.setDenied(true)
        let broker = ToolBroker(definitions: ComputerTools(controller: controller).definitions())

        do {
            _ = try await broker.execute(ToolProposal(name: "computer.snapshot", arguments: [:]))
            XCTFail("permission should be denied")
        } catch let error as ToolBrokerError {
            guard case .executionFailed(let message) = error else {
                return XCTFail("unexpected broker error: \(error)")
            }
            XCTAssertTrue(message.contains("Accessibility permission"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSearchOutputIsSemanticAndBounded() async throws {
        let controller = MockAccessibilityController()
        await controller.setFindResult([AXElementReference(identifier: "0", role: "button", label: String(repeating: "a", count: 200), actions: ["press"])])
        let broker = ToolBroker(definitions: ComputerTools(controller: controller).definitions())

        let result = try await broker.execute(ToolProposal(name: "computer.search", arguments: ["query": "save"]))

        XCTAssertLessThanOrEqual(result.value.utf8.count, 8_192)
        XCTAssertTrue(result.value.contains("button"))
        XCTAssertTrue(result.value.contains("press"))
        XCTAssertFalse(result.value.contains(String(repeating: "a", count: 200)))
    }

    func testPerformRejectsAmbiguousQueryAndDisallowedAction() async {
        let controller = MockAccessibilityController()
        await controller.setFindResult([
            AXElementReference(identifier: "0"),
            AXElementReference(identifier: "1")
        ])
        let broker = ToolBroker(definitions: ComputerTools(controller: controller).definitions())

        do {
            _ = try await broker.execute(ToolProposal(name: "computer.perform", arguments: ["query": "Save", "action": "press"]), confirmationGranted: true)
            XCTFail("ambiguous query should be rejected")
        } catch let error as ToolBrokerError {
            XCTAssertTrue(String(describing: error).contains("more than one"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        do {
            _ = try await broker.execute(ToolProposal(name: "computer.perform", arguments: ["query": "Save", "action": "delete"]), confirmationGranted: true)
            XCTFail("disallowed action should be rejected")
        } catch let error as ToolBrokerError {
            XCTAssertTrue(String(describing: error).contains("not allowed"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPerformRequiresPolicyConfirmation() async {
        let controller = MockAccessibilityController()
        await controller.setFindResult([AXElementReference(identifier: "0")])
        let broker = ToolBroker(definitions: ComputerTools(controller: controller).definitions())

        do {
            _ = try await broker.execute(ToolProposal(name: "computer.perform", arguments: ["query": "Save", "action": "press"]))
            XCTFail("perform should require confirmation")
        } catch let error as ToolBrokerError {
            XCTAssertEqual(error, .confirmationRequired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        let performCount = await controller.performCount
        XCTAssertEqual(performCount, 0)
    }
}
