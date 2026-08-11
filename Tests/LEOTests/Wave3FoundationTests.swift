import XCTest
@testable import LEO

final class Wave3FoundationTests: XCTestCase {
    func testFinderSelectionProducesStablePrivacyMinimalEntities() async throws {
        let url = URL(fileURLWithPath: "/tmp/Example.pdf")
        let provider = FinderContextProvider(source: MockFinderSelectionSource(urls: [url]))
        let first = try await provider.currentSelection()
        let second = try await provider.currentSelection()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first?.id, "file:/tmp/Example.pdf")
        XCTAssertEqual(first.first?.fileName, "Example.pdf")
    }

    func testAudioInputCanStartStopAndForwardFrames() throws {
        let backend = MockAudioCaptureBackend()
        let input = AudioInput(backend: backend)
        var received: AudioFrame?
        input.onFrame = { received = $0 }
        try input.start()
        backend.emit(AudioFrame(samples: [0.1, -0.1]))
        XCTAssertEqual(received?.samples, [0.1, -0.1])
        input.stop()
        XCTAssertFalse(input.isRunning)
    }

    func testMacosUseUnavailableAdapterFailsCleanly() async {
        let controller = MacosUseAccessibilityController()
        do {
            _ = try await controller.snapshotFrontmostApplication()
            XCTFail("Expected unavailable adapter")
        } catch let error as AccessibilityControllerError {
            XCTAssertEqual(error, .unsupported)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
