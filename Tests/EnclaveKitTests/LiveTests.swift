//
//  LiveTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import EnclaveKit
import EnclaveKitCore
import Foundation
import Testing

/// Read-only calls against a running Kora and devnet: they check the
/// stubs' JSON against the real servers. Off unless `KORA_URL` is set:
///
///     KORA_URL=http://127.0.0.1:8080 swift test --filter LiveTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KORA_URL"] != nil))
struct LiveTests {
    let kora: Kora
    let rpc = SolanaRPC()

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = try #require(environment["KORA_URL"].flatMap(URL.init))
        kora = Kora(url: url, apiKey: environment["KORA_API_KEY"])
    }

    @Test func koraPayerHoldsLamports() async throws {
        let payer = try await kora.payerSigner()
        #expect(try await rpc.balance(payer) > 0)
    }

    @Test func koraGivesABlockhash() async throws {
        #expect(try await kora.blockhash().bytes.count == 32)
    }

    @Test func programIsDeployed() async throws {
        let program = try #require(try await rpc.accountInfo(EnclaveKitProgram.id))
        #expect(program.owner == (try PublicKey(base58: "BPFLoaderUpgradeab1e11111111111111111111111")))
    }

    /// A wallet id nobody enrolled: its state does not exist.
    @Test func unknownWalletHasNoState() async throws {
        let walletId = [UInt8](repeating: 0xee, count: 32)
        #expect(try await rpc.accountInfo(EnclaveKitProgram.walletAddress(walletId: walletId)) == nil)
    }

    /// The rent grows with the size. No fixed value: the cluster sets it.
    @Test func rentGrowsWithSpace() async throws {
        let empty = try await rpc.minimumBalanceForRentExemption(space: 0)
        let state = try await rpc.minimumBalanceForRentExemption(space: 229)
        #expect(empty > 0)
        #expect(state > empty)
    }

    /// 64 zero bytes: a well-formed signature no transaction has.
    @Test func unknownSignatureHasNoStatus() async throws {
        #expect(try await rpc.signatureStatus(String(repeating: "1", count: 64)) == nil)
    }
}
