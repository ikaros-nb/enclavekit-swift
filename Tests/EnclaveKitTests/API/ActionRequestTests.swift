//
//  ActionRequestTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

struct ActionRequestTests {
    static let recipient = try! PublicKey(bytes: [UInt8](repeating: 0x77, count: 32))
    static let sent = Receipt(signature: "5VERv8NM", explorerURL: URL(string: "https://explorer.solana.com/tx/5VERv8NM?cluster=devnet")!)

    @Test func firstTransferPaysTheStateRent() async throws {
        let request = try await wallet(balance: 20_000_000).prepareTransfer(10_000_000, to: Self.recipient)
        #expect(request.maxFee == Lamports(1_813_560 + 10_000))
        #expect(request.summary == "Send 0.01 SOL to 93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8")
    }

    @Test func laterTransferPaysTheFeeOnly() async throws {
        let wallet = wallet(state: accountJSON(data: stateData()), balance: 20_000_000)
        #expect(try await wallet.prepareTransfer(10_000_000, to: Self.recipient).maxFee == 10_000)
    }

    /// 20 000 000 − 1 823 560 of fee ceiling − 650 240 of vault rent.
    @Test func vaultKeepsItsRent() async throws {
        let wallet = wallet(balance: 20_000_000)
        _ = try await wallet.prepareTransfer(17_526_200, to: Self.recipient)
        await #expect(throws: EnclaveKitError.insufficientFunds(available: 17_526_200)) {
            try await wallet.prepareTransfer(17_526_201, to: Self.recipient)
        }
    }

    @Test func emptyVaultHasNothingAvailable() async {
        await #expect(throws: EnclaveKitError.insufficientFunds(available: 0)) {
            try await wallet(balance: 0).prepareTransfer(1, to: Self.recipient)
        }
    }

    @Test func replacedKeyCannotPrepare() async throws {
        let other = try CompressedP256Key(bytes: [0x02] + [UInt8](repeating: 0xaa, count: 32))
        let wallet = wallet(state: accountJSON(data: stateData(activeKey: other)), balance: 20_000_000)
        await #expect(throws: EnclaveKitError.keyReplaced) {
            try await wallet.prepareTransfer(10_000_000, to: Self.recipient)
        }
    }

    /// A guardian's device signs for someone else's wallet, a rotation
    /// proposal only: it never spends.
    @Test func guardianProposesButNeverSpends() async throws {
        let guardian = SoftwareKey()
        let wallet = wallet(state: accountJSON(data: stateData(guardian: guardian.publicKey)), balance: 20_000_000, signer: guardian)
        #expect(try await wallet.prepare(.proposeRotation(newKey: SoftwareKey().publicKey)).maxFee == 10_000)
        await #expect(throws: EnclaveKitError.self) {
            try await wallet.prepareTransfer(10_000_000, to: Self.recipient)
        }
    }

    @Test func strangerCannotPropose() async throws {
        let wallet = wallet(state: accountJSON(data: stateData()), balance: 20_000_000, signer: SoftwareKey())
        await #expect(throws: EnclaveKitError.self) {
            try await wallet.prepare(.proposeRotation(newKey: SoftwareKey().publicKey))
        }
    }

    /// Nothing for the enclave to sign, so no Face ID: the transaction holds
    /// `confirm_rotation` alone.
    @Test func confirmRotationSignsNothing() async throws {
        let kora = Self.relayer { params in
            let transaction = Self.transaction(params)
            #expect(transaction.firstRange(of: EnclaveKitProgram.discriminator(of: "confirm_rotation")) != nil)
            #expect(transaction.firstRange(of: Secp256r1Program.id.bytes) == nil)
        }
        #expect(try await wallet(kora: kora).confirmRotation() == Self.sent)
    }

    /// Approved on the first action, authorized once the state exists: the
    /// enclave signs the approved ceiling, the relayer gets back only the fee.
    @Test func authorizeSignsTheApprovedCeiling() async throws {
        let kora = Self.relayer { params in
            Self.checkTransferSol(params, nonce: 1, maxRelayerFee: 1_823_560, relayerFee: 10_000)
        }
        let wallet = wallet(state: accountJSON(data: stateData()), kora: kora)
        let request = ActionRequest(maxFee: 1_823_560, action: .transferSol(to: Self.recipient, lamports: 1_000_000), wallet: wallet)
        #expect(try await request.authorize() == Self.sent)
    }

    /// The fee is paid, the receipt still leads to the explorer.
    @Test func failureOnChainKeepsTheReceipt() async throws {
        let wallet = wallet(state: accountJSON(data: stateData()), err: #"{"InstructionError":[1,{"Custom":6003}]}"#)
        let request = ActionRequest(maxFee: 10_000, action: .transferSol(to: Self.recipient, lamports: 1_000_000), wallet: wallet)
        await #expect(throws: EnclaveKitError.failed(Self.sent, reason: "instruction 1 failed with error 6003")) {
            try await request.authorize()
        }
    }

    /// Kora simulates before sending: what fails there never leaves it.
    @Test func relayerRejectionSendsNothing() async throws {
        let reason = "Invalid transaction: Transaction simulation failed: Error processing Instruction 1: custom program error: 0x1773"
        let wallet = wallet(state: accountJSON(data: stateData()), kora: Self.relayer(errors: ["signAndSendTransaction": reason]))
        let request = ActionRequest(maxFee: 10_000, action: .transferSol(to: Self.recipient, lamports: 1_000_000), wallet: wallet)
        await #expect(throws: EnclaveKitError.rejected(reason: reason)) {
            try await request.authorize()
        }
    }

    /// `SoftwareKey.test`'s wallet, seen from `signer`, on a devnet that
    /// answers with `state` at the state's address, `balance` in the vault,
    /// and `err` for any sent transaction.
    func wallet(state: String = "null", balance: UInt64 = 0, err: String = "null", kora: Kora? = nil, signer: any Signer = SoftwareKey.test) -> Wallet {
        let rpc = SolanaRPC(transport: stub { method, params in
            switch method {
            case "getAccountInfo":
                #"{"context":{"slot":1},"value":\#(state)}"#
            case "getBalance":
                #"{"context":{"slot":1},"value":\#(balance)}"#
            case "getMinimumBalanceForRentExemption":
                switch (params as? [Int])?.first {
                case 0: "650240"
                case SmartWallet.space: "1813560"
                default: nil
                }
            case "getSignatureStatuses":
                #"{"context":{"slot":1},"value":[{"confirmationStatus":"confirmed","err":\#(err)}]}"#
            default:
                nil
            }
        })
        return Wallet(signer: signer, walletId: walletId(of: SoftwareKey.test.publicKey), kora: kora ?? Self.relayer(), rpc: rpc)
    }

    /// Kora as the tests see it: `check` gets what `signAndSendTransaction`
    /// receives, the answer is always `sent`, unless `errors` says otherwise.
    static func relayer(errors: [String: String] = [:], check: @escaping @Sendable (_ params: Any?) -> Void = { _ in }) -> Kora {
        Kora(url: URL(string: "http://kora.invalid")!, transport: stub(errors: errors) { method, params in
            switch method {
            case "getPayerSigner":
                return #"{"signer_address":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8","payment_address":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"}"#
            case "getBlockhash":
                return #"{"blockhash":"AByCTxLPRZPoyK22KdMxa3xkCbcNbeNWzVeEvh6UcJs9"}"#
            case "signAndSendTransaction":
                check(params)
                return #"{"signature":"5VERv8NM","signed_transaction":"AQ==","signer_pubkey":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"}"#
            default:
                return nil
            }
        })
    }

    /// The transaction Kora receives, empty if there is none.
    static func transaction(_ params: Any?) -> [UInt8] {
        (params as? [String: String])?["transaction"].flatMap { Data(base64Encoded: $0) }.map(Array.init) ?? []
    }

    /// Finds the `transfer_sol` arguments in the transaction Kora receives
    /// and checks them.
    static func checkTransferSol(_ params: Any?, nonce: UInt64, maxRelayerFee: UInt64, relayerFee: UInt64) {
        let transaction = transaction(params)
        guard let start = transaction.firstRange(of: EnclaveKitProgram.discriminator(of: "transfer_sol"))?.upperBound else {
            Issue.record("no transfer_sol in what Kora received")
            return
        }
        // wallet_id 32, nonce, expires_at, max_relayer_fee, lamports, relayer_fee
        let field = { (offset: Int) in
            transaction[start + offset..<start + offset + 8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        }
        #expect(field(32) == nonce)
        #expect(field(48) == maxRelayerFee)
        #expect(field(64) == relayerFee)
    }
}
