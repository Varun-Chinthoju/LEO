import XCTest
@testable import LEO

final class ModelRuntimeStatusTests: XCTestCase {
    func testCurrentStatusIsExplicitlyNotProductionReady() {
        XCTAssertEqual(ModelRuntimeStatus.current.availability, "available")
        XCTAssertTrue(ModelRuntimeStatus.current.isProductionReady)
        XCTAssertEqual(ModelRuntimeStatus.current.reason, nil)
    }

    func testUnavailableStatusRequiresReasonAndRoundTrips() throws {
        let status = ModelRuntimeStatus.unavailable(reason: "backend and weights are not configured")
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(ModelRuntimeStatus.self, from: data)

        XCTAssertEqual(decoded, status)
        XCTAssertEqual(decoded.availability, "unavailable")
        XCTAssertFalse(decoded.isProductionReady)
    }

    func testAvailableStatusIsTheOnlyProductionReadyState() {
        XCTAssertTrue(ModelRuntimeStatus.available(backend: "example").isProductionReady)
        XCTAssertFalse(ModelRuntimeStatus.fixtureOnly(reason: "fixture").isProductionReady)
        XCTAssertFalse(ModelRuntimeStatus.unavailable(reason: "missing").isProductionReady)
    }
}
