import Foundation

actor VoiceClient {
    private let orchestrator: InteractionOrchestrator
    private let synthesizer: any SpeechSynthesizer
    private let cuePlayer = VoiceCuePlayer()
    private let onPhase: (@MainActor @Sendable (VoiceSessionPhase) -> Void)?
    private var stopRequested = false

    init(
        orchestrator: InteractionOrchestrator,
        synthesizer: any SpeechSynthesizer,
        onPhase: (@MainActor @Sendable (VoiceSessionPhase) -> Void)? = nil
    ) {
        self.orchestrator = orchestrator
        self.synthesizer = synthesizer
        self.onPhase = onPhase
    }

    func submit(transcript: String) async -> [AssistantEvent] {
        stopRequested = false
        publish(.thinking)
        leoVoiceLogger.info("voice_model_request_started characters=\(transcript.count, privacy: .public)")
        let request = AssistantRequest(input: .text(transcript), source: .voice)
        var events: [AssistantEvent] = []
        let thinkingCueTask = Task { [cuePlayer] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await cuePlayer.play(.thinking)
        }
        for await event in await orchestrator.submit(request) {
            events.append(event)
            switch event {
            case .accepted:
                leoVoiceLogger.info("voice_model_request_accepted")
            case .failed(let failure):
                leoVoiceLogger.error("voice_model_request_failed detail=\(failure.message, privacy: .public)")
            default:
                break
            }
            if case .responseCompleted(let response) = event, request.presentation.speakResponse {
                thinkingCueTask.cancel()
                cuePlayer.stop()
                leoVoiceLogger.info("voice_response_completed characters=\(response.count, privacy: .public)")
                if stopRequested {
                    stopRequested = false
                    leoVoiceLogger.info("voice_response_suppressed_after_interrupt")
                    publish(.listening)
                    continue
                }
                // Start the transition cue and TTS generation together. The
                // cue gives immediate feedback while Kokoro initializes,
                // instead of adding its process-start cost to the handoff.
                let answeringCueTask = Task { [cuePlayer] in
                    await cuePlayer.play(.answering)
                }
                publish(.responding)
                // Consume the stream so synthesizers can report completion and
                // remain compatible with streaming implementations.
                let speechText = SpeechTextSanitizer.plainText(from: response)
                if !speechText.isEmpty {
                    for await _ in await synthesizer.speak(speechText) {}
                }
                answeringCueTask.cancel()
                publish(.listening)
            }
        }
        // Failed, cancelled, or otherwise non-speaking streams must not leave
        // the voice surface permanently displaying Thinking.
        publish(.listening)
        return events
    }

    func stopSpeaking() async {
        stopRequested = true
        cuePlayer.stop()
        await synthesizer.stop()
    }

    private func publish(_ phase: VoiceSessionPhase) {
        guard let onPhase else { return }
        Task { @MainActor in onPhase(phase) }
    }
}
