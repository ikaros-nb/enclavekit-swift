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
/// making and loading a key ask for nothing, only signing would. One test at
/// a time: a dozen keys made at once leave the enclave's daemon silent, and
/// the whole run hangs.
@Suite(.serialized, .enabled(if: SecureEnclave.isAvailable))
final class EnclaveKitClientTests {
    let client = EnclaveKitClient(
        config: EnclaveKitConfig(relayerURL: URL(string: "http://kora.invalid")!),
        account: "test-\(UUID().uuidString)"
    )

    deinit {
        try? Keychain.delete(client.account)
        try? Keychain.delete(client.forgottenAccount)
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

    /// No key, nothing can name it: no network.
    @Test func noKeyFindsNothing() async throws {
        #expect(try await client.guardedWallets().isEmpty)
        #expect(try await client.recoverableWallets().isEmpty)
    }

    /// What a confirmed close runs: `deleteDeviceKey()`, lists included.
    @Test func closedWalletTakesTheKeyAlong() throws {
        _ = try client.createWallet()
        try client.forgetWallet(Self.someWallet)
        try #require(try client.wallet()).deleteKey()
        #expect(try client.wallet() == nil)
        #expect(try Keychain.read(client.forgottenAccount) == nil)
    }

    /// Its owner's key, no proposal.
    @Test func recoveryNeedsAProposal() async throws {
        let own = try client.createWallet()
        await #expect(throws: EnclaveKitError.noRecovery) {
            try await online([Self.someWallet: stateData()]).recoverWallet(Self.someWallet)
        }
        #expect(try client.wallet()?.id == own.id)
    }

    /// A guardian proposed this device's key.
    @Test func recoveredWalletIsFoundAgain() async throws {
        let own = try client.createWallet()
        let pending = rotation(to: own.deviceKey.key, secondsAgo: 10)
        let recovered = try await online([Self.someWallet: stateData(rotation: pending)]).recoverWallet(Self.someWallet)
        #expect(try await recovered.status() == .recovering(Recovery(pending, cluster: .devnet)))
        let found = try #require(try client.wallet())
        #expect(found.id == Self.someWallet)
        #expect(found.deviceKey == own.deviceKey)
    }

    /// The old device moved the wallet here: no delay, it signs at once.
    @Test func movedWalletIsTakenOn() async throws {
        let own = try client.createWallet()
        let moved = try await online([Self.someWallet: stateData(activeKey: own.deviceKey.key)]).recoverWallet(Self.someWallet)
        #expect(try await moved.status() == .active(recovery: nil))
        #expect(try client.wallet()?.id == Self.someWallet)
    }

    /// Its own wallet, moved away then back: read again like any other.
    @Test func walletMovedBackIsTakenOnAgain() async throws {
        let own = try client.createWallet()
        let back = try await online([own.id: stateData(activeKey: own.deviceKey.key)]).recoverWallet(own.id)
        #expect(back.id == own.id)
        #expect(try await back.status() == .active(recovery: nil))
    }

    /// Its own wallet, still with the key it moved to: nothing to take on.
    @Test func walletMovedAwayIsNotTakenBack() async throws {
        let own = try client.createWallet()
        await #expect(throws: EnclaveKitError.noRecovery) {
            try await online([own.id: stateData()]).recoverWallet(own.id)
        }
        #expect(try client.wallet()?.id == own.id)
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
        try client.forgetWallet(Self.someWallet)
        let pending = rotation(to: own.deviceKey.key, secondsAgo: 10)
        _ = try await online([Self.someWallet: stateData(rotation: pending)]).recoverWallet(Self.someWallet)

        try client.deleteDeviceKey()
        #expect(try client.wallet() == nil)
        #expect(try Keychain.read(client.forgottenAccount) == nil)

        // A new key starts with its own wallet.
        let next = try client.createWallet()
        #expect(next.deviceKey != own.deviceKey)
        #expect(try client.wallet()?.id == next.id)
    }

    /// The wallet on screen is never offered: this device's own, active on
    /// its key, then the one it took on.
    @Test func shownWalletIsNotRecoverable() async throws {
        let own = try client.createWallet()
        #expect(try await online([own.id: stateData(of: own.deviceKey.key)]).recoverableWallets().isEmpty)

        let device = online([Self.someWallet: stateData(rotation: rotation(to: own.deviceKey.key, secondsAgo: 10))])
        #expect(try await device.recoverableWallets().map(\.id) == [Self.someWallet])
        _ = try await device.recoverWallet(Self.someWallet)
        #expect(try await device.recoverableWallets().isEmpty)
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
            switch method {
            case "getAccountInfo":
                guard let address = (params as? [Any])?.first as? String else { return nil }
                return #"{"context":{"slot":1},"value":\#(accounts[address] ?? "null")}"#
            case "getProgramAccounts":
                return programAccountsJSON(Array(states.values), params: params)
            default:
                return nil
            }
        })
    }
}
