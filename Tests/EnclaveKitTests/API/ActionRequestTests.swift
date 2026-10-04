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
    let kora = Kora(url: URL(string: "http://kora.invalid")!)

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
        await #expect(throws: Wallet.SendError.insufficientFunds(available: 17_526_200)) {
            try await wallet.prepareTransfer(17_526_201, to: Self.recipient)
        }
    }

    @Test func emptyVaultHasNothingAvailable() async {
        await #expect(throws: Wallet.SendError.insufficientFunds(available: 0)) {
            try await wallet(balance: 0).prepareTransfer(1, to: Self.recipient)
        }
    }

    @Test func replacedKeyCannotPrepare() async throws {
        let other = try CompressedP256Key(bytes: [0x02] + [UInt8](repeating: 0xaa, count: 32))
        let wallet = wallet(state: accountJSON(data: stateData(activeKey: other)), balance: 20_000_000)
        await #expect(throws: Wallet.SendError.notActiveKey) {
            try await wallet.prepareTransfer(10_000_000, to: Self.recipient)
        }
    }

    /// Approved on the first action, authorized once the state exists: the
    /// enclave signs the approved ceiling, the relayer gets back only the fee.
    @Test func authorizeSignsTheApprovedCeiling() async throws {
        let kora = Kora(url: URL(string: "http://kora.invalid")!, transport: stub { method, params in
            switch method {
            case "getPayerSigner":
                #"{"signer_address":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8","payment_address":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"}"#
            case "getBlockhash":
                #"{"blockhash":"AByCTxLPRZPoyK22KdMxa3xkCbcNbeNWzVeEvh6UcJs9"}"#
            case "signAndSendTransaction":
                Self.checkTransferSol(params, nonce: 1, maxRelayerFee: 1_823_560, relayerFee: 10_000)
            default:
                nil
            }
        })
        let wallet = wallet(state: accountJSON(data: stateData()), kora: kora)
        let request = ActionRequest(maxFee: 1_823_560, action: .transferSol(to: Self.recipient, lamports: 1_000_000), wallet: wallet)

        let receipt = try await request.authorize()
        #expect(receipt.signature == "5VERv8NM")
        #expect(receipt.explorerURL.absoluteString == "https://explorer.solana.com/tx/5VERv8NM?cluster=devnet")
    }

    /// `SoftwareKey.test`'s wallet on a devnet that answers with `state` at
    /// the state's address and `balance` in the vault.
    func wallet(state: String = "null", balance: UInt64 = 0, kora: Kora? = nil) -> Wallet {
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
                #"{"context":{"slot":1},"value":[{"confirmationStatus":"confirmed","err":null}]}"#
            default:
                nil
            }
        })
        return Wallet(signer: SoftwareKey.test, kora: kora ?? self.kora, rpc: rpc)
    }

    /// Finds the `transfer_sol` arguments in the transaction Kora receives,
    /// checks them, and answers like Kora.
    static func checkTransferSol(_ params: Any?, nonce: UInt64, maxRelayerFee: UInt64, relayerFee: UInt64) -> String? {
        guard let base64 = (params as? [String: String])?["transaction"],
              let transaction = Data(base64Encoded: base64).map(Array.init),
              let start = transaction.firstRange(of: EnclaveKitProgram.discriminator(of: "transfer_sol"))?.upperBound
        else { return nil }
        // wallet_id 32, nonce, expires_at, max_relayer_fee, lamports, relayer_fee
        let field = { (offset: Int) in
            transaction[start + offset..<start + offset + 8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        }
        #expect(field(32) == nonce)
        #expect(field(48) == maxRelayerFee)
        #expect(field(64) == relayerFee)
        return #"{"signature":"5VERv8NM","signed_transaction":"AQ==","signer_pubkey":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"}"#
    }
}
