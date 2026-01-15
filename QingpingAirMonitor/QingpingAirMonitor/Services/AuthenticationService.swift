import Foundation

actor AuthenticationService {
    private let tokenURL = URL(string: "https://oauth.cleargrass.com/oauth2/token")!
    private let keychainService: KeychainService
    private let session: URLSession

    private var cachedToken: String?
    private var tokenExpiration: Date?

    init(keychainService: KeychainService) {
        self.keychainService = keychainService

        // Configurar session con timeouts apropiados
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func getValidToken() async throws -> String {
        if let token = cachedToken,
           let expiration = tokenExpiration,
           expiration > Date().addingTimeInterval(60) {
            return token
        }

        return try await refreshToken()
    }

    func clearCache() {
        cachedToken = nil
        tokenExpiration = nil
    }

    private func refreshToken() async throws -> String {
        guard let credentials = await keychainService.getCredentials() else {
            throw AuthError.noCredentials
        }

        let credentialString = "\(credentials.clientId):\(credentials.clientSecret)"
        guard let credentialData = credentialString.data(using: .utf8) else {
            throw AuthError.encodingError
        }
        let base64Credentials = credentialData.base64EncodedString()

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = "grant_type=client_credentials&scope=device_full_access"
        request.httpBody = bodyParams.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw AuthError.serverError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            throw AuthError.invalidResponse
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        cachedToken = tokenResponse.accessToken
        tokenExpiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))

        return tokenResponse.accessToken
    }
}

enum AuthError: LocalizedError {
    case noCredentials
    case encodingError
    case invalidResponse
    case tokenExpired
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "API no configurada. Añade tus credenciales en Ajustes."
        case .encodingError:
            return "Error al codificar credenciales"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .tokenExpired:
            return "Token expirado"
        case .serverError(let code, _):
            // No exponer detalles del servidor al usuario
            return "Error de autenticación (código \(code))"
        }
    }
}
