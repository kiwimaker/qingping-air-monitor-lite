import SwiftUI

@main
struct QingpingAirMonitorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .task {
                    appState.onAppLaunch()
                }
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("Histórico", id: "history-window") {
            HistoryWindowView()
                .environmentObject(appState)
        }
        .defaultSize(width: 800, height: 550)
        .windowResizability(.contentMinSize)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "aqi.medium")

            if let data = appState.currentData, appState.menuBarDisplayOptions.hasAnyFieldEnabled {
                Text(data.displayText(options: appState.menuBarDisplayOptions))
                    .font(.system(.body, design: .rounded))
            }
        }
    }
}