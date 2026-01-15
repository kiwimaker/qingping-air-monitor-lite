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
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "aqi.medium")

            if let data = appState.currentData, appState.menuBarDisplayOptions.hasAnyFieldEnabled {
                Text(buildDisplayText(data: data, options: appState.menuBarDisplayOptions))
                    .font(.system(.body, design: .rounded))
            }
        }
    }

    private func buildDisplayText(data: AirQualityData, options: MenuBarDisplayOptions) -> String {
        var parts: [String] = []

        if options.showTemperature, let temp = data.temperature {
            parts.append(String(format: "%.0f°", temp))
        }

        if options.showHumidity, let humidity = data.humidity {
            parts.append(String(format: "%.0f%%", humidity))
        }

        if options.showCO2, let co2 = data.co2 {
            parts.append("\(co2)ppm")
        }

        if options.showPM25, let pm25 = data.pm25 {
            parts.append("PM\(pm25)")
        }

        if options.showPM10, let pm10 = data.pm10 {
            parts.append("PM10:\(pm10)")
        }

        return parts.joined(separator: " ")
    }
}