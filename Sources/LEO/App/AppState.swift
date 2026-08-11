import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var status: AppStatus = .starting
    let launchedAt: Date

    init(launchedAt: Date = .now) {
        self.launchedAt = launchedAt
    }

    var menuStatusText: String {
        "Status: \(status.label)"
    }

    var settingsSummaryText: String {
        "LEO is \(status.label.lowercased())"
    }

    func setStatus(_ status: AppStatus) {
        self.status = status
    }

    func markReady() {
        status = .ready
    }
}

enum AppStatus: Equatable {
    case starting
    case ready
    case custom(String)

    var label: String {
        switch self {
        case .starting:
            return "Starting"
        case .ready:
            return "Ready"
        case .custom(let value):
            return value
        }
    }
}
