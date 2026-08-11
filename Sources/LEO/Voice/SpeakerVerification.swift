import Foundation

struct SpeakerVerificationResult: Sendable, Equatable {
    let accepted: Bool
    let similarity: Float
}

struct SpeakerVerifier {
    var profile: SpeakerProfile?
    var threshold: Float

    init(profile: SpeakerProfile? = nil, threshold: Float = 0.8) {
        self.profile = profile
        self.threshold = threshold
    }

    func verify(_ embedding: [Float], pushToTalk: Bool = false) -> SpeakerVerificationResult {
        guard !pushToTalk, let profile else { return SpeakerVerificationResult(accepted: pushToTalk, similarity: 0) }
        let similarity = cosine(profile.embedding, embedding)
        return SpeakerVerificationResult(accepted: similarity >= threshold, similarity: similarity)
    }

    private func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let dot = zip(lhs, rhs).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let left = sqrt(lhs.reduce(Float(0)) { $0 + $1 * $1 })
        let right = sqrt(rhs.reduce(Float(0)) { $0 + $1 * $1 })
        return left > 0 && right > 0 ? dot / (left * right) : 0
    }
}
