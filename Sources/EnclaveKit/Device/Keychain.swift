//
//  Keychain.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import Foundation
import Security

/// Generic passwords of this app: readable once the device is unlocked,
/// left out of backups restored on another device.
enum Keychain {
    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    private static let service = "EnclaveKit"

    static func read(_ account: String) throws(Failure) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Failure(status: status)
        }
    }

    /// Never overwrites: an existing `account` fails with `errSecDuplicateItem`.
    static func add(_ data: Data, account: String) throws(Failure) {
        var query = query(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func delete(_ account: String) throws(Failure) {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    /// No `kSecUseDataProtectionKeychain`: iOS has only that keychain, and on
    /// the Mac it needs an entitlement `swift test` does not have.
    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
