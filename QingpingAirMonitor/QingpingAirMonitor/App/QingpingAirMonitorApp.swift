import SwiftUI

@main
struct QingpingAirMonitorApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        // MenuBarExtra es la forma oficial de SwiftUI para crear apps de barra de menú
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label("Air", systemImage: "cloud.fill")
        }
        .menuBarExtraStyle(.window)
        
        // Ventana de ajustes
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}