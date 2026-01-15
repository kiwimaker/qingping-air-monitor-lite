import SwiftUI
import Combine

enum ConnectionStatus {
    case connected, disconnected, connecting, error

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .error: return .red
        }
    }

    var description: String {
        switch self {
        case .connected: return "Conectado"
        case .disconnected: return "Desconectado"
        case .connecting: return "Conectando..."
        case .error: return "Error"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var currentData: AirQualityData?
    @Published var devices: [DeviceWithData] = []
    @Published var selectedDeviceMac: String?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var refreshInterval: TimeInterval = 60
    @Published var menuBarDisplayOptions: MenuBarDisplayOptions {
        didSet { saveDisplayOptions() }
    }

    // MARK: - Services
    let keychainService = KeychainService()
    private var apiService: QingpingAPIService?
    private var authService: AuthenticationService?

    // MARK: - Timer
    private var refreshTask: Task<Void, Never>?

    // MARK: - Computed Properties
    var isConfigured: Bool {
        keychainService.hasCredentials
    }

    var selectedDevice: DeviceWithData? {
        devices.first { $0.info.mac == selectedDeviceMac }
    }

    // MARK: - UserDefaults Keys
    private let displayOptionsKey = "menuBarDisplayOptions"

    // MARK: - Initialization

    init() {
        menuBarDisplayOptions = Self.loadDisplayOptions()
        setupServices()
        // NO iniciar refresh aquí - debe hacerse después de que la UI esté lista
    }

    private static func loadDisplayOptions() -> MenuBarDisplayOptions {
        guard let data = UserDefaults.standard.data(forKey: "menuBarDisplayOptions"),
              let options = try? JSONDecoder().decode(MenuBarDisplayOptions.self, from: data) else {
            return .default
        }
        return options
    }

    private func saveDisplayOptions() {
        if let data = try? JSONEncoder().encode(menuBarDisplayOptions) {
            UserDefaults.standard.set(data, forKey: displayOptionsKey)
        }
    }

    /// Llamar después de que la app esté completamente inicializada
    func onAppLaunch() {
        if isConfigured {
            startPeriodicRefresh()
        }
    }

    func setupServices() {
        guard isConfigured else { return }

        authService = AuthenticationService(keychainService: keychainService)
        apiService = QingpingAPIService(authService: authService!)
    }

    // MARK: - Data Refresh

    func refreshData() async {
        guard isConfigured else {
            lastError = "API no configurada"
            connectionStatus = .disconnected
            return
        }

        if apiService == nil {
            setupServices()
        }

        guard let apiService = apiService else { return }

        isLoading = true
        connectionStatus = .connecting
        lastError = nil

        do {
            let fetchedDevices = try await apiService.fetchDevicesWithData()
            devices = fetchedDevices

            if selectedDeviceMac == nil, let firstDevice = fetchedDevices.first {
                selectedDeviceMac = firstDevice.info.mac
            }

            if let device = selectedDevice, let sensorData = device.data {
                currentData = AirQualityData(
                    co2: sensorData.co2.map { Int($0.value) },
                    pm25: sensorData.pm25.map { Int($0.value) },
                    pm10: sensorData.pm10.map { Int($0.value) },
                    temperature: sensorData.temperature?.value,
                    humidity: sensorData.humidity?.value,
                    battery: sensorData.battery.map { Int($0.value) },
                    timestamp: sensorData.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0.value)) }
                )
            }

            connectionStatus = .connected

        } catch {
            lastError = error.localizedDescription
            connectionStatus = .error
        }

        isLoading = false
    }

    // MARK: - Periodic Refresh

    func startPeriodicRefresh() {
        refreshTask?.cancel()

        refreshTask = Task {
            while !Task.isCancelled {
                if isConfigured {
                    await refreshData()
                }

                try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
            }
        }
    }

    func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        if isConfigured {
            startPeriodicRefresh()
        }
    }

    // MARK: - Credentials Management

    func saveCredentials(clientId: String, clientSecret: String) async throws {
        let credentials = APICredentials(clientId: clientId, clientSecret: clientSecret)
        try keychainService.saveCredentials(credentials)

        // Reset services with new credentials
        authService = nil
        apiService = nil
        setupServices()

        // Intentar obtener token y datos inmediatamente para validar credenciales
        await refreshData()

        // Si no hubo error, iniciar refresh periódico
        if lastError == nil {
            startPeriodicRefresh()
        }
    }

    func clearCredentials() {
        keychainService.deleteCredentials()
        stopPeriodicRefresh()
        authService = nil
        apiService = nil
        currentData = nil
        devices = []
        selectedDeviceMac = nil
        connectionStatus = .disconnected
    }
}
