import XCTest
@testable import LEO

final class PolicyEngineTests: XCTestCase {
    func testReadOnlyAllowsEveryClient() {
        let policy = PolicyEngine()
        XCTAssertEqual(policy.decide(effect: .readOnly, source: .cli), .allow)
        XCTAssertEqual(policy.decide(effect: .readOnly, source: .voice), .allow)
    }

    func testWritesRequireTrustedConfirmation() {
        let policy = PolicyEngine()
        XCTAssertEqual(policy.decide(effect: .reversibleWrite, source: .cli), .confirm)
        XCTAssertEqual(policy.decide(effect: .reversibleWrite, source: .commandPalette, confirmationGranted: true), .allow)
        XCTAssertEqual(policy.decide(effect: .consequential, source: .voice), .deny("This action requires trusted confirmation."))
    }

    func testBrokerCannotExecuteProtectedToolWithoutPolicyApproval() async {
        let broker = ToolBroker(definitions: [ToolDefinition(name: "files.write", effect: .reversibleWrite, idempotency: .nonIdempotent) { _ in
            ToolResult.success("changed")
        }])
        do {
            _ = try await broker.execute(ToolProposal(name: "files.write", arguments: [:]), source: .cli)
            XCTFail("policy should stop execution")
        } catch let error as ToolBrokerError {
            XCTAssertEqual(error, .confirmationRequired)
        } catch { XCTFail("unexpected error: \(error)") }
    }
}
