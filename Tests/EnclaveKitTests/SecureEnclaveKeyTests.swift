//
//  SecureEnclaveKeyTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import CryptoKit
import EnclaveKitCore
import Foundation
import Testing
@testable import EnclaveKit

/// The Mac's own Secure Enclave, keys without `.userPresence`. Off where
/// there is none: the iOS simulator, Intel Macs without T2.
@Suite(.enabled(if: SecureEnclave.isAvailable))
final class SecureEnclaveKeyTests {
    let account = "test-\(UUID().uuidString)"

    deinit {
        try? Keychain.delete(account)
    }

    func key() throws -> SecureEnclaveKey {
        try SecureEnclaveKey.loadOrCreate(account: account, flags: .privateKeyUsage)
    }

    @Test func signaturesVerify() async throws {
        let message = Array("enclavekit:v1 preimage".utf8)
        let key = try key()
        let signature = try await key.sign(message)

        let publicKey = try P256.Signing.PublicKey(compressedRepresentation: key.publicKey.bytes)
        #expect(publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: message))
    }

    @Test func secondLoadFindsTheSameKey() throws {
        let first = try key()
        let second = try key()
        #expect(second.publicKey == first.publicKey)
    }
}
