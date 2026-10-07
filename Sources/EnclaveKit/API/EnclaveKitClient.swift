//
//  EnclaveKitClient.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 04/10/2026.
//

import Foundation

/// The SDK's entry point: one per app, made from its config.
///
///     let enclaveKit = EnclaveKitClient(config: EnclaveKitConfig(relayerURL: url))
///     let wallet = try enclaveKit.wallet() ?? enclaveKit.createWallet()
public struct EnclaveKitClient: Sendable {
    public let config: EnclaveKitConfig
    /// Keychain account of the device key.
    let account: String
    /// Keychain account of the wallets this device guards.
    var guardedAccount: String { account + ".guarded" }
    /// Keychain account of the wallet this device recovered, absent while
    /// it has the one its key made.
    var recoveredAccount: String { account + ".recovered" }
    private let rpc: SolanaRPC
    private let kora: Kora

    public init(config: EnclaveKitConfig) {
        self.init(config: config, account: "wallet")
    }

    /// Tests pick their own account, away from the real wallet's, and may
    /// answer for the network.
    init(config: EnclaveKitConfig, account: String, transport: @escaping HTTPTransport = { try await URLSession.shared.data(for: $0) }) {
        self.config = config
        self.account = account
        rpc = SolanaRPC(url: config.cluster.rpcURL, transport: transport)
        kora = Kora(url: config.relayerURL, apiKey: config.relayerAPIKey, transport: transport)
    }

    /// The wallet of this device's key, `nil` until `createWallet()`: the
    /// one the key made, or the one it recovered. Reads the Keychain only:
    /// no network, no Face ID. The key outlives the app: a reinstall finds
    /// the same wallet.
    public func wallet() throws -> Wallet? {
        guard let key = try SecureEnclaveKey.load(account: account) else { return nil }
        return wallet(of: key, id: try recoveredID())
    }

    /// Makes the device key in the Secure Enclave. Throws `walletExists` if
    /// there is one already: the wallet is that key, it is never replaced.
    /// A device that replaces a lost one starts here too: a guardian
    /// proposes its `deviceKey`, then `recoverWallet(_:)`.
    public func createWallet() throws -> Wallet {
        guard try SecureEnclaveKey.load(account: account) == nil else { throw EnclaveKitError.walletExists }
        return wallet(of: try SecureEnclaveKey.create(account: account), id: nil)
    }

    /// Takes on the wallet `id`, scanned on a guardian's screen once the
    /// guardian proposed this device's `deviceKey`, or on the old device's
    /// once it moved the wallet here: this device's own wallet too, moved
    /// away then back. Kept in the Keychain next to the key: from now on
    /// `wallet()` returns it, `recovering` until `confirmRecovery()` after
    /// the delay, `active` at once after a move. Throws `noRecovery` if the
    /// wallet neither moved nor is moving to this device's key,
    /// `walletExists` while this device signs for another.
    public func recoverWallet(_ id: Wallet.ID) async throws -> Wallet {
        guard let key = try SecureEnclaveKey.load(account: account) else { throw EnclaveKitError.noWallet }
        let current = wallet(of: key, id: try recoveredID())
        if current.id != id, case .active = try await current.status() { throw EnclaveKitError.walletExists }
        let recovered = wallet(of: key, id: id)
        switch try await recovered.status() {
        case .recovering, .active: try Keychain.set(Data(id.bytes), account: recoveredAccount)
        case .notOnChainYet, .keyReplaced: throw EnclaveKitError.noRecovery
        }
        return recovered
    }

    /// Deletes this device's key, for good. The wallet stays on-chain with
    /// what it holds: only its guardians can move it to another key. The
    /// wallets this device guards lose it as guardian: their owners name
    /// another. The key goes last: a failure halfway never leaves a list a
    /// later key would take for its own.
    public func deleteDeviceKey() throws {
        try Keychain.delete(guardedAccount)
        try Keychain.delete(recoveredAccount)
        try Keychain.delete(account)
    }

    /// The wallets this device guards, in the order it took them on. Kept in
    /// the Keychain next to the key: a reinstall still finds them.
    public func guardedWallets() throws -> [GuardedWallet] {
        guard let key = try SecureEnclaveKey.load(account: account) else { return [] }
        return try guardedIDs().map { guardedWallet($0, key: key) }
    }

    /// Keeps the wallet `id`, scanned on its owner's device, among those
    /// this device guards. Its owner names this device with
    /// `prepareSetGuardians`, before or after. Throws `noWallet` before
    /// `createWallet()`: the guardian signs with this device's key.
    public func guardWallet(_ id: Wallet.ID) throws -> GuardedWallet {
        guard let key = try SecureEnclaveKey.load(account: account) else { throw EnclaveKitError.noWallet }
        let ids = try guardedIDs()
        if !ids.contains(id) {
            try Keychain.set(Data((ids + [id]).flatMap(\.bytes)), account: guardedAccount)
        }
        return guardedWallet(id, key: key)
    }

    /// Stops guarding the wallet `id`: `guardedWallets()` leaves it out. The
    /// wallet still names this device until its owner changes its
    /// guardians.
    public func forgetWallet(_ id: Wallet.ID) throws {
        let ids = try guardedIDs().filter { $0 != id }
        // An update with no bytes leaves the item as it was, on the Mac at
        // least: forgetting the last one deletes the list.
        if ids.isEmpty {
            try Keychain.delete(guardedAccount)
        } else {
            try Keychain.set(Data(ids.flatMap(\.bytes)), account: guardedAccount)
        }
    }

    /// 32 bytes per wallet, one after the other.
    private func guardedIDs() throws -> [Wallet.ID] {
        let bytes = try Keychain.read(guardedAccount).map(Array.init) ?? []
        return stride(from: 0, to: bytes.count - 31, by: 32).map { Wallet.ID(bytes: Array(bytes[$0..<$0 + 32])) }
    }

    private func recoveredID() throws -> Wallet.ID? {
        try Keychain.read(recoveredAccount).map { Wallet.ID(bytes: Array($0)) }
    }

    /// `id` `nil`: the wallet `key` made.
    private func wallet(of key: SecureEnclaveKey, id: Wallet.ID?) -> Wallet {
        Wallet(signer: key, walletId: id?.bytes, kora: kora, rpc: rpc, cluster: config.cluster, deleteKey: { try deleteDeviceKey() })
    }

    private func guardedWallet(_ id: Wallet.ID, key: SecureEnclaveKey) -> GuardedWallet {
        GuardedWallet(wallet: wallet(of: key, id: id))
    }
}
