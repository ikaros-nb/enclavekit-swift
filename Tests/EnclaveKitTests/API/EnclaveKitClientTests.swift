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
        try? Keychain.delete(client.guardedAccount)
    }

    @Test func noWalletBeforeCreate() throws {
        #expect(try client.wallet() == nil)
    }

    @Test func createdWalletIsFoundAgain() throws {
        let created = try client.createWallet()
        #expect(try client.wallet()?.address == created.address)
    }

    @Test func createWalletNeverReplaces() throws {
        let created = try client.createWallet()
        #expect(throws: EnclaveKitError.walletExists) { try client.createWallet() }
        #expect(try client.wallet()?.address == created.address)
    }

    @Test func guardingNeedsAWallet() throws {
        #expect(throws: EnclaveKitError.noWallet) { try client.guardWallet(Self.someWallet) }
        #expect(try client.guardedWallets().isEmpty)
    }

    /// Each wallet once, in the order the device took them on, signed with
    /// this device's key.
    @Test func guardedWalletsAreFoundAgain() throws {
        let own = try client.createWallet()
        let other = Wallet(signer: SoftwareKey(), kora: Kora(url: URL(string: "http://kora.invalid")!)).id
        _ = try client.guardWallet(Self.someWallet)
        _ = try client.guardWallet(other)
        _ = try client.guardWallet(Self.someWallet)
        let guarded = try client.guardedWallets()
        #expect(guarded.map(\.id) == [Self.someWallet, other])
        #expect(guarded.allSatisfy { $0.wallet.deviceKey == own.deviceKey })
    }

    /// The wallet of key.json.
    static let someWallet = try! Wallet.ID("enclavekit:wallet:FAnBvyFqTsuE8HTbq9yCDS4fuWyHnvH8CH5Vi5EqKcNQ")
}
