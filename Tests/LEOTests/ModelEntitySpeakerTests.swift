import XCTest
@testable import LEO

final class ModelEntitySpeakerTests: XCTestCase {
    func testModelHostPreparesStreamsAndUnloads() async throws {
        let host = ModelHost(backend: MockModelBackend(response: "hello"))
        try await host.prepare()
        var output: [String] = []
        for try await chunk in await host.stream(ModelRequest(prompt: "hi")) { output.append(chunk) }
        XCTAssertEqual(output, ["hello"])
        let prepared = await host.resourceSnapshot()
        XCTAssertTrue(prepared.isPrepared)
        await host.unload()
        let unloaded = await host.resourceSnapshot()
        XCTAssertFalse(unloaded.isPrepared)
    }

    func testEntityKeepsIdentityAndPathHistoryAfterMove() throws {
        var store = EntityStore()
        let oldURL = URL(fileURLWithPath: "/tmp/leo-before.txt")
        let entity = try store.register(oldURL)
        let updated = try store.update(entity.id, movedTo: URL(fileURLWithPath: "/tmp/leo-after.txt"))
        XCTAssertEqual(updated.id, entity.id)
        XCTAssertEqual(updated.previousURLs, [oldURL])
    }

    func testSpeakerVerifierAcceptsOwnerRejectsDifferentEmbeddingAndBypassesPTT() throws {
        var enrollment = SpeakerEnrollment()
        let profile = try enrollment.enroll(embeddings: [[1, 0], [1, 0]])
        let verifier = SpeakerVerifier(profile: profile, threshold: 0.9)
        XCTAssertTrue(verifier.verify([1, 0]).accepted)
        XCTAssertFalse(verifier.verify([0, 1]).accepted)
        XCTAssertTrue(verifier.verify([0, 1], pushToTalk: true).accepted)
    }
}
