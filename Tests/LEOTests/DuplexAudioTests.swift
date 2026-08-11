import XCTest
@testable import LEO

final class DuplexAudioTests: XCTestCase {
    func testMicrophoneRemainsActiveWhileTTSStreams() async throws {
        let backend = MockAudioCaptureBackend()
        let input = AudioInput(backend: backend)
        let synthesizer = MockSpeechSynthesizer()
        let coordinator = DuplexAudioCoordinator(input: input, synthesizer: synthesizer)
        try await coordinator.start()
        backend.emit(AudioFrame(samples: [0.1], sampleRate: 16_000, channelCount: 1, timestamp: 0))
        await coordinator.speak("hello")
        XCTAssertTrue(input.isRunning)
        let capturedFrames = await coordinator.capturedFrames
        XCTAssertEqual(capturedFrames, 1)
        await coordinator.stop()
        XCTAssertFalse(input.isRunning)
    }

    func testPushToTalkInterruptStopsSpeechAndEnsuresListening() async throws {
        let backend = MockAudioCaptureBackend()
        let input = AudioInput(backend: backend)
        let synthesizer = BlockingSpeechSynthesizer()
        let coordinator = DuplexAudioCoordinator(input: input, synthesizer: synthesizer)

        let speech = Task { await coordinator.speak("long response") }
        try await Task.sleep(for: .milliseconds(10))
        try await coordinator.interruptForPushToTalk()
        await speech.value

        let isSpeaking = await coordinator.isSpeaking
        let stopCount = await synthesizer.stopCount
        XCTAssertFalse(isSpeaking)
        XCTAssertTrue(input.isRunning)
        XCTAssertEqual(stopCount, 1)

        await coordinator.stop()
    }
}

private actor BlockingSpeechSynthesizer: SpeechSynthesizer {
    private var continuation: AsyncStream<AudioFrame>.Continuation?
    private(set) var stopCount = 0

    func speak(_ text: String) -> AsyncStream<AudioFrame> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(AudioFrame(samples: [0]))
        }
    }

    func stop() {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }
}
