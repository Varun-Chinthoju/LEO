import Foundation

enum PolicyDecision: Sendable, Equatable {
    case allow
    case confirm
    case deny(String)
}

struct PolicyEngine: Sendable {
    func decide(effect: ToolEffect, source: RequestSource, confirmationGranted: Bool = false) -> PolicyDecision {
        switch effect {
        case .readOnly:
            return .allow
        case .reversibleWrite:
            return confirmationGranted ? .allow : .confirm
        case .consequential:
            return confirmationGranted ? .allow : .deny("This action requires trusted confirmation.")
        }
    }
}
