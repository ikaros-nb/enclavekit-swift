//
//  WalletTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

struct WalletTests {
    let kora = Kora(url: URL(string: "http://kora.invalid")!)

    @Test func addressesComeFromTheKey() {
        let wallet = Wallet(signer: SoftwareKey.test, kora: kora)
        #expect(wallet.address.base58 == "hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK")
        #expect(wallet.explorerURL.absoluteString == "https://explorer.solana.com/address/hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK?cluster=devnet")
    }

    @Test func noAccountIsNotOnChainYet() async throws {
        #expect(try await wallet(stateAccount: "null").status() == .notOnChainYet)
    }

    /// Lamports sent to the state's address before the first action leave a
    /// System account there. Still no state: the first action must go through.
    @Test func accountOwnedByAnotherProgramIsNoState() async throws {
        let wallet = wallet(stateAccount: accountJSON(owner: "11111111111111111111111111111111", data: []))
        #expect(try await wallet.state() == nil)
        #expect(try await wallet.status() == .notOnChainYet)
    }

    @Test func stateOfThisKeyIsActive() async throws {
        let wallet = wallet(stateAccount: accountJSON(data: stateData(attested: true)))
        #expect(try await wallet.status() == .active(attested: true))
    }

    @Test func stateOfAnotherKeyIsReplaced() async throws {
        let other = try CompressedP256Key(bytes: [0x02] + [UInt8](repeating: 0xaa, count: 32))
        let wallet = wallet(stateAccount: accountJSON(data: stateData(activeKey: other)))
        #expect(try await wallet.status() == .keyReplaced)
    }

    /// The wallet of `SoftwareKey.test`, whose RPC answers the one
    /// `getAccountInfo` of its state with `value`.
    func wallet(stateAccount value: String) -> Wallet {
        let rpc = SolanaRPC(transport: stub(
            expecting: """
            {"jsonrpc":"2.0","id":1,"method":"getAccountInfo",
             "params":["EKyNGE7ecVLS8GYLf13LypzugwLbRQuRVNvNQdu9jQxF",{"commitment":"confirmed","encoding":"base64"}]}
            """,
            reply: #"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":\#(value)}}"#
        ))
        return Wallet(signer: SoftwareKey.test, kora: kora, rpc: rpc)
    }
}
