import Foundation
import Security
import KeineMagieCore

// The only persisted copy of the bearer token lives in the device Keychain.
enum TokenStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "de.keinemagie.app.server",
         kSecAttrAccount as String: "bearer-token"]
    }
    static func read(account: String = "bearer-token") throws -> String {
        if account == "bearer-token", UserDefaults.standard.bool(forKey: "nativeIdentityRevoked") { return "" }
        var attributes = query
        attributes[kSecAttrAccount as String] = account
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainFailure(status: status)
        }
        return value
    }
    static func save(_ value: String, account: String = "bearer-token") throws {
        var query = query
        query[kSecAttrAccount as String] = account
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure(status: status) }
            return
        }
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = Data(value.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        if account == "bearer-token" { UserDefaults.standard.removeObject(forKey: "nativeIdentityRevoked") }
    }
    static func readIdentity() throws -> SavedNativeIdentity? {
        guard !UserDefaults.standard.bool(forKey: "nativeIdentityRevoked") else { return nil }
        let value = try read(account: "verified-native-identity-v1")
        guard !value.isEmpty else { return nil }
        return try JSONDecoder().decode(SavedNativeIdentity.self, from: Data(value.utf8))
    }
    static func saveIdentity(_ identity: SavedNativeIdentity?) throws {
        // A deny-only tombstone survives Keychain deletion failure. It never grants access.
        if identity == nil { UserDefaults.standard.set(true, forKey: "nativeIdentityRevoked") }
        let value = try identity.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? ""
        try save(value, account: "verified-native-identity-v1")
        if identity != nil { UserDefaults.standard.removeObject(forKey: "nativeIdentityRevoked") }
    }
}
private struct KeychainFailure: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { AppL10n.text("keychain.failure", status) }
}
