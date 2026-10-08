//
//  SolanaRPCTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Testing
@testable import EnclaveKit

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

    /// The size, then the bytes in base58; the whole data comes back in
    /// base64.
    @Test func programAccountsSendsBothFilters() async throws {
        let rpc = SolanaRPC(transport: stub(
            expecting: """
            {"jsonrpc":"2.0","id":1,"method":"getProgramAccounts",
             "params":["dG4h3aizVEW1bKjzkGsfk6zqcfa2MVn2DjavPniesSY",{"commitment":"confirmed","encoding":"base64",
              "filters":[{"dataSize":325},{"memcmp":{"offset":280,"bytes":"Ldp"}}]}]}
            """,
            reply: """
            {"jsonrpc":"2.0","id":1,"result":[{"pubkey":"hYEjxsHxt6UeiMra3eqTxzuWKTWMbC7Q4qjZLV5NpZK","account":{
             "data":["AQID","base64"],"executable":false,"lamports":2301240,
             "owner":"dG4h3aizVEW1bKjzkGsfk6zqcfa2MVn2DjavPniesSY",
             "rentEpoch":18446744073709551615,"space":3}}]}
            """
        ))
        let accounts = try await rpc.programAccounts(EnclaveKitProgram.id, dataSize: 325, offset: 280, bytes: [1, 2, 3])
        #expect(accounts.map(\.data) == [[1, 2, 3]])
    }

    /// One call per token program, SPL Token first.
    @Test func tokenAmountsCoverBothPrograms() async throws {
        let rpc = SolanaRPC(transport: stub { [address] method, params in
            let params = params as? [Any]
            #expect(method == "getTokenAccountsByOwner")
            #expect(params?.first as? String == address.base58)
            #expect(params?.last as? [String: String] == ["commitment": "confirmed", "encoding": "base64"])
            let programId = try #require((params?[1] as? [String: String])?["programId"])
            let index = try #require(SolanaRPC.tokenPrograms.map(\.base58).firstIndex(of: programId))
            let account = tokenAccountJSON(owner: address, amount: UInt64(index) * 5, program: SolanaRPC.tokenPrograms[index])
            return #"{"context":{"slot":1},"value":[\#(account)]}"#
        })
        #expect(try await rpc.tokenAmounts(owner: address) == [0, 5])
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

    /// A 429 is tried again first: see `JSONRPCTests`.
    @Test func httpErrorThrows() async {
        let rpc = SolanaRPC(transport: stub(
            expecting: #"{"jsonrpc":"2.0","id":1,"method":"getMinimumBalanceForRentExemption","params":[229]}"#,
            reply: "Service Unavailable",
            status: 503
        ))
        await #expect(throws: JSONRPCError.httpStatus(503)) {
            try await rpc.minimumBalanceForRentExemption(space: 229)
        }
    }
}
