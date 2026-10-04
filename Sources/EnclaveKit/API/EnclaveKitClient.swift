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

    private func wallet(of key: SecureEnclaveKey) -> Wallet {
        Wallet(signer: key, kora: kora, rpc: rpc, cluster: config.cluster)
    }
}
