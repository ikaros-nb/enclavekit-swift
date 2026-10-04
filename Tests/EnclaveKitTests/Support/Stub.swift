//
//  Stub.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 29/09/2026.
//

import EnclaveKit
import Foundation
import Testing

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
