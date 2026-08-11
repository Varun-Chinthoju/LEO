import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.menuStatusText)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            Button("Open Command Palette…") {
                NotificationCenter.default.post(name: .leoShowCommandPalette, object: nil)
            }

            SettingsLink {
                Text("Settings…")
            }

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Text("Quit LEO")
            }
        }
        .padding(12)
        .frame(minWidth: 220, alignment: .leading)
    }
}
