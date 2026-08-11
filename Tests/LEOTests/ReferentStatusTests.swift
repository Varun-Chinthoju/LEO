import XCTest
@testable import LEO

final class ReferentStatusTests: XCTestCase {
    func testRecentEntityResolvesAsItAndThatFile() {
        var store = ReferentStore()
        store.record(entityID: "file-1", displayName: "Report.pdf", source: .commandPalette)
        XCTAssertEqual(store.resolve("it")?.entityID, "file-1")
        XCTAssertEqual(store.resolve("that file")?.displayName, "Report.pdf")
    }

    func testReferentSalienceDecays() {
        let now = Date(timeIntervalSince1970: 10_000)
        var store = ReferentStore(halfLife: 10)
        store.record(entityID: "file-1", displayName: "Report.pdf", source: .cli, at: now)
        XCTAssertEqual(store.resolve("it", at: now.addingTimeInterval(10))?.salience ?? 0, 0.5, accuracy: 0.001)
    }

    func testRecordingAnEntityMergesAliasesAndPreservesEntityIdentity() {
        let now = Date(timeIntervalSince1970: 10_000)
        var store = ReferentStore()
        store.record(entityID: "file-1", displayName: "Report.pdf", source: .cli, labels: ["it", "that file"], at: now)
        store.record(entityID: "file-1", displayName: "Report.pdf", source: .commandPalette, labels: ["this", "it"], at: now.addingTimeInterval(5))

        XCTAssertEqual(store.candidates.count, 1)
        XCTAssertEqual(store.candidates[0].entityID, "file-1")
        XCTAssertEqual(Set(store.candidates[0].aliases), Set(["it", "that file", "this"]))
        XCTAssertEqual(store.resolve("this", at: now.addingTimeInterval(5))?.entityID, "file-1")
    }

    func testResolvingReferentUpdatesLastReferencedAtAndDecayUsesThatTimestamp() {
        let now = Date(timeIntervalSince1970: 10_000)
        var store = ReferentStore(halfLife: 10)
        store.record(entityID: "file-1", displayName: "Report.pdf", source: .cli, at: now)

        XCTAssertEqual(store.resolve("it", at: now.addingTimeInterval(10))?.salience ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(store.candidates[0].lastReferencedAt, now.addingTimeInterval(10))
        XCTAssertEqual(store.resolve("it", at: now.addingTimeInterval(20))?.salience ?? 0, 0.5, accuracy: 0.001)
    }

    func testResolutionRanksSalienceAndLeavesTiesAmbiguous() {
        let now = Date(timeIntervalSince1970: 10_000)
        var store = ReferentStore()
        store.record(entityID: "file-1", displayName: "First.pdf", source: .cli, labels: ["it"], at: now)
        store.record(entityID: "file-2", displayName: "Second.pdf", source: .cli, labels: ["it"], at: now)

        XCTAssertNil(store.resolve("it", at: now))
        store.record(entityID: "file-2", displayName: "Second.pdf", source: .cli, labels: ["it"], at: now.addingTimeInterval(1))
        XCTAssertEqual(store.resolve("it", at: now.addingTimeInterval(1))?.entityID, "file-2")
    }

    func testStatusPresenterDeduplicatesAdjacentStatuses() {
        var presenter = StatusPresenter()
        XCTAssertEqual(presenter.present(.thinking), "Thinking…")
        XCTAssertNil(presenter.present(.thinking))
        XCTAssertEqual(presenter.present(.reasoningSummary("Opening Xcode…")), "Opening Xcode…")
        XCTAssertNil(presenter.present(.reasoningSummary("Opening Xcode…")))
    }
}
