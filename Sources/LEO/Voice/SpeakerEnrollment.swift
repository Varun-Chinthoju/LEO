import Foundation

struct SpeakerProfile: Codable, Sendable, Equatable {
    let id: UUID
    let embedding: [Float]
    let enrolledAt: Date
}

struct SpeakerEnrollment {
    private(set) var profile: SpeakerProfile?

    mutating func enroll(embeddings: [[Float]]) throws -> SpeakerProfile {
        guard !embeddings.isEmpty, let width = embeddings.first?.count, width > 0,
              embeddings.allSatisfy({ $0.count == width }) else { throw EnrollmentError.invalidSamples }
        let average = (0..<width).map { index in embeddings.map { $0[index] }.reduce(0, +) / Float(embeddings.count) }
        let profile = SpeakerProfile(id: UUID(), embedding: average, enrolledAt: .now)
        self.profile = profile
        return profile
    }

    mutating func reset() { profile = nil }
    enum EnrollmentError: Error, Equatable { case invalidSamples }
}
