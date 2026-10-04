//
//  EnclaveKitClientTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 04/10/2026.
//

import CryptoKit
import Foundation
import Testing
@testable import EnclaveKit

/// The Mac's Secure Enclave with the app's flags, `.userPresence` included:
/// making and loading a key ask for nothing, only signing would.
@Suite(.enabled(if: SecureEnclave.isAvailable))
final class EnclaveKitClientTests {
    let client = EnclaveKitClient(
        config: EnclaveKitConfig(relayerURL: URL(string: "http://kora.invalid")!),
        account: "test-\(UUID().uuidString)"
    )

    deinit {
        try? Keychain.delete(client.account)
    }

    @Test func noWalletBeforeCreate() throws {
        #expect(try client.wallet() == nil)
    }

    @Test func createdWalletIsFoundAgain() throws {
        let created = try client.createWallet()
        #expect(try client.wallet()?.address == created.address)
    }
}
