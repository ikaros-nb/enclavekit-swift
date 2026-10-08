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

    /// SPL Token, then Token-2022: every token account belongs to one of them.
    static let tokenPrograms = [
        try! PublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
        try! PublicKey(base58: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"),
    ]

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

    /// The amount in each token account `owner` holds, under both token
    /// programs, empty ones included.
    func tokenAmounts(owner: PublicKey) async throws -> [UInt64] {
        var amounts: [UInt64] = []
        for program in Self.tokenPrograms {
            let reply: WithContext<[KeyedAccount]> = try await client.call(
                "getTokenAccountsByOwner",
                Positional(owner.base58, ["programId": program.base58], Config(encoding: "base64"))
            )
            amounts += try reply.value.map { try $0.account.tokenAmount }
        }
        return amounts
    }

    /// The accounts of `program` that are `dataSize` bytes long and hold
    /// `bytes` at `offset`. The RPC ANDs the filters of one call: each
    /// alternative is a call of its own.
    func programAccounts(_ program: PublicKey, dataSize: Int, offset: Int, bytes: [UInt8]) async throws -> [AccountInfo] {
        let filters = [Filter(dataSize: dataSize), Filter(memcmp: Memcmp(offset: offset, bytes: Base58.encode(bytes)))]
        let reply: [KeyedAccount] = try await client.call(
            "getProgramAccounts",
            Positional(program.base58, Config(encoding: "base64", filters: filters))
        )
        return reply.map(\.account)
    }

    /// `{ "pubkey": …, "account": … }`
    private struct KeyedAccount: Decodable {
        let account: AccountInfo
    }

    private struct Config: Encodable {
        var commitment = "confirmed"
        var encoding: String?
        var filters: [Filter]?
    }

    /// `{ "dataSize": … }` or `{ "memcmp": … }`: one of the two.
    private struct Filter: Encodable {
        var dataSize: Int?
        var memcmp: Memcmp?
    }

    /// `bytes` in base58, the RPC's default for `memcmp`.
    private struct Memcmp: Encodable {
        let offset: Int
        let bytes: String
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

    /// A token account's amount: Token-2022 keeps SPL Token's layout, mint
    /// and owner first, then the amount, then its own extensions.
    var tokenAmount: UInt64 {
        get throws(AccountError) {
            guard data.count >= 72 else { throw .truncated }
            return data[64..<72].reversed().reduce(0) { $0 << 8 | UInt64($1) }
        }
    }
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
