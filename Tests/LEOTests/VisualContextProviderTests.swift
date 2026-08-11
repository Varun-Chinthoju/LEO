import XCTest
@testable import LEO

final class VisualContextProviderTests: XCTestCase {
    func testDeniedPermissionReturnsRecoverableUnavailableWithoutCapturing() async {
        let permission = MockScreenRecordingPermission(status: .notGranted)
        let capture = MockTargetedVisualCapture()
        let provider = TargetedVisualContextProvider(permission: permission, capture: capture)
        let request = TargetedVisualContextRequest(
            reason: "The semantic query did not expose the visible status text."
        )

        let result = await provider.capture(request: request)

        XCTAssertEqual(result, .unavailable(.screenRecordingNotGranted(
            reason: request.reason,
            bounds: request.bounds,
            redactionPolicy: request.redactionPolicy,
            permission: .notGranted
        )))
        XCTAssertEqual(capture.captureCount, 0)
    }

    func testAuthorizedRequestIsCapturedOnceWithBoundedMetadata() async {
        let permission = MockScreenRecordingPermission(status: .authorized)
        let request = TargetedVisualContextRequest(
            reason: "The semantic query did not expose the visible status text.",
            bounds: .frontmostWindow(maxPixelDimension: 512),
            redactionPolicy: .pixelsBounded
        )
        let capture = MockTargetedVisualCapture(result: .available(
            TargetedVisualContextPayload(
                imageData: Data([1, 2, 3]),
                pixelWidth: 3,
                pixelHeight: 1,
                request: request
            )
        ))
        let provider = TargetedVisualContextProvider(permission: permission, capture: capture)

        let result = await provider.capture(request: request)

        guard case .available(let payload) = result else {
            return XCTFail("Expected an available targeted visual result")
        }
        XCTAssertEqual(payload.imageData, Data([1, 2, 3]))
        XCTAssertEqual(payload.pixelWidth, 3)
        XCTAssertEqual(payload.pixelHeight, 1)
        XCTAssertEqual(payload.request, request)
        XCTAssertEqual(payload.permission, .authorized)
        XCTAssertEqual(capture.captureCount, 1)
        XCTAssertEqual(capture.lastRequest, request)
    }

    func testEmptySemanticInsufficiencyReasonFailsClosed() async {
        let permission = MockScreenRecordingPermission(status: .authorized)
        let capture = MockTargetedVisualCapture()
        let provider = TargetedVisualContextProvider(permission: permission, capture: capture)

        let result = await provider.capture(request: TargetedVisualContextRequest(reason: "  "))

        XCTAssertEqual(result, .unavailable(.invalidRequest))
        XCTAssertEqual(capture.captureCount, 0)
    }
}

private final class MockScreenRecordingPermission: ScreenRecordingPermissionProviding, @unchecked Sendable {
    let currentStatus: ScreenRecordingPermissionStatus

    init(status: ScreenRecordingPermissionStatus) {
        self.currentStatus = status
    }

    func status() -> ScreenRecordingPermissionStatus { currentStatus }
}

private final class MockTargetedVisualCapture: TargetedVisualCapture, @unchecked Sendable {
    var result: TargetedVisualContextResult = .unavailable(.captureUnavailable)
    private(set) var captureCount = 0
    private(set) var lastRequest: TargetedVisualContextRequest?

    init(result: TargetedVisualContextResult? = nil) {
        if let result { self.result = result }
    }

    func capture(request: TargetedVisualContextRequest) async -> TargetedVisualContextResult {
        captureCount += 1
        lastRequest = request
        return result
    }
}
