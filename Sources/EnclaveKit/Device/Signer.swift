//
//  Signer.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import CryptoKit
import Foundation

/// The key that authorises the wallet's actions: the Secure Enclave on a
/// device, a software key in tests.
protocol Signer: Sendable {
    var publicKey: CompressedP256Key { get }

    /// ECDSA P-256 over SHA-256(`message`), as r ‖ s. S may be high: the
    /// secp256r1 instruction normalises it.
    func sign(_ message: [UInt8]) async throws -> [UInt8]
}

/// A P-256 key made by the Secure Enclave, which never lets it out. The app
/// keeps `dataRepresentation` in the Keychain: a blob only this enclave can
/// open, useless on any other device.
struct SecureEnclaveKey: Signer {
    let publicKey: CompressedP256Key
    private let dataRepresentation: Data

    /// The key saved under `account`, `nil` if there is none.
    static func load(account: String) throws -> SecureEnclaveKey? {
        try Keychain.read(account).map(SecureEnclaveKey.init(dataRepresentation:))
    }

    /// A new key, saved under `account`. Every signature asks for Face ID,
    /// Touch ID or the passcode; tests leave out `.userPresence`, nobody
    /// looks at the Mac. Never replaces a key: an `account` already taken
    /// fails with `errSecDuplicateItem`.
    static func create(account: String, flags: SecAccessControlCreateFlags = [.privateKeyUsage, .userPresence]) throws -> SecureEnclaveKey {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
        try Keychain.add(key.dataRepresentation, account: account)
        return try SecureEnclaveKey(dataRepresentation: key.dataRepresentation)
    }

    private init(dataRepresentation: Data) throws {
        // Loading and reading the public half need no authentication.
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation)
        publicKey = try CompressedP256Key(bytes: Array(key.publicKey.compressedRepresentation))
        self.dataRepresentation = dataRepresentation
    }

    /// Blocks its thread until the user authenticates: `@concurrent` keeps it
    /// off the caller's actor, the main one for an app.
    @concurrent func sign(_ message: [UInt8]) async throws -> [UInt8] {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation)
        return Array(try key.signature(for: message).rawRepresentation)
    }
}
