import ApplicationServices
import CoreGraphics
import EventKit

enum PermissionAccess {
    /// Ask macOS to register LEO as an assistive app for global hotkeys.
    /// The system owns the prompt and the user must approve it explicitly.
    static func requestHotkeyPermissions() {
        _ = AXIsProcessTrustedWithOptions([
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary)

        // NSEvent's global monitor also requires listen-event (Input
        // Monitoring) access when receiving key events from other apps.
        _ = CGRequestListenEventAccess()
    }

    /// Requests the permissions needed by the currently shipped integrations.
    /// Each request is OS-owned and approval remains entirely user-controlled.
    /// This does not execute a calendar action or a computer-use action.
    static func requestIntegrationPermissions() async {
        let calendarStore = EKEventStore()
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await calendarStore.requestFullAccessToEvents()
        }

        // Screen Recording has no separate preflight prompt API. The request
        // opens the system approval flow; capture still remains opt-in later.
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    /// Read-only Screen Recording check. This never presents a prompt.
    static func screenRecordingStatus() -> ScreenRecordingPermissionStatus {
        CGPreflightScreenCaptureAccess() ? .authorized : .notGranted
    }

    /// Call only from an explicit user action that asks to enable visual
    /// context. This is intentionally not called during app launch.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
