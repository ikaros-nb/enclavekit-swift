//
//  SolanaRPCTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import EnclaveKit
import EnclaveKitCore
import Testing

struct SolanaRPCTests {
    let address = try! PublicKey(base58: "hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK")

    @Test func accountInfoDecodesTheData() async throws {
        let rpc = SolanaRPC(transport: stub(
            expecting: """
            {"jsonrpc":"2.0","id":1,"method":"getAccountInfo",
             "params":["hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK",{"commitment":"confirmed","encoding":"base64"}]}
            """,
            reply: """
            {"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":{
             "data":["AQID","base64"],"executable":false,"lamports":2484720,
             "owner":"dG4h3aizVEW1bKjzkGsfk6zqcfa2MVn2DjavPniesSY",
             "rentEpoch":18446744073709551615,"space":3}}}
            """
        ))
        let info = try #require(try await rpc.accountInfo(address))
        #expect(info.lamports == 2_484_720)
        #expect(info.owner == EnclaveKitProgram.id)
        #expect(info.data == [1, 2, 3])
    }

    @Test func missingAccountIsNil() async throws {
        let rpc = SolanaRPC(transport: stub(
            expecting: """
            {"jsonrpc":"2.0","id":1,"method":"getAccountInfo",
             "params":["hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK",{"commitment":"confirmed","encoding":"base64"}]}
            """,
            reply: #"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":null}}"#
        ))
        #expect(try await rpc.accountInfo(address) == nil)
    }

    @Test func balance() async throws {
        let rpc = SolanaRPC(transport: stub(
            expecting: """
            {"jsonrpc":"2.0","id":1,"method":"getBalance",
             "params":["hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK",{"commitment":"confirmed"}]}
            """,
            reply: #"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":15000000}}"#
        ))
        #expect(try await rpc.balance(address) == 15_000_000)
    }

    @Test func minimumBalanceForRentExemption() async throws {
        let rpc = SolanaRPC(transport: stub(
            expecting: #"{"jsonrpc":"2.0","id":1,"method":"getMinimumBalanceForRentExemption","params":[229]}"#,
            reply: #"{"jsonrpc":"2.0","id":1,"result":2484720}"#
        ))
        #expect(try await rpc.minimumBalanceForRentExemption(space: 229) == 2_484_720)
    }

    @Test func serverErrorThrows() async {
        let rpc = SolanaRPC(transport: stub(
            expecting: #"{"jsonrpc":"2.0","id":1,"method":"getMinimumBalanceForRentExemption","params":[229]}"#,
            reply: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Invalid params"}}"#
        ))
        await #expect(throws: JSONRPCError.server(code: -32602, message: "Invalid params")) {
            try await rpc.minimumBalanceForRentExemption(space: 229)
        }
    }

    @Test func httpErrorThrows() async {
        let rpc = SolanaRPC(transport: stub(
            expecting: #"{"jsonrpc":"2.0","id":1,"method":"getMinimumBalanceForRentExemption","params":[229]}"#,
            reply: "Too many requests",
            status: 429
        ))
        await #expect(throws: JSONRPCError.httpStatus(429)) {
            try await rpc.minimumBalanceForRentExemption(space: 229)
        }
    }
}
