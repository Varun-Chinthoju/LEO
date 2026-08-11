import XCTest
@testable import LEO

final class UserPreferenceStoreTests: XCTestCase {
    func testExplicitPreferencesAreBoundedAndAvailableToPrompt() async {
        let store = UserPreferenceStore(fileURL: nil)

        _ = await store.remember("I prefer concise answers")
        _ = await store.remember("I like British English")

        let context = await store.promptContext()
        XCTAssertEqual(context, "- I prefer concise answers\n- I like British English")
    }

    func testDuplicatePreferenceIsReplacedWithoutGrowingProfile() async {
        let store = UserPreferenceStore(fileURL: nil)

        _ = await store.remember("I prefer concise answers")
        _ = await store.remember("I prefer concise answers")

        let entries = await store.all()
        XCTAssertEqual(entries.count, 1)
    }
}
