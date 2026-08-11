import XCTest
@testable import LEO

@MainActor
final class AppStateTests: XCTestCase {
    func testInitialStateStartsAsStarting() {
        let appState = AppState(launchedAt: .distantPast)

        XCTAssertEqual(appState.status, .starting)
        XCTAssertEqual(appState.menuStatusText, "Status: Starting")
        XCTAssertEqual(appState.settingsSummaryText, "LEO is starting")
    }

    func testMarkReadyUpdatesSharedStatusText() {
        let appState = AppState(launchedAt: .distantPast)

        appState.markReady()

        XCTAssertEqual(appState.status, .ready)
        XCTAssertEqual(appState.menuStatusText, "Status: Ready")
        XCTAssertEqual(appState.settingsSummaryText, "LEO is ready")
    }

    func testCustomStatusPassesThroughToBothSurfaces() {
        let appState = AppState(launchedAt: .distantPast)

        appState.setStatus(.custom("Indexing"))

        XCTAssertEqual(appState.status, .custom("Indexing"))
        XCTAssertEqual(appState.menuStatusText, "Status: Indexing")
        XCTAssertEqual(appState.settingsSummaryText, "LEO is indexing")
    }
}
