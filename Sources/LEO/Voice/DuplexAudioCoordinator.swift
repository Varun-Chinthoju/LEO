import Foundation

actor DuplexAudioCoordinator {
    private let input: AudioInput
    private let synthesizer: any SpeechSynthesizer
    private(set) var capturedFrames = 0
    private(set) var isSpeaking = false
    private var playbackGeneration: UInt = 0

    init(input: AudioInput, synthesizer: any SpeechSynthesizer) {
        self.input = input
        self.synthesizer = synthesizer
    }

    func start() throws {
        input.onFrame = { [weak self] _ in
            Task { await self?.recordFrame() }
        }
        try input.start()
    }

    func speak(_ text: String) async {
        playbackGeneration &+= 1
        let generation = playbackGeneration
        isSpeaking = true
        defer {
            if playbackGeneration == generation {
                isSpeaking = false
            }
        }
        for await _ in await synthesizer.speak(text) {
            guard playbackGeneration == generation else { break }
            if Task.isCancelled { break }
        }
    }

    /// Stops the current response and leaves the microphone ready for a PTT turn.
    /// The generation guard prevents a previously started speech stream from
    /// changing state after the interruption.
    func interruptForPushToTalk() async throws {
        playbackGeneration &+= 1
        await synthesizer.stop()
        isSpeaking = false
        if !input.isRunning {
            try input.start()
        }
    }

    func stop() async {
        playbackGeneration &+= 1
        input.stop()
        await synthesizer.stop()
        isSpeaking = false
    }

    private func recordFrame() { capturedFrames += 1 }
}
