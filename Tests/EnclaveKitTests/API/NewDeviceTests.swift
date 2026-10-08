//
//  NewDeviceTests.swift
//  EnclaveKit
//
//  Created by Nicolas Bouème on 06/10/2026.
//

import Foundation
import os
import Testing
@testable import EnclaveKit

/// `SoftwareKey.test`'s wallet, seen from the device that replaces it.
struct NewDeviceTests {
    /// Kora's answer while the cluster's clock is short of `opensAt`.
    static let tooEarly = "Invalid transaction: Transaction simulation failed: Error processing Instruction 0: custom program error: 0x1780"
    static let device = SoftwareKey()

    @Test func guardianProposedThisDevice() async throws {
        let pending = rotation(to: Self.device.publicKey, secondsAgo: 10)
        #expect(try await wallet(holding: pending).status() == .recovering(Recovery(pending, cluster: .devnet)))
    }

    /// No guardian proposed this device yet, or the owner cancelled; a
    /// proposal for another device; this device's, lapsed.
    @Test(arguments: [
        nil,
        rotation(to: SoftwareKey().publicKey, secondsAgo: 10),
        rotation(to: NewDeviceTests.device.publicKey, secondsAgo: 60 + 7 * 24 * 60 * 60 + 1),
    ])
    func nothingToConfirm(pending: SmartWallet.PendingRotation?) async throws {
        let wallet = wallet(holding: pending)
        #expect(try await wallet.status() == .keyReplaced)
        await #expect(throws: EnclaveKitError.noRecovery) { try await wallet.confirmRecovery() }
    }

    /// The owner still has 50 seconds to cancel: nothing reaches Kora.
    @Test func confirmWaitsForTheDelay() async throws {
        let pending = rotation(to: Self.device.publicKey, secondsAgo: 10)
        let silent = Kora(url: URL(string: "http://kora.invalid")!, transport: stub { _, _ in nil })
        await #expect(throws: EnclaveKitError.recoveryNotOpen(opensAt: Recovery(pending, cluster: .devnet).opensAt)) {
            try await wallet(holding: pending, kora: silent).confirmRecovery()
        }
    }

    @Test func confirmOnceOpen() async throws {
        let kora = ActionRequestTests.relayer { params in
            #expect(ActionRequestTests.transaction(params).firstRange(of: EnclaveKitProgram.discriminator(of: "confirm_rotation")) != nil)
        }
        let pending = rotation(to: Self.device.publicKey, secondsAgo: 61)
        #expect(try await wallet(holding: pending, kora: kora).confirmRecovery() == ActionRequestTests.sent)
    }

    /// Open by this device's clock, not yet by the cluster's: Kora's
    /// simulation says too early once, then lets it through.
    @Test func clusterClockCatchesUp() async throws {
        let sends = OSAllocatedUnfairLock(initialState: 0)
        let kora = ActionRequestTests.relayer { _ in
            if sends.withLock({ $0 += 1; return $0 }) == 1 { throw ServerError(message: Self.tooEarly) }
        }
        let pending = rotation(to: Self.device.publicKey, secondsAgo: 61)
        #expect(try await wallet(holding: pending, kora: kora).confirmRecovery(retryingEvery: .zero) == ActionRequestTests.sent)
        #expect(sends.withLock { $0 } == 2)
    }

    @Test func clusterClockTooFarBehind() async throws {
        let kora = ActionRequestTests.relayer(errors: ["signAndSendTransaction": Self.tooEarly])
        let pending = rotation(to: Self.device.publicKey, secondsAgo: 61)
        await #expect(throws: EnclaveKitError.recoveryNotOpen(opensAt: Recovery(pending, cluster: .devnet).opensAt)) {
            try await wallet(holding: pending, kora: kora).confirmRecovery(retryingEvery: .zero, attempts: 3)
        }
    }

    /// Proposed 59 seconds ago, by whole seconds: open within a second. The
    /// confirmation waits for `opensAt`, then goes out on its own.
    @Test func confirmWhenOpenWaitsForTheDelay() async throws {
        let pending = rotation(to: Self.device.publicKey, secondsAgo: 59)
        let opensAt = Recovery(pending, cluster: .devnet).opensAt
        let kora = ActionRequestTests.relayer { params in
            #expect(Date.now >= opensAt)
            #expect(ActionRequestTests.transaction(params).firstRange(of: EnclaveKitProgram.discriminator(of: "confirm_rotation")) != nil)
        }
        #expect(try await wallet(holding: pending, kora: kora).confirmRecoveryWhenOpen() == ActionRequestTests.sent)
    }

    /// The owner cancels while the device waits: nothing reaches Kora.
    @Test func confirmWhenOpenStopsAtACancel() async throws {
        let pending = rotation(to: Self.device.publicKey, secondsAgo: 59)
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let rpc = SolanaRPC(transport: stub { method, _ in
            guard method == "getAccountInfo" else { return nil }
            let cancelled = reads.withLock { $0 += 1; return $0 } > 1
            return #"{"context":{"slot":1},"value":\#(accountJSON(data: stateData(rotation: cancelled ? nil : pending)))}"#
        })
        let silent = Kora(url: URL(string: "http://kora.invalid")!, transport: stub { _, _ in nil })
        let wallet = Wallet(signer: Self.device, walletId: walletId(of: SoftwareKey.test.publicKey), kora: silent, rpc: rpc)
        await #expect(throws: EnclaveKitError.noRecovery) { try await wallet.confirmRecoveryWhenOpen() }
    }

    /// `SoftwareKey.test`'s wallet, seen from `device`, with `pending` in
    /// its state.
    func wallet(holding pending: SmartWallet.PendingRotation?, kora: Kora? = nil) -> Wallet {
        ActionRequestTests().wallet(state: accountJSON(data: stateData(rotation: pending)), kora: kora, signer: Self.device)
    }
}
