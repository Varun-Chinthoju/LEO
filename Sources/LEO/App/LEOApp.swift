import SwiftUI

@main
struct LEOApp: App {
    @NSApplicationDelegateAdaptor(LEOAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("LEO", systemImage: "bolt.circle.fill") {
            MenuBarView()
                .environmentObject(appState)
        }
        .commands {
            CommandMenu("LEO") {
                Button("Open Command Palette…") {
                    NotificationCenter.default.post(name: .leoShowCommandPalette, object: nil)
                }
                .keyboardShortcut(" ", modifiers: [.option, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

    }
}
