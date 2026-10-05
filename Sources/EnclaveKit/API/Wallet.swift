//
//  Wallet.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import Foundation

/// A smart wallet seen from one device: the device's key, which signs as
/// the wallet's owner or as one of its guardians, the relayer that pays,
/// the RPC that reads it.
public struct Wallet: Sendable {
    public enum Status: Equatable, Sendable {
        /// No action yet. The address already receives; the first send
        /// creates the account, its rent part of that send's fee.
        case notOnChainYet
        /// `attested`: an App Attest receipt vouches that the key lives in
        /// a genuine Secure Enclave.
        case active(attested: Bool)
        /// The wallet rotated to another key: this device can no longer sign.
        case keyReplaced
    }

    /// 5 000 lamports per signature: the relayer's Ed25519 one and the
    /// secp256r1 one the precompile checks.
    static let transactionFee: UInt64 = 10_000
    /// Seconds the enclave's authorisation stays valid on-chain.
    static let authorizationTTL: Int64 = 120
    /// A blockhash lives 150 slots, about a minute: past this the
    /// transaction can no longer land.
    static let confirmationTimeout: Duration = .seconds(90)

    let signer: any Signer
    /// SHA-256 of the key that made the wallet: the seed of both addresses.
    /// A rotation never changes it.
    let walletId: [UInt8]
    let cluster: Cluster
    private let rpc: SolanaRPC
    private let kora: Kora

    /// `walletId` defaults to the wallet `signer` made. Another one when the
    /// device recovered a wallet, or guards it.
    init(signer: any Signer, walletId: [UInt8]? = nil, kora: Kora, rpc: SolanaRPC = SolanaRPC(), cluster: Cluster = .devnet) {
        self.signer = signer
        self.walletId = walletId ?? EnclaveKit.walletId(of: signer.publicKey)
        self.cluster = cluster
        self.rpc = rpc
        self.kora = kora
    }

    var programId: PublicKey { cluster.programId }

    /// Where to send SOL to this wallet: the vault. Receives before the
    /// first action.
    public var address: PublicKey {
        EnclaveKitProgram.vaultAddress(walletId: walletId, programId: programId)
    }

    /// The vault's page: balance, every transaction in and out.
    public var explorerURL: URL {
        cluster.explorerURL("address/\(address)")
    }

    public func balance() async throws -> Lamports {
        Lamports(try await rpc.balance(address))
    }

    public func status() async throws -> Status {
        guard let state = try await state() else { return .notOnChainYet }
        guard state.activeKey == signer.publicKey else { return .keyReplaced }
        return .active(attested: state.attested)
    }

    /// `nil` until the first action creates the state. An account the
    /// program does not own is no state either: anyone can send lamports to
    /// the address before it exists.
    func state() async throws -> SmartWallet? {
        let stateAddress = EnclaveKitProgram.walletAddress(walletId: walletId, programId: programId)
        guard let account = try await rpc.accountInfo(stateAddress), account.owner == programId else { return nil }
        return try SmartWallet(data: account.data)
    }

    /// A transfer for the user to approve. Reads the state and the balance,
    /// and refuses here, before any Face ID, what the vault cannot pay.
    public func prepareTransfer(_ amount: Lamports, to recipient: PublicKey) async throws -> ActionRequest {
        try await prepare(.transferSol(to: recipient, lamports: amount.value), spending: amount)
    }

    /// The vault pays `amount`, the relayer's refund, and keeps its own rent:
    /// below it the runtime rejects the transaction, and only `sweep_vault`
    /// may empty it.
    func prepare(_ action: Action, spending amount: Lamports = 0) async throws -> ActionRequest {
        let state = try await state()
        try requireAuthority(over: state, for: action)
        let maxFee = try await relayerFee(state)
        let reserved = maxFee + (try await rpc.minimumBalanceForRentExemption(space: 0))
        let balance = try await rpc.balance(address)
        guard balance >= reserved, amount.value <= balance - reserved else {
            throw EnclaveKitError.insufficientFunds(available: Lamports(balance > reserved ? balance - reserved : 0))
        }
        return ActionRequest(maxFee: Lamports(maxFee), action: action, wallet: self)
    }

    /// Signs `action` with the enclave, has Kora send it, returns once
    /// confirmed. One Face ID. `maxRelayerFee` is the ceiling the user
    /// approved; the nonce and the expiry are read now, right before.
    func execute(_ action: Action, maxRelayerFee: UInt64) async throws -> Receipt {
        let state = try await state()
        try requireAuthority(over: state, for: action)
        // Lower than approved if another send created the state meanwhile.
        let relayerFee = min(try await relayerFee(state), maxRelayerFee)
        let relayer = try await kora.payerSigner()
        let preimage = Preimage(
            programId: programId,
            walletId: walletId,
            nonce: state?.nonce ?? 0,
            expiresAt: Int64(Date.now.timeIntervalSince1970) + Self.authorizationTTL,
            maxRelayerFee: maxRelayerFee,
            action: action
        )
        // Before Face ID: an action without handler throws here.
        let instruction = try EnclaveKitProgram.instruction(executing: preimage, relayer: relayer, relayerFee: relayerFee)

        let signature = try await signer.sign(preimage.bytes)
        return try await send(
            [
                Secp256r1Program.instruction(publicKey: signer.publicKey, signature: signature, message: preimage.bytes),
                instruction,
            ],
            payer: relayer
        )
    }

    /// Swaps in the key a guardian proposed, once the timelock has passed.
    /// Nothing to sign, no Face ID: anyone may send it, the relayer pays the
    /// fee and gets nothing back.
    func confirmRotation() async throws -> Receipt {
        try await send(
            [EnclaveKitProgram.confirmRotation(walletId: walletId, programId: programId)],
            payer: try await kora.payerSigner()
        )
    }

    /// The active key signs every action. A guardian only proposes a new
    /// key. Before the first action there is no state: the key that made
    /// the wallet creates it.
    private func requireAuthority(over state: SmartWallet?, for action: Action) throws {
        guard let state, state.activeKey != signer.publicKey else { return }
        if case .proposeRotation = action, state.guardians.contains(.p256(signer.publicKey)) { return }
        throw EnclaveKitError.keyReplaced
    }

    /// Kora signs as fee payer and sends, then the cluster confirms.
    private func send(_ instructions: [Instruction], payer relayer: PublicKey) async throws -> Receipt {
        // Not signed by the enclave: fetched last, after any Face ID, it
        // keeps its whole life.
        let blockhash = try await kora.blockhash()
        let message = Message(instructions: instructions, payer: relayer, recentBlockhash: blockhash)
        let receipt: Receipt
        do {
            receipt = self.receipt(try await kora.signAndSend(message))
        } catch let JSONRPCError.server(_, reason) {
            // Kora simulates first: what fails there is never sent.
            throw EnclaveKitError.rejected(reason: reason)
        }
        try await confirm(receipt)
        return receipt
    }

    private func receipt(_ signature: String) -> Receipt {
        Receipt(signature: signature, explorerURL: cluster.explorerURL("tx/\(signature)"))
    }

    /// What the relayer advances and the vault pays back: the fee, and on
    /// the first action the rent of the state.
    private func relayerFee(_ state: SmartWallet?) async throws -> UInt64 {
        let rent = state == nil ? try await rpc.minimumBalanceForRentExemption(space: SmartWallet.space) : 0
        return rent + Self.transactionFee
    }

    private func confirm(_ receipt: Receipt) async throws {
        let deadline = ContinuousClock.now + Self.confirmationTimeout
        while ContinuousClock.now < deadline {
            if let status = try await rpc.signatureStatus(receipt.signature) {
                if let error = status.error { throw EnclaveKitError.failed(receipt, reason: "\(error)") }
                if status.confirmationStatus == .confirmed || status.confirmationStatus == .finalized { return }
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw EnclaveKitError.notConfirmed(receipt)
    }
}
