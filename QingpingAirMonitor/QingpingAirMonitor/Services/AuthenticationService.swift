import Foundation

actor AuthenticationService {
    private let tokenURL = URL(string: "https://oauth.cleargrass.com/oauth2/token")!
    private let keychainService: KeychainService

    private var cachedToken: String?
    private var tokenExpiration: Date?

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
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
        guard let credentials = keychainService.getCredentials() else {
            print("[Auth] No credentials found")
            throw AuthError.noCredentials
        }

        print("[Auth] Got credentials - clientId: \(credentials.clientId.prefix(5))...")

        let credentialString = "\(credentials.clientId):\(credentials.clientSecret)"
        guard let credentialData = credentialString.data(using: .utf8) else {
            throw AuthError.encodingError
        }
        let base64Credentials = credentialData.base64EncodedString()

        print("[Auth] Base64: \(base64Credentials.prefix(20))...")
        print("[Auth] Requesting token from: \(tokenURL)")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = "grant_type=client_credentials&scope=device_full_access"
        request.httpBody = bodyParams.data(using: .utf8)

        print("[Auth] Sending request...")
        let (data, response) = try await URLSession.shared.data(for: request)
        print("[Auth] Got response")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[Auth] Invalid response type")
            throw AuthError.invalidResponse
        }

        print("[Auth] Status code: \(httpResponse.statusCode)")
        if let responseBody = String(data: data, encoding: .utf8) {
            print("[Auth] Response body: \(responseBody)")
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw AuthError.serverError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            throw AuthError.invalidResponse
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        print("[Auth] Token obtained successfully!")

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
        case .serverError(let code, let message):
            return "Error del servidor (\(code)): \(message)"
        }
    }
}
