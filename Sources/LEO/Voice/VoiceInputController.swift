import Foundation

@MainActor
final class VoiceInputController {
    private let input: AudioInput
    private let recognizer: any SpeechRecognizer
    private let voiceClient: VoiceClient
    private let volumeDucker = SystemAudioDucker()
    private var endpointDetector = SpeechEndpointDetector()
    private var frames: [AudioFrame] = []
    private var recognitionTask: Task<Void, Never>?
    private var originalVolume: Int?
    private var interruptFrames: [AudioFrame] = []
    private var listeningForInterrupt = false
    private var interruptRecognitionInFlight = false
    private var interruptListeningStartedAt: ContinuousClock.Instant?
    private var assistantPhase: VoiceSessionPhase = .idle

    // Give the output route a moment to settle before accepting microphone
    // energy as a barge-in. Without this, the first speaker frames can be
    // mistaken for the user's voice, especially when using built-in speakers.
    private let interruptStartupGrace: Duration = .milliseconds(300)

    private(set) var isCapturing = false
    private(set) var lastTranscript: String?
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioLevel: ((Double) -> Void)?
    var onVoicePhaseChanged: ((VoiceSessionPhase) -> Void)?

    init(
        input: AudioInput,
        recognizer: any SpeechRecognizer,
        voiceClient: VoiceClient
    ) {
        self.input = input
        self.recognizer = recognizer
        self.voiceClient = voiceClient
    }

    func setAssistantPhase(_ phase: VoiceSessionPhase) {
        assistantPhase = phase
        // Normal capture transitions to Thinking after the endpoint decision
        // and must retain hasSpeech. Only reset the interruption detector,
        // where the assistant's own cue audio must be ignored.
        if phase == .thinking, listeningForInterrupt {
            endpointDetector.reset()
            interruptFrames = []
        }
    }

    func beginPushToTalk() {
        guard !isCapturing else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        endpointDetector.reset()
        frames = []
        input.onFrame = { [weak self] frame in
            Task { @MainActor [weak self] in
                self?.receive(frame)
            }
        }

        do {
            try input.start()
            isCapturing = true
            onVoicePhaseChanged?(.listening)
            onAudioLevel?(0)
            originalVolume = volumeDucker.begin()
            leoVoiceLogger.info("voice_capture_started")
            NSLog("LEO voice capture started")
        } catch {
            leoVoiceLogger.error("voice_capture_start_failed")
            onError?("Could not start microphone: \(error.localizedDescription)")
        }
    }

    func toggleCapture() {
        if isCapturing {
            endPushToTalk()
        } else if listeningForInterrupt, !interruptRecognitionInFlight {
            Task { await voiceClient.stopSpeaking() }
            stopInterruptListening()
        } else {
            beginPushToTalk()
        }
    }

    func endPushToTalk() {
        // Audio callbacks hop onto the main actor. Give already-delivered
        // frames one turn to run before evaluating the endpoint detector;
        // otherwise a fast toggle can discard a valid recording as silence.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.finishCapture(reason: "hotkey released")
        }
    }

    private func receive(_ frame: AudioFrame) {
        if isCapturing {
            onAudioLevel?(AudioLevelMeter.level(for: frame))
            frames.append(frame)
            if endpointDetector.observe(frame) == .speechEnded {
                finishCapture(reason: "silence detected")
            }
        } else if listeningForInterrupt {
            // Spoken thinking/transition cues can arrive through the mic.
            // Ignore them while the assistant is preparing its response;
            // barge-in becomes active again once real TTS begins.
            guard assistantPhase != .thinking else { return }
            onAudioLevel?(AudioLevelMeter.level(for: frame))
            interruptFrames.append(frame)
            switch endpointDetector.observe(frame) {
            case .speechStarted:
                if let startedAt = interruptListeningStartedAt,
                   ContinuousClock().now - startedAt < interruptStartupGrace {
                    endpointDetector.reset()
                    interruptFrames = []
                    leoVoiceLogger.info("voice_barge_in_ignored_startup")
                    return
                }
                // Barge-in is driven by speech onset, not by recognizing a
                // complete "stop" command. This keeps the response from
                // talking over the user while the rest of their utterance is
                // still captured for the next turn.
                leoVoiceLogger.info("voice_barge_in_detected")
                onVoicePhaseChanged?(.listening)
                Task { await voiceClient.stopSpeaking() }
            case .speechEnded:
                finishInterruptCapture()
            case .silence, .speechContinued:
                break
            }
        }
    }

    private func finishCapture(reason: String) {
        guard isCapturing else { return }
        isCapturing = false
        onVoicePhaseChanged?(.thinking)
        onAudioLevel?(0)
        if let originalVolume {
            volumeDucker.restore(originalVolume)
            self.originalVolume = nil
        }
        let capturedFrames = frames
        frames = []
        guard endpointDetector.hasSpeech else {
            let maxLevel = capturedFrames.map(AudioLevelMeter.level(for:)).max() ?? 0
            leoVoiceLogger.info("voice_capture_discarded_no_speech frames=\(capturedFrames.count, privacy: .public) max_level=\(maxLevel, privacy: .public)")
            NSLog("LEO voice capture discarded: no speech")
            input.stop()
            return
        }

        leoVoiceLogger.info("voice_capture_ended frames=\(capturedFrames.count, privacy: .public)")
        NSLog("LEO voice capture ended (%{public}@), frames=%d", reason, capturedFrames.count)
        recognitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var transcript: String?
                for try await event in try await recognizer.recognize(frames: capturedFrames) {
                    if case .final(let value) = event { transcript = value }
                }
                guard let transcript, !transcript.isEmpty else {
                    stopInterruptListening()
                    return
                }
                leoVoiceLogger.info("voice_transcription_completed characters=\(transcript.count, privacy: .public)")
                lastTranscript = transcript
                onTranscript?(transcript)
                beginInterruptListening()
                _ = await voiceClient.submit(transcript: transcript)
                // An interruption may already be undergoing Parakeet
                // recognition. Do not tear down the shared mic stream until
                // that candidate has either become the next turn or failed.
                if !interruptRecognitionInFlight {
                    stopInterruptListening()
                }
            } catch {
                let detail = error.localizedDescription
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(1200)
                leoVoiceLogger.error("voice_transcription_failed detail=\(String(detail), privacy: .public)")
                onError?("Voice recognition failed: \(error.localizedDescription)")
                stopInterruptListening()
            }
        }
    }

    private func beginInterruptListening() {
        interruptFrames = []
        endpointDetector.reset()
        listeningForInterrupt = true
        interruptListeningStartedAt = ContinuousClock().now
        onVoicePhaseChanged?(.listening)
        onAudioLevel?(0)
        leoVoiceLogger.info("voice_interrupt_listening_started")
    }

    private func stopInterruptListening() {
        let wasListening = listeningForInterrupt
        listeningForInterrupt = false
        interruptRecognitionInFlight = false
        interruptFrames = []
        interruptListeningStartedAt = nil
        endpointDetector.reset()
        input.stop()
        if wasListening {
            onVoicePhaseChanged?(.idle)
            onAudioLevel?(0)
        }
        leoVoiceLogger.info("voice_interrupt_listening_stopped")
    }

    private func finishInterruptCapture() {
        guard listeningForInterrupt, endpointDetector.hasSpeech else { return }
        let capturedFrames = interruptFrames
        interruptFrames = []
        endpointDetector.reset()
        interruptRecognitionInFlight = true
        onVoicePhaseChanged?(.thinking)
        leoVoiceLogger.info("voice_interrupt_candidate frames=\(capturedFrames.count, privacy: .public)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var transcript: String?
                for try await event in try await recognizer.recognize(frames: capturedFrames) {
                    if case .final(let value) = event { transcript = value }
                }
                guard let transcript, !transcript.isEmpty else {
                    stopInterruptListening()
                    return
                }
                if Self.isStopCommand(transcript) {
                    leoVoiceLogger.info("voice_interrupt_confirmed")
                    await voiceClient.stopSpeaking()
                    stopInterruptListening()
                    return
                }

                // Speech that interrupted the assistant is a new voice turn,
                // just like ChatGPT Voice. Re-arm the listener before sending
                // it so the user can barge in on the next response too.
                leoVoiceLogger.info("voice_barge_in_transcript_received characters=\(transcript.count, privacy: .public)")
                interruptRecognitionInFlight = false
                beginInterruptListening()
                _ = await voiceClient.submit(transcript: transcript)
                stopInterruptListening()
            } catch {
                leoVoiceLogger.error("voice_interrupt_recognition_failed detail=\(error.localizedDescription, privacy: .public)")
                stopInterruptListening()
            }
        }
    }

    private static func isStopCommand(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return ["stop talking", "stop speaking", "be quiet", "quiet please", "stop"].contains(normalized)
    }
}
