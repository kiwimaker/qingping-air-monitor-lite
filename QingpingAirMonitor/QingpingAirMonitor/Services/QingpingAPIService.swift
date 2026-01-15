import Foundation

actor QingpingAPIService {
    private let baseURL = "https://apis.cleargrass.com/v1/apis"
    private let authService: AuthenticationService

    init(authService: AuthenticationService) {
        self.authService = authService
    }

    func fetchDevicesWithData() async throws -> [DeviceWithData] {
        let token = try await authService.getValidToken()
        let timestamp = Int(Date().timeIntervalSince1970)

        guard let url = URL(string: "\(baseURL)/devices?timestamp=\(timestamp)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        let devicesResponse = try JSONDecoder().decode(DeviceDataResponse.self, from: data)
        return devicesResponse.devices
    }

    func fetchHistoricalData(mac: String, startTime: Int, endTime: Int) async throws -> [DeviceWithData] {
        let token = try await authService.getValidToken()
        let timestamp = Int(Date().timeIntervalSince1970)

        var components = URLComponents(string: "\(baseURL)/devices/data")!
        components.queryItems = [
            URLQueryItem(name: "mac", value: mac),
            URLQueryItem(name: "start_time", value: String(startTime)),
            URLQueryItem(name: "end_time", value: String(endTime)),
            URLQueryItem(name: "timestamp", value: String(timestamp))
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let devicesResponse = try JSONDecoder().decode(DeviceDataResponse.self, from: data)
        return devicesResponse.devices
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL inválida"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .httpError(let code, let message):
            return "Error HTTP \(code): \(message)"
        case .decodingError(let detail):
            return "Error al procesar datos: \(detail)"
        }
    }
}
