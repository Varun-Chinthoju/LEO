import XCTest
@testable import LEO

final class BrowserContextProviderTests: XCTestCase {
    func testSupportedBrowserMetadataIsReturnedWithoutTransformation() async {
        let context = BrowserContext(
            application: "Safari",
            title: "LEO spec",
            url: URL(string: "https://example.com/spec?q=private")
        )
        let provider = BrowserContextProvider(source: MockBrowserContextSource(result: context))

        let result = await provider.currentContext()

        XCTAssertEqual(result, .available(context))
    }

    func testUnsupportedBrowserIsUnavailableWithoutCallingMetadataReader() async {
        let source = MockBrowserContextSource(result: nil)
        let provider = BrowserContextProvider(source: source)

        let result = await provider.currentContext()

        XCTAssertEqual(result, .unavailable(.unsupportedBrowser))
        XCTAssertEqual(source.callCount, 1)
    }

    func testAdapterFailureIsUnavailableAndDoesNotLeakErrorDetails() async {
        let provider = BrowserContextProvider(source: MockBrowserContextSource(error: TestError.denied))

        let result = await provider.currentContext()

        XCTAssertEqual(result, .unavailable(.metadataUnavailable))
    }

    func testSystemSourceAllowListsBrowsersAndUsesApplicationNameFallback() async throws {
        let source = MacOSBrowserContextSource(
            workspace: MockWorkspace(frontmostApplication: WorkspaceApplication(
                bundleIdentifier: "com.brave.Browser",
                localizedName: nil
            )),
            metadataReader: MockBrowserMetadataReader(metadata: BrowserMetadata(
                title: "Example",
                url: URL(string: "https://example.com")
            ))
        )

        guard let context = try await source.currentContext() else {
            return XCTFail("Expected supported browser context")
        }

        XCTAssertEqual(context.application, "Brave Browser")
        XCTAssertEqual(context.title, "Example")
        XCTAssertEqual(context.url?.absoluteString, "https://example.com")
    }

    func testSystemSourceDoesNotReadMetadataForUnsupportedApplication() async throws {
        let reader = MockBrowserMetadataReader(metadata: BrowserMetadata(title: "unexpected", url: nil))
        let source = MacOSBrowserContextSource(
            workspace: MockWorkspace(frontmostApplication: WorkspaceApplication(
                bundleIdentifier: "com.example.Editor",
                localizedName: "Editor"
            )),
            metadataReader: reader
        )

        let context = try await source.currentContext()
        XCTAssertNil(context)
        XCTAssertEqual(reader.callCount, 0)
    }
}

private struct MockBrowserContextSource: BrowserContextSource {
    let result: BrowserContext?
    let error: Error?
    let callCountBox: CallCountBox

    init(result: BrowserContext? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
        self.callCountBox = CallCountBox()
    }

    var callCount: Int { callCountBox.value }

    func currentContext() async throws -> BrowserContext? {
        callCountBox.value += 1
        if let error { throw error }
        return result
    }
}

private final class CallCountBox: @unchecked Sendable {
    var value = 0
}

private struct MockWorkspace: WorkspaceProviding {
    let frontmostApplication: WorkspaceApplication?
}

private struct MockBrowserMetadataReader: BrowserMetadataReading {
    let metadata: BrowserMetadata
    let callCountBox = CallCountBox()

    var callCount: Int { callCountBox.value }

    func readMetadata(for browser: SupportedBrowser) async throws -> BrowserMetadata {
        callCountBox.value += 1
        return metadata
    }
}

private enum TestError: Error {
    case denied
}
