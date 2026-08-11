import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Shell") {
                LabeledContent("Status", value: appState.status.label)
                LabeledContent("Summary", value: appState.settingsSummaryText)
                LabeledContent("Launch", value: formattedLaunchDate)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var formattedLaunchDate: String {
        appState.launchedAt.formatted(date: .abbreviated, time: .standard)
    }
}
