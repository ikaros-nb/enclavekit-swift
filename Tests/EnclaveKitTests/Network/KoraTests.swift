//
//  KoraTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import EnclaveKit
import Foundation
import Testing

struct KoraTests {
    let url = URL(string: "http://127.0.0.1:8080")!
    let apiKey = ["x-api-key": "secret"]

    @Test func payerSigner() async throws {
        let kora = Kora(url: url, apiKey: "secret", transport: stub(
            expecting: #"{"jsonrpc":"2.0","id":1,"method":"getPayerSigner","params":[]}"#,
            headers: apiKey,
            reply: """
            {"jsonrpc":"2.0","id":1,"result":{
             "signer_address":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8",
             "payment_address":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"}}
            """
        ))
        #expect(try await kora.payerSigner() == PublicKey(bytes: [UInt8](repeating: 0x77, count: 32)))
    }

    @Test func blockhash() async throws {
        let kora = Kora(url: url, apiKey: "secret", transport: stub(
            expecting: #"{"jsonrpc":"2.0","id":1,"method":"getBlockhash","params":[]}"#,
            headers: apiKey,
            reply: #"{"jsonrpc":"2.0","id":1,"result":{"blockhash":"AByCTxLPRZPoyK22KdMxa3xkCbcNbeNWzVeEvh6UcJs9"}}"#
        ))
        #expect(try await kora.blockhash().bytes == [UInt8](repeating: 0x88, count: 32))
    }

    /// The smallest message: payer only, no instruction. The base64 is
    /// computed outside Swift: 01, 64 zero bytes, then the message.
    @Test func signAndSendPostsTheUnsignedTransaction() async throws {
        let message = Message(
            instructions: [],
            payer: try PublicKey(bytes: [UInt8](repeating: 0x77, count: 32)),
            recentBlockhash: try Blockhash(base58: "AByCTxLPRZPoyK22KdMxa3xkCbcNbeNWzVeEvh6UcJs9")
        )
        let kora = Kora(url: url, apiKey: "secret", transport: stub(
            expecting: """
            {"jsonrpc":"2.0","id":1,"method":"signAndSendTransaction","params":{"transaction":
             "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAABd3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3eIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiAA="}}
            """,
            headers: apiKey,
            reply: #"{"jsonrpc":"2.0","id":1,"result":{"signature":"5VERv8NM","signed_transaction":"AQ==","signer_pubkey":"93MB2qRDNVLxbmmPuYpLdAqn3u2x9ZhaVZK5wELHueP8"}}"#
        ))
        #expect(try await kora.signAndSend(message) == "5VERv8NM")
    }

    @Test func wrongAPIKeyIsUnauthorized() async {
        let kora = Kora(url: url, apiKey: "wrong", transport: stub(
            expecting: #"{"jsonrpc":"2.0","id":1,"method":"getBlockhash","params":[]}"#,
            reply: "",
            status: 401
        ))
        await #expect(throws: JSONRPCError.httpStatus(401)) {
            try await kora.blockhash()
        }
    }
}
