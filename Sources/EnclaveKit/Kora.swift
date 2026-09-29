//
//  Kora.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import EnclaveKitCore
import Foundation

/// The Kora relayer: it pays the transaction fee as fee payer, and the vault
/// pays it back through `relayer_fee`.
public struct Kora: Sendable {
    private let client: JSONRPCClient

    public init(url: URL, apiKey: String? = nil, transport: @escaping HTTPTransport = { try await URLSession.shared.data(for: $0) }) {
        client = JSONRPCClient(url: url, headers: apiKey.map { ["x-api-key": $0] } ?? [:], transport: transport)
    }

    /// The fee payer Kora signs with. It is also the `relayer` account of the
    /// instruction: rent payer on first use, refund destination.
    public func payerSigner() async throws -> PublicKey {
        let reply: PayerSigner = try await client.call("getPayerSigner", noParams)
        return try PublicKey(base58: reply.signerAddress)
    }

    public func blockhash() async throws -> Blockhash {
        let reply: BlockhashReply = try await client.call("getBlockhash", noParams)
        return try Blockhash(base58: reply.blockhash)
    }

    /// Kora checks the transaction against its config, simulates it, fills
    /// the fee payer's signature slot and sends. A failed simulation comes
    /// back as `JSONRPCError.server`. Returns the transaction signature.
    public func signAndSend(_ message: Message) async throws -> String {
        let transaction = Data(message.unsignedTransaction).base64EncodedString()
        let reply: Sent = try await client.call("signAndSendTransaction", ["transaction": transaction])
        return reply.signature
    }

    private let noParams: [String] = []

    private struct PayerSigner: Decodable {
        let signerAddress: String
    }

    private struct BlockhashReply: Decodable {
        let blockhash: String
    }

    private struct Sent: Decodable {
        let signature: String
    }
}
