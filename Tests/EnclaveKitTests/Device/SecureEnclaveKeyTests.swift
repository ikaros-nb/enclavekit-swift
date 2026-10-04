//
//  SecureEnclaveKeyTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import CryptoKit
import Foundation
import Security
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

    func create() throws -> SecureEnclaveKey {
        try SecureEnclaveKey.create(account: account, flags: .privateKeyUsage)
    }

    @Test func signaturesVerify() async throws {
        let message = Array("enclavekit:v1 preimage".utf8)
        let key = try create()
        let signature = try await key.sign(message)

        let publicKey = try P256.Signing.PublicKey(compressedRepresentation: key.publicKey.bytes)
        #expect(publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: message))
    }

    @Test func loadFindsTheCreatedKey() throws {
        #expect(try SecureEnclaveKey.load(account: account) == nil)
        let created = try create()
        #expect(try SecureEnclaveKey.load(account: account)?.publicKey == created.publicKey)
    }

    @Test func createNeverReplaces() throws {
        let first = try create()
        #expect(throws: Keychain.Failure(status: errSecDuplicateItem)) { try create() }
        #expect(try SecureEnclaveKey.load(account: account)?.publicKey == first.publicKey)
    }
}
