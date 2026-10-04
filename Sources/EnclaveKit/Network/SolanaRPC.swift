//
//  SolanaRPC.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Foundation

/// The Solana RPC methods the SDK reads with, all at `confirmed`.
struct SolanaRPC: Sendable {
    static let devnet = URL(string: "https://api.devnet.solana.com")!

    private let client: JSONRPCClient

    init(url: URL = devnet, transport: @escaping HTTPTransport = { try await URLSession.shared.data(for: $0) }) {
        client = JSONRPCClient(url: url, transport: transport)
    }

    /// `nil` when the account does not exist, like the wallet state before
    /// its first action.
    func accountInfo(_ address: PublicKey) async throws -> AccountInfo? {
        let reply: WithContext<AccountInfo?> = try await client.call(
            "getAccountInfo",
            Positional(address.base58, Config(encoding: "base64"))
        )
        return reply.value
    }

    func balance(_ address: PublicKey) async throws -> UInt64 {
        let reply: WithContext<UInt64> = try await client.call("getBalance", Positional(address.base58, Config()))
        return reply.value
    }

    /// What the relayer advances for the wallet state on its first action.
    func minimumBalanceForRentExemption(space: Int) async throws -> UInt64 {
        try await client.call("getMinimumBalanceForRentExemption", [space])
    }
    
    /// `nil` while the cluster has not seen the transaction.
    func signatureStatus(_ signature: String) async throws -> SignatureStatus? {
        let reply: WithContext<[SignatureStatus?]> = try await client.call(
            "getSignatureStatuses",
            Positional([signature], ["searchTransactionHistory": true])
        )
        return reply.value.first ?? nil
    }

    private struct Config: Encodable {
        var commitment = "confirmed"
        var encoding: String?
    }

    /// `{ "context": { "slot": … }, "value": … }`
    private struct WithContext<Value: Decodable>: Decodable {
        let value: Value
    }
}

struct AccountInfo: Equatable, Sendable {
    let lamports: UInt64
    let owner: PublicKey
    let data: [UInt8]
}

extension AccountInfo: Decodable {
    private enum CodingKeys: CodingKey {
        case lamports, owner, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lamports = try container.decode(UInt64.self, forKey: .lamports)
        owner = try PublicKey(base58: container.decode(String.self, forKey: .owner))
        // `["<base64>", "base64"]`: the data, then the encoding asked for.
        let encoded = try container.decode([String].self, forKey: .data)
        guard let base64 = encoded.first, let bytes = Data(base64Encoded: base64) else {
            throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "expected [base64, \"base64\"]")
        }
        data = Array(bytes)
    }
}
