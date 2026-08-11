import Foundation

struct AudioLevelMeter: Sendable {
    static func level(for frame: AudioFrame) -> Double {
        guard !frame.samples.isEmpty else { return 0 }

        let meanSquare = frame.samples.reduce(into: 0.0) { result, sample in
            let value = Double(sample)
            result += value * value
        } / Double(frame.samples.count)
        let rms = sqrt(meanSquare)

        // Speech is usually much quieter than a full-scale sample. This gain
        // keeps the Siri-style waveform visibly responsive to normal speech
        // while the clamp prevents loud input from exceeding the UI range.
        return min(max(rms * 12, 0), 1)
    }
}
