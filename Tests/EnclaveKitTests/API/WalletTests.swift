//
//  WalletTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 30/09/2026.
//

import EnclaveKit
import Foundation
import Testing

struct WalletTests {
    let kora = Kora(url: URL(string: "http://kora.invalid")!)

    @Test func addressesComeFromTheKey() {
        let wallet = Wallet(signer: SoftwareKey.test, kora: kora)
        #expect(wallet.vaultAddress.base58 == "hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK")
    }

    /// Lamports sent to the state's address before the first action leave a
    /// System account there. Still no state: the first action must go through.
    @Test func accountOwnedByAnotherProgramIsNoState() async throws {
        let rpc = SolanaRPC(transport: stub(
            expecting: """
            {"jsonrpc":"2.0","id":1,"method":"getAccountInfo",
             "params":["EKyNGE7ecVLS8GYLf13LypzugwLbRQuRVNvNQdu9jQxF",{"commitment":"confirmed","encoding":"base64"}]}
            """,
            reply: """
            {"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":{
             "data":["","base64"],"executable":false,"lamports":1,
             "owner":"11111111111111111111111111111111",
             "rentEpoch":18446744073709551615,"space":0}}}
            """
        ))
        let wallet = Wallet(signer: SoftwareKey.test, kora: kora, rpc: rpc)
        #expect(try await wallet.state() == nil)
    }
}
