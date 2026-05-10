import SwiftUI
import Combine
import Network

enum ConnectionStatus {
    case connected, disconnected, connecting, error, noNetwork

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .error: return .red
        case .noNetwork: return .orange
        }
    }

    var description: String {
        switch self {
        case .connected: return "Conectado"
        case .disconnected: return "Desconectado"
        case .connecting: return "Conectando..."
        case .error: return "Error"
        case .noNetwork: return "Sin conexión"
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
    @Published var isNetworkAvailable = true
    @Published var menuBarDisplayOptions: MenuBarDisplayOptions {
        didSet { saveDisplayOptions() }
    }

    // MARK: - History Properties
    @Published var isHistoryEnabled: Bool {
        didSet { UserDefaults.standard.set(isHistoryEnabled, forKey: historyEnabledKey) }
    }
    @Published var historyRetention: HistoryRetention {
        didSet { UserDefaults.standard.set(historyRetention.rawValue, forKey: historyRetentionKey) }
    }
    @Published var showHistoryWindow = false

    // refreshInterval con persistencia
    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: refreshIntervalKey)
        }
    }

    // MARK: - Services
    let keychainService = KeychainService()
    private var apiService: QingpingAPIService?
    private var authService: AuthenticationService?
    private(set) var historyService: HistoryDatabaseService?

    // MARK: - Network Monitor
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.qingping.networkmonitor")

    // MARK: - Timer
    private var refreshTask: Task<Void, Never>?
    private var hasLaunched = false

    // MARK: - Computed Properties
    var isConfigured: Bool {
        get async {
            await keychainService.hasCredentials
        }
    }

    // Versión síncrona para UI (usa cache)
    private var _isConfiguredCache = false
    var isConfiguredSync: Bool { _isConfiguredCache }

    var selectedDevice: DeviceWithData? {
        devices.first { $0.info.mac == selectedDeviceMac }
    }

    // MARK: - UserDefaults Keys
    private let displayOptionsKey = "menuBarDisplayOptions"
    private let refreshIntervalKey = "refreshInterval"
    private let historyEnabledKey = "historyEnabled"
    private let historyRetentionKey = "historyRetention"

    // MARK: - Initialization

    init() {
        // Cargar preferencias guardadas
        menuBarDisplayOptions = Self.loadDisplayOptions()

        // Cargar refreshInterval persistido
        let savedInterval = UserDefaults.standard.double(forKey: refreshIntervalKey)
        refreshInterval = savedInterval > 0 ? savedInterval : 900 // Default 15 min

        // Cargar configuración de histórico
        isHistoryEnabled = UserDefaults.standard.bool(forKey: historyEnabledKey)
        let retentionRaw = UserDefaults.standard.string(forKey: historyRetentionKey) ?? HistoryRetention.unlimited.rawValue
        historyRetention = HistoryRetention(rawValue: retentionRaw) ?? .unlimited

        // Configurar monitoreo de red
        setupNetworkMonitoring()

        // Configurar observador de wake from sleep
        setupWakeNotification()

        // Inicializar servicio de histórico
        setupHistoryService()

        // Actualizar cache de credenciales
        Task {
            _isConfiguredCache = await keychainService.hasCredentials
            if _isConfiguredCache {
                setupServices()
            }
        }
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied

                // Si la red vuelve a estar disponible, refrescar datos
                if !wasAvailable && self.isNetworkAvailable && self._isConfiguredCache {
                    await self.refreshData()
                }

                // Actualizar estado de conexión si no hay red
                if !self.isNetworkAvailable {
                    self.connectionStatus = .noNetwork
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Wake from Sleep Detection

    private func setupWakeNotification() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self._isConfiguredCache else { return }
                // Esperar un momento para que la red se restablezca
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.refreshData()
            }
        }
    }

    // MARK: - Display Options

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
        guard !hasLaunched else { return }
        hasLaunched = true

        Task {
            _isConfiguredCache = await keychainService.hasCredentials
            if _isConfiguredCache {
                // Refrescar datos primero para tener selectedDeviceMac
                await refreshData()
                startPeriodicRefresh()

                // Sincronizar histórico desde la API (llena gaps cuando la app estaba cerrada)
                if isHistoryEnabled {
                    await syncHistoryFromAPI()
                }
            }

            // Limpieza de histórico al iniciar
            await cleanupOldHistory()
        }
    }

    func setupServices() {
        Task {
            guard await keychainService.hasCredentials else { return }

            authService = AuthenticationService(keychainService: keychainService)
            apiService = QingpingAPIService(authService: authService!)
        }
    }

    // MARK: - Data Refresh

    func refreshData() async {
        // Verificar conectividad de red primero
        guard isNetworkAvailable else {
            lastError = "Sin conexión a internet"
            connectionStatus = .noNetwork
            return
        }

        let configured = await keychainService.hasCredentials
        guard configured else {
            lastError = "API no configurada"
            connectionStatus = .disconnected
            return
        }

        if apiService == nil {
            setupServices()
            // Esperar a que los servicios se configuren
            try? await Task.sleep(nanoseconds: 100_000_000)
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

                // Guardar en histórico si está habilitado
                if isHistoryEnabled, let data = currentData {
                    await saveToHistory(data: data, deviceMac: device.info.mac)
                }
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
        refreshTask = nil

        refreshTask = Task {
            while !Task.isCancelled {
                let configured = await keychainService.hasCredentials
                if configured {
                    await refreshData()
                }

                // Manejar correctamente la cancelación durante el sleep
                do {
                    try await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
                } catch {
                    // Task fue cancelado, salir del loop
                    break
                }
            }
        }
    }

    func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        Task {
            if await keychainService.hasCredentials {
                startPeriodicRefresh()
            }
        }
    }

    // MARK: - Credentials Management

    func saveCredentials(clientId: String, clientSecret: String) async throws {
        let credentials = APICredentials(clientId: clientId, clientSecret: clientSecret)
        try await keychainService.saveCredentials(credentials)

        // Reset services with new credentials
        authService = nil
        apiService = nil
        _isConfiguredCache = true
        setupServices()

        // Esperar a que los servicios se inicialicen
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Intentar obtener token y datos inmediatamente para validar credenciales
        await refreshData()

        // Si no hubo error, iniciar refresh periódico
        if lastError == nil {
            startPeriodicRefresh()
        }
    }

    func clearCredentials() {
        Task {
            await keychainService.deleteCredentials()
            stopPeriodicRefresh()
            authService = nil
            apiService = nil
            currentData = nil
            devices = []
            selectedDeviceMac = nil
            connectionStatus = .disconnected
            _isConfiguredCache = false
        }
    }

    // MARK: - History Management

    private func setupHistoryService() {
        do {
            historyService = try HistoryDatabaseService()
        } catch {
            print("Error inicializando servicio de histórico: \(error.localizedDescription)")
        }
    }

    private func saveToHistory(data: AirQualityData, deviceMac: String) async {
        guard let service = historyService else { return }

        let reading = SensorReading(from: data, deviceMac: deviceMac)
        do {
            try await service.insertReading(reading)
        } catch {
            print("Error guardando lectura en histórico: \(error.localizedDescription)")
        }
    }

    func cleanupOldHistory() async {
        guard let service = historyService,
              let cutoffDate = historyRetention.cutoffDate else { return }

        do {
            let deleted = try await service.deleteOldReadings(olderThan: cutoffDate)
            if deleted > 0 {
                print("Limpieza de histórico: \(deleted) registros eliminados")
            }
        } catch {
            print("Error limpiando histórico: \(error.localizedDescription)")
        }
    }

    func deleteAllHistory() async {
        guard let service = historyService else { return }

        do {
            try await service.deleteAllReadings()
        } catch {
            print("Error eliminando histórico: \(error.localizedDescription)")
        }
    }

    func getHistoryStats() async -> (count: Int, size: Int64, oldest: Date?, newest: Date?) {
        guard let service = historyService else { return (0, 0, nil, nil) }

        let count = await service.getRecordCount()
        let size = await service.getDatabaseSize()
        let range = await service.getDateRange()

        return (count, size, range.oldest, range.newest)
    }

    func exportHistoryToCSV() async -> String? {
        guard let service = historyService,
              let deviceMac = selectedDeviceMac else { return nil }

        do {
            return try await service.exportAllToCSV(deviceMac: deviceMac)
        } catch {
            print("Error exportando CSV: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchMonthlyStats() async -> [MonthlyStats] {
        guard let service = historyService,
              let deviceMac = selectedDeviceMac else { return [] }

        do {
            return try await service.fetchMonthlyStats(deviceMac: deviceMac)
        } catch {
            print("Error obteniendo estadísticas mensuales: \(error.localizedDescription)")
            return []
        }
    }

    func fetchHistoryReadings(for range: TimeRange) async -> [SensorReading] {
        guard let service = historyService,
              let deviceMac = selectedDeviceMac else { return [] }

        do {
            return try await service.fetchAggregatedReadings(
                deviceMac: deviceMac,
                from: range.startDate,
                to: Date(),
                bucketSeconds: range.aggregationBucketSeconds
            )
        } catch {
            print("Error obteniendo lecturas: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - History Sync from API

    /// Sincroniza el histórico desde la API de Qingping
    /// Obtiene datos desde el último registro guardado hasta ahora
    func syncHistoryFromAPI() async {
        guard isHistoryEnabled,
              let service = historyService,
              let apiService = apiService,
              let deviceMac = selectedDeviceMac else { return }

        let lastTimestamp = await service.getLastTimestamp(deviceMac: deviceMac)

        let startDate: Date
        if let last = lastTimestamp {
            startDate = last.addingTimeInterval(60)
        } else {
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }

        let endDate = Date()

        // No sincronizar si la diferencia es menor a 5 minutos
        guard endDate.timeIntervalSince(startDate) > 300 else { return }

        let startTime = Int(startDate.timeIntervalSince1970)
        let endTime = Int(endDate.timeIntervalSince1970)

        do {
            let historicalData = try await apiService.fetchHistoricalData(
                mac: deviceMac,
                startTime: startTime,
                endTime: endTime
            )

            let readings: [SensorReading] = historicalData.map { item in
                SensorReading(
                    deviceMac: deviceMac,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(item.timestamp.value)),
                    co2: item.co2.map { Int($0.value) },
                    pm25: item.pm25.map { Int($0.value) },
                    pm10: item.pm10.map { Int($0.value) },
                    temperature: item.temperature?.value,
                    humidity: item.humidity?.value,
                    battery: item.battery.map { Int($0.value) }
                )
            }

            if !readings.isEmpty {
                try await service.insertReadingsIgnoringDuplicates(readings)
            }
        } catch {
            // Silently fail - sync errors shouldn't disrupt user experience
        }
    }

    /// Sincronización forzada de los últimos N días (ignora lastTimestamp)
    @Published var isSyncingHistory = false
    @Published var syncProgress: HistorySyncProgress?
    @Published var lastSyncError: String?
    @Published var lastSyncSummary: String?

    func forceSyncHistory(days: Int) async {
        guard let service = historyService,
              let apiService = apiService,
              let deviceMac = selectedDeviceMac else { return }

        isSyncingHistory = true
        syncProgress = HistorySyncProgress(phase: .connecting, loaded: 0, total: 0)
        lastSyncError = nil
        lastSyncSummary = nil
        defer {
            isSyncingHistory = false
            syncProgress = nil
        }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        let startTime = Int(startDate.timeIntervalSince1970)
        let endTime = Int(endDate.timeIntervalSince1970)

        do {
            let historicalData = try await apiService.fetchHistoricalData(
                mac: deviceMac,
                startTime: startTime,
                endTime: endTime
            ) { [weak self] loaded, total in
                Task { @MainActor in
                    self?.syncProgress = HistorySyncProgress(
                        phase: .fetching,
                        loaded: loaded,
                        total: total
                    )
                }
            }

            syncProgress = HistorySyncProgress(
                phase: .saving,
                loaded: 0,
                total: historicalData.count
            )

            let readings: [SensorReading] = historicalData.map { item in
                SensorReading(
                    deviceMac: deviceMac,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(item.timestamp.value)),
                    co2: item.co2.map { Int($0.value) },
                    pm25: item.pm25.map { Int($0.value) },
                    pm10: item.pm10.map { Int($0.value) },
                    temperature: item.temperature?.value,
                    humidity: item.humidity?.value,
                    battery: item.battery.map { Int($0.value) }
                )
            }

            if !readings.isEmpty {
                try await service.insertReadingsIgnoringDuplicates(readings)
            }

            lastSyncSummary = "\(readings.count) lecturas sincronizadas"
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Sincronización de huecos

    /// Detecta tramos sin datos en el histórico local y solicita a la API
    /// los rangos faltantes. Útil cuando el dispositivo estuvo offline durante
    /// días/semanas y necesitamos recuperar lo que la nube todavía conserva.
    /// Solo considera huecos > `gapThreshold` para evitar consultas inútiles
    /// por outages cortos (cadencia normal del dispositivo es 1–15 min).
    func syncHistoryGaps(gapThreshold: TimeInterval = 6 * 3600) async {
        guard let service = historyService,
              let apiService = apiService,
              let deviceMac = selectedDeviceMac else { return }

        isSyncingHistory = true
        syncProgress = HistorySyncProgress(phase: .scanningGaps, loaded: 0, total: 0)
        lastSyncError = nil
        lastSyncSummary = nil
        defer {
            isSyncingHistory = false
            syncProgress = nil
        }

        // 1. Detectar huecos
        let timestamps: [Int64]
        do {
            timestamps = try await service.fetchTimestamps(deviceMac: deviceMac)
        } catch {
            lastSyncError = error.localizedDescription
            return
        }

        guard timestamps.count >= 2 else {
            lastSyncSummary = "No hay suficientes datos para detectar huecos"
            return
        }

        var gaps: [(start: Date, end: Date)] = []
        let thresholdSecs = Int64(gapThreshold)
        for i in 1..<timestamps.count {
            let delta = timestamps[i] - timestamps[i - 1]
            if delta > thresholdSecs {
                // Pedimos justo el interior del hueco para no duplicar
                let start = Date(timeIntervalSince1970: TimeInterval(timestamps[i - 1] + 60))
                let end = Date(timeIntervalSince1970: TimeInterval(timestamps[i] - 60))
                gaps.append((start, end))
            }
        }

        guard !gaps.isEmpty else {
            lastSyncSummary = "No se han detectado huecos"
            return
        }

        // 2. Rellenar cada hueco
        var totalRecovered = 0
        var failedGaps = 0

        for (index, gap) in gaps.enumerated() {
            syncProgress = HistorySyncProgress(
                phase: .fillingGap(index: index + 1, count: gaps.count),
                loaded: 0,
                total: 0
            )

            let startTime = Int(gap.start.timeIntervalSince1970)
            let endTime = Int(gap.end.timeIntervalSince1970)

            do {
                let historicalData = try await apiService.fetchHistoricalData(
                    mac: deviceMac,
                    startTime: startTime,
                    endTime: endTime
                ) { [weak self] loaded, total in
                    Task { @MainActor in
                        self?.syncProgress = HistorySyncProgress(
                            phase: .fillingGap(index: index + 1, count: gaps.count),
                            loaded: loaded,
                            total: total
                        )
                    }
                }

                let readings: [SensorReading] = historicalData.map { item in
                    SensorReading(
                        deviceMac: deviceMac,
                        timestamp: Date(timeIntervalSince1970: TimeInterval(item.timestamp.value)),
                        co2: item.co2.map { Int($0.value) },
                        pm25: item.pm25.map { Int($0.value) },
                        pm10: item.pm10.map { Int($0.value) },
                        temperature: item.temperature?.value,
                        humidity: item.humidity?.value,
                        battery: item.battery.map { Int($0.value) }
                    )
                }

                if !readings.isEmpty {
                    try await service.insertReadingsIgnoringDuplicates(readings)
                    totalRecovered += readings.count
                }
            } catch {
                failedGaps += 1
                // Seguimos con el siguiente hueco; un fallo aislado no debe
                // abortar toda la operación.
            }
        }

        var summary = "\(gaps.count) huecos analizados · \(totalRecovered) lecturas recuperadas"
        if failedGaps > 0 {
            summary += " · \(failedGaps) sin respuesta del servidor"
        }
        lastSyncSummary = summary
    }
}

// MARK: - Progreso de sincronización

struct HistorySyncProgress: Equatable {
    enum Phase: Equatable {
        case connecting
        case fetching
        case saving
        case scanningGaps
        case fillingGap(index: Int, count: Int)

        var label: String {
            switch self {
            case .connecting: return "Conectando…"
            case .fetching: return "Descargando"
            case .saving: return "Guardando"
            case .scanningGaps: return "Buscando huecos"
            case .fillingGap: return "Rellenando hueco"
            }
        }
    }

    let phase: Phase
    let loaded: Int
    let total: Int

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(loaded) / Double(total))
    }
}
