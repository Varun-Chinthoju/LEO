import Foundation

struct AudioFrame: Sendable, Equatable {
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int
    let timestamp: TimeInterval

    init(samples: [Float], sampleRate: Double = 16_000, channelCount: Int = 1, timestamp: TimeInterval = 0) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.timestamp = timestamp
    }
}
