import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            if appState.isConfiguredSync {
                if let data = appState.currentData {
                    sensorsSection(data: data)
                } else if appState.isLoading {
                    loadingSection
                } else if let error = appState.lastError {
                    errorSection(error: error)
                } else {
                    waitingSection
                }
            } else {
                configurationPrompt
            }

            Divider()

            footerSection
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "aqi.medium")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Qingping Air Monitor")
                    .font(.headline)
                if let device = appState.selectedDevice {
                    Text(sanitizedDeviceName(device))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(appState.connectionStatus.color)
                .frame(width: 8, height: 8)
                .help(appState.connectionStatus.description)
        }
        .padding()
    }

    // MARK: - Sensors

    private func sensorsSection(data: AirQualityData) -> some View {
        VStack(spacing: 12) {
            // CO2
            SensorRowView(
                icon: "carbon.dioxide.cloud",
                title: "CO₂",
                value: data.co2.map { "\($0)" } ?? "—",
                unit: "ppm",
                level: data.co2Level
            )

            // PM2.5
            SensorRowView(
                icon: "smoke",
                title: "PM2.5",
                value: data.pm25.map { "\($0)" } ?? "—",
                unit: "µg/m³",
                level: data.pm25Level
            )

            // PM10
            SensorRowView(
                icon: "smoke.fill",
                title: "PM10",
                value: data.pm10.map { "\($0)" } ?? "—",
                unit: "µg/m³",
                level: data.pm10Level
            )

            Divider()
                .padding(.vertical, 4)

            // Temperatura y Humedad
            HStack(spacing: 0) {
                ClimateRowView(
                    icon: "thermometer.medium",
                    title: "Temperatura",
                    value: data.temperature.map { String(format: "%.1f", $0) } ?? "—",
                    unit: "°C",
                    color: .orange
                )

                Divider()
                    .frame(height: 50)

                ClimateRowView(
                    icon: "humidity",
                    title: "Humedad",
                    value: data.humidity.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "%",
                    color: .blue
                )
            }

            // Batería y última actualización
            HStack {
                if let battery = data.battery {
                    Label("\(battery)%", systemImage: batteryIcon(for: battery))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let timestamp = data.timestamp {
                    Text(timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Ofusca la MAC address si no hay nombre de dispositivo
    private func sanitizedDeviceName(_ device: DeviceWithData) -> String {
        if let name = device.info.name, !name.isEmpty {
            return name
        }
        // Mostrar solo los últimos 4 caracteres de la MAC
        let mac = device.info.mac
        return "Device ...\(mac.suffix(4))"
    }

    // MARK: - Loading

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Cargando datos...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 150)
    }

    // MARK: - Waiting

    private var waitingSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Esperando datos...")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Actualizar") {
                Task { await appState.refreshData() }
            }
            .buttonStyle(.bordered)
        }
        .frame(height: 150)
    }

    // MARK: - Error

    private func errorSection(error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.yellow)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Reintentar") {
                Task { await appState.refreshData() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Configuration Prompt

    private var configurationPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "gear.badge.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("API no configurada")
                .font(.headline)
            Text("Añade tus credenciales de Qingping en Ajustes")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            SettingsLink {
                Text("Abrir Ajustes")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: { Task { await appState.refreshData() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(appState.isLoading)
            .help("Actualizar")

            Spacer()

            if appState.devices.count > 1 {
                Menu {
                    ForEach(appState.devices) { device in
                        Button(sanitizedDeviceName(device)) {
                            appState.selectedDeviceMac = device.info.mac
                            Task { await appState.refreshData() }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.stack")
                }
                .menuStyle(.borderlessButton)
                .help("Cambiar dispositivo")
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Ajustes")

            Spacer()

            Button {
                openWindow(id: "history-window")
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.borderless)
            .help("Ver histórico")
            .disabled(!appState.isHistoryEnabled)

            Spacer()

            Button("Salir") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
