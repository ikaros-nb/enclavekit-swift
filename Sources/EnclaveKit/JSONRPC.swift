//
//  JSONRPC.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Foundation

/// Sends one HTTP request: `URLSession` in the app, a stub in tests.
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

public enum JSONRPCError: Error, Equatable {
    /// Status other than 200. Kora answers 401 to a missing or wrong API key,
    /// public RPC nodes 429 when rate limited.
    case httpStatus(Int)
    /// The `error` object of the reply.
    case server(code: Int, message: String)
    /// Neither `result` nor `error` in the reply.
    case missingResult
}

/// JSON-RPC 2.0 over HTTP POST, what both Solana RPC and Kora speak.
struct JSONRPCClient: Sendable {
    let url: URL
    var headers: [String: String] = [:]
    let transport: HTTPTransport

    func call<Result: Decodable>(_ method: String, _ params: some Encodable) async throws -> Result {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(Request(method: method, params: params))

        let (data, response) = try await transport(request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw JSONRPCError.httpStatus(status)
        }
        let decoder = JSONDecoder()
        // Kora answers in snake_case, Solana in camelCase: keys without an
        // underscore go through unchanged.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let reply = try decoder.decode(Reply<Result>.self, from: data)
        if let error = reply.error {
            throw JSONRPCError.server(code: error.code, message: error.message)
        }
        guard let result = reply.result else { throw JSONRPCError.missingResult }
        return result
    }

    private struct Request<Params: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id = 1
        let method: String
        let params: Params
    }

    private struct Reply<Result: Decodable>: Decodable {
        let result: Result?
        let error: ServerError?
    }

    private struct ServerError: Decodable {
        let code: Int
        let message: String
    }
}

/// `[first, second]`: Solana RPC takes positional parameters of mixed types.
struct Positional<First: Encodable, Second: Encodable>: Encodable {
    let first: First
    let second: Second

    init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(first)
        try container.encode(second)
    }
}
