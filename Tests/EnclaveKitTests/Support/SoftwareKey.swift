//
//  SoftwareKey.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import CryptoKit
import EnclaveKit

/// A P-256 key in memory, for tests. A device key never leaves its enclave.
struct SoftwareKey: Signer {
    /// The key of key.json. Public: anyone can sign for its wallet, devnet only.
    static let test = try! SoftwareKey(rawRepresentation: Array(1...32))

    let privateKey: P256.Signing.PrivateKey
    let publicKey: CompressedP256Key

    init(rawRepresentation: [UInt8]) throws {
        privateKey = try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation)
        publicKey = try CompressedP256Key(bytes: Array(privateKey.publicKey.compressedRepresentation))
    }

    func sign(_ message: [UInt8]) async throws -> [UInt8] {
        Array(try privateKey.signature(for: message).rawRepresentation)
    }
}
