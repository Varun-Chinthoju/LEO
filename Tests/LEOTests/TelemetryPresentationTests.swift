import XCTest
@testable import LEO

final class TelemetryPresentationTests: XCTestCase {
    func testResourceMonitorTracksActiveRequestsWithoutInventingMemory() async {
        let monitor = ResourceMonitor()
        await monitor.requestStarted()
        let snapshot = await monitor.snapshot()
        XCTAssertEqual(snapshot.activeRequests, 1)
        XCTAssertTrue(snapshot.residentMemoryBytes != nil || snapshot.residentMemoryUnavailableReason != nil)
        await monitor.requestFinished()
        let finished = await monitor.snapshot()
        XCTAssertEqual(finished.activeRequests, 0)
    }

    func testPresentationTrackerMarksTypedResponsesSilentAndVoicePending() {
        var tracker = PresentationTracker()
        let typed = tracker.record(text: "Done", source: .cli, speaks: false)
        let voice = tracker.record(text: "Done", source: .voice, speaks: true)
        XCTAssertEqual(typed.state, .silent)
        XCTAssertEqual(voice.state, .pending)
        tracker.update(voice.id, state: .spoken)
        XCTAssertEqual(tracker.utterances.last?.state, .spoken)
    }

    func testComputerControlEvidenceIsBoundedAndContainsNoPayloadContent() throws {
        let evidence = ComputerControlEvidence(
            caseID: String(repeating: "case-", count: 100),
            permission: PermissionEvidence(accessibility: .granted, inputMonitoring: .denied, screenRecording: .unavailable(reason: String(repeating: "r", count: 500))),
            accessibility: AXEvidence(elementCount: 99_999, payloadBytes: 100_000_001),
            timings: TimingEvidence(contextMilliseconds: 12.5, toolMilliseconds: 20.25),
            model: ModelEvidence(ttftMilliseconds: 30, tokensPerSecond: 40),
            runtime: RuntimeEvidence(state: .cold, build: String(repeating: "b", count: 200), hardware: String(repeating: "h", count: 200)),
            memory: ResourceEvidence(idleRSSBytes: 100, peakRSSBytes: 200),
            outcome: .failure(layer: .permission, reason: String(repeating: "x", count: 500))
        )

        XCTAssertLessThanOrEqual(evidence.caseID.count, DiagnosticsBounds.caseIDCharacters)
        XCTAssertEqual(evidence.accessibility.elementCount, DiagnosticsBounds.maxCount)
        XCTAssertEqual(evidence.accessibility.payloadBytes, DiagnosticsBounds.maxBytes)
        XCTAssertEqual(evidence.permission.screenRecording.reason?.count, DiagnosticsBounds.reasonCharacters)
        XCTAssertEqual(evidence.runtime.build.count, DiagnosticsBounds.identityCharacters)
        XCTAssertEqual(evidence.outcome.failureReason?.count, DiagnosticsBounds.reasonCharacters)

        let data = try JSONEncoder().encode(evidence)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("secure"))
        XCTAssertFalse(json.contains("screenshot"))
        XCTAssertFalse(json.contains("chain"))
    }

    func testEvidenceStoreKeepsOnlyTheNewestBoundedRecords() async {
        let store = LocalEvidenceStore(capacity: 2)
        for index in 0..<3 {
            await store.append(ComputerControlEvidence.fixture(caseID: "case-\(index)"))
        }

        let records = await store.records()
        XCTAssertEqual(records.map(\.caseID), ["case-1", "case-2"])
    }

    func testResourceSnapshotReportsUnavailableRSSWithReason() async {
        let monitor = ResourceMonitor(residentMemoryProvider: { nil })
        let snapshot = await monitor.snapshot()
        XCTAssertNil(snapshot.residentMemoryBytes)
        XCTAssertEqual(snapshot.residentMemoryUnavailableReason, "resident memory measurement unavailable")
    }
}
