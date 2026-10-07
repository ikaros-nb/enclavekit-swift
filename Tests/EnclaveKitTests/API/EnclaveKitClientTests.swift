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
        try? Keychain.delete(client.recoveredAccount)
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

    /// This device's list only: the wallet still names it on-chain.
    @Test func forgottenWalletIsNoLongerGuarded() throws {
        _ = try client.createWallet()
        let other = Wallet(signer: SoftwareKey(), kora: Kora(url: URL(string: "http://kora.invalid")!)).id
        _ = try client.guardWallet(Self.someWallet)
        _ = try client.guardWallet(other)
        try client.forgetWallet(Self.someWallet)
        #expect(try client.guardedWallets().map(\.id) == [other])
        try client.forgetWallet(Self.someWallet)
        try client.forgetWallet(other)
        #expect(try client.guardedWallets().isEmpty)
    }

    /// What a confirmed close runs: `deleteDeviceKey()`, lists included.
    @Test func closedWalletTakesTheKeyAlong() throws {
        _ = try client.createWallet()
        _ = try client.guardWallet(Self.someWallet)
        try #require(try client.wallet()).deleteKey()
        #expect(try client.wallet() == nil)
        // A new key guards nothing.
        _ = try client.createWallet()
        #expect(try client.guardedWallets().isEmpty)
    }

    /// Its owner's key, no proposal.
    @Test func recoveryNeedsAProposal() async throws {
        let own = try client.createWallet()
        await #expect(throws: EnclaveKitError.noRecovery) {
            try await online([Self.someWallet: stateData()]).recoverWallet(Self.someWallet)
        }
        #expect(try client.wallet()?.id == own.id)
    }

    /// A guardian proposed this device's key, then showed the wallet.
    @Test func recoveredWalletIsFoundAgain() async throws {
        let own = try client.createWallet()
        let pending = rotation(to: own.deviceKey.key, secondsAgo: 10)
        let recovered = try await online([Self.someWallet: stateData(rotation: pending)]).recoverWallet(Self.someWallet)
        #expect(try await recovered.status() == .recovering(Recovery(pending, cluster: .devnet)))
        let found = try #require(try client.wallet())
        #expect(found.id == Self.someWallet)
        #expect(found.deviceKey == own.deviceKey)
    }

    /// This device signs for its own wallet: taking on another would hide it.
    @Test func walletInUseIsKept() async throws {
        let own = try client.createWallet()
        let device = online([
            own.id: stateData(activeKey: own.deviceKey.key),
            Self.someWallet: stateData(rotation: rotation(to: own.deviceKey.key, secondsAgo: 10)),
        ])
        await #expect(throws: EnclaveKitError.walletExists) { try await device.recoverWallet(Self.someWallet) }
        #expect(try client.wallet()?.id == own.id)
    }

    @Test func deletedKeyTakesItsListsAlong() async throws {
        let own = try client.createWallet()
        _ = try client.guardWallet(Self.someWallet)
        let pending = rotation(to: own.deviceKey.key, secondsAgo: 10)
        _ = try await online([Self.someWallet: stateData(rotation: pending)]).recoverWallet(Self.someWallet)

        try client.deleteDeviceKey()
        #expect(try client.wallet() == nil)
        #expect(try client.guardedWallets().isEmpty)

        // A new key starts with its own wallet, and guards nothing.
        let next = try client.createWallet()
        #expect(next.deviceKey != own.deviceKey)
        #expect(try client.wallet()?.id == next.id)
        #expect(try client.guardedWallets().isEmpty)
    }

    /// The wallet of key.json.
    static let someWallet = try! Wallet.ID("enclavekit:wallet:FAnBvyFqTsuE8HTbq9yCDS4fuWyHnvH8CH5Vi5EqKcNQ")

    /// This device, on a devnet that holds `states`, by wallet, and no other
    /// account.
    func online(_ states: [Wallet.ID: [UInt8]]) -> EnclaveKitClient {
        let accounts = Dictionary(uniqueKeysWithValues: states.map { id, data in
            (EnclaveKitProgram.walletAddress(walletId: id.bytes).base58, accountJSON(data: data))
        })
        return EnclaveKitClient(config: client.config, account: client.account, transport: stub { method, params in
            guard method == "getAccountInfo", let address = (params as? [Any])?.first as? String else { return nil }
            return #"{"context":{"slot":1},"value":\#(accounts[address] ?? "null")}"#
        })
    }
}
