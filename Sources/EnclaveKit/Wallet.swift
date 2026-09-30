//
//  Wallet.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import EnclaveKitCore
import Foundation

/// A smart wallet seen from the device: the key that authorises it, the
/// relayer that pays for it, the RPC that reads it.
public struct Wallet: Sendable {
    public enum SendError: Error, Equatable {
        /// The state names another key: the wallet rotated away from this one.
        case notActiveKey
        /// Landed and failed: the relayer paid the fee, nothing else happened.
        case failed(signature: String, TransactionError)
        /// Still unknown after its blockhash expired: it can no longer land.
        case notConfirmed(signature: String)
    }

    /// 5 000 lamports per signature: the relayer's Ed25519 one and the
    /// secp256r1 one the precompile checks.
    static let transactionFee: UInt64 = 10_000
    /// Seconds the enclave's authorisation stays valid on-chain.
    static let authorizationTTL: Int64 = 120
    /// A blockhash lives 150 slots, about a minute: past this the
    /// transaction can no longer land.
    static let confirmationTimeout: Duration = .seconds(90)

    public let signer: any Signer
    /// SHA-256 of the key that made the wallet: the seed of both addresses.
    public let walletId: [UInt8]
    public let programId: PublicKey
    private let rpc: SolanaRPC
    private let kora: Kora

    public init(signer: any Signer, kora: Kora, rpc: SolanaRPC = SolanaRPC(), programId: PublicKey = EnclaveKitProgram.id) {
        self.signer = signer
        self.walletId = EnclaveKitCore.walletId(of: signer.publicKey)
        self.programId = programId
        self.rpc = rpc
        self.kora = kora
    }

    /// Where to send SOL to this wallet. Receives before the first action.
    public var vaultAddress: PublicKey {
        EnclaveKitProgram.vaultAddress(walletId: walletId, programId: programId)
    }

    public func balance() async throws -> UInt64 {
        try await rpc.balance(vaultAddress)
    }

    /// `nil` until the first action creates the state. An account the
    /// program does not own is no state either: anyone can send lamports to
    /// the address before it exists.
    public func state() async throws -> SmartWallet? {
        let address = EnclaveKitProgram.walletAddress(walletId: walletId, programId: programId)
        guard let account = try await rpc.accountInfo(address), account.owner == programId else { return nil }
        return try SmartWallet(data: account.data)
    }

    /// Signs `action` with the enclave, has Kora send it, returns once
    /// confirmed. One Face ID.
    public func send(_ action: Action) async throws -> String {
        // What the preimage binds: the on-chain nonce and the relayer's
        // ceiling. The relayer advances the fee, and on the first action the
        // rent of the state; the vault pays both back.
        let state = try await state()
        if let state, state.activeKey != signer.publicKey { throw SendError.notActiveKey }
        let rent = state == nil ? try await rpc.minimumBalanceForRentExemption(space: SmartWallet.space) : 0
        let relayerFee = rent + Self.transactionFee
        let relayer = try await kora.payerSigner()
        let preimage = Preimage(
            programId: programId,
            walletId: walletId,
            nonce: state?.nonce ?? 0,
            expiresAt: Int64(Date.now.timeIntervalSince1970) + Self.authorizationTTL,
            maxRelayerFee: relayerFee,
            action: action
        )
        // Before Face ID: an action without handler throws here.
        let instruction = try EnclaveKitProgram.instruction(executing: preimage, relayer: relayer, relayerFee: relayerFee)

        let signature = try await signer.sign(preimage.bytes)
        // Not signed by the enclave: fetched after Face ID, it keeps its whole life.
        let blockhash = try await kora.blockhash()
        let message = Message(
            instructions: [
                Secp256r1Program.instruction(publicKey: signer.publicKey, signature: signature, message: preimage.bytes),
                instruction,
            ],
            payer: relayer,
            recentBlockhash: blockhash
        )
        let transaction = try await kora.signAndSend(message)
        try await confirm(transaction)
        return transaction
    }

    private func confirm(_ signature: String) async throws {
        let deadline = ContinuousClock.now + Self.confirmationTimeout
        while ContinuousClock.now < deadline {
            if let status = try await rpc.signatureStatus(signature) {
                if let error = status.error { throw SendError.failed(signature: signature, error) }
                if status.confirmationStatus == .confirmed || status.confirmationStatus == .finalized { return }
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw SendError.notConfirmed(signature: signature)
    }
}
