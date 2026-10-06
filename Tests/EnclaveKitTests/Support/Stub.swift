//
//  Stub.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

/// A server that checks the one request it receives, then sends `reply`.
func stub(expecting body: String, headers: [String: String] = [:], reply: String, status: Int = 200) -> HTTPTransport {
    { request in
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        for (field, value) in headers {
            #expect(request.value(forHTTPHeaderField: field) == value)
        }
        let sent = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? NSObject
        let wanted = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? NSObject
        #expect(sent == wanted, "request body")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.utf8), response)
    }
}

/// What a stub's `reply` throws to answer a JSON-RPC error with `message`.
struct ServerError: Error {
    let message: String
}

/// A server for flows that make several calls: `reply` gets each method and
/// its params and returns the `result`, or `nil` for a call it does not expect.
/// The methods in `errors` answer a JSON-RPC error with that message instead.
func stub(errors: [String: String] = [:], _ reply: @escaping @Sendable (_ method: String, _ params: Any?) throws -> String?) -> HTTPTransport {
    { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let method = try #require(body?["method"] as? String)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        do {
            if let message = errors[method] { throw ServerError(message: message) }
            let result = try #require(try reply(method, body?["params"]), "unexpected call to \(method)")
            return (Data(#"{"jsonrpc":"2.0","id":1,"result":\#(result)}"#.utf8), response)
        } catch let error as ServerError {
            return (Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"\#(error.message)"}}"#.utf8), response)
        }
    }
}
