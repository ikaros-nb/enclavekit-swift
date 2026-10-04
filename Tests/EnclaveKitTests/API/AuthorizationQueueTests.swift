//
//  AuthorizationQueueTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

import Testing
@testable import EnclaveKit

struct AuthorizationQueueTests {
    actor Log {
        var events: [String] = []
        func append(_ event: String) { events.append(event) }
    }

    /// Three at once, each suspended in the middle: no start before the
    /// previous end, whatever order they enter in.
    @Test func runsOneAtATime() async throws {
        let queue = AuthorizationQueue()
        let log = Log()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await queue.run {
                        await log.append("start")
                        try await Task.sleep(for: .milliseconds(20))
                        await log.append("end")
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await log.events == ["start", "end", "start", "end", "start", "end"])
    }

    @Test func aFailureFreesTheQueue() async throws {
        let queue = AuthorizationQueue()
        await #expect(throws: CancellationError.self) {
            try await queue.run { throw CancellationError() }
        }
        #expect(try await queue.run { 42 } == 42)
    }
}
