//
//  SignatureStatusTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import EnclaveKit
import Testing

struct SignatureStatusTests {
    static let request = """
        {"jsonrpc":"2.0","id":1,"method":"getSignatureStatuses",
         "params":[["5VERv8NM"],{"searchTransactionHistory":true}]}
        """

    static func rpc(value: String) -> SolanaRPC {
        SolanaRPC(transport: stub(
            expecting: request,
            reply: #"{"jsonrpc":"2.0","id":1,"result":{"context":{"slot":1},"value":[\#(value)]}}"#
        ))
    }

    @Test func unknownSignatureIsNil() async throws {
        #expect(try await Self.rpc(value: "null").signatureStatus("5VERv8NM") == nil)
    }

    @Test func confirmedTransaction() async throws {
        let status = try #require(try await Self.rpc(value: """
            {"slot":1,"confirmations":0,"err":null,"status":{"Ok":null},"confirmationStatus":"confirmed"}
            """).signatureStatus("5VERv8NM"))
        #expect(status.confirmationStatus == .confirmed)
        #expect(status.error == nil)
    }

    /// Shapes of `err`: serde writes the Rust `TransactionError` enum.
    @Test(arguments: [
        (#"{"InstructionError":[1,{"Custom":6003}]}"#, TransactionError.custom(instruction: 1, code: 6003)),
        (#"{"InstructionError":[0,"InvalidArgument"]}"#, .instruction(0, "InvalidArgument")),
        (#"{"InsufficientFundsForRent":{"account_index":2}}"#, .transaction("InsufficientFundsForRent")),
        (#""AccountInUse""#, .transaction("AccountInUse")),
    ])
    func failedTransaction(err: String, expected: TransactionError) async throws {
        let status = try #require(try await Self.rpc(value: """
            {"slot":1,"confirmations":null,"err":\(err),"status":{"Err":\(err)},"confirmationStatus":"finalized"}
            """).signatureStatus("5VERv8NM"))
        #expect(status.confirmationStatus == .finalized)
        #expect(status.error == expected)
    }
}
