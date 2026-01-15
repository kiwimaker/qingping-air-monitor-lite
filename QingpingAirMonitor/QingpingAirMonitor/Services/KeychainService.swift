import Foundation
import Security

struct APICredentials: Sendable {
    let clientId: String
    let clientSecret: String
}

actor KeychainService {
    private let service = "com.qingping.airmonitor2"
    private let clientIdKey = "qingping_client_id"
    private let clientSecretKey = "qingping_client_secret"

    // MARK: - Save Credentials

    func saveCredentials(_ credentials: APICredentials) throws {
        try save(key: clientIdKey, value: credentials.clientId)
        try save(key: clientSecretKey, value: credentials.clientSecret)
    }

    private func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingError
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Más restrictivo: no se copia en backups a otros dispositivos
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Get Credentials

    func getCredentials() -> APICredentials? {
        guard let clientId = getValue(for: clientIdKey),
              let clientSecret = getValue(for: clientSecretKey) else {
            return nil
        }
        return APICredentials(clientId: clientId, clientSecret: clientSecret)
    }

    private func getValue(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    // MARK: - Delete Credentials

    func deleteCredentials() {
        delete(key: clientIdKey)
        delete(key: clientSecretKey)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Check if configured

    var hasCredentials: Bool {
        getCredentials() != nil
    }
}

enum KeychainError: LocalizedError {
    case encodingError
    case saveFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Error al codificar los datos"
        case .saveFailed:
            // No exponer código de error técnico al usuario
            return "No se pudieron guardar las credenciales. Intenta de nuevo."
        case .notFound:
            return "Credenciales no encontradas"
        }
    }
}
