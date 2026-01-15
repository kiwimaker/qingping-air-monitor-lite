import SwiftUI

@main
struct QingpingAirMonitorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    appState.onAppLaunch()
                }
        } label: {
            Image(systemName: "aqi.medium")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}