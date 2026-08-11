import Foundation

protocol SpeechSynthesizer: Actor {
    func speak(_ text: String) -> AsyncStream<AudioFrame>
    func stop()
}

actor MockSpeechSynthesizer: SpeechSynthesizer {
    private(set) var spoken: [String] = []
    private(set) var stopCount = 0
    private var stopped = false

    func speak(_ text: String) -> AsyncStream<AudioFrame> {
        spoken.append(text)
        stopped = false
        return AsyncStream { continuation in
            guard !stopped else { continuation.finish(); return }
            continuation.yield(AudioFrame(samples: [0], sampleRate: 16_000, channelCount: 1, timestamp: 0))
            continuation.finish()
        }
    }

    func stop() {
        stopCount += 1
        stopped = true
    }
    func spokenTexts() -> [String] { spoken }
}
