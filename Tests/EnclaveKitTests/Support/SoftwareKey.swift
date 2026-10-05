//
//  SoftwareKey.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import CryptoKit
@testable import EnclaveKit

/// A P-256 key in memory, for tests. A device key never leaves its enclave.
struct SoftwareKey: Signer {
    /// The key of key.json. Public: anyone can sign for its wallet, devnet only.
    static let test = try! SoftwareKey(rawRepresentation: Array(1...32))
    /// A second devnet wallet, vault QWA9Uu…: it funds the live scenarios
    /// that need a new wallet, away from `test`'s nonce.
    static let funder = try! SoftwareKey(rawRepresentation: Array(33...64))

    let privateKey: P256.Signing.PrivateKey
    let publicKey: CompressedP256Key

    init(rawRepresentation: [UInt8]) throws {
        self.init(privateKey: try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation))
    }

    /// A key nobody had before: a new wallet, a new device.
    init() {
        self.init(privateKey: P256.Signing.PrivateKey())
    }

    private init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
        // A compressed P-256 key is always 33 bytes.
        publicKey = try! CompressedP256Key(bytes: Array(privateKey.publicKey.compressedRepresentation))
    }

    func sign(_ message: [UInt8]) async throws -> [UInt8] {
        Array(try privateKey.signature(for: message).rawRepresentation)
    }
}
