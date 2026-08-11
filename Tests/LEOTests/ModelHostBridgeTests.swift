import Foundation
import XCTest
@testable import LEO

final class ModelHostBridgeTests: XCTestCase {
    func testLanguageModelBridgePreparesOnceAndAggregatesChunks() async throws {
        let backend = RecordingModelBackend(chunks: ["hel", "lo"])
        let host = ModelHost(backend: backend)

        let first = try await host.response(to: .text("first"))
        let second = try await host.response(to: .text("second"))

        XCTAssertEqual(first, "hello")
        XCTAssertEqual(second, "hello")
        XCTAssertEqual(backend.prepareCount, 1)
        XCTAssertEqual(backend.prompts, ["first", "second"])
        let snapshot = await host.resourceSnapshot()
        XCTAssertEqual(snapshot, ModelResourceSnapshot(isPrepared: true, activeRequestCount: 0))
    }

    func testConcurrentResponsesShareOneInFlightPreparation() async throws {
        let backend = RecordingModelBackend(chunks: ["ok"], blockingPreparation: true)
        let host = ModelHost(backend: backend)

        async let first = host.response(to: .text("first"))
        await backend.waitUntilPreparing()
        async let second = host.response(to: .text("second"))
        await Task.yield()
        backend.finishPreparation()

        _ = try await (first, second)
        XCTAssertEqual(backend.prepareCount, 1)
    }

    func testLanguageModelBridgePropagatesStreamErrors() async {
        let expected = BridgeTestError.failed
        let host = ModelHost(backend: RecordingModelBackend(error: expected))

        do {
            _ = try await host.response(to: .text("fail"))
            XCTFail("Expected the backend stream error")
        } catch {
            XCTAssertEqual(error as? BridgeTestError, expected)
        }
    }

    func testLanguageModelBridgePropagatesCancellation() async {
        let backend = RecordingModelBackend(blocking: true)
        let host = ModelHost(backend: backend)
        let responseTask = Task { try await host.response(to: .text("cancel")) }

        await backend.waitUntilStreaming()
        responseTask.cancel()

        do {
            _ = try await responseTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testResponseStreamYieldsChunksIncrementallyAndTracksActiveRequest() async throws {
        let backend = RecordingModelBackend(blocking: true)
        let host = ModelHost(backend: backend)
        let stream = try await host.responseStream(to: .text("stream"))
        var iterator = stream.makeAsyncIterator()

        XCTAssertEqual(backend.prepareCount, 1)
        backend.yield("hel")
        let firstChunk = try await iterator.next()
        XCTAssertEqual(firstChunk, "hel")
        let activeAfterFirstChunk = await host.resourceSnapshot().activeRequestCount
        XCTAssertEqual(activeAfterFirstChunk, 1)

        backend.yield("lo")
        let secondChunk = try await iterator.next()
        XCTAssertEqual(secondChunk, "lo")
        backend.finishStream()
        let endOfStream = try await iterator.next()
        XCTAssertNil(endOfStream)
        let activeAfterCompletion = await host.resourceSnapshot().activeRequestCount
        XCTAssertEqual(activeAfterCompletion, 0)
    }

    func testResponseStreamCancellationClearsActiveRequest() async throws {
        let backend = RecordingModelBackend(blocking: true)
        let host = ModelHost(backend: backend)
        let stream = try await host.responseStream(to: .text("cancel stream"))
        let consumerTask = Task {
            do {
                for try await _ in stream {}
            } catch is CancellationError {
                // Expected.
            } catch {
                // The test backend should only terminate through cancellation.
            }
        }

        await backend.waitUntilStreaming()
        consumerTask.cancel()
        await consumerTask.value

        while await host.resourceSnapshot().activeRequestCount != 0 {
            await Task.yield()
        }
    }

    func testUnloadCancelsActiveBridgeRequestAndClearsResources() async throws {
        let backend = RecordingModelBackend(blocking: true)
        let host = ModelHost(backend: backend)
        let responseTask = Task { try await host.response(to: .text("unload")) }

        await backend.waitUntilStreaming()
        await host.unload()

        let snapshot = await host.resourceSnapshot()
        XCTAssertFalse(snapshot.isPrepared)
        XCTAssertEqual(snapshot.activeRequestCount, 0)
        responseTask.cancel()
        _ = try? await responseTask.value
        XCTAssertEqual(backend.unloadCount, 1)
    }
}

private enum BridgeTestError: Error, Equatable {
    case failed
}

private final class RecordingModelBackend: ModelBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let chunks: [String]
    private let error: Error?
    private let blocking: Bool
    private let blockingPreparation: Bool
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var preparationContinuation: CheckedContinuation<Void, Never>?
    private var didStartPreparing = false
    private var didStartStreaming = false
    private(set) var prepareCount = 0
    private(set) var unloadCount = 0
    private(set) var prompts: [String] = []

    init(
        chunks: [String] = [],
        error: Error? = nil,
        blocking: Bool = false,
        blockingPreparation: Bool = false
    ) {
        self.chunks = chunks
        self.error = error
        self.blocking = blocking
        self.blockingPreparation = blockingPreparation
    }

    func prepare() async throws {
        lock.withLock {
            prepareCount += 1
            didStartPreparing = true
        }
        if blockingPreparation {
            await withCheckedContinuation { continuation in
                lock.withLock { preparationContinuation = continuation }
            }
        }
    }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock {
            prompts.append(request.prompt)
            didStartStreaming = true
        }

        return AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
            if let error {
                continuation.finish(throwing: error)
            } else if !blocking {
                chunks.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }
    }

    func unload() async {
        lock.withLock { unloadCount += 1 }
        lock.withLock { continuation?.finish() }
    }

    func waitUntilStreaming() async {
        while !lock.withLock({ didStartStreaming }) {
            await Task.yield()
        }
    }

    func waitUntilPreparing() async {
        while !lock.withLock({ didStartPreparing }) {
            await Task.yield()
        }
    }

    func finishPreparation() {
        lock.withLock {
            preparationContinuation?.resume()
            preparationContinuation = nil
        }
    }

    func yield(_ chunk: String) {
        lock.withLock { continuation?.yield(chunk) }
    }

    func finishStream() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }
}
