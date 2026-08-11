import Foundation

struct PresentationPreference: Codable, Sendable, Equatable {
    var showText: Bool
    var speakResponse: Bool
    var machineReadable: Bool

    static let voice = Self(showText: true, speakResponse: true, machineReadable: false)
    static let commandPalette = Self(showText: true, speakResponse: false, machineReadable: false)
    static let cli = Self(showText: true, speakResponse: false, machineReadable: true)

    static func defaultPresentation(for source: RequestSource) -> Self {
        switch source {
        case .voice:
            return .voice
        case .commandPalette:
            return .commandPalette
        case .cli:
            return .cli
        }
    }
}
