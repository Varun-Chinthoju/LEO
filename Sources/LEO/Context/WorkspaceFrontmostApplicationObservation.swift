import AppKit
import Foundation

struct WorkspaceFrontmostApplicationObservation: FrontmostApplicationObservationSource {
    func updates() -> AsyncStream<FrontmostApplicationSnapshot?> {
        AsyncStream { continuation in
            let task = Task {
                for await notification in NotificationCenter.default.notifications(
                    named: NSWorkspace.didActivateApplicationNotification,
                    object: NSWorkspace.shared
                ) {
                    continuation.yield(Self.snapshot(from: notification))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func snapshot(from notification: Notification) -> FrontmostApplicationSnapshot? {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return nil
        }

        return FrontmostApplicationSnapshot(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier
        )
    }
}
