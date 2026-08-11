import XCTest
@testable import LEO

final class SpeechTextSanitizerTests: XCTestCase {
    func testRemovesMarkdownFormattingButPreservesReadableText() {
        let result = SpeechTextSanitizer.plainText(from: "**Open** *Mail* and [watch this](https://example.com).")

        XCTAssertEqual(result, "Open Mail and watch this.")
    }

    func testRemovesCodeAndBulletFormatting() {
        let result = SpeechTextSanitizer.plainText(from: "# Steps\n- Open Mail\n```swift\nlet x = 1\n```")

        XCTAssertEqual(result, "Steps\nOpen Mail")
    }
}
