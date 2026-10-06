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
    private let rpc: SolanaRPC
    private let kora: Kora

    public init(config: EnclaveKitConfig) {
        self.init(config: config, account: "wallet")
    }

    /// Tests pick their own account, away from the real wallet's.
    init(config: EnclaveKitConfig, account: String) {
        self.config = config
        self.account = account
        rpc = SolanaRPC(url: config.cluster.rpcURL)
        kora = Kora(url: config.relayerURL, apiKey: config.relayerAPIKey)
    }

    /// The wallet of this device's key, `nil` until `createWallet()`. Reads
    /// the Keychain only: no network, no Face ID. The key outlives the app:
    /// a reinstall finds the same wallet.
    public func wallet() throws -> Wallet? {
        try SecureEnclaveKey.load(account: account).map(wallet(of:))
    }

    /// Makes the device key in the Secure Enclave. Throws `walletExists` if
    /// there is one already: the wallet is that key, it is never replaced.
    public func createWallet() throws -> Wallet {
        guard try SecureEnclaveKey.load(account: account) == nil else { throw EnclaveKitError.walletExists }
        return wallet(of: try SecureEnclaveKey.create(account: account))
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

    /// 32 bytes per wallet, one after the other.
    private func guardedIDs() throws -> [Wallet.ID] {
        let bytes = try Keychain.read(guardedAccount).map(Array.init) ?? []
        return stride(from: 0, to: bytes.count - 31, by: 32).map { Wallet.ID(bytes: Array(bytes[$0..<$0 + 32])) }
    }

    private func wallet(of key: SecureEnclaveKey) -> Wallet {
        Wallet(signer: key, kora: kora, rpc: rpc, cluster: config.cluster)
    }

    private func guardedWallet(_ id: Wallet.ID, key: SecureEnclaveKey) -> GuardedWallet {
        GuardedWallet(wallet: Wallet(signer: key, walletId: id.bytes, kora: kora, rpc: rpc, cluster: config.cluster))
    }
}
