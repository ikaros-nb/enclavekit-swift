//
//  JSONRPCTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Foundation
import Testing
@testable import EnclaveKit

struct JSONRPCTests {
    /// Rate limited twice, then served: the caller only sees the result.
    @Test func rateLimitIsTriedAgain() async throws {
        let client = client(statuses: [429, 429, 200], retryDelays: [.zero, .zero])
        let slot: Int = try await client.call("getSlot", [String]())
        #expect(slot == 42)
    }

    @Test func rateLimitGivesUpAfterTheLastDelay() async throws {
        let client = client(statuses: [429, 429, 429], retryDelays: [.zero, .zero])
        await #expect(throws: JSONRPCError.httpStatus(429)) {
            let _: Int = try await client.call("getSlot", [String]())
        }
    }

    /// Any other status fails at once.
    @Test func otherStatusIsNotTriedAgain() async throws {
        let client = client(statuses: [401], retryDelays: [.zero])
        await #expect(throws: JSONRPCError.httpStatus(401)) {
            let _: Int = try await client.call("getSlot", [String]())
        }
    }

    /// A server that answers with each status in turn, `42` when it is 200,
    /// and fails the test if called once more.
    func client(statuses: [Int], retryDelays: [Duration]) -> JSONRPCClient {
        let replies = Replies(statuses)
        return JSONRPCClient(url: URL(string: "http://rpc.invalid")!, transport: { request in
            let status = try #require(await replies.next(), "one call too many")
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"jsonrpc":"2.0","id":1,"result":42}"#.utf8), response)
        }, retryDelays: retryDelays)
    }
}

private actor Replies {
    private var statuses: [Int]

    init(_ statuses: [Int]) {
        self.statuses = statuses
    }

    func next() -> Int? {
        statuses.isEmpty ? nil : statuses.removeFirst()
    }
}
