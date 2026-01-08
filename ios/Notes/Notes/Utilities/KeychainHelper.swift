import Foundation
import Security

/// Secure Keychain wrapper for storing sensitive data
enum KeychainHelper {

    enum KeychainError: Error {
        case duplicateEntry
        case noData
        case unexpectedStatus(OSStatus)
        case encodingError
    }

    // MARK: - Keychain Keys

    enum Key: String {
        case accessToken = "com.notes.accessToken"
        case refreshToken = "com.notes.refreshToken"
    }

    // MARK: - Save

    static func save(_ data: Data, for key: Key) throws {
        // Delete any existing item first
        try? delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func save(_ string: String, for key: Key) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingError
        }
        try save(data, for: key)
    }

    // MARK: - Read

    static func read(_ key: Key) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.noData
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.noData
        }

        return data
    }

    static func readString(_ key: Key) throws -> String {
        let data = try read(key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingError
        }
        return string
    }

    static func readStringOrNil(_ key: Key) -> String? {
        try? readString(key)
    }

    // MARK: - Delete

    static func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Convenience Methods

    static func saveTokens(accessToken: String, refreshToken: String) throws {
        try save(accessToken, for: .accessToken)
        try save(refreshToken, for: .refreshToken)
    }

    static func getAccessToken() -> String? {
        readStringOrNil(.accessToken)
    }

    static func getRefreshToken() -> String? {
        readStringOrNil(.refreshToken)
    }

    static func clearTokens() {
        try? delete(.accessToken)
        try? delete(.refreshToken)
    }
}
