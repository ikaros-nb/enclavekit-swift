//
//  DiscoveryTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 08/10/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

/// What a device finds on-chain from its key alone: the wallets it guards,
/// those waiting for it. A software key stands for the device's; the
/// forgotten wallets go to the Mac's Keychain, under an account of the
/// test's own.
final class DiscoveryTests {
    let device = SoftwareKey()
    let account = "test-\(UUID().uuidString)"

    deinit {
        try? Keychain.delete(client([]).forgottenAccount)
    }

    /// In any slot, each wallet once, in the order of their IDs. A wallet
    /// this key signs for, or moves to, is not guarded.
    @Test func guardedWalletsNameThisKey() async throws {
        let first = SoftwareKey().publicKey
        let second = SoftwareKey().publicKey
        let states = [
            stateData(of: first, guardian: device.publicKey, inSlots: [0]),
            stateData(of: second, guardian: device.publicKey, inSlots: [1, 2]),
            stateData(of: SoftwareKey().publicKey, guardian: SoftwareKey().publicKey),
            stateData(of: SoftwareKey().publicKey, activeKey: device.publicKey),
            stateData(of: SoftwareKey().publicKey, rotation: rotation(to: device.publicKey, secondsAgo: 10)),
        ]
        let guarded = try await client(states).guardedWallets(of: device)
        #expect(guarded.map(\.id) == [id(first), id(second)].sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) })
        #expect(guarded.allSatisfy { $0.wallet.deviceKey == DeviceKey(device.publicKey) })
    }

    /// Forgetting twice changes nothing.
    @Test func forgottenWalletsStayOut() async throws {
        let first = SoftwareKey().publicKey
        let second = SoftwareKey().publicKey
        let client = client([stateData(of: first, guardian: device.publicKey), stateData(of: second, guardian: device.publicKey)])
        try client.forgetWallet(id(first))
        try client.forgetWallet(id(first))
        #expect(try await client.guardedWallets(of: device).map(\.id) == [id(second)])
        try client.forgetWallet(id(second))
        #expect(try await client.guardedWallets(of: device).isEmpty)
    }

    /// Moved to this key, or a guardian proposed it. Not a lapsed proposal,
    /// not one toward another key, not the wallet on screen.
    @Test func recoverableWalletsWaitForThisKey() async throws {
        let moved = SoftwareKey().publicKey
        let proposed = SoftwareKey().publicKey
        let shown = SoftwareKey().publicKey
        let states = [
            stateData(of: moved, activeKey: device.publicKey),
            stateData(of: proposed, rotation: rotation(to: device.publicKey, secondsAgo: 10)),
            stateData(of: SoftwareKey().publicKey, rotation: rotation(to: device.publicKey, secondsAgo: 60 + 7 * 24 * 60 * 60 + 1)),
            stateData(of: SoftwareKey().publicKey, rotation: rotation(to: SoftwareKey().publicKey, secondsAgo: 10)),
            stateData(of: shown, activeKey: device.publicKey),
        ]
        let found = try await client(states).recoverableWallets(of: device, besides: id(shown))
        #expect(Set(found.map(\.id)) == [id(moved), id(proposed)])
        #expect(found.count == 2)
    }

    /// This device's client, on a devnet that holds `states` and no other
    /// account.
    func client(_ states: [[UInt8]]) -> EnclaveKitClient {
        EnclaveKitClient(
            config: EnclaveKitConfig(relayerURL: URL(string: "http://kora.invalid")!),
            account: account,
            transport: stub { method, params in
                method == "getProgramAccounts" ? programAccountsJSON(states, params: params) : nil
            }
        )
    }

    /// The wallet `key` made.
    func id(_ key: CompressedP256Key) -> Wallet.ID {
        Wallet.ID(bytes: walletId(of: key))
    }
}
