import Foundation

enum VoiceSessionPhase: Equatable, Sendable {
    case idle
    case listening
    case thinking
    case responding
}
