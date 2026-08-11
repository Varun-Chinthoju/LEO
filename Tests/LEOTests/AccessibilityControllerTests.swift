import XCTest
@testable import LEO

@MainActor
final class AccessibilityControllerTests: XCTestCase {
    func testMockControllerReturnsConfiguredSnapshot() async throws {
        let controller = MockAccessibilityController()

        let snapshot = try await controller.snapshotFrontmostApplication()

        XCTAssertEqual(snapshot.applicationName, "MockApp")
    }

    func testMockControllerReturnsPermissionDeniedCleanly() async {
        let controller = MockAccessibilityController()
        await controller.setDenied(true)

        do {
            _ = try await controller.snapshotFrontmostApplication()
            XCTFail("Expected permission denied error")
        } catch let error as AccessibilityControllerError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

