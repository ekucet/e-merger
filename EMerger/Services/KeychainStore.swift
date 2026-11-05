//
//  KeychainStore.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation
import Security

/// Secrets live only here, as `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// generic-password items: never synced to iCloud Keychain, never written to the
/// config file, never exported by the app.
enum KeychainStore {
    private static let credentialService = "com.emerger.bitbucket-credential"

    // MARK: Account credentials

    static func saveCredential(_ credential: BitbucketCredential, forAccountID id: String) throws {
        let data = try JSONEncoder().encode(credential)
        try save(data, service: credentialService, account: id)
    }

    static func loadCredential(forAccountID id: String) throws -> BitbucketCredential? {
        guard let data = try load(service: credentialService, account: id) else { return nil }
        return try JSONDecoder().decode(BitbucketCredential.self, from: data)
    }

    static func deleteCredential(forAccountID id: String) throws {
        try delete(service: credentialService, account: id)
    }

    // MARK: Primitives

    private static func save(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw EMergerError.keychain(status) }
    }

    private static func load(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw EMergerError.keychain(status)
        }
        return data
    }

    private static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EMergerError.keychain(status)
        }
    }
}
