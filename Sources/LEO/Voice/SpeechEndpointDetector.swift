import Foundation

enum SpeechEndpointEvent: Equatable, Sendable {
    case silence
    case speechStarted
    case speechContinued
    case speechEnded
}

struct SpeechEndpointDetector: Sendable {
    let energyThreshold: Float
    let requiredSilence: TimeInterval
    private(set) var hasSpeech = false
    private(set) var accumulatedSilence: TimeInterval = 0

    init(energyThreshold: Float = 0.006, requiredSilence: TimeInterval = 1.25) {
        self.energyThreshold = energyThreshold
        self.requiredSilence = requiredSilence
    }

    mutating func observe(_ frame: AudioFrame) -> SpeechEndpointEvent {
        let duration = frameDuration(frame)
        let energy = rms(frame.samples)
        guard energy >= energyThreshold else {
            guard hasSpeech else { return .silence }
            accumulatedSilence += duration
            if accumulatedSilence >= requiredSilence {
                return .speechEnded
            }
            return .speechContinued
        }

        if !hasSpeech {
            hasSpeech = true
            accumulatedSilence = 0
            return .speechStarted
        }
        accumulatedSilence = 0
        return .speechContinued
    }

    mutating func reset() {
        hasSpeech = false
        accumulatedSilence = 0
    }

    private func frameDuration(_ frame: AudioFrame) -> TimeInterval {
        guard frame.sampleRate > 0, frame.channelCount > 0 else { return 0 }
        return Double(frame.samples.count) / frame.sampleRate / Double(frame.channelCount)
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(Float.zero) { $0 + ($1 * $1) } / Float(samples.count)
        return sqrt(meanSquare)
    }
}
