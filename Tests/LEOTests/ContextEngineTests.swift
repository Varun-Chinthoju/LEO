import XCTest
@testable import LEO

struct TestFrontmostApplicationObservation: FrontmostApplicationObservationSource {
    let stream: AsyncStream<FrontmostApplicationSnapshot?>

    func updates() -> AsyncStream<FrontmostApplicationSnapshot?> {
        stream
    }
}

@MainActor
final class ContextEngineTests: XCTestCase {
    func testFrontmostApplicationUpdatesReplaceLiveStateWithoutPolling() async throws {
        var continuation: AsyncStream<FrontmostApplicationSnapshot?>.Continuation?
        let stream = AsyncStream<FrontmostApplicationSnapshot?> { continuation = $0 }
        let engine = ContextEngine(
            liveState: LiveState(),
            observationSource: TestFrontmostApplicationObservation(stream: stream)
        )

        await engine.startObservingFrontmostApplication()
        continuation?.yield(
            FrontmostApplicationSnapshot(
                bundleIdentifier: "com.example.Editor",
                localizedName: "Editor",
                processIdentifier: 42
            )
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let state = await engine.liveState
        XCTAssertEqual(state.frontmostApplication?.bundleIdentifier, "com.example.Editor")
        XCTAssertEqual(state.frontmostApplication?.localizedName, "Editor")
        XCTAssertEqual(state.frontmostApplication?.processIdentifier, 42)
    }

    func testManualUpdateSetsFrontmostApplication() async {
        let engine = ContextEngine(
            liveState: LiveState(),
            observationSource: TestFrontmostApplicationObservation(stream: AsyncStream { _ in })
        )

        await engine.updateFrontmostApplication(
            FrontmostApplicationSnapshot(
                bundleIdentifier: "com.example.Mail",
                localizedName: "Mail",
                processIdentifier: 7
            )
        )

        let state = await engine.liveState
        XCTAssertEqual(state.frontmostApplication?.bundleIdentifier, "com.example.Mail")
    }
}

