import Foundation

actor QingpingAPIService {
    private let baseURL = "https://apis.cleargrass.com/v1/apis"
    private let authService: AuthenticationService
    private let session: URLSession

    init(authService: AuthenticationService) {
        self.authService = authService

        // Configurar session con timeouts apropiados
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetch con reintentos y backoff exponencial

    func fetchDevicesWithData() async throws -> [DeviceWithData] {
        try await fetchWithRetry {
            try await self.performFetchDevices(retryOnUnauthorized: true)
        }
    }

    private func fetchWithRetry<T>(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error

                // No reintentar errores de autenticación o respuestas HTTP válidas con error
                if case APIError.httpError = error {
                    throw error
                }

                // Solo reintentar errores de red
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2  // Backoff exponencial
                }
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private func performFetchDevices(retryOnUnauthorized: Bool) async throws -> [DeviceWithData] {
        let token = try await authService.getValidToken()
        let timestamp = Int(Date().timeIntervalSince1970)

        guard let url = URL(string: "\(baseURL)/devices?timestamp=\(timestamp)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Si recibimos 401, limpiamos el token y reintentamos una vez
        if httpResponse.statusCode == 401 && retryOnUnauthorized {
            await authService.clearCache()
            return try await performFetchDevices(retryOnUnauthorized: false)
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Error desconocido")
        }

        let devicesResponse = try JSONDecoder().decode(DeviceDataResponse.self, from: data)
        return devicesResponse.devices
    }

    func fetchHistoricalData(mac: String, startTime: Int, endTime: Int) async throws -> [HistoricalReading] {
        var allReadings: [HistoricalReading] = []
        var offset = 0
        let limit = 200
        var totalReported = 0

        while true {
            let token = try await authService.getValidToken()
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)

            var components = URLComponents(string: "\(baseURL)/devices/data")!
            components.queryItems = [
                URLQueryItem(name: "mac", value: mac),
                URLQueryItem(name: "start_time", value: String(startTime)),
                URLQueryItem(name: "end_time", value: String(endTime)),
                URLQueryItem(name: "timestamp", value: String(timestamp)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]

            guard let url = components.url else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                if !allReadings.isEmpty { break }
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Error fetching historical data")
            }

            let historyResponse: HistoricalDataResponse
            do {
                historyResponse = try JSONDecoder().decode(HistoricalDataResponse.self, from: data)
            } catch {
                if !allReadings.isEmpty { break }
                throw error
            }

            totalReported = historyResponse.total

            if historyResponse.data.isEmpty { break }

            allReadings.append(contentsOf: historyResponse.data)

            if allReadings.count >= totalReported { break }

            offset += limit
        }

        return allReadings
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL inválida"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .httpError(let code, _):
            // No exponer detalles técnicos del mensaje
            return "Error del servidor (código \(code))"
        case .decodingError:
            return "Error al procesar los datos recibidos"
        case .networkUnavailable:
            return "Sin conexión a internet"
        }
    }
}
