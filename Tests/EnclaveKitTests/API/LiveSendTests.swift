//
//  LiveSendTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import EnclaveKit
import Foundation
import Testing

/// A real `transfer_sol` through Kora: it spends devnet lamports and shows in
/// the explorer. Off unless `LIVE_SEND` is set as well as `KORA_URL`:
///
///     KORA_URL=http://127.0.0.1:8080 LIVE_SEND=1 swift test --filter LiveSendTests
@Suite(.enabled(if: ["KORA_URL", "LIVE_SEND"].allSatisfy { ProcessInfo.processInfo.environment[$0] != nil }))
struct LiveSendTests {
    let wallet: Wallet
    let rpc = SolanaRPC()

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(environment["KORA_URL"].flatMap(URL.init))
        wallet = Wallet(signer: SoftwareKey.test, kora: Kora(url: url, apiKey: environment["KORA_API_KEY"]))
    }

    /// First run: the state is created, its rent refunded to Kora. Later
    /// runs: nonce + 1 each time.
    @Test func transferSolLands() async throws {
        let vault = wallet.address
        try #require(
            try await wallet.balance() >= 5_000_000,
            "fund the vault: solana transfer \(vault) 0.05 --allow-unfunded-recipient -u devnet"
        )
        let nonce = try await wallet.state()?.nonce ?? 0
        // A new account every run. 0.001 SOL is above the rent-exempt minimum.
        let to = try PublicKey(bytes: (0..<32).map { _ in .random(in: 0...255) })

        let request = try await wallet.prepareTransfer(1_000_000, to: to)
        let receipt = try await request.authorize()
        print(receipt.explorerURL)

        #expect(try await rpc.balance(to) == 1_000_000)
        #expect(try await wallet.state()?.nonce == nonce + 1)
    }
}
