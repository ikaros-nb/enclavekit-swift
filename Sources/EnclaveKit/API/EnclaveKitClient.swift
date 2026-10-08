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
    /// Keychain account of the wallets `forgetWallet(_:)` hid.
    var forgottenAccount: String { account + ".forgotten" }
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
    /// proposes its `deviceKey`, `recoverableWallets()` finds the wallet,
    /// `recoverWallet(_:)` takes it on.
    public func createWallet() throws -> Wallet {
        guard try SecureEnclaveKey.load(account: account) == nil else { throw EnclaveKitError.walletExists }
        return wallet(of: try SecureEnclaveKey.create(account: account), id: nil)
    }

    /// Takes on the wallet `id`, one of `recoverableWallets()`: a guardian
    /// proposed this device's `deviceKey`, or the old device moved the
    /// wallet here. This device's own wallet too, moved away then back.
    /// Kept in the Keychain next to the key: from now on
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
        try Keychain.delete(forgottenAccount)
        try Keychain.delete(recoveredAccount)
        try Keychain.delete(account)
    }

    /// The wallets waiting for this device's key, read on-chain: the old
    /// device moved one here, or a guardian proposed this key for one. The
    /// wallet `wallet()` returns is left out, and so is a lapsed proposal.
    /// `recoverWallet(_:)` takes one on. Empty before `createWallet()`:
    /// nothing can name a key that does not exist yet.
    public func recoverableWallets() async throws -> [Wallet] {
        guard let key = try SecureEnclaveKey.load(account: account) else { return [] }
        return try await recoverableWallets(of: key, besides: wallet(of: key, id: try recoveredID()).id)
    }

    /// The same for any key, `shown` left out.
    func recoverableWallets(of key: any Signer, besides shown: Wallet.ID) async throws -> [Wallet] {
        let states = try await states(matchingAny: [.activeKey(key.publicKey), .proposal(to: key.publicKey)])
        return states.compactMap { state in
            let wallet = wallet(of: key, id: Wallet.ID(bytes: state.walletId))
            guard wallet.id != shown else { return nil }
            switch wallet.status(in: state) {
            case .active, .recovering: return wallet
            case .notOnChainYet, .keyReplaced: return nil
            }
        }
    }

    /// The wallets that name this device among their guardians, read
    /// on-chain: an owner adds this device's key, and the wallet shows here
    /// with nothing more to do; removed, it goes. Those `forgetWallet(_:)`
    /// hid stay out. Empty before `createWallet()`.
    public func guardedWallets() async throws -> [GuardedWallet] {
        guard let key = try SecureEnclaveKey.load(account: account) else { return [] }
        return try await guardedWallets(of: key)
    }

    /// The same for any key.
    func guardedWallets(of key: any Signer) async throws -> [GuardedWallet] {
        let forgotten = try forgottenIDs()
        let filters = (0..<maxGuardians).map { SmartWallet.Filter.guardian(key.publicKey, slot: $0) }
        return try await states(matchingAny: filters)
            .map { Wallet.ID(bytes: $0.walletId) }
            .filter { !forgotten.contains($0) }
            .map { GuardedWallet(wallet: wallet(of: key, id: $0)) }
    }

    /// Hides the wallet `id` from `guardedWallets()` for good: anyone can
    /// name this device's key, once shown, as their guardian. The wallet
    /// still names it until its owner changes its guardians, and named
    /// again later, it stays hidden. Kept in the Keychain next to the key.
    public func forgetWallet(_ id: Wallet.ID) throws {
        let ids = try forgottenIDs()
        guard !ids.contains(id) else { return }
        try Keychain.set(Data((ids + [id]).flatMap(\.bytes)), account: forgottenAccount)
    }

    /// 32 bytes per wallet, one after the other.
    private func forgottenIDs() throws -> [Wallet.ID] {
        let bytes = try Keychain.read(forgottenAccount).map(Array.init) ?? []
        return stride(from: 0, to: bytes.count - 31, by: 32).map { Wallet.ID(bytes: Array(bytes[$0..<$0 + 32])) }
    }

    private func recoveredID() throws -> Wallet.ID? {
        try Keychain.read(recoveredAccount).map { Wallet.ID(bytes: Array($0)) }
    }

    /// The wallet states that match one of `filters` at least, each once,
    /// in the order of their IDs: a list that keeps its order from one read
    /// to the next. One query per filter, all at once.
    private func states(matchingAny filters: [SmartWallet.Filter]) async throws -> [SmartWallet] {
        let accounts = try await withThrowingTaskGroup(of: [AccountInfo].self) { group in
            for filter in filters {
                group.addTask {
                    try await rpc.programAccounts(config.cluster.programId, dataSize: SmartWallet.space, offset: filter.offset, bytes: filter.bytes)
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        // The program lets a wallet name a key in two slots.
        let states = try accounts.map { try SmartWallet(data: $0.data) }
        return Dictionary(states.map { ($0.walletId, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { $0.walletId.lexicographicallyPrecedes($1.walletId) }
    }

    /// `id` `nil`: the wallet `key` made.
    private func wallet(of key: any Signer, id: Wallet.ID?) -> Wallet {
        Wallet(signer: key, walletId: id?.bytes, kora: kora, rpc: rpc, cluster: config.cluster, deleteKey: { try deleteDeviceKey() })
    }
}
