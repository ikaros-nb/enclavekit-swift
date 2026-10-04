//
//  AuthorizationQueue.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 05/10/2026.
//

/// One authorization at a time. Two in parallel would sign the same nonce
/// and the second would fail in Kora's simulation; in line, the next one
/// reads the nonce the previous one left.
actor AuthorizationQueue {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Runs `operation` once every earlier one has ended, failed ones
    /// included. `nonisolated`: the operation stays on the caller's actor,
    /// only the turn-taking happens here.
    nonisolated func run<T>(_ operation: () async throws -> T) async throws -> T {
        await enter()
        do {
            let result = try await operation()
            await leave()
            return result
        } catch {
            await leave()
            throw error
        }
    }

    private func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the turn to the first in line, if any: `busy` stays set.
    private func leave() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
