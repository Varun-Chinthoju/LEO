import XCTest
@testable import LEO

final class AppToolsTests: XCTestCase {
    func testAppsOpenUsesProviderAndVerifiesSuccess() throws {
        let provider = MockAppProvider(app: InstalledApplication(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", url: URL(fileURLWithPath: "/Applications/Xcode.app")), opensSuccessfully: true)
        let tools = AppTools(provider: provider)
        XCTAssertEqual(try tools.open(name: "Xcode"), "Opened Xcode.")
        XCTAssertEqual(provider.openedNames, ["Xcode"])
    }

    func testMissingApplicationDoesNotClaimSuccess() {
        let tools = AppTools(provider: MockAppProvider(app: nil, opensSuccessfully: false))
        XCTAssertThrowsError(try tools.open(name: "No Such App")) { error in
            XCTAssertEqual(error as? AppToolError, .notInstalled("No Such App"))
        }
    }
}

private final class MockAppProvider: AppProvider, @unchecked Sendable {
    let app: InstalledApplication?
    let opensSuccessfully: Bool
    private(set) var openedNames: [String] = []

    init(app: InstalledApplication?, opensSuccessfully: Bool) {
        self.app = app
        self.opensSuccessfully = opensSuccessfully
    }

    func findApplication(named name: String) -> InstalledApplication? { app?.name == name ? app : nil }
    func open(_ application: InstalledApplication) -> Bool {
        openedNames.append(application.name)
        return opensSuccessfully
    }
}
